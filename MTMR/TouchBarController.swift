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
    let sourcePath: String
    let fingerprint: String
    let definition: BarItemDefinition
}

struct RuntimeBarGeometry: Sendable {
    let id: String
    let align: String
    let width: Double
    let visible: Bool
}

extension ItemType {
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
        case .dock(autoResize: _, filter: _):
            return "com.tovam.MMTMR.dock"
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
    private var renderedFingerprints: [NSTouchBarItem.Identifier: String] = [:]
    private var renderedOrder: [NSTouchBarItem.Identifier] = []
    var items: [NSTouchBarItem.Identifier: NSTouchBarItem] = [:]
    var leftIdentifiers: [NSTouchBarItem.Identifier] = []
    var centerIdentifiers: [NSTouchBarItem.Identifier] = []
    var rightIdentifiers: [NSTouchBarItem.Identifier] = []
    let basicViewIdentifier = NSTouchBarItem.Identifier("com.tovam.MMTMR.scrollView")
    private let centerScrollAreaIdentifier = NSTouchBarItem.Identifier("com.tovam.MMTMR.scrollArea")
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

        let scrollArea = ScrollViewItem(identifier: centerScrollAreaIdentifier, items: centerItems)

        let leftItems = leftIdentifiers.compactMap({ (identifier) -> NSTouchBarItem? in
            items[identifier]
        })
        let rightItems = rightIdentifiers.compactMap({ (identifier) -> NSTouchBarItem? in
            items[identifier]
        })

        let visibleItems = leftItems + [scrollArea] + rightItems
        if let basicView {
            basicView.update(items: visibleItems, swipeItems: swipeItems)
        } else {
            basicView = BasicView(identifier: basicViewIdentifier, items: visibleItems, swipeItems: swipeItems)
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
        (leftIdentifiers + centerIdentifiers + rightIdentifiers).compactMap { identifier in
            guard let id = definitionIDs[identifier], let definition = itemDefinitions[identifier] else { return nil }
            let item = items[identifier]
            let width = item?.view?.fittingSize.width ?? item?.view?.frame.width ?? 0
            return RuntimeBarGeometry(
                id: id,
                align: definition.align.rawValue,
                width: Double(width),
                visible: item != nil
            )
        }
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
            barItem = CPUBarItem(identifier: identifier, refreshInterval: refreshInterval)
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
