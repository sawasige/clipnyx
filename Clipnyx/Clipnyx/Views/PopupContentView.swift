import SwiftUI

struct PopupContentView: View {
    var clipboardManager: ClipboardManager
    var onDismiss: () -> Void
    var onPaste: () -> Void

    @State private var searchText = ""
    @State private var selectedIndex = 0
    @State private var keyboardNavigation = true
    @State private var lastScreenPosition: CGPoint?
    @State private var selectedCategory: ClipboardContentCategory?
    @State private var selectedSnippetCategory: UUID?
    @State private var showSavedOnly = false
    @State private var listContentHeight: CGFloat = 0
    @State private var detailItem: ClipboardItem?
    @FocusState private var isSearchFocused: Bool

    private var filteredItems: [ClipboardItem] {
        var result = clipboardManager.items
        if showSavedOnly {
            result = result.filter(\.isSaved)
        }
        if let snippetCategoryId = selectedSnippetCategory {
            result = result.filter { $0.snippetCategoryId == snippetCategoryId }
        } else if let category = selectedCategory {
            result = result.filter { $0.category == category }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.previewText.localizedCaseInsensitiveContains(searchText)
                || ($0.snippetName?.localizedCaseInsensitiveContains(searchText) ?? false)
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

                // Saved filter
                Button {
                    showSavedOnly.toggle()
                    selectedIndex = 0
                } label: {
                    Image(systemName: showSavedOnly ? "bookmark.fill" : "bookmark")
                        .foregroundStyle(showSavedOnly ? .orange : .secondary)
                }
                .buttonStyle(.plain)
                .help(showSavedOnly ? Text("Show All") : Text("Saved Only"))

                // Category filter
                Menu {
                    Button {
                        selectedCategory = nil
                        selectedSnippetCategory = nil
                    } label: {
                        Label(String(localized: "All"), systemImage: "tray.full")
                    }
                    Divider()
                    ForEach(activeCategories, id: \.self) { category in
                        Button {
                            if selectedCategory == category {
                                selectedCategory = nil
                            } else {
                                selectedCategory = category
                                selectedSnippetCategory = nil
                            }
                        } label: {
                            Label(category.label, systemImage: category.icon)
                        }
                    }
                    if !clipboardManager.snippetCategories.isEmpty {
                        Divider()
                        ForEach(clipboardManager.snippetCategories.sorted(by: { $0.order < $1.order })) { cat in
                            Button {
                                if selectedSnippetCategory == cat.id {
                                    selectedSnippetCategory = nil
                                } else {
                                    selectedSnippetCategory = cat.id
                                    selectedCategory = nil
                                }
                            } label: {
                                Label(cat.name, systemImage: "tag")
                            }
                        }
                    }
                } label: {
                    Image(systemName: (selectedCategory != nil || selectedSnippetCategory != nil) ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .foregroundStyle((selectedCategory != nil || selectedSnippetCategory != nil) ? Color.accentColor : Color.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Filter")

                // New snippet
                Button {
                    NotificationCenter.default.post(name: .openSnippetEditor, object: nil)
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("New Snippet")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            historyContent
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onContinuousHover { phase in
            if case .active = phase {
                let screenPos = NSEvent.mouseLocation
                if let last = lastScreenPosition {
                    let dx = abs(screenPos.x - last.x)
                    let dy = abs(screenPos.y - last.y)
                    if dx > 1 || dy > 1 {
                        keyboardNavigation = false
                        lastScreenPosition = screenPos
                    }
                } else {
                    lastScreenPosition = screenPos
                }
            }
        }
        .onKeyPress(keys: [.upArrow, .downArrow, .return, .escape, .tab]) { press in
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
        .popover(item: $detailItem) { item in
            ItemDetailView(item: item, clipboardManager: clipboardManager)
        }
    }

    // MARK: - History Content

    @ViewBuilder
    private var historyContent: some View {
        if filteredItems.isEmpty {
            ContentUnavailableView {
                Label(showSavedOnly ? "No Saved Items" : "No History", systemImage: showSavedOnly ? "bookmark.slash" : "clipboard")
            } description: {
                if showSavedOnly {
                    Text("Save items to keep them here")
                } else if searchText.isEmpty {
                    Text("Copied content will appear here")
                } else {
                    Text("No results found")
                }
            }
            .frame(height: 120)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                            itemRow(item: item, index: index)
                        }
                    }
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: ListContentHeightKey.self, value: geo.size.height)
                    })
                    .padding(.vertical, 4)
                }
                .frame(height: min(listContentHeight, 450))
                .onPreferenceChange(ListContentHeightKey.self) { newHeight in
                    listContentHeight = newHeight
                }
                .onChange(of: selectedIndex) { _, newValue in
                    if keyboardNavigation, let item = filteredItems[safe: newValue] {
                        proxy.scrollTo(item.id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func itemRow(item: ClipboardItem, index: Int) -> some View {
        UnifiedItemRow(
            item: item,
            index: index,
            isSelected: index == selectedIndex,
            onBookmark: {
                clipboardManager.toggleSave(item)
            },
            onSelect: {
                selectedIndex = index
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    selectAndPaste(item: item)
                }
            },
            onShowDetail: { detailItem = item },
            onDelete: {
                clipboardManager.removeItem(item)
            },
            onPastePlainText: {
                selectAndPaste(item: item, asPlainText: true)
            }
        )
        .id(item.id)
        .onHover { hovering in
            if hovering, !keyboardNavigation {
                selectedIndex = index
            }
        }
    }

    private var activeCategories: [ClipboardContentCategory] {
        let present = Set(clipboardManager.items.map(\.category))
        return ClipboardContentCategory.allCases.filter { present.contains($0) }
    }

    // MARK: - Key Handling

    private var isIMEComposing: Bool {
        guard let inputContext = NSTextInputContext.current else { return false }
        return inputContext.client.markedRange().length > 0
    }

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        if press.key == .tab {
            showSavedOnly.toggle()
            selectedIndex = 0
            return .handled
        }
        if isIMEComposing { return .ignored }
        if press.key == .escape {
            onDismiss()
            return .handled
        }

        switch press.key {
        case .upArrow:
            if selectedIndex > 0 {
                keyboardNavigation = true
                selectedIndex -= 1
            }
            return .handled
        case .downArrow:
            if selectedIndex < filteredItems.count - 1 {
                keyboardNavigation = true
                selectedIndex += 1
            }
            return .handled
        case .return:
            if let item = filteredItems[safe: selectedIndex] {
                selectAndPaste(item: item, asPlainText: press.modifiers.contains(.shift))
            }
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
                keyboardNavigation = true
                selectedIndex += 1
            }
            return .handled
        case "p":
            if selectedIndex > 0 {
                keyboardNavigation = true
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

// MARK: - Unified Item Row

private struct UnifiedItemRow: View {
    let item: ClipboardItem
    let index: Int
    let isSelected: Bool
    let onBookmark: () -> Void
    let onSelect: () -> Void
    let onShowDetail: () -> Void
    let onDelete: () -> Void
    let onPastePlainText: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Number badge (1-9)
            if index < 9 {
                Text("\(index + 1)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            } else {
                Spacer().frame(width: 16)
            }

            // Category icon (with saved overlay)
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: item.category.icon)
                    .font(.callout)
                    .foregroundStyle(item.category.color)
                    .frame(width: 18)

                if item.isSaved {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(item.isSnippet ? Color.accentColor : .orange)
                        .offset(x: 4, y: 2)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                if let snippetName = item.snippetName {
                    Text(snippetName)
                        .font(.callout.bold())
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                }
                ItemPreviewContent(item: item, maxThumbnailHeight: 40)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ZStack {
                if isSelected {
                    HStack(spacing: 4) {
                        ActionButton(icon: item.isSaved ? "bookmark.fill" : "bookmark", color: item.isSaved ? .orange : .secondary, action: onBookmark)
                        ActionButton(icon: "info.circle", color: .secondary, action: onShowDetail)
                        ActionButton(icon: "trash", color: .red, action: onDelete)
                    }
                } else {
                    Text(item.formattedDataSize)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 84, height: 24, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            Button {
                onSelect()
            } label: {
                Text("Paste")
            }
            Button {
                onPastePlainText()
            } label: {
                Label("Paste as Plain Text", systemImage: "doc.plaintext")
            }
            Divider()
            Button {
                onBookmark()
            } label: {
                Label(item.isSaved ? "Unsave" : "Save", systemImage: item.isSaved ? "bookmark.slash" : "bookmark")
            }
            Button {
                onShowDetail()
            } label: {
                Label("Detail", systemImage: "info.circle")
            }
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

private struct ActionButton: View {
    let icon: String
    let color: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(isHovered ? color : .secondary)
                .frame(width: 24, height: 24)
                .background(isHovered ? color.opacity(0.12) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct ListContentHeightKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
