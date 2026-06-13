#if DEBUG
import AppKit
import ScreenCaptureKit
import SwiftUI

/// マーケティング用スクリーンショットを生成する（Debug ビルド限定）。
///
/// `Clipnyx --render-screenshots -AppleLanguages '(ja)'` のように起動すると、
/// 実データに触れずデモデータでペーストパネルとコレクション画面を一瞬だけ
/// 実画面に表示し、ScreenCaptureKit で撮影（Liquid Glass 込みの本物の見た目）して、
/// ヘッドライン付きの 2560×1600（App Store 用）画像などの PNG を書き出して終了する。
///
/// - 初回は「画面収録」権限（システム設定 ▸ プライバシーとセキュリティ）の許可が必要。
/// - サンドボックスのため出力先はコンテナ内の一時ディレクトリ（stdout にパスを出力）。
/// - 通常は scripts/generate_screenshots.sh から使う。
@MainActor
enum ScreenshotRenderer {
    /// `--render-screenshots` 付きで起動されたときだけ実行し、true を返す
    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains("--render-screenshots") else { return false }

        // ウィンドウをアクティブ表示（色付き信号機）で撮るため、通常アプリとして
        // 起動を完了させ、イベント処理（pumpRunLoop）でアクティブ化を成立させる
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.finishLaunching()
        app.activate(ignoringOtherApps: true)

        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            print("SCREENSHOTS_ERROR: 画面収録の権限が必要です。")
            print("システム設定 ▸ プライバシーとセキュリティ ▸ 画面収録とシステムオーディオ録音 で Clipnyx を許可してから再実行してください。")
            exit(1)
        }

        let outDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("clipnyx-screenshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let isJapanese = Locale.preferredLanguages.first?.hasPrefix("ja") ?? false
        let lang = isJapanese ? "ja" : "en"

        // 実カーソルのホバーで選択状態が動かないよう、生成中はカーソルを画面隅へ退避
        let savedMouseLocation = CGEvent(source: nil)?.location ?? .zero
        CGWarpMouseCursorPosition(CGPoint(x: 2, y: 2))
        defer { CGWarpMouseCursorPosition(savedMouseLocation) }

        for dark in [false, true] {
            let style = dark ? "dark" : "light"
            // Liquid Glass が背後の画面を透かすため、無地のバッキングウィンドウを敷いて
            // 撮影結果のトーンを安定させる
            let backing = makeBackingWindow(dark: dark)

            let panel = renderPanel(japanese: isJapanese, dark: dark)
            write(panel, to: outDir.appendingPathComponent("panel-\(lang)-\(style).png"))
            write(
                composeMarketing(
                    content: panel,
                    contentWidth: 440,
                    headline: isJapanese ? "クリップボード履歴を自動保存。" : "Automatically save clipboard history.",
                    subtitle: isJapanese
                        ? "テキスト、画像、コードなど、いつでも呼び出せます。"
                        : "Text, images, code, and more—you can access them anytime.",
                    dark: dark
                ),
                to: outDir.appendingPathComponent("marketing-history-\(lang)-\(style).png")
            )

            let collection = renderCollection(japanese: isJapanese, dark: dark)
            write(
                composeMarketing(
                    content: collection,
                    contentWidth: 860,
                    headline: isJapanese ? "お気に入りをフォルダで整理。" : "Organize favorites into folders.",
                    subtitle: isJapanese
                        ? "定型文やよく使うテキストを、コレクションでまとめて管理。"
                        : "Keep templates and frequently used text together in your collection.",
                    dark: dark
                ),
                to: outDir.appendingPathComponent("marketing-collection-\(lang)-\(style).png")
            )

            backing.orderOut(nil)
        }

        print("SCREENSHOTS_DIR: \(outDir.path)")
        return true
    }

    // MARK: - Panel Rendering

    private static func renderPanel(japanese: Bool, dark: Bool) -> NSImage {
        let demo = demoData(japanese: japanese)
        let manager = ClipboardManager(previewItems: demo.items, previewFolders: demo.folders)
        let hosting = NSHostingView(rootView: PopupContentView(
            clipboardManager: manager,
            onDismiss: {},
            onPaste: {}
        ))

        let window = KeyableWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 420, height: 560)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.contentView = hosting
        centerOnScreen(window)
        window.makeKeyAndOrderFront(nil)

        pumpRunLoop(seconds: 0.8)
        // PreferenceKey ベースで確定した内容高さにウィンドウを合わせる
        let height = min(max(hosting.fittingSize.height, 200), 560)
        window.setContentSize(NSSize(width: 420, height: height))
        pumpRunLoop(seconds: 0.4)

        let image = captureWindow(window)
        window.orderOut(nil)
        return image
    }

    // MARK: - Collection Rendering

    private static func renderCollection(japanese: Bool, dark: Bool) -> NSImage {
        let demo = demoData(japanese: japanese)
        let manager = ClipboardManager(previewItems: demo.items, previewFolders: demo.folders)

        // 実アプリと同じく NSWindow(contentViewController:) で構築する
        let controller = NSHostingController(rootView: FavoriteManagerView(
            clipboardManager: manager,
            initialItemId: demo.collectionItemId
        ))
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .resizable]
        window.title = japanese ? "コレクション" : "Collection"
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.setContentSize(NSSize(width: 1040, height: 640))
        centerOnScreen(window)
        window.makeKeyAndOrderFront(nil)
        // 信号機ボタンをアクティブ色で撮るため、アプリのアクティブ化を粘る
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeMain()

        // initialItemId の選択反映（onAppear → 0.05 秒遅延）を待ってから撮る
        pumpRunLoop(seconds: 1.5)

        let image = captureWindow(window)
        window.orderOut(nil)
        return image
    }

    // MARK: - On-screen Capture (ScreenCaptureKit)

    private final class KeyableWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { true }
    }

    private static func centerOnScreen(_ window: NSWindow) {
        guard let screen = NSScreen.main else { return }
        let frame = window.frame
        window.setFrameOrigin(NSPoint(
            x: screen.visibleFrame.midX - frame.width / 2,
            y: screen.visibleFrame.midY - frame.height / 2
        ))
    }

    /// 撮影トーン安定用の無地ウィンドウ（対象ウィンドウの背後に敷く）
    private static func makeBackingWindow(dark: Bool) -> NSWindow {
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1200)
        let window = NSWindow(contentRect: screen, styleMask: [.borderless], backing: .buffered, defer: false)
        window.backgroundColor = dark
            ? NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
            : NSColor(calibratedWhite: 0.93, alpha: 1)
        window.level = .normal
        window.ignoresMouseEvents = true
        window.orderFront(nil)
        return window
    }

    /// 画面上のウィンドウを ScreenCaptureKit で撮影する（Liquid Glass 込み）
    private static func captureWindow(_ window: NSWindow) -> NSImage {
        let windowID = CGWindowID(window.windowNumber)
        let scale = window.backingScaleFactor
        let size = window.frame.size

        var captured: CGImage?
        var failure: String?
        var done = false

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
                    failure = "window \(windowID) not found in shareable content"
                    done = true
                    return
                }
                let filter = SCContentFilter(desktopIndependentWindow: scWindow)
                let config = SCStreamConfiguration()
                config.width = Int(size.width * scale)
                config.height = Int(size.height * scale)
                config.backgroundColor = .clear
                config.ignoreShadowsSingleWindow = true
                config.showsCursor = false
                config.captureResolution = .best
                captured = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            } catch {
                failure = String(describing: error)
            }
            done = true
        }
        while !done {
            pumpRunLoop(seconds: 0.05)
        }

        guard let cgImage = captured else {
            fatalError("Failed to capture window: \(failure ?? "unknown")")
        }
        // ポイントサイズを維持した 2x 画像として包む
        return NSImage(cgImage: cgImage, size: size)
    }

    /// ランループを回しつつ NSApp のイベントも処理する（アクティブ化・
    /// キーウィンドウ化のハンドシェイクは run() なしでは進まないため）
    private static func pumpRunLoop(seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if let event = NSApp.nextEvent(
                matching: .any,
                until: Date().addingTimeInterval(0.02),
                inMode: .default,
                dequeue: true
            ) {
                NSApp.sendEvent(event)
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }

    // MARK: - Marketing Composition (2560×1600 = 1280×800 @2x)

    private static func composeMarketing(
        content: NSImage,
        contentWidth: CGFloat,
        headline: String,
        subtitle: String,
        dark: Bool
    ) -> NSImage {
        let view = MarketingShotView(
            content: content,
            contentWidth: contentWidth,
            headline: headline,
            subtitle: subtitle,
            dark: dark
        )
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage else {
            fatalError("Failed to render marketing image")
        }
        return image
    }

    private struct MarketingShotView: View {
        let content: NSImage
        let contentWidth: CGFloat
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
                Image(nsImage: content)
                    .resizable()
                    .scaledToFit()
                    .frame(width: contentWidth)
                    .shadow(color: .black.opacity(dark ? 0.6 : 0.22), radius: 28, y: 14)
                    .padding(.top, 24)
            }
            .padding(.top, 72)
            .frame(width: 1280, height: 800, alignment: .top)
            .background(dark ? Color(red: 0.11, green: 0.11, blue: 0.12) : Color.white)
        }
    }

    // MARK: - Demo Data

    private struct DemoData {
        let items: [ClipboardItem]
        let folders: [FavoriteFolder]
        /// コレクション画面で選択状態にするアイテム
        let collectionItemId: UUID
    }

    private static func demoData(japanese: Bool) -> DemoData {
        let templates = FavoriteFolder(name: japanese ? "定型文" : "Templates", order: 0)
        let work = FavoriteFolder(name: japanese ? "仕事" : "Work", order: 1)

        var order = 0
        func item(
            _ category: ClipboardContentCategory,
            _ preview: String,
            size: Int? = nil,
            thumbnail: Data? = nil,
            favorite: String? = nil,
            folder: FavoriteFolder? = nil
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
                item(.image, "画像 1,024×640", size: 482_304, thumbnail: demoThumbnail()),
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
                item(.image, "Image 1,024×640", size: 482_304, thumbnail: demoThumbnail()),
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

        return DemoData(
            items: items,
            folders: [templates, work],
            collectionItemId: emailTemplate.id
        )
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
