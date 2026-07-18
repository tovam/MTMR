import Foundation

struct ConfigCodec: Sendable {
    private let validator = ConfigValidator()

    func decode(_ data: Data) -> ConfigurationValidationResult {
        let root: JSONValue
        do {
            var parser = try StrictJSONParser(data: data)
            root = try parser.parse()
        } catch let diagnostic as ConfigurationDiagnostic {
            return ConfigurationValidationResult(document: nil, diagnostics: [diagnostic], canonicalSource: nil)
        } catch {
            return ConfigurationValidationResult(
                document: nil,
                diagnostics: [ConfigurationDiagnostic(code: "json.invalid", message: error.localizedDescription)],
                canonicalSource: nil
            )
        }

        let diagnostics = validator.validate(root: root)
        guard !diagnostics.contains(where: { $0.severity == .error }) else {
            return ConfigurationValidationResult(document: nil, diagnostics: diagnostics, canonicalSource: nil)
        }

        do {
            let intermediate = try JSONEncoder().encode(root)
            let document = try JSONDecoder().decode(ConfigDocument.self, from: intermediate)
            let source = try canonicalString(for: document)
            return ConfigurationValidationResult(document: document, diagnostics: diagnostics, canonicalSource: source)
        } catch {
            let diagnostic = ConfigurationDiagnostic(
                code: "config.decode",
                message: "Configuration could not be decoded: \(error.localizedDescription)"
            )
            return ConfigurationValidationResult(document: nil, diagnostics: diagnostics + [diagnostic], canonicalSource: nil)
        }
    }

    func decode(_ source: String) -> ConfigurationValidationResult {
        decode(Data(source.utf8))
    }

    func canonicalData(for document: ConfigDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(document)
        if data.last != 0x0A { data.append(0x0A) }
        return data
    }

    func canonicalString(for document: ConfigDocument) throws -> String {
        let data = try canonicalData(for: document)
        guard let source = String(data: data, encoding: .utf8) else {
            throw ConfigurationDiagnostic(code: "config.encoding", message: "Could not encode configuration as UTF-8.")
        }
        return source
    }

    func validate(_ document: ConfigDocument) -> ConfigurationValidationResult {
        do {
            return decode(try canonicalData(for: document))
        } catch {
            return ConfigurationValidationResult(
                document: nil,
                diagnostics: [ConfigurationDiagnostic(code: "config.encoding", message: error.localizedDescription)],
                canonicalSource: nil
            )
        }
    }
}
