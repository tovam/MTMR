//
//  TouchBar.swift
//  MTMR
//
//  Created by Anton Palgunov on 18/03/2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.
//

import Cocoa

struct RuntimeBarItem {
    let id: String
    let kind: String
    let sourcePath: String
    let fingerprint: String
    let definition: BarItemDefinition
}

struct RuntimeBarGeometry: Sendable {
    let id: String
    let align: String
    let x: Double?
    let width: Double
    let height: Double
    let visible: Bool
    let kind: String
    let title: String?
    let renderedImage: String?
    let renderedImageChanged: Bool
}

@MainActor
protocol RuntimeRenderSignatureProviding: AnyObject {
    var runtimeRenderSignature: String { get }
}

extension ItemType {
    var canonicalJSONType: String {
        switch self {
        case .staticButton(title: _): return "staticButton"
        case .appleScriptTitledButton(source: _, refreshInterval: _, alternativeImages: _): return "appleScriptTitledButton"
        case .shellScriptTitledButton(source: _, refreshInterval: _): return "shellScriptTitledButton"
        case .timeButton(formatTemplate: _, timeZone: _, locale: _): return "timeButton"
        case .battery: return "battery"
        case .cpu(refreshInterval: _): return "cpu"
        case .memory(refreshInterval: _): return "memory"
        case .dock(autoResize: _, filter: _): return "dock"
        case .pinnedDock(autoResize: _, applications: _, showRunningIndicator: _, longPressAction: _, spacing: _): return "pinnedDock"
        case .volume: return "volume"
        case .brightness(refreshInterval: _): return "brightness"
        case .weather(interval: _, units: _, api_key: _, icon_type: _): return "weather"
        case .yandexWeather(interval: _): return "yandexWeather"
        case .currency(interval: _, from: _, to: _, full: _): return "currency"
        case .inputsource: return "inputsource"
        case .music(interval: _, disableMarquee: _): return "music"
        case .group(items: _): return "group"
        case .nightShift: return "nightShift"
        case .dnd: return "dnd"
        case .pomodoro(workTime: _, restTime: _): return "pomodoro"
        case .network(flip: _, units: _): return "network"
        case .darkMode: return "darkMode"
        case .swipe(direction: _, fingers: _, minOffset: _, sourceApple: _, sourceBash: _): return "swipe"
        case .upnext(interval: _, from: _, to: _, maxToShow: _, autoResize: _): return "upnext"
        }
    }

    var identifierBase: String {
        switch self {
        case .staticButton(title: _):
            return "com.tovam.MMTMR.staticButton."
        case .appleScriptTitledButton(source: _, refreshInterval: _, alternativeImages: _):
            return "com.tovam.MMTMR.appleScriptButton."
        case .shellScriptTitledButton(source: _, refreshInterval: _):
            return "com.tovam.MMTMR.shellScriptButton."
        case .timeButton(formatTemplate: _, timeZone: _, locale: _):
            return "com.tovam.MMTMR.timeButton."
        case .battery:
            return "com.tovam.MMTMR.battery."
        case .cpu(refreshInterval: _):
            return "com.tovam.MMTMR.cpu."
        case .memory(refreshInterval: _):
            return "com.tovam.MMTMR.memory."
        case .dock(autoResize: _, filter: _):
            return "com.tovam.MMTMR.dock"
        case .pinnedDock(autoResize: _, applications: _, showRunningIndicator: _, longPressAction: _, spacing: _):
            return "com.tovam.MMTMR.pinnedDock"
        case .volume:
            return "com.tovam.MMTMR.volume"
        case .brightness(refreshInterval: _):
            return "com.tovam.MMTMR.brightness"
        case .weather(interval: _, units: _, api_key: _, icon_type: _):
            return "com.tovam.MMTMR.weather"
        case .yandexWeather(interval: _):
            return "com.tovam.MMTMR.yandexWeather"
        case .currency(interval: _, from: _, to: _, full: _):
            return "com.tovam.MMTMR.currency"
        case .inputsource:
            return "com.tovam.MMTMR.inputsource."
        case .music(interval: _, disableMarquee: _):
            return "com.tovam.MMTMR.music."
        case .group(items: _):
            return "com.tovam.MMTMR.groupBar."
        case .nightShift:
            return "com.tovam.MMTMR.nightShift."
        case .dnd:
            return "com.tovam.MMTMR.dnd."
        case .pomodoro(workTime: _, restTime: _):
            return "com.tovam.MMTMR.pomodoro."
        case .network(flip: _, units: _):
            return "com.tovam.MMTMR.network."
        case .darkMode:
            return "com.tovam.MMTMR.darkMode."
        case .swipe(direction: _, fingers: _, minOffset: _, sourceApple: _, sourceBash: _):
            return "com.tovam.MMTMR.swipe."
        case .upnext(interval: _, from: _, to: _, maxToShow: _, autoResize: _):
            return "com.connorgmeehan.mtmrup.next."
        }
    }
}

