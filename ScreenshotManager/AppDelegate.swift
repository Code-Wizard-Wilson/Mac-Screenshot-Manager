import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = ScreenshotStore()

    private var windowController: NSWindowController?
    private var settingsWindowController: NSWindowController?
    private var statusItem: NSStatusItem?
    private var statusPopover: NSPopover?
    private var menuBarVisibilityObserver: NSObjectProtocol?
    private let clipboardHotkeyID: UInt32 = 1
    private let saveHotkeyID: UInt32 = 2

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        showWindow()
        registerGlobalHotkeys()
        configureMenuBarVisibility()

        menuBarVisibilityObserver = NotificationCenter.default.addObserver(
            forName: .screenshotManagerMenuBarVisibilityDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let visible = (notification.object as? Bool)
                ?? UserDefaults.standard.object(forKey: AppPreferenceKeys.showsMenuBarItem) as? Bool
                ?? true
            Task { @MainActor [weak self] in
                self?.setMenuBarItemVisible(visible)
            }
        }

        store.hotkeysDidChange = { [weak self] in
            self?.registerGlobalHotkeys()
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            store.requestRequiredPermissions()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalHotkeyManager.shared.unregister()
        if let menuBarVisibilityObserver {
            NotificationCenter.default.removeObserver(menuBarVisibilityObserver)
        }
        statusPopover?.close()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }

    func applicationShouldSaveApplicationState(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldRestoreApplicationState(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        store.refreshRequiredPermissions()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.identifier == NSUserInterfaceItemIdentifier("ScreenshotManager.MainWindow") else {
            return
        }

        NSApp.terminate(nil)
    }

    func openManagerWindow() {
        showWindow()
    }

    func openSettingsWindow() {
        let window = currentSettingsWindow()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureMenuBarVisibility() {
        if UserDefaults.standard.object(forKey: AppPreferenceKeys.showsMenuBarItem) == nil {
            UserDefaults.standard.set(true, forKey: AppPreferenceKeys.showsMenuBarItem)
        }
        let visible = UserDefaults.standard.bool(forKey: AppPreferenceKeys.showsMenuBarItem)
        setMenuBarItemVisible(visible)
    }

    func setMenuBarItemVisible(_ visible: Bool) {
        UserDefaults.standard.set(visible, forKey: AppPreferenceKeys.showsMenuBarItem)

        if visible {
            guard statusItem == nil else { return }

            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            if let button = item.button {
                let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
                button.image = NSImage(
                    systemSymbolName: "camera.viewfinder",
                    accessibilityDescription: "Screenshot Manager"
                )?.withSymbolConfiguration(config)
                button.imagePosition = .imageOnly
                button.toolTip = "Screenshot Manager"
                button.target = self
                button.action = #selector(toggleStatusPopover(_:))
                button.sendAction(on: [.leftMouseUp])
            }
            statusItem = item
            return
        }

        statusPopover?.performClose(nil)
        statusPopover = nil
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    @objc private func toggleStatusPopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }

        if let popover = statusPopover, popover.isShown {
            popover.performClose(sender)
            return
        }

        let popover = statusPopover ?? makeStatusPopover()
        statusPopover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeStatusPopover() -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 292, height: 322)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPanelView(
                store: store,
                openManager: { [weak self] in
                    self?.statusPopover?.performClose(nil)
                    self?.openManagerWindow()
                },
                openSettings: { [weak self] in
                    self?.statusPopover?.performClose(nil)
                    self?.openSettingsWindow()
                },
                quit: {
                    NSApp.terminate(nil)
                }
            )
        )
        return popover
    }

    private func registerGlobalHotkeys() {
        let didRegisterClipboard = GlobalHotkeyManager.shared.register(id: clipboardHotkeyID, hotkey: store.clipboardHotkey) { [weak self] in
            self?.store.captureToClipboard()
        }

        let didRegisterSave = GlobalHotkeyManager.shared.register(id: saveHotkeyID, hotkey: store.saveHotkey) { [weak self] in
            self?.store.captureAndSaveToLibrary()
        }

        if !didRegisterClipboard {
            store.showHotkeyRegistrationFailed(store.clipboardHotkey, name: "copy")
        }

        if !didRegisterSave {
            store.showHotkeyRegistrationFailed(store.saveHotkey, name: "library")
        }
    }

    private func makeWindow() -> NSWindow {
        let contentView = ContentView(store: store) { [weak self] in
            self?.openSettingsWindow()
        }
        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Screenshot Manager"
        window.titleVisibility = .hidden
        window.identifier = NSUserInterfaceItemIdentifier("ScreenshotManager.MainWindow")
        window.titlebarAppearsTransparent = false
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true
        window.hasShadow = true
        window.toolbarStyle = .unifiedCompact
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.minSize = NSSize(width: 920, height: 580)
        window.contentViewController = hostingController
        window.delegate = self
        window.center()

        let controller = NSWindowController(window: window)
        windowController = controller

        return window
    }

    private func makeSettingsWindow() -> NSWindow {
        let contentView = SettingsView(store: store)
        let hostingController = NSHostingController(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Screenshot Manager Settings"
        window.titleVisibility = .hidden
        window.identifier = NSUserInterfaceItemIdentifier("ScreenshotManager.SettingsWindow")
        window.titlebarAppearsTransparent = false
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true
        window.hasShadow = true
        window.toolbarStyle = .unifiedCompact
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.minSize = NSSize(width: 700, height: 440)
        window.contentViewController = hostingController
        window.center()

        let controller = NSWindowController(window: window)
        settingsWindowController = controller

        return window
    }

    private func currentWindow() -> NSWindow {
        windowController?.window ?? makeWindow()
    }

    private func currentSettingsWindow() -> NSWindow {
        settingsWindowController?.window ?? makeSettingsWindow()
    }

    private func showWindow() {
        let window = currentWindow()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func toggleWindow() {
        let window = currentWindow()

        if window.isVisible, NSApp.isActive {
            window.orderOut(nil)
        } else {
            showWindow()
        }
    }
}
