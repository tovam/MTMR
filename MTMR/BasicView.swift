//
//  BasicView.swift
//  MTMR
//
//  Created by Fedor Zaitsev on 3/29/20.
//  Copyright © 2020 Anton Palgunov. All rights reserved.
//

import AppKit

private final class TouchBarZonesView: NSView {
    private let leftContainer = NSView()
    private let centerContainer = NSView()
    private let rightContainer = NSView()
    private let leftStack = TouchBarZonesView.makeStack()
    private let centerStack = TouchBarZonesView.makeStack()
    private let rightStack = TouchBarZonesView.makeStack()
    private var fillWidthConstraints: [ObjectIdentifier: NSLayoutConstraint] = [:]

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: TouchBarPhysicalLayout.preferredWidth,
            height: TouchBarPhysicalLayout.preferredHeight
        )
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        [leftContainer, centerContainer, rightContainer].forEach { container in
            container.wantsLayer = true
            container.layer?.masksToBounds = true
            addSubview(container)
        }
        install(leftStack, in: leftContainer, alignment: .left)
        install(centerStack, in: centerContainer, alignment: .center)
        install(rightStack, in: rightContainer, alignment: .right)
    }

    convenience init() {
        self.init(frame: NSRect(
            x: 0,
            y: 0,
            width: TouchBarPhysicalLayout.preferredWidth,
            height: TouchBarPhysicalLayout.preferredHeight
        ))
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        leftContainer.frame = TouchBarPhysicalLayout.frame(
            for: .left,
            containerWidth: bounds.width,
            containerHeight: bounds.height
        )
        centerContainer.frame = TouchBarPhysicalLayout.frame(
            for: .center,
            containerWidth: bounds.width,
            containerHeight: bounds.height
        )
        rightContainer.frame = TouchBarPhysicalLayout.frame(
            for: .right,
            containerWidth: bounds.width,
            containerHeight: bounds.height
        )
    }

    func update(left: [NSView], center: [NSView], right: [NSView]) {
        replaceArrangedSubviews(of: leftStack, with: left)
        replaceArrangedSubviews(of: centerStack, with: center)
        replaceArrangedSubviews(of: rightStack, with: right)
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    private enum ZoneAlignment {
        case left
        case center
        case right
    }

    private static func makeStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        // Without an explicit horizontal hugging priority AppKit may stretch an
        // intrinsic center stack to the full zone width. Its arranged views are
        // then laid out from that stretched stack's leading edge, so `center`
        // visually behaves like the left edge of the middle third.
        stack.setContentHuggingPriority(.required, for: .horizontal)
        return stack
    }

    private func install(_ stack: NSStackView, in container: NSView, alignment: ZoneAlignment) {
        container.addSubview(stack)
        let fillWidth = stack.widthAnchor.constraint(equalTo: container.widthAnchor)
        fillWidthConstraints[ObjectIdentifier(stack)] = fillWidth
        var constraints = [
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor),
            stack.heightAnchor.constraint(lessThanOrEqualTo: container.heightAnchor),
        ]
        switch alignment {
        case .left:
            constraints.append(stack.leadingAnchor.constraint(equalTo: container.leadingAnchor))
        case .center:
            constraints.append(stack.centerXAnchor.constraint(equalTo: container.centerXAnchor))
        case .right:
            constraints.append(stack.trailingAnchor.constraint(equalTo: container.trailingAnchor))
        }
        NSLayoutConstraint.activate(constraints)
    }

    private func replaceArrangedSubviews(of stack: NSStackView, with views: [NSView]) {
        let fillWidthConstraint = fillWidthConstraints[ObjectIdentifier(stack)]
        fillWidthConstraint?.isActive = false
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let unboundedScrollViews = views.compactMap { view -> NSScrollView? in
            guard let scrollView = view as? NSScrollView else { return nil }
            let hasWidth = scrollView.constraints.contains { constraint in
                constraint.isActive
                    && constraint.relation == .equal
                    && constraint.firstItem === scrollView
                    && constraint.firstAttribute == .width
            }
            return hasWidth ? nil : scrollView
        }
        let fillsAvailableWidth = !unboundedScrollViews.isEmpty
        stack.setContentHuggingPriority(fillsAvailableWidth ? .defaultLow : .required, for: .horizontal)
        for view in views {
            if let scrollView = view as? NSScrollView {
                // A scrollable widget may shrink when its natural width is wider
                // than its physical third, but it must not stretch the whole
                // stack. Stretching the stack moves a centered group to the
                // leading edge of the center zone.
                scrollView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                scrollView.setContentHuggingPriority(
                    unboundedScrollViews.contains { $0 === scrollView } ? .defaultLow : .defaultHigh,
                    for: .horizontal
                )
            }
            stack.addArrangedSubview(view)
        }
        // Preserve the historical fill behaviour only for scroll widgets that
        // deliberately have no width. Center scroll areas and auto-sized Docks
        // carry a natural-width constraint and therefore hug their content.
        fillWidthConstraint?.isActive = fillsAvailableWidth
    }
}

