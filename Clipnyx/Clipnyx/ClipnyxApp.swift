import SwiftUI

@main
enum ClipnyxMain {
    static func main() {
        MainActor.assumeIsolated {
            #if DEBUG
            // スクリーンショット生成モードのときは通常起動せずに終了する
            if ScreenshotRenderer.runIfRequested() { return }
            #endif
            ClipnyxApp.main()
        }
    }
}

struct ClipnyxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage(MenuBarSettings.showIconKey) private var showMenuBarIcon = true

    var body: some Scene {
        MenuBarExtra("Clipnyx", image: "MenuBarIcon", isInserted: $showMenuBarIcon) {
            MenuBarView()
                .environment(appDelegate.clipboardManager)
        }
    }
}

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let clipboardManager = AppDelegate.makeClipboardManager()
    private var popupController = PopupPanelController()
    private var settingsWindow: NSWindow?
    private var favoriteManagerWindow: NSWindow?
    #if ENABLE_SPARKLE
    let updateManager = UpdateManager()
    #endif

    /// 通常は実データを扱う ClipboardManager を生成する。Debug ビルドを
    /// `--demo-mode` で起動したときだけ、デモデータ＋読み取り専用ストアの
    /// 録画用マネージャを返す（実データには一切触れない）。
    static func makeClipboardManager() -> ClipboardManager {
        #if DEBUG
        if CommandLine.arguments.contains("--demo-mode") {
            let isJapanese = Locale.preferredLanguages.first?.hasPrefix("ja") ?? false
            let demo = DemoData.make(japanese: isJapanese)
            return ClipboardManager(
                demoItems: demo.items,
                demoFolders: demo.folders,
                demoRepresentations: demo.representations
            )
        }
        #endif
        return ClipboardManager()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // PostEvent 権限は起動時には要求しない。ユーザーが初めて直接ペーストした
        // タイミングでのみ要求する（App Store ガイドライン 2.4.5 対策。
        // 要求箇所は PopupPanelController.closeAndPaste を参照）
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

    /// Finder / Launchpad からアプリを開き直したとき（reopen）はホットキーと同じく
    /// ポップアップパネルを開く。メニューバーアイコンを非表示にしていても、ここから
    /// パネルのメニュー経由で設定・終了に辿り着ける最終的な復帰手段になる。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            popupController.toggle(clipboardManager: clipboardManager)
        }
        return true
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
        // 位置・サイズを記憶する（macOS 純正の仕組み。復元時に AppKit が画面内へ補正する）。
        window.setFrameUsingName("FavoriteManagerWindow")
        window.setFrameAutosaveName("FavoriteManagerWindow")
        window.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // NavigationSplitView のカラム幅を記憶させる。SwiftUI は永続化 API を出して
        // いないため、裏側の NSSplitView を探して autosaveName を設定する。
        // SwiftUI 内部構造に依存するが、見つからなければ黙って何もしない（クラッシュしない）。
        persistSplitViewWidths(in: window)
    }

    /// NavigationSplitView の裏側の NSSplitView に autosaveName を設定し、カラム幅を永続化する。
    /// SwiftUI はビューを次のランループ以降に生成するため、見つかるまで数回だけ再試行する。
    private func persistSplitViewWidths(in window: NSWindow, attempt: Int = 0) {
        guard let contentView = window.contentView else { return }
        let splitViews = Self.collectSplitViews(in: contentView)
        if splitViews.isEmpty {
            guard attempt < 5 else { return }
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window else { return }
                self.persistSplitViewWidths(in: window, attempt: attempt + 1)
            }
            return
        }
        for (index, splitView) in splitViews.enumerated() where (splitView.autosaveName ?? "").isEmpty {
            splitView.autosaveName = "FavoriteManagerSplit-\(index)"
        }
    }

    private static func collectSplitViews(in view: NSView) -> [NSSplitView] {
        var result: [NSSplitView] = []
        if let split = view as? NSSplitView { result.append(split) }
        for sub in view.subviews {
            result.append(contentsOf: collectSplitViews(in: sub))
        }
        return result
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

enum MenuBarSettings {
    /// メニューバーアイコンの表示/非表示（既定 true）。
    /// アプリ本体（MenuBarExtra）と設定画面で共有する。
    static let showIconKey = "showMenuBarIcon"
}

extension Notification.Name {
    static let openSettingsRequest = Notification.Name("openSettingsRequest")
    static let openPopupPanel = Notification.Name("openPopupPanel")
    static let closePopupPanel = Notification.Name("closePopupPanel")
    static let openFavoriteManager = Notification.Name("openFavoriteManager")
    static let shiftTabPressed = Notification.Name("shiftTabPressed")
    static let selectLibraryItem = Notification.Name("selectLibraryItem")
}
