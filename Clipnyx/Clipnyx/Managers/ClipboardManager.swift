import AppKit
import Observation

@MainActor
@Observable
final class ClipboardManager {
    var items: [ClipboardItem] = []
    var isPaused: Bool = false
    var favoriteFolders: [FavoriteFolder] = []

    var maxHistoryCount: Int {
        didSet { UserDefaults.standard.set(maxHistoryCount, forKey: "maxHistoryCount") }
    }

    var maxTotalSizeMB: Int {
        didSet { UserDefaults.standard.set(maxTotalSizeMB, forKey: "maxTotalSizeMB") }
    }

    var excludedCategories: Set<ClipboardContentCategory> {
        didSet { UserDefaults.standard.set(excludedCategories.map(\.rawValue), forKey: "excludedCategories") }
    }

    private(set) var isRestoringItem: Bool = false
    private var lastChangeCount: Int = 0
    private var pollingTimer: Timer?
    let store = ClipboardStore()

    init() {
        maxHistoryCount = UserDefaults.standard.object(forKey: "maxHistoryCount") as? Int ?? 50
        maxTotalSizeMB = UserDefaults.standard.object(forKey: "maxTotalSizeMB") as? Int ?? 1024
        if let raw = UserDefaults.standard.stringArray(forKey: "excludedCategories") {
            excludedCategories = Set(raw.compactMap { ClipboardContentCategory(rawValue: $0) })
        } else {
            excludedCategories = []
        }
        items = store.loadIndex()
        favoriteFolders = store.loadFavoriteFolders()
        store.cleanupOrphans(validIDs: Set(items.map(\.id)))
        lastChangeCount = NSPasteboard.general.changeCount
        startPolling()
    }

    // MARK: - Polling

