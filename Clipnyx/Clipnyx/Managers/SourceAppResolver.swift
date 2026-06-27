import AppKit

/// コピー元アプリの bundle ID から表示名・アイコンを解決する。
/// アイコン・名前は実行時に解決してキャッシュするだけで、履歴 blob には保存しない
/// （保存はあくまで bundle ID 文字列のみ。アイコン画像で永続データが肥大化しない）。
@MainActor
enum SourceAppResolver {
    private static var iconCache: [String: NSImage?] = [:]
    private static var nameCache: [String: String?] = [:]

    private static func appURL(for bundleId: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
    }

    /// アプリアイコン。解決できなければ nil（行表示側でフォールバックする）。
    static func icon(for bundleId: String) -> NSImage? {
        if let cached = iconCache[bundleId] { return cached }
        let icon = appURL(for: bundleId).map { NSWorkspace.shared.icon(forFile: $0.path) }
        iconCache[bundleId] = icon
        return icon
    }

    /// アプリ表示名（"Safari" など）。解決できなければ bundle ID をそのまま返す。
    static func name(for bundleId: String) -> String {
        if let cached = nameCache[bundleId] { return cached ?? bundleId }
        let resolved = appURL(for: bundleId).map {
            (FileManager.default.displayName(atPath: $0.path) as NSString).deletingPathExtension
        }
        nameCache[bundleId] = resolved
        return resolved ?? bundleId
    }
}
