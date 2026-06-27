import AppKit
import os

final class ClipboardStore: Sendable {
    private let writeQueue = DispatchQueue(label: "com.clipnyx.store.write", qos: .utility)
    private static let logger = Logger(subsystem: "com.himatsubu.Clipnyx", category: "ClipboardStore")

    /// true のとき書き込み・削除を一切行わない（スクリーンショット生成などの
    /// プレビュー用途で実データを保護する）。読み取りは許可される。
    let isReadOnly: Bool

    /// デモ録画モード用: アイテム ID → ペーストボード代表データのメモリ上マップ。
    /// `loadRepresentations` はディスクより先にこちらを参照するため、デモアイテムでも
    /// 実際にクリップボードへ復元・ペーストできる（ディスクには一切触れない）。
    private let inMemoryRepresentations: [UUID: [PasteboardRepresentation]]

    init(isReadOnly: Bool = false, inMemoryRepresentations: [UUID: [PasteboardRepresentation]] = [:]) {
        self.isReadOnly = isReadOnly
        self.inMemoryRepresentations = inMemoryRepresentations
    }

    private static let baseURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Clipnyx", isDirectory: true)
    }()

    private static let indexURL: URL = {
        baseURL.appendingPathComponent("index.json")
    }()

    private static let blobsURL: URL = {
        baseURL.appendingPathComponent("blobs", isDirectory: true)
    }()

    private static let favoriteFoldersURL: URL = {
        baseURL.appendingPathComponent("favorite_folders.json")
    }()

    /// Legacy file path for backward compatibility
    private static let legacySnippetCategoriesURL: URL = {
        baseURL.appendingPathComponent("snippet_categories.json")
    }()

    // MARK: - Index Codable Types

    private struct IndexEntry: Codable {
        let id: UUID
        let timestamp: Date
        let category: ClipboardContentCategory
        let previewText: String
        let hasThumbnail: Bool
        let totalDataSize: Int
        let contentHash: Data
        let representationInfos: [RepInfoEntry]
        // Legacy field (read-only for migration)
        let isPinned: Bool?
        // New fields
        let isSaved: Bool?
        let favoriteName: String?
        let favoriteFolderId: UUID?
        // OCR 認識テキスト（画像・PDF のみ。後方互換のため任意フィールド）
        let recognizedText: String?
        // コピー元アプリの bundle ID（後方互換のため任意フィールド）
        let sourceBundleId: String?

        // Legacy fallback keys
        // 旧バージョンが書き出した index を読むための互換フィールド（読み取り専用）。
        // 初回保存時に新キーへ書き換わる。旧版からの直接アップデートを
        // サポートしなくなるまで削除しないこと。
        let snippetName: String?
        let snippetCategoryId: UUID?

        enum CodingKeys: String, CodingKey {
            case id, timestamp, category, previewText, hasThumbnail, totalDataSize, contentHash
            case representationInfos, isPinned, isSaved
            case favoriteName, favoriteFolderId
            case recognizedText
            case sourceBundleId
            case snippetName, snippetCategoryId
        }
    }

    private struct RepInfoEntry: Codable {
        let type: String
        let size: Int
    }

    private struct BlobMeta: Codable {
        let types: [String]
        let sizes: [Int]
    }

    // MARK: - Save Index

    func saveIndex(_ items: [ClipboardItem]) {
        guard !isReadOnly else { return }
        let entries = items.map { item in
            IndexEntry(
                id: item.id,
                timestamp: item.timestamp,
                category: item.category,
                previewText: item.previewText,
                hasThumbnail: item.thumbnailData != nil,
                totalDataSize: item.totalDataSize,
                contentHash: item.contentHash,
                representationInfos: item.representationInfos.map { RepInfoEntry(type: $0.type, size: $0.size) },
                isPinned: nil,
                isSaved: item.isSaved,
                favoriteName: item.favoriteName,
                favoriteFolderId: item.favoriteFolderId,
                recognizedText: item.recognizedText,
                sourceBundleId: item.sourceBundleId,
                snippetName: nil,
                snippetCategoryId: nil
            )
        }
        writeQueue.async {
            do {
                try FileManager.default.createDirectory(at: Self.baseURL, withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(entries)
                try data.write(to: Self.indexURL, options: .atomic)
            } catch {
                Self.logger.error("Failed to save index: \(error)")
            }
        }
    }

    // MARK: - Save Blobs

    func saveBlobs(for itemID: UUID, representations: [PasteboardRepresentation], thumbnail: Data?) {
        guard !isReadOnly else { return }
        writeQueue.async {
            do {
                let blobDir = Self.blobsURL.appendingPathComponent(itemID.uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: blobDir, withIntermediateDirectories: true)

                // Write representation data
                for (index, rep) in representations.enumerated() {
                    let repFile = blobDir.appendingPathComponent("rep-\(index).dat")
                    try rep.data.write(to: repFile)
                }

                // Write thumbnail
                if let thumbnail {
                    let thumbFile = blobDir.appendingPathComponent("thumb.dat")
                    try thumbnail.write(to: thumbFile)
                }

                // Write meta.json
                let meta = BlobMeta(
                    types: representations.map(\.typeRawValue),
                    sizes: representations.map(\.data.count)
                )
                let metaData = try JSONEncoder().encode(meta)
                try metaData.write(to: blobDir.appendingPathComponent("meta.json"))
            } catch {
                Self.logger.error("Failed to save blobs for \(itemID): \(error)")
            }
        }
    }

    // MARK: - Load Index

    func loadIndex() -> [ClipboardItem] {
        guard FileManager.default.fileExists(atPath: Self.indexURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: Self.indexURL)
            let entries = try JSONDecoder().decode([IndexEntry].self, from: data)
            return entries.compactMap { entry in
                // Load thumbnail from blob dir
                var thumbnailData: Data?
                if entry.hasThumbnail {
                    let thumbFile = Self.blobsURL
                        .appendingPathComponent(entry.id.uuidString, isDirectory: true)
                        .appendingPathComponent("thumb.dat")
                    thumbnailData = try? Data(contentsOf: thumbFile)
                }

                return ClipboardItem(
                    id: entry.id,
                    timestamp: entry.timestamp,
                    category: entry.category,
                    previewText: entry.previewText,
                    thumbnailData: thumbnailData,
                    totalDataSize: entry.totalDataSize,
                    contentHash: entry.contentHash,
                    representationInfos: entry.representationInfos.map { RepresentationInfo(type: $0.type, size: $0.size) },
                    isSaved: entry.isSaved ?? entry.isPinned ?? false,
                    favoriteName: entry.favoriteName ?? entry.snippetName,
                    favoriteFolderId: entry.favoriteFolderId ?? entry.snippetCategoryId,
                    recognizedText: entry.recognizedText,
                    sourceBundleId: entry.sourceBundleId
                )
            }
        } catch {
            Self.logger.error("Failed to load index: \(error)")
            return []
        }
    }

    // MARK: - Load Representations

    func loadRepresentations(for itemID: UUID) -> [PasteboardRepresentation]? {
        // デモ録画モード: メモリ上の代表データを優先（ディスクには触れない）
        if let memory = inMemoryRepresentations[itemID] { return memory }

        let blobDir = Self.blobsURL.appendingPathComponent(itemID.uuidString, isDirectory: true)
        let metaFile = blobDir.appendingPathComponent("meta.json")

        guard let metaData = try? Data(contentsOf: metaFile),
              let meta = try? JSONDecoder().decode(BlobMeta.self, from: metaData) else { return nil }

        var reps: [PasteboardRepresentation] = []
        for (index, type) in meta.types.enumerated() {
            let repFile = blobDir.appendingPathComponent("rep-\(index).dat")
            guard let data = try? Data(contentsOf: repFile) else { continue }
            reps.append(PasteboardRepresentation(
                type: NSPasteboard.PasteboardType(type),
                data: data
            ))
        }

        return reps.isEmpty ? nil : reps
    }

    // MARK: - Delete

    func deleteBlobs(for itemIDs: [UUID]) {
        guard !isReadOnly else { return }
        writeQueue.async {
            let fm = FileManager.default
            for id in itemIDs {
                let blobDir = Self.blobsURL.appendingPathComponent(id.uuidString, isDirectory: true)
                try? fm.removeItem(at: blobDir)
            }
        }
    }

    func deleteAll() {
        guard !isReadOnly else { return }
        writeQueue.async {
            let fm = FileManager.default
            try? fm.removeItem(at: Self.indexURL)
            try? fm.removeItem(at: Self.blobsURL)
        }
    }

    // MARK: - Favorite Folders

    func saveFavoriteFolders(_ folders: [FavoriteFolder]) {
        guard !isReadOnly else { return }
        writeQueue.async {
            do {
                try FileManager.default.createDirectory(at: Self.baseURL, withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(folders)
                try data.write(to: Self.favoriteFoldersURL, options: .atomic)
            } catch {
                Self.logger.error("Failed to save favorite folders: \(error)")
            }
        }
    }

    func loadFavoriteFolders() -> [FavoriteFolder] {
        // Try new file first
        if FileManager.default.fileExists(atPath: Self.favoriteFoldersURL.path) {
            do {
                let data = try Data(contentsOf: Self.favoriteFoldersURL)
                return try JSONDecoder().decode([FavoriteFolder].self, from: data)
            } catch {
                Self.logger.error("Failed to load favorite folders: \(error)")
                return []
            }
        }
        // Fallback to legacy file
        if FileManager.default.fileExists(atPath: Self.legacySnippetCategoriesURL.path) {
            do {
                let data = try Data(contentsOf: Self.legacySnippetCategoriesURL)
                return try JSONDecoder().decode([FavoriteFolder].self, from: data)
            } catch {
                Self.logger.error("Failed to load legacy snippet categories: \(error)")
                return []
            }
        }
        return []
    }

    // MARK: - Cleanup Orphans

    func cleanupOrphans(validIDs: Set<UUID>) {
        guard !isReadOnly else { return }
        writeQueue.async {
            let fm = FileManager.default
            guard let contents = try? fm.contentsOfDirectory(
                at: Self.blobsURL,
                includingPropertiesForKeys: nil
            ) else { return }

            for url in contents {
                guard let uuid = UUID(uuidString: url.lastPathComponent) else {
                    try? fm.removeItem(at: url)
                    continue
                }
                if !validIDs.contains(uuid) {
                    try? fm.removeItem(at: url)
                }
            }
        }
    }
}
