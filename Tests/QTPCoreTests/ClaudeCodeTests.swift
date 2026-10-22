import Foundation
import XCTest
@testable import QTPCore

final class ClaudeCodeTests: XCTestCase {
    private let result = #"{"type":"result","subtype":"success","is_error":false,"result":"hello"}"#
    private func delta(_ text: String, parent: Any = NSNull()) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: [
            "type": "stream_event", "parent_tool_use_id": parent,
            "event": ["type": "content_block_delta", "delta": ["type": "text_delta", "text": text]]
        ])
        data.append(10)
        return data
    }

    func testLegacyProfileAndClaudeRoundTrip() throws {
        let json = #"{"id":"550e8400-e29b-41d4-a716-446655440000","name":"Codex","type":"codex-oauth","baseURL":"","model":"test"}"#
        let legacy = try JSONDecoder().decode(ProviderProfile.self, from: Data(json.utf8))
        XCTAssertNil(legacy.executablePath)
        XCTAssertTrue(legacy.type.usesOAuth)
        let profile = ProviderProfile(name: "Claude", type: .claudeCode, executablePath: "/custom/claude")
        XCTAssertEqual(profile.model, "sonnet")
        XCTAssertFalse(profile.type.usesOAuth)
        XCTAssertEqual(try JSONDecoder().decode(ProviderProfile.self, from: JSONEncoder().encode(profile)), profile)
        XCTAssertFalse(ProviderType.openAICompatible.usesOAuth)
        XCTAssertTrue(ProviderType.xaiOAuth.usesOAuth)
    }

    func testSplitUnicodeAndNoDuplicateResult() throws {
        var parser = ClaudeCodeStreamParser()
        let data = try delta("日本語") + Data((result + "\n").utf8)
        var events: [LLMStreamEvent] = []
        for byte in data { events += try parser.feed(Data([byte])) }
        events += try parser.finish()
        XCTAssertEqual(events, [.delta("日本語")])
        XCTAssertTrue(parser.resultReceived)
        XCTAssertNil(parser.failure)
    }

    func testResultFallbackAndIgnoredEvents() throws {
        var parser = ClaudeCodeStreamParser()
        var data = Data(#"{"type":"system","subtype":"init"}"#.utf8)
        data.append(10)
        data += try delta("subagent", parent: "tool-1")
        data += Data(#"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"secret"}}}"#.utf8)
        data.append(10)
        data += Data(result.utf8)
        XCTAssertEqual(try parser.feed(data), [])
        XCTAssertEqual(try parser.finish(), [.delta("hello")])
    }

    func testErrorsAndMalformedOutput() throws {
        var parser = ClaudeCodeStreamParser()
        XCTAssertEqual(try parser.feed(Data(#"{"type":"result","subtype":"error_during_execution","is_error":true,"errors":["Not signed in"]}"#.utf8)), [])
        _ = try parser.finish()
        XCTAssertEqual(parser.failure, "Not signed in")
        var malformed = ClaudeCodeStreamParser()
        XCTAssertThrowsError(try malformed.feed(Data("not json\n".utf8)))
    }

    private func fakeCLI(_ script: String) throws -> (URL, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("claude")
        try Data(("#!/bin/sh\n" + script).utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return (directory, executable)
    }

    private func collect(_ stream: AsyncThrowingStream<LLMStreamEvent, Error>) async throws -> [LLMStreamEvent] {
        var events: [LLMStreamEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }

    func testArgumentsStdinStreamingAndCleanup() async throws {
        let (directory, executable) = try fakeCLI("""
        printf '%s\\n' "$PWD" > "$(dirname "$0")/cwd"
        printf '%s\\n' "$@" > "$(dirname "$0")/args"
        cat > "$(dirname "$0")/input"
        printf '%s\\n' '\(result)'
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let prompt = "日本語\n$(touch do-not-run) `exit`"
        let events = try await collect(ClaudeCodeRunner.start(prompt: prompt, model: "sonnet", executablePath: executable.path))
        XCTAssertEqual(events, [.delta("hello"), .done])
        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent("input"), encoding: .utf8), prompt)
        let args = try String(contentsOf: directory.appendingPathComponent("args"), encoding: .utf8)
        XCTAssertEqual(args, "-p\n--model\nsonnet\n--output-format\nstream-json\n--verbose\n--include-partial-messages\n--no-session-persistence\n--safe-mode\n--tools\n\n--disallowedTools\nmcp__*\n")
        let cwd = try String(contentsOf: directory.appendingPathComponent("cwd"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        // Cleanup happens as the producer returns after completing the stream.
        for _ in 0..<100 where FileManager.default.fileExists(atPath: cwd) {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: cwd))
    }

    func testNonzeroExitDrainsStderr() async throws {
        let (directory, executable) = try fakeCLI("""
        cat >/dev/null
        i=0
        while [ "$i" -lt 3000 ]; do printf 'diagnostic diagnostic diagnostic diagnostic\\n' >&2; i=$((i+1)); done
        printf 'authentication failed\\n' >&2
        exit 1
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            _ = try await collect(ClaudeCodeRunner.start(prompt: "test", model: "sonnet", executablePath: executable.path))
            XCTFail("Expected failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("status 1"))
            XCTAssertTrue(error.localizedDescription.contains("authentication failed"))
        }
    }

    func testMissingResultAndInvalidJSONFail() async throws {
        for output in ["", "not json"] {
            let (directory, executable) = try fakeCLI("cat >/dev/null\nprintf '%s\\n' '\(output)'\n")
            defer { try? FileManager.default.removeItem(at: directory) }
            do {
                _ = try await collect(ClaudeCodeRunner.start(prompt: "", model: "sonnet", executablePath: executable.path))
                XCTFail("Expected failure")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains(output.isEmpty ? "without a result" : "Invalid JSON"))
            }
        }
    }

    func testEmitsDeltasBeforeProcessExit() async throws {
        let line = String(decoding: try delta("streaming"), as: UTF8.self).trimmingCharacters(in: .newlines)
        let (directory, executable) = try fakeCLI("""
        cat >/dev/null
        printf '%s\\n' '\(line)'
        while [ ! -f "$(dirname "$0")/release" ]; do sleep 0.01; done
        printf '%s\\n' '\(result)'
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        var events: [LLMStreamEvent] = []
        for try await event in try ClaudeCodeRunner.start(prompt: "", model: "sonnet", executablePath: executable.path, timeout: 5) {
            events.append(event)
            if case .delta = event { try Data().write(to: directory.appendingPathComponent("release")) }
        }
        XCTAssertEqual(events, [.delta("streaming"), .done])
    }

    func testSuccessfulResultStillRequiresZeroExit() async throws {
        let (directory, executable) = try fakeCLI("cat >/dev/null\nprintf '%s\\n' '\(result)'\nexit 2\n")
        defer { try? FileManager.default.removeItem(at: directory) }
        var events: [LLMStreamEvent] = []
        do {
            for try await event in try ClaudeCodeRunner.start(prompt: "", model: "sonnet", executablePath: executable.path) { events.append(event) }
            XCTFail("Expected failure")
        } catch { XCTAssertTrue(error.localizedDescription.contains("status 2")) }
        XCTAssertFalse(events.contains(.done))
    }

    func testEarlyExitWithLargePromptDoesNotSignalParent() async throws {
        let (directory, executable) = try fakeCLI("exit 1\n")
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            _ = try await collect(ClaudeCodeRunner.start(prompt: String(repeating: "x", count: 1024 * 1024),
                                                        model: "sonnet", executablePath: executable.path))
            XCTFail("Expected failure")
        } catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
    }

    func testTimeoutAndCancellationReapProcess() async throws {
        for cancel in [false, true] {
            let (directory, executable) = try fakeCLI("""
            printf '%s\\n' "$$" > "$(dirname "$0")/pid"
            cat >/dev/null
            trap '' TERM
            while :; do :; done
            """)
            defer { try? FileManager.default.removeItem(at: directory) }
            let stream = try ClaudeCodeRunner.start(prompt: "", model: "sonnet", executablePath: executable.path, timeout: cancel ? 10 : 1)
            let task = Task { try await self.collect(stream) }
            let pidURL = directory.appendingPathComponent("pid")
            for _ in 0..<100 where !FileManager.default.fileExists(atPath: pidURL.path) {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            let pid = try XCTUnwrap(Int32(String(contentsOf: pidURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
            if cancel { task.cancel() }
            do {
                _ = try await task.value
                if !cancel { XCTFail("Expected timeout") }
            } catch {
                if !cancel { XCTAssertTrue(error.localizedDescription.contains("timed out")) }
            }
            for _ in 0..<400 where kill(pid, 0) == 0 {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            XCTAssertEqual(kill(pid, 0), -1, "Child should have been reaped")
        }
    }

    func testDiscoveryAndInstallationCheck() async throws {
        let (directory, executable) = try fakeCLI("printf 'Claude Code test-version\\n'\n")
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertEqual(try ClaudeCodeRunner.resolveExecutable(nil, environment: ["PATH": directory.path]), executable)
        XCTAssertThrowsError(try ClaudeCodeRunner.resolveExecutable(directory.path))
        XCTAssertThrowsError(try ClaudeCodeRunner.resolveExecutable("/nonexistent/claude"))
        let version = try await ClaudeCodeRunner.checkInstallation(executablePath: executable.path)
        XCTAssertEqual(version, "Claude Code test-version")
    }
}
