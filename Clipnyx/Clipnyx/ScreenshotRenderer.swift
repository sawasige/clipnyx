#if DEBUG
import AppKit
import SwiftUI

/// マーケティング用スクリーンショットをオフスクリーン描画で生成する（Debug ビルド限定）。
///
/// `Clipnyx --render-screenshots -AppleLanguages '(ja)'` のように起動すると、
/// 実データに触れずデモデータでペーストパネルを描画し、ヘッドライン付きの
/// 2560×1600（App Store 用）画像とパネル単体の PNG を書き出して終了する。
/// サンドックスのため出力先はコンテナ内の一時ディレクトリ（stdout にパスを出力）。
/// 通常は scripts/generate_screenshots.sh から使う。
@MainActor
enum ScreenshotRenderer {
    /// `--render-screenshots` 付きで起動されたときだけ実行し、true を返す
    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains("--render-screenshots") else { return false }

        NSApplication.shared.setActivationPolicy(.prohibited)

        let outDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("clipnyx-screenshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let isJapanese = Locale.preferredLanguages.first?.hasPrefix("ja") ?? false
        let lang = isJapanese ? "ja" : "en"

        for dark in [false, true] {
            let style = dark ? "dark" : "light"
            let panel = renderPanel(japanese: isJapanese, dark: dark)
            write(panel, to: outDir.appendingPathComponent("panel-\(lang)-\(style).png"))
            let marketing = renderMarketing(panel: panel, japanese: isJapanese, dark: dark)
            write(marketing, to: outDir.appendingPathComponent("marketing-\(lang)-\(style).png"))
        }

        print("SCREENSHOTS_DIR: \(outDir.path)")
        return true
    }

    // MARK: - Panel Rendering

    private static func renderPanel(japanese: Bool, dark: Bool) -> NSImage {
        let manager = ClipboardManager(
            previewItems: demoItems(japanese: japanese),
            previewFolders: demoFolders(japanese: japanese)
        )
        let hosting = NSHostingView(rootView: PopupContentView(
            clipboardManager: manager,
            onDismiss: {},
            onPaste: {}
        ))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderFront(nil)

        // LazyVStack の materialize と PreferenceKey ベースの高さ確定を待つ
        pumpRunLoop(seconds: 0.8)
        let height = min(max(hosting.fittingSize.height, 200), 560)
        window.setContentSize(NSSize(width: 420, height: height))
        pumpRunLoop(seconds: 0.4)

        let bounds = hosting.bounds
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: bounds) else {
            fatalError("Failed to create bitmap rep for panel")
        }
        hosting.cacheDisplay(in: bounds, to: rep)
        window.orderOut(nil)

        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }

    private static func pumpRunLoop(seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    // MARK: - Marketing Composition (2560×1600 = 1280×800 @2x)

    private static func renderMarketing(panel: NSImage, japanese: Bool, dark: Bool) -> NSImage {
        let headline = japanese
            ? "クリップボード履歴を自動保存。"
            : "Automatically save clipboard history."
        let subtitle = japanese
            ? "テキスト、画像、コードなど、いつでも呼び出せます。"
            : "Text, images, code, and more—you can access them anytime."

        let view = MarketingShotView(panel: panel, headline: headline, subtitle: subtitle, dark: dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage else {
            fatalError("Failed to render marketing image")
        }
        return image
    }

    private struct MarketingShotView: View {
        let panel: NSImage
        let headline: String
        let subtitle: String
        let dark: Bool

        var body: some View {
            VStack(spacing: 16) {
                Text(headline)
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(dark ? Color.white : Color(red: 0.11, green: 0.11, blue: 0.12))
                Text(subtitle)
                    .font(.system(size: 20))
                    .foregroundStyle(dark ? Color.white.opacity(0.65) : Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.6))
                Image(nsImage: panel)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 440)
                    .shadow(color: .black.opacity(dark ? 0.6 : 0.22), radius: 28, y: 14)
                    .padding(.top, 24)
            }
            .padding(.top, 72)
            .frame(width: 1280, height: 800, alignment: .top)
            .background(dark ? Color(red: 0.11, green: 0.11, blue: 0.12) : Color.white)
        }
    }

    // MARK: - Demo Data

    private static func demoFolders(japanese: Bool) -> [FavoriteFolder] {
        [FavoriteFolder(name: japanese ? "定型文" : "Templates", order: 0)]
    }

    private static func demoItems(japanese: Bool) -> [ClipboardItem] {
        let folderId = demoFolders(japanese: japanese)[0].id
        var order = 0
        func item(
            _ category: ClipboardContentCategory,
            _ preview: String,
            size: Int? = nil,
            thumbnail: Data? = nil,
            favorite: String? = nil,
            inFolder: Bool = false
        ) -> ClipboardItem {
            order += 1
            return ClipboardItem(
                id: UUID(),
                timestamp: Date().addingTimeInterval(TimeInterval(-order * 173)),
                category: category,
                previewText: preview,
                thumbnailData: thumbnail,
                totalDataSize: size ?? preview.utf8.count,
                contentHash: Data([UInt8(order)]),
                representationInfos: [RepresentationInfo(type: NSPasteboard.PasteboardType.string.rawValue, size: size ?? preview.utf8.count)],
                isSaved: favorite != nil,
                favoriteName: favorite,
                favoriteFolderId: inFolder ? folderId : nil
            )
        }

        if japanese {
            return [
                item(.url, "https://developer.apple.com/jp/macos/"),
                item(.plainText, "明日の打ち合わせは 14:00 から、3F 会議室 B に変更になりました。"),
                item(.image, "画像 1,024×640", size: 482_304, thumbnail: demoThumbnail()),
                item(.sourceCode, "func greet(name: String) -> String {\n    \"こんにちは、\\(name)さん！\"\n}"),
                item(.plainText, "お世話になっております。澤田です。\nご確認のほどよろしくお願いいたします。", favorite: "メールの定型文", inFolder: true),
                item(.color, "#5E5CE6"),
                item(.fileURL, "企画書_2026.pdf, ロゴ案.png", size: 2_412_544),
                item(.plainText, "〒150-0002 東京都渋谷区渋谷 2-21-1"),
                item(.csv, "日付,項目,金額\n2026-06-01,交通費,1280"),
            ]
        } else {
            return [
                item(.url, "https://developer.apple.com/macos/"),
                item(.plainText, "Tomorrow's meeting has been moved to 2:00 PM in Conference Room B."),
                item(.image, "Image 1,024×640", size: 482_304, thumbnail: demoThumbnail()),
                item(.sourceCode, "func greet(name: String) -> String {\n    \"Hello, \\(name)!\"\n}"),
                item(.plainText, "Thanks for reaching out!\nPlease let me know if you have any questions.", favorite: "Email template", inFolder: true),
                item(.color, "#5E5CE6"),
                item(.fileURL, "Proposal_2026.pdf, Logo_draft.png", size: 2_412_544),
                item(.plainText, "1 Apple Park Way, Cupertino, CA 95014"),
                item(.csv, "date,item,amount\n2026-06-01,transit,12.80"),
            ]
        }
    }

    private static func demoThumbnail() -> Data? {
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

    // MARK: - Output

    private static func write(_ image: NSImage, to url: URL) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            fatalError("Failed to encode \(url.lastPathComponent)")
        }
        do {
            try png.write(to: url)
        } catch {
            fatalError("Failed to write \(url.path): \(error)")
        }
    }
}
#endif
