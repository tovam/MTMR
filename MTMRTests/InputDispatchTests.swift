import Foundation
import XCTest

final class InputDispatchTests: XCTestCase {
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
