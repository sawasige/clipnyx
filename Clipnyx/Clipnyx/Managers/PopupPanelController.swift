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
}

@MainActor
@Observable
final class PopupPanelController {
    private var panel: NSPanel?
    private var previousApp: NSRunningApplication?
    private var clickMonitor: Any?
    var isVisible: Bool = false

    func toggle(clipboardManager: ClipboardManager) {
        if isVisible {
            close()
        } else {
            show(clipboardManager: clipboardManager)
        }
    }

    func show(clipboardManager: ClipboardManager) {
        guard !isVisible else { return }

        // パネル表示前の最前面アプリを記憶（自分自身は除外）
        let myBundleID = Bundle.main.bundleIdentifier
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.bundleIdentifier != myBundleID {
            previousApp = frontmost
        }

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
    }

    func close() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        panel?.orderOut(nil)
        panel = nil
        isVisible = false

        // 元のアプリを再アクティベート
        previousApp?.activate()
    }

    func closeAndPaste() {
        let targetApp = previousApp
        close()

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
        keyDown.post(tap: .cghidEventTap)
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            keyUp.post(tap: .cghidEventTap)
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
    }
}
