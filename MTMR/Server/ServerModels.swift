import Foundation

/// A Sendable, Codable representation of arbitrary JSON used at the server boundary.
///
/// Keeping this type independent from the configuration model lets the editor server
/// expose the current document and schema without depending on the parser's concrete
/// Swift types.
enum ServerJSONValue: Codable, Equatable, Sendable {
    case object([String: ServerJSONValue])
    case array([ServerJSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([ServerJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: ServerJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var objectValue: [String: ServerJSONValue]? {
        guard case .object(let object) = self else { return nil }
        return object
    }

    var stringValue: String? {
        guard case .string(let string) = self else { return nil }
        return string
    }

    var numberValue: Double? {
        guard case .number(let number) = self else { return nil }
        return number
    }
}

struct ServerDiagnostic: Codable, Equatable, Sendable {
    enum Severity: String, Codable, Sendable {
        case error
        case warning
        case information
    }

    let severity: Severity
    let message: String
    let code: String?
    let path: String?
    let line: Int?
    let column: Int?

    init(
        severity: Severity,
        message: String,
        code: String? = nil,
        path: String? = nil,
        line: Int? = nil,
        column: Int? = nil
    ) {
        self.severity = severity
        self.message = message
        self.code = code
        self.path = path
        self.line = line
        self.column = column
    }
}

struct ServerConfigurationSnapshot: Codable, Equatable, Sendable {
    let source: String
    let document: ServerJSONValue?
    let revision: Int
    let diagnostics: [ServerDiagnostic]
    let valid: Bool
    let configPath: String

    init(
        source: String,
        document: ServerJSONValue?,
        revision: Int,
        diagnostics: [ServerDiagnostic],
        valid: Bool,
        configPath: String
    ) {
        self.source = source
        self.document = document
        self.revision = revision
        self.diagnostics = diagnostics
        self.valid = valid
        self.configPath = configPath
    }
}

struct ServerValidationResult: Codable, Equatable, Sendable {
    let valid: Bool
    let document: ServerJSONValue?
    let diagnostics: [ServerDiagnostic]

    init(valid: Bool, document: ServerJSONValue?, diagnostics: [ServerDiagnostic]) {
        self.valid = valid
        self.document = document
        self.diagnostics = diagnostics
    }
}

enum ServerConfigurationWriteResult: Sendable {
    case accepted(ServerConfigurationSnapshot)
    case conflict(ServerConfigurationSnapshot)
    case invalid(ServerValidationResult)
}

/// The only configuration-core contract required by the embedded editor server.
///
/// Implementations are expected to serialize mutations internally. In particular,
/// `replaceConfiguration` must compare and replace atomically so two clients cannot
/// both commit against the same revision.
protocol ServerConfigurationProviding: Sendable {
    func configurationSnapshot() async throws -> ServerConfigurationSnapshot
    func configurationSchema() async throws -> ServerJSONValue
    func validateConfiguration(source: String) async throws -> ServerValidationResult
    func replaceConfiguration(source: String, expectedRevision: Int) async throws -> ServerConfigurationWriteResult
}

struct ServerEvent: Codable, Equatable, Sendable {
    enum EventType: String, Codable, Hashable, Sendable {
        case configChanged = "config.changed"
        case configInvalid = "config.invalid"
        case runtimeSnapshot = "runtime.snapshot"
        case simulationChanged = "simulation.changed"
        case serverError = "server.error"
    }

    let type: EventType
    let revision: Int?
    let payload: ServerJSONValue
    let timestamp: String

    init(
        type: EventType,
        revision: Int? = nil,
        payload: ServerJSONValue,
        timestamp: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.type = type
        self.revision = revision
        self.payload = payload
        self.timestamp = timestamp
    }
}

enum MMTMREditorServerState: Equatable, Sendable {
    case stopped
    case starting
    case running(URL)
    case failed(String)
}
