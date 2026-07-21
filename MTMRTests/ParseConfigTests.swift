import XCTest

class ParseConfig: XCTestCase {
    func testButtonNoAction() {
        let buttonNoActionFixture = """
            [  { "type": "staticButton",  "title": "Pew" } ]
        """.data(using: .utf8)!
        let result = try? JSONDecoder().decode([BarItemDefinition].self, from: buttonNoActionFixture)
        guard case .staticButton("Pew")? = result?.first?.type else {
            XCTFail()
            return
        }
        guard result?.first?.actions.count == 0 else {
            XCTFail()
            return
        }
    }

    func testButtonKeyCodeAction() {
        let buttonKeycodeFixture = """
            [  { "type": "staticButton",  "title": "Pew", "actions": [ { "trigger": "singleTap", "action": "hidKey", "keycode": 123 } ] } ]
        """.data(using: .utf8)!
        let result = try? JSONDecoder().decode([BarItemDefinition].self, from: buttonKeycodeFixture)
        guard case .staticButton("Pew")? = result?.first?.type else {
            XCTFail()
            return
        }
        guard case .hidKey(keycode: 123)? = result?.first?.actions.filter({ $0.trigger == .singleTap }).first?.value else {
            XCTFail()
            return
        }
    }

    func testButtonUnicodeTextAction() {
        let buttonFixture = """
            [  { "type": "staticButton", "title": "Unicode", "actions": [ { "trigger": "singleTap", "action": "typeText", "text": "ž👍" } ] } ]
        """.data(using: .utf8)!
        let result = try? JSONDecoder().decode([BarItemDefinition].self, from: buttonFixture)

        guard case .typeText(text: "ž👍")? = result?.first?.actions.first?.value else {
            XCTFail()
            return
        }
    }
    
    func testButtonKeyCodeLegacyAction() {
        let buttonKeycodeFixture = """
            [  { "type": "staticButton",  "title": "Pew", "action": "hidKey", "keycode": 123 } ]
        """.data(using: .utf8)!
        let result = try? JSONDecoder().decode([BarItemDefinition].self, from: buttonKeycodeFixture)
        guard case .staticButton("Pew")? = result?.first?.type else {
            XCTFail()
            return
        }
        guard case .hidKey(keycode: 123)? = result?.first?.legacyAction else {
            XCTFail()
            return
        }
    }

    func testPredefinedItem() {
        let buttonKeycodeFixture = """
            [  { "type": "escape" } ]
        """.data(using: .utf8)!
        let result = try? JSONDecoder().decode([BarItemDefinition].self, from: buttonKeycodeFixture)
        guard case .staticButton("esc")? = result?.first?.type else {
            XCTFail()
            return
        }
        guard case .keyPress(keycode: 53)? = result?.first?.actions.filter({ $0.trigger == .singleTap }).first?.value else {
            XCTFail()
            return
        }
    }

    func testPhysicalSystemButtonsDecodeToNativeMediaKeys() throws {
        let fixture = """
            [
              { "type": "brightnessDown" },
              { "type": "brightnessUp" },
              { "type": "volumeDown" },
              { "type": "volumeUp" }
            ]
        """.data(using: .utf8)!

        let items = try JSONDecoder().decode([BarItemDefinition].self, from: fixture)
        // Stable NX auxiliary-key ABI values from IOKit/ev_keymap.h.
        let expected: [Int32] = [3, 2, 1, 0]

        XCTAssertEqual(items.count, expected.count)
        for (item, keyCode) in zip(items, expected) {
            guard case let .hidKey(actualCode)? = item.actions.first?.value else {
                XCTFail("Predefined system button did not decode to a native media-key action")
                continue
            }
            XCTAssertEqual(actualCode, keyCode)
        }
    }

    func testDockHugsItsIconsUnlessAManualWidthWasRequested() throws {
        let fixture = """
            [
              { "type": "dock" },
              { "type": "dock", "width": 420 },
              { "type": "dock", "width": 420, "autoResize": true },
              { "type": "dock", "autoResize": false }
            ]
        """.data(using: .utf8)!

        let items = try JSONDecoder().decode([BarItemDefinition].self, from: fixture)
        let automaticValues = items.compactMap { item -> Bool? in
            guard case let .dock(autoResize: automatic, filter: _) = item.type else { return nil }
            return automatic
        }

        XCTAssertEqual(automaticValues, [true, false, true, false])
    }

