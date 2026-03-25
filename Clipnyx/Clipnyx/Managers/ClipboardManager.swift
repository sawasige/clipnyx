import AppKit
import Observation

@Observable
final class ClipboardManager: @unchecked Sendable {
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

    deinit {
        pollingTimer?.invalidate()
    }

    // MARK: - Polling

    func startPolling() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForChanges()
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

    // MARK: - Save (replaces Pin)

    func toggleSave(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = items
        updated[index].isSaved.toggle()
        if !updated[index].isSaved {
            updated[index].favoriteName = nil
            updated[index].favoriteFolderId = nil
        }
        items = updated
        store.saveIndex(items)
    }

    // MARK: - Favorite

    func registerAsFavorite(_ item: ClipboardItem, name: String, folderId: UUID) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = items
        updated[index].isSaved = true
        updated[index].favoriteName = name
        updated[index].favoriteFolderId = folderId
        items = updated
        store.saveIndex(items)
    }

    func removeFromFavorites(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = items
        updated[index].favoriteName = nil
        updated[index].favoriteFolderId = nil
        items = updated
        store.saveIndex(items)
    }

    func updateFavoriteName(_ item: ClipboardItem, name: String) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = items
        updated[index].favoriteName = name.isEmpty ? nil : name
        items = updated
        store.saveIndex(items)
    }

    func updateFavoriteFolder(_ item: ClipboardItem, folderId: UUID?) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = items
        updated[index].favoriteFolderId = folderId
        items = updated
        store.saveIndex(items)
    }

    func updateFavoriteContent(_ item: ClipboardItem, text: String) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let current = items[index]
        items[index] = ClipboardItem(
            id: current.id,
            timestamp: current.timestamp,
            category: current.category,
            previewText: String(text.prefix(500)),
            thumbnailData: current.thumbnailData,
            totalDataSize: text.utf8.count,
            contentHash: current.contentHash,
            representationInfos: [RepresentationInfo(type: NSPasteboard.PasteboardType.string.rawValue, size: text.utf8.count)],
            isSaved: current.isSaved,
            favoriteName: current.favoriteName,
            favoriteFolderId: current.favoriteFolderId
        )
        // Blob を更新
        let rep = PasteboardRepresentation(type: .string, data: Data(text.utf8))
        store.saveBlobs(for: item.id, representations: [rep], thumbnail: nil)
        store.saveIndex(items)
    }

    func convertToPlainText(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let text = item.previewText
        let current = items[index]
        items[index] = ClipboardItem(
            id: current.id,
            timestamp: current.timestamp,
            category: .plainText,
            previewText: current.previewText,
            thumbnailData: nil,
            totalDataSize: text.utf8.count,
            contentHash: current.contentHash,
            representationInfos: [RepresentationInfo(type: NSPasteboard.PasteboardType.string.rawValue, size: text.utf8.count)],
            isSaved: current.isSaved,
            favoriteName: current.favoriteName,
            favoriteFolderId: current.favoriteFolderId
        )
        let rep = PasteboardRepresentation(type: .string, data: Data(text.utf8))
        store.saveBlobs(for: item.id, representations: [rep], thumbnail: nil)
        store.saveIndex(items)
    }

    func createFavorite(text: String, name: String, folderId: UUID?) {
        let id = UUID()
        let item = ClipboardItem(
            id: id,
            timestamp: Date(),
            category: .plainText,
            previewText: String(text.prefix(500)),
            thumbnailData: nil,
            totalDataSize: text.utf8.count,
            contentHash: Data(),
            representationInfos: [RepresentationInfo(type: NSPasteboard.PasteboardType.string.rawValue, size: text.utf8.count)],
            isSaved: true,
            favoriteName: name,
            favoriteFolderId: folderId
        )
        items.insert(item, at: 0)
        let rep = PasteboardRepresentation(type: .string, data: Data(text.utf8))
        store.saveBlobs(for: id, representations: [rep], thumbnail: nil)
        store.saveIndex(items)
    }

    func addTextToHistory(text: String) {
        let id = UUID()
        let item = ClipboardItem(
            id: id,
            timestamp: Date(),
            category: .plainText,
            previewText: String(text.prefix(500)),
            thumbnailData: nil,
            totalDataSize: text.utf8.count,
            contentHash: Data(),
            representationInfos: [RepresentationInfo(type: NSPasteboard.PasteboardType.string.rawValue, size: text.utf8.count)],
            isSaved: false,
            favoriteName: nil,
            favoriteFolderId: nil
        )
        items.insert(item, at: 0)
        let rep = PasteboardRepresentation(type: .string, data: Data(text.utf8))
        store.saveBlobs(for: id, representations: [rep], thumbnail: nil)
        store.saveIndex(items)
    }

    // MARK: - Favorite Folders

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

        // 使用したアイテムを先頭に移動
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let index = self.items.firstIndex(where: { $0.id == item.id }) {
                let moved = self.items.remove(at: index)
                self.items.insert(moved, at: 0)
            }
            self.store.saveIndex(self.items)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isRestoringItem = false
        }
    }

    // MARK: - Statistics

    var totalDataSize: Int {
        items.reduce(0) { $0 + $1.totalDataSize }
    }

    var formattedTotalSize: String {
        let bytes = totalDataSize
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
        }
    }

    var categoryCountMap: [ClipboardContentCategory: Int] {
        var map: [ClipboardContentCategory: Int] = [:]
        for item in items {
            map[item.category, default: 0] += 1
        }
        return map
    }
}
