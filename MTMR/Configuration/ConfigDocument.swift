import Foundation

struct ConfigDocument: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1

    var formatVersion: Int
    var notes: String?
    var items: [ConfigItem]

    init(formatVersion: Int = ConfigDocument.currentFormatVersion, notes: String? = nil, items: [ConfigItem]) {
        self.formatVersion = formatVersion
        self.notes = notes
        self.items = items
    }

    /// JSON consumed by the existing item parser while it is being replaced by
    /// a fully typed runtime model. Editor-only metadata is intentionally absent.
    func runtimeItemsData(
        relativeTo configurationURL: URL = MMTMRConfigurationLocation.canonicalURL()
    ) throws -> Data {
        let items = self.items.enumerated().compactMap { index, item in
            item.runtimeJSONValue(sourcePath: "$.items[\(index)]")
        }
            .map { $0.resolvingFilePaths(relativeTo: configurationURL) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(JSONValue.array(items))
    }

    /// Per-item representation used by the Touch Bar diffing layer. `id` stays
    /// out of the legacy decoder input but remains paired with its bytes.
    func runtimeItems(
        relativeTo configurationURL: URL = MMTMRConfigurationLocation.canonicalURL()
    ) throws -> [RuntimeConfigItem] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try items.enumerated().compactMap { index, item in
            let sourcePath = "$.items[\(index)]"
            guard let value = item.runtimeJSONValue(sourcePath: sourcePath) else { return nil }
            let resolved = value.resolvingFilePaths(relativeTo: configurationURL)
            let data = try encoder.encode(resolved)
            var fingerprintData = data
            for path in resolved.referencedFilePaths().sorted() {
                fingerprintData.append(0)
                fingerprintData.append(contentsOf: path.utf8)
                fingerprintData.append(0)
                fingerprintData.append(try Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe]))
            }
            return RuntimeConfigItem(
                id: item.id,
                kind: item.type,
                sourcePath: sourcePath,
                data: data,
                fingerprint: ConfigContentHasher.sha256(fingerprintData)
            )
        }
    }
}

private extension JSONValue {
    func resolvingFilePaths(relativeTo configurationURL: URL) -> JSONValue {
        switch self {
        case let .array(values):
            return .array(values.map { $0.resolvingFilePaths(relativeTo: configurationURL) })
        case let .object(object):
            return .object(object.mapValues { $0.resolvingFilePaths(relativeTo: configurationURL) }.mapValuesWithKey {
                key, value in
                let isPinnedApplicationPath = key == "path" && object["bundleIdentifier"]?.stringValue != nil
                guard (key == "filePath" || key == "executablePath" || isPinnedApplicationPath),
                      let rawPath = value.stringValue else { return value }
                return .string(MMTMRConfigurationLocation.resolveResourcePath(rawPath, relativeTo: configurationURL).path)
            })
        default:
            return self
        }
    }

    func referencedFilePaths() -> Set<String> {
        switch self {
        case let .array(values):
            return values.reduce(into: Set<String>()) { $0.formUnion($1.referencedFilePaths()) }
        case let .object(object):
            return object.reduce(into: Set<String>()) { result, entry in
                if entry.key == "filePath", let path = entry.value.stringValue {
                    result.insert(path)
                } else {
                    result.formUnion(entry.value.referencedFilePaths())
                }
            }
        default:
            return []
        }
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    func mapValuesWithKey(_ transform: (String, JSONValue) -> JSONValue) -> [String: JSONValue] {
        reduce(into: [:]) { result, entry in
            result[entry.key] = transform(entry.key, entry.value)
        }
    }
}

struct RuntimeConfigItem: Equatable, Sendable {
    let id: String
    let kind: String
    let sourcePath: String
    let data: Data
    let fingerprint: String
}

struct ConfigItem: Codable, Equatable, Sendable {
    private static let reservedKeys = Set([
        "id", "type", "actions", "notes", "editorName", "enabled", "items",
    ])

