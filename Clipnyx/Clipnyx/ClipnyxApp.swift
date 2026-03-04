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

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if ENABLE_AUTOPASTE
        // アクセシビリティ権限の確認（未許可ならシステムダイアログを表示）
        AXIsProcessTrustedWithOptions(
            ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        )
        #endif

        // Register hotkey
        HotKeyManager.shared.onHotKey = { [weak self] in
            guard let self else { return }
            self.popupController.toggle(clipboardManager: self.clipboardManager)
        }
        HotKeyManager.shared.register()

        // 設定ウィンドウ表示リクエスト
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showSettings),
            name: .openSettingsRequest,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.unregister()
        clipboardManager.stopPolling()
    }

    @objc func showSettings() {
        if let settingsWindow {
            settingsWindow.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            settingsWindow.makeKey()
            return
        }

        let tabVC = NSTabViewController()
        tabVC.tabStyle = .toolbar
        tabVC.title = String(localized: "Settings")

        let generalItem = NSTabViewItem(viewController: NSHostingController(
            rootView: GeneralTab().formStyle(.grouped)
        ))
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

        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKey()
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
}
