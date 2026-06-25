import AppKit
import SwiftUI
import Observation

// MARK: - KeyablePanel

private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    var onEscape: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           event.keyCode == 48 /* Tab */,
           event.modifierFlags.contains(.shift) {
            NotificationCenter.default.post(name: .shiftTabPressed, object: nil)
            return
        }
        super.sendEvent(event)
    }
}

@MainActor
@Observable
final class PopupPanelController {
    private var panel: NSPanel?
    private var previousApp: NSRunningApplication?
    private var clickMonitor: Any?
    private var localClickMonitor: Any?
    private var appActivationObserver: NSObjectProtocol?
    private var hasShownPastePermissionPrompt = false
    var isVisible: Bool = false

    init() {
        NotificationCenter.default.addObserver(
            forName: .closePopupPanel,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.close(restoreFocus: false)
            }
        }
    }

    func toggle(clipboardManager: ClipboardManager) {
        if isVisible {
            close()
        } else {
            show(clipboardManager: clipboardManager)
        }
    }

    func show(clipboardManager: ClipboardManager) {
        guard !isVisible else { return }

        // パネル表示前の最前面アプリを記憶
        previousApp = NSWorkspace.shared.frontmostApplication

        let panelWidth: CGFloat = 420
        let panelHeight: CGFloat = 560

        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.onEscape = { [weak self] in
            self?.close()
        }
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let contentView = PopupContentView(
            clipboardManager: clipboardManager,
            onDismiss: { [weak self] in
                self?.close()
            },
            onPaste: { [weak self] in
                self?.closeAndPaste()
            }
        )

        panel.contentView = NSHostingView(rootView: contentView)

        self.panel = panel
        self.isVisible = true

        let mousePoint = NSEvent.mouseLocation
        let panelOrigin = Self.panelOrigin(anchor: mousePoint, panelWidth: panelWidth, panelHeight: panelHeight)
        panel.setFrameOrigin(panelOrigin)
        panel.makeKeyAndOrderFront(nil)
        setupClickMonitor()
        setupAppActivationObserver()
    }

    func close(restoreFocus: Bool = true) {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        if let monitor = localClickMonitor {
            NSEvent.removeMonitor(monitor)
            localClickMonitor = nil
        }
        if let observer = appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appActivationObserver = nil
        }
        panel?.orderOut(nil)
        panel = nil
        isVisible = false

        if restoreFocus {
            previousApp?.activate()
        }
    }

    func closeAndPaste() {
        let targetApp = previousApp
        close(restoreFocus: false)

        guard let targetApp else { return }

        // アイテムは selectAndPaste で既にクリップボードへ復元済み。自動ペーストは
        // 「⌘V を省く」便宜機能で、無効時・未許可時は手動 ⌘V にフォールバックする。

        // 自動ペーストが無効なら直接ペーストせず、元アプリへ戻して手動 ⌘V を可能にする。
        guard PasteAccess.isAutoPasteEnabled else {
            targetApp.activate()
            return
        }

        #if ENABLE_SPARKLE
        // Full 版: 権限がなさそうなら、初回だけ自前の説明を提示してから要求する
        // （起動時やいきなりのシステムダイアログを避ける）。hasPermission() は
        // プロセス内でキャッシュされ付与後も更新されないため、これは「初回に説明を
        // 出すか」の best-effort 判定に留める。実際の投函（下の performPaste）は
        // ライブの TCC 状態で判定されるので、付与直後でも再起動なしで動作する。
        if !PasteAccess.hasPermission() && !hasShownPastePermissionPrompt {
            hasShownPastePermissionPrompt = true
            presentPastePermissionExplanation(restoreFocusTo: targetApp)
            return
        }
        #else
        // App Store 版: 権限を一切「要求」しない（システムダイアログを出さない・
        // アクセシビリティへの言及も一切しない）。ユーザーが自分でアクセシビリティへ
        // Clipnyx を追加済みのとき（preflight が true）だけ自動ペーストする。未許可
        // なら何もせず元アプリへ戻し、手動 ⌘V で貼れるようにする。preflight は
        // プロセス内キャッシュのため、付与後は Clipnyx の再起動で有効になる。
        #if DEBUG
        // デモ録画モードでは preflight ガードを外し、投函（CGEvent.post＝ライブ判定）に
        // 任せる。初回投函で macOS が許可ダイアログを出し、許可後は再起動なしで効く。
        let canAutoPaste = PasteAccess.hasPermission() || CommandLine.arguments.contains("--demo-mode")
        #else
        let canAutoPaste = PasteAccess.hasPermission()
        #endif
        guard canAutoPaste else {
            targetApp.activate()
            return
        }
        #endif

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            targetApp.activate()
            await performPaste(targetPID: targetApp.processIdentifier, attempt: 0)
        }
    }

    #if ENABLE_SPARKLE
    /// 直接ペースト権限が未許可のとき、初回だけ表示する説明。システムのダイアログを
    /// いきなり出さず、目的とフォールバック（手動 ⌘V）を伝えてから要求する。
    /// App Store 版では権限を要求しないため、この説明自体を持たない。
    private func presentPastePermissionExplanation(restoreFocusTo targetApp: NSRunningApplication) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = String(localized: "Copied — press ⌘V to paste")
        alert.informativeText = String(localized: "To paste automatically with a single click, Clipnyx needs permission to control your computer (System Settings ▸ Privacy & Security ▸ Accessibility). Without it, your selection is still copied and you can paste it yourself with ⌘V.")
        alert.addButton(withTitle: String(localized: "Enable One-Click Paste…"))
        alert.addButton(withTitle: String(localized: "Not Now"))

        if alert.runModal() == .alertFirstButtonReturn {
            // 権限を要求する。システムダイアログ表示中に他アプリへフォーカスを移すと
            // ダイアログが閉じて登録が完了しないため、ここでは元アプリへ戻さず
            // Clipnyx を前面に保つ。
            PasteAccess.requestPermission()
        } else {
            // 「後で」の場合のみ、手動 ⌘V 用に元アプリへ戻す。
            targetApp.activate()
        }
    }
    #endif

    private func performPaste(targetPID: pid_t, attempt: Int) async {
        let maxAttempts = 10

        try? await Task.sleep(for: .milliseconds(50))
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

        if frontPID != targetPID, attempt < maxAttempts {
            await performPaste(targetPID: targetPID, attempt: attempt + 1)
            return
        }

        Self.postPasteEvent()
    }

    private static func postPasteEvent() {
        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false) else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            keyUp.post(tap: .cgSessionEventTap)
        }
    }

    // MARK: - Panel Positioning

    private static func panelOrigin(anchor: NSPoint, panelWidth: CGFloat, panelHeight: CGFloat) -> NSPoint {
        var origin = NSPoint(x: anchor.x, y: anchor.y - panelHeight)

        if let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) }) ?? NSScreen.main {
            let visibleFrame = screen.visibleFrame
            if origin.x < visibleFrame.minX { origin.x = visibleFrame.minX }
            if origin.x + panelWidth > visibleFrame.maxX { origin.x = visibleFrame.maxX - panelWidth }
            if origin.y < visibleFrame.minY { origin.y = visibleFrame.minY }
            if origin.y + panelHeight > visibleFrame.maxY { origin.y = visibleFrame.maxY - panelHeight }
        }

        return origin
    }

    private func setupClickMonitor() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.window !== panel && event.window?.parent !== panel {
                self.close(restoreFocus: false)
            }
            return event
        }
    }

    private func setupAppActivationObserver() {
        guard appActivationObserver == nil else { return }
        let currentApp = previousApp
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            // パネル表示時にアクティブだったアプリの通知は無視
            if app.processIdentifier == currentApp?.processIdentifier { return }
            MainActor.assumeIsolated {
                self?.close(restoreFocus: false)
            }
        }
    }
}

