import Foundation

/// 履歴一覧の絞り込み。ペーストパネル（Tab 巡回・フォルダチップ）と
/// コレクション画面（サイドバー選択）で共有する。
enum FavoriteFilter: Hashable {
    case allHistory
    case allSaved
    case uncategorized
    case folder(UUID)

    /// この絞り込みをアイテム列に適用する
    func apply(to items: [ClipboardItem]) -> [ClipboardItem] {
        switch self {
        case .allHistory:
            return items
        case .allSaved:
            return items.filter(\.isSaved)
        case .uncategorized:
            return items.filter { $0.isSaved && $0.favoriteFolderId == nil }
        case .folder(let id):
            return items.filter { $0.favoriteFolderId == id }
        }
    }

    /// Tab キーで巡回する順序（全履歴 → 全お気に入り → 未分類 → 各フォルダ）
    static func cycleOrder(folders: [FavoriteFolder]) -> [FavoriteFilter] {
        [.allHistory, .allSaved, .uncategorized] + folders.map { .folder($0.id) }
    }
}
