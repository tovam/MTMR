//
//  BasicView.swift
//  MTMR
//
//  Created by Fedor Zaitsev on 3/29/20.
//  Copyright © 2020 Anton Palgunov. All rights reserved.
//

import AppKit
import QuartzCore

extension Notification.Name {
    static let mmtmrTouchBarContentSizeDidChange = Notification.Name("com.tovam.MMTMR.touchBarContentSizeDidChange")
}

private final class TouchBarZoneContentView: NSView {
    private(set) var itemViews: [NSView] = []
    private(set) var naturalSize = NSSize.zero
    private let spacing: CGFloat = TouchBarPhysicalLayout.groupSpacing

    func update(views: [NSView]) {
        itemViews.forEach { $0.removeFromSuperview() }
        itemViews = views
        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = true
            addSubview(view)
        }
        measure()
    }

    @discardableResult
    func measure() -> NSSize {
        let sizes = itemViews.map(Self.preferredSize)
        let totalSpacing = spacing * CGFloat(max(0, sizes.count - 1))
        naturalSize = NSSize(
            width: sizes.reduce(totalSpacing) { $0 + $1.width },
            height: sizes.map(\.height).max() ?? TouchBarPhysicalLayout.preferredHeight
        )
        return naturalSize
    }

    func layoutItems(height: CGFloat) {
        let sizes = itemViews.map(Self.preferredSize)
        let totalSpacing = spacing * CGFloat(max(0, sizes.count - 1))
        naturalSize = NSSize(
            width: sizes.reduce(totalSpacing) { $0 + $1.width },
            height: sizes.map(\.height).max() ?? TouchBarPhysicalLayout.preferredHeight
        )
        frame.size = NSSize(width: naturalSize.width, height: max(0, height))

        var x: CGFloat = 0
        for (view, preferredSize) in zip(itemViews, sizes) {
            let itemHeight = min(max(0, preferredSize.height), max(0, height))
            view.frame = NSRect(
                x: x,
                y: max(0, (height - itemHeight) / 2),
                width: max(0, preferredSize.width),
                height: itemHeight
            )
            x += preferredSize.width + spacing
        }
    }

    private static func preferredSize(of view: NSView) -> NSSize {
        NSSize(width: preferredWidth(of: view), height: preferredHeight(of: view))
    }

    private static func preferredWidth(of view: NSView) -> CGFloat {
        if let width = requiredConstant(for: .width, in: view) {
            return max(0, width)
        }
        if let scrollView = view as? NSScrollView {
            let documentWidth = scrollView.documentView?.fittingSize.width ?? 0
            if documentWidth.isFinite, documentWidth > 0 {
                return documentWidth
            }
        }
        let candidates = [view.fittingSize.width, view.intrinsicContentSize.width, view.frame.width]
        return max(0, candidates.first(where: { $0.isFinite && $0 > 0 }) ?? 0)
    }

    private static func preferredHeight(of view: NSView) -> CGFloat {
        if let height = requiredConstant(for: .height, in: view) {
            return max(0, height)
        }
        let candidates = [view.fittingSize.height, view.intrinsicContentSize.height, view.frame.height]
        return max(
            0,
            candidates.first(where: { $0.isFinite && $0 > 0 }) ?? TouchBarPhysicalLayout.preferredHeight
        )
    }

    private static func requiredConstant(
        for attribute: NSLayoutConstraint.Attribute,
        in view: NSView
    ) -> CGFloat? {
        let constants = view.constraints.compactMap { constraint -> CGFloat? in
            guard constraint.isActive,
                  constraint.priority == .required,
                  constraint.relation == .equal,
                  constraint.secondItem == nil,
                  constraint.firstItem === view,
                  constraint.firstAttribute == attribute
            else { return nil }
            return constraint.constant
        }
        // A dynamic script item may temporarily activate a zero-width hide
        // constraint alongside its configured width. In that case hiding wins.
        return constants.min()
    }
}

private final class TouchBarZoneScrollView: NSScrollView {
    enum Anchor: Equatable {
        case leading
        case center
        case trailing
    }

    private let zoneAnchor: Anchor
    private let zoneContent = TouchBarZoneContentView()
    private var hasEstablishedScrollPosition = false

    var naturalWidth: CGFloat {
        zoneContent.measure().width
    }

    var hasItems: Bool {
        !zoneContent.itemViews.isEmpty
    }

