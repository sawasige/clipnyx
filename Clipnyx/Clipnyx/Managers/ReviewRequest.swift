import Foundation
import AppKit

/// App Store 版でのみ、適切なタイミングで控えめにレビューを依頼する導線。
///
/// Full（Homebrew）版は App Store 経由ではないため `SKStoreReviewController` /
/// `requestReview` は無効。そのため記録・依頼ともにすべて no-op にしてある。
///
/// 方針（Issue #97）:
/// - 履歴からの貼り付け（＝価値を感じたであろう操作）を控えめに記録する。
///   「累計回数」と「実際に使った日数」の2つを retention の指標として持つ
/// - 起動直後や貼り付けの瞬間ではなく、**コレクション画面を開いた「落ち着いた」タイミング**で依頼する
///   （Clipnyx のウィンドウが最前面なのでシステムのレビューダイアログが自然に寄る）
/// - 初回ゲート: 3日以上の利用日 かつ 累計15回以上の貼り付け
/// - 再依頼: 前回から90日以上 かつ その後も使い続けている（追加の貼り付けがある）場合のみ。
///   表示・頻度の最終判断は OS（最大 年3回）に委ねる。スクリーニング（評価の事前選別）はしない
@MainActor
enum ReviewRequest {
    private static let pasteCountKey = "reviewRequest.pasteCount"
    private static let activeDaysKey = "reviewRequest.activeDays"
    private static let lastActiveDayKey = "reviewRequest.lastActiveDay"
    private static let lastPromptDateKey = "reviewRequest.lastPromptDate"
    private static let pasteCountAtLastPromptKey = "reviewRequest.pasteCountAtLastPrompt"

    #if !ENABLE_SPARKLE
    #if DEBUG
    // 動作確認用に緩める（1回貼り付け→コレクションを開けば出る。再依頼間隔も 0 なので再検証が容易）。
    private static let minimumActiveDays = 1
    private static let minimumPasteCount = 1
    private static let reAskInterval: TimeInterval = 0
    private static let minimumNewPastes = 0
    #else
    /// 初回ゲート: これだけの「実際に使った日数」が必要（retention シグナル）。
    private static let minimumActiveDays = 3
    /// 初回ゲート: これだけ累計で履歴を再利用してから依頼する。
    private static let minimumPasteCount = 15
    /// 再依頼: 前回依頼からこの期間を空ける（90日）。年3回の OS 上限を活かせる間隔。
    private static let reAskInterval: TimeInterval = 90 * 24 * 60 * 60
    /// 再依頼: 前回依頼以降にこれだけ新たに使っている（＝休眠していない）こと。
    private static let minimumNewPastes = 5
    #endif
    #endif

    /// 価値を感じたであろう操作（履歴からの貼り付け・再利用）を1回記録する。
    /// 累計回数と、日付が変わったら「利用した日数」を加算する。
    static func recordValueMoment() {
        #if !ENABLE_SPARKLE
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: pasteCountKey) + 1, forKey: pasteCountKey)

        let today = Calendar.current.startOfDay(for: Date())
        let lastActiveDay = defaults.object(forKey: lastActiveDayKey) as? Date
        if lastActiveDay == nil || !Calendar.current.isDate(lastActiveDay!, inSameDayAs: today) {
            defaults.set(defaults.integer(forKey: activeDaysKey) + 1, forKey: activeDaysKey)
            defaults.set(today, forKey: lastActiveDayKey)
        }
        #endif
    }

    /// 邪魔にならないタイミング（コレクション画面を開いたとき）で呼ぶ。
    /// 条件を満たしていれば `perform` を実行する。`perform` には SwiftUI の
    /// `requestReview` アクションなど、実際の依頼処理を渡す。
    static func requestIfAppropriate(_ perform: () -> Void) {
        #if !ENABLE_SPARKLE
        #if DEBUG
        // デモ録画モードではレビュー依頼を一切出さない（録画に写り込むのを防ぐ）。
        // DEBUG は閾値を極小にしているため、これがないとコレクションを開くたびに発火する。
        if CommandLine.arguments.contains("--demo-mode") { return }
        #endif
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: activeDaysKey) >= minimumActiveDays else { return }
        let pasteCount = defaults.integer(forKey: pasteCountKey)
        guard pasteCount >= minimumPasteCount else { return }

        if let lastPrompt = defaults.object(forKey: lastPromptDateKey) as? Date {
            // 再依頼は、前回から十分間隔があり、かつその後も使い続けている場合のみ。
            guard Date().timeIntervalSince(lastPrompt) >= reAskInterval else { return }
            guard pasteCount - defaults.integer(forKey: pasteCountAtLastPromptKey) >= minimumNewPastes else { return }
        }

        // 依頼した記録を残す（次の再依頼の起点。OS が実際に出すかは別判断）。
        defaults.set(Date(), forKey: lastPromptDateKey)
        defaults.set(pasteCount, forKey: pasteCountAtLastPromptKey)
        perform()
        #endif
    }

    /// App Store のレビュー記入ページを開く（設定画面の手動導線）。
    /// Apple が公式に案内している「レビューを書く」リンク形式（`?action=write-review`）。
    static func openReviewPage() {
        #if !ENABLE_SPARKLE
        guard let url = URL(string: "https://apps.apple.com/app/id6759652985?action=write-review") else { return }
        NSWorkspace.shared.open(url)
        #endif
    }
}
