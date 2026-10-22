import Foundation
import Darwin

/// Owns subprocess lifetime independently of the UI and never invokes a shell.
public enum ClaudeCodeRunner {
    public static func resolveExecutable(_ path: String?, environment: [String: String] = ProcessInfo.processInfo.environment,
                                         home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> URL {
        let explicit = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let candidates: [String]
        if !explicit.isEmpty {
            candidates = [(explicit as NSString).expandingTildeInPath]
        } else {
            let directories = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
                + [home.appendingPathComponent(".local/bin").path, "/opt/homebrew/bin", "/usr/local/bin"]
            candidates = directories.filter { $0.hasPrefix("/") }.map { $0 + "/claude" }
        }
        for candidate in candidates where candidate.hasPrefix("/") {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory),
               !isDirectory.boolValue, FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        throw LLMError.invalidConfiguration("Claude Code executable not found. Install Claude Code or set its absolute path in Settings → Providers.")
    }

    public static func start(prompt: String, model: String, executablePath: String? = nil,
                             timeout: TimeInterval = 180) throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.invalidConfiguration("Choose a Claude Code model in Settings → Providers.")
        }
        return try launch(arguments: ["-p", "--model", model, "--output-format", "stream-json",
                                      "--verbose", "--include-partial-messages", "--no-session-persistence",
                                      "--safe-mode", "--tools", "", "--disallowedTools", "mcp__*"],
                          input: prompt, executablePath: executablePath, timeout: timeout, plainText: false)
    }

    public static func checkInstallation(executablePath: String?) async throws -> String {
        try Task.checkCancellation()
        let stream = try launch(arguments: ["--version"], input: "", executablePath: executablePath,
                                timeout: 10, plainText: true)
        var version = ""
        for try await event in stream {
            if case .delta(let text) = event { version += text }
        }
        return version.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func launch(arguments: [String], input: String, executablePath: String?,
                               timeout: TimeInterval, plainText: Bool) throws -> AsyncThrowingStream<LLMStreamEvent, Error> {
        let executable = try resolveExecutable(executablePath)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("qtp-claude-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        // Print mode must retain the CLI's normal subscription credential lookup.
        environment.removeValue(forKey: "CLAUDE_CODE_SIMPLE")
        environment.removeValue(forKey: "CLAUDECODE")
        environment["PATH"] = executable.deletingLastPathComponent().path + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
        process.environment = environment
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        // A child exiting before reading stdin must not deliver SIGPIPE to the app.
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        do { try process.run() } catch {
            try? FileManager.default.removeItem(at: directory)
            throw LLMError.invalidConfiguration("Could not launch Claude Code: \(error.localizedDescription)")
        }
        let lifetime = ProcessLifetime(process)
        return AsyncThrowingStream { continuation in
            let timer = DispatchWorkItem { lifetime.stop(reason: "Claude Code timed out after \(Int(timeout)) seconds.") }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
            continuation.onTermination = { _ in lifetime.stop(reason: nil) }
            DispatchQueue.global().async {
                let group = DispatchGroup()
                let diagnostics = DiagnosticTail()
                group.enter()
                DispatchQueue.global().async {
                    while true {
                        let data = stderr.fileHandleForReading.availableData
                        if data.isEmpty { break }
                        diagnostics.append(data)
                    }
                    try? stderr.fileHandleForReading.close()
                    group.leave()
                }
                group.enter()
                DispatchQueue.global().async {
                    do { try stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8)) } catch {
                        lifetime.stop(reason: "Could not send the prompt to Claude Code: \(error.localizedDescription)")
                    }
                    try? stdin.fileHandleForWriting.close()
                    group.leave()
                }
                var parser = ClaudeCodeStreamParser()
                var decodingError: Error?
                while true {
                    let data = stdout.fileHandleForReading.availableData
                    if data.isEmpty { break }
                    do {
                        if plainText {
                            diagnostics.appendOutput(data)
                        } else {
                            for event in try parser.feed(data) { continuation.yield(event) }
                        }
                    } catch {
                        decodingError = error
                        lifetime.stop(reason: error.localizedDescription)
                        break
                    }
                }
                try? stdout.fileHandleForReading.close()
                process.waitUntilExit()
                group.wait()
                timer.cancel()
                lifetime.complete()
                defer { try? FileManager.default.removeItem(at: directory) }
                do {
                    if let reason = lifetime.reason { throw LLMError.invalidConfiguration(reason) }
                    if let decodingError { throw decodingError }
                    if !plainText {
                        for event in try parser.finish() { continuation.yield(event) }
                    }
                    if let failure = parser.failure { throw LLMError.invalidConfiguration(failure) }
                    guard process.terminationStatus == 0 else {
                        throw LLMError.invalidConfiguration("Claude Code exited with status \(process.terminationStatus). \(diagnostics.text) Sign in using Claude Code in Terminal if needed; update it if an option is unsupported.")
                    }
                    if plainText {
                        continuation.yield(.delta(diagnostics.outputText))
                    } else if !parser.resultReceived {
                        throw LLMError.invalidConfiguration("Claude Code exited without a result. \(diagnostics.text)")
                    }
                    continuation.yield(.done)
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
        }
    }
}

private final class ProcessLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private var finished = false
    private var stopped = false
    private var failure: String?
    init(_ process: Process) { self.process = process }
    var reason: String? { lock.lock(); defer { lock.unlock() }; return failure }
    func complete() { lock.lock(); finished = true; lock.unlock() }
    func stop(reason: String?) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished, !stopped else { return }
        stopped = true
        failure = reason
        if process.isRunning { process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [self] in
            lock.lock()
            defer { lock.unlock() }
            if !finished, process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
}

private final class DiagnosticTail: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var output = Data()
    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
        if data.count > 16 * 1024 { data.removeFirst(data.count - 16 * 1024) }
    }
    func appendOutput(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        output.append(chunk)
        if output.count > 16 * 1024 { output.removeFirst(output.count - 16 * 1024) }
    }
    var text: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
    var outputText: String { lock.lock(); defer { lock.unlock() }; return String(decoding: output, as: UTF8.self) }
}
