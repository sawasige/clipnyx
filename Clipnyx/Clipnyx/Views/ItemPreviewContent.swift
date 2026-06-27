import SwiftUI

/// アイテムのアイコン表示（パネルとコレクションで共有）。
/// コピー元アプリがあれば、そのアプリアイコンを主役に大きく表示し、種別を表す
/// SF Symbol を左下に小バッジで重ねる（Mission Control 風）。シンボルは小さくても
/// 潰れないが実アプリアイコンは小さいと読めないため、この役割分担にしている。
/// 元アプリが不明なアイテムは従来どおり種別シンボル単体。お気に入りは右下バッジ。
struct ItemCategoryBadge: View {
    let item: ClipboardItem

    private let iconSize: CGFloat = 20

    var body: some View {
        content
            .frame(width: iconSize, height: iconSize)
            .overlay(alignment: .bottomTrailing) {
                if item.isSaved {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(item.isFavoriteItem ? Color.accentColor : .orange)
                        .offset(x: 4, y: 3)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let bundleId = item.sourceBundleId,
           let appIcon = SourceAppResolver.icon(for: bundleId) {
            Image(nsImage: appIcon)
                .resizable()
                .clipShape(RoundedRectangle(cornerRadius: 4.5))
                .overlay(alignment: .bottomLeading) { categorySymbolBadge.offset(x: -4, y: 4) }
                .help(SourceAppResolver.name(for: bundleId))
        } else {
            // 元アプリ不明: 種別シンボルのみ（中央寄せで幅を揃える）
            Image(systemName: item.category.icon)
                .font(.callout)
                .foregroundStyle(item.category.color)
        }
    }

    /// 種別を表す SF Symbol の小バッジ（アプリアイコンに重ねるため背景でくり抜く）
    private var categorySymbolBadge: some View {
        Image(systemName: item.category.icon)
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(item.category.color)
            .frame(width: 13, height: 13)
            .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
    }
}

/// サムネイル PNG のデコード結果をキャッシュする。body 再評価のたびに
/// NSImage(data:) で再デコードするとスクロールが重くなるため、item.id 単位で1回だけ。
@MainActor
enum ThumbnailCache {
    private static let cache = NSCache<NSUUID, NSImage>()

    static func image(for item: ClipboardItem) -> NSImage? {
        guard let data = item.thumbnailData else { return nil }
        let key = item.id as NSUUID
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

struct ItemPreviewContent: View {
    let item: ClipboardItem
    var maxThumbnailHeight: CGFloat = 40

    var body: some View {
        switch item.category {
        case .color:
            colorPreview
        case .url:
            urlPreview
        case .image, .pdf:
            imagePreview
        case .sourceCode:
            sourceCodePreview
        default:
            defaultPreview
        }
    }

    // MARK: - Color

    private var colorPreview: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(hex: item.previewText))
                .frame(width: 16, height: 16)
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5)
                )
            Text(item.previewText)
                .font(.body.monospaced())
                .lineLimit(1)
        }
    }

    // MARK: - URL

    private var urlPreview: some View {
        Text(item.previewText)
            .font(.body)
            .foregroundStyle(.cyan)
            .lineLimit(2)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Image / PDF

    private var imagePreview: some View {
        HStack(spacing: 6) {
            if let nsImage = ThumbnailCache.image(for: item) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: maxThumbnailHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            Text(item.previewText)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Source Code

    private var sourceCodePreview: some View {
        Text(item.previewText)
            .font(.body.monospaced())
            .lineLimit(2)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    // MARK: - Default

    private var defaultPreview: some View {
        HStack(spacing: 6) {
            if let nsImage = ThumbnailCache.image(for: item) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: maxThumbnailHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            Text(item.previewText)
                .font(.body)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
