import SwiftUI
import AppKit
import ServiceManagement

// MARK: - General Tab

struct GeneralTab: View {
    #if ENABLE_SPARKLE
    let updateManager: UpdateManager
    #endif

    var body: some View {
        Form {
            Section("Startup") {
                LaunchAtLoginToggle()
            }

            Section("Hot Key") {
                HotKeyRecorderRow()
            }

            #if ENABLE_SPARKLE
            Section("Software Update") {
                SoftwareUpdateView(updateManager: updateManager)
            }
            #endif

            Section("About") {
                LabeledContent("Version") {
                    Text(verbatim: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                }
                LabeledContent("Edition") {
                    #if ENABLE_SPARKLE
                    Text("Full")
                    #else
                    Text("App Store")
                    #endif
                }
            }
        }
    }
}

// MARK: - History Tab

struct HistoryTab: View {
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
                    let pinnedCount = clipboardManager.items.filter(\.isPinned).count
                    if pinnedCount > 0 {
                        Text("\(clipboardManager.items.count) items (\(pinnedCount) pinned)")
                    } else {
                        Text("\(clipboardManager.items.count) items")
                    }
                }

                LabeledContent("Current Usage") {
                    Text(clipboardManager.formattedTotalSize)
                }
            }

            Section {
                Button("Delete History", role: .destructive) {
                    clipboardManager.removeAllItems()
                }
            } footer: {
                Text("Pinned items will not be deleted.")
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

#if ENABLE_SPARKLE
// MARK: - Software Update

private struct SoftwareUpdateView: View {
    let updateManager: UpdateManager
    @State private var automaticallyChecks: Bool

    init(updateManager: UpdateManager) {
        self.updateManager = updateManager
        self._automaticallyChecks = State(initialValue: updateManager.automaticallyChecksForUpdates)
    }

    var body: some View {
        Toggle("Automatically Check for Updates", isOn: $automaticallyChecks)
            .onChange(of: automaticallyChecks) { _, newValue in
                updateManager.automaticallyChecksForUpdates = newValue
            }

        Button("Check for Updates...") {
            updateManager.checkForUpdates()
        }
        .disabled(!updateManager.canCheckForUpdates)
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

struct FilterTab: View {
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
