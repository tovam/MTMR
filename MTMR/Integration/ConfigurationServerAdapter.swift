import AppKit
import Foundation

/// Bridges the strict configuration owner to the transport-only editor server.
/// The coordinator remains the sole authority for revisions and disk writes.
final class ConfigurationServerAdapter: ServerConfigurationProviding, @unchecked Sendable {
    private let coordinator: ConfigurationCoordinator
    private let runtimeValidator: @Sendable (ConfigDocument) async -> [ConfigurationDiagnostic]
    private let onAccepted: @Sendable (ConfigurationSnapshot) async throws -> Void
    private let touchBarCalibrationHandler:
        @Sendable (ServerTouchBarCalibrationRequest) async throws -> ServerTouchBarCalibrationState

    init(
        coordinator: ConfigurationCoordinator,
        runtimeValidator: @escaping @Sendable (ConfigDocument) async -> [ConfigurationDiagnostic] = { _ in [] },
        onAccepted: @escaping @Sendable (ConfigurationSnapshot) async throws -> Void = { _ in },
        touchBarCalibrationHandler:
            @escaping @Sendable (ServerTouchBarCalibrationRequest) async throws -> ServerTouchBarCalibrationState = {
                request in
                ServerTouchBarCalibrationState(
                    active: request.active,
                    hardwareModel: "unknown",
                    centerReference: request.active ? "chassis" : "touchBar",
                    centerOffset: request.centerOffset ?? 0,
                    pointsPerMillimeter: request.pointsPerMillimeter
                        ?? TouchBarCalibrationProfile.defaultPointsPerMillimeter,
                    guideWidthMillimeters: TouchBarLayoutRuntimeState.calibrationGuideWidthMillimeters,
                    calibrated: false
                )
            }
    ) {
        self.coordinator = coordinator
        self.runtimeValidator = runtimeValidator
        self.onAccepted = onAccepted
        self.touchBarCalibrationHandler = touchBarCalibrationHandler
    }

    func configurationSnapshot() async throws -> ServerConfigurationSnapshot {
        serverSnapshot(coordinator.snapshot())
    }

    func configurationSchema() async throws -> ServerJSONValue {
        MMTMRConfigurationSchema.document
    }

    func validateConfiguration(source: String) async throws -> ServerValidationResult {
        let validation = coordinator.validate(source: source)
        guard let document = validation.document else { return serverValidation(validation) }
        let runtimeDiagnostics = await runtimeValidator(document)
        return serverValidation(validation, additionalDiagnostics: runtimeDiagnostics)
    }

    func replaceConfiguration(
        source: String,
        expectedRevision: Int
    ) async throws -> ServerConfigurationWriteResult {
        guard expectedRevision >= 0 else {
            return .conflict(serverSnapshot(coordinator.snapshot()))
        }

        let current = coordinator.snapshot()
        guard UInt64(expectedRevision) == current.revision else {
            return .conflict(serverSnapshot(current))
        }

        let validation = coordinator.validate(source: source)
        guard let document = validation.document else {
            return .invalid(serverValidation(validation))
        }
        let runtimeDiagnostics = await runtimeValidator(document)
        if runtimeDiagnostics.contains(where: { $0.severity == .error }) {
            return .invalid(serverValidation(validation, additionalDiagnostics: runtimeDiagnostics))
        }

        do {
            let snapshot = try coordinator.replace(
                source: source,
                expectedRevision: UInt64(expectedRevision)
            )
            do {
                try await onAccepted(snapshot)
                return .accepted(serverSnapshot(snapshot))
            } catch {
                // The write has already committed at this point. Never answer
                // with a generic 500 that would make the browser retry a save
                // which actually advanced the revision. Publish the persisted
                // source as invalid and keep the previous AppKit bar visible.
                let current = coordinator.snapshot()
                let rejected: ConfigurationSnapshot
                if current.revision == snapshot.revision, current.document != nil {
                    rejected = coordinator.rejectRuntimeConfiguration(
                        revision: snapshot.revision,
                        diagnostics: [ConfigurationDiagnostic(
                            code: "runtime.apply",
                            message: "The configuration was saved but could not be applied to AppKit: \(error.localizedDescription)"
                        )]
                    )
                } else {
                    rejected = current
                }
                return .accepted(serverSnapshot(rejected))
            }
        } catch ConfigurationCoordinatorError.revisionConflict {
            return .conflict(serverSnapshot(coordinator.snapshot()))
        } catch let ConfigurationCoordinatorError.invalid(diagnostics) {
            return .invalid(ServerValidationResult(
                valid: false,
                document: nil,
                diagnostics: diagnostics.map(Self.serverDiagnostic)
            ))
        }
    }

    func applicationCatalog() async throws -> ServerApplicationCatalog {
        await InstalledApplicationCatalog.shared.snapshot()
    }

