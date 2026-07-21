import Foundation

struct ConfigValidator {
    static let supportedItemTypes: Set<String> = [
        "staticButton", "appleScriptTitledButton", "shellScriptTitledButton", "timeButton",
        "battery", "cpu", "memory", "dock", "pinnedDock", "volume", "brightness", "weather", "yandexWeather",
        "currency", "inputsource", "music", "group", "nightShift", "dnd", "pomodoro",
        "network", "darkMode", "swipe", "upnext", "escape", "delete", "brightnessUp",
        "brightnessDown", "illuminationUp", "illuminationDown", "volumeDown", "volumeUp",
        "mute", "previous", "play", "next", "sleep", "displaySleep", "exitTouchbar", "close"
    ]

    static let supportedActionTypes: Set<String> = [
        "hidKey", "keyPress", "typeText", "appleScript", "shellScript", "openUrl"
    ]

    private static let commonItemKeys: Set<String> = [
        "id", "type", "actions", "notes", "editorName", "enabled", "width", "image", "align",
        "bordered", "background", "title", "matchAppId"
    ]

    private static let itemSpecificKeys: [String: Set<String>] = [
        "appleScriptTitledButton": ["source", "refreshInterval", "alternativeImages"],
        "shellScriptTitledButton": ["source", "refreshInterval"],
        "timeButton": ["formatTemplate", "timeZone", "locale"],
        "cpu": ["refreshInterval"],
        "memory": ["refreshInterval"],
        "dock": ["autoResize", "filter"],
        "pinnedDock": ["autoResize", "applications", "showRunningIndicator", "longPressAction", "spacing"],
        "brightness": ["refreshInterval"],
        "weather": ["refreshInterval", "units", "api_key", "icon_type"],
        "yandexWeather": ["refreshInterval"],
        "currency": ["refreshInterval", "from", "to", "full"],
        "music": ["refreshInterval", "disableMarquee"],
        "group": ["items"],
        "pomodoro": ["workTime", "restTime"],
        "network": ["flip", "units"],
        "swipe": ["direction", "fingers", "minOffset", "sourceApple", "sourceBash"],
        "upnext": ["from", "to", "maxToShow", "autoResize", "refreshInterval"],
    ]

    private static let itemExcludedKeys: [String: Set<String>] = [
        "cpu": ["width", "image", "background", "title"],
        "memory": ["width", "image", "background", "title"],
    ]

    private static let allItemKeys = itemSpecificKeys.values.reduce(commonItemKeys, { $0.union($1) })
    private static let nonActionableItemTypes: Set<String> = ["cpu", "memory", "dock", "pinnedDock", "volume", "brightness", "group", "swipe", "upnext"]

    private static let stringItemKeys: Set<String> = [
        "notes", "editorName", "background", "title", "matchAppId", "timeZone", "units", "api_key",
        "icon_type", "formatTemplate", "locale", "filter", "direction", "longPressAction"
    ]
    private static let numberItemKeys: Set<String> = [
        "width", "refreshInterval", "workTime", "restTime", "minOffset", "maxToShow", "fingers", "spacing"
    ]
    private static let boolItemKeys: Set<String> = [
        "enabled", "bordered", "full", "flip", "autoResize", "disableMarquee", "showRunningIndicator"
    ]
    private static let sourceItemKeys: Set<String> = ["source", "image", "sourceApple", "sourceBash"]

    func validate(root: JSONValue) -> [ConfigurationDiagnostic] {
        var diagnostics: [ConfigurationDiagnostic] = []
        guard case let .object(object) = root else {
            return [error("config.rootType", "$", "Configuration root must be an object.")]
        }

        let rootKeys = Set(["formatVersion", "notes", "items"])
        for key in object.keys.sorted() where !rootKeys.contains(key) {
            diagnostics.append(error("config.unknownKey", path("$", key), "Unknown top-level property ‘\(key)’.") )
        }

        if case let .number(version)? = object["formatVersion"] {
            if version.rounded() != version || version != Double(ConfigDocument.currentFormatVersion) {
                diagnostics.append(error(
                    "config.unsupportedVersion",
                    "$.formatVersion",
                    "formatVersion must be the integer \(ConfigDocument.currentFormatVersion)."
                ))
            }
        } else {
            diagnostics.append(error("config.formatVersion", "$.formatVersion", "formatVersion must be the integer 1."))
        }

        if let notes = object["notes"], notes.stringValue == nil {
            diagnostics.append(typeError("$.notes", expected: "a string"))
        }

        guard case let .array(items)? = object["items"] else {
            diagnostics.append(error("config.items", "$.items", "items must be an array."))
            return diagnostics
        }

        var seenIDs = Set<String>()
        validate(items: items, path: "$.items", seenIDs: &seenIDs, diagnostics: &diagnostics)
        return diagnostics
    }

