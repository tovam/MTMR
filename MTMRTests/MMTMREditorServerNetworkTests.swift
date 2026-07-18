import Foundation
import XCTest

#if SWIFT_PACKAGE
@testable import MMTMRServerBuildCheck
#endif

final class MMTMREditorServerNetworkTests: XCTestCase {
    func testLiveWebSocketReconnectPortConflictAndGracefulLifecycle() async throws {
        let port = Int.random(in: 49_152...64_000)
        let recorder = LiveServerStateRecorder()
        let configuration = MMTMREditorServerConfiguration(
            port: port,
            editorRootURL: nil,
            stateHandler: recorder.append
        )
        let server = MMTMREditorServer(configuration: configuration, provider: LiveServerProvider())

        // Exercise an immediate start/stop transition, then start the same
        // instance from several callers. Exactly one lifecycle may be installed.
        server.start()
        await server.stop()
        recorder.reset()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 { group.addTask { server.start() } }
        }

        guard await Self.waitUntil({ recorder.isRunning }) else {
            await server.stop()
            return XCTFail("The editor server did not become ready")
        }
        XCTAssertEqual(recorder.startingCount, 1)

        do {
            let cookie = try await Self.sessionCookie(configuration: configuration)
            let firstSocket = Self.webSocket(cookie: cookie, configuration: configuration)
            firstSocket.resume()
            let initial = try await Self.receiveEvent(from: firstSocket)
            XCTAssertEqual(initial.type, .configChanged)

            let broadcast = ServerEvent(
                type: .runtimeSnapshot,
                payload: .object(["items": .array([])])
            )
            await server.publish(broadcast)
            let delivered = try await Self.receiveEvent(from: firstSocket)
            XCTAssertEqual(delivered.type, .runtimeSnapshot)
            firstSocket.cancel(with: .goingAway, reason: nil)

            let reconnectedSocket = Self.webSocket(cookie: cookie, configuration: configuration)
            reconnectedSocket.resume()
            let reconnectedInitial = try await Self.receiveEvent(from: reconnectedSocket)
            XCTAssertEqual(reconnectedInitial.type, .configChanged)
            reconnectedSocket.cancel(with: .goingAway, reason: nil)

            let occupiedRecorder = LiveServerStateRecorder()
            let occupied = MMTMREditorServer(
                configuration: MMTMREditorServerConfiguration(
                    port: port,
                    editorRootURL: nil,
                    stateHandler: occupiedRecorder.append
                ),
                provider: LiveServerProvider()
            )
            occupied.start()
            let portConflictWasReported = await Self.waitUntil({ occupiedRecorder.hasFailed })
            XCTAssertTrue(portConflictWasReported)
            await occupied.stop()
        } catch {
            await server.stop()
            throw error
        }

        async let firstStop: Void = server.stop()
        async let secondStop: Void = server.stop()
        _ = await (firstStop, secondStop)
        XCTAssertTrue(recorder.hasStopped)
    }

    private static func sessionCookie(configuration: MMTMREditorServerConfiguration) async throws -> String {
        let session = URLSession(configuration: .ephemeral)
        let (_, response) = try await session.data(
            from: configuration.serverURL.appendingPathComponent("api/v1/session")
        )
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)
        let raw = try XCTUnwrap(http.value(forHTTPHeaderField: "Set-Cookie"))
        return String(raw.split(separator: ";", maxSplits: 1)[0])
    }

    private static func webSocket(
        cookie: String,
        configuration: MMTMREditorServerConfiguration
    ) -> URLSessionWebSocketTask {
        var components = URLComponents(url: configuration.serverURL, resolvingAgainstBaseURL: false)!
        components.scheme = "ws"
        components.path = "/api/v1/events"
        var request = URLRequest(url: components.url!)
        request.setValue(configuration.expectedOrigin, forHTTPHeaderField: "Origin")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        return URLSession.shared.webSocketTask(with: request)
    }

    private static func receiveEvent(from task: URLSessionWebSocketTask) async throws -> ServerEvent {
        let data: Data
        switch try await task.receive() {
        case let .string(text):
            data = Data(text.utf8)
        case let .data(value):
            data = value
        @unknown default:
            throw LiveServerTestError.unknownWebSocketMessage
        }
        return try JSONDecoder().decode(ServerEvent.self, from: data)
    }

    private static func waitUntil(
        _ predicate: @escaping @Sendable () -> Bool,
        attempts: Int = 500
    ) async -> Bool {
        for _ in 0..<attempts {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}

private enum LiveServerTestError: Error {
    case unknownWebSocketMessage
}

private final class LiveServerStateRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var states: [MMTMREditorServerState] = []

    func append(_ state: MMTMREditorServerState) {
        lock.withLock { states.append(state) }
    }

    func reset() {
        lock.withLock { states.removeAll() }
    }

    var startingCount: Int {
        lock.withLock { states.filter { $0 == .starting }.count }
    }

    var isRunning: Bool {
        lock.withLock { states.contains { if case .running = $0 { true } else { false } } }
    }

    var hasFailed: Bool {
        lock.withLock { states.contains { if case .failed = $0 { true } else { false } } }
    }

    var hasStopped: Bool {
        lock.withLock { states.contains(.stopped) }
    }
}

private actor LiveServerProvider: ServerConfigurationProviding {
    func configurationSnapshot() -> ServerConfigurationSnapshot {
        .init(
            source: #"{"formatVersion":1,"items":[]}"#,
            document: .object(["formatVersion": .number(1), "items": .array([])]),
            revision: 1,
            diagnostics: [],
            valid: true,
            configPath: "build-checks/test-home/.mtmr.json"
        )
    }

    func configurationSchema() -> ServerJSONValue { .object([:]) }

    func validateConfiguration(source _: String) -> ServerValidationResult {
        .init(valid: true, document: .object([:]), diagnostics: [])
    }

    func replaceConfiguration(source _: String, expectedRevision _: Int) -> ServerConfigurationWriteResult {
        .accepted(configurationSnapshot())
    }
}
