import Foundation
import Hummingbird
import HummingbirdTesting
import XCTest

#if SWIFT_PACKAGE
@testable import MMTMRServerBuildCheck
#endif

final class MMTMREditorServerTests: XCTestCase {
    func testWebSocketLimiterBoundsConnectionsAndMessages() async {
        let limiter = EditorWebSocketLimiter(connectionLimit: 1, messageLimit: 2, window: 60)

        let firstConnection = await limiter.acquireConnection()
        let blockedConnection = await limiter.acquireConnection()
        XCTAssertTrue(firstConnection)
        XCTAssertFalse(blockedConnection)
        await limiter.releaseConnection()
        let replacementConnection = await limiter.acquireConnection()
        XCTAssertTrue(replacementConnection)

        let firstMessage = await limiter.allowMessage(now: 100)
        let secondMessage = await limiter.allowMessage(now: 101)
        let blockedMessage = await limiter.allowMessage(now: 102)
        let messageAfterWindow = await limiter.allowMessage(now: 161)
        XCTAssertTrue(firstMessage)
        XCTAssertTrue(secondMessage)
        XCTAssertFalse(blockedMessage)
        XCTAssertTrue(messageAfterWindow)
        await limiter.releaseConnection()
    }

    func testEventHubReplaysRuntimeAndContextWithoutReplayingAnAction() async {
        let hub = EditorServerEventHub()
        let runtime = ServerEvent(
            type: .runtimeSnapshot,
            payload: .object(["items": .array([])]),
            timestamp: "2026-01-01T00:00:00Z"
        )
        let context = ServerEvent(
            type: .simulationChanged,
            payload: .object([
                "kind": .string("context"),
                "context": .object(["theme": .string("light")]),
            ]),
            timestamp: "2026-01-01T00:00:01Z"
        )
        let action = ServerEvent(
            type: .simulationChanged,
            payload: .object([
                "kind": .string("action"),
                "description": .string("Would type text."),
            ]),
            timestamp: "2026-01-01T00:00:02Z"
        )

        await hub.publish(runtime)
        await hub.publish(context)
        await hub.publish(action)
        let stream = await hub.stream()
        var iterator = stream.makeAsyncIterator()

        let first = await iterator.next()
        let second = await iterator.next()
        await hub.finish()
        let end = await iterator.next()

        XCTAssertEqual(first, runtime)
        XCTAssertEqual(second, context)
        XCTAssertNil(end)
    }

    func testEventHubBroadcastsRuntimeDeltaButReplaysCompleteSnapshot() async {
        let hub = EditorServerEventHub()
        let delta = ServerEvent(
            type: .runtimeSnapshot,
            payload: .object(["items": .array([.object([
                "id": .string("clock"),
                "title": .null,
            ])])]),
            timestamp: "2026-01-01T00:00:00Z"
        )
        let complete = ServerEvent(
            type: .runtimeSnapshot,
            payload: .object(["items": .array([.object([
                "id": .string("clock"),
                "renderedImage": .string("data:image/png;base64,AAAA"),
            ])])]),
            timestamp: "2026-01-01T00:00:00Z"
        )

        let liveStream = await hub.stream()
        var liveIterator = liveStream.makeAsyncIterator()
        await hub.publish(delta, cachedRuntimeSnapshot: complete)
        let liveEvent = await liveIterator.next()
        XCTAssertEqual(liveEvent, delta)
        XCTAssertEqual(
            liveEvent?.payload.objectValue?["items"],
            .array([.object(["id": .string("clock"), "title": .null])])
        )

        let reconnectStream = await hub.stream()
        var reconnectIterator = reconnectStream.makeAsyncIterator()
        let replayedEvent = await reconnectIterator.next()
        XCTAssertEqual(replayedEvent, complete)
        await hub.finish()
    }

    func testRootCreatesStrictSessionAndStatusRequiresIt() async throws {
        let provider = EditorServerTestProvider()
        let server = makeServer(provider: provider)
        let app = server.makeApplication()

        try await app.test(.router) { client in
            let root = try await client.execute(
                uri: "/",
                method: .get
            )
            XCTAssertEqual(root.status, .ok)
            XCTAssertEqual(root.headers[.contentType], "text/html; charset=utf-8")
            XCTAssertNotNil(root.headers[.contentSecurityPolicy])
            XCTAssertNil(root.headers[.accessControlAllowOrigin])
            let cookie = try XCTUnwrap(root.headers[.setCookie])
            XCTAssertTrue(cookie.contains("HttpOnly"))
            XCTAssertTrue(cookie.contains("SameSite=Strict"))

            let denied = try await client.execute(
                uri: "/api/v1/status",
                method: .get
            )
            XCTAssertEqual(denied.status, .forbidden)

            let status = try await client.execute(
                uri: "/api/v1/status",
                method: .get,
                headers: Self.authenticatedHeaders(cookie: cookie)
            )
            XCTAssertEqual(status.status, .ok)
            let json = try Self.decodeJSON(status.body)
            XCTAssertEqual(json.objectValue?["port"], .number(8787))
            XCTAssertEqual(json.objectValue?["configPath"], .string("build-checks/test-home/.mtmr.json"))

            let applications = try await client.execute(
                uri: "/api/v1/applications",
                method: .get,
                headers: Self.authenticatedHeaders(cookie: cookie)
            )
            XCTAssertEqual(applications.status, .ok)
            XCTAssertEqual(
                try Self.decodeJSON(applications.body).objectValue?["applications"]?.arrayValue?.first?.objectValue?["bundleIdentifier"],
                .string("com.apple.Terminal")
            )
        }
    }

