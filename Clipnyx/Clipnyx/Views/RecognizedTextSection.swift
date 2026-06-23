import SwiftUI

/// 画像・PDF の OCR 認識テキストを表示するセクション。
/// recognizedText の3状態（nil=解析中 / 空=文字なし / 非空=テキストあり）で表示を切り替える。
struct RecognizedTextSection: View {
    let recognizedText: String?
    /// OCR がいま処理中か。true のとき「解析中…」を表示する。
    var isRecognizing: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Recognized Text", systemImage: "text.viewfinder")
                .font(.subheadline.bold())

            switch state {
            case .analyzing:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Analyzing text…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)

            case .empty:
                Text("No text detected.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)

            case .text(let value):
                ScrollView {
                    Text(value)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor))
                )
            }
        }
    }

    private enum State {
        case analyzing
        case empty
        case text(String)
    }

    private var state: State {
        if isRecognizing { return .analyzing }
        guard let recognizedText else { return .empty }
        return recognizedText.isEmpty ? .empty : .text(recognizedText)
    }
}
