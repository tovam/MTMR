//
//  KeyPress.swift
//  MTMR
//
//  Created by Anton Palgunov on 17/03/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Foundation

protocol KeyPress {
    var keyCode: CGKeyCode { get }
    func send()
}

struct GenericKeyPress: KeyPress {
    var keyCode: CGKeyCode
}

struct UnicodeTextInput {
    let text: String

    func send() {
        let codeUnits = Array(text.utf16)
        guard !codeUnits.isEmpty else { return }

        guard
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
        else { return }

        codeUnits.withUnsafeBufferPointer { buffer in
            keyDown.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
            keyUp.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)

            let location: CGEventTapLocation = .cghidEventTap
            keyDown.post(tap: location)
            keyUp.post(tap: location)
        }
    }
}

extension KeyPress {
    func send() {
        let src = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)

        let loc: CGEventTapLocation = .cghidEventTap
        keyDown?.post(tap: loc)
        keyUp?.post(tap: loc)
    }
}

func HIDPostAuxKey(_ key: Int32) {
    let key = UInt8(key)
    MediaKeys.hidPostAuxKey(key)
}
