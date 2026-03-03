import SwiftUI

struct PopupContentView: View {
    var clipboardManager: ClipboardManager
    var onDismiss: () -> Void
    var onPaste: () -> Void

    @State private var searchText = ""
    @State private var selectedIndex = 0
    @State private var hoveredIndex: Int?
    @State private var selectedCategory: ClipboardContentCategory?
    @State private var listContentHeight: CGFloat = 0
    @FocusState private var isSearchFocused: Bool

    private var filteredItems: [ClipboardItem] {
        var result = clipboardManager.items
        if let category = selectedCategory {
            result = result.filter { $0.category == category }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.previewText.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($isSearchFocused)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial)

            Divider()

            // Category filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    FilterChip(
                        label: String(localized: "All"),
                        icon: "tray.full",
                        isSelected: selectedCategory == nil,
                        color: .accentColor
                    ) {
                        selectedCategory = nil
                    }

                    ForEach(activeCategories, id: \.self) { category in
                        FilterChip(
                            label: category.label,
                            icon: category.icon,
                            isSelected: selectedCategory == category,
                            color: category.color
                        ) {
                            selectedCategory = selectedCategory == category ? nil : category
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            Divider()

            // History list
            if filteredItems.isEmpty {
                ContentUnavailableView {
                    Label("No History", systemImage: "clipboard")
                } description: {
                    if searchText.isEmpty {
                        Text("Copied content will appear here")
                    } else {
                        Text("No results found")
                    }
                }
                .frame(height: 120)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                                PopupItemRow(
                                    item: item,
                                    index: index,
                                    isSelected: index == selectedIndex,
                                    isHovered: index == hoveredIndex
                                )
                                .id(item.id)
                                .onHover { hovering in
                                    hoveredIndex = hovering ? index : nil
                                }
                                .onTapGesture {
                                    selectedIndex = index
                                    hoveredIndex = nil
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                                        selectAndPaste(item: item)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .background(GeometryReader { geo in
                            Color.clear.preference(key: ListContentHeightKey.self, value: geo.size.height)
                        })
                    }
                    .frame(height: min(listContentHeight, 450))
                    .onPreferenceChange(ListContentHeightKey.self) { newHeight in
                        DispatchQueue.main.async { listContentHeight = newHeight }
                    }
                    .onChange(of: selectedIndex) { _, newValue in
                        if let item = filteredItems[safe: newValue] {
                            withAnimation(.easeOut(duration: 0.1)) {
                                proxy.scrollTo(item.id, anchor: .center)
                            }
                        }
                    }
                }
            }

            Divider()

            // Footer
            HStack {
                Text("\(filteredItems.count) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("↩ Paste")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("⇧↩ Plain Text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onKeyPress(keys: [.upArrow, .downArrow, .return, .escape]) { press in
            handleKeyPress(press)
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "np")) { press in
            handleEmacsKey(press)
        }
        .onKeyPress(characters: .decimalDigits) { press in
            handleNumberKey(press)
        }
        .task {
            try? await Task.sleep(for: .milliseconds(100))
            isSearchFocused = true
        }
        .onChange(of: searchText) { _, _ in
            selectedIndex = 0
        }
    }

    private var activeCategories: [ClipboardContentCategory] {
        let present = Set(clipboardManager.items.map(\.category))
        return ClipboardContentCategory.allCases.filter { present.contains($0) }
    }

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .upArrow:
            if selectedIndex > 0 {
                selectedIndex -= 1
            }
            return .handled
        case .downArrow:
            if selectedIndex < filteredItems.count - 1 {
                selectedIndex += 1
            }
            return .handled
        case .return:
            if let item = filteredItems[safe: selectedIndex] {
                selectAndPaste(item: item, asPlainText: press.modifiers.contains(.shift))
            }
            return .handled
        case .escape:
            onDismiss()
            return .handled
        default:
            return .ignored
        }
    }

    private func handleEmacsKey(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.contains(.control) else { return .ignored }
        switch press.characters {
        case "n":
            if selectedIndex < filteredItems.count - 1 {
                selectedIndex += 1
            }
            return .handled
        case "p":
            if selectedIndex > 0 {
                selectedIndex -= 1
            }
            return .handled
        default:
            return .ignored
        }
    }

    private func handleNumberKey(_ press: KeyPress) -> KeyPress.Result {
        guard let char = press.characters.first,
              let num = Int(String(char)),
              num >= 1, num <= 9 else {
            return .ignored
        }
        let index = num - 1
        if let item = filteredItems[safe: index] {
            selectAndPaste(item: item)
            return .handled
        }
        return .ignored
    }

    private func selectAndPaste(item: ClipboardItem, asPlainText: Bool = false) {
        clipboardManager.restoreToClipboard(item, asPlainText: asPlainText)
        onPaste()
    }
}

// MARK: - Subviews

private struct FilterChip: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(label)
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isSelected ? color.opacity(0.2) : Color.clear)
            .foregroundStyle(isSelected ? color : .secondary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? color.opacity(0.5) : Color.secondary.opacity(0.3), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct PopupItemRow: View {
    let item: ClipboardItem
    let index: Int
    let isSelected: Bool
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Number badge (1-9)
            if index < 9 {
                Text("\(index + 1)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            } else {
                Spacer().frame(width: 16)
            }

            // Category icon
            Image(systemName: item.category.icon)
                .font(.caption)
                .foregroundStyle(item.category.color)
                .frame(width: 16)

            // Thumbnail or preview text
            if let thumbnailData = item.thumbnailData,
               let nsImage = NSImage(data: thumbnailData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Text(item.previewText)
                .font(.system(size: 12))
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Data size
            Text(item.formattedDataSize)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.15) : isHovered ? Color.primary.opacity(0.06) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }
}

private struct ListContentHeightKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
