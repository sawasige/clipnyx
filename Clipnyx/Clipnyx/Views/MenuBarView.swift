import SwiftUI

struct MenuBarView: View {
    @Environment(ClipboardManager.self) private var clipboardManager
    @State private var viewId = UUID()

    var body: some View {
        PopupContentView(
            clipboardManager: clipboardManager,
            isMenuBar: true,
            onDismiss: {},
            onPaste: {}
        )
        .id(viewId)
        .frame(width: 360)
        .onAppear {
            viewId = UUID()
            NotificationCenter.default.post(name: .closePopupPanel, object: nil)
        }
    }
}
