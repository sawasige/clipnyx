import SwiftUI

@main
struct ClipnyxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Clipnyx", image: "MenuBarIcon") {
            MenuBarView()
                .environment(appDelegate.clipboardManager)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let clipboardManager = ClipboardManager()
    private var popupController = PopupPanelController()
    private var settingsWindow: NSWindow?
    #if ENABLE_SPARKLE
    let updateManager = UpdateManager()
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        CGRequestPostEventAccess()

        HotKeyManager.shared.onHotKey = { [weak self] in
            guard let self else { return }
            self.popupController.toggle(clipboardManager: self.clipboardManager)
        }
        HotKeyManager.shared.register()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowSettings),
            name: .openSettingsRequest,
            object: nil
        )
    }

    @objc private func handleShowSettings() {
        showSettings()
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.unregister()
        clipboardManager.stopPolling()
    }

    // Dock アイコンクリックで設定を開く
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func showSettings() {
        // MenuBarExtra パネルが開いていたら先に閉じる
        for window in NSApp.windows where window is NSPanel && window.isVisible {
            window.orderOut(nil)
        }

        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let tabVC = NSTabViewController()
        tabVC.tabStyle = .toolbar
        tabVC.title = String(localized: "Settings")

        #if ENABLE_SPARKLE
        let generalItem = NSTabViewItem(viewController: NSHostingController(
            rootView: GeneralTab(updateManager: updateManager).formStyle(.grouped)
        ))
        #else
        let generalItem = NSTabViewItem(viewController: NSHostingController(
            rootView: GeneralTab().formStyle(.grouped)
        ))
        #endif
        generalItem.label = String(localized: "General")
        generalItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
        tabVC.addTabViewItem(generalItem)

        let historyItem = NSTabViewItem(viewController: NSHostingController(
            rootView: HistoryTab(clipboardManager: clipboardManager).formStyle(.grouped)
        ))
        historyItem.label = String(localized: "History")
        historyItem.image = NSImage(systemSymbolName: "clock", accessibilityDescription: nil)
        tabVC.addTabViewItem(historyItem)

        let filterItem = NSTabViewItem(viewController: NSHostingController(
            rootView: FilterTab(clipboardManager: clipboardManager).formStyle(.grouped)
        ))
        filterItem.label = String(localized: "Filter")
        filterItem.image = NSImage(systemSymbolName: "line.3.horizontal.decrease.circle", accessibilityDescription: nil)
        tabVC.addTabViewItem(filterItem)

        let window = NSWindow(contentViewController: tabVC)
        window.styleMask = [.titled, .closable]
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.settingsWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === settingsWindow else { return }
        settingsWindow = nil
    }
}

extension Notification.Name {
    static let openSettingsRequest = Notification.Name("openSettingsRequest")
    static let closePopupPanel = Notification.Name("closePopupPanel")
}
