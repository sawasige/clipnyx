import SwiftUI

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
            if let thumbnailData = item.thumbnailData,
               let nsImage = NSImage(data: thumbnailData) {
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
            if let thumbnailData = item.thumbnailData,
               let nsImage = NSImage(data: thumbnailData) {
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
