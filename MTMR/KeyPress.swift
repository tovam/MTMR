//
//  KeyPress.swift
//  MTMR
//
//  Created by Anton Palgunov on 17/03/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Foundation
import CoreAudio
import CoreGraphics
import AudioToolbox

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

/// Volume and display brightness are controls, not keyboard input. Driving
/// their native subsystems first makes the dedicated Touch Bar buttons work
/// immediately even when macOS has not granted PostEvent/Accessibility access.
private enum DirectSystemControl {
    private static let step: Float32 = 1.0 / 16.0

    static func send(keyCode: Int32) -> InputDispatchResult? {
        switch keyCode {
        case NX_KEYTYPE_SOUND_DOWN:
            return adjustVolume(by: -step)
        case NX_KEYTYPE_SOUND_UP:
            return adjustVolume(by: step)
        case NX_KEYTYPE_MUTE:
            return toggleMute()
        case NX_KEYTYPE_BRIGHTNESS_DOWN:
            return adjustBrightness(by: -step)
        case NX_KEYTYPE_BRIGHTNESS_UP:
            return adjustBrightness(by: step)
        default:
            return nil
        }
    }

    private static func adjustVolume(by delta: Float32) -> InputDispatchResult? {
        guard let device = defaultOutputDevice(),
              let current = readFloatProperty(
                  device: device,
                  selector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume
              )
        else { return nil }

        let next = min(1, max(0, current + delta))
        let volumeStatus = writeFloatProperty(
            next,
            device: device,
            selector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume
        )
        guard volumeStatus == noErr else { return nil }

        // Match the system volume keys: zero mutes and raising the volume
        // releases mute. A device without a writable mute property is still a
        // successful volume adjustment.
        _ = writeUInt32Property(next == 0 ? 1 : 0, device: device, selector: kAudioDevicePropertyMute)
        return InputDispatchResult(
            action: .mediaKey,
            backend: .coreAudio,
            status: .success,
            message: "The output volume was changed directly through Core Audio."
        )
    }

    private static func toggleMute() -> InputDispatchResult? {
        guard let device = defaultOutputDevice(),
              let current = readUInt32Property(device: device, selector: kAudioDevicePropertyMute)
        else { return nil }
        let status = writeUInt32Property(current == 0 ? 1 : 0, device: device, selector: kAudioDevicePropertyMute)
        guard status == noErr else { return nil }
        return InputDispatchResult(
            action: .mediaKey,
            backend: .coreAudio,
            status: .success,
            message: "Output mute was changed directly through Core Audio."
        )
    }

    private static func adjustBrightness(by delta: Float32) -> InputDispatchResult? {
        let displayID = CGMainDisplayID()
        let current = CoreDisplay_Display_GetUserBrightness(Int32(bitPattern: displayID))
        guard current.isFinite, current >= 0, current <= 1 else { return nil }
        let next = min(1, max(0, current + Double(delta)))
        CoreDisplay_Display_SetUserBrightness(Int32(bitPattern: displayID), next)
        return InputDispatchResult(
            action: .mediaKey,
            backend: .coreDisplay,
            status: .success,
            message: "Display brightness was changed directly through CoreDisplay."
        )
    }

    private static func defaultOutputDevice() -> AudioObjectID? {
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout.size(ofValue: device))
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        )
        return status == noErr && device != 0 ? device : nil
    }

    private static func readFloatProperty(
        device: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> Float32? {
        var value = Float32.zero
        var size = UInt32(MemoryLayout.size(ofValue: value))
        var address = outputAddress(selector: selector)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr && value.isFinite ? value : nil
    }

    private static func writeFloatProperty(
        _ value: Float32,
        device: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> OSStatus {
        var value = value
        var address = outputAddress(selector: selector)
        return AudioObjectSetPropertyData(
            device,
            &address,
            0,
            nil,
            UInt32(MemoryLayout.size(ofValue: value)),
            &value
        )
    }

    private static func readUInt32Property(
        device: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> UInt32? {
        var value = UInt32.zero
        var size = UInt32(MemoryLayout.size(ofValue: value))
        var address = outputAddress(selector: selector)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private static func writeUInt32Property(
        _ value: UInt32,
        device: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> OSStatus {
        var value = value
        var address = outputAddress(selector: selector)
        return AudioObjectSetPropertyData(
            device,
            &address,
            0,
            nil,
            UInt32(MemoryLayout.size(ofValue: value)),
            &value
        )
    }

    private static func outputAddress(
        selector: AudioObjectPropertySelector
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}

@discardableResult
func HIDPostAuxKey(
    _ key: Int32,
    backend: any MediaKeyInputBackend = SystemMediaKeyInputBackend(),
    directFallback: (Int32) -> InputDispatchResult? = { DirectSystemControl.send(keyCode: $0) }
) -> InputDispatchResult {
    guard let keyCode = UInt8(exactly: key) else {
        return InputDispatchDiagnostics.publish(InputDispatchResult(
            action: .mediaKey,
            backend: .none,
            status: .backendFailure,
            message: "Media-key code \(key) is outside the UInt8 range."
        ))
    }

    // A genuine auxiliary-key event lets macOS perform the operation and show
    // its native volume/brightness OSD. Direct CoreAudio/CoreDisplay writes are
    // retained only for machines where neither PostEvent backend can dispatch
    // the key. Never fall back after a partial post, which could apply the
    // command twice.
    let mediaResult = MediaKeyInputDispatcher(backend: backend).send(
        keyCode: keyCode,
        publishDiagnostics: false
    )
    if mediaResult.succeeded || mediaResult.status == .partialDispatch {
        return InputDispatchDiagnostics.publish(mediaResult)
    }
    if let directResult = directFallback(key) {
        return InputDispatchDiagnostics.publish(directResult)
    }
    return InputDispatchDiagnostics.publish(mediaResult)
}
