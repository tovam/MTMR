//
//  TouchBarItems.swift
//  MTMR
//
//  Created by Anton Palgunov on 18/03/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Cocoa

struct ItemAction {
    typealias TriggerClosure = (() -> Void)?
    
    let trigger: Action.Trigger
    let closure: TriggerClosure
    
    init(trigger: Action.Trigger, _ closure: TriggerClosure) {
        self.trigger = trigger
        self.closure = closure
    }
}

class CustomButtonTouchBarItem: NSCustomTouchBarItem, NSGestureRecognizerDelegate {
    
    var actions: [ItemAction] = [] {
        didSet {
            multiClick.isDoubleClickEnabled = actions.filter({ $0.trigger == .doubleTap }).count > 0
            multiClick.isTripleClickEnabled = actions.filter({ $0.trigger == .tripleTap }).count > 0
            longClick.isEnabled = actions.filter({ $0.trigger == .longTap }).count > 0
        }
    }
    var finishViewConfiguration: ()->() = {}
    
    private var button: NSButton!
    private var longClick: LongPressGestureRecognizer!
    private var multiClick: MultiClickGestureRecognizer!

    init(identifier: NSTouchBarItem.Identifier, title: String) {
        attributedTitle = title.defaultTouchbarAttributedString

        super.init(identifier: identifier)
        button = CustomHeightButton(title: title, target: nil, action: nil)

        longClick = LongPressGestureRecognizer(target: self, action: #selector(handleGestureLong))
        longClick.isEnabled = false
        longClick.allowedTouchTypes = .direct
        longClick.delegate = self
        
        multiClick = MultiClickGestureRecognizer(
            target: self,
            action: #selector(handleGestureSingleTap),
            doubleAction: #selector(handleGestureDoubleTap),
            tripleAction: #selector(handleGestureTripleTap)
        )
        multiClick.allowedTouchTypes = .direct
        multiClick.delegate = self
        multiClick.isDoubleClickEnabled = false
        multiClick.isTripleClickEnabled = false

        reinstallButton()
        button.attributedTitle = attributedTitle
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isBordered: Bool = true {
        didSet {
            guard isBordered != oldValue else { return }
            reinstallButton()
            NotificationCenter.default.post(name: .mmtmrRuntimeVisualDidChange, object: nil)
        }
    }

    var backgroundColor: NSColor? {
        didSet {
            guard !Self.colorsAreEqual(backgroundColor, oldValue) else { return }
            reinstallButton()
            NotificationCenter.default.post(name: .mmtmrRuntimeVisualDidChange, object: nil)
        }
    }

    var title: String {
        get {
            return attributedTitle.string
        }
        set {
            let nextTitle = newValue.defaultTouchbarAttributedString
            guard !attributedTitle.isEqual(to: nextTitle) else { return }
            attributedTitle = nextTitle
        }
    }

    var attributedTitle: NSAttributedString {
        didSet {
            guard !attributedTitle.isEqual(to: oldValue) else { return }
            button?.imagePosition = attributedTitle.length > 0 ? .imageLeading : .imageOnly
            button?.attributedTitle = attributedTitle
            NotificationCenter.default.post(name: .mmtmrRuntimeVisualDidChange, object: nil)
        }
    }

    var image: NSImage? {
        didSet {
            guard !Self.imagesAreEqual(image, oldValue) else { return }
            button.image = image
            NotificationCenter.default.post(name: .mmtmrRuntimeVisualDidChange, object: nil)
        }
    }

    private static func colorsAreEqual(_ lhs: NSColor?, _ rhs: NSColor?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return lhs.isEqual(rhs)
        default:
            return false
        }
    }

    private static func imagesAreEqual(_ lhs: NSImage?, _ rhs: NSImage?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return lhs === rhs || lhs.isEqual(rhs)
        default:
            return false
        }
    }

    private func reinstallButton() {
        let title = button.attributedTitle
        let image = button.image
        let cell = CustomButtonCell(parentItem: self)
        button.cell = cell
        if let color = backgroundColor {
            cell.isBordered = true
            button.bezelColor = color
            button.bezelStyle = .rounded
            cell.backgroundColor = color
        } else {
            button.isBordered = isBordered
            button.bezelStyle = isBordered ? .rounded : .inline
        }
        button.imageScaling = .scaleProportionallyDown
        button.imageHugsTitle = true
        button.attributedTitle = title
        button?.imagePosition = title.length > 0 ? .imageLeading : .imageOnly
        button.image = image
        view = button

        view.addGestureRecognizer(longClick)
        // view.addGestureRecognizer(singleClick)
        view.addGestureRecognizer(multiClick)
        finishViewConfiguration()
    }

    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: NSGestureRecognizer) -> Bool {
        if gestureRecognizer == multiClick && otherGestureRecognizer == longClick
            || gestureRecognizer == longClick && otherGestureRecognizer == multiClick // need it
        {
            return false
        }
        return true
    }
    
    func callActions(for trigger: Action.Trigger) {
        let itemActions = self.actions.filter { $0.trigger == trigger }
        for itemAction in itemActions {
            itemAction.closure?()
        }
    }
    
    @objc func handleGestureSingleTap() {
        callActions(for: .singleTap)
    }
    
    @objc func handleGestureDoubleTap() {
        callActions(for: .doubleTap)
    }
    
    @objc func handleGestureTripleTap() {
        callActions(for: .tripleTap)
    }

    @objc func handleGestureLong(gr: NSPressGestureRecognizer) {
        switch gr.state {
        case .possible: // tiny hack because we're calling action manually
            multiClick.suppressCurrentTouchSequence()
            callActions(for: .longTap)
            break
        default:
            break
        }
    }
}

