import Foundation

public enum InputDispatchAction: String, Sendable {
    case unicodeText
    case keyPress
    case mediaKey
}

public enum InputDispatchBackendKind: String, Sendable {
    case none
    case coreGraphicsKeyboard
    case ioHID
    case coreGraphicsAuxiliary
}

public enum InputDispatchStatus: String, Sendable {
    case success
    case permissionDenied
    case eventCreationFailed
    case backendFailure
    case partialDispatch
}

public struct InputDispatchResult: Equatable, Sendable {
    public let action: InputDispatchAction
    public let backend: InputDispatchBackendKind
    public let status: InputDispatchStatus
    public let message: String
    public let systemCodes: [String: Int32]

    public var succeeded: Bool { status == .success }

    public init(
        action: InputDispatchAction,
        backend: InputDispatchBackendKind,
        status: InputDispatchStatus,
        message: String,
        systemCodes: [String: Int32] = [:]
    ) {
        self.action = action
        self.backend = backend
        self.status = status
        self.message = message
        self.systemCodes = systemCodes
    }
}

public extension Notification.Name {
    /// Posted synchronously after every keyboard, Unicode, or media-key attempt.
    /// The `InputDispatchResult` value is stored under
    /// `MMTMRInputDispatchNotification.resultUserInfoKey`.
    static let mmtmrInputDispatchDidComplete = Notification.Name(
        "com.tovam.MMTMR.inputDispatchDidComplete"
    )
}

public enum MMTMRInputDispatchNotification {
    public static let resultUserInfoKey = "result"
}

/// Pure state used by the physical Touch Bar gesture recognizers. Once a long
/// press has fired, the release that ends that same touch must not also count as
/// a single tap.
struct TouchTapSequenceState: Equatable, Sendable {
    private(set) var clickCount = 0
    private var suppressNextTouchEnd = false

    mutating func suppressCurrentTouchSequence() {
        clickCount = 0
        suppressNextTouchEnd = true
    }

    mutating func recordTouchEnd() -> Int? {
        if suppressNextTouchEnd {
            suppressNextTouchEnd = false
            return nil
        }
        clickCount += 1
        return clickCount
    }

    mutating func reset() {
        clickCount = 0
        suppressNextTouchEnd = false
    }
}

enum InputDispatchDiagnostics {
    @discardableResult
    static func publish(_ result: InputDispatchResult) -> InputDispatchResult {
        if !result.succeeded {
            let codes = result.systemCodes
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ", ")
            let suffix = codes.isEmpty ? "" : " [\(codes)]"
            NSLog(
                "[MMTMR Input] %@ via %@: %@%@",
                result.status.rawValue,
                result.backend.rawValue,
                result.message,
                suffix
            )
        }
        NotificationCenter.default.post(
            name: .mmtmrInputDispatchDidComplete,
            object: nil,
            userInfo: [MMTMRInputDispatchNotification.resultUserInfoKey: result]
        )
        return result
    }
}

enum KeyboardBackendPostResult: Equatable, Sendable {
    case success
    case eventCreationFailed(String)
    case failed(String)
}

protocol KeyboardInputBackend: Sendable {
    func hasPostEventAccess() -> Bool
    func requestPostEventAccess() -> Bool
    func postUnicodeText(_ text: String) -> KeyboardBackendPostResult
    func postKeyPress(_ keyCode: UInt16) -> KeyboardBackendPostResult
}

struct KeyboardInputDispatcher: Sendable {
    let backend: any KeyboardInputBackend

    @discardableResult
    func sendUnicodeText(_ text: String) -> InputDispatchResult {
        guard !text.utf16.isEmpty else {
            return InputDispatchDiagnostics.publish(InputDispatchResult(
                action: .unicodeText,
                backend: .coreGraphicsKeyboard,
                status: .eventCreationFailed,
                message: "Unicode text is empty."
            ))
        }
        return dispatch(
            action: .unicodeText,
            operation: { backend.postUnicodeText(text) }
        )
    }

    @discardableResult
    func sendKeyPress(_ keyCode: UInt16) -> InputDispatchResult {
        dispatch(
            action: .keyPress,
            operation: { backend.postKeyPress(keyCode) }
        )
    }

    private func dispatch(
        action: InputDispatchAction,
        operation: () -> KeyboardBackendPostResult
    ) -> InputDispatchResult {
        let accessGranted = backend.hasPostEventAccess() || backend.requestPostEventAccess()
        guard accessGranted else {
            return InputDispatchDiagnostics.publish(InputDispatchResult(
                action: action,
                backend: .coreGraphicsKeyboard,
                status: .permissionDenied,
                message: "Core Graphics PostEvent access was denied."
            ))
        }

        let result: InputDispatchResult
        switch operation() {
        case .success:
            result = InputDispatchResult(
                action: action,
                backend: .coreGraphicsKeyboard,
                status: .success,
                message: "Core Graphics events were posted."
            )
        case let .eventCreationFailed(message):
            result = InputDispatchResult(
                action: action,
                backend: .coreGraphicsKeyboard,
                status: .eventCreationFailed,
                message: message
            )
        case let .failed(message):
            result = InputDispatchResult(
                action: action,
                backend: .coreGraphicsKeyboard,
                status: .backendFailure,
                message: message
            )
        }
        return InputDispatchDiagnostics.publish(result)
    }
}

