import SwiftUI

struct PopupContentView: View {
    var clipboardManager: ClipboardManager
    var isMenuBar: Bool
    var onDismiss: () -> Void
    var onPaste: () -> Void

    @State private var searchText = ""
    @State private var selectedIndex = 0
    @State private var hoveredIndex: Int?
    @State private var selectedCategory: ClipboardContentCategory?
    @State private var showPinnedOnly = false
    @State private var listContentHeight: CGFloat = 0
    @State private var detailItem: ClipboardItem?
    @FocusState private var isSearchFocused: Bool

    private var filteredItems: [ClipboardItem] {
        var result = clipboardManager.items
        if showPinnedOnly {
            result = result.filter(\.isPinned)
        }
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
                    .font(.system(size: isMenuBar ? 13 : 14))
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

                // Pin filter
                Button {
                    showPinnedOnly.toggle()
                    selectedIndex = 0
                } label: {
                    Image(systemName: showPinnedOnly ? "pin.fill" : "pin")
                        .foregroundStyle(showPinnedOnly ? .orange : .secondary)
                }
                .buttonStyle(.plain)
                .help(showPinnedOnly ? Text("Show All") : Text("Pinned Only"))

                // Category filter
                Menu {
                    Button {
                        selectedCategory = nil
                    } label: {
                        Label(String(localized: "All"), systemImage: "tray.full")
                    }
                    Divider()
                    ForEach(activeCategories, id: \.self) { category in
                        Button {
                            selectedCategory = selectedCategory == category ? nil : category
                        } label: {
                            Label(category.label, systemImage: category.icon)
                        }
                    }
                } label: {
                    Image(systemName: selectedCategory != nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .foregroundStyle(selectedCategory != nil ? Color.accentColor : Color.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Filter")

                if isMenuBar {
                    // Pause toggle
                    Button {
                        clipboardManager.isPaused.toggle()
                    } label: {
                        Image(systemName: clipboardManager.isPaused ? "play.fill" : "pause.fill")
                            .contentTransition(.symbolEffect(.replace))
                            .foregroundStyle(clipboardManager.isPaused ? .orange : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(clipboardManager.isPaused ? Text("Resume Monitoring") : Text("Pause Monitoring"))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            historyContent

            if isMenuBar {
                Divider()

                // Footer
                HStack(spacing: 12) {
                    Text("\(clipboardManager.items.count) items")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(verbatim: "·")
                        .foregroundStyle(.quaternary)
                    Text(clipboardManager.formattedTotalSize)
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Spacer()

                    FooterIconButton(icon: "trash", color: .red) {
                        clipboardManager.removeAllItems()
                    }
                    .help("Delete All")

                    FooterIconButton(icon: "gearshape", color: .secondary) {
                        NotificationCenter.default.post(name: .openSettingsRequest, object: nil)
                    }
                    .help("Settings")

                    FooterIconButton(icon: "power", color: .red) {
                        NSApplication.shared.terminate(nil)
                    }
                    .help("Quit")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
            ItemDetailView(item: item)
        }
    }

    // MARK: - History Content

    @ViewBuilder
    private var historyContent: some View {
        if filteredItems.isEmpty {
            ContentUnavailableView {
                Label(showPinnedOnly ? "No Pinned Items" : "No History", systemImage: showPinnedOnly ? "pin.slash" : "clipboard")
            } description: {
                if showPinnedOnly {
                    Text("Pin items to keep them here")
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
                    LazyVStack(spacing: 2) {
                        ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                            itemRow(item: item, index: index)
                        }
                    }
                    .padding(.vertical, 4)
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: ListContentHeightKey.self, value: geo.size.height)
                    })
                }
                .modifier(ScrollHeightModifier(isMenuBar: isMenuBar, contentHeight: listContentHeight))
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
    }

    @ViewBuilder
    private func itemRow(item: ClipboardItem, index: Int) -> some View {
        UnifiedItemRow(
            item: item,
            index: isMenuBar ? nil : index,
            isSelected: !isMenuBar && index == selectedIndex,
            isHovered: index == hoveredIndex,
            isMenuBar: isMenuBar,
            onPin: {
                clipboardManager.togglePin(item)
            },
            onSelect: {
                if isMenuBar {
                    clipboardManager.restoreToClipboard(item)
                } else {
                    selectedIndex = index
                    hoveredIndex = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        selectAndPaste(item: item)
                    }
                }
            },
            onShowDetail: isMenuBar ? { detailItem = item } : nil,
            onDelete: {
                clipboardManager.removeItem(item)
            },
            onPastePlainText: isMenuBar ? {
                clipboardManager.restoreToClipboard(item, asPlainText: true)
            } : nil
        )
        .id(item.id)
        .onHover { hovering in
            hoveredIndex = hovering ? index : nil
        }
    }

    private var activeCategories: [ClipboardContentCategory] {
        let present = Set(clipboardManager.items.map(\.category))
        return ClipboardContentCategory.allCases.filter { present.contains($0) }
    }

    // MARK: - Key Handling

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        if press.key == .tab {
            showPinnedOnly.toggle()
            selectedIndex = 0
            return .handled
        }
        if press.key == .escape {
            onDismiss()
            return .handled
        }

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

// MARK: - Unified Item Row

private struct UnifiedItemRow: View {
    let item: ClipboardItem
    let index: Int?
    let isSelected: Bool
    let isHovered: Bool
    let isMenuBar: Bool
    let onPin: () -> Void
    let onSelect: () -> Void
    let onShowDetail: (() -> Void)?
    let onDelete: () -> Void
    let onPastePlainText: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            // Number badge (1-9) for popup mode
            if let index, !isMenuBar {
                if index < 9 {
                    Text("\(index + 1)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                } else {
                    Spacer().frame(width: 16)
                }
            }

            // Category icon (with pin overlay)
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: item.category.icon)
                    .font(.callout)
                    .foregroundStyle(item.category.color)
                    .frame(width: 18)

                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(.orange)
                        .offset(x: 4, y: 2)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                ItemPreviewContent(item: item, maxThumbnailHeight: isMenuBar ? 36 : 40)
                if isMenuBar {
                    Text(item.timestamp, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isHovered {
                // ピンボタン
                Button {
                    onPin()
                } label: {
                    Image(systemName: item.isPinned ? "pin.slash" : "pin")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(item.isPinned ? .orange : .secondary)

                if let onShowDetail {
                    Button {
                        onShowDetail()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.callout)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            } else {
                Text(item.formattedDataSize)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.15) : isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            Button {
                onSelect()
            } label: {
                Text(isMenuBar ? "Copy" : "Paste")
            }
            if let onPastePlainText {
                Button {
                    onPastePlainText()
                } label: {
                    Label("Paste as Plain Text", systemImage: "doc.plaintext")
                }
            }
            Divider()
            Button {
                onPin()
            } label: {
                Label(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin")
            }
            if let onShowDetail {
                Button {
                    onShowDetail()
                } label: {
                    Label("Detail", systemImage: "info.circle")
                }
            }
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Footer

private struct FooterIconButton: View {
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            FooterIconLabel(icon: icon, color: color)
        }
        .buttonStyle(.plain)
    }
}

private struct FooterIconLabel: View {
    let icon: String
    let color: Color

    @State private var isHovered = false

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 14))
            .foregroundStyle(isHovered ? color : .secondary)
            .frame(width: 28, height: 28)
            .background(isHovered ? color.opacity(0.1) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .onHover { isHovered = $0 }
    }
}

/// メニューバーは maxHeight でスクロール可能にし、
/// ポップアップパネルはコンテンツ高さに合わせて縮む。
private struct ScrollHeightModifier: ViewModifier {
    let isMenuBar: Bool
    let contentHeight: CGFloat

    func body(content: Content) -> some View {
        if isMenuBar {
            content.frame(maxHeight: 450)
        } else {
            content.frame(height: min(contentHeight, 450))
        }
    }
}

private struct ListContentHeightKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
