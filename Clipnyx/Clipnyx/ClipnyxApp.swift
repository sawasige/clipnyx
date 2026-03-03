import SwiftUI
import ApplicationServices

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
        // アクセシビリティ権限の確認
        if !AXIsProcessTrusted() {
            showAccessibilityAlert()
        }

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

        let settingsView = SettingsView()
            .environment(clipboardManager)

        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Settings")
        window.contentView = NSHostingView(rootView: settingsView)
        window.setContentSize(window.contentView!.fittingSize)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.settingsWindow = window

        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKey()
    }
}

// MARK: - Accessibility Alert

extension AppDelegate {
    func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Accessibility Permission Required")
        let message = String(localized: "Clipnyx needs accessibility permission to paste clipboard items. Please add Clipnyx in System Settings → Privacy & Security → Accessibility.")
        alert.informativeText = "\(message)\n\n\(Bundle.main.bundlePath)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Open System Settings"))
        alert.addButton(withTitle: String(localized: "Later"))

        let copyButton = NSButton(title: String(localized: "Copy App Path"), image: NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)!, target: self, action: #selector(copyAppPath(_:)))
        copyButton.imagePosition = .imageLeading
        copyButton.bezelStyle = .accessoryBarAction
        alert.accessoryView = copyButton

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            )
        }
    }

    @objc private func copyAppPath(_ sender: NSButton) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Bundle.main.bundlePath, forType: .string)

        let originalImage = sender.image
        sender.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Copied")
        sender.contentTintColor = .systemGreen
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            sender.image = originalImage
            sender.contentTintColor = nil
        }
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
