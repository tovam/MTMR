import Foundation

struct ConfigurationSnapshot: Codable, Equatable, Sendable {
    let revision: UInt64
    let hash: String
    let source: String
    let document: ConfigDocument?
    let diagnostics: [ConfigurationDiagnostic]

    var isValid: Bool {
        document != nil && !diagnostics.contains(where: { $0.severity == .error })
    }
}

enum ConfigurationCoordinatorError: Error, Equatable, Sendable {
    case revisionConflict(expected: UInt64, actual: UInt64)
    case invalid([ConfigurationDiagnostic])
    case io(String)
}

final class ConfigurationCoordinator: @unchecked Sendable {
    private static let uninitializedHash = ConfigContentHasher.sha256(
        Data("MMTMR configuration has not been loaded".utf8)
    )
    private static let missingFileHash = ConfigContentHasher.sha256(
        Data("MMTMR configuration file is missing".utf8)
    )

    let configurationURL: URL

    private let codec: ConfigCodec
    private let resourceValidator: ConfigResourceValidator
    private let store: any ConfigFileStoring
    private let stateQueue = DispatchQueue(label: "com.tovam.MMTMR.configuration-coordinator")
    private var state: ConfigurationSnapshot
    private var lastValid: ConfigDocument?
    private var previousValidBeforeCurrent: ConfigDocument?
    private var fileWatcher: ConfigurationFileWatcher?

    init(
        configurationURL: URL = MMTMRConfigurationLocation.canonicalURL(),
        codec: ConfigCodec = ConfigCodec(),
        resourceValidator: ConfigResourceValidator = ConfigResourceValidator(),
        store: any ConfigFileStoring = FileConfigStore()
    ) {
        self.configurationURL = configurationURL
        self.codec = codec
        self.resourceValidator = resourceValidator
        self.store = store
        state = ConfigurationSnapshot(
            revision: 0,
            hash: Self.uninitializedHash,
            source: "",
            document: nil,
            diagnostics: []
        )
    }

    func snapshot() -> ConfigurationSnapshot {
        stateQueue.sync { state }
    }

    func lastValidDocument() -> ConfigDocument? {
        stateQueue.sync { lastValid }
    }

    /// AppKit performs the final platform-specific resolution (images and
    /// AppleScript compilation). If that phase fails for an external edit, fold
    /// its diagnostics into the authoritative snapshot without replacing the
    /// last valid runtime document.
    @discardableResult
    func rejectRuntimeConfiguration(
        revision: UInt64,
        diagnostics: [ConfigurationDiagnostic]
    ) -> ConfigurationSnapshot {
        stateQueue.sync {
            guard state.revision == revision else { return state }
            lastValid = previousValidBeforeCurrent
            previousValidBeforeCurrent = nil
            state = ConfigurationSnapshot(
                revision: state.revision,
                hash: state.hash,
                source: state.source,
                document: nil,
                diagnostics: state.diagnostics + diagnostics
            )
            return state
        }
    }

    @discardableResult
    func loadFromDisk() -> ConfigurationSnapshot {
        stateQueue.sync { refreshFromDiskOnQueue() }
    }

    func validate(source: String) -> ConfigurationValidationResult {
        validate(data: Data(source.utf8))
    }

    @discardableResult
    func replace(source: String, expectedRevision: UInt64) throws -> ConfigurationSnapshot {
        try stateQueue.sync {
            // The directory watcher is debounced, so the file can be newer than
            // the in-memory revision for a short period. Refresh synchronously
            // before comparing If-Match so an editor save is never silently
            // overwritten by a browser PUT.
            _ = refreshFromDiskOnQueue()
            guard expectedRevision == state.revision else {
                throw ConfigurationCoordinatorError.revisionConflict(expected: expectedRevision, actual: state.revision)
            }

            let validation = validate(data: Data(source.utf8))
            guard validation.isValid, let document = validation.document else {
                throw ConfigurationCoordinatorError.invalid(validation.diagnostics)
            }

            let canonicalData: Data
            do {
                canonicalData = try codec.canonicalData(for: document)
                try store.writeAtomically(canonicalData, to: configurationURL)
            } catch {
                throw ConfigurationCoordinatorError.io(error.localizedDescription)
            }

            return updateState(data: canonicalData, validation: validate(data: canonicalData))
        }
    }