    private func validate(
        items: [JSONValue],
        path itemsPath: String,
        seenIDs: inout Set<String>,
        diagnostics: inout [ConfigurationDiagnostic]
    ) {
        for (index, itemValue) in items.enumerated() {
            let itemPath = "\(itemsPath)[\(index)]"
            guard case let .object(item) = itemValue else {
                diagnostics.append(typeError(itemPath, expected: "an object"))
                continue
            }

            if case let .string(id)? = item["id"], !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !seenIDs.insert(id).inserted {
                    diagnostics.append(error("config.duplicateID", "\(itemPath).id", "Item id ‘\(id)’ is used more than once."))
                }
            } else {
                diagnostics.append(error("config.itemID", "\(itemPath).id", "Every item must have a non-empty string id."))
            }

            var itemType: String?
            if case let .string(type)? = item["type"] {
                itemType = type
                if !Self.supportedItemTypes.contains(type) {
                    diagnostics.append(error("config.unknownItemType", "\(itemPath).type", "Unknown item type ‘\(type)’.") )
                }
            } else {
                diagnostics.append(error("config.itemType", "\(itemPath).type", "Every item must have a string type."))
            }

            let allowedItemKeys: Set<String>
            if let itemType, Self.supportedItemTypes.contains(itemType) {
                allowedItemKeys = Self.commonItemKeys
                    .union(Self.itemSpecificKeys[itemType] ?? [])
                    .subtracting(Self.itemExcludedKeys[itemType] ?? [])
            } else {
                allowedItemKeys = Self.allItemKeys
            }
            for key in item.keys.sorted() where !allowedItemKeys.contains(key) {
                diagnostics.append(error(
                    "config.unknownKey",
                    path(itemPath, key),
                    "Property ‘\(key)’ is not declared for item type ‘\(itemType ?? "unknown")’."
                ))
            }

            for key in Self.stringItemKeys where item[key] != nil && item[key]?.stringValue == nil {
                diagnostics.append(typeError(path(itemPath, key), expected: "a string"))
            }
            for key in Self.numberItemKeys where item[key] != nil && item[key]?.numberValue == nil {
                diagnostics.append(typeError(path(itemPath, key), expected: "a number"))
            }
            for key in Self.boolItemKeys where item[key] != nil && item[key]?.boolValue == nil {
                diagnostics.append(typeError(path(itemPath, key), expected: "a boolean"))
            }

            if let width = item["width"]?.numberValue, width < 0 {
                diagnostics.append(error("config.range", "\(itemPath).width", "width must be zero or greater."))
            }
            if itemType == "pinnedDock",
               let spacing = item["spacing"]?.numberValue,
               spacing < -12 || spacing > 20 {
                diagnostics.append(error(
                    "config.range",
                    "\(itemPath).spacing",
                    "pinnedDock spacing must be from -12 through 20 points."
                ))
            }
            if let interval = item["refreshInterval"]?.numberValue, interval < 0.001 {
                diagnostics.append(error("config.range", "\(itemPath).refreshInterval", "refreshInterval must be at least 0.001 seconds."))
            }
            if let itemType,
               ["cpu", "memory"].contains(itemType),
               let interval = item["refreshInterval"]?.numberValue,
               interval < 1 || interval > 30 {
                diagnostics.append(error(
                    "config.range",
                    "\(itemPath).refreshInterval",
                    "\(itemType) refreshInterval must be from 1 through 30 seconds."
                ))
            }
            for key in ["workTime", "restTime"] {
                if let value = item[key]?.numberValue, value < 0.001 {
                    diagnostics.append(error("config.range", path(itemPath, key), "\(key) must be at least 0.001 seconds."))
                }
            }
            if let offset = item["minOffset"]?.numberValue,
               offset < 0 || offset > Double(Float.greatestFiniteMagnitude) {
                diagnostics.append(error("config.range", "\(itemPath).minOffset", "minOffset must be a non-negative Float value."))
            }
            if let maximum = item["maxToShow"]?.numberValue,
               maximum.rounded() != maximum || maximum < 1 || maximum > Double(Int32.max) {
                diagnostics.append(error("config.range", "\(itemPath).maxToShow", "maxToShow must be a positive integer."))
            }

            if let align = item["align"] {
                if let value = align.stringValue, ["left", "center", "right"].contains(value) {
                    // Valid alignment.
                } else {
                    diagnostics.append(error("config.align", "\(itemPath).align", "align must be left, center, or right."))
                }
            }

            if let pattern = item["matchAppId"]?.stringValue {
                do {
                    _ = try NSRegularExpression(pattern: pattern)
                } catch {
                    diagnostics.append(self.error(
                        "config.matchAppId",
                        "\(itemPath).matchAppId",
                        "matchAppId must be a valid regular expression."
                    ))
                }
            }

            if itemType == "currency" {
                for key in ["from", "to"] where item[key] != nil && item[key]?.stringValue == nil {
                    diagnostics.append(typeError(path(itemPath, key), expected: "a string"))
                }
            } else if itemType == "upnext" {
                for key in ["from", "to"] where item[key] != nil && item[key]?.numberValue == nil {
                    diagnostics.append(typeError(path(itemPath, key), expected: "a number"))
                }
            }

            if let filter = item["filter"]?.stringValue,
               (try? NSRegularExpression(pattern: filter)) == nil {
                diagnostics.append(error("config.filter", "\(itemPath).filter", "filter must be a valid regular expression."))
            }

            if itemType == "pinnedDock" {
                validatePinnedApplications(
                    item["applications"],
                    path: "\(itemPath).applications",
                    diagnostics: &diagnostics
                )
                if let longPressAction = item["longPressAction"]?.stringValue,
                   !["none", "quit"].contains(longPressAction) {
                    diagnostics.append(error(
                        "config.enum",
                        "\(itemPath).longPressAction",
                        "longPressAction must be none or quit."
                    ))
                }
            }

            if let identifier = item["timeZone"]?.stringValue,
               TimeZone(identifier: identifier) == nil,
               TimeZone(abbreviation: identifier) == nil {
                diagnostics.append(error("config.timeZone", "\(itemPath).timeZone", "timeZone must be a valid IANA identifier or abbreviation."))
            }

            if itemType == "weather", let units = item["units"]?.stringValue,
               !["metric", "imperial"].contains(units) {
                diagnostics.append(error("config.enum", "\(itemPath).units", "weather units must be metric or imperial."))
            }
            if itemType == "network", let units = item["units"]?.stringValue,
               !["dynamic", "bytes", "bits"].contains(units) {
                diagnostics.append(error("config.enum", "\(itemPath).units", "network units must be dynamic, bytes, or bits."))
            }
            if itemType == "weather", let iconType = item["icon_type"]?.stringValue,
               !["text", "images"].contains(iconType) {
                diagnostics.append(error("config.enum", "\(itemPath).icon_type", "icon_type must be text or images."))
            }

            for key in Self.sourceItemKeys {
                if let source = item[key] {
                    validate(source: source, path: path(itemPath, key), diagnostics: &diagnostics)
                }
            }
            if let alternatives = item["alternativeImages"] {
                if case let .object(images) = alternatives {
                    for (name, source) in images {
                        validate(source: source, path: path(path(itemPath, "alternativeImages"), name), diagnostics: &diagnostics)
                    }
                } else {
                    diagnostics.append(typeError("\(itemPath).alternativeImages", expected: "an object"))
                }
            }

            if let actionsValue = item["actions"] {
                if case let .array(actions) = actionsValue {
                    let isEmptyLegacySystemUsageActions = actions.isEmpty
                        && itemType.map { ["cpu", "memory"].contains($0) } == true
                    if let itemType,
                       Self.nonActionableItemTypes.contains(itemType),
                       !isEmptyLegacySystemUsageActions {
                        diagnostics.append(error(
                            "config.unsupportedActions",
                            "\(itemPath).actions",
                            "Item type ‘\(itemType)’ does not declare an actions property."
                        ))
                    }
                    validate(actions: actions, path: "\(itemPath).actions", diagnostics: &diagnostics)
                } else {
                    diagnostics.append(typeError("\(itemPath).actions", expected: "an array"))
                }
            }

            if let nestedValue = item["items"] {
                if case let .array(nestedItems) = nestedValue {
                    validate(items: nestedItems, path: "\(itemPath).items", seenIDs: &seenIDs, diagnostics: &diagnostics)
                } else {
                    diagnostics.append(typeError("\(itemPath).items", expected: "an array"))
                }
            }

            if let itemType {
                validateRequiredFields(
                    for: itemType,
                    item: item,
                    path: itemPath,
                    diagnostics: &diagnostics
                )
            }
        }
    }

    private func validateRequiredFields(
        for itemType: String,
        item: [String: JSONValue],
        path itemPath: String,
        diagnostics: inout [ConfigurationDiagnostic]
    ) {
        switch itemType {
        case "staticButton":
            if item["title"]?.stringValue == nil {
                diagnostics.append(error("config.required", "\(itemPath).title", "staticButton requires a string title."))
            }
        case "appleScriptTitledButton", "shellScriptTitledButton":
            if item["source"] == nil {
                diagnostics.append(error("config.required", "\(itemPath).source", "\(itemType) requires a source."))
            }
        case "group":
            if item["items"]?.arrayValue == nil {
                diagnostics.append(error("config.required", "\(itemPath).items", "group requires an items array."))
            }
        case "pinnedDock":
            if item["applications"]?.arrayValue == nil {
                diagnostics.append(error(
                    "config.required",
                    "\(itemPath).applications",
                    "pinnedDock requires an applications array."
                ))
            }
        case "swipe":
            if let direction = item["direction"]?.stringValue, ["left", "right"].contains(direction) {
                // Valid swipe direction.
            } else {
                diagnostics.append(error("config.required", "\(itemPath).direction", "swipe direction must be left or right."))
            }
            if let fingers = item["fingers"]?.numberValue,
               fingers.rounded() == fingers,
               (2...4).contains(fingers) {
                // BasicView installs recognizers for two, three, and four fingers.
            } else {
                diagnostics.append(error("config.required", "\(itemPath).fingers", "swipe fingers must be the integer 2, 3, or 4."))
            }
        default:
            break
        }
    }

    private func validatePinnedApplications(
        _ value: JSONValue?,
        path applicationsPath: String,
        diagnostics: inout [ConfigurationDiagnostic]
    ) {
        guard let value else { return }
        guard case let .array(applications) = value else {
            diagnostics.append(typeError(applicationsPath, expected: "an array"))
            return
        }

        let allowedKeys = Set(["bundleIdentifier", "path", "label"])
        var seenBundleIdentifiers = Set<String>()
        for (index, value) in applications.enumerated() {
            let applicationPath = "\(applicationsPath)[\(index)]"
            guard case let .object(application) = value else {
                diagnostics.append(typeError(applicationPath, expected: "an object"))
                continue
            }
            for key in application.keys.sorted() where !allowedKeys.contains(key) {
                diagnostics.append(error(
                    "config.unknownKey",
                    path(applicationPath, key),
                    "Property ‘\(key)’ is not declared for a pinned application."
                ))
            }

            if let bundleIdentifier = application["bundleIdentifier"]?.stringValue,
               !bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !seenBundleIdentifiers.insert(bundleIdentifier).inserted {
                    diagnostics.append(error(
                        "config.duplicateApplication",
                        "\(applicationPath).bundleIdentifier",
                        "Application ‘\(bundleIdentifier)’ is listed more than once in this pinnedDock."
                    ))
                }
            } else {
                diagnostics.append(error(
                    "config.required",
                    "\(applicationPath).bundleIdentifier",
                    "Every pinned application requires a non-empty bundleIdentifier."
                ))
            }

            for key in ["path", "label"] where application[key] != nil && application[key]?.stringValue == nil {
                diagnostics.append(typeError(path(applicationPath, key), expected: "a string"))
            }
            if let appPath = application["path"]?.stringValue,
               appPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                diagnostics.append(error(
                    "config.required",
                    "\(applicationPath).path",
                    "Application path must not be empty when provided."
                ))
            }
        }
    }

    private func validate(
        actions: [JSONValue],
        path actionsPath: String,
        diagnostics: inout [ConfigurationDiagnostic]
    ) {
        for (index, actionValue) in actions.enumerated() {
            let actionPath = "\(actionsPath)[\(index)]"
            guard case let .object(action) = actionValue else {
                diagnostics.append(typeError(actionPath, expected: "an object"))
                continue
            }

            guard case let .string(trigger)? = action["trigger"] else {
                diagnostics.append(error("config.actionTrigger", "\(actionPath).trigger", "Action trigger must be a string."))
                continue
            }
            if !["singleTap", "doubleTap", "tripleTap", "longTap"].contains(trigger) {
                diagnostics.append(error("config.actionTrigger", "\(actionPath).trigger", "Unknown action trigger ‘\(trigger)’.") )
            }

            guard case let .string(actionType)? = action["action"] else {
                diagnostics.append(error("config.actionType", "\(actionPath).action", "Action type must be a string."))
                continue
            }
            guard Self.supportedActionTypes.contains(actionType) else {
                diagnostics.append(error("config.unknownActionType", "\(actionPath).action", "Unknown action type ‘\(actionType)’.") )
                continue
            }

            var allowed = Set(["trigger", "action"])
            switch actionType {
            case "hidKey":
                allowed.insert("keycode")
                if let number = action["keycode"]?.numberValue,
                   number.rounded() == number,
                   (0...255).contains(number) {
                    // HIDPostAuxKey converts this value to UInt8.
                } else {
                    diagnostics.append(error("config.actionKeycode", "\(actionPath).keycode", "hidKey keycode must be an integer from 0 through 255."))
                }
            case "keyPress":
                allowed.insert("keycode")
                if let number = action["keycode"]?.numberValue,
                   number.rounded() == number,
                   (0...Double(UInt16.max)).contains(number) {
                    // GenericKeyPress converts this value to CGKeyCode (UInt16).
                } else {
                    diagnostics.append(error("config.actionKeycode", "\(actionPath).keycode", "keyPress keycode must be an integer from 0 through 65535."))
                }
            case "typeText":
                allowed.insert("text")
                if action["text"]?.stringValue == nil {
                    diagnostics.append(typeError("\(actionPath).text", expected: "a string"))
                }
            case "appleScript":
                allowed.insert("actionAppleScript")
                if let source = action["actionAppleScript"] {
                    validate(source: source, path: "\(actionPath).actionAppleScript", diagnostics: &diagnostics)
                } else {
                    diagnostics.append(error("config.actionAppleScript", "\(actionPath).actionAppleScript", "appleScript actions require actionAppleScript."))
                }
            case "shellScript":
                allowed.formUnion(["executablePath", "shellArguments"])
                if let executable = action["executablePath"]?.stringValue,
                   !executable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Resolved against the configuration directory before runtime.
                } else {
                    diagnostics.append(typeError("\(actionPath).executablePath", expected: "a string"))
                }
                if let arguments = action["shellArguments"] {
                    guard case let .array(values) = arguments, values.allSatisfy({ $0.stringValue != nil }) else {
                        diagnostics.append(typeError("\(actionPath).shellArguments", expected: "an array of strings"))
                        break
                    }
                }
            case "openUrl":
                allowed.insert("url")
                if let rawURL = action["url"]?.stringValue,
                   !rawURL.isEmpty,
                   URL(string: rawURL) != nil {
                    // Valid URL representation.
                } else {
                    diagnostics.append(typeError("\(actionPath).url", expected: "a string"))
                }
            default:
                break
            }

            for key in action.keys.sorted() where !allowed.contains(key) {
                diagnostics.append(error("config.unknownKey", path(actionPath, key), "Unknown property ‘\(key)’ for a \(actionType) action."))
            }
        }
    }

    private func validate(
        source: JSONValue,
        path sourcePath: String,
        diagnostics: inout [ConfigurationDiagnostic]
    ) {
        guard case let .object(object) = source else {
            diagnostics.append(typeError(sourcePath, expected: "an object"))
            return
        }
        let allowed = Set(["filePath", "base64", "inline"])
        for key in object.keys where !allowed.contains(key) {
            diagnostics.append(error("config.unknownKey", path(sourcePath, key), "Unknown source property ‘\(key)’.") )
        }
        let populated = allowed.filter { object[$0]?.stringValue != nil }
        if populated.count != 1 {
            diagnostics.append(error(
                "config.source",
                sourcePath,
                "A source must contain exactly one of filePath, base64, or inline."
            ))
        }
        for key in allowed where object[key] != nil && object[key]?.stringValue == nil {
            diagnostics.append(typeError(path(sourcePath, key), expected: "a string"))
        }
        if let filePath = object["filePath"]?.stringValue,
           filePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            diagnostics.append(error("config.source", "\(sourcePath).filePath", "filePath must not be empty."))
        }
        if let encoded = object["base64"]?.stringValue,
           Data(base64Encoded: encoded) == nil {
            diagnostics.append(error("config.sourceBase64", "\(sourcePath).base64", "base64 must contain valid Base64 data."))
        }
    }

    private func path(_ base: String, _ key: String) -> String {
        "\(base).\(key)"
    }

    private func error(_ code: String, _ path: String, _ message: String) -> ConfigurationDiagnostic {
        ConfigurationDiagnostic(code: code, path: path, message: message)
    }

    private func typeError(_ path: String, expected: String) -> ConfigurationDiagnostic {
        error("config.type", path, "Expected \(expected).")
    }
}