    // タイマーはメインランループにスケジュールされるため、コールバックは常にメインスレッド。
    // アプリ終了時は applicationWillTerminate が stopPolling() を呼ぶ。
    func startPolling() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkForChanges()
            }
        }
    }

    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    private func checkForChanges() {
        guard !isPaused, !isRestoringItem else { return }

        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        guard let (newItem, representations) = ClipboardItem.capture(from: pasteboard) else { return }

        // Check excluded categories
        guard !excludedCategories.contains(newItem.category) else { return }

        addItem(newItem, representations: representations)
    }

    // MARK: - Item Management

    private func addItem(_ newItem: ClipboardItem, representations: [PasteboardRepresentation]) {
        // 保存済みアイテムの重複は除外しない
        let duplicateIDs = items.filter { !$0.isSaved && $0.hasSameContent(as: newItem) }.map(\.id)

        // Remove duplicates (unsaved only)
        items.removeAll { !$0.isSaved && $0.hasSameContent(as: newItem) }

        // Insert at front
        items.insert(newItem, at: 0)

        // Enforce count limit (unsaved only)
        var removedIDs = duplicateIDs
        let unsavedCount = items.filter({ !$0.isSaved }).count
        if unsavedCount > maxHistoryCount {
            var removeCount = unsavedCount - maxHistoryCount
            var i = items.count - 1
            while i >= 0, removeCount > 0 {
                if !items[i].isSaved {
                    removedIDs.append(items[i].id)
                    items.remove(at: i)
                    removeCount -= 1
                }
                i -= 1
            }
        }

        // Enforce total size limit (unsaved only)
        let maxBytes = maxTotalSizeMB * 1024 * 1024
        while items.filter({ !$0.isSaved }).count > 1, totalDataSize > maxBytes {
            if let lastUnsavedIndex = items.lastIndex(where: { !$0.isSaved }) {
                removedIDs.append(items[lastUnsavedIndex].id)
                items.remove(at: lastUnsavedIndex)
            } else {
                break
            }
        }

        // Save blobs first, then index
        store.saveBlobs(for: newItem.id, representations: representations, thumbnail: newItem.thumbnailData)
        store.saveIndex(items)
        if !removedIDs.isEmpty {
            store.deleteBlobs(for: removedIDs)
        }
    }

    func removeItem(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        store.saveIndex(items)
        store.deleteBlobs(for: [item.id])
    }

    func removeAllItems() {
        // 保存済みアイテムは残す
        let saved = items.filter(\.isSaved)
        let removedIDs = items.filter { !$0.isSaved }.map(\.id)
        items = saved
        store.saveIndex(items)
        if !removedIDs.isEmpty {
            store.deleteBlobs(for: removedIDs)
        }
    }

    /// ID でアイテムを見つけて変更を適用し、index を保存する
    private func updateItem(id: UUID, _ mutate: (inout ClipboardItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[index])
        store.saveIndex(items)
    }

    // MARK: - Save (replaces Pin)

    func toggleSave(_ item: ClipboardItem) {
        updateItem(id: item.id) {
            $0.isSaved.toggle()
            if !$0.isSaved {
                $0.favoriteName = nil
                $0.favoriteFolderId = nil
            }
        }
    }

    // MARK: - Favorite

    func registerAsFavorite(_ item: ClipboardItem, name: String, folderId: UUID) {
        updateItem(id: item.id) {
            $0.isSaved = true
            $0.favoriteName = name
            $0.favoriteFolderId = folderId
        }
    }

    func removeFromFavorites(_ item: ClipboardItem) {
        updateItem(id: item.id) {
            $0.favoriteName = nil
            $0.favoriteFolderId = nil
        }
    }

    func updateFavoriteName(_ item: ClipboardItem, name: String) {
        updateItem(id: item.id) {
            $0.favoriteName = name.isEmpty ? nil : name
        }
    }

    func updateFavoriteFolder(_ item: ClipboardItem, folderId: UUID?) {
        updateItem(id: item.id) {
            $0.favoriteFolderId = folderId
        }
    }

    func updateFavoriteContent(_ item: ClipboardItem, text: String) {
        replaceContentWithPlainText(
            id: item.id,
            text: text,
            category: item.category,
            previewText: String(text.prefix(500)),
            thumbnailData: item.thumbnailData
        )
    }

    func convertToPlainText(_ item: ClipboardItem) {
        replaceContentWithPlainText(
            id: item.id,
            text: item.previewText,
            category: .plainText,
            previewText: item.previewText,
            thumbnailData: nil
        )
    }

    private func replaceContentWithPlainText(
        id: UUID,
        text: String,
        category: ClipboardContentCategory,
        previewText: String,
        thumbnailData: Data?
    ) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let (updated, rep) = items[index].replacingContentWithPlainText(
            text: text,
            category: category,
            previewText: previewText,
            thumbnailData: thumbnailData
        )
        items[index] = updated
        store.saveBlobs(for: id, representations: [rep], thumbnail: nil)
        store.saveIndex(items)
    }

    func createFavorite(text: String, name: String, folderId: UUID?) {
        insertPlainTextItem(ClipboardItem.plainText(
            text: text, isSaved: true, favoriteName: name, favoriteFolderId: folderId
        ))
    }

    func addTextToHistory(text: String) {
        insertPlainTextItem(ClipboardItem.plainText(text: text, isSaved: false))
    }

    private func insertPlainTextItem(_ pair: (item: ClipboardItem, representation: PasteboardRepresentation)) {
        items.insert(pair.item, at: 0)
        store.saveBlobs(for: pair.item.id, representations: [pair.representation], thumbnail: nil)
        store.saveIndex(items)
    }

    // MARK: - Favorite Folders

    /// 表示順（order 昇順）に並べたお気に入りフォルダ
    var sortedFavoriteFolders: [FavoriteFolder] {
        favoriteFolders.sorted { $0.order < $1.order }
    }

    func addFavoriteFolder(name: String) -> FavoriteFolder {
        let maxOrder = favoriteFolders.max(by: { $0.order < $1.order })?.order ?? -1
        let folder = FavoriteFolder(name: name, order: maxOrder + 1)
        favoriteFolders.append(folder)
        store.saveFavoriteFolders(favoriteFolders)
        return folder
    }

    func renameFavoriteFolder(id: UUID, name: String) {
        guard let index = favoriteFolders.firstIndex(where: { $0.id == id }) else { return }
        var updated = favoriteFolders
        updated[index].name = name
        favoriteFolders = updated
        store.saveFavoriteFolders(favoriteFolders)
    }

    func deleteFavoriteFolder(id: UUID) {
        favoriteFolders.removeAll { $0.id == id }
        store.saveFavoriteFolders(favoriteFolders)
        // 該当フォルダのアイテムからお気に入り属性をクリア（isSavedは維持）
        for i in items.indices where items[i].favoriteFolderId == id {
            items[i].favoriteName = nil
            items[i].favoriteFolderId = nil
        }
        store.saveIndex(items)
    }

    func reorderFavoriteFolders(_ folders: [FavoriteFolder]) {
        favoriteFolders = folders
        store.saveFavoriteFolders(favoriteFolders)
    }

    // MARK: - Restore

    func restoreToClipboard(_ item: ClipboardItem, asPlainText: Bool = false) {
        isRestoringItem = true

        if let reps = store.loadRepresentations(for: item.id) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            if asPlainText {
                if let stringRep = reps.first(where: { $0.pasteboardType == .string }) {
                    pasteboard.declareTypes([.string], owner: nil)
                    pasteboard.setData(stringRep.data, forType: .string)
                }
            } else {
                let types = reps.map(\.pasteboardType)
                pasteboard.declareTypes(types, owner: nil)
                for rep in reps {
                    pasteboard.setData(rep.data, forType: rep.pasteboardType)
                }
            }
        }
        lastChangeCount = NSPasteboard.general.changeCount

        // 使用したアイテムを先頭に移動（現在のイベント処理が終わってから行う）
        Task {
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                let moved = items.remove(at: index)
                items.insert(moved, at: 0)
            }
            store.saveIndex(items)
        }

        // ポーリングが自分の書き込みを履歴として拾わないよう、復元直後の1サイクルは監視を止める
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            isRestoringItem = false
        }
    }

    // MARK: - Statistics

    var totalDataSize: Int {
        items.reduce(0) { $0 + $1.totalDataSize }
    }

    var formattedTotalSize: String {
        totalDataSize.formatted(.byteCount(style: .file))
    }

    var categoryCountMap: [ClipboardContentCategory: Int] {
        var map: [ClipboardContentCategory: Int] = [:]
        for item in items {
            map[item.category, default: 0] += 1
        }
        return map
    }
}