extension NSTouchBarItem.Identifier {
    static let controlStripItem = NSTouchBarItem.Identifier("com.tovam.MMTMR.controlStrip")
}

@MainActor
class TouchBarController: NSObject, NSTouchBarDelegate {
    static let shared = TouchBarController()

    var touchBar: NSTouchBar!

    var jsonItems: [BarItemDefinition] = []
    var itemDefinitions: [NSTouchBarItem.Identifier: BarItemDefinition] = [:]
    private var definitionFingerprints: [NSTouchBarItem.Identifier: String] = [:]
    private var definitionIDs: [NSTouchBarItem.Identifier: String] = [:]
    private var definitionKinds: [NSTouchBarItem.Identifier: String] = [:]
    private var renderedFingerprints: [NSTouchBarItem.Identifier: String] = [:]
    private var renderedOrder: [NSTouchBarItem.Identifier] = []
    private struct RuntimeRenderCacheEntry {
        let signature: String
        let renderedImage: String?
    }
    private var runtimeRenderCache: [String: RuntimeRenderCacheEntry] = [:]
    private static let runtimeRenderMaximumPixelSize = NSSize(width: 240, height: 64)
    private static let runtimeRenderMaximumPNGBytes = 64 * 1024
    private static let runtimeRenderMaximumCacheCharacters = 384 * 1024
    var items: [NSTouchBarItem.Identifier: NSTouchBarItem] = [:]
    var leftIdentifiers: [NSTouchBarItem.Identifier] = []
    var centerIdentifiers: [NSTouchBarItem.Identifier] = []
    var rightIdentifiers: [NSTouchBarItem.Identifier] = []
    let basicViewIdentifier = NSTouchBarItem.Identifier("com.tovam.MMTMR.scrollView")
    var basicView: BasicView?
    var swipeItems: [SwipeItem] = []

