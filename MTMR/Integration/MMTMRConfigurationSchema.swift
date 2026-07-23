import Foundation

enum MMTMRConfigurationSchema {
    typealias JSON = ServerJSONValue

    static let document: JSON = .object([
        "$schema": .string("https://json-schema.org/draft/2020-12/schema"),
        "$id": .string("https://mmtmr.local/schema/config-v1.json"),
        "title": .string("MMTMR configuration"),
        "type": .string("object"),
        "additionalProperties": .bool(false),
        "required": strings("formatVersion", "items"),
        "properties": .object([
            "formatVersion": .object([
                "type": .string("integer"),
                "const": .number(1),
                "description": .string("Version of the canonical MMTMR JSON format."),
            ]),
            "notes": stringProperty("Free-form configuration notes."),
            "touchBarLayout": reference("#/$defs/touchBarLayout"),
            "items": .object([
                "type": .string("array"),
                "items": reference("#/$defs/item"),
            ]),
        ]),
        "$defs": .object([
            "source": sourceDefinition,
            "action": actionDefinition,
            "pinnedApplication": pinnedApplicationDefinition,
            "touchBarCalibration": touchBarCalibrationDefinition,
            "touchBarLayout": touchBarLayoutDefinition,
            "item": itemDefinition,
        ]),
    ])

    private static let touchBarCalibrationDefinition: JSON = .object([
        "type": .string("object"),
        "additionalProperties": .bool(false),
        "required": strings("centerOffset", "pointsPerMillimeter"),
        "properties": .object([
            "centerOffset": numberProperty(defaultValue: 0, minimum: -300, maximum: 300),
            "pointsPerMillimeter": numberProperty(
                defaultValue: TouchBarCalibrationProfile.defaultPointsPerMillimeter,
                minimum: 2,
                maximum: 8
            ),
        ]),
    ])

    private static let touchBarLayoutDefinition: JSON = .object([
        "type": .string("object"),
        "additionalProperties": .bool(false),
        "required": strings("centerReference", "calibrations"),
        "properties": .object([
            "centerReference": enumProperty("touchBar", "chassis", defaultValue: "touchBar"),
            "calibrations": .object([
                "type": .string("object"),
                "additionalProperties": reference("#/$defs/touchBarCalibration"),
                "default": .object([:]),
            ]),
        ]),
    ])

    private static let sourceDefinition: JSON = .object([
        "type": .string("object"),
        "additionalProperties": .bool(false),
        "minProperties": .number(1),
        "maxProperties": .number(1),
        "properties": .object([
            "filePath": stringProperty("Absolute, ~/ or configuration-relative path."),
            "base64": stringProperty("Base64-encoded content."),
            "inline": stringProperty("Inline UTF-8 content."),
        ]),
    ])

