import Foundation
import Hummingbird

struct MMTMREditorServerConfiguration: Sendable {
    static let defaultPort = 8787
    static let bindHost = "127.0.0.1"

    let port: Int
    let appVersion: String
    let bodyLimit: Int
    let mutationLimitPerMinute: Int
    let webSocketConnectionLimit: Int
    let webSocketMessageLimitPerMinute: Int
    let editorRootURL: URL?
    let stateHandler: @Sendable (MMTMREditorServerState) -> Void

    init(
        port: Int = MMTMREditorServerConfiguration.defaultPort,
        appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
        bodyLimit: Int = 512 * 1024,
        mutationLimitPerMinute: Int = 240,
        webSocketConnectionLimit: Int = 4,
        webSocketMessageLimitPerMinute: Int = 120,
        editorRootURL: URL? = Bundle.main.resourceURL?.appendingPathComponent("Editor", isDirectory: true),
        stateHandler: @escaping @Sendable (MMTMREditorServerState) -> Void = { _ in }
    ) {
        precondition((1...65_535).contains(port), "Editor port must be between 1 and 65535")
        precondition(bodyLimit > 0, "Editor request body limit must be positive")
        precondition(mutationLimitPerMinute > 0, "Editor mutation rate limit must be positive")
        precondition(webSocketConnectionLimit > 0, "Editor WebSocket connection limit must be positive")
        precondition(webSocketMessageLimitPerMinute > 0, "Editor WebSocket message rate limit must be positive")
        self.port = port
        self.appVersion = appVersion
        self.bodyLimit = bodyLimit
        self.mutationLimitPerMinute = mutationLimitPerMinute
        self.webSocketConnectionLimit = webSocketConnectionLimit
        self.webSocketMessageLimitPerMinute = webSocketMessageLimitPerMinute
        self.editorRootURL = editorRootURL
        self.stateHandler = stateHandler
    }

    var serverURL: URL {
        // The host and port are validated constants/integers, so URL construction cannot fail.
        URL(string: "http://\(Self.bindHost):\(port)")!
    }

    var expectedHost: String { "\(Self.bindHost):\(port)" }
    var expectedOrigin: String { serverURL.absoluteString }
}

struct EditorServerSecurity: Sendable {
    static let sessionCookieName = "mmtmr_session"

    let expectedHost: String
    let expectedOrigin: String
    let sessionToken: String

    init(configuration: MMTMREditorServerConfiguration, sessionToken: String = EditorServerSecurity.makeSessionToken()) {
        self.expectedHost = configuration.expectedHost
        self.expectedOrigin = configuration.expectedOrigin
        self.sessionToken = sessionToken
    }

    init(expectedHost: String, expectedOrigin: String, sessionToken: String = EditorServerSecurity.makeSessionToken()) {
        self.expectedHost = expectedHost
        self.expectedOrigin = expectedOrigin
        self.sessionToken = sessionToken
    }

    func allowsPublicAssetRequest(_ request: Request) -> Bool {
        guard request.head.authority == expectedHost else { return false }
        guard let origin = request.headers[.origin] else { return true }
        return origin == expectedOrigin
    }

    func allowsAPIRequest(_ request: Request, requiresOrigin: Bool) -> Bool {
        guard allowsPublicAssetRequest(request) else { return false }
        if requiresOrigin, request.headers[.origin] != expectedOrigin {
            return false
        }
        guard let suppliedToken = request.cookies[Self.sessionCookieName]?.value else { return false }
        return Self.constantTimeEqual(suppliedToken, sessionToken)
    }

    func allowsWebSocketUpgrade(_ request: Request) -> Bool {
        allowsAPIRequest(request, requiresOrigin: true)
    }

    var cookie: Cookie {
        Cookie(
            name: Self.sessionCookieName,
            value: sessionToken,
            path: "/",
            secure: false,
            httpOnly: true,
            sameSite: .strict
        )
    }

    private static func makeSessionToken() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator)) }.joined()
    }

    private static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        var difference = UInt8(truncatingIfNeeded: left.count ^ right.count)
        let count = max(left.count, right.count)

        for index in 0..<count {
            let leftByte = index < left.count ? left[index] : 0
            let rightByte = index < right.count ? right[index] : 0
            difference |= leftByte ^ rightByte
        }
        return difference == 0
    }
}
