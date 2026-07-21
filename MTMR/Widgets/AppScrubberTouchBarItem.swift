//
//  AppScrubberTouchBarItem.swift
//  MTMR
//
//  Created by Daniel Apatin on 18.04.2018.
//  Copyright © 2018 Anton Palgunov. All rights reserved.

import Cocoa

class AppScrubberTouchBarItem: NSCustomTouchBarItem {
    private var scrollView = NSScrollView()
    private var autoResize: Bool = true
    private var widthConstraint: NSLayoutConstraint?
    private let filter: NSRegularExpression?

    private var persistentAppIdentifiers: [String] = []
    private var runningAppsIdentifiers: [String] = []

    private var frontmostApplicationIdentifier: String? {
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    private var applications: [DockItem] = []
    private var items: [DockBarItem] = []

    init(identifier: NSTouchBarItem.Identifier, autoResize: Bool = true, filter: NSRegularExpression? = nil) {
        self.filter = filter
        super.init(identifier: identifier)
        self.autoResize = autoResize
        view = scrollView

        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(hardReloadItems), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(hardReloadItems), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(softReloadItems), name: NSWorkspace.didActivateApplicationNotification, object: nil)

        persistentAppIdentifiers = AppSettings.dockPersistentAppIds
        hardReloadItems()
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func hardReloadItems() {
        applications = launchedApplications()
        applications += getDockPersistentAppsList()
        reloadData()
        softReloadItems()
        updateSize()
    }
    
    @objc func softReloadItems() {
        let frontMostAppId = self.frontmostApplicationIdentifier
        let runningAppsIds = NSWorkspace.shared.runningApplications.map { $0.bundleIdentifier }
        for barItem in items {
            let bundleId = barItem.dockItem.bundleIdentifier
            barItem.isRunning = runningAppsIds.contains(bundleId)
            barItem.isFrontmost = frontMostAppId == bundleId
        }
    }
    
    func updateSize() {
        let hasManualWidth = scrollView.constraints.contains { constraint in
            constraint.isActive
                && constraint !== widthConstraint
                && constraint.priority == .required
                && constraint.relation == .equal
                && constraint.secondItem == nil
                && constraint.firstItem === scrollView
                && constraint.firstAttribute == .width
        }
        // With no explicit `width`, the Dock must always track the number of
        // applications. `autoResize: false` only remains meaningful together
        // with a manual width; otherwise it used to collapse into an arbitrary
        // zone and show only a few icons.
        if self.autoResize || !hasManualWidth {
            self.widthConstraint?.isActive = false
            
            let width = self.scrollView.documentView?.fittingSize.width ?? 0
            self.widthConstraint = self.scrollView.widthAnchor.constraint(equalToConstant: width)
            // Preserve the Dock's natural width while still allowing the zone
            // container to clip an unusually large list of applications.
            self.widthConstraint!.priority = .defaultHigh
            self.widthConstraint!.isActive = true
        }
        NotificationCenter.default.post(name: .mmtmrTouchBarContentSizeDidChange, object: self)
    }
    
    func reloadData() {
        items = applications.map { self.createAppButton(for: $0) }
        let stackView = NSStackView(views: items.compactMap { $0.view })
        stackView.spacing = 1
        stackView.orientation = .horizontal
        let visibleRect = self.scrollView.documentVisibleRect
        scrollView.documentView = stackView
        stackView.scroll(visibleRect.origin)
    }

    public func createAppButton(for app: DockItem) -> DockBarItem {
        let item = DockBarItem(app)
        item.isBordered = false
        item.actions.append(contentsOf: [
            ItemAction(trigger: .singleTap) { [weak self] in
                self?.switchToApp(app: app)
            },
            ItemAction(trigger: .longTap) { [weak self] in
                self?.handleHalfLongPress(item: app)
            }
        ])
        item.killAppClosure = {[weak self] in
            self?.handleLongPress(item: app)
        }
        
        return item
    }
    
    public func switchToApp(app: DockItem) {
        let bundleIdentifier = app.bundleIdentifier
        if bundleIdentifier!.contains("file://") {
            NSWorkspace.shared.openFile(bundleIdentifier!.replacingOccurrences(of: "file://", with: ""))
        } else {
            NSWorkspace.shared.launchApplication(withBundleIdentifier: bundleIdentifier!, options: [.default], additionalEventParamDescriptor: nil, launchIdentifier: nil)
        }
        softReloadItems()

        // NB: if you can't open app which on another space, try to check mark
        // "When switching to an application, switch to a Space with open windows for the application"
        // in Mission control settings
    }
    
    //todo
    private func handleLongPress(item: DockItem) {
        if let pid = item.pid, let app = NSRunningApplication(processIdentifier: pid) {
            if !app.terminate() {
                app.forceTerminate()
            }
            hardReloadItems()
        }
    }
    
    private func handleHalfLongPress(item: DockItem) {
        if let index = self.persistentAppIdentifiers.firstIndex(of: item.bundleIdentifier) {
            persistentAppIdentifiers.remove(at: index)
            hardReloadItems()
        } else {
            persistentAppIdentifiers.append(item.bundleIdentifier)
        }

        AppSettings.dockPersistentAppIds = persistentAppIdentifiers
    }
    
    private func launchedApplications() -> [DockItem] {
        runningAppsIdentifiers = []
        var returnable: [DockItem] = []
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == NSApplication.ActivationPolicy.regular else { continue }
            guard let bundleIdentifier = app.bundleIdentifier else { continue }
            if let filter = self.filter,
                let name = app.localizedName,
                filter.numberOfMatches(in: name, options: [], range: NSRange(location: 0, length: name.count)) == 0 {
                continue
            }
            
            runningAppsIdentifiers.append(bundleIdentifier)

            let dockItem = DockItem(bundleIdentifier: bundleIdentifier, icon: app.icon ?? getIcon(forBundleIdentifier: bundleIdentifier), pid: app.processIdentifier)
            returnable.append(dockItem)
        }
        return returnable
    }

