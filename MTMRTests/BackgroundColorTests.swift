import AppKit
import XCTest

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
}