    func testSessionBootstrapUsesTheSameHostOriginAndCookiePolicy() async throws {
        let server = makeServer(provider: EditorServerTestProvider())
        let app = server.makeApplication()

        try await app.test(.router) { client in
            let session = try await client.execute(
                uri: "/api/v1/session",
                method: .get
            )
            XCTAssertEqual(session.status, .ok)
            let cookie = try XCTUnwrap(session.headers[.setCookie])
            XCTAssertTrue(cookie.contains("HttpOnly"))
            XCTAssertTrue(cookie.contains("SameSite=Strict"))
            XCTAssertEqual(try Self.decodeJSON(session.body).objectValue?["ok"], .bool(true))

            let authenticated = try await client.execute(
                uri: "/api/v1/status",
                method: .get,
                headers: Self.authenticatedHeaders(cookie: cookie)
            )
            XCTAssertEqual(authenticated.status, .ok)

            let foreignOrigin = try await client.execute(
                uri: "/api/v1/session",
                method: .get,
                headers: [
                    .origin: "http://127.0.0.1:5173",
                ]
            )
            XCTAssertEqual(foreignOrigin.status, .forbidden)
        }
    }

    func testHostOriginAndContentTypeAreEnforced() async throws {
        let productionSecurity = EditorServerSecurity(
            configuration: .init(editorRootURL: nil),
            sessionToken: "test-token"
        )
        let trustedRequest = Request(
            head: .init(
                method: .get,
                scheme: "http",
                authority: "127.0.0.1:8787",
                path: "/",
                headerFields: [:]
            ),
            body: .init(buffer: ByteBuffer())
        )
        let foreignHostRequest = Request(
            head: .init(
                method: .get,
                scheme: "http",
                authority: "evil.invalid",
                path: "/",
                headerFields: [:]
            ),
            body: .init(buffer: ByteBuffer())
        )
        XCTAssertTrue(productionSecurity.allowsPublicAssetRequest(trustedRequest))
        XCTAssertFalse(productionSecurity.allowsPublicAssetRequest(foreignHostRequest))

        let server = makeServer(provider: EditorServerTestProvider())
        let app = server.makeApplication()

        try await app.test(.router) { client in
            let cookie = try await Self.sessionCookie(client)
            let body = ByteBuffer(string: #"{"source":"{}"}"#)

            let badOrigin = try await client.execute(
                uri: "/api/v1/validate",
                method: .post,
                headers: Self.mutationHeaders(cookie: cookie, origin: "http://evil.invalid"),
                body: body
            )
            XCTAssertEqual(badOrigin.status, .forbidden)

            var noContentType = Self.authenticatedHeaders(cookie: cookie)
            noContentType[.origin] = "http://127.0.0.1:8787"
            let unsupported = try await client.execute(
                uri: "/api/v1/validate",
                method: .post,
                headers: noContentType,
                body: body
            )
            XCTAssertEqual(unsupported.status, .unsupportedMediaType)
        }
    }

    func testPutRequiresRevisionAndReturnsConflictOrValidationDiagnostics() async throws {
        let server = makeServer(provider: EditorServerTestProvider())
        let app = server.makeApplication()

        try await app.test(.router) { client in
            let cookie = try await Self.sessionCookie(client)
            let body = ByteBuffer(string: #"{"source":"{\"formatVersion\":1,\"items\":[]}"}"#)

            let missing = try await client.execute(
                uri: "/api/v1/config",
                method: .put,
                headers: Self.mutationHeaders(cookie: cookie),
                body: body
            )
            XCTAssertEqual(missing.status, .badRequest)

            var staleHeaders = Self.mutationHeaders(cookie: cookie)
            staleHeaders[.ifMatch] = #""0""#
            let conflict = try await client.execute(
                uri: "/api/v1/config",
                method: .put,
                headers: staleHeaders,
                body: body
            )
            XCTAssertEqual(conflict.status, .conflict)

            var validHeaders = Self.mutationHeaders(cookie: cookie)
            validHeaders[.ifMatch] = #""1""#
            let invalidBody = ByteBuffer(string: #"{"source":"invalid"}"#)
            let invalid = try await client.execute(
                uri: "/api/v1/config",
                method: .put,
                headers: validHeaders,
                body: invalidBody
            )
            XCTAssertEqual(invalid.status, .unprocessableContent)
        }
    }

    func testBodyLimitAndMutationRateLimit() async throws {
        let provider = EditorServerTestProvider()
        let configuration = MMTMREditorServerConfiguration(
            bodyLimit: 64,
            mutationLimitPerMinute: 2,
            editorRootURL: nil
        )
        let server = MMTMREditorServer(
            configuration: configuration,
            provider: provider,
            assets: EditorServerTestAssets(),
            security: Self.routerSecurity(configuration: configuration)
        )
        let app = server.makeApplication()

        try await app.test(.router) { client in
            let cookie = try await Self.sessionCookie(client)
            let headers = Self.mutationHeaders(cookie: cookie)

            let oversized = ByteBuffer(string: #"{"source":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}"#)
            let tooLarge = try await client.execute(
                uri: "/api/v1/validate",
                method: .post,
                headers: headers,
                body: oversized
            )
            XCTAssertEqual(tooLarge.status, .contentTooLarge)

            let action = ByteBuffer(string: #"{"itemID":"letter-z","trigger":"singleTap"}"#)
            let first = try await client.execute(uri: "/api/v1/preview/action", method: .post, headers: headers, body: action)
            XCTAssertEqual(first.status, .ok)

            let limited = try await client.execute(uri: "/api/v1/preview/action", method: .post, headers: headers, body: action)
            XCTAssertEqual(limited.status, .tooManyRequests)
            let replaceCallCount = await provider.replaceCallCount()
            XCTAssertEqual(replaceCallCount, 0, "Previewing an action must never call the configuration executor")
        }
    }

    private func makeServer(provider: EditorServerTestProvider) -> MMTMREditorServer {
        let configuration = MMTMREditorServerConfiguration(editorRootURL: nil)
        return MMTMREditorServer(
            configuration: configuration,
            provider: provider,
            assets: EditorServerTestAssets(),
            security: Self.routerSecurity(configuration: configuration)
        )
    }

    private static func sessionCookie(_ client: some TestClientProtocol) async throws -> String {
        let response = try await client.execute(
            uri: "/",
            method: .get
        )
        return try XCTUnwrap(response.headers[.setCookie])
    }

    private static func authenticatedHeaders(cookie: String) -> HTTPFields {
        [.cookie: cookie.split(separator: ";", maxSplits: 1).first.map(String.init) ?? cookie]
    }

    private static func mutationHeaders(
        cookie: String,
        origin: String = "http://127.0.0.1:8787"
    ) -> HTTPFields {
        var headers = authenticatedHeaders(cookie: cookie)
        headers[.origin] = origin
        headers[.contentType] = "application/json"
        return headers
    }

    private static func routerSecurity(configuration: MMTMREditorServerConfiguration) -> EditorServerSecurity {
        EditorServerSecurity(
            expectedHost: "localhost",
            expectedOrigin: configuration.expectedOrigin,
            sessionToken: "router-test-session"
        )
    }

    private static func decodeJSON(_ buffer: ByteBuffer) throws -> ServerJSONValue {
        try JSONDecoder().decode(ServerJSONValue.self, from: Data(buffer.readableBytesView))
    }
}

private actor EditorServerTestProvider: ServerConfigurationProviding {
    private var revision = 1
    private var source = #"{"formatVersion":1,"items":[]}"#
    private var replaceCalls = 0

    func configurationSnapshot() -> ServerConfigurationSnapshot {
        snapshot()
    }

    func configurationSchema() -> ServerJSONValue {
        .object([
            "$schema": .string("https://json-schema.org/draft/2020-12/schema"),
            "type": .string("object"),
        ])
    }

    func validateConfiguration(source: String) -> ServerValidationResult {
        if source == "invalid" {
            return .init(
                valid: false,
                document: nil,
                diagnostics: [.init(severity: .error, message: "Invalid fixture")]
            )
        }
        return .init(valid: true, document: .object([:]), diagnostics: [])
    }

    func replaceConfiguration(source: String, expectedRevision: Int) -> ServerConfigurationWriteResult {
        replaceCalls += 1
        guard expectedRevision == revision else { return .conflict(snapshot()) }
        let validation = validateConfiguration(source: source)
        guard validation.valid else { return .invalid(validation) }
        revision += 1
        self.source = source
        return .accepted(snapshot())
    }

    func applicationCatalog() -> ServerApplicationCatalog {
        ServerApplicationCatalog(
            applications: [ServerApplicationDescriptor(
                bundleIdentifier: "com.apple.Terminal",
                name: "Terminal",
                path: "/System/Applications/Utilities/Terminal.app",
                icon: nil,
                installed: true,
                running: false,
                frontmost: false
            )],
            generatedAt: "2026-07-19T00:00:00Z"
        )
    }

    func replaceCallCount() -> Int { replaceCalls }

    private func snapshot() -> ServerConfigurationSnapshot {
        .init(
            source: source,
            document: .object(["formatVersion": .number(1), "items": .array([])]),
            revision: revision,
            diagnostics: [],
            valid: true,
            configPath: "build-checks/test-home/.mtmr.json"
        )
    }
}

private struct EditorServerTestAssets: ServerEditorAssetServing {
    func asset(at path: String) -> ServerEditorAsset? {
        guard path == "index.html" else { return nil }
        return .init(data: Data("<!doctype html><title>MMTMR</title>".utf8), contentType: "text/html; charset=utf-8")
    }
}