    init(anchor: Anchor) {
        zoneAnchor = anchor
        super.init(frame: .zero)
        drawsBackground = false
        borderType = .noBorder
        hasHorizontalScroller = false
        hasVerticalScroller = false
        autohidesScrollers = true
        horizontalScrollElasticity = .automatic
        verticalScrollElasticity = .none
        contentView.postsBoundsChangedNotifications = true
        documentView = zoneContent
        wantsLayer = true
        layer?.masksToBounds = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: contentView
        )
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func update(views: [NSView]) {
        zoneContent.update(views: views)
        hasEstablishedScrollPosition = false
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let oldMaximumOffset = maximumHorizontalOffset
        let oldOffset = contentView.bounds.minX
        let wasAtTrailingEdge = oldMaximumOffset > 0 && oldOffset >= oldMaximumOffset - 0.5

        zoneContent.layoutItems(height: contentSize.height)
        let newMaximumOffset = maximumHorizontalOffset
        let nextOffset: CGFloat
        if !hasEstablishedScrollPosition {
            switch zoneAnchor {
            case .leading: nextOffset = 0
            case .center: nextOffset = newMaximumOffset / 2
            case .trailing: nextOffset = newMaximumOffset
            }
            hasEstablishedScrollPosition = true
        } else if zoneAnchor == .trailing && (wasAtTrailingEdge || oldMaximumOffset == 0) {
            nextOffset = newMaximumOffset
        } else {
            nextOffset = min(max(0, oldOffset), newMaximumOffset)
        }
        contentView.scroll(to: NSPoint(x: nextOffset, y: 0))
        reflectScrolledClipView(contentView)
        updateFadeMask()
    }

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        updateFadeMask()
    }

    private var maximumHorizontalOffset: CGFloat {
        max(0, zoneContent.frame.width - contentSize.width)
    }

    @objc private func clipBoundsDidChange(_: Notification) {
        updateFadeMask()
    }

    private func updateFadeMask() {
        guard bounds.width > 0 else {
            layer?.mask = nil
            return
        }
        let maximumOffset = maximumHorizontalOffset
        let currentOffset = contentView.bounds.minX
        let hasLeadingOverflow = currentOffset > 0.5
        let hasTrailingOverflow = currentOffset < maximumOffset - 0.5
        guard hasLeadingOverflow || hasTrailingOverflow else {
            layer?.mask = nil
            return
        }

        let transparent = NSColor.black.withAlphaComponent(0).cgColor
        let opaque = NSColor.black.cgColor
        let gradient = CAGradientLayer()
        gradient.frame = bounds
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        switch (hasLeadingOverflow, hasTrailingOverflow) {
        case (true, true):
            gradient.colors = [transparent, opaque, opaque, transparent]
            gradient.locations = [0, 0.08, 0.92, 1]
        case (true, false):
            gradient.colors = [transparent, opaque, opaque]
            gradient.locations = [0, 0.08, 1]
        case (false, true):
            gradient.colors = [opaque, opaque, transparent]
            gradient.locations = [0, 0.92, 1]
        case (false, false):
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.mask = gradient
        CATransaction.commit()
    }
}

private final class TouchBarCalibrationOverlayView: NSView {
    private var centerX: CGFloat = 0
    private var pointsPerMillimeter: CGFloat = CGFloat(
        TouchBarCalibrationProfile.defaultPointsPerMillimeter
    )

    override var isOpaque: Bool { false }

