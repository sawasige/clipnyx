import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @Environment(ClipboardManager.self) private var clipboardManager

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            HistoryTab(clipboardManager: clipboardManager)
                .tabItem {
                    Label("History", systemImage: "clock")
                }

            FilterTab(clipboardManager: clipboardManager)
                .tabItem {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 350)
    }
}

// MARK: - General Tab

private struct GeneralTab: View {
    var body: some View {
        Form {
            Section("Startup") {
                LaunchAtLoginToggle()
            }

            Section("Hot Key") {
                HotKeyRecorderRow()
            }

            #if ENABLE_AUTOPASTE
            Section("Accessibility") {
                AccessibilityStatusView()
            }
            #endif

            Section("About") {
                LabeledContent("Version") {
                    Text(verbatim: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                }
            }
        }
    }
}

// MARK: - History Tab

private struct HistoryTab: View {
    @Bindable var clipboardManager: ClipboardManager

    private let historyCountOptions = [20, 50, 100, 200, 500]
    private let totalSizeOptions = [256, 512, 1024, 2048, 5120]

    var body: some View {
        Form {
            Section("History") {
                Picker("Max Items", selection: $clipboardManager.maxHistoryCount) {
                    ForEach(historyCountOptions, id: \.self) { count in
                        Text("\(count) items").tag(count)
                    }
                }

                Picker("Max Storage", selection: $clipboardManager.maxTotalSizeMB) {
                    ForEach(totalSizeOptions, id: \.self) { size in
                        if size >= 1024 {
                            Text("\(size / 1024) GB").tag(size)
                        } else {
                            Text("\(size) MB").tag(size)
                        }
                    }
                }

                LabeledContent("Current Items") {
                    Text("\(clipboardManager.items.count) items")
                }

                LabeledContent("Current Usage") {
                    Text(clipboardManager.formattedTotalSize)
                }
            }

            Section {
                Button("Delete All History", role: .destructive) {
                    clipboardManager.removeAllItems()
                }
            }
        }
    }
}

// MARK: - Launch at Login

private struct LaunchAtLoginToggle: View {
    @State private var isEnabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Launch at Login", isOn: $isEnabled)
            .onChange(of: isEnabled) { _, newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    isEnabled = SMAppService.mainApp.status == .enabled
                }
            }
    }
}

#if ENABLE_AUTOPASTE
// MARK: - Accessibility Status

private struct AccessibilityStatusView: View {
    @State private var isGranted = AXIsProcessTrusted()
    var body: some View {
        LabeledContent("Permission Status") {
            HStack(spacing: 6) {
                Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(isGranted ? .green : .red)
                if isGranted {
                    Text("Granted")
                } else {
                    Text("Not Granted")
                }
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                isGranted = AXIsProcessTrusted()
            }
        }

        if !isGranted {
            Text("Accessibility permission is required for paste and cursor detection. You may need to restart the app after granting permission.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Open System Settings") {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                )
            }
        }
    }
}
#endif

// MARK: - Hot Key Recorder

private struct HotKeyRecorderRow: View {
    @State private var keyCode: UInt32 = HotKeyManager.shared.currentKeyCode
    @State private var modifiers: UInt = HotKeyManager.shared.currentModifiers
    @State private var isRecording = false
    @State private var eventMonitor: Any?

    private var displayString: String {
        HotKeyManager.displayString(keyCode: keyCode, modifiers: modifiers)
    }

    var body: some View {
        LabeledContent("Hot Key") {
            Button {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            } label: {
                Group {
                    if isRecording {
                        Text("Press a key...")
                    } else {
                        Text(verbatim: displayString)
                    }
                }
                .frame(minWidth: 80)
            }
            .keyboardShortcut(.none)
        }
    }

    private func startRecording() {
        HotKeyManager.shared.unregister()
        isRecording = true

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let cocoaModifiers = event.modifierFlags
                .intersection([.command, .shift, .option, .control]).rawValue
            // Require at least one modifier key (⌘, ⌥, ⌃, ⇧)
            guard cocoaModifiers != 0 else { return nil }

            let newKeyCode = UInt32(event.keyCode)
            keyCode = newKeyCode
            modifiers = cocoaModifiers

            HotKeyManager.shared.currentKeyCode = newKeyCode
            HotKeyManager.shared.currentModifiers = cocoaModifiers

            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        guard isRecording else { return }
        isRecording = false
        HotKeyManager.shared.register()
    }
}

// MARK: - Filter Tab

private struct FilterTab: View {
    @Bindable var clipboardManager: ClipboardManager

    var body: some View {
        Form {
            Section("Category Filter") {
                Text("Disabled categories will not be recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(ClipboardContentCategory.allCases, id: \.self) { category in
                    Toggle(isOn: Binding(
                        get: { !clipboardManager.excludedCategories.contains(category) },
                        set: { isEnabled in
                            if isEnabled {
                                clipboardManager.excludedCategories.remove(category)
                            } else {
                                clipboardManager.excludedCategories.insert(category)
                            }
                        }
                    )) {
                        Label {
                            Text(category.label)
                        } icon: {
                            Image(systemName: category.icon)
                                .foregroundStyle(category.color)
                        }
                    }
                }
            }
        }
    }
}
