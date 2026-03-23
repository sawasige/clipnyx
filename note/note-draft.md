# Clipnyx 開発記 — noteネタ帳

## 開発の全体像

- 開発期間: 2026/2/25 〜 3/22（約1ヶ月）
- 総コミット数: 129（マージコミット含む）
- リリース: v1.0.0 〜 v1.2.1（10リリース）
- 開発はほぼすべてClaude Codeで行った（手書きコードなし）

---

## 1. なぜ作ったか — クリップボードマネージャーの系譜

Windows時代からクリップボード履歴マネージャーをずっと使ってきた。

- **CLCL**（Windows） — Alt+Cでホットキー呼び出し、システムトレイ常駐の老舗フリーソフト
- **ClipMenu**（Mac） — Macに移行して使い始めたクリップボード管理アプリ。その後開発停止・オープンソース化
- **Clipy**（Mac） — ClipMenuのコードベースを引き継いで開発された後継アプリ。直近まで使用

Clipyに大きな不満はなかったが、UIが古臭いのと開発が進んでいないように見えた。

自作の動機は **単純に何かMacアプリを作りたかった**のがいちばんの理由。Macアプリの開発自体がすごく久しぶりで、Claude Codeを使えば簡単に思い通りのものが作れそうだった。課金してるし高いからもったいない、というのもある。

MaccyやPasteといった最近のクリップボードマネージャーは使っていない。豪華すぎる。

### Windows時代のアプリ開発

以前Windowsで **Special Launch** というランチャーアプリを公開していた。同分野では国内で1位2位を争うほど評判が良かった。アイコンに星をモチーフにしていたことが、後のClipnyxの命名にもつながっている。

---

## 2. 誕生 — 初日の5時間（2/25）

14:50 に「ClipboardHistory」として初コミット。そこから5時間で：

- 14:50 初コミット
- 14:59 ログイン時起動
- 15:58 メニューバーアイコン、署名
- 16:21 アプリアイコン（初日に2回変更）
- 16:41 ホットキーのカスタマイズ
- 16:52 ターミナルへの貼り付け対応
- 16:56 ポップアップパネルの背景改善
- **17:53 Clipnyxに改名**
- 19:17 App Sandbox有効化
- 19:54 App Store提出準備

→ 初日に基本機能完成 + App Store申請準備まで到達

---

## 3. アプリ名 — Clip + Nyx（夜の女神）

### 初期名
**ClipboardHistory** — ありきたりすぎる。機能がある程度形になった16:56以降、名前探しを開始。

### 命名プロセス
「クリップボードを想起する単語 + 個性を表す名前」という方針で、Claude Codeに候補を大量に出させた。同時に、同名のアプリが既に存在しないかを調査させた。

結構たくさん候補を出したが、同じ名前のアプリがあることが多く、決定まで時間がかかった。約1時間の検討の末、17:53に **Clipnyx** に決定。翌日（2/26）にプロジェクト全体をリネーム。

### Nyxの由来
**Nyx（ニュクス / Νύξ）** — ギリシャ神話の夜の女神。

- 女神というのがかっこいい
- Special Launchで星をモチーフにしていたので、夜の女神とのつながりを感じた
- 発音はしづらいが、逆にかっこいいと思った。LinuxとかGnuとか読み方がわからない単語がかっこいい
- 他に同名のアプリがなかった

ボツ案は…もう覚えていない。

---

## 4. アイコン — 夜の女神をChatGPTで

### アプリアイコン
- **ChatGPT**で生成。「夜の女神」「立体感がない」「背景透明」などを指示
- 生成した画像をそのままアプリアイコンに使用
- 初日に2回変更して現在のデザインに

ChatGPTが出力した画像：

![ChatGPTが生成した夜の女神Nyx](nyx.png)

### メニューバーアイコン
- 当初は女神ベースのデザインだったが、小さすぎてわかりづらい
- **クリップボードベース**のデザインに変更（2/28）

