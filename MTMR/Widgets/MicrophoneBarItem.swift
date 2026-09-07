import AppKit
import CoreAudio
import Foundation

/// A native input mute control. Core Audio delivers both device and property
/// changes to this item, so the Touch Bar never has to poll an AppleScript.
final class MicrophoneBarItem: NSCustomTouchBarItem {
    enum Status: Equatable {
        case active
        case muted
        case unavailable
    }

    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)
    private static let defaultInputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMaster
    )

    private let button: NSButton
    private var observedDevice: AudioObjectID = kAudioObjectUnknown
    private var observedMuteAddress: AudioObjectPropertyAddress?
    private var observedVolumeAddress: AudioObjectPropertyAddress?
    private var muteIsSettable = false
    private var volumeIsSettable = false
    private var lastKnownNonZeroVolume: [AudioObjectID: Float32] = [:]
    private var renderedStatus: Status?
    private var renderedEnabled = false
    private(set) var status: Status = .unavailable

    // Keep the block values alive for the matching Remove calls. Core Audio
    // identifies a listener by its block identity, not by a selector alone.
    private lazy var defaultDeviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        DispatchQueue.main.async { [weak self] in
            self?.switchToCurrentDefaultInput()
        }
    }

    private lazy var devicePropertyListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        DispatchQueue.main.async { [weak self] in
            self?.refreshStatus()
        }
    }

    override init(identifier: NSTouchBarItem.Identifier) {
        let initialImage = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Microphone")
            ?? NSImage(size: NSSize(width: 18, height: 18))
        button = NSButton(image: initialImage, target: nil, action: nil)
        super.init(identifier: identifier)

        button.target = self
        button.action = #selector(toggleMute)
        button.isBordered = false
        button.imageScaling = .scaleProportionallyDown
        button.setAccessibilityLabel("Microphone")
        view = button

        addDefaultDeviceListener()
        switchToCurrentDefaultInput()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        var address = Self.defaultInputAddress
        AudioObjectRemovePropertyListenerBlock(Self.systemObject, &address, nil, defaultDeviceListener)
        removeDeviceListeners()
    }

    private func addDefaultDeviceListener() {
        var address = Self.defaultInputAddress
        AudioObjectAddPropertyListenerBlock(Self.systemObject, &address, nil, defaultDeviceListener)
    }

    private func switchToCurrentDefaultInput() {
        removeDeviceListeners()
        observedDevice = Self.defaultInputDeviceID()
        guard observedDevice != kAudioObjectUnknown else {
            status = .unavailable
            updateButton()
            return
        }

        let muteAddress = Self.address(selector: kAudioDevicePropertyMute)
        if Self.hasProperty(observedDevice, address: muteAddress) {
            observedMuteAddress = muteAddress
            muteIsSettable = Self.isSettable(observedDevice, address: muteAddress)
            addListener(muteAddress)
        }

        let volumeAddress = Self.address(selector: kAudioDevicePropertyVolumeScalar)
        if Self.hasProperty(observedDevice, address: volumeAddress) {
            observedVolumeAddress = volumeAddress
            volumeIsSettable = Self.isSettable(observedDevice, address: volumeAddress)
            addListener(volumeAddress)
        }

        refreshStatus()
    }

    private func addListener(_ address: AudioObjectPropertyAddress) {
        var address = address
        AudioObjectAddPropertyListenerBlock(observedDevice, &address, nil, devicePropertyListener)
    }

    private func removeDeviceListeners() {
        guard observedDevice != kAudioObjectUnknown else { return }
        if var address = observedMuteAddress {
            AudioObjectRemovePropertyListenerBlock(observedDevice, &address, nil, devicePropertyListener)
        }
        if var address = observedVolumeAddress {
            AudioObjectRemovePropertyListenerBlock(observedDevice, &address, nil, devicePropertyListener)
        }
        observedMuteAddress = nil
        observedVolumeAddress = nil
        muteIsSettable = false
        volumeIsSettable = false
        observedDevice = kAudioObjectUnknown
    }

    private func refreshStatus() {
        guard observedDevice != kAudioObjectUnknown else {
            status = .unavailable
            updateButton()
            return
        }

        if muteIsSettable, let muteAddress = observedMuteAddress,
           let muted = Self.readUInt32(observedDevice, address: muteAddress) {
            status = muted != 0 ? .muted : .active
        } else if let volumeAddress = observedVolumeAddress, let volume = Self.readFloat(observedDevice, address: volumeAddress) {
            if let safe = Self.safeVolume(volume), safe > 0 {
                lastKnownNonZeroVolume[observedDevice] = safe
            }
            status = volume <= 0 ? .muted : .active
        } else if let muteAddress = observedMuteAddress,
                  let muted = Self.readUInt32(observedDevice, address: muteAddress) {
            // Some devices expose a readable but immutable mute state. Display
            // it accurately while leaving the button disabled.
            status = muted != 0 ? .muted : .active
        } else {
            status = .unavailable
        }
        updateButton()
    }

    @objc private func toggleMute() {
        guard observedDevice != kAudioObjectUnknown else { return }

        if muteIsSettable, let address = observedMuteAddress, let muted = Self.readUInt32(observedDevice, address: address) {
            var value: UInt32 = muted == 0 ? 1 : 0
            var mutableAddress = address
            guard AudioObjectSetPropertyData(
                observedDevice,
                &mutableAddress,
                0,
                nil,
                UInt32(MemoryLayout<UInt32>.size),
                &value
            ) == noErr else { return }
        } else {
            toggleVolumeFallback()
        }
        refreshStatus()
    }

    /// A number of microphones expose input volume but no mute property. In
    /// that case zero is used only as a reversible mute, with the previous
    /// finite scalar retained per device for restoration.
    private func toggleVolumeFallback() {
        guard volumeIsSettable, let address = observedVolumeAddress,
              let current = Self.readFloat(observedDevice, address: address) else { return }

        let target: Float32
        if current > 0 {
            guard let safe = Self.safeVolume(current) else { return }
            lastKnownNonZeroVolume[observedDevice] = safe
            target = 0
        } else {
            target = lastKnownNonZeroVolume[observedDevice] ?? 0.7
        }
        var mutableAddress = address
        var value = target
        guard value.isFinite, (0...1).contains(value) else { return }
        _ = AudioObjectSetPropertyData(
            observedDevice,
            &mutableAddress,
            0,
            nil,
            UInt32(MemoryLayout<Float32>.size),
            &value
        )
    }

    private func updateButton() {
        let enabled = status != .unavailable && (muteIsSettable || volumeIsSettable)
        guard status != renderedStatus || enabled != renderedEnabled else { return }
        renderedStatus = status
        renderedEnabled = enabled

        let symbol: String
        let label: String
        switch status {
        case .active:
            symbol = "mic.fill"
            label = "Microphone active"
        case .muted:
            symbol = "mic.slash.fill"
            label = "Microphone muted"
        case .unavailable:
            symbol = "mic.slash"
            label = "Microphone unavailable"
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.setAccessibilityLabel(label)
        button.isEnabled = enabled
        NotificationCenter.default.post(name: .mmtmrRuntimeVisualDidChange, object: nil)
    }

    private static func address(selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMaster
        )
    }

    private static func defaultInputDeviceID() -> AudioObjectID {
        var address = defaultInputAddress
        var device = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &device) == noErr else {
            return kAudioObjectUnknown
        }
        return device
    }

    private static func hasProperty(_ device: AudioObjectID, address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        return AudioObjectHasProperty(device, &address)
    }

    private static func isSettable(_ device: AudioObjectID, address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    private static func readUInt32(_ device: AudioObjectID, address: AudioObjectPropertyAddress) -> UInt32? {
        var address = address
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func readFloat(_ device: AudioObjectID, address: AudioObjectPropertyAddress) -> Float32? {
        var address = address
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func safeVolume(_ value: Float32) -> Float32? {
        guard value.isFinite, value > 0, value <= 1 else { return nil }
        return value
    }
}
