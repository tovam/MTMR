import AppKit
import XCTest

private final class RuntimeVisualChangeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    func increment() {
        lock.lock()
        storedValue += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }
}

class BackgroundColorTests: XCTestCase {
    func testOpaque() {
        let buttonNoActionFixture = """
            [  { "type": "staticButton",  "title": "Pew", "background": "#FF0000" } ]
        """.data(using: .utf8)!
        let result = try? JSONDecoder().decode([BarItemDefinition].self, from: buttonNoActionFixture)
        guard case let .background(color)? = result?.first?.additionalParameters[.background] else {
            XCTFail()
            return
        }
        XCTAssertEqual(color, .red)
    }

    func testAlpha() {
        let buttonNoActionFixture = """
            [  { "type": "staticButton",  "title": "Pew", "background": "#FF000080" } ]
        """.data(using: .utf8)!
        let result = try? JSONDecoder().decode([BarItemDefinition].self, from: buttonNoActionFixture)
        guard case let .background(color)? = result?.first?.additionalParameters[.background] else {
            XCTFail()
            return
        }
        XCTAssertEqual(color.alphaComponent, 0.5, accuracy: 0.01)
    }

    func testResizeRejectsInvalidDimensions() {
        XCTAssertNil(NSImage(size: .zero).resize(maxSize: NSSize(width: 24, height: 24)))

        let image = NSImage(size: NSSize(width: 24, height: 24))
        XCTAssertNil(image.resize(maxSize: .zero))
    }

    func testResizeRejectsImageWithoutCGImage() {
        let image = NSImage(size: NSSize(width: 24, height: 24))

        XCTAssertNil(image.resize(maxSize: NSSize(width: 24, height: 24)))
    }

    @MainActor
    func testButtonPublishesOnlyRealVisualChanges() {
        let button = CustomButtonTouchBarItem(identifier: .init("test.visual"), title: "A")
        let counter = RuntimeVisualChangeCounter()
        let observer = NotificationCenter.default.addObserver(
            forName: .mmtmrRuntimeVisualDidChange,
            object: nil,
            queue: nil
        ) { _ in
            counter.increment()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        button.title = "A"
        button.image = nil
        button.isBordered = true
        XCTAssertEqual(counter.value, 0)

        button.title = "B"
        button.title = "B"
        let image = NSImage(size: NSSize(width: 16, height: 16))
        button.image = image
        button.image = image
        button.isBordered = false
        button.isBordered = false

        XCTAssertEqual(counter.value, 3)
    }
}