### 3/4 アイコン表示問題
- GitHub Actionsでビルドしたらアイコンが表示されない
- Icon Composer対応が必要だった
- CIランナーを macos-26 に変更して解決

---

## 5. App Store — リジェクトとの戦い

### 審査タイムライン

| 日付 | 出来事 |
|------|--------|
| 2/25 | 初日にSandbox化してApp Store提出準備 |
| 2/26 14:44 | 初回提出「Ready For Review」 |
| 3/3 19:31 | **リジェクト** |
| 3/4 11:48 | 再提出「Ready For Review」 |
| 3/10 08:07 | **承認「Ready for Distribution」** |

初回提出から承認まで **約2週間**（2/26〜3/10）。

### リジェクト理由

**Guideline 2.4.5 - Performance**（Accessibility）

> The app requests access to Accessibility features on macOS but does not use these features for accessibility purposes.

Accessibility APIを使っていないのにリジェクトされた。App Store版では `#if ENABLE_AUTOPASTE` でアクセシビリティ関連コード（`AXIsProcessTrusted` 等）をコンパイル時に除外していたが、レビュアーに伝わらなかった。

### 返信内容（要約）
「App Store版ではAccessibility APIを一切使っていない。`#if ENABLE_AUTOPASTE` でコンパイル時に除外済み。App Sandbox内で動作し、NSPasteboardのみアクセスしている。ユーザーが履歴アイテムを選択するとシステムペーストボードにコピーするだけで、キーストローク模倣やAccessibility機能は使用していない」

→ 再提出後、6日で承認。ただしこれは「クリップボードにコピーするだけ」版での承認。

### ペースト機能はまだ実現できていない
App Store版では `CGEvent.post` による ⌘V 送信（ダイレクトペースト）を実現できていない。Full版では問題なく動くが、App Store版ではクリップボードにコピーするだけの機能に制限されている。

ペースト機能をApp Storeで実現する方法を模索中で、**審査との格闘は継続中**。

### このリジェクトがきっかけで
`ENABLE_AUTOPASTE` フラグを整理し `ENABLE_SPARKLE` に分離。App Store版とFull版のコンパイルフラグをきれいに分けた。

### App Storeに出した動機
Analyticsを仕込んでいないので、**App Storeからダウンロード数などを確認したかった**。

### App Storeバッジの一時無効化（3/5）
まだ審査中で公開されていなかったため、ランディングページのApp Storeバッジを一時的に非表示にした。3/10の承認後に有効化。

### 2エディション並行運用
- **App Store版**: サンドボックス、Sparkleなし、Xcode Cloudでビルド
- **Full版（Homebrew）**: サンドボックス + Sparkle自動更新、GitHub Actionsでビルド
- Full版リリース → タグ `v*` 作成 → Xcode Cloudが自動トリガー → 両方同時デプロイ
- `ENABLE_SPARKLE` コンパイルフラグで分岐

---

## 6. 3/4 CI地獄 — 1日6リリース

v1.0.0の初リリース日。GitHub Actionsの自動化を整備しながらリリースし、修正→再リリースを繰り返した。

| バージョン | 時刻 | 何を直した |
|-----------|------|-----------|
| v1.0.0 | 11:36 | 初リリース！…しかしHomebrew CaskのURLが間違い |
| v1.0.0 | (再) | Cask URLをsawasige orgに修正 |
| v1.1.0 | 14:54 | Sparkle自動アップデート追加。しかしApp Store版にSparkleが混入 |
| v1.1.1 | 18:53 | workflow_dispatch起動に変更 |
| v1.1.2 | 19:02 | リリース作成をタグ作成後に移動（重複タグエラー） |
| v1.1.3 | 19:29 | アプリアイコンが表示されない問題を修正 |
| v1.1.4 | 19:43 | CIランナーをmacos-26に変更（Icon Composer対応） |

→ YAML構文エラー、sign_updateパス、Sparkle除外忘れ、detached HEAD、重複タグ…全部踏んだ

---

## 7. サンドボックスとの戦い