enum MediaPostEventAccess: Equatable, Sendable {
    case granted
    case denied
    case unknown
}

struct IOHIDMediaPostResult: Equatable, Sendable {
    let succeeded: Bool
    let keyDownPosted: Bool
    let keyUpPosted: Bool
    let systemCodes: [String: Int32]

    init(
        succeeded: Bool,
        keyDownPosted: Bool,
        keyUpPosted: Bool,
        systemCodes: [String: Int32] = [:]
    ) {
        self.succeeded = succeeded
        self.keyDownPosted = keyDownPosted
        self.keyUpPosted = keyUpPosted
        self.systemCodes = systemCodes
    }
}

enum CoreGraphicsAuxiliaryPostResult: Equatable, Sendable {
    case success
    case eventCreationFailed(String)
    /// No event was posted, so falling back cannot duplicate the action.
    case failedBeforePosting(String)
}

protocol MediaKeyInputBackend: Sendable {
    func ioHIDPostEventAccess() -> MediaPostEventAccess
    func requestIOHIDPostEventAccess() -> Bool
    func postUsingIOHID(keyCode: UInt8) -> IOHIDMediaPostResult

    func hasCoreGraphicsPostEventAccess() -> Bool
    func requestCoreGraphicsPostEventAccess() -> Bool
    func postUsingCoreGraphics(keyCode: UInt8) -> CoreGraphicsAuxiliaryPostResult
}

struct MediaKeyInputDispatcher: Sendable {
    let backend: any MediaKeyInputBackend

    @discardableResult
    func send(keyCode: UInt8) -> InputDispatchResult {
        let coreGraphicsGranted = backend.hasCoreGraphicsPostEventAccess()
            || backend.requestCoreGraphicsPostEventAccess()
        var coreGraphicsFailure: String?
        if coreGraphicsGranted {
            switch backend.postUsingCoreGraphics(keyCode: keyCode) {
            case .success:
                // CGEventPost has no delivery result. Once the complete pair has
                // been posted, never invoke IOHID as that could emit the action
                // twice even if the system later ignores the CG event.
                return InputDispatchDiagnostics.publish(InputDispatchResult(
                    action: .mediaKey,
                    backend: .coreGraphicsAuxiliary,
                    status: .success,
                    message: "The media key was posted through Core Graphics."
                ))
            case let .eventCreationFailed(message), let .failedBeforePosting(message):
                coreGraphicsFailure = message
            }
        }

        // IOHID is retained solely as a controlled fallback. It is reached only
        // when Core Graphics posted no event (permission denied or construction
        // failed), so it cannot duplicate a media-key action.
        let initialAccess = backend.ioHIDPostEventAccess()
        let ioHIDGranted = initialAccess == .granted || backend.requestIOHIDPostEventAccess()
        guard ioHIDGranted else {
            return InputDispatchDiagnostics.publish(InputDispatchResult(
                action: .mediaKey,
                backend: .none,
                status: .permissionDenied,
                message: coreGraphicsGranted
                    ? "Core Graphics could not create the media-key events and IOHID PostEvent access was denied."
                    : "PostEvent access was denied for Core Graphics and IOHID."
            ))
        }

        let fallback = backend.postUsingIOHID(keyCode: keyCode)
        if fallback.succeeded {
            return InputDispatchDiagnostics.publish(InputDispatchResult(
                action: .mediaKey,
                backend: .ioHID,
                status: .success,
                message: coreGraphicsFailure.map {
                    "Core Graphics failed before posting (\($0)); IOHID fallback posted the media key."
                } ?? "The media key was posted through the IOHID fallback.",
                systemCodes: fallback.systemCodes
            ))
        }

        if fallback.keyDownPosted {
            return InputDispatchDiagnostics.publish(InputDispatchResult(
                action: .mediaKey,
                backend: .ioHID,
                status: .partialDispatch,
                message: fallback.keyUpPosted
                    ? "IOHID reported failure after posting both media-key events."
                    : "IOHID posted key-down but failed to post key-up.",
                systemCodes: fallback.systemCodes
            ))
        }

        return InputDispatchDiagnostics.publish(InputDispatchResult(
            action: .mediaKey,
            backend: .ioHID,
            status: .backendFailure,
            message: coreGraphicsFailure.map {
                "Core Graphics failed before posting (\($0)); IOHID fallback also failed before key-down."
            } ?? "IOHID fallback failed before key-down.",
            systemCodes: fallback.systemCodes
        ))
    }
}