    @discardableResult
    func observeExternalChange(_ data: Data?) -> ConfigurationSnapshot {
        observeExternalChange(data, readError: nil)
    }

    func startWatching(onChange: @escaping @Sendable (ConfigurationSnapshot) -> Void) throws {
        stopWatching()
        let watcher = ConfigurationFileWatcher(configurationURL: configurationURL)
        try watcher.startWatching { [weak self] in
            guard let self else { return }
            let previousRevision = self.snapshot().revision
            let updated = self.loadFromDisk()
            if updated.revision != previousRevision { onChange(updated) }
        }
        stateQueue.sync { fileWatcher = watcher }
    }

    func stopWatching() {
        let watcher = stateQueue.sync { () -> ConfigurationFileWatcher? in
            defer { fileWatcher = nil }
            return fileWatcher
        }
        watcher?.stopWatching()
    }

    private func observeExternalChange(_ data: Data?, readError: Error?) -> ConfigurationSnapshot {
        stateQueue.sync { observeExternalChangeOnQueue(data, readError: readError) }
    }

    private func refreshFromDiskOnQueue() -> ConfigurationSnapshot {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        do {
            return observeExternalChangeOnQueue(try store.read(from: configurationURL), readError: nil)
        } catch {
            return observeExternalChangeOnQueue(nil, readError: error)
        }
    }

    private func observeExternalChangeOnQueue(_ data: Data?, readError: Error?) -> ConfigurationSnapshot {
        dispatchPrecondition(condition: .onQueue(stateQueue))
        guard let data else {
            let diagnostic = ConfigurationDiagnostic(
                code: "config.missing",
                path: configurationURL.path,
                message: readError.map { "Configuration could not be read: \($0.localizedDescription)" }
                    ?? "Configuration file does not exist."
            )
            if state.document == nil,
               state.hash == Self.missingFileHash,
               state.diagnostics == [diagnostic] {
                return state
            }
            state = ConfigurationSnapshot(
                revision: state.revision + 1,
                hash: Self.missingFileHash,
                source: "",
                document: nil,
                diagnostics: [diagnostic]
            )
            return state
        }

        let hash = ConfigContentHasher.sha256(data)
        if state.hash == hash { return state }
        return updateState(data: data, validation: validate(data: data))
    }

    private func validate(data: Data) -> ConfigurationValidationResult {
        let decoded = codec.decode(data)
        guard let document = decoded.document else { return decoded }
        let resourceDiagnostics = resourceValidator.validate(document: document, relativeTo: configurationURL)
        guard !resourceDiagnostics.contains(where: { $0.severity == .error }) else {
            return ConfigurationValidationResult(
                document: nil,
                diagnostics: decoded.diagnostics + resourceDiagnostics,
                canonicalSource: nil
            )
        }
        return ConfigurationValidationResult(
            document: document,
            diagnostics: decoded.diagnostics + resourceDiagnostics,
            canonicalSource: decoded.canonicalSource
        )
    }

    private func updateState(data: Data, validation: ConfigurationValidationResult) -> ConfigurationSnapshot {
        let document = validation.document
        if let document {
            previousValidBeforeCurrent = lastValid
            lastValid = document
        }
        state = ConfigurationSnapshot(
            revision: state.revision + 1,
            hash: ConfigContentHasher.sha256(data),
            source: String(decoding: data, as: UTF8.self),
            document: document,
            diagnostics: validation.diagnostics
        )
        return state
    }
}