    func update(active: Bool, centerX: CGFloat, pointsPerMillimeter: CGFloat) {
        isHidden = !active
        self.centerX = centerX
        self.pointsPerMillimeter = max(2, min(8, pointsPerMillimeter))
        setAccessibilityElement(active)
        if active {
            setAccessibilityLabel("Repère de calibration du centre physique")
            setAccessibilityValue("Zone de 30 millimètres centrée sur une ligne d’un pixel")
        }
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isHidden ? nil : (bounds.contains(point) ? self : nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !isHidden, let context = NSGraphicsContext.current else { return }

        context.saveGraphicsState()
        defer { context.restoreGraphicsState() }
        context.shouldAntialias = false

        let backingScale = max(
            1,
            window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        )
        let physicalPixel = 1 / backingScale
        let alignedCenterX = (centerX * backingScale).rounded() / backingScale
        let guideWidth = CGFloat(
            TouchBarLayoutRuntimeState.calibrationGuideWidthMillimeters
        ) * pointsPerMillimeter
        let guideRect = NSRect(
            x: alignedCenterX - guideWidth / 2,
            y: bounds.minY,
            width: guideWidth,
            height: bounds.height
        ).intersection(bounds)

        NSColor.systemRed.withAlphaComponent(0.16).setFill()
        guideRect.fill()

        NSColor.systemRed.withAlphaComponent(0.78).setFill()
        NSRect(
            x: alignedCenterX - guideWidth / 2 - physicalPixel / 2,
            y: bounds.minY,
            width: physicalPixel,
            height: bounds.height
        ).intersection(bounds).fill()
        NSRect(
            x: alignedCenterX + guideWidth / 2 - physicalPixel / 2,
            y: bounds.minY,
            width: physicalPixel,
            height: bounds.height
        ).intersection(bounds).fill()

        NSColor.systemRed.setFill()
        NSRect(
            x: alignedCenterX - physicalPixel / 2,
            y: bounds.minY,
            width: physicalPixel,
            height: bounds.height
        ).intersection(bounds).fill()
    }
}

private final class TouchBarZonesView: NSView {
    private let leftZone = TouchBarZoneScrollView(anchor: .leading)
    private let centerZone = TouchBarZoneScrollView(anchor: .center)
    private let rightZone = TouchBarZoneScrollView(anchor: .trailing)
    private let calibrationOverlay = TouchBarCalibrationOverlayView()
    private var layoutState = TouchBarLayoutRuntimeState(
        hardwareModel: TouchBarHardwareProfile.current.modelIdentifier,
        centerReference: .touchBar,
        centerOffset: 0,
        pointsPerMillimeter: TouchBarCalibrationProfile.defaultPointsPerMillimeter,
        calibrated: false,
        calibrationActive: false
    )

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: TouchBarPhysicalLayout.preferredWidth,
            height: TouchBarPhysicalLayout.preferredHeight
        )
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        [leftZone, centerZone, rightZone].forEach { zone in
            addSubview(zone)
        }
        addSubview(calibrationOverlay)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentSizeDidChange(_:)),
            name: .mmtmrTouchBarContentSizeDidChange,
            object: nil
        )
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

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        needsLayout = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let actualBounds = TouchBarPhysicalLayout.visibleBounds(bounds: bounds, visibleRect: visibleRect)
        let chassisCenterX = bounds.midX + CGFloat(layoutState.centerOffset)
        let layoutCenterX = layoutState.centerReference == .chassis
            ? chassisCenterX
            : actualBounds.midX
        let frames = TouchBarPhysicalLayout.frames(
            in: actualBounds,
            naturalWidths: TouchBarZoneWidths(
                left: leftZone.naturalWidth,
                center: centerZone.naturalWidth,
                right: rightZone.naturalWidth
            ),
            centerX: layoutCenterX
        )
        apply(frame: frames.left, to: leftZone)
        apply(frame: frames.center, to: centerZone)
        apply(frame: frames.right, to: rightZone)
        calibrationOverlay.frame = bounds
        calibrationOverlay.update(
            active: layoutState.calibrationActive,
            centerX: chassisCenterX,
            pointsPerMillimeter: CGFloat(layoutState.pointsPerMillimeter)
        )
    }

    func update(left: [NSView], center: [NSView], right: [NSView]) {
        // Detach every old item before adding any new one. This matters when an
        // item moves between alignments: removing the old center after adding
        // it to the left would otherwise detach it from its new parent.
        leftZone.update(views: [])
        centerZone.update(views: [])
        rightZone.update(views: [])
        leftZone.update(views: left)
        centerZone.update(views: center)
        rightZone.update(views: right)
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    func update(layoutState: TouchBarLayoutRuntimeState) {
        self.layoutState = layoutState
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    @objc private func contentSizeDidChange(_: Notification) {
        needsLayout = true
        superview?.needsLayout = true
    }

    private func apply(frame: CGRect, to zone: TouchBarZoneScrollView) {
        zone.isHidden = !zone.hasItems || frame.width <= 0.5
        zone.frame = frame
        zone.needsLayout = true
        zone.layoutSubtreeIfNeeded()
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

    func update(layoutState: TouchBarLayoutRuntimeState) {
        zonesView.update(layoutState: layoutState)
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
