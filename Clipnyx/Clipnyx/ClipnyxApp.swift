import SwiftUI

@main
struct ClipnyxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Clipnyx", image: "MenuBarIcon") {
            MenuBarView()
                .environment(appDelegate.clipboardManager)
        }
    }
}

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let clipboardManager = ClipboardManager()
    private var popupController = PopupPanelController()
    private var settingsWindow: NSWindow?
    private var favoriteManagerWindow: NSWindow?
    #if ENABLE_SPARKLE
    let updateManager = UpdateManager()
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenPopupPanel),
            name: .openPopupPanel,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenFavoriteManager(_:)),
            name: .openFavoriteManager,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.unregister()
        clipboardManager.stopPolling()
    }

    @objc private func handleOpenPopupPanel() {
        popupController.toggle(clipboardManager: clipboardManager)
    }

    @objc private func handleOpenFavoriteManager(_ notification: Notification) {
        let item = notification.object as? ClipboardItem
        showFavoriteManager(selectItem: item)
    }

    // MARK: - Library

    private func showFavoriteManager(selectItem: ClipboardItem?) {
        popupController.close(restoreFocus: false)

        if let favoriteManagerWindow {
            favoriteManagerWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            if let selectItem {
                NotificationCenter.default.post(name: .selectLibraryItem, object: selectItem)
            }
            return
        }

        let managerView = FavoriteManagerView(clipboardManager: clipboardManager, initialItemId: selectItem?.id)

        let window = NSWindow(
            contentViewController: NSHostingController(rootView: managerView)
        )
        window.styleMask = [.titled, .closable, .resizable]
        window.title = String(localized: "Collection")
        window.setContentSize(NSSize(width: 800, height: 500))
        window.isReleasedWhenClosed = false
        self.favoriteManagerWindow = window

        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Settings

    @objc private func handleShowSettings() {
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

        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        let window = notification.object as? NSWindow
        if window === settingsWindow {
            settingsWindow = nil
        } else if window === favoriteManagerWindow {
            favoriteManagerWindow = nil
        }
        if settingsWindow == nil && favoriteManagerWindow == nil {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

extension Notification.Name {
    static let openSettingsRequest = Notification.Name("openSettingsRequest")
    static let openPopupPanel = Notification.Name("openPopupPanel")
    static let closePopupPanel = Notification.Name("closePopupPanel")
    static let openFavoriteManager = Notification.Name("openFavoriteManager")
    static let shiftTabPressed = Notification.Name("shiftTabPressed")
    static let selectLibraryItem = Notification.Name("selectLibraryItem")
}
