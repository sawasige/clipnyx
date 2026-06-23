import SwiftUI

struct FavoriteManagerView: View {
    var clipboardManager: ClipboardManager
    var initialItemId: UUID? = nil
    @State var selectedFolderFilter: FavoriteFilter = .allHistory
    @State var selectedItemIds: Set<UUID> = []
    @State private var newFolderName = ""
    @State private var renamingFolderId: UUID?
    @State private var renamingText = ""
    @State private var dropTargetFilter: FavoriteFilter?
    @State private var isConfirmingBulkDelete = false
    @FocusState private var isRenamingFocused: Bool
    @FocusState private var focusedArea: FocusArea?

    /// ドラッグペイロードの接頭辞（プレーンテキストとしての誤解釈を避けるため識別子を付ける）
    private static let dragPrefix = "clipnyx-item:"

    enum FocusArea: Hashable {
        case sidebar
        case detail
    }

    private var isShowingFavorites: Bool {
        selectedFolderFilter != .allHistory
    }

    private var filteredItems: [ClipboardItem] {
        selectedFolderFilter.apply(to: clipboardManager.items)
    }

    /// 単一選択時のみ、そのアイテムを返す
    private var selectedItem: ClipboardItem? {
        guard selectedItemIds.count == 1, let id = selectedItemIds.first else { return nil }
        return clipboardManager.items.first(where: { $0.id == id })
    }

