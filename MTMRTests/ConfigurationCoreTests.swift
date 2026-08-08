import XCTest

final class ConfigurationCoreTests: XCTestCase {
    private let codec = ConfigCodec()

    func testStrictDocumentRoundTripsHeterogeneousPropertiesAndTypeText() throws {
        let source = #"""
        {
          "formatVersion": 1,
          "notes": "Unicode configuration",
          "items": [
            {
              "id": "letter-z",
              "type": "staticButton",
              "title": "ž",
              "width": 18,
              "bordered": false,
              "actions": [
                { "trigger": "singleTap", "action": "typeText", "text": "ž👍" }
              ]
            }
          ]
        }
        """#

        let result = codec.decode(source)
        XCTAssertTrue(result.isValid, "\(result.diagnostics)")
        XCTAssertEqual(result.document?.items.first?.properties["title"], .string("ž"))
        XCTAssertEqual(result.document?.items.first?.actions.first?.action, "typeText")
        XCTAssertEqual(result.document?.items.first?.actions.first?.parameters["text"], .string("ž👍"))

        let canonical = try XCTUnwrap(result.canonicalSource)
        XCTAssertTrue(canonical.contains("ž👍"))
        XCTAssertTrue(canonical.hasSuffix("\n"))
        XCTAssertTrue(codec.decode(canonical).isValid)
    }

    func testStrictJSONRejectsCommentsTrailingCommasAndDuplicateKeys() {
        let commented = codec.decode(#"{"formatVersion":1,"items":[] /* nope */}"#)
        XCTAssertEqual(commented.diagnostics.first?.code, "json.comment")

        let trailing = codec.decode(#"{"formatVersion":1,"items":[],}"#)
        XCTAssertEqual(trailing.diagnostics.first?.code, "json.trailingComma")

        let duplicate = codec.decode(#"{"formatVersion":1,"formatVersion":1,"items":[]}"#)
        XCTAssertEqual(duplicate.diagnostics.first?.code, "json.duplicateKey")
        XCTAssertEqual(duplicate.diagnostics.first?.path, "$.formatVersion")
    }

    func testTouchBarChassisCalibrationRoundTripsPerHardwareModel() throws {
        let source = #"""
        {
          "formatVersion": 1,
          "touchBarLayout": {
            "centerReference": "chassis",
            "calibrations": {
              "MacBookPro16,1": {
                "centerOffset": -38.5,
                "pointsPerMillimeter": 4.27
              }
            }
          },
          "items": []
        }
        """#

        let result = codec.decode(source)
        XCTAssertTrue(result.isValid, "\(result.diagnostics)")
        let layout = try XCTUnwrap(result.document?.touchBarLayout)
        XCTAssertEqual(layout.centerReference, .chassis)
        XCTAssertEqual(layout.calibration(for: "MacBookPro16,1")?.centerOffset, -38.5)
        XCTAssertEqual(layout.calibration(for: "MacBookPro16,1")?.pointsPerMillimeter, 4.27)

        let canonical = try XCTUnwrap(result.canonicalSource)
        XCTAssertTrue(canonical.contains(#""touchBarLayout""#))
        XCTAssertTrue(codec.decode(canonical).isValid)
    }

    func testTouchBarChassisCalibrationRejectsUnknownAndUnsafeValues() {
        let result = codec.decode(#"""
        {
          "formatVersion": 1,
          "touchBarLayout": {
            "centerReference": "desk",
            "unknown": true,
            "calibrations": {
              "MacBookPro16,1": {
                "centerOffset": 301,
                "pointsPerMillimeter": 1,
                "typo": 1
              }
            }
          },
          "items": []
        }
        """#)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.diagnostics.contains {
            $0.code == "config.enum" && $0.path == "$.touchBarLayout.centerReference"
        })
        XCTAssertTrue(result.diagnostics.contains {
            $0.code == "config.unknownKey" && $0.path == "$.touchBarLayout.unknown"
        })
        XCTAssertEqual(
            result.diagnostics.filter {
                $0.code == "config.range"
                    && $0.path.hasPrefix("$.touchBarLayout.calibrations.MacBookPro16,1")
            }.count,
            2
        )
        XCTAssertTrue(result.diagnostics.contains {
            $0.code == "config.unknownKey" && $0.path.hasSuffix(".typo")
        })
    }

    func testValidationRejectsUnknownKeysTypesAndDuplicateIDs() {
        let result = codec.decode(#"""
        {
          "formatVersion": 1,
          "items": [
            { "id": "same", "type": "staticButton", "title": "A", "typo": true },
            { "id": "same", "type": "notAWidget" }
          ]
        }
        """#)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.diagnostics.contains(where: { $0.code == "config.unknownKey" && $0.path == "$.items[0].typo" }))
        XCTAssertTrue(result.diagnostics.contains(where: { $0.code == "config.duplicateID" }))
        XCTAssertTrue(result.diagnostics.contains(where: { $0.code == "config.unknownItemType" }))
    }

    func testCPUAndMemoryUsageAreStrictValidatedRuntimeTypes() throws {
        let result = codec.decode(#"""
        {
          "formatVersion": 1,
          "items": [
            { "id": "processor", "type": "cpu", "refreshInterval": 2, "bordered": true, "actions": [] },
            { "id": "ram", "type": "memory", "refreshInterval": 3, "bordered": false, "actions": [] }
          ]
        }
        """#)

        XCTAssertTrue(result.isValid, "\(result.diagnostics)")
        let runtimeItems = try XCTUnwrap(result.document).runtimeItems()
        XCTAssertEqual(runtimeItems.map(\.kind), ["cpu", "memory"])

        let invalid = codec.decode(#"""
        {
          "formatVersion": 1,
          "items": [
            { "id": "ram", "type": "memory", "refreshInterval": "often" },
            { "id": "ram-typo", "type": "memory", "interval": 2 },
            { "id": "decorated", "type": "cpu", "width": 40, "title": "CPU" },
            { "id": "too-fast", "type": "memory", "refreshInterval": 0.5 },
            { "id": "non-empty-actions", "type": "cpu", "actions": [
              { "trigger": "singleTap", "action": "typeText", "text": "x" }
            ] }
          ]
        }
        """#)
        XCTAssertTrue(invalid.diagnostics.contains { $0.code == "config.type" && $0.path.hasSuffix(".refreshInterval") })
        XCTAssertTrue(invalid.diagnostics.contains { $0.code == "config.unknownKey" && $0.path.hasSuffix(".interval") })
        XCTAssertTrue(invalid.diagnostics.contains { $0.code == "config.unknownKey" && $0.path.hasSuffix(".width") })
        XCTAssertTrue(invalid.diagnostics.contains { $0.code == "config.unknownKey" && $0.path.hasSuffix(".title") })
        XCTAssertTrue(invalid.diagnostics.contains { $0.code == "config.range" && $0.path.hasSuffix(".refreshInterval") })
        XCTAssertTrue(invalid.diagnostics.contains { $0.code == "config.unsupportedActions" && $0.path.hasSuffix(".actions") })

        let definitions = try XCTUnwrap(MMTMRConfigurationSchema.document.objectValue?["$defs"]?.objectValue)
        guard case let .array(variants)? = definitions["item"]?.objectValue?["oneOf"] else {
            return XCTFail("The item schema must expose oneOf variants.")
        }
        for type in ["cpu", "memory"] {
            let variant = try XCTUnwrap(variants.first {
                $0.objectValue?["properties"]?.objectValue?["type"]?.objectValue?["const"] == .string(type)
            })
            let properties = try XCTUnwrap(variant.objectValue?["properties"]?.objectValue)
            XCTAssertNotNil(properties["refreshInterval"])
            XCTAssertNotNil(properties["actions"])
            XCTAssertNotNil(properties["bordered"])
            XCTAssertNil(properties["actions"]?.objectValue?["default"])
            XCTAssertNil(properties["bordered"]?.objectValue?["default"])
            XCTAssertEqual(properties["actions"]?.objectValue?["maxItems"], .number(0))
            for forbidden in ["width", "image", "background", "title"] {
                XCTAssertNil(properties[forbidden], "\(type) must remain a bare square graph")
            }
        }
    }

    func testPinnedDockValidationAndRelativeFallbackPath() throws {
        let duplicate = codec.decode(#"""
        {
          "formatVersion": 1,
          "items": [{
            "id": "fixed-apps",
            "type": "pinnedDock",
            "applications": [
              {"bundleIdentifier":"com.apple.Terminal"},
              {"bundleIdentifier":"com.apple.Terminal","unknown":true}
            ],
            "longPressAction": "explode",
            "spacing": 21
          }, {
            "id": "too-tight",
            "type": "pinnedDock",
            "applications": [],
            "spacing": -12.5
          }]
        }
        """#)
        XCTAssertFalse(duplicate.isValid)
        XCTAssertTrue(duplicate.diagnostics.contains { $0.code == "config.duplicateApplication" })
        XCTAssertTrue(duplicate.diagnostics.contains { $0.code == "config.unknownKey" && $0.path.hasSuffix(".unknown") })
        XCTAssertTrue(duplicate.diagnostics.contains { $0.code == "config.enum" && $0.path.hasSuffix(".longPressAction") })
        XCTAssertEqual(duplicate.diagnostics.filter { $0.code == "config.range" && $0.path.hasSuffix(".spacing") }.count, 2)

        let valid = codec.decode(#"""
        {
          "formatVersion": 1,
          "items": [{
            "id": "fixed-apps",
            "type": "pinnedDock",
            "applications": [{"bundleIdentifier":"com.example.App","path":"Apps/Example.app"}],
            "spacing": -6.5
          }]
        }
        """#)
        let document = try XCTUnwrap(valid.document)
        let runtime = try XCTUnwrap(document.runtimeItems(
            relativeTo: URL(fileURLWithPath: "/project/config/.mtmr.json")
        ).first)
        let runtimeJSON = try JSONDecoder().decode(JSONValue.self, from: runtime.data)
        let application = try XCTUnwrap(runtimeJSON.objectValue?["applications"]?.arrayValue?.first?.objectValue)
        XCTAssertEqual(application["path"]?.stringValue, "/project/config/Apps/Example.app")
        XCTAssertEqual(runtimeJSON.objectValue?["spacing"]?.numberValue, -6.5)

        let definitions = try XCTUnwrap(MMTMRConfigurationSchema.document.objectValue?["$defs"]?.objectValue)
        guard case let .array(variants)? = definitions["item"]?.objectValue?["oneOf"] else {
            return XCTFail("The item schema must expose oneOf variants.")
        }
        let pinnedDock = try XCTUnwrap(variants.first {
            $0.objectValue?["properties"]?.objectValue?["type"]?.objectValue?["const"] == .string("pinnedDock")
        })
        let spacingSchema = try XCTUnwrap(pinnedDock.objectValue?["properties"]?.objectValue?["spacing"]?.objectValue)
        XCTAssertEqual(spacingSchema["minimum"], .number(-12))
        XCTAssertEqual(spacingSchema["maximum"], .number(20))
    }

    func testInvalidMatchApplicationPatternIsRejected() {
        let result = codec.decode(#"""
        {
          "formatVersion": 1,
          "items": [
            { "id": "conditional", "type": "staticButton", "title": "A", "matchAppId": "[" }
          ]
        }
        """#)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.diagnostics.contains(where: { $0.code == "config.matchAppId" }))
    }

    func testActionValidationIsSpecificAndIncludesTypeText() {
        let valid = codec.decode(#"""
        {
          "formatVersion": 1,
          "items": [{
            "id": "unicode",
            "type": "staticButton",
            "title": "Ž",
            "actions": [{"trigger":"singleTap","action":"typeText","text":"ž","shiftText":"Ž"}]
          }]
        }
        """#)
        XCTAssertTrue(valid.isValid, "\(valid.diagnostics)")
        XCTAssertEqual(
            valid.document?.items.first?.actions.first?.parameters["shiftText"],
            .string("Ž")
        )

        let invalidShiftText = codec.decode(#"{"formatVersion":1,"items":[{"id":"bad-shift","type":"staticButton","title":"ž","actions":[{"trigger":"singleTap","action":"typeText","text":"ž","shiftText":42}]}]}"#)
        XCTAssertTrue(invalidShiftText.diagnostics.contains {
            $0.code == "config.type" && $0.path == "$.items[0].actions[0].shiftText"
        })

        let actionDefinition = MMTMRConfigurationSchema.document.objectValue?["$defs"]?
            .objectValue?["action"]?.objectValue
        let typeTextVariant = actionDefinition?["oneOf"]?.arrayValue?.first {
            $0.objectValue?["properties"]?.objectValue?["action"]?
                .objectValue?["const"] == .string("typeText")
        }
        XCTAssertNotNil(
            typeTextVariant?.objectValue?["properties"]?.objectValue?["shiftText"]
        )

        let invalid = codec.decode(#"""
        {
          "formatVersion": 1,
          "items": [{
            "id": "bad",
            "type": "staticButton",
            "title": "bad",
            "actions": [{"trigger":"singleTap","action":"openUrl","keycode":42}]
          }]
        }
        """#)
        XCTAssertTrue(invalid.diagnostics.contains(where: { $0.path.hasSuffix(".url") }))
        XCTAssertTrue(invalid.diagnostics.contains(where: { $0.code == "config.unknownKey" && $0.path.hasSuffix(".keycode") }))

        let unsafeKeycodes = codec.decode(#"""
        {
          "formatVersion": 1,
          "items": [{
            "id": "unsafe",
            "type": "staticButton",
            "title": "unsafe",
            "actions": [
              {"trigger":"singleTap","action":"hidKey","keycode":256},
              {"trigger":"longTap","action":"keyPress","keycode":-1}
            ]
          }]
        }
        """#)
        XCTAssertEqual(unsafeKeycodes.diagnostics.filter { $0.code == "config.actionKeycode" }.count, 2)
    }

    func testPropertiesAndActionsAreValidatedForTheirConcreteRuntimeType() {
        let result = codec.decode(#"""
        {
          "formatVersion": 1,
          "items": [
            {"id":"play","type":"play","api_key":"ignored"},
            {"id":"weather","type":"weather","units":"kelvin"},
            {"id":"swipe","type":"swipe","direction":"left","fingers":5},
            {"id":"group","type":"group","items":[],"actions":[{"trigger":"singleTap","action":"typeText","text":"x"}]},
            {"id":"upnext","type":"upnext","actions":[]}
          ]
        }
        """#)

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.diagnostics.contains { $0.code == "config.unknownKey" && $0.path.hasSuffix(".api_key") })
        XCTAssertTrue(result.diagnostics.contains { $0.code == "config.enum" && $0.path.hasSuffix(".units") })
        XCTAssertTrue(result.diagnostics.contains { $0.path.hasSuffix(".fingers") })
        XCTAssertEqual(result.diagnostics.filter { $0.code == "config.unsupportedActions" }.count, 2)
    }

    func testRuntimeRequiredFieldsAndExclusiveSourcesAreValidated() {
        let missing = codec.decode(#"""
        {
          "formatVersion": 1,
          "items": [
            {"id":"button","type":"staticButton"},
            {"id":"script","type":"appleScriptTitledButton"},
            {"id":"group","type":"group"},
            {"id":"swipe","type":"swipe","direction":"up","fingers":2.5}
          ]
        }
        """#)
        XCTAssertFalse(missing.isValid)
        XCTAssertTrue(missing.diagnostics.contains(where: { $0.path == "$.items[0].title" }))
        XCTAssertTrue(missing.diagnostics.contains(where: { $0.path == "$.items[1].source" }))
        XCTAssertTrue(missing.diagnostics.contains(where: { $0.path == "$.items[2].items" }))
        XCTAssertTrue(missing.diagnostics.contains(where: { $0.path == "$.items[3].direction" }))
        XCTAssertTrue(missing.diagnostics.contains(where: { $0.path == "$.items[3].fingers" }))

        let ambiguousSource = codec.decode(#"""
        {
          "formatVersion": 1,
          "items": [{
            "id":"script",
            "type":"appleScriptTitledButton",
            "source":{"filePath":"title.scpt","inline":"return 1"}
          }]
        }
        """#)
        XCTAssertTrue(ambiguousSource.diagnostics.contains(where: { $0.code == "config.source" }))
    }

    func testLegacyMigrationAcceptsCommentsAndTrailingCommasAndNormalizesActions() throws {
        var nextID = 0
        let migrator = LegacyConfigMigrator(idGenerator: {
            nextID += 1
            return "generated-\(nextID)"
        })
        let legacy = #"""
        [
          // lower-case letter
          {
            "type": "staticButton",
            "title": "ž",
            "action": "typeText",
            "text": "ž",
            "shiftText": "Ž",
            "longAction": "typeText",
            "longText": "Ž",
          },
        ]
        """#

        let result = try migrator.migrate(Data(legacy.utf8))
        XCTAssertEqual(result.document.formatVersion, 1)
        XCTAssertEqual(result.document.items.first?.id, "generated-1")
        XCTAssertEqual(result.document.items.first?.actions.map(\.trigger), ["singleTap", "longTap"])
        XCTAssertEqual(result.document.items.first?.actions.map(\.action), ["typeText", "typeText"])
        XCTAssertEqual(
            result.document.items.first?.actions.first?.parameters["shiftText"],
            .string("Ž")
        )
        let output = try XCTUnwrap(String(data: result.canonicalData, encoding: .utf8))
        XCTAssertFalse(output.contains("//"))
        XCTAssertFalse(output.contains("longAction"))
        XCTAssertTrue(codec.decode(output).isValid)
    }

    func testRuntimeItemsKeepIDsFilterDisabledAndResolveRelativeFilePaths() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mmtmr-runtime-tests-\(UUID().uuidString)", isDirectory: true)
        let scriptURL = directory.appendingPathComponent("scripts/title.scpt")
        try FileManager.default.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("return 1".utf8).write(to: scriptURL)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configurationURL = directory.appendingPathComponent(".mtmr.json")
        let document = ConfigDocument(items: [
            ConfigItem(
                id: "visible",
                type: "appleScriptTitledButton",
                properties: [
                    "source": .object(["filePath": .string("scripts/title.scpt")])
                ]
            ),
            ConfigItem(id: "hidden", type: "play", enabled: false)
        ])

        let runtimeItems = try document.runtimeItems(relativeTo: configurationURL)
        XCTAssertEqual(runtimeItems.map(\.id), ["visible"])
        XCTAssertEqual(runtimeItems.first?.fingerprint.count, 64)

        let runtimeData = try XCTUnwrap(runtimeItems.first?.data)
        let runtimeJSON = try JSONDecoder().decode(JSONValue.self, from: runtimeData)
        let source = runtimeJSON.objectValue?["source"]?.objectValue
        XCTAssertEqual(source?["filePath"]?.stringValue, scriptURL.path)
        XCTAssertNil(runtimeJSON.objectValue?["id"])
    }

    func testEditorNameRoundTripsButNeverChangesRuntimeDataOrFingerprint() throws {
        let source = #"""
        {
          "formatVersion": 1,
          "items": [{
            "id": "play",
            "type": "play",
            "editorName": "Lecture principale"
          }]
        }
        """#
        let decoded = codec.decode(source)
        let document = try XCTUnwrap(decoded.document)
        XCTAssertEqual(document.items.first?.editorName, "Lecture principale")
        XCTAssertTrue(try XCTUnwrap(decoded.canonicalSource).contains("\"editorName\""))

        let namedRuntime = try XCTUnwrap(document.runtimeItems().first)
        XCTAssertEqual(namedRuntime.kind, "play")
        let unnamedDocument = ConfigDocument(items: [ConfigItem(id: "play", type: "play")])
        let unnamedRuntime = try XCTUnwrap(unnamedDocument.runtimeItems().first)
        XCTAssertEqual(namedRuntime.data, unnamedRuntime.data)
        XCTAssertEqual(namedRuntime.fingerprint, unnamedRuntime.fingerprint)

        let runtimeJSON = try JSONDecoder().decode(JSONValue.self, from: namedRuntime.data)
        XCTAssertNil(runtimeJSON.objectValue?["editorName"])
    }

    func testEditorNameMustBeAStringAndIsDeclaredByEveryItemSchema() throws {
        let invalid = codec.decode(#"{"formatVersion":1,"items":[{"id":"play","type":"play","editorName":7}]}"#)
        XCTAssertNil(invalid.document)
        XCTAssertTrue(invalid.diagnostics.contains {
            $0.code == "config.type" && $0.path == "$.items[0].editorName"
        })

        let definitions = try XCTUnwrap(MMTMRConfigurationSchema.document.objectValue?["$defs"]?.objectValue)
        let itemDefinition = try XCTUnwrap(definitions["item"]?.objectValue)
        guard case let .array(variants)? = itemDefinition["oneOf"] else {
            return XCTFail("The item schema must expose oneOf variants.")
        }
        XCTAssertFalse(variants.isEmpty)
        for variant in variants {
            let properties = try XCTUnwrap(variant.objectValue?["properties"]?.objectValue)
            XCTAssertEqual(properties["editorName"]?.objectValue?["type"], .string("string"))
        }
    }

    func testNestedRuntimeItemsKeepPersistentIDsAndResolveExecutables() throws {
        let configurationURL = URL(fileURLWithPath: "/project/config/.mtmr.json")
        let document = ConfigDocument(items: [
            ConfigItem(
                id: "group",
                type: "group",
                items: [
                    ConfigItem(
                        id: "nested",
                        type: "staticButton",
                        actions: [
                            ConfigAction(
                                trigger: "singleTap",
                                action: "shellScript",
                                parameters: ["executablePath": .string("scripts/run")]
                            )
                        ],
                        properties: ["title": .string("Run")]
                    )
                ]
            )
        ])

        let runtimeData = try XCTUnwrap(document.runtimeItems(relativeTo: configurationURL).first?.data)
        let runtimeJSON = try JSONDecoder().decode(JSONValue.self, from: runtimeData)
        let nested = try XCTUnwrap(runtimeJSON.objectValue?["items"]?.arrayValue?.first?.objectValue)
        XCTAssertEqual(nested["id"]?.stringValue, "nested")
        let executable = nested["actions"]?.arrayValue?.first?.objectValue?["executablePath"]?.stringValue
        XCTAssertEqual(executable, "/project/config/scripts/run")
    }

    func testCoordinatorUsesRevisionsAndKeepsLastValidDocument() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mmtmr-config-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(".mtmr.json")
        let first = #"{"formatVersion":1,"items":[{"id":"first","type":"play"}]}"#
        try Data(first.utf8).write(to: url)

        let coordinator = ConfigurationCoordinator(configurationURL: url)
        let loaded = coordinator.loadFromDisk()
        XCTAssertTrue(loaded.isValid)
        XCTAssertEqual(loaded.revision, 1)

        let second = #"{"formatVersion":1,"items":[{"id":"second","type":"mute"}]}"#
        let replaced = try coordinator.replace(source: second, expectedRevision: loaded.revision)
        XCTAssertEqual(replaced.revision, 2)
        XCTAssertEqual(replaced.document?.items.first?.id, "second")

        XCTAssertThrowsError(try coordinator.replace(source: second, expectedRevision: loaded.revision)) { error in
            XCTAssertEqual(
                error as? ConfigurationCoordinatorError,
                .revisionConflict(expected: 1, actual: 2)
            )
        }

        let invalid = coordinator.observeExternalChange(Data(#"{"formatVersion":1,"items":[}"#.utf8))
        XCTAssertFalse(invalid.isValid)
        XCTAssertEqual(coordinator.lastValidDocument()?.items.first?.id, "second")
    }

    func testCoordinatorRejectsMissingResourcesBeforeWriting() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mmtmr-resource-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(".mtmr.json")
        let initial = #"{"formatVersion":1,"items":[{"id":"first","type":"play"}]}"#
        try Data(initial.utf8).write(to: url)

        let coordinator = ConfigurationCoordinator(configurationURL: url)
        let loaded = coordinator.loadFromDisk()
        let missing = #"{"formatVersion":1,"items":[{"id":"script","type":"appleScriptTitledButton","source":{"filePath":"missing.scpt"}}]}"#

        XCTAssertThrowsError(try coordinator.replace(source: missing, expectedRevision: loaded.revision))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), initial)
    }

    func testCoordinatorRefreshesDiskBeforeReplacingAStaleRevision() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mmtmr-external-race-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(".mtmr.json")
        let initial = #"{"formatVersion":1,"items":[{"id":"initial","type":"play"}]}"#
        try Data(initial.utf8).write(to: url)

        let coordinator = ConfigurationCoordinator(configurationURL: url)
        let loaded = coordinator.loadFromDisk()
        let external = #"{"formatVersion":1,"items":[{"id":"external","type":"mute"}]}"#
        try Data(external.utf8).write(to: url, options: .atomic)
        let browser = #"{"formatVersion":1,"items":[{"id":"browser","type":"play"}]}"#

        XCTAssertThrowsError(try coordinator.replace(source: browser, expectedRevision: loaded.revision)) { error in
            XCTAssertEqual(
                error as? ConfigurationCoordinatorError,
                .revisionConflict(expected: loaded.revision, actual: loaded.revision + 1)
            )
        }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), external)
        XCTAssertEqual(coordinator.snapshot().document?.items.first?.id, "external")
    }

    func testCoordinatorDistinguishesADeletedFileFromAnEmptyFile() {
        let coordinator = ConfigurationCoordinator(configurationURL: URL(fileURLWithPath: "/unused/.mtmr.json"))
        let missing = coordinator.observeExternalChange(nil)
        let empty = coordinator.observeExternalChange(Data())

        XCTAssertEqual(missing.diagnostics.first?.code, "config.missing")
        XCTAssertEqual(empty.revision, missing.revision + 1)
        XCTAssertNotEqual(empty.hash, missing.hash)
        XCTAssertNotEqual(empty.diagnostics.first?.code, "config.missing")
    }

    func testServerAdapterReportsTheCommittedRevisionWhenAppKitApplyFails() async throws {
        struct ApplyFailure: LocalizedError {
            var errorDescription: String? { "Fixture apply failure" }
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mmtmr-apply-failure-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(".mtmr.json")
        try Data(#"{"formatVersion":1,"items":[{"id":"initial","type":"play"}]}"#.utf8).write(to: url)

        let coordinator = ConfigurationCoordinator(configurationURL: url)
        let loaded = coordinator.loadFromDisk()
        let adapter = ConfigurationServerAdapter(
            coordinator: coordinator,
            onAccepted: { _ in throw ApplyFailure() }
        )
        let replacement = #"{"formatVersion":1,"items":[{"id":"saved","type":"mute"}]}"#
        let result = try await adapter.replaceConfiguration(
            source: replacement,
            expectedRevision: Int(loaded.revision)
        )

        guard case let .accepted(snapshot) = result else {
            return XCTFail("The transport must receive the authoritative committed snapshot.")
        }
        XCTAssertEqual(snapshot.revision, Int(loaded.revision + 1))
        XCTAssertFalse(snapshot.valid)
        XCTAssertTrue(snapshot.diagnostics.contains { $0.code == "runtime.apply" })
        XCTAssertEqual(
            ConfigCodec().decode(try Data(contentsOf: url)).document?.items.first?.id,
            "saved"
        )
        XCTAssertEqual(coordinator.lastValidDocument()?.items.first?.id, "initial")
    }

    func testBootstrapImportsLegacyPresetWithoutModifyingIt() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("mmtmr-bootstrap-tests-\(UUID().uuidString)", isDirectory: true)
        let legacyURL = home.appendingPathComponent("Library/Application Support/MTMR/items.json")
        try FileManager.default.createDirectory(at: legacyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let legacy = #"[{"type":"staticButton","title":"Z","action":"typeText","text":"ž",},]"#
        try Data(legacy.utf8).write(to: legacyURL)

        let bootstrapper = ConfigurationBootstrapper(
            homeDirectory: home,
            bundledPresetURL: nil,
            migrator: LegacyConfigMigrator(idGenerator: { "generated" })
        )
        let result = bootstrapper.bootstrapIfNeeded()

        XCTAssertTrue(result.isValid, "\(result.diagnostics)")
        XCTAssertEqual(result.importedFrom, legacyURL)
        XCTAssertTrue(result.didCreateFile)
        XCTAssertEqual(try String(contentsOf: legacyURL, encoding: .utf8), legacy)
        let canonical = try Data(contentsOf: home.appendingPathComponent(".mtmr.json"))
        XCTAssertTrue(codec.decode(canonical).isValid)
    }

    func testDirectoryWatcherSeesAtomicReplacement() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mmtmr-watcher-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(".mtmr.json")
        let first = #"{"formatVersion":1,"items":[{"id":"first","type":"play"}]}"#
        try Data(first.utf8).write(to: url, options: .atomic)

        let coordinator = ConfigurationCoordinator(configurationURL: url)
        _ = coordinator.loadFromDisk()
        let changed = expectation(description: "atomic configuration replacement observed")
        try coordinator.startWatching { snapshot in
            if snapshot.document?.items.first?.id == "second" { changed.fulfill() }
        }
        defer { coordinator.stopWatching() }

        let second = #"{"formatVersion":1,"items":[{"id":"second","type":"mute"}]}"#
        try Data(second.utf8).write(to: url, options: .atomic)
        wait(for: [changed], timeout: 3)
    }

    func testDirectoryWatcherSeesInPlaceWrite() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mmtmr-in-place-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(".mtmr.json")
        try Data(#"{"formatVersion":1,"items":[{"id":"first","type":"play"}]}"#.utf8).write(to: url)

        let coordinator = ConfigurationCoordinator(configurationURL: url)
        _ = coordinator.loadFromDisk()
        let changed = expectation(description: "in-place write observed")
        try coordinator.startWatching { snapshot in
            if snapshot.document?.items.first?.id == "second" { changed.fulfill() }
        }
        defer { coordinator.stopWatching() }

        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data(#"{"formatVersion":1,"items":[{"id":"second","type":"mute"}]}"#.utf8))
        try handle.close()
        wait(for: [changed], timeout: 3)
    }
}
