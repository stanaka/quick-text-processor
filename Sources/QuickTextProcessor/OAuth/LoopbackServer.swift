import Foundation
import Network
import QTPCore

/// Tiny one-shot HTTP server on 127.0.0.1 that catches the browser's OAuth
/// redirect (GET <path>?code=...&state=...), verifies the state, shows a
/// success page, and hands the authorization code back to the flow.
///
/// Only the request line is parsed (via QTPCore.LoopbackRequestParser);
/// stray requests like /favicon.ico get a 404 and the server keeps waiting.
final class LoopbackServer: @unchecked Sendable {

    let port: UInt16

    private let listener: NWListener
    private let expectedPath: String
    private let expectedState: String
    private let successHTML: String
    private let queue = DispatchQueue(label: "com.stanaka.QuickTextProcessor.loopback")
    private var continuation: CheckedContinuation<String, Error>?
    private var connections: [NWConnection] = []
    private var readyResumed = false

    /// Binds the port and waits until the listener is actually ready, so a
    /// port conflict throws here instead of hanging the flow.
    static func start(port: UInt16,
                      path: String,
                      expectedState: String,
                      successHTML: String) async throws -> LoopbackServer {
        let server = try LoopbackServer(port: port,
                                        path: path,
                                        expectedState: expectedState,
                                        successHTML: successHTML)
        try await server.waitUntilReady()
        return server
    }

    private init(port: UInt16,
                 path: String,
                 expectedState: String,
                 successHTML: String) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw AuthFlowError.portUnavailable(port, "Invalid port")
        }
        self.port = port
        self.expectedPath = path
        self.expectedState = expectedState
        self.successHTML = successHTML

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host("127.0.0.1"),
                                                               port: nwPort)
        self.listener = try NWListener(using: parameters)
    }

    private func waitUntilReady() async throws {
        try await withCheckedThrowingContinuation { (ready: CheckedContinuation<Void, Error>) in
            queue.async {
                self.listener.stateUpdateHandler = { [weak self] state in
                    guard let self, !self.readyResumed else { return }
                    switch state {
                    case .ready:
                        self.readyResumed = true
                        ready.resume()
                    case .failed(let error):
                        self.readyResumed = true
                        ready.resume(throwing: error)
                    case .cancelled:
                        self.readyResumed = true
                        ready.resume(throwing: CancellationError())
                    default:
                        break
                    }
                }
                self.listener.newConnectionHandler = { [weak self] connection in
                    self?.accept(connection)
                }
                self.listener.start(queue: self.queue)
            }
        }
    }

    /// Waits for the redirect carrying the authorization code.
    func waitForCode(timeout: TimeInterval = 300) async throws -> String {
        try await withCheckedThrowingContinuation { (code: CheckedContinuation<String, Error>) in
            queue.async {
                self.continuation = code
                self.queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                    self?.finish(.failure(AuthFlowError.timedOut))
                }
            }
        }
    }

    func stop() {
        queue.async {
            self.finish(.failure(CancellationError()))
            self.listener.cancel()
            for connection in self.connections {
                connection.cancel()
            }
            self.connections.removeAll()
        }
    }

    // MARK: - Connections (all on `queue`)

    private func accept(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data {
                buffer.append(data)
            }
            let head = String(decoding: buffer, as: UTF8.self)
            if head.contains("\r\n\r\n") || head.contains("\n\n") || isComplete {
                self.handleRequest(head: head, connection: connection)
            } else if error != nil || buffer.count > 16_384 {
                connection.cancel()
            } else {
                self.receive(connection, buffer: buffer)
            }
        }
    }

    private func handleRequest(head: String, connection: NWConnection) {
        guard let callback = LoopbackRequestParser.parse(requestHead: head) else {
            respond(connection, status: "400 Bad Request", body: "Bad request")
            return
        }
        guard callback.path == expectedPath else {
            // favicon.ico and friends — answer and keep waiting.
            respond(connection, status: "404 Not Found", body: "Not found")
            return
        }
        if let errorCode = callback.query["error"] {
            let description = callback.query["error_description"] ?? errorCode
            respond(connection, status: "200 OK",
                    body: "<html><body><p>Sign-in failed: \(description)</p></body></html>")
            finish(.failure(AuthFlowError.authorizationFailed(description)))
            return
        }
        guard callback.query["state"] == expectedState,
              let code = callback.query["code"], !code.isEmpty else {
            respond(connection, status: "400 Bad Request", body: "State mismatch")
            finish(.failure(AuthFlowError.stateMismatch))
            return
        }
        respond(connection, status: "200 OK", body: successHTML)
        finish(.success(code))
    }

    private func respond(_ connection: NWConnection, status: String, body: String) {
        let payload = Data(body.utf8)
        let head = "HTTP/1.1 \(status)\r\n"
            + "Content-Type: text/html; charset=utf-8\r\n"
            + "Content-Length: \(payload.count)\r\n"
            + "Connection: close\r\n\r\n"
        var response = Data(head.utf8)
        response.append(payload)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func finish(_ result: Result<String, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        switch result {
        case .success(let code):
            continuation.resume(returning: code)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
