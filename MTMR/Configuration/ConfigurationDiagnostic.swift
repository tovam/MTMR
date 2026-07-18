import Foundation

enum ConfigurationDiagnosticSeverity: String, Codable, Equatable, Sendable {
    case warning
    case error
}

struct ConfigurationDiagnostic: Error, Codable, Equatable, Sendable {
    let severity: ConfigurationDiagnosticSeverity
    let code: String
    let path: String
    let message: String
    let line: Int?
    let column: Int?

    init(
        severity: ConfigurationDiagnosticSeverity = .error,
        code: String,
        path: String = "$",
        message: String,
        line: Int? = nil,
        column: Int? = nil
    ) {
        self.severity = severity
        self.code = code
        self.path = path
        self.message = message
        self.line = line
        self.column = column
    }
}

struct ConfigurationValidationResult: Codable, Equatable, Sendable {
    let document: ConfigDocument?
    let diagnostics: [ConfigurationDiagnostic]
    let canonicalSource: String?

    var isValid: Bool {
        document != nil && !diagnostics.contains(where: { $0.severity == .error })
    }
}
