import AppKit
import XCTest

final class InputDispatchTests: XCTestCase {
    func testPhysicalTouchBarAlignmentUsesNaturalEdgeWidthsAndAnExactCenter() {
        let frames = TouchBarPhysicalLayout.frames(
            in: CGRect(x: 0, y: 0, width: 1_000, height: 30),
            naturalWidths: TouchBarZoneWidths(left: 400, center: 100, right: 250)
        )

        XCTAssertEqual(frames.left, CGRect(x: 0, y: 0, width: 400, height: 30))
        XCTAssertEqual(frames.center, CGRect(x: 450, y: 0, width: 100, height: 30))
        XCTAssertEqual(frames.right, CGRect(x: 750, y: 0, width: 250, height: 30))
        XCTAssertEqual(frames.center.midX, 500, accuracy: 0.001)
    }

    func testPhysicalTouchBarClipsSidesBeforeMovingTheCenter() {
        let frames = TouchBarPhysicalLayout.frames(
            in: CGRect(x: 0, y: 0, width: 1_000, height: 30),
            naturalWidths: TouchBarZoneWidths(left: 700, center: 100, right: 700)
        )

        XCTAssertEqual(frames.center.midX, 500, accuracy: 0.001)
        XCTAssertEqual(frames.left.minX, 0, accuracy: 0.001)
        XCTAssertEqual(frames.left.maxX, frames.center.minX - TouchBarPhysicalLayout.groupSpacing, accuracy: 0.001)
        XCTAssertEqual(frames.right.minX, frames.center.maxX + TouchBarPhysicalLayout.groupSpacing, accuracy: 0.001)
        XCTAssertEqual(frames.right.maxX, 1_000, accuracy: 0.001)
    }

    func testPhysicalTouchBarLetsAnAsymmetricSideUseOtherwiseEmptySpace() {
        let frames = TouchBarPhysicalLayout.frames(
            in: CGRect(x: 0, y: 0, width: 1_000, height: 30),
            naturalWidths: TouchBarZoneWidths(left: 800, center: 0, right: 100)
        )

        XCTAssertEqual(frames.left.width, 800, accuracy: 0.001)
        XCTAssertEqual(frames.right.width, 100, accuracy: 0.001)
        XCTAssertEqual(frames.right.maxX, 1_000, accuracy: 0.001)
        XCTAssertLessThanOrEqual(frames.left.maxX + TouchBarPhysicalLayout.groupSpacing, frames.right.minX)
    }

    @MainActor
    func testCenterItemsStayAtTheActualVisibleMidpointWithoutAWrapper() throws {
        let first = fixedItem("center-a", width: 40)
        let second = fixedItem("center-b", width: 60)

        let basicView = BasicView(
            identifier: .init("basic-layout-test"),
            leftItems: [],
            centerItems: [first, second],
            rightItems: [],
            swipeItems: []
        )
        basicView.view.frame = NSRect(
            x: 0,
            y: 0,
            width: TouchBarPhysicalLayout.preferredWidth,
            height: TouchBarPhysicalLayout.preferredHeight
        )
        basicView.view.layoutSubtreeIfNeeded()

        let firstView = try XCTUnwrap(first.view)
        let secondView = try XCTUnwrap(second.view)
        let firstFrame = firstView.convert(firstView.bounds, to: basicView.view)
        let secondFrame = secondView.convert(secondView.bounds, to: basicView.view)
        let groupMidpoint = (firstFrame.minX + secondFrame.maxX) / 2
        XCTAssertEqual(secondFrame.minX - firstFrame.maxX, TouchBarPhysicalLayout.groupSpacing, accuracy: 0.001)
        XCTAssertEqual(groupMidpoint, TouchBarPhysicalLayout.preferredWidth / 2, accuracy: 0.5)
    }

