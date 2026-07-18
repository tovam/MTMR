import Foundation

struct ConfigurationBootstrapResult: Equatable, Sendable {
    let destinationURL: URL
    let importedFrom: URL?
    let document: ConfigDocument?
    let diagnostics: [ConfigurationDiagnostic]
    let didCreateFile: Bool

    var isValid: Bool { document != nil }
}

struct ConfigurationBootstrapper {
    let destinationURL: URL
    let legacyURLs: [URL]
    let bundledPresetURL: URL?

    private let codec: ConfigCodec
    private let migrator: LegacyConfigMigrator
    private let store: any ConfigFileStoring
    private let fileManager: FileManager

    init(
        destinationURL: URL? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        legacyURLs: [URL]? = nil,
        bundledPresetURL: URL? = Bundle.main.url(forResource: "defaultPreset", withExtension: "json"),
        codec: ConfigCodec = ConfigCodec(),
        migrator: LegacyConfigMigrator = LegacyConfigMigrator(),
        store: any ConfigFileStoring = FileConfigStore(),
        fileManager: FileManager = .default
    ) {
        self.destinationURL = destinationURL ?? MMTMRConfigurationLocation.canonicalURL(homeDirectory: homeDirectory)
        self.legacyURLs = legacyURLs ?? MMTMRConfigurationLocation.legacyURLs(homeDirectory: homeDirectory)
        self.bundledPresetURL = bundledPresetURL
        self.codec = codec
        self.migrator = migrator
        self.store = store
        self.fileManager = fileManager
    }

    func bootstrapIfNeeded() -> ConfigurationBootstrapResult {
        if fileManager.fileExists(atPath: destinationURL.path) {
            do {
                let result = codec.decode(try store.read(from: destinationURL))
                return ConfigurationBootstrapResult(
                    destinationURL: destinationURL,
                    importedFrom: nil,
                    document: result.document,
                    diagnostics: result.diagnostics,
                    didCreateFile: false
                )
            } catch {
                return failure(
                    source: nil,
                    diagnostic: ConfigurationDiagnostic(code: "bootstrap.read", message: error.localizedDescription)
                )
            }
        }

        let candidates = legacyURLs + (bundledPresetURL.map { [$0] } ?? [])
        guard let sourceURL = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            return failure(
                source: nil,
                diagnostic: ConfigurationDiagnostic(
                    code: "bootstrap.noPreset",
                    message: "No legacy or bundled preset was available to create ~/.mtmr.json."
                )
            )
        }

        do {
            let sourceData = try store.read(from: sourceURL)
            let strictResult = codec.decode(sourceData)
            let document: ConfigDocument
            let canonicalData: Data
            let diagnostics: [ConfigurationDiagnostic]

            if let validDocument = strictResult.document {
                document = validDocument
                canonicalData = try codec.canonicalData(for: validDocument)
                diagnostics = strictResult.diagnostics
            } else {
                let migrated = try migrator.migrate(sourceData)
                document = migrated.document
                canonicalData = migrated.canonicalData
                diagnostics = migrated.diagnostics
            }

            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try store.writeAtomically(canonicalData, to: destinationURL)
            return ConfigurationBootstrapResult(
                destinationURL: destinationURL,
                importedFrom: sourceURL,
                document: document,
                diagnostics: diagnostics,
                didCreateFile: true
            )
        } catch let ConfigMigrationError.invalid(diagnostics) {
            return ConfigurationBootstrapResult(
                destinationURL: destinationURL,
                importedFrom: sourceURL,
                document: nil,
                diagnostics: diagnostics,
                didCreateFile: false
            )
        } catch {
            return failure(
                source: sourceURL,
                diagnostic: ConfigurationDiagnostic(code: "bootstrap.io", message: error.localizedDescription)
            )
        }
    }

    private func failure(source: URL?, diagnostic: ConfigurationDiagnostic) -> ConfigurationBootstrapResult {
        ConfigurationBootstrapResult(
            destinationURL: destinationURL,
            importedFrom: source,
            document: nil,
            diagnostics: [diagnostic],
            didCreateFile: false
        )
    }
}