    func updateTouchBarCalibration(
        _ request: ServerTouchBarCalibrationRequest
    ) async throws -> ServerTouchBarCalibrationState {
        try await touchBarCalibrationHandler(request)
    }

    func serverSnapshot(_ snapshot: ConfigurationSnapshot) -> ServerConfigurationSnapshot {
        ServerConfigurationSnapshot(
            source: snapshot.source,
            document: snapshot.document.flatMap(Self.serverJSON),
            revision: Int(clamping: snapshot.revision),
            diagnostics: snapshot.diagnostics.map(Self.serverDiagnostic),
            valid: snapshot.isValid,
            configPath: coordinator.configurationURL.path
        )
    }

    private func serverValidation(
        _ validation: ConfigurationValidationResult,
        additionalDiagnostics: [ConfigurationDiagnostic] = []
    ) -> ServerValidationResult {
        let diagnostics = validation.diagnostics + additionalDiagnostics
        return ServerValidationResult(
            valid: validation.document != nil && !diagnostics.contains(where: { $0.severity == .error }),
            document: validation.document.flatMap(Self.serverJSON),
            diagnostics: diagnostics.map(Self.serverDiagnostic)
        )
    }

    private static func serverJSON<Value: Encodable>(_ value: Value) -> ServerJSONValue? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(ServerJSONValue.self, from: data)
    }

    private static func serverDiagnostic(_ diagnostic: ConfigurationDiagnostic) -> ServerDiagnostic {
        let severity: ServerDiagnostic.Severity
        switch diagnostic.severity {
        case .error:
            severity = .error
        case .warning:
            severity = .warning
        }
        return ServerDiagnostic(
            severity: severity,
            message: diagnostic.message,
            code: diagnostic.code,
            path: diagnostic.path,
            line: diagnostic.line,
            column: diagnostic.column
        )
    }
}

/// Produces a read-only catalog from macOS' standard application folders. The
/// HTTP endpoint never accepts a path, so it cannot be repurposed as a general
/// filesystem browser.
@MainActor
private final class InstalledApplicationCatalog {
    static let shared = InstalledApplicationCatalog()

    private struct InstalledApplication {
        let bundleIdentifier: String
        let name: String
        let path: String
        let icon: String?
    }

    private var cachedApplications: [InstalledApplication] = []
    private var cacheDate: Date?
    private let cacheLifetime: TimeInterval = 60

    func snapshot() -> ServerApplicationCatalog {
        if cacheDate.map({ Date().timeIntervalSince($0) >= cacheLifetime }) != false {
            cachedApplications = scanApplications()
            cacheDate = Date()
        }

        let runningIdentifiers = Set(
            NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        )
        let frontmostIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return ServerApplicationCatalog(applications: cachedApplications.map { application in
            ServerApplicationDescriptor(
                bundleIdentifier: application.bundleIdentifier,
                name: application.name,
                path: application.path,
                icon: application.icon,
                installed: true,
                running: runningIdentifiers.contains(application.bundleIdentifier),
                frontmost: frontmostIdentifier == application.bundleIdentifier
            )
        })
    }

    private func scanApplications() -> [InstalledApplication] {
        let fileManager = FileManager.default
        let roots = [
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Library/CoreServices", isDirectory: true),
        ]
        var applicationsByIdentifier: [String: InstalledApplication] = [:]

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let url as URL in enumerator {
                guard url.pathExtension.caseInsensitiveCompare("app") == .orderedSame else { continue }
                enumerator.skipDescendants()
                guard applicationsByIdentifier.count < 1_000,
                      let bundle = Bundle(url: url),
                      let bundleIdentifier = bundle.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !bundleIdentifier.isEmpty,
                      applicationsByIdentifier[bundleIdentifier] == nil
                else { continue }

                let localized = bundle.localizedInfoDictionary
                let name = (localized?["CFBundleDisplayName"] as? String)
                    ?? (localized?["CFBundleName"] as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let icon = Self.iconDataURL(NSWorkspace.shared.icon(forFile: url.path))
                applicationsByIdentifier[bundleIdentifier] = InstalledApplication(
                    bundleIdentifier: bundleIdentifier,
                    name: name,
                    path: url.path,
                    icon: icon
                )
            }
        }

        return applicationsByIdentifier.values.sorted { left, right in
            let order = left.name.localizedCaseInsensitiveCompare(right.name)
            return order == .orderedSame
                ? left.bundleIdentifier < right.bundleIdentifier
                : order == .orderedAscending
        }
    }

    private static func iconDataURL(_ source: NSImage) -> String? {
        let size = NSSize(width: 56, height: 56)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: source.size),
            operation: .sourceOver,
            fraction: 1
        )
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]),
              png.count <= 96 * 1_024
        else { return nil }
        return "data:image/png;base64,\(png.base64EncodedString())"
    }
}
