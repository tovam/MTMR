import Foundation

/// Small RFC 8259 parser used before Codable so duplicate keys, comments, and
/// trailing commas cannot be silently accepted by Foundation.
struct StrictJSONParser {
    struct Options {
        let allowsComments: Bool
        let allowsTrailingCommas: Bool

        static let strict = Options(allowsComments: false, allowsTrailingCommas: false)
        static let legacy = Options(allowsComments: true, allowsTrailingCommas: true)
    }

    private let bytes: [UInt8]
    private let options: Options
    private var offset = 0

    init(data: Data, options: Options = .strict) throws {
        guard String(data: data, encoding: .utf8) != nil else {
            throw ConfigurationDiagnostic(
                code: "json.invalidUTF8",
                message: "Configuration must be valid UTF-8."
            )
        }
        bytes = Array(data)
        self.options = options
    }

    mutating func parse() throws -> JSONValue {
        try skipWhitespaceAndComments()
        let value = try parseValue(path: "$")
        try skipWhitespaceAndComments()
        guard offset == bytes.count else {
            throw diagnostic(code: "json.trailingContent", message: "Unexpected content after the JSON document.")
        }
        return value
    }

    private mutating func parseValue(path: String) throws -> JSONValue {
        try skipWhitespaceAndComments()
        guard let byte = peek() else {
            throw diagnostic(code: "json.unexpectedEnd", path: path, message: "Unexpected end of JSON input.")
        }

        switch byte {
        case 0x7B: return try parseObject(path: path) // {
        case 0x5B: return try parseArray(path: path) // [
        case 0x22: return .string(try parseString(path: path)) // "
        case 0x74:
            try consumeLiteral("true", path: path)
            return .bool(true)
        case 0x66:
            try consumeLiteral("false", path: path)
            return .bool(false)
        case 0x6E:
            try consumeLiteral("null", path: path)
            return .null
        case 0x2D, 0x30...0x39:
            return .number(try parseNumber(path: path))
        default:
            throw diagnostic(code: "json.unexpectedToken", path: path, message: "Unexpected token in JSON value.")
        }
    }

    private mutating func parseObject(path: String) throws -> JSONValue {
        offset += 1
        try skipWhitespaceAndComments()
        var result: [String: JSONValue] = [:]
        var seen = Set<String>()

        if consume(0x7D) { return .object(result) }

        while true {
            try skipWhitespaceAndComments()
            guard peek() == 0x22 else {
                throw diagnostic(code: "json.expectedKey", path: path, message: "Expected a quoted object key.")
            }
            let keyOffset = offset
            let key = try parseString(path: path)
            let keyPath = Self.appending(key: key, to: path)
            guard seen.insert(key).inserted else {
                throw diagnostic(
                    at: keyOffset,
                    code: "json.duplicateKey",
                    path: keyPath,
                    message: "Duplicate object key ‘\(key)’ is not allowed."
                )
            }

            try skipWhitespaceAndComments()
            guard consume(0x3A) else {
                throw diagnostic(code: "json.expectedColon", path: keyPath, message: "Expected ':' after object key.")
            }
            result[key] = try parseValue(path: keyPath)
            try skipWhitespaceAndComments()

            if consume(0x7D) { break }
            guard consume(0x2C) else {
                throw diagnostic(code: "json.expectedComma", path: path, message: "Expected ',' or '}' in object.")
            }
            try skipWhitespaceAndComments()
            if peek() == 0x7D {
                guard options.allowsTrailingCommas else {
                    throw diagnostic(code: "json.trailingComma", path: path, message: "Trailing commas are not valid strict JSON.")
                }
                offset += 1
                break
            }
        }
        return .object(result)
    }

    private mutating func parseArray(path: String) throws -> JSONValue {
        offset += 1
        try skipWhitespaceAndComments()
        var result: [JSONValue] = []

        if consume(0x5D) { return .array(result) }

        while true {
            result.append(try parseValue(path: "\(path)[\(result.count)]"))
            try skipWhitespaceAndComments()
            if consume(0x5D) { break }
            guard consume(0x2C) else {
                throw diagnostic(code: "json.expectedComma", path: path, message: "Expected ',' or ']' in array.")
            }
            try skipWhitespaceAndComments()
            if peek() == 0x5D {
                guard options.allowsTrailingCommas else {
                    throw diagnostic(code: "json.trailingComma", path: path, message: "Trailing commas are not valid strict JSON.")
                }
                offset += 1
                break
            }
        }
        return .array(result)
    }