macOS のサンドボックス環境でクリップボード履歴マネージャーを作る難しさ：

- `AXIsProcessTrusted()` が使えない → `CGRequestPostEventAccess()` / `CGPreflightPostEventAccess()` に統一
- Carbon API (`RegisterEventHotKey`) → 最初NSEventに置き換えたが、最終的にCarbon APIに戻した（イベント消費のため）
- ペースト: `CGEvent.post` で ⌘V を送信（PostEvent権限が必要）
- 当初Full版はサンドボックスなしだったが、v1.1.6で統一

---

## 8. 設定ウィンドウの格闘

MenuBarExtraアプリで設定画面を前面に表示する問題に長時間格闘。

### 問題
- MenuBarExtraのパネルは「非アクティブ」— パネルが表示されてもアプリはアクティブにならない
- そこから設定ウィンドウを開いても、前面に来ない

### 試したこと
- `NSApp.activate(ignoringOtherApps: true)` → macOS 14でパラメータ無視されるようになった
- `NSApp.activate()` 新API → メニューバーアプリでは効かない
- window level を `.floating` に → 他の問題が発生
- `NSWorkspace.openApplication` → 効果なし
- SwiftUI の `Settings` シーン → MenuBarExtraパネルが閉じない
- `SettingsLink` → アクティベーション問題は解決せず
- メインウィンドウ方式 → 常にDock/Cmd+Tabに表示されるが設定が背面に行く問題は残った

### 最終解決
**パネルを全部閉じてからactivate** — シンプルだが一番効いた

```swift
for window in NSApp.windows where window is NSPanel && window.isVisible {
    window.orderOut(nil)
}
window.makeKeyAndOrderFront(nil)
NSApp.activate(ignoringOtherApps: true)
```

---

## 9. スニペット → ピン留め（v1.2.0）

### 作ったけど消した機能
- スニペット機能: フォルダ管理、変数展開（`{{date}}` 等）付きのテキストスニペット
- 7ファイル（Model, Manager, Store, View x3）を実装

### なぜ消したか
- 履歴とスニペットで操作感が違う
- メニューバーとポップアップで見た目が似てるのに挙動が違う
- 変数展開もあまり便利じゃなかった

### 何に変えたか
- スニペット → `ClipboardItem.isPinned` プロパティだけ
- メニューバーとポップアップを `PopupContentView(isMenuBar:)` で統一
- Tab キーでピン留めフィルタ切り替え
- 7ファイル削除、コードは大幅にシンプルに

---

## 10. Claude Codeとの開発

### 開発スタイル
- コードはほぼ全てClaude Codeが書いた。手書きはない
- CLAUDE.md でプロジェクトルール・構造を共有
- コミットメッセージは日本語
- mainに直接コミットしない（ブランチ→PR→マージ）
- 「動作確認の前にコミットしない」ルール

### なぜClaude Codeで開発したか
- 課金してるし高いからもったいない
- Macアプリの開発自体がすごく久しぶりで、Claude Codeなら簡単に思い通りのものが作れそうだった

### 感想
- あまり苦労していないが、一度思い通りに動かないとなかなか治らない
- 命名もClaude Codeに候補を出させて調査させた

---

## 11. 数字で見るClipnyx

| 項目 | 値 |
|------|-----|
| 開発開始 | 2026/2/25 14:50 |
| 初リリース（v1.0.0） | 2026/3/4 |
| 最新バージョン | v1.2.1（3/22） |
| 総コミット | 129 |
| PR数 | 20 |
| タグ数 | 10 |
| 開発日数 | 16日（コミットがある日） |
| 対応macOS | 15.0+ |
| 言語 | Swift 6 / SwiftUI |
| ローカライズ | 日本語・英語 |
| 配信チャネル | App Store / Homebrew / DMG |

---

## 12. 今後

- スニペット機能の再導入（よりシンプルな形で）
- プレビュー機能
- ただし重くならない程度に

---

## 記事タイトル

「5時間で作ったMacアプリをHomebrewで公開した話」