    private static let actionDefinition: JSON = .object([
        "oneOf": .array([
            actionVariant("typeText", title: "Type Unicode text", fields: [
                "text": stringProperty("Text injected with a native CGEvent."),
            ], required: ["text"]),
            actionVariant("keyPress", title: "Key press", fields: [
                "keycode": integerProperty(minimum: 0, maximum: Double(UInt16.max)),
            ], required: ["keycode"]),
            actionVariant("hidKey", title: "Media/HID key", fields: [
                "keycode": integerProperty(minimum: 0, maximum: 255),
            ], required: ["keycode"]),
            actionVariant("appleScript", title: "AppleScript", fields: [
                "actionAppleScript": reference("#/$defs/source"),
            ], required: ["actionAppleScript"]),
            actionVariant("shellScript", title: "Shell script", fields: [
                "executablePath": stringProperty("Executable path."),
                "shellArguments": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                    "default": .array([]),
                ]),
            ], required: ["executablePath"]),
            actionVariant("openUrl", title: "Open URL", fields: [
                "url": stringProperty("URL opened by macOS."),
            ], required: ["url"]),
        ]),
    ])

    private static let pinnedApplicationDefinition: JSON = .object([
        "title": .string("Pinned application"),
        "type": .string("object"),
        "additionalProperties": .bool(false),
        "required": strings("bundleIdentifier"),
        "properties": .object([
            "bundleIdentifier": .object([
                "type": .string("string"),
                "minLength": .number(1),
                "description": .string("Stable macOS application bundle identifier."),
            ]),
            "path": stringProperty("Optional application path, supporting ~ and configuration-relative paths."),
            "label": stringProperty("Optional editor and accessibility label."),
        ]),
    ])

    private static let itemDefinition: JSON = .object([
        "oneOf": .array([
            itemVariant("staticButton", title: "Static button", fields: [
                "title": stringProperty("Button label.", defaultValue: "Button"),
            ], required: ["title"]),
            itemVariant("appleScriptTitledButton", title: "AppleScript", fields: [
                "source": reference("#/$defs/source"),
                "refreshInterval": numberProperty(defaultValue: 1800, minimum: 0.001),
                "alternativeImages": .object([
                    "type": .string("object"),
                    "additionalProperties": reference("#/$defs/source"),
                ]),
            ], required: ["source"]),
            itemVariant("shellScriptTitledButton", title: "Shell title", fields: [
                "source": reference("#/$defs/source"),
                "refreshInterval": numberProperty(defaultValue: 1800, minimum: 0.001),
            ], required: ["source"]),
            itemVariant("timeButton", title: "Time", fields: [
                "formatTemplate": stringProperty("DateFormatter pattern.", defaultValue: "HH:mm"),
                "timeZone": stringProperty("Optional IANA time zone."),
                "locale": stringProperty("Optional locale identifier."),
            ]),
            itemVariant("battery", title: "Battery"),
            itemVariant("cpu", title: "CPU usage", fields: [
                "refreshInterval": systemUsageRefreshProperty,
                "bordered": systemUsageLegacyBorderedProperty,
                "actions": systemUsageLegacyActionsProperty,
            ], excludedCommonFields: systemUsageExcludedFields),
            itemVariant("memory", title: "Memory usage", fields: [
                "refreshInterval": systemUsageRefreshProperty,
                "bordered": systemUsageLegacyBorderedProperty,
                "actions": systemUsageLegacyActionsProperty,
            ], excludedCommonFields: systemUsageExcludedFields),
            itemVariant("dock", title: "Dock", fields: [
                "autoResize": boolProperty(defaultValue: true),
                "filter": stringProperty("Application bundle-id regular expression."),
            ]),
            itemVariant("pinnedDock", title: "Pinned applications", fields: [
                "autoResize": boolProperty(defaultValue: true),
                "applications": .object([
                    "type": .string("array"),
                    "items": reference("#/$defs/pinnedApplication"),
                    "default": .array([]),
                ]),
                "showRunningIndicator": boolProperty(defaultValue: true),
                "longPressAction": enumProperty("none", "quit", defaultValue: "quit"),
                "spacing": numberProperty(defaultValue: 1, minimum: -12, maximum: 20),
            ], required: ["applications"]),
            itemVariant("volume", title: "Volume"),
            itemVariant("brightness", title: "Brightness", fields: ["refreshInterval": numberProperty(defaultValue: 0.5, minimum: 0.001)]),
            itemVariant("weather", title: "Weather", fields: [
                "refreshInterval": numberProperty(defaultValue: 1800, minimum: 0.001),
                "units": enumProperty("metric", "imperial", defaultValue: "metric"),
                "api_key": stringProperty("Weather provider API key."),
                "icon_type": enumProperty("text", "images", defaultValue: "text"),
            ]),
            itemVariant("yandexWeather", title: "Yandex weather", fields: ["refreshInterval": numberProperty(defaultValue: 1800, minimum: 0.001)]),
            itemVariant("currency", title: "Currency", fields: [
                "refreshInterval": numberProperty(defaultValue: 600, minimum: 0.001),
                "from": stringProperty("Source currency.", defaultValue: "RUB"),
                "to": stringProperty("Target currency.", defaultValue: "USD"),
                "full": boolProperty(defaultValue: false),
            ]),
            itemVariant("inputsource", title: "Input source"),
            itemVariant("music", title: "Music", fields: [
                "refreshInterval": numberProperty(defaultValue: 5, minimum: 0.001),
                "disableMarquee": boolProperty(defaultValue: false),
            ]),
            itemVariant("group", title: "Group", fields: [
                "title": stringProperty("Displayed title of the button that opens the group.", defaultValue: "Groupe"),
                "items": .object([
                    "type": .string("array"),
                    "items": reference("#/$defs/item"),
                    "default": .array([]),
                ]),
            ], required: ["items"]),
            itemVariant("nightShift", title: "Night Shift"),
            itemVariant("dnd", title: "Do Not Disturb"),
            itemVariant("pomodoro", title: "Pomodoro", fields: [
                "workTime": numberProperty(defaultValue: 1500, minimum: 0.001),
                "restTime": numberProperty(defaultValue: 600, minimum: 0.001),
            ]),
            itemVariant("network", title: "Network", fields: [
                "flip": boolProperty(defaultValue: false),
                "units": enumProperty("dynamic", "bytes", "bits", defaultValue: "dynamic"),
            ]),
            itemVariant("darkMode", title: "Dark mode"),
            itemVariant("swipe", title: "Swipe", fields: [
                "direction": enumProperty("left", "right", defaultValue: "right"),
                "fingers": integerProperty(defaultValue: 2, minimum: 2, maximum: 4),
                "minOffset": numberProperty(defaultValue: 0, minimum: 0, maximum: Double(Float.greatestFiniteMagnitude)),
                "sourceApple": reference("#/$defs/source"),
                "sourceBash": reference("#/$defs/source"),
            ], required: ["direction", "fingers"]),
            itemVariant("upnext", title: "Upcoming events", fields: [
                "refreshInterval": numberProperty(defaultValue: 60, minimum: 0.001),
                "from": numberProperty(defaultValue: 0),
                "to": numberProperty(defaultValue: 12),
                "maxToShow": integerProperty(defaultValue: 3, minimum: 1, maximum: Double(Int32.max)),
                "autoResize": boolProperty(defaultValue: false),
            ]),
        ] + predefinedItemTypes.map { itemVariant($0, title: $0) }),
    ])

    private static let predefinedItemTypes = [
        "escape", "delete", "brightnessUp", "brightnessDown", "illuminationUp",
        "illuminationDown", "volumeDown", "volumeUp", "mute", "previous", "play",
        "next", "sleep", "displaySleep", "exitTouchbar", "close",
    ]

    private static func itemVariant(
        _ type: String,
        title: String,
        fields: [String: JSON] = [:],
        required: [String] = [],
        excludedCommonFields: Set<String> = []
    ) -> JSON {
        var properties = commonItemProperties(includeActions: !nonActionableItemTypes.contains(type))
        excludedCommonFields.forEach { properties.removeValue(forKey: $0) }
        properties["type"] = .object(["const": .string(type)])
        fields.forEach { properties[$0.key] = $0.value }
        return .object([
            "title": .string(title),
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "required": .array(([
                "id", "type",
            ] + required).map(JSON.string)),
            "properties": .object(properties),
        ])
    }

    private static let nonActionableItemTypes: Set<String> = ["cpu", "memory", "dock", "pinnedDock", "volume", "brightness", "group", "swipe", "upnext"]

    private static let systemUsageExcludedFields: Set<String> = [
        "actions", "width", "image", "bordered", "background", "title",
    ]

    private static let systemUsageRefreshProperty: JSON = .object([
        "type": .string("number"),
        "default": .number(2),
        "minimum": .number(1),
        "maximum": .number(30),
        "description": .string("Seconds represented by each new one-pixel graph column."),
    ])

    private static let systemUsageLegacyBorderedProperty: JSON = .object([
        "type": .string("boolean"),
        "deprecated": .bool(true),
        "description": .string("Legacy compatibility field; ignored by the graph."),
    ])

    private static let systemUsageLegacyActionsProperty: JSON = .object([
        "type": .string("array"),
        "items": reference("#/$defs/action"),
        "maxItems": .number(0),
        "deprecated": .bool(true),
        "description": .string("Legacy empty actions array; ignored by the graph."),
    ])

    private static func commonItemProperties(includeActions: Bool) -> [String: JSON] {
        var properties: [String: JSON] = [
            "id": .object(["type": .string("string"), "minLength": .number(1)]),
            "type": .object(["type": .string("string")]),
            "align": enumProperty("left", "center", "right", defaultValue: "center"),
            "width": numberProperty(minimum: 0),
            "image": reference("#/$defs/source"),
            "bordered": boolProperty(defaultValue: true),
            "background": stringProperty("Hex color."),
            "title": stringProperty("Displayed title."),
            "matchAppId": stringProperty("Frontmost application bundle-id regex."),
            "notes": stringProperty("Editor-only notes."),
            "editorName": stringProperty("Editor-only display name; never forwarded to the Touch Bar runtime."),
            "enabled": boolProperty(defaultValue: true),
        ]
        if includeActions {
            properties["actions"] = .object([
                "type": .string("array"),
                "items": reference("#/$defs/action"),
                "default": .array([]),
            ])
        }
        return properties
    }

    private static func actionVariant(
        _ action: String,
        title: String,
        fields: [String: JSON],
        required: [String]
    ) -> JSON {
        var properties: [String: JSON] = [
            "trigger": enumProperty("singleTap", "doubleTap", "tripleTap", "longTap", defaultValue: "singleTap"),
            "action": .object(["const": .string(action)]),
        ]
        fields.forEach { properties[$0.key] = $0.value }
        return .object([
            "title": .string(title),
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "required": .array((["trigger", "action"] + required).map(JSON.string)),
            "properties": .object(properties),
        ])
    }

    private static func reference(_ value: String) -> JSON {
        .object(["$ref": .string(value)])
    }

    private static func strings(_ values: String...) -> JSON {
        .array(values.map(JSON.string))
    }

    private static func stringProperty(_ description: String? = nil, defaultValue: String? = nil) -> JSON {
        var value: [String: JSON] = ["type": .string("string")]
        if let description { value["description"] = .string(description) }
        if let defaultValue { value["default"] = .string(defaultValue) }
        return .object(value)
    }

    private static func numberProperty(
        defaultValue: Double? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil
    ) -> JSON {
        var value: [String: JSON] = ["type": .string("number")]
        if let defaultValue { value["default"] = .number(defaultValue) }
        if let minimum { value["minimum"] = .number(minimum) }
        if let maximum { value["maximum"] = .number(maximum) }
        return .object(value)
    }

    private static func integerProperty(
        defaultValue: Double? = nil,
        minimum: Double? = nil,
        maximum: Double? = nil
    ) -> JSON {
        var value: [String: JSON] = ["type": .string("integer")]
        if let defaultValue { value["default"] = .number(defaultValue) }
        if let minimum { value["minimum"] = .number(minimum) }
        if let maximum { value["maximum"] = .number(maximum) }
        return .object(value)
    }

    private static func boolProperty(defaultValue: Bool? = nil) -> JSON {
        var value: [String: JSON] = ["type": .string("boolean")]
        if let defaultValue { value["default"] = .bool(defaultValue) }
        return .object(value)
    }

    private static func enumProperty(_ values: String..., defaultValue: String? = nil) -> JSON {
        var value: [String: JSON] = [
            "type": .string("string"),
            "enum": .array(values.map(JSON.string)),
        ]
        if let defaultValue { value["default"] = .string(defaultValue) }
        return .object(value)
    }
}
