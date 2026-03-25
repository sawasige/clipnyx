import SwiftUI

struct MenuBarView: View {
    @Environment(ClipboardManager.self) private var clipboardManager

    var body: some View {
        VStack(spacing: 4) {
            Button {
                NotificationCenter.default.post(name: .openPopupPanel, object: nil)
            } label: {
                let hotKeyDisplay = HotKeyManager.displayString(
                    keyCode: HotKeyManager.shared.currentKeyCode,
                    modifiers: HotKeyManager.shared.currentModifiers
                )
                Label("Show History (\(hotKeyDisplay))", systemImage: "clipboard")
            }

            Divider()

            Button {
                NotificationCenter.default.post(name: .openFavoriteManager, object: nil)
            } label: {
                Label("Collection", systemImage: "books.vertical")
            }

            Divider()

            Button {
                clipboardManager.isPaused.toggle()
            } label: {
                Label(
                    clipboardManager.isPaused ? "Resume Monitoring" : "Pause Monitoring",
                    systemImage: clipboardManager.isPaused ? "play.fill" : "pause.fill"
                )
            }

            Button {
                NotificationCenter.default.post(name: .openSettingsRequest, object: nil)
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}
