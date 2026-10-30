import AppKit
import Combine
import NotchCore
import SwiftUI

final class DeckPanel: NSPanel {
    var allowsKeyboard = true
    override var canBecomeKey: Bool { allowsKeyboard }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelCoordinator: NSObject {
    let model: DeckModel
    private let compact: DeckPanel
    private let expanded: DeckPanel
    private let shortcuts = ShortcutController()
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var subscriptions = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var globalClickMonitor: Any?
    private var localMonitor: Any?
    private var pointerTimer: Timer?
    private var hoverStarted: Date?
    private var outsideStarted: Date?
    private var sleeping = false
    private var previewWindow: NSWindow?

    init(model: DeckModel) {
        self.model = model
        compact = Self.makePanel(keyboard: false)
        expanded = Self.makePanel(keyboard: true)
        super.init()
        compact.hasShadow = false
        compact.contentView = NSHostingView(rootView: CompactView(model: model))
        expanded.contentView = NSHostingView(rootView: DeckView(model: model))
        model.onToggle = { [weak self] in self?.toggle() }
        model.onClose = { [weak self] in self?.close() }
        model.onSettings = { [weak self] in self?.showSettings() }
        model.onFocusClipboard = { [weak self] in self?.open(tab: .clipboard, keyboard: true) }
    }

    func start() {
        installLocalMonitor()
        if model.isPreview { showPreview(); return }
        createStatusItem()
        updateScreens()
        configureCollectionBehavior()
        updateShortcuts()
        model.media.start()
        model.clipboard.start()
        model.settings.$selectedDisplayID.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateScreens() }
        }.store(in: &subscriptions)
        model.settings.$showsInFullScreen.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.configureCollectionBehavior() }
        }.store(in: &subscriptions)
        model.settings.$shortcutsEnabled.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateShortcuts() }
        }.store(in: &subscriptions)
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateScreens() }
            })
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated { self?.workspaceChanged(note.name) }
            })
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.outsideClick() }
        }
        pointerTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackPointer() }
        }
        RunLoop.main.add(pointerTimer!, forMode: .common)
    }

    private func installLocalMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            let consumed = MainActor.assumeIsolated {
                if event.type == .keyDown, let window = event.window,
                   window === self.expanded || window === self.previewWindow {
                    if event.keyCode == 53 { self.close(); return true }
                    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    if flags.contains(.command), !flags.contains(.control), !flags.contains(.option) {
                        let character = event.charactersIgnoringModifiers?.lowercased() ?? ""
                        if character == "f" { self.open(tab: .clipboard, keyboard: true); return true }
                        if let number = Int(character), (1...DeckTab.allCases.count).contains(number) {
                            self.model.selectedTab = DeckTab.allCases[number - 1]
                            return true
                        }
                    }
                }
                if event.type != .keyDown, event.window !== self.expanded, event.window !== self.compact,
                   event.window !== self.previewWindow {
                    self.outsideClick()
                }
                return false
            }
            return consumed ? nil : event
        }
    }

    func stop() {
        pointerTimer?.invalidate()
        model.media.stop()
        model.clipboard.stop()
        shortcuts.unregister()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        compact.orderOut(nil)
        expanded.orderOut(nil)
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }

    func toggle() {
        if model.expanded { close() } else { open(keyboard: true) }
    }

    func open(tab: DeckTab? = nil, keyboard: Bool = false) {
        guard !sleeping else { return }
        if let tab { model.selectedTab = tab }
        let wasExpanded = model.expanded
        model.expanded = true
        outsideStarted = nil
        if model.isPreview {
            previewWindow?.makeKeyAndOrderFront(nil)
            if model.selectedTab == .clipboard { model.clipboardFocusRequest = UUID() }
            return
        }
        guard let geometry = model.geometry else { return }
        expanded.setFrame(geometry.expandedFrame, display: true)
        if keyboard {
            expanded.makeKeyAndOrderFront(nil)
            if model.selectedTab == .clipboard { model.clipboardFocusRequest = UUID() }
        } else { expanded.orderFrontRegardless() }
        if !wasExpanded, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            expanded.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                expanded.animator().alphaValue = 1
            }
        } else { expanded.alphaValue = 1 }
        model.media.refresh()
    }

    func close() {
        model.pinned = false
        model.expanded = false
        hoverStarted = nil
        outsideStarted = nil
        if model.isPreview { previewWindow?.orderOut(nil) }
        else { expanded.orderOut(nil) }
    }

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Настройки NotchDeck"
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        if !model.isPreview { close() }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private static func makePanel(keyboard: Bool) -> DeckPanel {
        let panel = DeckPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        panel.allowsKeyboard = keyboard
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        return panel
    }

    private func configureCollectionBehavior() {
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .stationary]
        if model.settings.showsInFullScreen {
            behavior.formUnion([.fullScreenAuxiliary, .canJoinAllApplications])
        } else { behavior.insert(.fullScreenNone) }
        compact.collectionBehavior = behavior
        expanded.collectionBehavior = behavior
    }

    private func updateScreens() {
        let screens = NSScreen.screens.map { screen -> DisplaySnapshot in
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            return DisplaySnapshot(id: id, frame: screen.frame, safeTop: screen.safeAreaInsets.top,
                                   auxiliaryLeft: screen.auxiliaryTopLeftArea, auxiliaryRight: screen.auxiliaryTopRightArea)
        }
        model.displays = zip(NSScreen.screens, screens).map { screen, snapshot in
            DisplayChoice(id: snapshot.id, name: screen.localizedName, hasCamera: DisplayGeometry.resolve(snapshot).hasCamera)
        }
        guard let screen = DisplayGeometry.select(from: screens, preferredID: model.settings.selectedDisplayID) else {
            model.geometry = nil
            compact.orderOut(nil)
            expanded.orderOut(nil)
            return
        }
        let geometry = DisplayGeometry.resolve(screen)
        model.geometry = geometry
        compact.setFrame(geometry.compactFrame, display: true)
        expanded.setFrame(geometry.expandedFrame, display: true)
        if !sleeping { compact.orderFrontRegardless() }
        if model.expanded { expanded.orderFrontRegardless() }
    }

    private func trackPointer() {
        guard !sleeping, compact.isOnActiveSpace else { return }
        let pointer = NSEvent.mouseLocation
        let inCompact = compact.frame.insetBy(dx: -4, dy: -4).contains(pointer)
        let inExpanded = model.expanded && expanded.frame.contains(pointer)
        if inCompact {
            outsideStarted = nil
            if hoverStarted == nil { hoverStarted = Date() }
            if !model.expanded, model.settings.opensOnHover,
               Date().timeIntervalSince(hoverStarted!) >= 0.22 { open() }
        } else { hoverStarted = nil }
        if model.expanded, !inCompact, !inExpanded, !model.pinned, !expanded.isKeyWindow,
           NSEvent.pressedMouseButtons == 0 {
            if outsideStarted == nil { outsideStarted = Date() }
            if Date().timeIntervalSince(outsideStarted!) >= 0.65 { close() }
        } else { outsideStarted = nil }
    }

    private func outsideClick() {
        guard !model.isPreview, model.expanded, !model.pinned else { return }
        let pointer = NSEvent.mouseLocation
        if !expanded.frame.contains(pointer), !compact.frame.contains(pointer) { close() }
    }

    private func workspaceChanged(_ name: Notification.Name) {
        switch name {
        case NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification:
            sleeping = true
            close()
            compact.orderOut(nil)
            model.media.stop()
            model.clipboard.stop()
        case NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification:
            sleeping = false
            model.focusTimer.tick()
            model.media.start()
            model.clipboard.start()
            updateScreens()
        default:
            close()
        }
    }

    private func updateShortcuts() {
        shortcuts.onToggle = { [weak self] in MainActor.assumeIsolated { self?.toggle() } }
        shortcuts.onClipboard = { [weak self] in MainActor.assumeIsolated { self?.open(tab: .clipboard, keyboard: true) } }
        if model.settings.shortcutsEnabled {
            if !shortcuts.register() { model.notice = "Сочетание клавиш занято. Панель доступна через значок в строке меню." }
        } else { shortcuts.unregister() }
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "NotchDeck")
        item.button?.toolTip = "NotchDeck · ⌃⌥Пробел"
        let menu = NSMenu()
        for (title, selector) in [("Открыть панель", #selector(menuToggle)),
                                   ("Буфер обмена", #selector(menuClipboard)),
                                   ("Настройки…", #selector(menuSettings))] {
            let entry = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            entry.target = self
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Завершить NotchDeck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    @objc private func menuToggle() { toggle() }
    @objc private func menuClipboard() { open(tab: .clipboard, keyboard: true) }
    @objc private func menuSettings() { showSettings() }

    private func showPreview() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 402),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "NotchDeck · Предпросмотр"
        window.backgroundColor = .black
        window.contentView = NSHostingView(rootView: DeckView(model: model))
        window.isReleasedWhenClosed = false
        model.expanded = true
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--tab"),
           ProcessInfo.processInfo.arguments.indices.contains(index + 1),
           let tab = DeckTab(rawValue: ProcessInfo.processInfo.arguments[index + 1]) {
            model.selectedTab = tab
        }
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        previewWindow = window
    }
}