    public func getIcon(forBundleIdentifier bundleIdentifier: String? = nil, orPath path: String? = nil) -> NSImage {
        if let bundleIdentifier = bundleIdentifier, let appPath = NSWorkspace.shared.absolutePathForApplication(withBundleIdentifier: bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: appPath)
        }

        if let path = path {
            return NSWorkspace.shared.icon(forFile: path)
        }

        let genericIcon = NSImage(contentsOfFile: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericDocumentIcon.icns")
        return genericIcon ?? NSImage(size: .zero)
    }

    public func getDockPersistentAppsList() -> [DockItem] {
        var returnable: [DockItem] = []

        for bundleIdentifier in persistentAppIdentifiers {
            if !runningAppsIdentifiers.contains(bundleIdentifier) {
                let dockItem = DockItem(bundleIdentifier: bundleIdentifier, icon: getIcon(forBundleIdentifier: bundleIdentifier))
                returnable.append(dockItem)
            }
        }

        return returnable
    }
}

/// A deterministic Dock whose content and order come exclusively from the
/// canonical JSON configuration. Unlike `AppScrubberTouchBarItem`, entries do
/// not disappear when their applications terminate.
class PinnedAppDockTouchBarItem: NSCustomTouchBarItem {
    private let scrollView = NSScrollView()
    private let autoResize: Bool
    private let definitions: [PinnedApplicationDefinition]
    private let showRunningIndicator: Bool
    private let longPressAction: PinnedDockLongPressAction
    private let spacing: CGFloat
    private var widthConstraint: NSLayoutConstraint?
    private var items: [DockBarItem] = []

    init(
        identifier: NSTouchBarItem.Identifier,
        autoResize: Bool,
        applications: [PinnedApplicationDefinition],
        showRunningIndicator: Bool,
        longPressAction: PinnedDockLongPressAction,
        spacing: Double
    ) {
        self.autoResize = autoResize
        definitions = applications
        self.showRunningIndicator = showRunningIndicator
        self.longPressAction = longPressAction
        self.spacing = CGFloat(min(20, max(-12, spacing)))
        super.init(identifier: identifier)
        view = scrollView

        let notifications = NSWorkspace.shared.notificationCenter
        notifications.addObserver(
            self,
            selector: #selector(applicationListChanged),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        notifications.addObserver(
            self,
            selector: #selector(applicationListChanged),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
        notifications.addObserver(
            self,
            selector: #selector(updateApplicationState),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        reloadItems()
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func applicationListChanged() {
        // Re-resolve the icon as well: this turns a missing placeholder into
        // the real application icon as soon as macOS can launch it.
        reloadItems()
    }

    private func reloadItems() {
        items = definitions.map(createAppButton)
        let stackView = NSStackView(views: items.map(\.view))
        stackView.spacing = spacing
        stackView.orientation = .horizontal
        let visibleOrigin = scrollView.documentVisibleRect.origin
        scrollView.documentView = stackView
        stackView.scroll(visibleOrigin)
        updateApplicationState()
        updateSize()
    }

    private func createAppButton(for definition: PinnedApplicationDefinition) -> DockBarItem {
        let runningApplication = runningApplication(for: definition.bundleIdentifier)
        let applicationURL = resolvedApplicationURL(for: definition)
        let icon: NSImage
        if let runningIcon = runningApplication?.icon {
            icon = runningIcon
        } else if let applicationURL {
            icon = NSWorkspace.shared.icon(forFile: applicationURL.path)
        } else {
            icon = Self.missingApplicationIcon()
        }

        let dockItem = DockItem(
            bundleIdentifier: definition.bundleIdentifier,
            icon: icon,
            pid: runningApplication?.processIdentifier
        )
        let item = DockBarItem(dockItem)
        item.isBordered = false
        item.showsRunningIndicator = showRunningIndicator
        item.allowsKillGesture = longPressAction == .quit
        item.view.toolTip = definition.label ?? runningApplication?.localizedName ?? definition.bundleIdentifier
        item.actions.append(ItemAction(trigger: .singleTap) { [weak self] in
            self?.openOrActivate(definition)
        })
        item.killAppClosure = { [weak self] in
            self?.quitApplication(definition.bundleIdentifier)
        }
        return item
    }

    @objc private func updateApplicationState() {
        let running = NSWorkspace.shared.runningApplications.reduce(
            into: [String: NSRunningApplication]()
        ) { result, application in
            guard let identifier = application.bundleIdentifier else { return }
            result[identifier] = result[identifier] ?? application
        }
        let frontmostIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        for item in items {
            let identifier = item.dockItem.bundleIdentifier ?? ""
            let application = running[identifier]
            item.dockItem.pid = application?.processIdentifier
            item.isRunning = application != nil
            item.isFrontmost = identifier == frontmostIdentifier
        }
    }

    private func updateSize() {
        let hasManualWidth = scrollView.constraints.contains { constraint in
            constraint.isActive
                && constraint !== widthConstraint
                && constraint.priority == .required
                && constraint.relation == .equal
                && constraint.secondItem == nil
                && constraint.firstItem === scrollView
                && constraint.firstAttribute == .width
        }
        if autoResize || !hasManualWidth {
            widthConstraint?.isActive = false
            let width = scrollView.documentView?.fittingSize.width ?? 0
            widthConstraint = scrollView.widthAnchor.constraint(equalToConstant: width)
            widthConstraint?.priority = .defaultHigh
            widthConstraint?.isActive = true
        }
        NotificationCenter.default.post(name: .mmtmrTouchBarContentSizeDidChange, object: self)
    }

    private func openOrActivate(_ definition: PinnedApplicationDefinition) {
        if let application = runningApplication(for: definition.bundleIdentifier) {
            application.activate(options: [.activateIgnoringOtherApps])
            updateApplicationState()
            return
        }

        guard let applicationURL = resolvedApplicationURL(for: definition) else {
            NSSound.beep()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) { [weak self] _, _ in
            DispatchQueue.main.async { self?.applicationListChanged() }
        }
    }

    private func quitApplication(_ bundleIdentifier: String) {
        guard longPressAction == .quit,
              let application = runningApplication(for: bundleIdentifier)
        else { return }
        if !application.terminate() {
            application.forceTerminate()
        }
    }

    private func runningApplication(for bundleIdentifier: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleIdentifier }
    }

    private func resolvedApplicationURL(for definition: PinnedApplicationDefinition) -> URL? {
        if let path = definition.path, FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: definition.bundleIdentifier)
    }

    private static func missingApplicationIcon() -> NSImage {
        let path = "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns"
        return NSImage(contentsOfFile: path) ?? NSImage(size: NSSize(width: iconWidth, height: iconWidth))
    }
}

public class DockItem: NSObject {
    var bundleIdentifier: String!, icon: NSImage!, pid: Int32!