class BasicView: NSCustomTouchBarItem, NSGestureRecognizerDelegate {
    private let zonesView = TouchBarZonesView()
    var twofingers: NSPanGestureRecognizer!
    var threefingers: NSPanGestureRecognizer!
    var fourfingers: NSPanGestureRecognizer!
    var swipeItems: [SwipeItem] = []
    var prevPositions: [Int: CGFloat] = [2:0, 3:0, 4:0]

    // legacy gesture positions
    // by legacy I mean gestures to increse/decrease volume/brigtness which can be checked from app menu
    var legacyPrevPositions: [Int: CGFloat] = [2:0, 3:0, 4:0]
    var legacyGesturesEnabled = false

    init(
        identifier: NSTouchBarItem.Identifier,
        leftItems: [NSTouchBarItem],
        centerItems: [NSTouchBarItem],
        rightItems: [NSTouchBarItem],
        swipeItems: [SwipeItem]
    ) {
        super.init(identifier: identifier)
        view = zonesView
        update(
            leftItems: leftItems,
            centerItems: centerItems,
            rightItems: rightItems,
            swipeItems: swipeItems
        )

        twofingers = NSPanGestureRecognizer(target: self, action: #selector(twofingersHandler(_:)))
        twofingers.numberOfTouchesRequired = 2
        twofingers.allowedTouchTypes = .direct
        view.addGestureRecognizer(twofingers)

        threefingers = NSPanGestureRecognizer(target: self, action: #selector(threefingersHandler(_:)))
        threefingers.numberOfTouchesRequired = 3
        threefingers.allowedTouchTypes = .direct
        view.addGestureRecognizer(threefingers)

        fourfingers = NSPanGestureRecognizer(target: self, action: #selector(fourfingersHandler(_:)))
        fourfingers.numberOfTouchesRequired = 4
        fourfingers.allowedTouchTypes = .direct
        view.addGestureRecognizer(fourfingers)
    }

    func update(
        leftItems: [NSTouchBarItem],
        centerItems: [NSTouchBarItem],
        rightItems: [NSTouchBarItem],
        swipeItems: [SwipeItem]
    ) {
        self.swipeItems = swipeItems
        zonesView.update(
            left: leftItems.compactMap(\.view),
            center: centerItems.compactMap(\.view),
            right: rightItems.compactMap(\.view)
        )
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func gestureHandler(position: CGFloat, fingers: Int, state: NSGestureRecognizer.State) {
        switch state {
        case .began:
            prevPositions[fingers] = position
            legacyPrevPositions[fingers] = position
        case .changed:
            if self.legacyGesturesEnabled {
                if fingers == 2 {
                    let prevPos = legacyPrevPositions[fingers]!
                    if ((position - prevPos) > 10) || ((prevPos - position) > 10) {
                        if position > prevPos {
                            HIDPostAuxKey(NX_KEYTYPE_SOUND_UP)
                        } else if position < prevPos {
                            HIDPostAuxKey(NX_KEYTYPE_SOUND_DOWN)
                        }
                        legacyPrevPositions[fingers] = position
                    }
                }
                if fingers == 3 {
                    let prevPos = legacyPrevPositions[fingers]!
                    if ((position - prevPos) > 15) || ((prevPos - position) > 15) {
                        if position > prevPos {
                            HIDPostAuxKey(NX_KEYTYPE_BRIGHTNESS_UP)
                        } else if position < prevPos {
                            HIDPostAuxKey(NX_KEYTYPE_BRIGHTNESS_DOWN)
                        }
                        legacyPrevPositions[fingers] = position
                    }
                }
            }
        case .ended:
            print("gesture ended \(position - prevPositions[fingers]!) \(fingers)")
            for item in swipeItems {
                item.processEvent(offset: position - prevPositions[fingers]!, fingers: fingers)
            }
        default:
            break
        }
    }

    @objc func twofingersHandler(_ sender: NSGestureRecognizer?) {
        let position = (sender?.location(in: sender?.view).x)!
        self.gestureHandler(position: position, fingers: 2, state: sender!.state)
    }

    @objc func threefingersHandler(_ sender: NSGestureRecognizer?) {
        let position = (sender?.location(in: sender?.view).x)!
        self.gestureHandler(position: position, fingers: 3, state: sender!.state)
    }

    @objc func fourfingersHandler(_ sender: NSGestureRecognizer?) {
        let position = (sender?.location(in: sender?.view).x)!
        self.gestureHandler(position: position, fingers: 4, state: sender!.state)
    }
}