class CustomHeightButton: NSButton {
    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.height = 30
        return size
    }
}

class CustomButtonCell: NSButtonCell {
    weak var parentItem: CustomButtonTouchBarItem?

    init(parentItem: CustomButtonTouchBarItem) {
        super.init(textCell: "")
        self.parentItem = parentItem
    }

    override func highlight(_ flag: Bool, withFrame cellFrame: NSRect, in controlView: NSView) {
        super.highlight(flag, withFrame: cellFrame, in: controlView)
        if !isBordered {
            if flag {
                setAttributedTitle(attributedTitle, withColor: .lightGray)
            } else if let parentItem = self.parentItem {
                attributedTitle = parentItem.attributedTitle
            }
        }
    }
    
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        return rect // need that so content may better fit in button with very limited width
    }

    required init(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setAttributedTitle(_ title: NSAttributedString, withColor color: NSColor) {
        let attrTitle = NSMutableAttributedString(attributedString: title)
        attrTitle.addAttributes([.foregroundColor: color], range: NSRange(location: 0, length: attrTitle.length))
        attributedTitle = attrTitle
    }
}

// Thanks to https://stackoverflow.com/a/49843893
final class MultiClickGestureRecognizer: NSClickGestureRecognizer {

    private let _action: Selector
    private let _doubleAction: Selector
    private let _tripleAction: Selector
    private var sequenceState = TouchTapSequenceState()
    
    public var isDoubleClickEnabled = true
    public var isTripleClickEnabled = true

    override var action: Selector? {
        get {
            return nil /// prevent base class from performing any actions
        } set {
            if newValue != nil { // if they are trying to assign an actual action
                fatalError("Only use init(target:action:doubleAction) for assigning actions")
            }
        }
    }

    required init(target: AnyObject, action: Selector, doubleAction: Selector, tripleAction: Selector) {
        _action = action
        _doubleAction = doubleAction
        _tripleAction = tripleAction
        super.init(target: target, action: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(target:action:doubleAction:tripleAction) is only support atm")
    }
    
    override func touchesBegan(with event: NSEvent) {
        HapticFeedback.instance.tap(type: .click)
        super.touchesBegan(with: event)
    }

    override func touchesEnded(with event: NSEvent) {
        HapticFeedback.instance.tap(type: .back)
        super.touchesEnded(with: event)
        guard let clickCount = sequenceState.recordTouchEnd() else { return }
        
        var delayThreshold: TimeInterval // fine tune this as needed
        
        guard isDoubleClickEnabled || isTripleClickEnabled else {
            _ = target?.perform(_action)
            return
        }
        
        if (isTripleClickEnabled) {
            delayThreshold = 0.4
            perform(#selector(_resetAndPerformActionIfNecessary), with: nil, afterDelay: delayThreshold)
            if clickCount == 3 {
                _ = target?.perform(_tripleAction)
            }
        } else {
            delayThreshold = 0.3
            perform(#selector(_resetAndPerformActionIfNecessary), with: nil, afterDelay: delayThreshold)
            if clickCount == 2 {
                _ = target?.perform(_doubleAction)
            }
        }
    }

    override func touchesCancelled(with event: NSEvent) {
        sequenceState.reset()
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(_resetAndPerformActionIfNecessary),
            object: nil
        )
        super.touchesCancelled(with: event)
    }

    func suppressCurrentTouchSequence() {
        sequenceState.suppressCurrentTouchSequence()
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(_resetAndPerformActionIfNecessary),
            object: nil
        )
    }

    @objc private func _resetAndPerformActionIfNecessary() {
        if sequenceState.clickCount == 1 {
            _ = target?.perform(_action)
        }
        if isTripleClickEnabled && sequenceState.clickCount == 2 {
            _ = target?.perform(_doubleAction)
        }
        sequenceState.reset()
    }
}

class LongPressGestureRecognizer: NSPressGestureRecognizer {
    var recognizeTimeout = 0.4
    private var timer: Timer?
    
    override func touchesBegan(with event: NSEvent) {
        timerInvalidate()
        
        let touches = event.touches(for: self.view!)
        if touches.count == 1 { // to prevent it for built-in two/three-finger gestures
            timer = Timer.scheduledTimer(timeInterval: recognizeTimeout, target: self, selector: #selector(self.onTimer), userInfo: nil, repeats: false)
        }
        
        super.touchesBegan(with: event)
    }
    
    override func touchesMoved(with event: NSEvent) {
        timerInvalidate() // to prevent it for built-in two/three-finger gestures
        super.touchesMoved(with: event)
    }
    
    override func touchesCancelled(with event: NSEvent) {
        timerInvalidate()
        super.touchesCancelled(with: event)
    }
    
    override func touchesEnded(with event: NSEvent) {
        timerInvalidate()
        super.touchesEnded(with: event)
    }
    
    private func timerInvalidate() {
        if let timer = timer {
            timer.invalidate()
            self.timer = nil
        }
    }
    
    @objc private func onTimer() {
        if let target = self.target, let action = self.action {
            target.performSelector(onMainThread: action, with: self, waitUntilDone: false)
            HapticFeedback.instance.tap(type: .strong)
        }
    }
    
    isolated deinit {
        timerInvalidate()
    }
}

extension String {
    var defaultTouchbarAttributedString: NSAttributedString {
        let attrTitle = NSMutableAttributedString(string: self, attributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 15, weight: .regular), .baselineOffset: 1])
        attrTitle.setAlignment(.center, range: NSRange(location: 0, length: count))
        return attrTitle
    }
}
