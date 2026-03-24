import SwiftUI
import Carbon.HIToolbox

@main
struct PasteTestApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var status = "Open a text editor, then tap the button."

    var body: some View {
        VStack(spacing: 20) {
            Text(status)
                .font(.title3)

            Button("Copy text & simulate ⌘V") {
                // 1. Check PostEvent access
                let hasAccess = CGPreflightPostEventAccess()
                if !hasAccess {
                    CGRequestPostEventAccess()
                    status = "Please grant permission in System Settings > Privacy & Security > Accessibility"
                    return
                }

                // 2. Write text to pasteboard
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString("Hello from PasteTest", forType: .string)

                // 3. Hide the app so the previous app becomes active, then post ⌘V
                NSApp.hide(nil)

                Task {
                    // Wait for another app to become frontmost
                    try? await Task.sleep(for: .milliseconds(300))

                    await MainActor.run {
                        // Post ⌘V keystroke via CGEvent (Core Graphics API)
                        // This requires kTCCServicePostEvent, NOT kTCCServiceAccessibility
                        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: UInt16(kVK_ANSI_V), keyDown: true),
                              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: UInt16(kVK_ANSI_V), keyDown: false) else {
                            return
                        }
                        keyDown.flags = .maskCommand
                        keyUp.flags = .maskCommand
                        keyDown.post(tap: .cgSessionEventTap)
                        keyUp.post(tap: .cgSessionEventTap)
                    }

                    // Show window again after paste
                    try? await Task.sleep(for: .milliseconds(500))
                    await MainActor.run {
                        NSApp.activate(ignoringOtherApps: true)
                        for window in NSApp.windows {
                            window.makeKeyAndOrderFront(nil)
                        }
                        status = "✓ Simulated ⌘V via CGEvent.post"
                    }
                }
            }
            .buttonStyle(.borderedProminent)

            Text("""
                This app uses CGEvent.post (kTCCServicePostEvent)
                to simulate a ⌘V keystroke.
                It does NOT use AXUIElement or any Accessibility framework API.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(width: 500, height: 300)
    }
}
