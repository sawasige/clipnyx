#if ENABLE_AUTOPASTE
import AppKit
import Sparkle

@MainActor
final class UpdateManager: NSObject, SPUStandardUserDriverDelegate {
    private var updaterController: SPUStandardUpdaterController!

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    override init() {
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    // MARK: - SPUStandardUserDriverDelegate

    /// バックグラウンドアプリ（LSUIElement）での gentle reminder 対応
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        if !state.userInitiated {
            Task { @MainActor in
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
#endif