/// Resolves every disk-backed source before a configuration is committed. The
/// runtime still receives paths (so existing MTMR widgets keep their behavior),
/// but a missing/unreadable resource can no longer be persisted as a valid bar.
struct ConfigResourceValidator {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func validate(document: ConfigDocument, relativeTo configurationURL: URL) -> [ConfigurationDiagnostic] {
        var diagnostics: [ConfigurationDiagnostic] = []
        validate(
            items: document.items,
            path: "$.items",
            relativeTo: configurationURL,
            diagnostics: &diagnostics
        )
        return diagnostics
    }

    private func validate(
        items: [ConfigItem],
        path itemsPath: String,
        relativeTo configurationURL: URL,
        diagnostics: inout [ConfigurationDiagnostic]
    ) {
        for (index, item) in items.enumerated() {
            let itemPath = "\(itemsPath)[\(index)]"
            guard item.enabled != false else { continue }
            for key in ["source", "image", "sourceApple", "sourceBash"] {
                if let source = item.properties[key] {
                    validate(source: source, path: "\(itemPath).\(key)", relativeTo: configurationURL, diagnostics: &diagnostics)
                }
            }

            if case let .object(images)? = item.properties["alternativeImages"] {
                for (name, source) in images {
                    validate(
                        source: source,
                        path: "\(itemPath).alternativeImages.\(name)",
                        relativeTo: configurationURL,
                        diagnostics: &diagnostics
                    )
                }
            }

            for (actionIndex, action) in item.actions.enumerated() {
                let actionPath = "\(itemPath).actions[\(actionIndex)]"
                if let source = action.parameters["actionAppleScript"] {
                    validate(
                        source: source,
                        path: "\(actionPath).actionAppleScript",
                        relativeTo: configurationURL,
                        diagnostics: &diagnostics
                    )
                }
                if action.action == "shellScript",
                   let rawPath = action.parameters["executablePath"]?.stringValue {
                    let url = MMTMRConfigurationLocation.resolveResourcePath(rawPath, relativeTo: configurationURL)
                    var isDirectory: ObjCBool = false
                    if !fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
                        || isDirectory.boolValue
                        || !fileManager.isExecutableFile(atPath: url.path) {
                        diagnostics.append(ConfigurationDiagnostic(
                            code: "config.executable",
                            path: "\(actionPath).executablePath",
                            message: "Executable is missing or not executable: \(url.path)"
                        ))
                    }
                }
            }

            if let nested = item.items {
                validate(
                    items: nested,
                    path: "\(itemPath).items",
                    relativeTo: configurationURL,
                    diagnostics: &diagnostics
                )
            }
        }
    }

    private func validate(
        source: JSONValue,
        path sourcePath: String,
        relativeTo configurationURL: URL,
        diagnostics: inout [ConfigurationDiagnostic]
    ) {
        guard case let .object(object) = source else { return }
        if let encoded = object["base64"]?.stringValue, Data(base64Encoded: encoded) == nil {
            diagnostics.append(ConfigurationDiagnostic(
                code: "config.sourceBase64",
                path: "\(sourcePath).base64",
                message: "The source does not contain valid Base64 data."
            ))
        }
        guard let rawPath = object["filePath"]?.stringValue else { return }

        let url = MMTMRConfigurationLocation.resolveResourcePath(rawPath, relativeTo: configurationURL)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              fileManager.isReadableFile(atPath: url.path) else {
            diagnostics.append(ConfigurationDiagnostic(
                code: "config.resource",
                path: "\(sourcePath).filePath",
                message: "Resource is missing or unreadable: \(url.path)"
            ))
            return
        }

        do {
            _ = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            diagnostics.append(ConfigurationDiagnostic(
                code: "config.resource",
                path: "\(sourcePath).filePath",
                message: "Resource could not be resolved: \(error.localizedDescription)"
            ))
        }
    }
}
