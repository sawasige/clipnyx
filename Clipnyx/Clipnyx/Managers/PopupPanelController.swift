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
                #if ENABLE_AUTOPASTE
                self?.closeAndPaste()
                #else
                self?.closeAndCopy()
                #endif
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

    #if ENABLE_AUTOPASTE
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
    #else
    private var toastPanel: NSPanel?

    func closeAndCopy() {
        let panelFrame = panel?.frame
        close()

        guard let panelFrame else { return }
        showToast(near: panelFrame)
    }

    private func showToast(near frame: NSRect) {
        let toastWidth: CGFloat = frame.width
        let toastHeight: CGFloat = 40

        let toast = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: toastWidth, height: toastHeight),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        toast.isFloatingPanel = true
        toast.level = .floating
        toast.backgroundColor = .clear
        toast.isOpaque = false
        toast.hasShadow = true
        toast.hidesOnDeactivate = false
        toast.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let toastView = NSHostingView(rootView: ToastContentView())
        toast.contentView = toastView

        let origin = NSPoint(
            x: frame.midX - toastWidth / 2,
            y: frame.midY - toastHeight / 2
        )
        toast.setFrameOrigin(origin)
        toast.alphaValue = 1
        toast.orderFrontRegardless()
        self.toastPanel = toast

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                toast.animator().alphaValue = 0
            }
            toast.orderOut(nil)
            self?.toastPanel = nil
        }
    }
    #endif

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

#if !ENABLE_AUTOPASTE
private struct ToastContentView: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("コピーしました")
                .font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
#endif
