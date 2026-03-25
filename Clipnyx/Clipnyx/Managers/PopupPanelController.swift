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

        let panelWidth: CGFloat = 380
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
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            targetApp.activate()
            await performPaste(targetPID: targetApp.processIdentifier, attempt: 0)
        }
    }

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