    private mutating func parseString(path: String) throws -> String {
        let start = offset
        offset += 1

        while let byte = peek() {
            switch byte {
            case 0x22:
                offset += 1
                let token = Data(bytes[start..<offset])
                do {
                    return try JSONDecoder().decode(String.self, from: token)
                } catch {
                    throw diagnostic(at: start, code: "json.invalidString", path: path, message: "Invalid JSON string escape sequence.")
                }
            case 0x00...0x1F:
                throw diagnostic(code: "json.controlCharacter", path: path, message: "Unescaped control character in string.")
            case 0x5C:
                offset += 1
                guard let escaped = peek() else {
                    throw diagnostic(code: "json.unexpectedEnd", path: path, message: "Unterminated string escape.")
                }
                if escaped == 0x75 {
                    offset += 1
                    for _ in 0..<4 {
                        guard let hex = peek(), Self.isHexDigit(hex) else {
                            throw diagnostic(code: "json.invalidUnicodeEscape", path: path, message: "Expected four hexadecimal digits after \\u.")
                        }
                        offset += 1
                    }
                } else if [0x22, 0x5C, 0x2F, 0x62, 0x66, 0x6E, 0x72, 0x74].contains(escaped) {
                    offset += 1
                } else {
                    throw diagnostic(code: "json.invalidEscape", path: path, message: "Invalid JSON string escape sequence.")
                }
            default:
                offset += 1
            }
        }
        throw diagnostic(at: start, code: "json.unterminatedString", path: path, message: "Unterminated JSON string.")
    }

    private mutating func parseNumber(path: String) throws -> Double {
        let start = offset
        _ = consume(0x2D)

        guard let first = peek() else {
            throw diagnostic(code: "json.invalidNumber", path: path, message: "Incomplete JSON number.")
        }
        if first == 0x30 {
            offset += 1
            if let next = peek(), (0x30...0x39).contains(next) {
                throw diagnostic(code: "json.invalidNumber", path: path, message: "Leading zeroes are not allowed in JSON numbers.")
            }
        } else if (0x31...0x39).contains(first) {
            offset += 1
            while let byte = peek(), (0x30...0x39).contains(byte) { offset += 1 }
        } else {
            throw diagnostic(code: "json.invalidNumber", path: path, message: "Invalid JSON number.")
        }

        if consume(0x2E) {
            guard let byte = peek(), (0x30...0x39).contains(byte) else {
                throw diagnostic(code: "json.invalidNumber", path: path, message: "A decimal point must be followed by a digit.")
            }
            while let byte = peek(), (0x30...0x39).contains(byte) { offset += 1 }
        }

        if let byte = peek(), byte == 0x65 || byte == 0x45 {
            offset += 1
            if let sign = peek(), sign == 0x2B || sign == 0x2D { offset += 1 }
            guard let digit = peek(), (0x30...0x39).contains(digit) else {
                throw diagnostic(code: "json.invalidNumber", path: path, message: "An exponent must contain at least one digit.")
            }
            while let digit = peek(), (0x30...0x39).contains(digit) { offset += 1 }
        }

        let raw = String(decoding: bytes[start..<offset], as: UTF8.self)
        guard let value = Double(raw), value.isFinite else {
            throw diagnostic(at: start, code: "json.invalidNumber", path: path, message: "JSON number is outside the supported finite range.")
        }
        return value
    }

    private mutating func consumeLiteral(_ literal: StaticString, path: String) throws {
        let expected = Array("\(literal)".utf8)
        guard bytes.count - offset >= expected.count,
              Array(bytes[offset..<(offset + expected.count)]) == expected else {
            throw diagnostic(code: "json.unexpectedToken", path: path, message: "Invalid JSON literal.")
        }
        offset += expected.count
    }

    private mutating func skipWhitespaceAndComments() throws {
        while offset < bytes.count {
            switch bytes[offset] {
            case 0x20, 0x09, 0x0A, 0x0D:
                offset += 1
            case 0x2F where offset + 1 < bytes.count && (bytes[offset + 1] == 0x2F || bytes[offset + 1] == 0x2A):
                guard options.allowsComments else {
                    throw diagnostic(code: "json.comment", message: "Comments are not valid strict JSON.")
                }
                if bytes[offset + 1] == 0x2F {
                    offset += 2
                    while offset < bytes.count && bytes[offset] != 0x0A && bytes[offset] != 0x0D { offset += 1 }
                } else {
                    let commentStart = offset
                    offset += 2
                    while offset + 1 < bytes.count && !(bytes[offset] == 0x2A && bytes[offset + 1] == 0x2F) { offset += 1 }
                    guard offset + 1 < bytes.count else {
                        throw diagnostic(at: commentStart, code: "json.unterminatedComment", message: "Unterminated block comment.")
                    }
                    offset += 2
                }
            default:
                return
            }
        }
    }

    private func peek() -> UInt8? {
        guard offset < bytes.count else { return nil }
        return bytes[offset]
    }

    @discardableResult
    private mutating func consume(_ byte: UInt8) -> Bool {
        guard peek() == byte else { return false }
        offset += 1
        return true
    }

    private func diagnostic(
        at diagnosticOffset: Int? = nil,
        code: String,
        path: String = "$",
        message: String
    ) -> ConfigurationDiagnostic {
        let position = max(0, min(diagnosticOffset ?? offset, bytes.count))
        var line = 1
        var column = 1
        for byte in bytes[..<position] {
            if byte == 0x0A {
                line += 1
                column = 1
            } else {
                column += 1
            }
        }
        return ConfigurationDiagnostic(code: code, path: path, message: message, line: line, column: column)
    }

    private static func isHexDigit(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte) || (0x41...0x46).contains(byte) || (0x61...0x66).contains(byte)
    }

    private static func appending(key: String, to path: String) -> String {
        let simple = key.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_$")).contains($0)
        }
        return simple ? "\(path).\(key)" : "\(path)[\(String(reflecting: key))]"
    }
}