    var blacklistAppIdentifiers: [String] = []
    var frontmostApplicationIdentifier: String? {
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    private override init() {
        super.init()
        SupportedTypesHolder.sharedInstance.register(
            typename: "exitTouchbar",
            item: .staticButton(title: "exit"),
            actions: [
                Action(trigger: .singleTap, value: .custom(closure: { [weak self] in self?.dismissTouchBar() }))
            ],
            legacyAction: .none,
            legacyLongAction: .none
        )

        SupportedTypesHolder.sharedInstance.register(typename: "close") { _ in
            (
                item: .staticButton(title: ""),
                actions: [
                    Action(trigger: .singleTap, value: .custom(closure: { [weak self] in
                        self?.restoreRootPreset()
                    }))
                ],
                legacyAction: .none,
                legacyLongAction: .none,
                parameters: [.width: .width(30), .image: .image(source: (NSImage(named: NSImage.stopProgressFreestandingTemplateName))!)])
        }

        blacklistAppIdentifiers = AppSettings.blacklistedAppIds

        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeApplicationChanged), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeApplicationChanged), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeApplicationChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)

    }

    func createAndUpdatePreset(newJsonItems: [BarItemDefinition]) {
        let runtimeItems = newJsonItems.enumerated().map { index, definition in
            RuntimeBarItem(
                id: "legacy-\(index)",
                kind: definition.type.canonicalJSONType,
                sourcePath: "$[\(index)]",
                fingerprint: "legacy-\(index)-\(String(describing: definition.type))",
                definition: definition
            )
        }
        apply(runtimeItems: runtimeItems)
    }

    func apply(runtimeItems: [RuntimeBarItem]) {
        if touchBar == nil {
            touchBar = NSTouchBar()
        }
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [basicViewIdentifier]

        jsonItems = runtimeItems.map(\.definition)
        itemDefinitions = [:]
        definitionFingerprints = [:]
        definitionIDs = [:]
        definitionKinds = [:]

        loadItemDefinitions(runtimeItems: runtimeItems)
        
        updateActiveApp()
    }
    
    func didItemsChange(prevItems: [NSTouchBarItem.Identifier: NSTouchBarItem], prevSwipeItems: [SwipeItem]) -> Bool {
        if Set(items.keys) != Set(prevItems.keys) {
            return true
        }

        return swipeItems.map(\.identifier) != prevSwipeItems.map(\.identifier)
    }
    
    func prepareTouchBar() {
        guard touchBar != nil else { return }

        let prevItems = items
        let prevSwipeItems = swipeItems
        let previousFingerprints = renderedFingerprints
        let previousOrder = renderedOrder

        createItems()

        let newOrder = leftIdentifiers + centerIdentifiers + rightIdentifiers
        let changed = previousOrder != newOrder
            || previousFingerprints != renderedFingerprints
            || didItemsChange(prevItems: prevItems, prevSwipeItems: prevSwipeItems)
        renderedOrder = newOrder

        if !changed {
            return
        }
        
        let centerItems = centerIdentifiers.compactMap({ (identifier) -> NSTouchBarItem? in
            items[identifier]
        })

        let leftItems = leftIdentifiers.compactMap({ (identifier) -> NSTouchBarItem? in
            items[identifier]
        })
        let rightItems = rightIdentifiers.compactMap({ (identifier) -> NSTouchBarItem? in
            items[identifier]
        })

        if let basicView {
            basicView.update(
                leftItems: leftItems,
                centerItems: centerItems,
                rightItems: rightItems,
                swipeItems: swipeItems
            )
        } else {
            basicView = BasicView(
                identifier: basicViewIdentifier,
                leftItems: leftItems,
                centerItems: centerItems,
                rightItems: rightItems,
                swipeItems: swipeItems
            )
        }
        basicView?.legacyGesturesEnabled = AppSettings.multitouchGestures
    }

    @objc func activeApplicationChanged(_: Notification) {
        updateActiveApp()
    }

    func updateActiveApp() {
        if frontmostApplicationIdentifier != nil && blacklistAppIdentifiers.firstIndex(of: frontmostApplicationIdentifier!) != nil {
            dismissTouchBar()
        } else {
            prepareTouchBar()
            if touchBarContainsAnyItems() {
                presentTouchBar()
            } else {
                dismissTouchBar()
            }
        }
    }
    
    func touchBarContainsAnyItems() -> Bool {
        return items.count != 0 || swipeItems.count != 0
    }

    func restoreRootPreset() {
        guard touchBar != nil else { return }
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [basicViewIdentifier]
        updateActiveApp()
    }

    func loadItemDefinitions(runtimeItems: [RuntimeBarItem]) {
        leftIdentifiers = []
        centerIdentifiers = []
        rightIdentifiers = []

        for runtimeItem in runtimeItems {
            let item = runtimeItem.definition
            let identifierString = item.type.identifierBase.appending(runtimeItem.id)
            let identifier = NSTouchBarItem.Identifier(identifierString)
            itemDefinitions[identifier] = item
            definitionFingerprints[identifier] = runtimeItem.fingerprint
            definitionIDs[identifier] = runtimeItem.id
            definitionKinds[identifier] = runtimeItem.kind
            if item.align == .left {
                leftIdentifiers.append(identifier)
            }
            if item.align == .right {
                rightIdentifiers.append(identifier)
            }
            if item.align == .center {
                centerIdentifiers.append(identifier)
            }
        }
    }

    func createItems() {
        let previousItems = items
        let previousSwipeItems = Dictionary(uniqueKeysWithValues: swipeItems.map { ($0.identifier, $0) })
        var nextItems: [NSTouchBarItem.Identifier: NSTouchBarItem] = [:]
        var nextSwipeItems: [SwipeItem] = []

        for identifier in leftIdentifiers + centerIdentifiers + rightIdentifiers {
            guard let definition = itemDefinitions[identifier] else { continue }
            var show = true
            
            if let frontApp = frontmostApplicationIdentifier {
                if case let .matchAppId(regexString)? = definition.additionalParameters[.matchAppId] {
                    guard let regex = try? NSRegularExpression(pattern: regexString) else {
                        // The strict validator rejects malformed expressions. Keep
                        // this defensive check for legacy in-process definitions.
                        continue
                    }
                    let range = NSRange(frontApp.startIndex..<frontApp.endIndex, in: frontApp)
                    if regex.firstMatch(in: frontApp, range: range) == nil {
                        show = false
                    }
                }
            }
            
            if show {
                let item: NSTouchBarItem?
                let previousItem = previousItems[identifier] ?? previousSwipeItems[identifier]
                if renderedFingerprints[identifier] == definitionFingerprints[identifier],
                   let previousItem {
                    item = previousItem
                } else {
                    item = createItem(forIdentifier: identifier, definition: definition)
                }
                if item is SwipeItem {
                    nextSwipeItems.append(item as! SwipeItem)
                } else {
                    nextItems[identifier] = item
                }
            }
        }

        items = nextItems
        swipeItems = nextSwipeItems
        renderedFingerprints = definitionFingerprints
    }

    func runtimeGeometry() -> [RuntimeBarGeometry] {
        let identifiers = leftIdentifiers + centerIdentifiers + rightIdentifiers
        let activeIDs = Set(identifiers.compactMap { definitionIDs[$0] })
        for cachedID in Array(runtimeRenderCache.keys) where !activeIDs.contains(cachedID) {
            runtimeRenderCache.removeValue(forKey: cachedID)
        }

        return identifiers.compactMap { identifier in
            guard let id = definitionIDs[identifier],
                  let definition = itemDefinitions[identifier],
                  let kind = definitionKinds[identifier]
            else { return nil }
            let item = items[identifier] ?? swipeItems.first(where: { $0.identifier == identifier })
            let view = item?.view
            let frame = runtimeFrame(of: view)
            let size = frame?.size ?? runtimeSize(of: view)
            let title = runtimeTitle(for: item, view: view)
            let signature = runtimeRenderSignature(
                identifier: identifier,
                item: item,
                view: view,
                title: title,
                kind: kind
            )
            let render = runtimeRenderedImage(id: id, view: view, signature: signature)
            return RuntimeBarGeometry(
                id: id,
                align: definition.align.rawValue,
                x: frame.map { Double($0.minX) },
                width: Double(size.width),
                height: Double(size.height),
                visible: item != nil,
                kind: kind,
                title: title,
                renderedImage: render.image,
                renderedImageChanged: render.changed
            )
        }
    }

    private func runtimeFrame(of view: NSView?) -> NSRect? {
        guard let view, let rootView = basicView?.view else { return nil }
        rootView.layoutSubtreeIfNeeded()
        view.layoutSubtreeIfNeeded()
        let frame = view.convert(view.bounds, to: rootView)
        guard frame.origin.x.isFinite, frame.origin.y.isFinite,
              frame.width.isFinite, frame.height.isFinite,
              frame.width > 0, frame.height > 0
        else { return nil }
        return frame
    }

    private func runtimeSize(of view: NSView?) -> NSSize {
        guard let view else { return .zero }
        let candidates = [view.bounds.size, view.frame.size, view.fittingSize]
        return candidates.first(where: { $0.width.isFinite && $0.height.isFinite && $0.width > 0 && $0.height > 0 }) ?? .zero
    }

    private func runtimeTitle(for item: NSTouchBarItem?, view: NSView?) -> String? {
        if let buttonItem = item as? CustomButtonTouchBarItem {
            return nonEmptyRuntimeTitle(buttonItem.title)
        }
        guard let view else { return nil }
        if let button = firstRuntimeSubview(of: NSButton.self, in: view) {
            return nonEmptyRuntimeTitle(button.attributedTitle.string) ?? nonEmptyRuntimeTitle(button.title)
        }
        if let textField = firstRuntimeSubview(of: NSTextField.self, in: view) {
            return nonEmptyRuntimeTitle(textField.attributedStringValue.string) ?? nonEmptyRuntimeTitle(textField.stringValue)
        }
        return nil
    }

    private func nonEmptyRuntimeTitle(_ value: String) -> String? {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    }

    private func firstRuntimeSubview<View: NSView>(
        of type: View.Type,
        in view: NSView,
        depth: Int = 0
    ) -> View? {
        if let match = view as? View { return match }
        guard depth < 12 else { return nil }
        for subview in view.subviews.prefix(64) {
            if let match = firstRuntimeSubview(of: type, in: subview, depth: depth + 1) {
                return match
            }
        }
        return nil
    }

    private func runtimeRenderSignature(
        identifier: NSTouchBarItem.Identifier,
        item: NSTouchBarItem?,
        view: NSView?,
        title: String?,
        kind: String
    ) -> String {
        var components = [
            definitionFingerprints[identifier] ?? "",
            item == nil ? "hidden" : "visible",
            title ?? "",
            kind,
        ]
        var remainingViews = 256
        if let view {
            appendRuntimeViewSignature(view, depth: 0, remainingViews: &remainingViews, to: &components)
        }
        return ConfigContentHasher.sha256(Data(components.joined(separator: "|").utf8))
    }

    private func appendRuntimeViewSignature(
        _ view: NSView,
        depth: Int,
        remainingViews: inout Int,
        to components: inout [String]
    ) {
        guard remainingViews > 0, depth < 12 else { return }
        remainingViews -= 1
        components.append(String(describing: type(of: view)))
        components.append(runtimeRectSignature(view.frame))
        components.append(runtimeRectSignature(view.bounds))
        components.append(view.isHidden ? "hidden" : "shown")
        components.append(runtimeNumberSignature(view.alphaValue))
        if let provider = view as? RuntimeRenderSignatureProviding {
            components.append(provider.runtimeRenderSignature)
        }

        if let button = view as? NSButton {
            components.append(button.attributedTitle.string)
            components.append(button.title)
            components.append(String(button.state.rawValue))
            components.append(button.isEnabled ? "enabled" : "disabled")
            components.append(button.isBordered ? "bordered" : "unbordered")
            components.append(String(button.bezelStyle.rawValue))
            components.append(String(button.imagePosition.rawValue))
            appendRuntimeImageSignature(button.image, to: &components)
        } else if let textField = view as? NSTextField {
            components.append(textField.attributedStringValue.string)
            components.append(textField.stringValue)
            components.append(textField.textColor.map { String(describing: $0) } ?? "")
        } else if let slider = view as? NSSlider {
            components.append(runtimeNumberSignature(slider.doubleValue))
            components.append(runtimeNumberSignature(slider.minValue))
            components.append(runtimeNumberSignature(slider.maxValue))
            components.append(slider.isEnabled ? "enabled" : "disabled")
        } else if let imageView = view as? NSImageView {
            appendRuntimeImageSignature(imageView.image, to: &components)
        } else if let progress = view as? NSProgressIndicator {
            components.append(runtimeNumberSignature(progress.doubleValue))
            components.append(runtimeNumberSignature(progress.minValue))
            components.append(runtimeNumberSignature(progress.maxValue))
            components.append(progress.isIndeterminate ? "indeterminate" : "determinate")
        }

        if let layer = view.layer {
            components.append(layer.isHidden ? "layer-hidden" : "layer-shown")
            components.append(runtimeNumberSignature(layer.opacity))
            components.append(layer.backgroundColor.map { String(describing: $0) } ?? "")
            components.append(layer.contents.map { String(describing: $0) } ?? "")
        }

        for subview in view.subviews.prefix(64) {
            appendRuntimeViewSignature(subview, depth: depth + 1, remainingViews: &remainingViews, to: &components)
        }
    }

    private func appendRuntimeImageSignature(_ image: NSImage?, to components: inout [String]) {
        guard let image else {
            components.append("no-image")
            return
        }
        components.append(String(describing: ObjectIdentifier(image)))
        components.append(runtimeNumberSignature(image.size.width))
        components.append(runtimeNumberSignature(image.size.height))
        components.append(image.isTemplate ? "template" : "original")
    }

    private func runtimeRectSignature(_ rect: NSRect) -> String {
        [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height]
            .map(runtimeNumberSignature)
            .joined(separator: ",")
    }

    private func runtimeNumberSignature<T: BinaryFloatingPoint>(_ value: T) -> String {
        String(format: "%.3f", Double(value))
    }

    private func runtimeRenderedImage(id: String, view: NSView?, signature: String) -> (image: String?, changed: Bool) {
        if let cached = runtimeRenderCache[id], cached.signature == signature {
            return (cached.renderedImage, false)
        }

        let previousImage = runtimeRenderCache[id]?.renderedImage
        var renderedImage = view.flatMap(runtimePNGDataURL)
        if let candidate = renderedImage {
            let currentCharacterCount = runtimeRenderCache.reduce(into: 0) { total, entry in
                guard entry.key != id else { return }
                total += entry.value.renderedImage?.utf8.count ?? 0
            }
            if currentCharacterCount + candidate.utf8.count > Self.runtimeRenderMaximumCacheCharacters {
                renderedImage = nil
            }
        }
        runtimeRenderCache[id] = RuntimeRenderCacheEntry(signature: signature, renderedImage: renderedImage)
        return (renderedImage, previousImage != renderedImage)
    }

    private func runtimePNGDataURL(for view: NSView) -> String? {
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else {
            return nil
        }

        let widthScale = Self.runtimeRenderMaximumPixelSize.width / bounds.width
        let heightScale = Self.runtimeRenderMaximumPixelSize.height / bounds.height
        let scale = min(2, widthScale, heightScale)
        guard scale.isFinite, scale > 0 else { return nil }
        let pixelsWide = max(1, Int(ceil(bounds.width * scale)))
        let pixelsHigh = max(1, Int(ceil(bounds.height * scale)))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        bitmap.size = bounds.size
        view.cacheDisplay(in: bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]),
              png.count <= Self.runtimeRenderMaximumPNGBytes
        else {
            return nil
        }
        return "data:image/png;base64,\(png.base64EncodedString())"
    }

    @objc func setupControlStripPresence() {
        DFRSystemModalShowsCloseBoxWhenFrontMost(false)
        let item = NSCustomTouchBarItem(identifier: .controlStripItem)
        item.view = NSButton(image: #imageLiteral(resourceName: "StatusImage"), target: self, action: #selector(presentTouchBar))
        NSTouchBarItem.addSystemTrayItem(item)
        updateControlStripPresence()
    }

    func updateControlStripPresence() {
        let showMtmrButtonOnControlStrip = touchBarContainsAnyItems()
        DFRElementSetControlStripPresenceForIdentifier(.controlStripItem, showMtmrButtonOnControlStrip)
    }

    @objc private func presentTouchBar() {
        if AppSettings.showControlStripState {
            presentSystemModal(touchBar, systemTrayItemIdentifier: .controlStripItem)
        } else {
            presentSystemModal(touchBar, placement: 1, systemTrayItemIdentifier: .controlStripItem)
        }
        updateControlStripPresence()
    }

    @objc private func dismissTouchBar() {
        if touchBarContainsAnyItems() {
            minimizeSystemModal(touchBar)
        }
        updateControlStripPresence()
    }

    @objc func resetControlStrip() {
        dismissTouchBar()
        updateActiveApp()
    }

    func touchBar(_: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        if identifier == basicViewIdentifier {
            return basicView
        }

        return nil
    }

    func createItem(forIdentifier identifier: NSTouchBarItem.Identifier, definition item: BarItemDefinition) -> NSTouchBarItem? {
        var barItem: NSTouchBarItem!
        switch item.type {
        case let .staticButton(title: title):
            barItem = CustomButtonTouchBarItem(identifier: identifier, title: title)
        case let .appleScriptTitledButton(source: source, refreshInterval: interval, alternativeImages: alternativeImages):
            barItem = AppleScriptTouchBarItem(identifier: identifier, source: source, interval: interval, alternativeImages: alternativeImages)
        case let .shellScriptTitledButton(source: source, refreshInterval: interval):
            barItem = ShellScriptTouchBarItem(identifier: identifier, source: source, interval: interval)
        case let .timeButton(formatTemplate: template, timeZone: timeZone, locale: locale):
            barItem = TimeTouchBarItem(identifier: identifier, formatTemplate: template, timeZone: timeZone, locale: locale)
        case .battery:
            barItem = BatteryBarItem(identifier: identifier)
        case let .cpu(refreshInterval: refreshInterval):
            barItem = SystemUsageBarItem(
                identifier: identifier,
                metric: .cpu,
                refreshInterval: refreshInterval
            )
        case let .memory(refreshInterval: refreshInterval):
            barItem = SystemUsageBarItem(
                identifier: identifier,
                metric: .memory,
                refreshInterval: refreshInterval
            )
        case let .dock(autoResize: autoResize, filter: regexString):
            if let regexString = regexString {
                guard let regex = try? NSRegularExpression(pattern: regexString, options: []) else {
                    barItem = CustomButtonTouchBarItem(identifier: identifier, title: "Bad regex")
                    break
                }
                barItem = AppScrubberTouchBarItem(identifier: identifier, autoResize: autoResize, filter: regex)
            } else {
                barItem = AppScrubberTouchBarItem(identifier: identifier, autoResize: autoResize)
            }
        case let .pinnedDock(autoResize, applications, showRunningIndicator, longPressAction, spacing):
            barItem = PinnedAppDockTouchBarItem(
                identifier: identifier,
                autoResize: autoResize,
                applications: applications,
                showRunningIndicator: showRunningIndicator,
                longPressAction: longPressAction,
                spacing: spacing
            )
        case .volume:
            if case let .image(source)? = item.additionalParameters[.image] {
                barItem = VolumeViewController(identifier: identifier, image: source.image)
            } else {
                barItem = VolumeViewController(identifier: identifier)
            }
        case let .brightness(refreshInterval: interval):
            if case let .image(source)? = item.additionalParameters[.image] {
                barItem = BrightnessViewController(identifier: identifier, refreshInterval: interval, image: source.image)
            } else {
                barItem = BrightnessViewController(identifier: identifier, refreshInterval: interval)
            }
        case let .weather(interval: interval, units: units, api_key: api_key, icon_type: icon_type):
            barItem = WeatherBarItem(identifier: identifier, interval: interval, units: units, api_key: api_key, icon_type: icon_type)
        case let .yandexWeather(interval: interval):
            barItem = YandexWeatherBarItem(identifier: identifier, interval: interval)
        case let .currency(interval: interval, from: from, to: to, full: full):
            barItem = CurrencyBarItem(identifier: identifier, interval: interval, from: from, to: to, full: full)
        case .inputsource:
            barItem = InputSourceBarItem(identifier: identifier)
        case let .music(interval: interval, disableMarquee: disableMarquee):
            barItem = MusicBarItem(identifier: identifier, interval: interval, disableMarquee: disableMarquee)
        case let .group(items: items):
            barItem = GroupBarItem(identifier: identifier, items: items)
        case .nightShift:
            barItem = NightShiftBarItem(identifier: identifier)
        case .dnd:
            barItem = DnDBarItem(identifier: identifier)
        case let .pomodoro(workTime: workTime, restTime: restTime):
            barItem = PomodoroBarItem(identifier: identifier, workTime: workTime, restTime: restTime)
        case let .network(flip: flip, units: units):
            barItem = NetworkBarItem(identifier: identifier, flip: flip, units: units)
        case .darkMode:
            barItem = DarkModeBarItem(identifier: identifier)
        case let .swipe(direction: direction, fingers: fingers, minOffset: minOffset, sourceApple: sourceApple, sourceBash: sourceBash):
            barItem = SwipeItem(identifier: identifier, direction: direction, fingers: fingers, minOffset: minOffset, sourceApple: sourceApple, sourceBash: sourceBash)
        case let .upnext(interval: interval, from: from, to: to, maxToShow: maxToShow, autoResize: autoResize):
            barItem = UpNextScrubberTouchBarItem(identifier: identifier, interval: interval, from: from, to: to, maxToShow: maxToShow, autoResize: autoResize)
        }

        if let action = self.action(forItem: item), let item = barItem as? CustomButtonTouchBarItem {
            item.actions.append(ItemAction(trigger: .singleTap, action))
        }
        if let longAction = self.longAction(forItem: item), let item = barItem as? CustomButtonTouchBarItem {
            item.actions.append(ItemAction(trigger: .longTap, longAction))
        }
        
        if let touchBarItem = barItem as? CustomButtonTouchBarItem {
            for action in item.actions {
                touchBarItem.actions.append(ItemAction(trigger: action.trigger, self.closure(for: action)))
            }
        }
        if case let .bordered(bordered)? = item.additionalParameters[.bordered], let item = barItem as? CustomButtonTouchBarItem {
            item.isBordered = bordered
        }
        if case let .background(color)? = item.additionalParameters[.background], let item = barItem as? CustomButtonTouchBarItem {
            item.backgroundColor = color
        }
        if case let .width(value)? = item.additionalParameters[.width], let widthBarItem = barItem as? CanSetWidth {
            widthBarItem.setWidth(value: value)
        }
        if case let .image(source)? = item.additionalParameters[.image], let item = barItem as? CustomButtonTouchBarItem {
            item.image = source.image
        }
        if case let .title(value)? = item.additionalParameters[.title] {
            if let item = barItem as? GroupBarItem {
                item.collapsedRepresentationLabel = value
            } else if let item = barItem as? CustomButtonTouchBarItem {
                item.title = value
            }
        }
        return barItem
    }
    
    func closure(for action: Action) -> (() -> Void)? {
        switch action.value {
        case let .hidKey(keycode: keycode):
            return { HIDPostAuxKey(keycode) }
        case let .keyPress(keycode: keycode):
            return { GenericKeyPress(keyCode: CGKeyCode(keycode)).send() }
        case let .typeText(text: text):
            return { UnicodeTextInput(text: text).send() }
        case let .appleScript(source: source):
            guard let appleScript = source.appleScript else {
                print("cannot create apple script for item \(action)")
                return {}
            }
            return {
                DispatchQueue.appleScriptQueue.async {
                    var error: NSDictionary?
                    appleScript.executeAndReturnError(&error)
                    if let error = error {
                        print("error \(error) when handling \(action) ")
                    }
                }
            }
        case let .shellScript(executable: executable, parameters: parameters):
            return {
                let task = Process()
                task.launchPath = executable
                task.arguments = parameters
                task.launch()
            }
        case let .openUrl(url: url):
            return {
                if let url = URL(string: url), NSWorkspace.shared.open(url) {
                    #if DEBUG
                        print("URL was successfully opened")
                    #endif
                } else {
                    print("error", url)
                }
            }
        case let .custom(closure: closure):
            return closure
        case .none:
            return nil
        }
    }

    func action(forItem item: BarItemDefinition) -> (() -> Void)? {
        switch item.legacyAction {
        case let .hidKey(keycode: keycode):
            return { HIDPostAuxKey(keycode) }
        case let .keyPress(keycode: keycode):
            return { GenericKeyPress(keyCode: CGKeyCode(keycode)).send() }
        case let .appleScript(source: source):
            guard let appleScript = source.appleScript else {
                print("cannot create apple script for item \(item)")
                return {}
            }
            return {
                DispatchQueue.appleScriptQueue.async {
                    var error: NSDictionary?
                    appleScript.executeAndReturnError(&error)
                    if let error = error {
                        print("error \(error) when handling \(item) ")
                    }
                }
            }
        case let .shellScript(executable: executable, parameters: parameters):
            return {
                let task = Process()
                task.launchPath = executable
                task.arguments = parameters
                task.launch()
            }
        case let .openUrl(url: url):
            return {
                if let url = URL(string: url), NSWorkspace.shared.open(url) {
                    #if DEBUG
                        print("URL was successfully opened")
                    #endif
                } else {
                    print("error", url)
                }
            }
        case let .custom(closure: closure):
            return closure
        case .none:
            return nil
        }
    }

    func longAction(forItem item: BarItemDefinition) -> (() -> Void)? {
        switch item.legacyLongAction {
        case let .hidKey(keycode: keycode):
            return { HIDPostAuxKey(keycode) }
        case let .keyPress(keycode: keycode):
            return { GenericKeyPress(keyCode: CGKeyCode(keycode)).send() }
        case let .appleScript(source: source):
            guard let appleScript = source.appleScript else {
                print("cannot create apple script for item \(item)")
                return {}
            }
            return {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
                if let error = error {
                    print("error \(error) when handling \(item) ")
                }
            }
        case let .shellScript(executable: executable, parameters: parameters):
            return {
                let task = Process()
                task.launchPath = executable
                task.arguments = parameters
                task.launch()
            }
        case let .openUrl(url: url):
            return {
                if let url = URL(string: url), NSWorkspace.shared.open(url) {
                    #if DEBUG
                        print("URL was successfully opened")
                    #endif
                } else {
                    print("error", url)
                }
            }
        case let .custom(closure: closure):
            return closure
        case .none:
            return nil
        }
    }
}

@MainActor
protocol CanSetWidth {
    func setWidth(value: CGFloat)
}

extension NSCustomTouchBarItem: CanSetWidth {
    func setWidth(value: CGFloat) {
        view.widthAnchor.constraint(equalToConstant: value).isActive = true
    }
}

extension NSPopoverTouchBarItem: CanSetWidth {
    func setWidth(value: CGFloat) {
        view?.widthAnchor.constraint(equalToConstant: value).isActive = true
    }
}

extension BarItemDefinition {
    var align: Align {
        if case let .align(result)? = additionalParameters[.align] {
            return result
        }
        return .center
    }
}
