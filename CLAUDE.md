# Clipnyx - Claude Code ガイド

## プロジェクト概要
macOS メニューバー常駐のクリップボード履歴マネージャー。SwiftUI + Swift 6、macOS 15.0+対象。

## ビルド
```
cd Clipnyx
xcodebuild build -scheme Clipnyx -configuration Debug -destination 'platform=macOS' -quiet
```

## プロジェクト構造
```
Clipnyx/Clipnyx/
├── ClipnyxApp.swift              # アプリエントリポイント
├── Managers/
│   ├── ClipboardManager.swift    # クリップボード監視・履歴管理・お気に入り・フォルダ
│   ├── ClipboardStore.swift      # 履歴の永続化（JSON + blob）
│   ├── HotKeyManager.swift       # グローバルホットキー（Carbon API）
│   ├── PopupPanelController.swift # ホットキーパネル表示制御
│   └── UpdateManager.swift       # Sparkle 自動アップデート（Full版のみ）
├── Models/
│   ├── ClipboardItem.swift       # 履歴アイテムモデル（お気に入り・フォルダ情報含む）
│   ├── ClipboardContentCategory.swift # 11カテゴリ分類
│   ├── FavoriteFilter.swift      # 履歴絞り込み（パネルとコレクションで共有）
│   ├── FavoriteFolder.swift      # お気に入りフォルダモデル
│   └── PasteboardRepresentation.swift # ペーストボードデータ表現
├── Views/
│   ├── PopupContentView.swift    # ペーストパネル（フォルダチップ切り替え対応）
│   ├── MenuBarView.swift         # メニューバー（.menu スタイル）
│   ├── FavoriteManagerView.swift # コレクション画面（NavigationSplitView、詳細編集含む）
│   ├── SettingsView.swift        # 設定画面
│   ├── ItemDetailView.swift      # アイテム詳細ポップオーバー
│   └── ItemPreviewContent.swift  # アイテムプレビュー表示
└── Extensions/
    ├── CollectionExtension.swift  # safe subscript
    └── ColorExtension.swift       # Color ユーティリティ
```

## アーキテクチャ
- **@Observable** パターン（Observation framework）を使用
- ClipboardManager が中心。0.5秒間隔で NSPasteboard をポーリング
- 機密・一時データ（`org.nspasteboard.ConcealedType` / `TransientType` 等）は履歴に記録しない
- ホットキーは Carbon `RegisterEventHotKey` で登録（イベント消費のため）
- ペースト: `CGEvent.post` で ⌘V を送信（PostEvent 権限、サンドボックス互換）
- 権限チェック: `CGRequestPostEventAccess()` / `CGPreflightPostEventAccess()`
- 履歴は JSON で `~/Library/Application Support/Clipnyx/` に永続化
- **メニューバー**: `.menu` スタイル。履歴表示、コレクション、一時停止/再開、設定、終了
- **ペーストパネル**: `PopupContentView` がホットキーで表示。クリック → ダイレクトペースト。フォルダチップで Tab/Shift+Tab 切り替え
- **お気に入り・フォルダ**: `ClipboardItem.favoriteFolderId` でフォルダ紐付け。件数制限から除外。ユーザー定義フォルダで整理
- **コレクション画面**: `FavoriteManagerView`（NavigationSplitView）。サイドバー（全履歴/お気に入り/フォルダ）+ アイテム一覧 + 詳細編集。テキスト編集・新規テキスト追加が可能
- **プレーンテキスト変換**: リッチテキスト、HTML、URL等をプレーンテキストに変換可能

## ビルド構成
- **Debug / Release**: App Store 版（サンドボックス、Sparkle なし）
- **Debug-Full / Release-Full**: Full 版（サンドボックス + Sparkle）
- `ENABLE_SPARKLE` コンパイルフラグで Sparkle 関連コードを分岐

## タイポグラフィ規約
- **読むテキストは必ずセマンティックフォントを使う**。固定ピクセル（`.system(size:)`）はテキストに使わない
  - アイテムタイトル・件数: `.headline`
  - セクション見出し: `.subheadline.bold()`
  - 本文・一覧テキスト・編集欄: `.body`（コード/等幅は `.body.monospaced()`）
  - 二次テキスト・名前: `.callout`（強調は `.callout.bold()`）
  - メタ情報（日時・サイズ・ヒント・フィルタチップ等）: `.caption`。**これより小さい「読む文字」は作らない**
- `.system(size:)` の固定ピクセルは **SF Symbols アイコンのサイズ指定のみ**許可（例: ★バッジ `size 7`、ツールバーアイコン `13`/`15`）
- 理由: macOS には iOS のような全体文字サイズ設定が無いが、セマンティック統一により内部の一貫性と macOS 標準サイズへの準拠が得られ、極小文字とバラつきを防げる

## スクリーンショット生成
- `scripts/generate_screenshots.sh` で LP 用（docs/screenshot-*.png）と App Store 用（fastlane/screenshots/）を自動生成
- Debug ビルドの `ScreenshotRenderer`（`--render-screenshots` 起動引数、`#if DEBUG`）がデモデータでパネルとコレクション画面を一瞬実画面に表示し、ScreenCaptureKit で撮影（Liquid Glass 込みの本物の見た目）
- プレビュー用 ClipboardManager は読み取り専用ストアを使うため**実データには一切触れない**
- 初回は実行元（ターミナル）への「画面収録」権限の許可が必要。生成中は画面中央にウィンドウが数秒ずつ表示される
- ライト/ダーク × 日英の全バリアントがコンテナ内 tmp に出力される（履歴パネル + コレクションの2画面）

## CI/CD
- **リリース**: `gh workflow run "Release Full (Homebrew)" --ref main` を実行するだけで両エディションがデプロイされる
  - Full 版: GitHub Actions でビルド → 署名 → 公証 → DMG → appcast.xml 更新 → Homebrew Cask 更新 → タグ `v*` 作成
  - App Store 版: 上記タグ作成が Xcode Cloud をトリガー → Archive → TestFlight アップロード
- **ci_scripts/ci_post_clone.sh**: タグからバージョン抽出して pbxproj を更新
- **Fastlane**: `fastlane metadata` でApp Storeメタデータ・スクリーンショットをアップロード
- **GitHub Pages**: `docs/` 配下を自動デプロイ（ランディングページ、プライバシーポリシー、appcast.xml、changelog）

## リリースノート運用
- リリース前に `RELEASE_NOTES.md` に日本語と英語でリリースノートを記述（`<!-- en -->` で区切る）
- CIが `RELEASE_NOTES.md` を読んで `docs/appcast.xml` の `<description>` に日英で埋め込む
- `docs/changelog.html` が `appcast.xml` を読んでリリース履歴を動的表示（日英切り替え対応）
- ランディングページのフッターから changelog.html にリンク

## コミット規約
- コミットメッセージは日本語
- Co-Authored-By は付けない
- コミット・PR 本文に AI が作成した旨の表記を入れない（「Generated with Claude Code」等のフッター禁止）
- main ブランチに直接コミットしない。必ずブランチを切って PR を作成する
- PR マージ時は `gh pr merge --delete-branch` を使う