    var id: String
    var type: String
    var actions: [ConfigAction]
    var notes: String?
    var editorName: String?
    var enabled: Bool?
    var items: [ConfigItem]?
    var properties: [String: JSONValue]

    init(
        id: String,
        type: String,
        actions: [ConfigAction] = [],
        notes: String? = nil,
        editorName: String? = nil,
        enabled: Bool? = nil,
        items: [ConfigItem]? = nil,
        properties: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.type = type
        self.actions = actions
        self.notes = notes
        self.editorName = editorName
        self.enabled = enabled
        self.items = items
        self.properties = properties.filter { !Self.reservedKeys.contains($0.key) }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        id = try container.decode(String.self, forKey: DynamicCodingKey("id"))
        type = try container.decode(String.self, forKey: DynamicCodingKey("type"))
        actions = try container.decodeIfPresent([ConfigAction].self, forKey: DynamicCodingKey("actions")) ?? []
        notes = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("notes"))
        editorName = try container.decodeIfPresent(String.self, forKey: DynamicCodingKey("editorName"))
        enabled = try container.decodeIfPresent(Bool.self, forKey: DynamicCodingKey("enabled"))
        items = try container.decodeIfPresent([ConfigItem].self, forKey: DynamicCodingKey("items"))

        properties = try container.allKeys.reduce(into: [:]) { result, key in
            guard !Self.reservedKeys.contains(key.stringValue) else { return }
            result[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        try container.encode(id, forKey: DynamicCodingKey("id"))
        try container.encode(type, forKey: DynamicCodingKey("type"))
        if !actions.isEmpty {
            try container.encode(actions, forKey: DynamicCodingKey("actions"))
        }
        try container.encodeIfPresent(notes, forKey: DynamicCodingKey("notes"))
        try container.encodeIfPresent(editorName, forKey: DynamicCodingKey("editorName"))
        try container.encodeIfPresent(enabled, forKey: DynamicCodingKey("enabled"))
        try container.encodeIfPresent(items, forKey: DynamicCodingKey("items"))
        for (key, value) in properties {
            try container.encode(value, forKey: DynamicCodingKey(key))
        }
    }

    fileprivate func runtimeJSONValue(includeID: Bool = false, sourcePath: String) -> JSONValue? {
        guard enabled != false else { return nil }
        var object = properties
        if includeID {
            object["id"] = .string(id)
            object["_sourcePath"] = .string(sourcePath)
        }
        object["type"] = .string(type)
        if !actions.isEmpty {
            object["actions"] = .array(actions.map { $0.jsonValue })
        }
        if let items {
            object["items"] = .array(items.enumerated().compactMap { index, item in
                item.runtimeJSONValue(
                    includeID: true,
                    sourcePath: "\(sourcePath).items[\(index)]"
                )
            })
        }
        return .object(object)
    }
}

struct ConfigAction: Codable, Equatable, Sendable {
    var trigger: String
    var action: String
    var parameters: [String: JSONValue]

    init(trigger: String, action: String, parameters: [String: JSONValue] = [:]) {
        self.trigger = trigger
        self.action = action
        self.parameters = parameters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        trigger = try container.decode(String.self, forKey: DynamicCodingKey("trigger"))
        action = try container.decode(String.self, forKey: DynamicCodingKey("action"))
        parameters = try container.allKeys.reduce(into: [:]) { result, key in
            guard key.stringValue != "trigger", key.stringValue != "action" else { return }
            result[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        try container.encode(trigger, forKey: DynamicCodingKey("trigger"))
        try container.encode(action, forKey: DynamicCodingKey("action"))
        for (key, value) in parameters {
            try container.encode(value, forKey: DynamicCodingKey(key))
        }
    }

    fileprivate var jsonValue: JSONValue {
        var object = parameters
        object["trigger"] = .string(trigger)
        object["action"] = .string(action)
        return .object(object)
    }
}
