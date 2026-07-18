import Foundation

actor EditorServerEventHub {
    private var continuations: [UUID: AsyncStream<ServerEvent>.Continuation] = [:]
    private var latestRuntimeSnapshot: ServerEvent?
    private var latestSimulationContext: ServerEvent?

    func stream() -> AsyncStream<ServerEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<ServerEvent>.makeStream(bufferingPolicy: .bufferingNewest(128))
        continuations[id] = continuation
        if let latestRuntimeSnapshot { continuation.yield(latestRuntimeSnapshot) }
        if let latestSimulationContext { continuation.yield(latestSimulationContext) }
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id: id) }
        }
        return stream
    }

    func publish(_ event: ServerEvent) {
        if event.type == .runtimeSnapshot {
            latestRuntimeSnapshot = event
        } else if event.type == .simulationChanged,
                  event.payload.objectValue?["kind"] == .string("context") {
            // Action simulations are log entries, not visual state. Replaying
            // one must not evict the last context selected by the user.
            latestSimulationContext = event
        }
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    func finish() {
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
        latestRuntimeSnapshot = nil
        latestSimulationContext = nil
    }

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }
}

actor EditorPreviewStore {
    private var context: ServerJSONValue = .object([:])

    func replace(with context: ServerJSONValue) -> ServerJSONValue {
        self.context = context
        return context
    }

    func snapshot() -> ServerJSONValue {
        context
    }
}

/// A single-session rolling-window limiter. The server has one secret session and only
/// listens on loopback, so a global/session bucket is both deterministic and sufficient.
actor EditorMutationRateLimiter {
    private let limit: Int
    private let window: TimeInterval
    private var acceptedRequestTimes: [TimeInterval] = []

    init(limit: Int, window: TimeInterval = 60) {
        self.limit = limit
        self.window = window
    }

    func allowRequest(now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        let cutoff = now - window
        acceptedRequestTimes.removeAll { $0 <= cutoff }
        guard acceptedRequestTimes.count < limit else { return false }
        acceptedRequestTimes.append(now)
        return true
    }
}

/// Bounds authenticated WebSocket work independently from HTTP mutations. The
/// editor never accepts commands over this channel, so exceeding the quota only
/// closes that connection and leaves the application state untouched.
actor EditorWebSocketLimiter {
    private let connectionLimit: Int
    private let messageLimit: Int
    private let window: TimeInterval
    private var activeConnections = 0
    private var acceptedMessageTimes: [TimeInterval] = []

    init(connectionLimit: Int, messageLimit: Int, window: TimeInterval = 60) {
        self.connectionLimit = connectionLimit
        self.messageLimit = messageLimit
        self.window = window
    }

    func acquireConnection() -> Bool {
        guard activeConnections < connectionLimit else { return false }
        activeConnections += 1
        return true
    }

    func releaseConnection() {
        activeConnections = max(0, activeConnections - 1)
    }

    func allowMessage(now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        let cutoff = now - window
        acceptedMessageTimes.removeAll { $0 <= cutoff }
        guard acceptedMessageTimes.count < messageLimit else { return false }
        acceptedMessageTimes.append(now)
        return true
    }
}
