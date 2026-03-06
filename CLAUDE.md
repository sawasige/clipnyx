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
│   ├── ClipboardManager.swift    # クリップボード監視・履歴管理
│   ├── HotKeyManager.swift       # グローバルホットキー（Carbon API）
│   └── PopupPanelController.swift # ホットキーパネル表示制御
├── Models/
│   ├── ClipboardItem.swift       # 履歴アイテムモデル
│   ├── ClipboardContentCategory.swift # 11カテゴリ分類
│   └── PasteboardRepresentation.swift # ペーストボードデータ表現
├── Views/
│   ├── MenuBarView.swift         # メニューバーポップアップUI
│   ├── PopupContentView.swift    # ホットキーパネルUI
│   ├── SettingsView.swift        # 設定画面
│   └── ItemDetailView.swift      # アイテム詳細ポップオーバー
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

## ビルド構成
- **Debug / Release**: App Store 版（サンドボックス、Sparkle なし）
- **Debug-Full / Release-Full**: Full 版（サンドボックス + Sparkle）
- `ENABLE_SPARKLE` コンパイルフラグで Sparkle 関連コードを分岐

## CI/CD
- **Xcode Cloud**: タグ `v*` プッシュ → Archive → TestFlight アップロード
- **GitHub Actions** (`release-full.yml`): Full 版ビルド → 署名 → 公証 → DMG → appcast.xml 更新 → Homebrew Cask 更新
- **ci_scripts/ci_post_clone.sh**: タグからバージョン抽出して pbxproj を更新
- **Fastlane**: `fastlane metadata` でApp Storeメタデータ・スクリーンショットをアップロード
- **GitHub Pages**: `docs/` 配下を自動デプロイ（ランディングページ、プライバシーポリシー、appcast.xml）

## コミット規約
- コミットメッセージは日本語
- Co-Authored-By は付けない
- main ブランチに直接コミットしない。必ずブランチを切って PR を作成する
- PR マージ時は `gh pr merge --delete-branch` を使う