    func testCPUAndMemoryUsageShareTheSameRefreshDefaults() throws {
        let fixture = #"""
            [
              { "type": "cpu" },
              { "type": "memory" },
              { "type": "memory", "refreshInterval": 7.5 }
            ]
        """#.data(using: .utf8)!

        let items = try JSONDecoder().decode([BarItemDefinition].self, from: fixture)
        guard case let .cpu(cpuInterval) = items[0].type else {
            return XCTFail("Expected the CPU usage component")
        }
        guard case let .memory(defaultMemoryInterval) = items[1].type else {
            return XCTFail("Expected the memory usage component")
        }
        guard case let .memory(customMemoryInterval) = items[2].type else {
            return XCTFail("Expected the configurable memory usage component")
        }

        XCTAssertEqual(cpuInterval, 2)
        XCTAssertEqual(defaultMemoryInterval, 2)
        XCTAssertEqual(customMemoryInterval, 7.5)
    }

    func testPinnedDockKeepsExplicitApplicationOrderAndDefaults() throws {
        let fixture = #"""
            [
              {
                "type": "pinnedDock",
                "applications": [
                  {"bundleIdentifier":"org.mozilla.firefox"},
                  {"bundleIdentifier":"com.apple.Terminal","label":"Terminal","path":"/Applications/Terminal.app"}
                ]
              },
              {"type":"pinnedDock","applications":[],"spacing":6.5}
            ]
        """#.data(using: .utf8)!

        let decoded = try JSONDecoder().decode([BarItemDefinition].self, from: fixture)
        let item = try XCTUnwrap(decoded.first)
        guard case let .pinnedDock(autoResize, applications, showRunningIndicator, longPressAction, spacing) = item.type else {
            return XCTFail("Expected a pinnedDock runtime item")
        }
        XCTAssertTrue(autoResize)
        XCTAssertTrue(showRunningIndicator)
        XCTAssertEqual(longPressAction, .quit)
        XCTAssertEqual(spacing, 1)
        XCTAssertEqual(applications.map(\.bundleIdentifier), ["org.mozilla.firefox", "com.apple.Terminal"])
        XCTAssertEqual(applications.last?.label, "Terminal")
        guard case let .pinnedDock(_, _, _, _, customSpacing) = decoded[1].type else {
            return XCTFail("Expected the custom-spacing pinnedDock runtime item")
        }
        XCTAssertEqual(customSpacing, 6.5)
    }

    func testExtendedWidthForPredefinedItem() {
        let buttonKeycodeFixture = """
            [  { "type": "escape", "width": 110} ]
        """.data(using: .utf8)!
        let result = try? JSONDecoder().decode([BarItemDefinition].self, from: buttonKeycodeFixture)
        guard case .staticButton("esc")? = result?.first?.type else {
            XCTFail()
            return
        }
        guard case .keyPress(keycode: 53)? = result?.first?.actions.filter({ $0.trigger == .singleTap }).first?.value else {
            XCTFail()
            return
        }
        guard case .width(110)? = result?.first?.additionalParameters[.width] else {
            XCTFail()
            return
        }
    }

    func testFileSourceKeepsResolvedContentAfterTheFileChanges() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mmtmr-source-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("title.txt")
        try Data("premier".utf8).write(to: fileURL)
        let payload = try JSONSerialization.data(withJSONObject: ["filePath": fileURL.path])

        let source = try JSONDecoder().decode(Source.self, from: payload)
        try Data("second".utf8).write(to: fileURL)

        XCTAssertEqual(source.string, "premier")
        XCTAssertEqual(source.data, Data("premier".utf8))
    }

    func testBase64SourceCanResolveUTF8TextWithoutDiskAccess() throws {
        let encoded = Data("return \"ž\"".utf8).base64EncodedString()
        let payload = try JSONSerialization.data(withJSONObject: ["base64": encoded])
        let source = try JSONDecoder().decode(Source.self, from: payload)

        XCTAssertEqual(source.string, "return \"ž\"")
        XCTAssertNotNil(source.appleScript)
    }
}