    @MainActor
    func testRightItemsUseTheHostVisibleEdgeInsteadOfTheTheoreticalWidth() throws {
        let right = fixedItem("right-edge", width: 50)
        let basicView = BasicView(
            identifier: .init("visible-edge-layout-test"),
            leftItems: [],
            centerItems: [],
            rightItems: [right],
            swipeItems: []
        )
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 30))
        host.wantsLayer = true
        host.layer?.masksToBounds = true
        basicView.view.frame = NSRect(x: 0, y: 0, width: TouchBarPhysicalLayout.preferredWidth, height: 30)
        host.addSubview(basicView.view)
        host.layoutSubtreeIfNeeded()
        basicView.view.layoutSubtreeIfNeeded()

        let rightView = try XCTUnwrap(right.view)
        let frame = rightView.convert(rightView.bounds, to: host)
        XCTAssertEqual(frame.maxX, host.bounds.maxX, accuracy: 0.5)
        XCTAssertEqual(frame.width, 50, accuracy: 0.001)
    }

    func testLongTapReleaseIsNotAlsoCountedAsASingleTap() {
        var state = TouchTapSequenceState()

        state.suppressCurrentTouchSequence()

        XCTAssertNil(state.recordTouchEnd())
        XCTAssertEqual(state.recordTouchEnd(), 1)
    }

    func testUnicodeUsesExistingPostEventPermissionWithoutRequestingIt() {
        let backend = FakeKeyboardBackend()
        backend.hasAccess = true

        let result = KeyboardInputDispatcher(backend: backend).sendUnicodeText("ž")

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.backend, .coreGraphicsKeyboard)
        XCTAssertEqual(backend.requestCount, 0)
        XCTAssertEqual(backend.unicodePosts, ["ž"])
    }

    func testUnicodeRequestsPostEventPermissionBeforePosting() {
        let backend = FakeKeyboardBackend()
        backend.hasAccess = false
        backend.requestResult = true

        let result = KeyboardInputDispatcher(backend: backend).sendUnicodeText("Ž")

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(backend.requestCount, 1)
        XCTAssertEqual(backend.unicodePosts, ["Ž"])
    }

    func testUnicodePermissionDenialDoesNotPostAndPublishesStructuredFailure() {
        let backend = FakeKeyboardBackend()
        backend.hasAccess = false
        backend.requestResult = false
        let observed = LockedResultBox()
        let token = NotificationCenter.default.addObserver(
            forName: .mmtmrInputDispatchDidComplete,
            object: nil,
            queue: nil
        ) { notification in
            observed.value = notification.userInfo?[MMTMRInputDispatchNotification.resultUserInfoKey]
                as? InputDispatchResult
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let result = KeyboardInputDispatcher(backend: backend).sendUnicodeText("ž")

        XCTAssertEqual(result.status, .permissionDenied)
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(backend.unicodePosts.isEmpty)
        XCTAssertEqual(observed.value, result)
    }

    func testMediaUsesCoreGraphicsPrimaryAndNeverTouchesIOHIDAfterPosting() {
        let backend = FakeMediaBackend()
        backend.coreGraphicsHasAccess = true
        backend.coreGraphicsResult = .success

        let result = MediaKeyInputDispatcher(backend: backend).send(keyCode: 1)

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.backend, .coreGraphicsAuxiliary)
        XCTAssertEqual(backend.coreGraphicsPostCount, 1)
        XCTAssertEqual(backend.ioHIDAccessCount, 0)
        XCTAssertEqual(backend.ioHIDPostCount, 0)
    }

    func testMediaFallsBackToIOHIDOnlyWhenCoreGraphicsPostedNothing() {
        let backend = FakeMediaBackend()
        backend.coreGraphicsHasAccess = true
        backend.coreGraphicsResult = .eventCreationFailed("pair unavailable")
        backend.ioHIDAccess = .granted
        backend.ioHIDResult = IOHIDMediaPostResult(
            succeeded: true,
            keyDownPosted: true,
            keyUpPosted: true,
            systemCodes: ["IOHIDPostEvent(keyDown)": 0, "IOHIDPostEvent(keyUp)": 0]
        )

        let result = MediaKeyInputDispatcher(backend: backend).send(keyCode: 2)

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.backend, .ioHID)
        XCTAssertEqual(backend.coreGraphicsPostCount, 1)
        XCTAssertEqual(backend.ioHIDPostCount, 1)
        XCTAssertEqual(result.systemCodes["IOHIDPostEvent(keyDown)"], 0)
    }

    func testMediaPermissionDenialDoesNotPostEitherBackend() {
        let backend = FakeMediaBackend()
        backend.coreGraphicsHasAccess = false
        backend.coreGraphicsRequestResult = false
        backend.ioHIDAccess = .denied
        backend.ioHIDRequestResult = false

        let result = MediaKeyInputDispatcher(backend: backend).send(keyCode: 0)

        XCTAssertEqual(result.status, .permissionDenied)
        XCTAssertEqual(result.backend, .none)
        XCTAssertEqual(backend.coreGraphicsPostCount, 0)
        XCTAssertEqual(backend.ioHIDPostCount, 0)
        XCTAssertEqual(backend.coreGraphicsRequestCount, 1)
        XCTAssertEqual(backend.ioHIDRequestCount, 1)
    }

    func testMediaIOHIDPartialDispatchNeverRetriesOrDuplicates() {
        let backend = FakeMediaBackend()
        backend.coreGraphicsHasAccess = false
        backend.coreGraphicsRequestResult = false
        backend.ioHIDAccess = .granted
        backend.ioHIDResult = IOHIDMediaPostResult(
            succeeded: false,
            keyDownPosted: true,
            keyUpPosted: false,
            systemCodes: ["IOHIDPostEvent(keyUp)": -536_870_212]
        )

        let result = MediaKeyInputDispatcher(backend: backend).send(keyCode: 3)

        XCTAssertEqual(result.status, .partialDispatch)
        XCTAssertEqual(result.backend, .ioHID)
        XCTAssertEqual(backend.coreGraphicsPostCount, 0)
        XCTAssertEqual(backend.ioHIDPostCount, 1)
    }

    func testKeyboardEventCreationFailureIsStructured() {
        let backend = FakeKeyboardBackend()
        backend.hasAccess = true
        backend.keyPressResult = .eventCreationFailed("cannot create pair")

        let result = KeyboardInputDispatcher(backend: backend).sendKeyPress(53)

        XCTAssertEqual(result.status, .eventCreationFailed)
        XCTAssertEqual(result.message, "cannot create pair")
        XCTAssertEqual(backend.keyPresses, [53])
    }

    @MainActor
    func testGroupAlwaysHasAVisiblePhysicalButtonByDefault() {
        let group = GroupBarItem(identifier: .init("group-visible-test"), items: [])

        XCTAssertEqual(group.collapsedRepresentationLabel, "Groupe")
    }
}

