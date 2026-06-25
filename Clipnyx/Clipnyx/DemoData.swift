#if DEBUG
import AppKit

/// マーケティング用スクリーンショット生成（`ScreenshotRenderer`）とデモ録画モード
/// （`--demo-mode`）で共有するデモデータ（Debug ビルド限定）。
///
/// 見栄えのする履歴・お気に入り・フォルダを提供し、どちらの用途でも
/// 読み取り専用ストアと組み合わせて使うことで実データには一切触れない。
@MainActor
enum DemoData {
    struct Bundle {
        let items: [ClipboardItem]
        let folders: [FavoriteFolder]
        /// コレクション画面で選択状態にするアイテム
        let collectionItemId: UUID
        /// アイテム ID → 実際のペーストボード代表データ。デモ録画モードで
        /// クリップボードへ復元・ペーストできるようにする（read-only ストアに渡す）。
        let representations: [UUID: [PasteboardRepresentation]]
    }

    static func make(japanese: Bool) -> Bundle {
        let templates = FavoriteFolder(name: japanese ? "定型文" : "Templates", order: 0)
        let work = FavoriteFolder(name: japanese ? "仕事" : "Work", order: 1)

        var order = 0
        var representations: [UUID: [PasteboardRepresentation]] = [:]
        func item(
            _ category: ClipboardContentCategory,
            _ preview: String,
            size: Int? = nil,
            thumbnail: Data? = nil,
            favorite: String? = nil,
            folder: FavoriteFolder? = nil
        ) -> ClipboardItem {
            order += 1
            let id = UUID()
            // デモアイテムでも実際にペーストできるよう、代表データをメモリに用意する。
            // 画像は PNG、それ以外（テキスト・URL・コード・色・ファイル名等）は文字列として貼る。
            if category == .image, let thumbnail {
                representations[id] = [PasteboardRepresentation(type: .png, data: thumbnail)]
            } else {
                representations[id] = [PasteboardRepresentation(type: .string, data: Data(preview.utf8))]
            }
            return ClipboardItem(
                id: id,
                timestamp: Date().addingTimeInterval(TimeInterval(-order * 173)),
                category: category,
                previewText: preview,
                thumbnailData: thumbnail,
                totalDataSize: size ?? preview.utf8.count,
                contentHash: Data([UInt8(order)]),
                representationInfos: [RepresentationInfo(type: NSPasteboard.PasteboardType.string.rawValue, size: size ?? preview.utf8.count)],
                isSaved: favorite != nil,
                favoriteName: favorite,
                favoriteFolderId: folder?.id
            )
        }

        let items: [ClipboardItem]
        let emailTemplate: ClipboardItem

        if japanese {
            emailTemplate = item(
                .plainText,
                "お世話になっております。澤田です。\nご確認のほどよろしくお願いいたします。",
                favorite: "メールの定型文", folder: templates
            )
            items = [
                item(.url, "https://developer.apple.com/jp/macos/"),
                item(.plainText, "明日の打ち合わせは 14:00 から、3F 会議室 B に変更になりました。"),
                item(.image, "画像 1,024×640", size: 482_304, thumbnail: thumbnail()),
                item(.sourceCode, "func greet(name: String) -> String {\n    \"こんにちは、\\(name)さん！\"\n}"),
                emailTemplate,
                item(.color, "#5E5CE6"),
                item(.fileURL, "企画書_2026.pdf, ロゴ案.png", size: 2_412_544),
                item(.plainText, "〒150-0002 東京都渋谷区渋谷 2-21-1", favorite: "会社の住所", folder: templates),
                item(.csv, "日付,項目,金額\n2026-06-01,交通費,1280"),
                item(.plainText, "いつもありがとうございます。\n本日もよろしくお願いいたします。", favorite: "朝の挨拶", folder: templates),
                item(.plainText, "## 週報 YYYY-MM-DD\n- 今週やったこと\n- 来週やること\n- 課題", favorite: "週報テンプレート", folder: work),
                item(.plainText, "日時:\n参加者:\n決定事項:\nTODO:", favorite: "議事録の雛形", folder: work),
            ]
        } else {
            emailTemplate = item(
                .plainText,
                "Thanks for reaching out!\nPlease let me know if you have any questions.",
                favorite: "Email template", folder: templates
            )
            items = [
                item(.url, "https://developer.apple.com/macos/"),
                item(.plainText, "Tomorrow's meeting has been moved to 2:00 PM in Conference Room B."),
                item(.image, "Image 1,024×640", size: 482_304, thumbnail: thumbnail()),
                item(.sourceCode, "func greet(name: String) -> String {\n    \"Hello, \\(name)!\"\n}"),
                emailTemplate,
                item(.color, "#5E5CE6"),
                item(.fileURL, "Proposal_2026.pdf, Logo_draft.png", size: 2_412_544),
                item(.plainText, "1 Apple Park Way, Cupertino, CA 95014", favorite: "Office address", folder: templates),
                item(.csv, "date,item,amount\n2026-06-01,transit,12.80"),
                item(.plainText, "Good morning team!\nHope you all have a great day.", favorite: "Morning greeting", folder: templates),
                item(.plainText, "## Weekly report YYYY-MM-DD\n- Done this week\n- Next week\n- Issues", favorite: "Weekly report", folder: work),
                item(.plainText, "Date:\nAttendees:\nDecisions:\nTODO:", favorite: "Meeting notes", folder: work),
            ]
        }

        return Bundle(
            items: items,
            folders: [templates, work],
            collectionItemId: emailTemplate.id,
            representations: representations
        )
    }

    private static func thumbnail() -> Data? {
        let size = NSSize(width: 512, height: 320)
        let image = NSImage(size: size, flipped: false) { rect in
            let gradient = NSGradient(colors: [
                NSColor(calibratedRed: 0.18, green: 0.16, blue: 0.45, alpha: 1),
                NSColor(calibratedRed: 0.45, green: 0.35, blue: 0.85, alpha: 1),
            ])
            gradient?.draw(in: rect, angle: 35)
            // 月っぽい円を添える
            NSColor(calibratedWhite: 0.95, alpha: 0.9).setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.maxX - 130, y: rect.maxY - 120, width: 80, height: 80)).fill()
            return true
        }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
#endif
