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
│   ├── FavoriteFolder.swift      # お気に入りフォルダモデル
│   └── PasteboardRepresentation.swift # ペーストボードデータ表現
├── Views/
│   ├── PopupContentView.swift    # ペーストパネル（フォルダチップ切り替え対応）
│   ├── MenuBarView.swift         # メニューバー（.menu スタイル）
│   ├── FavoriteManagerView.swift # コレクション画面（NavigationSplitView）
│   ├── FavoriteEditorWindow.swift # お気に入り編集・新規テキスト追加ウィンドウ
│   ├── FavoriteRegistrationView.swift # お気に入り登録ポップオーバー
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

## CI/CD
- **リリース**: `gh workflow run "Release Full (Homebrew)" --ref main` を実行するだけで両エディションがデプロイされる
  - Full 版: GitHub Actions でビルド → 署名 → 公証 → DMG → appcast.xml 更新 → Homebrew Cask 更新 → タグ `v*` 作成
  - App Store 版: 上記タグ作成が Xcode Cloud をトリガー → Archive → TestFlight アップロード
- **ci_scripts/ci_post_clone.sh**: タグからバージョン抽出して pbxproj を更新
- **Fastlane**: `fastlane metadata` でApp Storeメタデータ・スクリーンショットをアップロード
- **GitHub Pages**: `docs/` 配下を自動デプロイ（ランディングページ、プライバシーポリシー、appcast.xml）

## コミット規約
- コミットメッセージは日本語
- Co-Authored-By は付けない
- main ブランチに直接コミットしない。必ずブランチを切って PR を作成する
- PR マージ時は `gh pr merge --delete-branch` を使う
