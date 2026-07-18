//
//  KeyPress.swift
//  MTMR
//
//  Created by Anton Palgunov on 17/03/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Foundation

/// Coalesces the macOS privacy prompts used by the concrete input backends.
/// AppDelegate requests Core Graphics access during launch, so physical taps
/// only perform the cheap preflight check after that one-time request.
final class InputAccessCoordinator: @unchecked Sendable {
    static let shared = InputAccessCoordinator()

    private let lock = NSLock()
    private var requestedCoreGraphicsAccess = false
    private var requestedIOHIDAccess = false

    private init() {}

    func requestCoreGraphicsPostEventAccessIfNeeded() -> Bool {
        if CGPreflightPostEventAccess() { return true }
        return lock.withLock {
            if CGPreflightPostEventAccess() { return true }
            guard !requestedCoreGraphicsAccess else { return false }
            requestedCoreGraphicsAccess = true
            return CGRequestPostEventAccess()
        }
    }

    func requestIOHIDPostEventAccessIfNeeded() -> Bool {
        if MediaKeys.checkHIDPostEventAccess().rawValue == 0 { return true }
        return lock.withLock {
            if MediaKeys.checkHIDPostEventAccess().rawValue == 0 { return true }
            guard !requestedIOHIDAccess else { return false }
            requestedIOHIDAccess = true
            return MediaKeys.requestHIDPostEventAccess()
        }
    }
}

protocol KeyPress {
    var keyCode: CGKeyCode { get }

    @discardableResult
    func send() -> InputDispatchResult
}

struct GenericKeyPress: KeyPress {
    var keyCode: CGKeyCode
    private let backend: any KeyboardInputBackend

    init(
        keyCode: CGKeyCode,
        backend: any KeyboardInputBackend = CoreGraphicsKeyboardInputBackend()
    ) {
        self.keyCode = keyCode
        self.backend = backend
    }

    @discardableResult
    func send() -> InputDispatchResult {
        KeyboardInputDispatcher(backend: backend).sendKeyPress(UInt16(keyCode))
    }
}

struct UnicodeTextInput {
    let text: String
    private let backend: any KeyboardInputBackend

    init(
        text: String,
        backend: any KeyboardInputBackend = CoreGraphicsKeyboardInputBackend()
    ) {
        self.text = text
        self.backend = backend
    }

    @discardableResult
    func send() -> InputDispatchResult {
        KeyboardInputDispatcher(backend: backend).sendUnicodeText(text)
    }
}

private struct CoreGraphicsKeyboardInputBackend: KeyboardInputBackend {
    func hasPostEventAccess() -> Bool {
        CGPreflightPostEventAccess()
    }

    func requestPostEventAccess() -> Bool {
        InputAccessCoordinator.shared.requestCoreGraphicsPostEventAccessIfNeeded()
    }

    func postUnicodeText(_ text: String) -> KeyboardBackendPostResult {
        let codeUnits = Array(text.utf16)
        guard !codeUnits.isEmpty else {
            return .eventCreationFailed("Unicode text is empty.")
        }

        guard
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
        else {
            return .eventCreationFailed("Core Graphics could not create the Unicode key events.")
        }

        codeUnits.withUnsafeBufferPointer { buffer in
            keyDown.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: buffer.baseAddress
            )
            keyUp.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: buffer.baseAddress
            )
        }

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return .success
    }

    func postKeyPress(_ keyCode: UInt16) -> KeyboardBackendPostResult {
        let source = CGEventSource(stateID: .hidSystemState)
        guard
            let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(keyCode),
                keyDown: true
            ),
            let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(keyCode),
                keyDown: false
            )
        else {
            return .eventCreationFailed("Core Graphics could not create the keyboard events.")
        }

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return .success
    }
}

private struct SystemMediaKeyInputBackend: MediaKeyInputBackend {
    func ioHIDPostEventAccess() -> MediaPostEventAccess {
        switch MediaKeys.checkHIDPostEventAccess().rawValue {
        case 0:
            return .granted
        case 1:
            return .denied
        default:
            return .unknown
        }
    }

    func requestIOHIDPostEventAccess() -> Bool {
        InputAccessCoordinator.shared.requestIOHIDPostEventAccessIfNeeded()
    }

    func postUsingIOHID(keyCode: UInt8) -> IOHIDMediaPostResult {
        let raw = MediaKeys.postAuxKeyUsingIOHID(keyCode)
        var codes: [String: Int32] = [:]
        if raw.mainPortAttempted.boolValue {
            codes["IOMainPort"] = raw.mainPortResult
        }
        if raw.matchingServicesAttempted.boolValue {
            codes["IOServiceGetMatchingServices"] = raw.matchingServicesResult
        }
        if raw.serviceOpenAttempted.boolValue {
            codes["IOServiceOpen"] = raw.serviceOpenResult
        }
        if raw.serviceReleaseAttempted.boolValue {
            codes["IOObjectRelease(service)"] = raw.serviceReleaseResult
        }
        if raw.iteratorReleaseAttempted.boolValue {
            codes["IOObjectRelease(iterator)"] = raw.iteratorReleaseResult
        }
        if raw.connectionCloseAttempted.boolValue {
            codes["IOServiceClose"] = raw.connectionCloseResult
        }
        if raw.keyDownAttempted.boolValue {
            codes["IOHIDPostEvent(keyDown)"] = raw.keyDownResult
        }
        if raw.keyUpAttempted.boolValue {
            codes["IOHIDPostEvent(keyUp)"] = raw.keyUpResult
        }
        return IOHIDMediaPostResult(
            succeeded: raw.succeeded.boolValue,
            keyDownPosted: raw.keyDownPosted.boolValue,
            keyUpPosted: raw.keyUpPosted.boolValue,
            systemCodes: codes
        )
    }

    func hasCoreGraphicsPostEventAccess() -> Bool {
        MediaKeys.checkCoreGraphicsPostEventAccess()
    }

    func requestCoreGraphicsPostEventAccess() -> Bool {
        InputAccessCoordinator.shared.requestCoreGraphicsPostEventAccessIfNeeded()
    }

    func postUsingCoreGraphics(keyCode: UInt8) -> CoreGraphicsAuxiliaryPostResult {
        let raw = MediaKeys.postAuxKeyUsingCoreGraphics(keyCode)
        if raw.succeeded.boolValue {
            return .success
        }
        return .eventCreationFailed(
            "Core Graphics could not create the complete media-key down/up pair "
                + "(keyDown=\(raw.keyDownCreated.boolValue), keyUp=\(raw.keyUpCreated.boolValue))."
        )
    }
}

@discardableResult
func HIDPostAuxKey(
    _ key: Int32,
    backend: any MediaKeyInputBackend = SystemMediaKeyInputBackend()
) -> InputDispatchResult {
    guard let keyCode = UInt8(exactly: key) else {
        return InputDispatchDiagnostics.publish(InputDispatchResult(
            action: .mediaKey,
            backend: .none,
            status: .backendFailure,
            message: "Media-key code \(key) is outside the UInt8 range."
        ))
    }
    return MediaKeyInputDispatcher(backend: backend).send(keyCode: keyCode)
}
