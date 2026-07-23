import Cocoa
import Network

private struct RuntimeConfigurationApplyError: LocalizedError, Sendable {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    var isBlockedApp = false

    private var coordinator: ConfigurationCoordinator?
    private var serverProvider: ConfigurationServerAdapter?
    private var editorServer: MMTMREditorServer?
    private var editorServerState: MMTMREditorServerState = .stopped
    private var configurationURL = MMTMRConfigurationLocation.canonicalURL()
    private var editorPort = MMTMREditorServerConfiguration.defaultPort
    private var terminating = false
    private var lastRuntimeError: String?
    private var lastInputDispatchError: String?
    private var preparedRuntimeItems: [String: [RuntimeBarItem]] = [:]
    private let networkMonitor = NWPathMonitor()
    private var networkConnected = false
    private var runtimeSnapshotTimer: Timer?
    private var lastRuntimeSnapshotHash: String?
    private let runtimeContextTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mmXXXXX"
        return formatter
    }()

    func applicationDidFinishLaunching(_: Notification) {
        guard noOtherMTMRInstanceIsRunning() else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "MTMR ou MMTMR est déjà lancé"
            alert.informativeText = "Quittez l’autre instance avant de lancer MMTMR afin que deux processus ne contrôlent pas la Touch Bar en même temps."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        configureLaunchOptions()
        bootstrapConfiguration()
        configureStatusItem()
        configureRuntimeContextMonitoring()
        configureInputDispatchMonitoring()

        TouchBarController.shared.setupControlStripPresence()
        if let snapshot = coordinator?.loadFromDisk() {
            _ = applyConfiguration(snapshot, publishConfigurationEvent: false)
        }

        startConfigurationWatcher()
        startEditorServer(port: editorPort)
        createMenu()

        // Move the one-time macOS permission prompt out of the first physical
        // Touch Bar tap so an already-authorized app injects immediately.
        DispatchQueue.main.async { [weak self] in
            self?.requestSystemInputAccess(openSettingsIfDenied: false)
        }

        let notifications = NSWorkspace.shared.notificationCenter
        notifications.addObserver(self, selector: #selector(updateIsBlockedApp(_:)), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        notifications.addObserver(self, selector: #selector(updateIsBlockedApp(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        notifications.addObserver(self, selector: #selector(updateIsBlockedApp(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        terminating = true
        coordinator?.stopWatching()
        networkMonitor.cancel()
        runtimeSnapshotTimer?.invalidate()
        runtimeSnapshotTimer = nil
        NotificationCenter.default.removeObserver(self, name: .mmtmrInputDispatchDidComplete, object: nil)

        guard let editorServer else { return .terminateNow }
        Task {
            await editorServer.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    @objc private func updateIsBlockedApp(_: Notification? = nil) {
        if let frontmostAppID = TouchBarController.shared.frontmostApplicationIdentifier {
            isBlockedApp = AppSettings.blacklistedAppIds.contains(frontmostAppID)
        } else {
            isBlockedApp = false
        }
        createMenu()
        publishRuntimeSnapshot()
    }

    @objc private func openEditor(_: Any?) {
        guard case let .running(url) = editorServerState else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "L’éditeur MMTMR n’est pas disponible"
            alert.informativeText = serverStateDescription
            alert.runModal()
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func openConfiguration(_: Any?) {
        guard FileManager.default.fileExists(atPath: configurationURL.path) else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Le fichier de configuration est absent"
            alert.informativeText = configurationURL.path
            alert.runModal()
            return
        }
        NSWorkspace.shared.open(configurationURL)
    }

    private func configureInputDispatchMonitoring() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(inputDispatchDidComplete(_:)),
            name: .mmtmrInputDispatchDidComplete,
            object: nil
        )
    }

    @objc private func requestSystemInputAccess(_: Any?) {
        requestSystemInputAccess(openSettingsIfDenied: true)
    }

    private func requestSystemInputAccess(openSettingsIfDenied: Bool) {
        let granted = InputAccessCoordinator.shared.requestCoreGraphicsPostEventAccessIfNeeded()
        createMenu()
        publishRuntimeSnapshot(force: true)

        guard !granted, openSettingsIfDenied,
              let settingsURL = URL(
                  string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
              )
        else { return }
        NSWorkspace.shared.open(settingsURL)
    }

    @objc private func inputDispatchDidComplete(_ notification: Notification) {
        guard let result = notification.userInfo?[MMTMRInputDispatchNotification.resultUserInfoKey]
            as? InputDispatchResult
        else { return }

        if result.succeeded {
            lastInputDispatchError = nil
        } else {
            let message = Self.localizedInputDispatchMessage(result)
            lastInputDispatchError = message
            publishServerError(
                message,
                code: "input.\(result.action.rawValue).\(result.status.rawValue)"
            )
        }
        createMenu()
        publishRuntimeSnapshot()
    }

    @objc private func changeEditorPort(_: Any?) {
        let field = NSTextField(string: String(editorPort))
        field.placeholderString = "8787"

        let alert = NSAlert()
        alert.messageText = "Port de l’éditeur MMTMR"
        alert.informativeText = "Choisissez un port local entre 1 et 65535. Le serveur restera lié uniquement à 127.0.0.1."
        alert.accessoryView = field
        alert.addButton(withTitle: "Appliquer")
        alert.addButton(withTitle: "Annuler")

        guard alert.runModal() == .alertFirstButtonReturn,
              let port = Int(field.stringValue),
              (1...65_535).contains(port),
              port != editorPort
        else { return }

        AppSettings.editorPort = port
        restartEditorServer(port: port)
    }

    @objc private func toggleControlStrip(_ item: NSMenuItem) {
        item.state = item.state == .on ? .off : .on
        AppSettings.showControlStripState = item.state == .off
        TouchBarController.shared.resetControlStrip()
    }

    @objc private func toggleBlackListedApp(_: Any?) {
        guard let appIdentifier = TouchBarController.shared.frontmostApplicationIdentifier else { return }
        if let index = TouchBarController.shared.blacklistAppIdentifiers.firstIndex(of: appIdentifier) {
            TouchBarController.shared.blacklistAppIdentifiers.remove(at: index)
        } else {
            TouchBarController.shared.blacklistAppIdentifiers.append(appIdentifier)
        }

        AppSettings.blacklistedAppIds = TouchBarController.shared.blacklistAppIdentifiers
        TouchBarController.shared.updateActiveApp()
        updateIsBlockedApp()
    }

    @objc private func toggleHapticFeedback(_ item: NSMenuItem) {
        item.state = item.state == .on ? .off : .on
        AppSettings.hapticFeedbackState = item.state == .on
    }

    @objc private func toggleMultitouch(_ item: NSMenuItem) {
        item.state = item.state == .on ? .off : .on
        AppSettings.multitouchGestures = item.state == .on
        TouchBarController.shared.basicView?.legacyGesturesEnabled = item.state == .on
    }

    @objc private func toggleStartAtLogin(_: Any?) {
        let controller = LaunchAtLoginController()
        controller.setLaunchAtLogin(
            !controller.launchAtLogin,
            for: URL(fileURLWithPath: Bundle.main.bundlePath)
        )
        createMenu()
    }

    private func configureLaunchOptions() {
        #if DEBUG
        let allowOverrides = true
        #else
        let allowOverrides = false
        #endif

        do {
            let options = try MMTMRLaunchOptions.parse(allowDevelopmentOverrides: allowOverrides)
            configurationURL = options.configurationURL
            let requestedPort = CommandLine.arguments.contains("--editor-port")
                ? options.editorPort
                : AppSettings.editorPort
            editorPort = (1...65_535).contains(requestedPort)
                ? requestedPort
                : MMTMREditorServerConfiguration.defaultPort
        } catch {
            configurationURL = MMTMRConfigurationLocation.canonicalURL()
            editorPort = AppSettings.editorPort
            lastRuntimeError = error.localizedDescription
        }
    }

    private func bootstrapConfiguration() {
        let canonicalURL = MMTMRConfigurationLocation.canonicalURL().standardizedFileURL
        let legacyURLs = configurationURL.standardizedFileURL == canonicalURL
            ? MMTMRConfigurationLocation.legacyURLs()
            : []
        let result = ConfigurationBootstrapper(
            destinationURL: configurationURL,
            legacyURLs: legacyURLs
        ).bootstrapIfNeeded()
        if !result.isValid {
            lastRuntimeError = result.diagnostics.map(\.message).joined(separator: " · ")
        }

        let coordinator = ConfigurationCoordinator(configurationURL: configurationURL)
        self.coordinator = coordinator
        serverProvider = ConfigurationServerAdapter(
            coordinator: coordinator,
            runtimeValidator: { [weak self] document in
                await MainActor.run { [weak self] in
                    self?.runtimeDiagnostics(for: document) ?? [ConfigurationDiagnostic(
                        code: "runtime.unavailable",
                        message: "The MMTMR runtime is unavailable."
                    )]
                }
            },
            onAccepted: { [weak self] snapshot in
                let applied = await MainActor.run { [weak self] in
                    self?.applyConfiguration(snapshot, publishConfigurationEvent: false) ?? false
                }
                if !applied {
                    throw RuntimeConfigurationApplyError("The validated configuration could not be applied to AppKit.")
                }
            },
            touchBarCalibrationHandler: { [weak self] request in
                await MainActor.run {
                    let state = TouchBarController.shared.updateCalibrationPreview(
                        active: request.active,
                        centerOffset: request.centerOffset,
                        pointsPerMillimeter: request.pointsPerMillimeter
                    )
                    self?.publishRuntimeSnapshot(force: true)
                    return ServerTouchBarCalibrationState(
                        active: state.calibrationActive,
                        hardwareModel: state.hardwareModel,
                        centerReference: state.centerReference.rawValue,
                        centerOffset: state.centerOffset,
                        pointsPerMillimeter: state.pointsPerMillimeter,
                        guideWidthMillimeters:
                            TouchBarLayoutRuntimeState.calibrationGuideWidthMillimeters,
                        calibrated: state.calibrated
                    )
                }
            }
        )
    }

    private func configureStatusItem() {
        statusItem.button?.image = #imageLiteral(resourceName: "StatusImage")
        statusItem.button?.toolTip = "MMTMR"
    }

    private func configureRuntimeContextMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                networkConnected = path.status == .satisfied
                publishRuntimeSnapshot()
            }
        }
        networkMonitor.start(queue: DispatchQueue(label: "com.tovam.MMTMR.network-context"))

        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.publishRuntimeSnapshot() }
        }
        timer.tolerance = 0.2
        runtimeSnapshotTimer = timer
    }

    private func startConfigurationWatcher() {
        do {
            try coordinator?.startWatching { [weak self] snapshot in
                Task { @MainActor [weak self] in
                    self?.applyConfiguration(snapshot, publishConfigurationEvent: true)
                }
            }
        } catch {
            lastRuntimeError = "Surveillance de la configuration : \(error.localizedDescription)"
        }
    }

    private func applyConfiguration(
        _ snapshot: ConfigurationSnapshot,
        publishConfigurationEvent: Bool
    ) -> Bool {
        var eventSnapshot = snapshot
        defer {
            createMenu()
            if publishConfigurationEvent { publishConfiguration(eventSnapshot) }
        }

        guard let document = snapshot.document else {
            // An invalid external edit is observable, but never replaces the last
            // valid AppKit tree already displayed on the Touch Bar.
            return false
        }

        do {
            let configItems = try document.runtimeItems(relativeTo: configurationURL)
            let cacheKey = try runtimeCacheKey(document: document, items: configItems)
            let runtimeItems: [RuntimeBarItem]
            if let prepared = preparedRuntimeItems.removeValue(forKey: cacheKey) {
                runtimeItems = prepared
            } else {
                runtimeItems = try resolveRuntimeItems(configItems)
                let diagnostics = validateRuntimeItems(runtimeItems)
                guard !diagnostics.contains(where: { $0.severity == .error }) else {
                    eventSnapshot = coordinator?.rejectRuntimeConfiguration(
                        revision: snapshot.revision,
                        diagnostics: diagnostics
                    ) ?? snapshot
                    lastRuntimeError = diagnostics.map(\.message).joined(separator: " · ")
                    publishServerError(lastRuntimeError ?? "Erreur runtime inconnue")
                    return false
                }
            }
            TouchBarController.shared.apply(
                runtimeItems: runtimeItems,
                layoutConfiguration: document.touchBarLayout
            )
            lastRuntimeError = nil
            DispatchQueue.main.async { [weak self] in
                self?.publishRuntimeSnapshot(revision: snapshot.revision, force: true)
            }
            return true
        } catch {
            let diagnostic = ConfigurationDiagnostic(
                code: "runtime.decode",
                message: "Résolution de la barre : \(error.localizedDescription)"
            )
            eventSnapshot = coordinator?.rejectRuntimeConfiguration(
                revision: snapshot.revision,
                diagnostics: [diagnostic]
            ) ?? snapshot
            lastRuntimeError = diagnostic.message
            publishServerError(lastRuntimeError ?? "Erreur runtime inconnue")
            return false
        }
    }

    private func runtimeDiagnostics(for document: ConfigDocument) -> [ConfigurationDiagnostic] {
        do {
            let configItems = try document.runtimeItems(relativeTo: configurationURL)
            let runtimeItems = try resolveRuntimeItems(configItems)
            let diagnostics = validateRuntimeItems(runtimeItems)
            guard !diagnostics.contains(where: { $0.severity == .error }) else { return diagnostics }

            let key = try runtimeCacheKey(document: document, items: configItems)
            preparedRuntimeItems[key] = runtimeItems
            while preparedRuntimeItems.count > 4, let oldest = preparedRuntimeItems.keys.first {
                preparedRuntimeItems.removeValue(forKey: oldest)
            }
            return diagnostics
        } catch {
            return [ConfigurationDiagnostic(
                code: "runtime.decode",
                message: "The configuration cannot be resolved by the Touch Bar runtime: \(error.localizedDescription)"
            )]
        }
    }

    private func resolveRuntimeItems(_ items: [RuntimeConfigItem]) throws -> [RuntimeBarItem] {
        try items.map { item in
            RuntimeBarItem(
                id: item.id,
                kind: item.kind,
                sourcePath: item.sourcePath,
                fingerprint: item.fingerprint,
                definition: try JSONDecoder().decode(BarItemDefinition.self, from: item.data)
            )
        }
    }

    private func runtimeCacheKey(document: ConfigDocument, items: [RuntimeConfigItem]) throws -> String {
        var data = try ConfigCodec().canonicalData(for: document)
        for item in items {
            data.append(0)
            data.append(contentsOf: item.id.utf8)
            data.append(0)
            data.append(contentsOf: item.fingerprint.utf8)
        }
        return ConfigContentHasher.sha256(data)
    }

    private func validateRuntimeItems(_ items: [RuntimeBarItem]) -> [ConfigurationDiagnostic] {
        var diagnostics: [ConfigurationDiagnostic] = []
        for item in items {
            validateRuntimeDefinition(
                item.definition,
                path: item.sourcePath,
                diagnostics: &diagnostics
            )
        }
        return diagnostics
    }

    private func validateRuntimeDefinition(
        _ definition: BarItemDefinition,
        path: String,
        diagnostics: inout [ConfigurationDiagnostic]
    ) {
        if case let .image(source)? = definition.additionalParameters[.image], source.image == nil {
            diagnostics.append(ConfigurationDiagnostic(
                code: "runtime.image",
                path: "\(path).image",
                message: "The configured image cannot be decoded."
            ))
        }

        switch definition.type {
        case let .appleScriptTitledButton(source, _, alternativeImages):
            validateAppleScript(source, path: "\(path).source", diagnostics: &diagnostics)
            for (name, image) in alternativeImages where image.image == nil {
                diagnostics.append(ConfigurationDiagnostic(
                    code: "runtime.image",
                    path: "\(path).alternativeImages.\(name)",
                    message: "The alternative image cannot be decoded."
                ))
            }
        case let .shellScriptTitledButton(source, _):
            if source.string == nil {
                diagnostics.append(ConfigurationDiagnostic(
                    code: "runtime.scriptEncoding",
                    path: "\(path).source",
                    message: "The shell title source must be readable text."
                ))
            }
        case let .pinnedDock(_, applications, _, _, _):
            for (index, application) in applications.enumerated() {
                let pathExists = application.path.map {
                    FileManager.default.fileExists(atPath: $0)
                } ?? false
                guard !pathExists,
                      NSWorkspace.shared.urlForApplication(
                        withBundleIdentifier: application.bundleIdentifier
                      ) == nil
                else { continue }
                diagnostics.append(ConfigurationDiagnostic(
                    severity: .warning,
                    code: "runtime.applicationMissing",
                    path: "\(path).applications[\(index)]",
                    message: "Application not found: \(application.bundleIdentifier). The pinned placeholder will remain visible."
                ))
            }
        case let .swipe(_, _, _, sourceApple, sourceBash):
            if let sourceApple {
                validateAppleScript(sourceApple, path: "\(path).sourceApple", diagnostics: &diagnostics)
            }
            if let sourceBash, sourceBash.string == nil {
                diagnostics.append(ConfigurationDiagnostic(
                    code: "runtime.scriptEncoding",
                    path: "\(path).sourceBash",
                    message: "The swipe shell source must be readable text."
                ))
            }
        case let .group(items):
            for (index, item) in items.enumerated() {
                validateRuntimeDefinition(
                    item,
                    path: item.sourcePath ?? "\(path).items[\(index)]",
                    diagnostics: &diagnostics
                )
            }
        default:
            break
        }

        for (index, action) in definition.actions.enumerated() {
            if case let .appleScript(source) = action.value {
                validateAppleScript(
                    source,
                    path: "\(path).actions[\(index)].actionAppleScript",
                    diagnostics: &diagnostics
                )
            }
        }
    }

    private func validateAppleScript(
        _ source: SourceProtocol,
        path: String,
        diagnostics: inout [ConfigurationDiagnostic]
    ) {
        guard let script = source.appleScript else {
            diagnostics.append(ConfigurationDiagnostic(
                code: "runtime.appleScript",
                path: path,
                message: "The AppleScript source cannot be loaded."
            ))
            return
        }
        var details: NSDictionary?
        guard script.compileAndReturnError(&details) else {
            diagnostics.append(ConfigurationDiagnostic(
                code: "runtime.appleScript",
                path: path,
                message: details?[NSAppleScript.errorMessage] as? String ?? "The AppleScript source does not compile."
            ))
            return
        }
    }

    private func startEditorServer(port: Int) {
        guard let serverProvider else { return }
        editorPort = port
        let configuration = MMTMREditorServerConfiguration(
            port: port,
            stateHandler: { [weak self] state in
                Task { @MainActor [weak self] in
                    self?.editorServerDidChangeState(state)
                }
            }
        )
        let server = MMTMREditorServer(configuration: configuration, provider: serverProvider)
        editorServer = server
        server.start()
    }

    private func restartEditorServer(port: Int) {
        let previous = editorServer
        editorServer = nil
        editorServerState = .starting
        createMenu()
        Task {
            if let previous { await previous.stop() }
            startEditorServer(port: port)
        }
    }

    private func editorServerDidChangeState(_ state: MMTMREditorServerState) {
        editorServerState = state
        createMenu()
        if case .running = state, let snapshot = coordinator?.snapshot() {
            publishConfiguration(snapshot)
            publishRuntimeSnapshot(revision: snapshot.revision, force: true)
        }
    }

    private func publishConfiguration(_ snapshot: ConfigurationSnapshot) {
        guard let editorServer, let serverProvider else { return }
        let envelope = serverProvider.serverSnapshot(snapshot)
        guard let payload = Self.serverJSON(envelope) else { return }
        let event = ServerEvent(
            type: snapshot.isValid ? .configChanged : .configInvalid,
            revision: Int(clamping: snapshot.revision),
            payload: payload
        )
        Task { await editorServer.publish(event) }
    }

    private func publishRuntimeSnapshot(revision: UInt64? = nil, force: Bool = false) {
        guard let editorServer else { return }
        let runtimeGeometry = TouchBarController.shared.runtimeGeometry()
        let completeGeometry: [ServerJSONValue] = runtimeGeometry.map { item in
            var object: [String: ServerJSONValue] = [
                "id": .string(item.id),
                "align": .string(item.align),
                "width": .number(item.width),
                "height": .number(item.height),
                "visible": .bool(item.visible),
                "kind": .string(item.kind),
            ]
            if let x = item.x {
                object["x"] = .number(x)
            }
            if let title = item.title {
                object["title"] = .string(title)
            }
            if let renderedImage = item.renderedImage {
                object["renderedImage"] = .string(renderedImage)
            }
            return .object(object)
        }
        let deltaGeometry: [ServerJSONValue] = runtimeGeometry.map { item in
            var object: [String: ServerJSONValue] = [
                "id": .string(item.id),
                "align": .string(item.align),
                "width": .number(item.width),
                "height": .number(item.height),
                "visible": .bool(item.visible),
                "kind": .string(item.kind),
            ]
            if let x = item.x {
                object["x"] = .number(x)
            }
            object["title"] = item.title.map { .string($0) } ?? .null
            if item.renderedImageChanged {
                object["renderedImage"] = item.renderedImage.map { .string($0) } ?? .null
            }
            return .object(object)
        }

        let batteryInfo = BatteryInfo()
        batteryInfo.getPSInfo()
        let theme = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "dark" : "light"
        let context: ServerJSONValue = .object([
            "application": .string(TouchBarController.shared.frontmostApplicationIdentifier ?? ""),
            "battery": .number(Double(batteryInfo.current)),
            "inputAccess": .bool(CGPreflightPostEventAccess()),
            "networkConnected": .bool(networkConnected),
            "theme": .string(theme),
            "time": .string(runtimeContextTimeFormatter.string(from: Date())),
        ])
        let touchBarLayoutState = TouchBarController.shared.currentTouchBarLayoutState()
        let touchBarLayout: ServerJSONValue = .object([
            "active": .bool(touchBarLayoutState.calibrationActive),
            "calibrated": .bool(touchBarLayoutState.calibrated),
            "centerOffset": .number(touchBarLayoutState.centerOffset),
            "centerReference": .string(touchBarLayoutState.centerReference.rawValue),
            "guideWidthMillimeters": .number(
                TouchBarLayoutRuntimeState.calibrationGuideWidthMillimeters
            ),
            "hardwareModel": .string(touchBarLayoutState.hardwareModel),
            "pointsPerMillimeter": .number(touchBarLayoutState.pointsPerMillimeter),
        ])
        let completePayload: ServerJSONValue = .object([
            "items": .array(completeGeometry),
            "context": context,
            "touchBarLayout": touchBarLayout,
        ])
        let eventRevision = revision ?? coordinator?.snapshot().revision
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard var hashData = try? encoder.encode(completePayload) else { return }
        hashData.append(Data("|revision:\(eventRevision.map { String($0) } ?? "nil")".utf8))
        let snapshotHash = ConfigContentHasher.sha256(hashData)
        guard force || snapshotHash != lastRuntimeSnapshotHash else { return }
        lastRuntimeSnapshotHash = snapshotHash

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let completeEvent = ServerEvent(
            type: .runtimeSnapshot,
            revision: eventRevision.map { Int(clamping: $0) },
            payload: completePayload,
            timestamp: timestamp
        )
        let event = ServerEvent(
            type: .runtimeSnapshot,
            revision: eventRevision.map { Int(clamping: $0) },
            payload: force ? completePayload : .object([
                "items": .array(deltaGeometry),
                "context": context,
                "touchBarLayout": touchBarLayout,
            ]),
            timestamp: timestamp
        )
        Task {
            await editorServer.publish(event, cachedRuntimeSnapshot: completeEvent)
        }
    }

    private func publishServerError(_ message: String, code: String? = nil) {
        guard let editorServer else { return }
        var payload: [String: ServerJSONValue] = ["message": .string(message)]
        if let code {
            payload["code"] = .string(code)
        }
        Task {
            await editorServer.publish(ServerEvent(
                type: .serverError,
                payload: .object(payload)
            ))
        }
    }

    private func createMenu() {
        let menu = NSMenu()

        let heading = NSMenuItem(title: "MMTMR", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        menu.addItem(withTitle: "Ouvrir l’éditeur", action: #selector(openEditor(_:)), keyEquivalent: "e")
        menu.addItem(withTitle: "Ouvrir ~/.mtmr.json", action: #selector(openConfiguration(_:)), keyEquivalent: ",")

        let serverStatus = NSMenuItem(title: serverStateDescription, action: nil, keyEquivalent: "")
        serverStatus.isEnabled = false
        menu.addItem(serverStatus)

        let pathItem = NSMenuItem(title: configurationURL.path, action: nil, keyEquivalent: "")
        pathItem.isEnabled = false
        menu.addItem(pathItem)
        menu.addItem(withTitle: "Changer le port…", action: #selector(changeEditorPort(_:)), keyEquivalent: "")

        let inputAccessGranted = CGPreflightPostEventAccess()
        let inputAccessItem = NSMenuItem(
            title: inputAccessGranted
                ? "Saisie Unicode : autorisée"
                : "⚠︎ Autoriser la saisie Unicode…",
            action: inputAccessGranted ? nil : #selector(requestSystemInputAccess(_:)),
            keyEquivalent: ""
        )
        inputAccessItem.isEnabled = !inputAccessGranted
        menu.addItem(inputAccessItem)

        if let snapshot = coordinator?.snapshot(), !snapshot.isValid {
            let diagnostic = snapshot.diagnostics.first?.message ?? "Configuration invalide"
            let item = NSMenuItem(title: "⚠︎ \(diagnostic)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else if let lastRuntimeError {
            let item = NSMenuItem(title: "⚠︎ \(lastRuntimeError)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        if let lastInputDispatchError {
            let item = NSMenuItem(title: "⚠︎ \(lastInputDispatchError)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let hapticFeedback = NSMenuItem(title: "Retour haptique", action: #selector(toggleHapticFeedback(_:)), keyEquivalent: "h")
        hapticFeedback.state = AppSettings.hapticFeedbackState ? .on : .off
        menu.addItem(hapticFeedback)

        let hideControlStrip = NSMenuItem(title: "Masquer le Control Strip", action: #selector(toggleControlStrip(_:)), keyEquivalent: "t")
        hideControlStrip.state = AppSettings.showControlStripState ? .off : .on
        menu.addItem(hideControlStrip)

        let toggleBlackList = NSMenuItem(title: "Exclure l’application active", action: #selector(toggleBlackListedApp(_:)), keyEquivalent: "b")
        toggleBlackList.state = isBlockedApp ? .on : .off
        menu.addItem(toggleBlackList)

        let startAtLogin = NSMenuItem(title: "Lancer à l’ouverture de session", action: #selector(toggleStartAtLogin(_:)), keyEquivalent: "l")
        startAtLogin.state = LaunchAtLoginController().launchAtLogin ? .on : .off
        menu.addItem(startAtLogin)

        let multitouch = NSMenuItem(title: "Gestes volume/luminosité", action: #selector(toggleMultitouch(_:)), keyEquivalent: "")
        multitouch.state = AppSettings.multitouchGestures ? .on : .off
        menu.addItem(multitouch)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quitter MMTMR", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    private var serverStateDescription: String {
        switch editorServerState {
        case .stopped:
            return "Serveur arrêté"
        case .starting:
            return "Serveur : démarrage sur 127.0.0.1:\(editorPort)…"
        case let .running(url):
            return "Serveur : \(url.absoluteString)"
        case let .failed(message):
            return "Serveur indisponible sur 127.0.0.1:\(editorPort) — \(message)"
        }
    }

    private func noOtherMTMRInstanceIsRunning() -> Bool {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let identifiers = ["Toxblh.MTMR", "com.toxblh.MTMR", "com.tovam.MTMR", "com.tovam.MMTMR"]
        return !identifiers.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
            .contains(where: { $0.processIdentifier != currentPID && !$0.isTerminated })
    }

    private static func localizedInputDispatchMessage(_ result: InputDispatchResult) -> String {
        switch result.status {
        case .permissionDenied:
            return "MMTMR n’est pas autorisé dans Réglages > Confidentialité et sécurité > Accessibilité."
        case .eventCreationFailed:
            return "macOS n’a pas pu créer l’événement pour \(result.action.rawValue)."
        case .backendFailure:
            return "La commande système \(result.action.rawValue) a échoué."
        case .partialDispatch:
            return "La commande système \(result.action.rawValue) n’a été envoyée que partiellement."
        case .success:
            return ""
        }
    }

    private static func serverJSON<Value: Encodable>(_ value: Value) -> ServerJSONValue? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(ServerJSONValue.self, from: data)
    }
}
