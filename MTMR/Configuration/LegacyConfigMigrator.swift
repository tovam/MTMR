import Foundation

struct ConfigMigrationResult: Equatable, Sendable {
    let document: ConfigDocument
    let canonicalData: Data
    let diagnostics: [ConfigurationDiagnostic]
}

enum ConfigMigrationError: Error, Equatable, Sendable {
    case invalid([ConfigurationDiagnostic])
}

struct LegacyConfigMigrator {
    private let codec: ConfigCodec
    private let idGenerator: () -> String

    init(
        codec: ConfigCodec = ConfigCodec(),
        idGenerator: @escaping () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.codec = codec
        self.idGenerator = idGenerator
    }

    func migrate(_ data: Data) throws -> ConfigMigrationResult {
        let root: JSONValue
        do {
            var parser = try StrictJSONParser(data: data, options: .legacy)
            root = try parser.parse()
        } catch let diagnostic as ConfigurationDiagnostic {
            throw ConfigMigrationError.invalid([diagnostic])
        } catch {
            throw ConfigMigrationError.invalid([
                ConfigurationDiagnostic(code: "migration.json", message: error.localizedDescription)
            ])
        }

        guard case let .array(legacyItems) = root else {
            throw ConfigMigrationError.invalid([
                ConfigurationDiagnostic(
                    code: "migration.root",
                    message: "A legacy MTMR preset must be a JSON array."
                )
            ])
        }

        var seenIDs = Set<String>()
        var warnings: [ConfigurationDiagnostic] = []
        let migrated = try legacyItems.enumerated().map { index, value in
            try migrateItem(
                value,
                path: "$[\(index)]",
                seenIDs: &seenIDs,
                warnings: &warnings
            )
        }
        let migratedRoot = JSONValue.object([
            "formatVersion": .number(Double(ConfigDocument.currentFormatVersion)),
            "items": .array(migrated)
        ])

        let temporaryData: Data
        do {
            temporaryData = try JSONEncoder().encode(migratedRoot)
        } catch {
            throw ConfigMigrationError.invalid([
                ConfigurationDiagnostic(code: "migration.encoding", message: error.localizedDescription)
            ])
        }

        let validation = codec.decode(temporaryData)
        guard let document = validation.document else {
            throw ConfigMigrationError.invalid(warnings + validation.diagnostics)
        }
        do {
            return ConfigMigrationResult(
                document: document,
                canonicalData: try codec.canonicalData(for: document),
                diagnostics: warnings + validation.diagnostics
            )
        } catch {
            throw ConfigMigrationError.invalid(warnings + [
                ConfigurationDiagnostic(code: "migration.encoding", message: error.localizedDescription)
            ])
        }
    }

    private func migrateItem(
        _ value: JSONValue,
        path: String,
        seenIDs: inout Set<String>,
        warnings: inout [ConfigurationDiagnostic]
    ) throws -> JSONValue {
        guard case var .object(item) = value else {
            throw ConfigMigrationError.invalid([
                ConfigurationDiagnostic(code: "migration.item", path: path, message: "Every legacy item must be an object.")
            ])
        }

        if let nested = item["items"] {
            guard case let .array(nestedItems) = nested else {
                throw ConfigMigrationError.invalid([
                    ConfigurationDiagnostic(code: "migration.items", path: "\(path).items", message: "Nested items must be an array.")
                ])
            }
            item["items"] = .array(try nestedItems.enumerated().map { index, nestedItem in
                try migrateItem(
                    nestedItem,
                    path: "\(path).items[\(index)]",
                    seenIDs: &seenIDs,
                    warnings: &warnings
                )
            })
        }

        var actions: [JSONValue]
        if let existing = item["actions"] {
            guard case let .array(existingActions) = existing else {
                throw ConfigMigrationError.invalid([
                    ConfigurationDiagnostic(code: "migration.actions", path: "\(path).actions", message: "actions must be an array.")
                ])
            }
            actions = existingActions
        } else {
            actions = []
        }

        if let action = legacyAction(from: item, long: false) { actions.append(action) }
        if let action = legacyAction(from: item, long: true) { actions.append(action) }
        if actions.isEmpty {
            item.removeValue(forKey: "actions")
        } else {
            item["actions"] = .array(actions)
        }

        for key in Self.legacyActionKeys { item.removeValue(forKey: key) }

        let existingID = item["id"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existingID, !existingID.isEmpty, seenIDs.insert(existingID).inserted {
            item["id"] = .string(existingID)
        } else {
            if item["id"] != nil {
                warnings.append(ConfigurationDiagnostic(
                    severity: .warning,
                    code: "migration.replacedID",
                    path: "\(path).id",
                    message: "Missing or duplicate item id was replaced."
                ))
            }
            let id = uniqueID(seenIDs: &seenIDs)
            item["id"] = .string(id)
        }

        return .object(item)
    }

    private func legacyAction(from item: [String: JSONValue], long: Bool) -> JSONValue? {
        let discriminatorKey = long ? "longAction" : "action"
        guard let action = item[discriminatorKey]?.stringValue else { return nil }

        var result: [String: JSONValue] = [
            "trigger": .string(long ? "longTap" : "singleTap"),
            "action": .string(action)
        ]

        switch action {
        case "hidKey", "keyPress":
            if let value = item[long ? "longKeycode" : "keycode"] { result["keycode"] = value }
        case "typeText":
            if let value = item[long ? "longText" : "text"] { result["text"] = value }
        case "appleScript":
            if let value = item[long ? "longActionAppleScript" : "actionAppleScript"] {
                result["actionAppleScript"] = value
            }
        case "shellScript":
            if let value = item[long ? "longExecutablePath" : "executablePath"] {
                result["executablePath"] = value
            }
            if let value = item[long ? "longShellArguments" : "shellArguments"] {
                result["shellArguments"] = value
            }
        case "openUrl":
            if let value = item[long ? "longUrl" : "url"] { result["url"] = value }
        default:
            break
        }
        return .object(result)
    }

    private func uniqueID(seenIDs: inout Set<String>) -> String {
        for _ in 0..<100 {
            let candidate = idGenerator().trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty, seenIDs.insert(candidate).inserted { return candidate }
        }
        var suffix = seenIDs.count + 1
        while !seenIDs.insert("item-\(suffix)").inserted { suffix += 1 }
        return "item-\(suffix)"
    }

    private static let legacyActionKeys: Set<String> = [
        "action", "keycode", "text", "actionAppleScript", "executablePath", "shellArguments", "url",
        "longAction", "longKeycode", "longText", "longActionAppleScript", "longExecutablePath",
        "longShellArguments", "longUrl"
    ]
}