// MARK: - PasteAccess

/// 直接ペースト（⌘V 注入）に必要な PostEvent 権限と、自動ペースト設定の窓口。
/// ペースト経路（PopupPanelController）と設定画面（SettingsView）で共有する。
enum PasteAccess {
    /// 自動ペーストの有効/無効（デフォルト ON）。未設定時は true を返す。
    static let autoPasteEnabledKey = "autoPasteEnabled"

    static var isAutoPasteEnabled: Bool {
        UserDefaults.standard.object(forKey: autoPasteEnabledKey) as? Bool ?? true
    }

    /// 権限の有無を確認する。ダイアログは出さない。
    static func hasPermission() -> Bool {
        CGPreflightPostEventAccess()
    }

    #if ENABLE_SPARKLE
    /// 直接ペースト権限を要求する。未判定なら `CGRequestPostEventAccess()` が
    /// システムダイアログを表示し、アプリをアクセシビリティ一覧へ登録する。
    /// このダイアログ自体に「システム設定を開く」導線があるため、こちらからは
    /// 設定を開かない（二重表示の防止）。一度応答済み（拒否含む）でダイアログが
    /// 出ないケースは、設定画面の常設「システム設定…」ボタンで誘導する。
    /// App Store 版ではこの API（および CGRequestPostEventAccess シンボル）を
    /// バイナリに含めない（ガイドライン 2.4.5 対策）。
    @discardableResult
    static func requestPermission() -> Bool {
        CGRequestPostEventAccess()
    }

    /// システム設定の「プライバシーとセキュリティ ▸ アクセシビリティ」画面を開く。
    /// 許可済みのユーザーが権限を確認・取り消したい場合にも使う。
    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    #endif
}