    private var selectedItems: [ClipboardItem] {
        clipboardManager.items.filter { selectedItemIds.contains($0.id) }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            itemList
        } detail: {
            detailArea
        }
        .frame(minWidth: 800, minHeight: 500)
        .onAppear {
            if let initialItemId {
                selectItem(id: initialItemId)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectLibraryItem)) { notification in
            if let item = notification.object as? ClipboardItem {
                selectItem(id: item.id)
            }
        }
        .onChange(of: selectedFolderFilter) { _, _ in
            selectedItemIds = []
        }
    }

    private func selectItem(id: UUID) {
        // アイテムのフォルダに合わせてフィルタを切り替え
        if let item = clipboardManager.items.first(where: { $0.id == id }) {
            if let folderId = item.favoriteFolderId {
                selectedFolderFilter = .folder(folderId)
            } else if item.isSaved {
                selectedFolderFilter = .allSaved
            } else {
                selectedFolderFilter = .allHistory
            }
        }
        // onChangeでクリアされた後にセットする
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            selectedItemIds = [id]
        }
    }

    // MARK: - Drag & Drop

    /// ドロップされたペイロードを対象アイテム集合に解決する。
    /// 選択中の行をドラッグした場合は選択全体を対象にする
    private func droppedItemIds(_ payloads: [String]) -> Set<UUID> {
        var ids: Set<UUID> = []
        for payload in payloads where payload.hasPrefix(Self.dragPrefix) {
            if let id = UUID(uuidString: String(payload.dropFirst(Self.dragPrefix.count))) {
                ids.insert(id)
            }
        }
        if !ids.isDisjoint(with: selectedItemIds) {
            ids.formUnion(selectedItemIds)
        }
        return ids
    }

    /// サイドバー行をアイテムのドロップ先にする
    private func folderDropDestination<Content: View>(
        _ content: Content,
        filter: FavoriteFilter,
        folderId: UUID?
    ) -> some View {
        content
            .listRowBackground(
                dropTargetFilter == filter
                    ? Color.accentColor.opacity(0.25)
                    : Color.clear
            )
            .dropDestination(for: String.self) { payloads, _ in
                let ids = droppedItemIds(payloads)
                guard !ids.isEmpty else { return false }
                clipboardManager.moveItemsToFolder(itemIds: ids, folderId: folderId)
                return true
            } isTargeted: { targeting in
                if targeting {
                    dropTargetFilter = filter
                } else if dropTargetFilter == filter {
                    dropTargetFilter = nil
                }
            }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        sidebarList
            .listStyle(.sidebar)
            .focusable()
            .focused($focusedArea, equals: .sidebar)
            .onDeleteCommand {
                if case .folder(let id) = selectedFolderFilter {
                    clipboardManager.deleteFavoriteFolder(id: id)
                    selectedFolderFilter = .allHistory
                }
            }
            .onKeyPress(.return) {
                guard renamingFolderId == nil,
                      case .folder(let id) = selectedFolderFilter,
                      let folder = clipboardManager.favoriteFolders.first(where: { $0.id == id }) else {
                    return .ignored
                }
                renamingText = folder.name
                renamingFolderId = id
                return .handled
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    TextField("New Folder", text: $newFolderName)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        guard !newFolderName.isEmpty else { return }
                        _ = clipboardManager.addFavoriteFolder(name: newFolderName)
                        newFolderName = ""
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(newFolderName.isEmpty)
                }
                .padding(8)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
    }

    private var sidebarList: some View {
        List(selection: $selectedFolderFilter) {
            Label("All History", systemImage: "clock")
                .tag(FavoriteFilter.allHistory)

            Section("Favorites") {
                Label("All Favorites", systemImage: "bookmark.fill")
                    .tag(FavoriteFilter.allSaved)
                folderDropDestination(
                    Label("Uncategorized", systemImage: "tray")
                        .tag(FavoriteFilter.uncategorized),
                    filter: .uncategorized,
                    folderId: nil
                )
            }

            Section("Folders") {
                ForEach(clipboardManager.sortedFavoriteFolders) { folder in
                    if renamingFolderId == folder.id {
                        TextField("", text: $renamingText)
                        .onSubmit {
                            if !renamingText.isEmpty {
                                clipboardManager.renameFavoriteFolder(id: folder.id, name: renamingText)
                            }
                            renamingFolderId = nil
                            isRenamingFocused = false
                        }
                        .textFieldStyle(.roundedBorder)
                        .focused($isRenamingFocused)
                        .onAppear { isRenamingFocused = true }
                        .onExitCommand {
                            renamingFolderId = nil
                            isRenamingFocused = false
                        }
                    } else {
                        folderDropDestination(
                            Label(folder.name, systemImage: "folder")
                                .tag(FavoriteFilter.folder(folder.id))
                                .contextMenu {
                                    Button("Rename") {
                                        renamingText = folder.name
                                        renamingFolderId = folder.id
                                    }
                                    Button("Delete Folder", role: .destructive) {
                                        clipboardManager.deleteFavoriteFolder(id: folder.id)
                                    }
                                },
                            filter: .folder(folder.id),
                            folderId: folder.id
                        )
                    }
                }
                .onMove { from, to in
                    var sorted = clipboardManager.sortedFavoriteFolders
                    sorted.move(fromOffsets: from, toOffset: to)
                    for i in sorted.indices {
                        sorted[i].order = i
                    }
                    clipboardManager.reorderFavoriteFolders(sorted)
                }
                .onDelete { offsets in
                    let sorted = clipboardManager.sortedFavoriteFolders
                    for index in offsets {
                        clipboardManager.deleteFavoriteFolder(id: sorted[index].id)
                    }
                }
            }
        }
    }

    // MARK: - Item List

    private var itemList: some View {
        Group {
            if filteredItems.isEmpty {
                ContentUnavailableView {
                    Label(isShowingFavorites ? "No Favorites" : "No History",
                          systemImage: isShowingFavorites ? "bookmark.slash" : "clipboard")
                } description: {
                    Text(isShowingFavorites ? "Add to favorites to keep them here" : "Copied content will appear here")
                }
            } else {
                List(filteredItems, selection: $selectedItemIds) { item in
                    HStack(spacing: 8) {
                        ZStack(alignment: .bottomTrailing) {
                            Image(systemName: item.category.icon)
                                .font(.callout)
                                .foregroundStyle(item.category.color)
                                .frame(width: 18)

                            if item.isSaved {
                                Image(systemName: "bookmark.fill")
                                    .font(.system(size: 7))
                                    .foregroundStyle(item.isFavoriteItem ? Color.accentColor : .orange)
                                    .offset(x: 4, y: 2)
                            }
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            if let name = item.favoriteName, !name.isEmpty {
                                Text(name)
                                    .font(.callout.bold())
                                    .foregroundStyle(Color.accentColor)
                                    .lineLimit(1)
                            }
                            ItemPreviewContent(item: item, maxThumbnailHeight: 30)
                            if let folderId = item.favoriteFolderId,
                               let folder = clipboardManager.favoriteFolders.first(where: { $0.id == folderId }) {
                                Text(folder.name)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .frame(minHeight: 36)
                    .tag(item.id)
                    .draggable(Self.dragPrefix + item.id.uuidString)
                    .contextMenu {
                        itemContextMenu(for: item)
                    }
                }
                .onDeleteCommand {
                    guard !selectedItemIds.isEmpty else { return }
                    isConfirmingBulkDelete = true
                }
                .confirmationDialog(
                    "Delete \(selectedItemIds.count) items?",
                    isPresented: $isConfirmingBulkDelete
                ) {
                    Button("Delete", role: .destructive) {
                        clipboardManager.removeItems(itemIds: selectedItemIds)
                        selectedItemIds = []
                    }
                } message: {
                    Text("This cannot be undone.")
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        .toolbar {
            ToolbarItem {
                if isShowingFavorites {
                    Button {
                        let defaultFolderId: UUID? = {
                            if case .folder(let id) = selectedFolderFilter { return id }
                            return nil
                        }()
                        clipboardManager.createFavorite(text: "", name: "", folderId: defaultFolderId)
                        if let newItem = clipboardManager.items.first {
                            selectedItemIds = [newItem.id]
                        }
                    } label: {
                        Label("New Favorite", systemImage: "plus")
                    }
                } else {
                    Button {
                        clipboardManager.addTextToHistory(text: "")
                        if let newItem = clipboardManager.items.first {
                            selectedItemIds = [newItem.id]
                        }
                    } label: {
                        Label("Add Text", systemImage: "plus")
                    }
                }
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func itemContextMenu(for item: ClipboardItem) -> some View {
        // 選択中の行なら選択全体、そうでなければその行だけを対象にする
        let targets = selectedItemIds.contains(item.id) ? selectedItemIds : [item.id]
        let targetItems = clipboardManager.items.filter { targets.contains($0.id) }

        Menu {
            ForEach(clipboardManager.sortedFavoriteFolders) { folder in
                Button(folder.name) {
                    clipboardManager.moveItemsToFolder(itemIds: targets, folderId: folder.id)
                }
            }
            Divider()
            Button("Uncategorized") {
                clipboardManager.moveItemsToFolder(itemIds: targets, folderId: nil)
            }
        } label: {
            Label("Move to Folder", systemImage: "folder")
        }
        if targetItems.contains(where: { !$0.isSaved }) {
            Button {
                clipboardManager.favoriteItems(itemIds: targets)
            } label: {
                Label("Favorite", systemImage: "bookmark")
            }
        }
        if targetItems.contains(where: \.isSaved) {
            Button {
                clipboardManager.unfavoriteItems(itemIds: targets)
            } label: {
                Label("Unfavorite", systemImage: "bookmark.slash")
            }
        }
        Divider()
        Button(role: .destructive) {
            clipboardManager.removeItems(itemIds: targets)
            selectedItemIds.subtract(targets)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailArea: some View {
        if selectedItemIds.count > 1 {
            bulkActionView
        } else if let item = selectedItem {
            ItemDetailEditor(clipboardManager: clipboardManager, itemId: item.id)
                .id(item.id)
        } else {
            ContentUnavailableView {
                Label("No Selection", systemImage: "square.dashed")
            } description: {
                Text("Select an item to view")
            }
        }
    }

    // MARK: - Bulk Actions

    private var bulkActionView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("\(selectedItemIds.count) items selected")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 10) {
                Menu {
                    ForEach(clipboardManager.sortedFavoriteFolders) { folder in
                        Button(folder.name) {
                            clipboardManager.moveItemsToFolder(itemIds: selectedItemIds, folderId: folder.id)
                        }
                    }
                    Divider()
                    Button("Uncategorized") {
                        clipboardManager.moveItemsToFolder(itemIds: selectedItemIds, folderId: nil)
                    }
                } label: {
                    Label("Move to Folder", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }

                if selectedItems.contains(where: { !$0.isSaved }) {
                    Button {
                        clipboardManager.favoriteItems(itemIds: selectedItemIds)
                    } label: {
                        Label("Favorite", systemImage: "bookmark")
                            .frame(maxWidth: .infinity)
                    }
                }

                if selectedItems.contains(where: \.isSaved) {
                    Button {
                        clipboardManager.unfavoriteItems(itemIds: selectedItemIds)
                    } label: {
                        Label("Unfavorite", systemImage: "bookmark.slash")
                            .frame(maxWidth: .infinity)
                    }
                }

                if selectedItems.contains(where: \.canConvertToPlainText) {
                    Button {
                        clipboardManager.convertItemsToPlainText(itemIds: selectedItemIds)
                    } label: {
                        Label("Convert to Plain Text", systemImage: "doc.plaintext")
                            .frame(maxWidth: .infinity)
                    }
                }

                Button(role: .destructive) {
                    isConfirmingBulkDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: 220)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Unified Detail Editor

private struct ItemDetailEditor: View {
    var clipboardManager: ClipboardManager
    let itemId: UUID

    @State private var name: String = ""
    @State private var selectedFolderId: UUID?
    @State private var text: String = ""
    @State private var pendingContentSave: Task<Void, Never>?

    private var item: ClipboardItem? {
        clipboardManager.items.first(where: { $0.id == itemId })
    }

    private var isTextEditable: Bool {
        item?.category == .plainText
    }

    var body: some View {
        ScrollView {
            if let item {
                VStack(alignment: .leading, spacing: 12) {
                    // Header
                    HStack {
                        Image(systemName: item.category.icon)
                            .foregroundStyle(item.category.color)
                        Text(item.category.label)
                            .font(.headline)
                        Spacer()
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

                    // Favorite fields (only when saved)
                    if item.isSaved {
                        Divider()

                        LabeledContent("Favorite Name") {
                            TextField("", text: $name)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: name) { _, newValue in
                                    clipboardManager.updateFavoriteName(item, name: newValue)
                                }
                        }

                        LabeledContent("Folder") {
                            Picker("", selection: $selectedFolderId) {
                                Text("None").tag(UUID?.none)
                                ForEach(clipboardManager.sortedFavoriteFolders) { folder in
                                    Text(folder.name).tag(UUID?.some(folder.id))
                                }
                            }
                            .labelsHidden()
                            .onChange(of: selectedFolderId) { _, newValue in
                                clipboardManager.updateFavoriteFolder(item, folderId: newValue)
                            }
                        }
                    }

                    Divider()

                    // Content / Preview
                    if isTextEditable {
                        TextEditor(text: $text)
                            .font(.system(size: 13, design: .monospaced))
                            .frame(minHeight: 200)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color(nsColor: .separatorColor))
                            )
                            .onChange(of: text) { _, newValue in
                                // 打鍵ごとの blob 書き込みを避けるため 0.5 秒 debounce する
                                pendingContentSave?.cancel()
                                pendingContentSave = Task {
                                    try? await Task.sleep(for: .milliseconds(500))
                                    guard !Task.isCancelled else { return }
                                    clipboardManager.updateFavoriteContent(item, text: newValue)
                                    pendingContentSave = nil
                                }
                            }
                            .onDisappear {
                                // 未保存の編集を即時反映してから破棄する
                                if let pendingContentSave {
                                    pendingContentSave.cancel()
                                    clipboardManager.updateFavoriteContent(item, text: text)
                                }
                            }
                    } else {
                        if let thumbnailData = item.thumbnailData,
                           let nsImage = NSImage(data: thumbnailData) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        Text(item.previewText)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(nsColor: .separatorColor))
                            )

                        if item.isOCRCandidate {
                            let recognizing = clipboardManager.recognizingIds.contains(item.id)
                            if recognizing || item.recognizedText != nil {
                                RecognizedTextSection(recognizedText: item.recognizedText, isRecognizing: recognizing)
                            }
                        }

                        if canConvertToPlainText(item) {
                            Button {
                                clipboardManager.convertToPlainText(item)
                            } label: {
                                Label("Convert to Plain Text", systemImage: "doc.plaintext")
                            }
                        }
                    }

                    Divider()

                    // Actions
                    // 幅が足りないときはボタンが見切れないよう横→縦に折り返す
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            actionButtons(for: item)
                        }
                        VStack(spacing: 8) {
                            actionButtons(for: item)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding()
            }
        }
        .onAppear { loadItem() }
        // 別アイテムへ切り替わったとき、また変換でカテゴリが変わったとき（画像→プレーンテキスト等）に
        // 編集テキストを読み直す。これをしないと変換直後に変換前の内容が残る。
        .onChange(of: itemId) { _, _ in loadItem() }
        .onChange(of: item?.category) { _, _ in loadItem() }
    }

    @ViewBuilder
    private func actionButtons(for item: ClipboardItem) -> some View {
        Button {
            clipboardManager.toggleSave(item)
        } label: {
            Label(item.isSaved ? "Unfavorite" : "Favorite",
                  systemImage: item.isSaved ? "bookmark.slash" : "bookmark")
        }

        Button {
            clipboardManager.restoreToClipboard(item)
        } label: {
            Label("Copy to Clipboard", systemImage: "doc.on.clipboard")
        }

        Button(role: .destructive) {
            clipboardManager.removeItem(item)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func canConvertToPlainText(_ item: ClipboardItem) -> Bool {
        item.canConvertToPlainText
    }

    private func loadItem() {
        guard let item else { return }
        name = item.favoriteName ?? ""
        selectedFolderId = item.favoriteFolderId
        if isTextEditable,
           let reps = clipboardManager.store.loadRepresentations(for: item.id),
           let stringRep = reps.first(where: { $0.pasteboardType == .string }),
           let str = String(data: stringRep.data, encoding: .utf8) {
            text = str
        } else {
            text = item.previewText
        }
    }
}