    convenience init(bundleIdentifier: String, icon: NSImage, pid: Int32? = nil) {
        self.init()
        self.bundleIdentifier = bundleIdentifier
        self.icon = icon
        self.pid = pid
    }
}

private let iconWidth = 32.0
class DockBarItem: CustomButtonTouchBarItem {
    let dotView = NSView(frame: .zero)
    let dockItem: DockItem
    fileprivate var killGestureRecognizer: LongPressGestureRecognizer!
    var killAppClosure: () -> Void = { }

    var showsRunningIndicator = true {
        didSet { redrawDotView() }
    }

    var allowsKillGesture = true {
        didSet { updateKillGestureState() }
    }
    
    var isRunning = false {
        didSet {
            redrawDotView()
            updateKillGestureState()
        }
    }
    
    var isFrontmost = false {
        didSet {
            redrawDotView()
        }
    }
    
    init(_ app: DockItem) {
        self.dockItem = app
        super.init(identifier: .init(app.bundleIdentifier), title: "")
        dotView.wantsLayer = true
        
        image = app.icon
        image?.size = NSSize(width: iconWidth, height: iconWidth)

        killGestureRecognizer = LongPressGestureRecognizer(target: self, action: #selector(firePanGestureRecognizer))
        killGestureRecognizer.allowedTouchTypes = .direct
        killGestureRecognizer.recognizeTimeout = 1.5
        killGestureRecognizer.minimumPressDuration = 1.5
        killGestureRecognizer.isEnabled = isRunning
        
        self.finishViewConfiguration = { [weak self] in
            guard let selfie = self else { return }
            selfie.dotView.layer?.cornerRadius = 1.5
            selfie.view.addSubview(selfie.dotView)
            selfie.redrawDotView()
            selfie.view.addGestureRecognizer(selfie.killGestureRecognizer)
        }
    }
    
    func redrawDotView() {
        let visible = showsRunningIndicator && isRunning
        dotView.layer?.backgroundColor = visible ? NSColor.white.cgColor : NSColor.clear.cgColor
        dotView.frame.size = NSSize(width: visible && isFrontmost ? iconWidth - 14 : 3, height: 3)
        dotView.setFrameOrigin(NSPoint(x: 18.0 - Double(dotView.frame.size.width) / 2.0, y: iconWidth - 5))
    }

    private func updateKillGestureState() {
        killGestureRecognizer?.isEnabled = allowsKillGesture && isRunning
    }
    
    @objc func firePanGestureRecognizer() {
        self.killAppClosure()
    }
    
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