@MainActor
private func fixedItem(_ identifier: String, width: CGFloat) -> NSTouchBarItem {
    let item = NSCustomTouchBarItem(identifier: .init(identifier))
    let view = NSView()
    view.widthAnchor.constraint(equalToConstant: width).isActive = true
    view.heightAnchor.constraint(equalToConstant: TouchBarPhysicalLayout.preferredHeight).isActive = true
    item.view = view
    return item
}

private final class LockedResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: InputDispatchResult?

    var value: InputDispatchResult? {
        get { lock.withLock { storedValue } }
        set { lock.withLock { storedValue = newValue } }
    }
}

private final class FakeKeyboardBackend: KeyboardInputBackend, @unchecked Sendable {
    var hasAccess = false
    var requestResult = false
    var unicodeResult: KeyboardBackendPostResult = .success
    var keyPressResult: KeyboardBackendPostResult = .success
    private(set) var requestCount = 0
    private(set) var unicodePosts: [String] = []
    private(set) var keyPresses: [UInt16] = []

    func hasPostEventAccess() -> Bool { hasAccess }

    func requestPostEventAccess() -> Bool {
        requestCount += 1
        return requestResult
    }

    func postUnicodeText(_ text: String) -> KeyboardBackendPostResult {
        unicodePosts.append(text)
        return unicodeResult
    }

    func postKeyPress(_ keyCode: UInt16) -> KeyboardBackendPostResult {
        keyPresses.append(keyCode)
        return keyPressResult
    }
}

private final class FakeMediaBackend: MediaKeyInputBackend, @unchecked Sendable {
    var coreGraphicsHasAccess = false
    var coreGraphicsRequestResult = false
    var coreGraphicsResult: CoreGraphicsAuxiliaryPostResult = .success
    var ioHIDAccess: MediaPostEventAccess = .unknown
    var ioHIDRequestResult = false
    var ioHIDResult = IOHIDMediaPostResult(
        succeeded: false,
        keyDownPosted: false,
        keyUpPosted: false
    )

    private(set) var coreGraphicsRequestCount = 0
    private(set) var coreGraphicsPostCount = 0
    private(set) var ioHIDAccessCount = 0
    private(set) var ioHIDRequestCount = 0
    private(set) var ioHIDPostCount = 0

    func ioHIDPostEventAccess() -> MediaPostEventAccess {
        ioHIDAccessCount += 1
        return ioHIDAccess
    }

    func requestIOHIDPostEventAccess() -> Bool {
        ioHIDRequestCount += 1
        return ioHIDRequestResult
    }

    func postUsingIOHID(keyCode _: UInt8) -> IOHIDMediaPostResult {
        ioHIDPostCount += 1
        return ioHIDResult
    }

    func hasCoreGraphicsPostEventAccess() -> Bool { coreGraphicsHasAccess }

    func requestCoreGraphicsPostEventAccess() -> Bool {
        coreGraphicsRequestCount += 1
        return coreGraphicsRequestResult
    }

    func postUsingCoreGraphics(keyCode _: UInt8) -> CoreGraphicsAuxiliaryPostResult {
        coreGraphicsPostCount += 1
        return coreGraphicsResult
    }
}
