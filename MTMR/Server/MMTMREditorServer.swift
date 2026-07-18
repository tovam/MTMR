import Foundation
import Hummingbird
import HummingbirdWebSocket
import ServiceLifecycle

final class MMTMREditorServer: @unchecked Sendable {
    let configuration: MMTMREditorServerConfiguration

    private let controller: EditorServerController
    private let taskLock = NSLock()
    private var runTask: Task<Void, Never>?
    private var serviceGroup: ServiceGroup?
    private var runID: UUID?
    private var stopping = false

    init(
        configuration: MMTMREditorServerConfiguration = .init(),
        provider: any ServerConfigurationProviding,
        assets: (any ServerEditorAssetServing)? = nil,
        security: EditorServerSecurity? = nil
    ) {
        self.configuration = configuration

        let resolvedAssets: any ServerEditorAssetServing
        if let assets {
            resolvedAssets = assets
        } else if let editorRootURL = configuration.editorRootURL {
            resolvedAssets = BundleEditorAssetStore(rootURL: editorRootURL)
        } else {
            resolvedAssets = EmptyEditorAssetStore()
        }

        self.controller = EditorServerController(
            configuration: configuration,
            provider: provider,
            assets: resolvedAssets,
            security: security ?? EditorServerSecurity(configuration: configuration),
            events: EditorServerEventHub(),
            preview: EditorPreviewStore(),
            mutationRateLimiter: EditorMutationRateLimiter(limit: configuration.mutationLimitPerMinute),
            webSocketLimiter: EditorWebSocketLimiter(
                connectionLimit: configuration.webSocketConnectionLimit,
                messageLimit: configuration.webSocketMessageLimitPerMinute
            )
        )
    }

    /// Builds the exact application used at runtime and is intentionally exposed for
    /// Hummingbird's in-process test framework.
    func makeApplication() -> some ApplicationProtocol {
        let httpRouter = controller.buildHTTPRouter()
        let webSocketRouter = controller.buildWebSocketRouter()
        let configuration = self.configuration

        return Application(
            router: httpRouter,
            server: .http1WebSocketUpgrade(
                webSocketRouter: webSocketRouter,
                configuration: .init(
                    ws: .init(
                        maxFrameSize: configuration.bodyLimit,
                        validateUTF8: true
                    )
                )
            ),
            configuration: .init(
                address: .hostname(MMTMREditorServerConfiguration.bindHost, port: configuration.port),
                serverName: "MMTMR",
                reuseAddress: true
            ),
            onServerRunning: { _ in
                configuration.stateHandler(.running(configuration.serverURL))
            }
        )
    }

    /// Starts the editor on `127.0.0.1`. Binding failures are reported through the
    /// configured state handler and never cause a fallback to another interface or port.
    func start() {
        taskLock.withLock {
            guard runTask == nil, !stopping else { return }

            // Install the complete lifecycle under one lock so stop() never
            // observes a half-created service and a restart cannot overlap a
            // server which is still shutting down.
            configuration.stateHandler(.starting)
            let application = makeApplication()
            let stateHandler = configuration.stateHandler
            let serviceGroup = ServiceGroup(
                configuration: .init(
                    services: [application],
                    gracefulShutdownSignals: [],
                    logger: application.logger
                )
            )
            let id = UUID()
            let task = Task.detached(priority: .utility) { [weak self] in
                do {
                    try await serviceGroup.run()
                    stateHandler(.stopped)
                } catch is CancellationError {
                    stateHandler(.stopped)
                } catch {
                    stateHandler(.failed(String(describing: error)))
                }
                self?.runDidFinish(id: id)
            }
            runTask = task
            self.serviceGroup = serviceGroup
            runID = id
        }
    }

    func stop() async {
        let (task, serviceGroup, id) = taskLock.withLock { () -> (Task<Void, Never>?, ServiceGroup?, UUID?) in
            guard let task = runTask else { return (nil, nil, nil) }
            stopping = true
            return (task, self.serviceGroup, runID)
        }

        guard let task else {
            configuration.stateHandler(.stopped)
            return
        }
        if let serviceGroup {
            await serviceGroup.triggerGracefulShutdown()
        } else {
            task.cancel()
        }
        await task.value
        await controller.events.finish()
        taskLock.withLock {
            guard runID == id else { return }
            runTask = nil
            self.serviceGroup = nil
            runID = nil
            stopping = false
        }
    }

    /// Allows the configuration coordinator to forward external file changes and
    /// authoritative AppKit runtime snapshots to connected editor sessions. A
    /// complete cached snapshot can accompany a smaller live image delta.
    func publish(_ event: ServerEvent, cachedRuntimeSnapshot: ServerEvent? = nil) async {
        await controller.events.publish(event, cachedRuntimeSnapshot: cachedRuntimeSnapshot)
    }

    deinit {
        taskLock.withLock {
            runTask?.cancel()
            runTask = nil
            serviceGroup = nil
            runID = nil
            stopping = false
        }
    }

    private func runDidFinish(id: UUID) {
        taskLock.withLock {
            guard runID == id, !stopping else { return }
            runTask = nil
            serviceGroup = nil
            runID = nil
        }
    }

}

private struct EmptyEditorAssetStore: ServerEditorAssetServing {
    func asset(at _: String) -> ServerEditorAsset? { nil }
}
