import SwiftUI

struct ItemDetailView: View {
    let item: ClipboardItem
    var clipboardManager: ClipboardManager? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: item.category.icon)
                    .foregroundStyle(item.category.color)
                Text(item.category.label)
                    .font(.headline)
                Spacer()
            }

            if let snippetName = item.snippetName {
                LabeledContent("Snippet") {
                    Text(snippetName)
                }
                if let categoryId = item.snippetCategoryId,
                   let category = clipboardManager?.snippetCategories.first(where: { $0.id == categoryId }) {
                    LabeledContent("Snippet Category") {
                        Text(category.name)
                    }
                }
            }

            Divider()

            // Details
            LabeledContent("Category") {
                Label(item.category.label, systemImage: item.category.icon)
                    .foregroundStyle(item.category.color)
            }

            LabeledContent("Copied At") {
                Text(item.timestamp, format: .dateTime
                    .year().month().day()
                    .hour().minute().second()
                )
            }

            LabeledContent("Data Size") {
                Text(item.formattedDataSize)
            }

            Divider()

            // Preview
            Text("Preview")
                .font(.subheadline.bold())

            if let thumbnailData = item.thumbnailData,
               let nsImage = NSImage(data: thumbnailData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Text(item.previewText)
                .font(.system(size: 12))
                .lineLimit(10)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Divider()

            // Data types
            Text("Data Types")
                .font(.subheadline.bold())

            ForEach(item.representationInfos, id: \.type) { info in
                HStack {
                    Text(info.type)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer()
                    Text(formatBytes(info.size))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if item.isSaved {
                Divider()
                Button {
                    NotificationCenter.default.post(name: .openSnippetEditor, object: item)
                } label: {
                    Label("Edit Snippet", systemImage: "pencil")
                }
                .buttonStyle(.link)
            }
        }
        .padding()
        .frame(width: 350)
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
        }
    }
}
