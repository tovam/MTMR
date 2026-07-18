import Foundation

/// Bridges the strict configuration owner to the transport-only editor server.
/// The coordinator remains the sole authority for revisions and disk writes.
final class ConfigurationServerAdapter: ServerConfigurationProviding, @unchecked Sendable {
    private let coordinator: ConfigurationCoordinator
    private let runtimeValidator: @Sendable (ConfigDocument) async -> [ConfigurationDiagnostic]
    private let onAccepted: @Sendable (ConfigurationSnapshot) async throws -> Void

    init(
        coordinator: ConfigurationCoordinator,
        runtimeValidator: @escaping @Sendable (ConfigDocument) async -> [ConfigurationDiagnostic] = { _ in [] },
        onAccepted: @escaping @Sendable (ConfigurationSnapshot) async throws -> Void = { _ in }
    ) {
        self.coordinator = coordinator
        self.runtimeValidator = runtimeValidator
        self.onAccepted = onAccepted
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
