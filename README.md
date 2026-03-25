# Clipnyx

macOS メニューバーに常駐する軽量クリップボード履歴マネージャー。

## 機能

- **クリップボード履歴の自動記録** — コピーした内容を自動で保存（最大500件）
- **ホットキーで即座にアクセス** — ⌘⇧V（カスタマイズ可能）で履歴パネルを表示
- **数字キーでダイレクト貼り付け** — 1〜9キーで素早く選択＆ペースト
- **お気に入り＆フォルダ** — よく使うアイテムをお気に入り登録し、ユーザー定義のフォルダで整理。Tab/Shift+Tab でフォルダ切り替え
- **コレクション画面** — 全データを一覧管理。サイドバーで全履歴/お気に入り/フォルダを切り替え、テキスト編集や新規テキスト追加が可能
- **プレーンテキスト変換** — リッチテキスト、HTML、URL等をプレーンテキストに変換
- **11カテゴリの自動分類** — テキスト、画像、PDF、URL、HTML、CSV、ソースコード、カラーなど
- **カテゴリフィルタ＆テキスト検索** — 目的の履歴をすばやく発見
- **画像・PDFのサムネイルプレビュー**
- **完全ローカル保存** — 外部送信なし、プライバシー安全

## 要件

- macOS 15.0 以降

## インストール

### App Store 版

[Mac App Store](https://apps.apple.com/app/clipnyx/id6759652985) からダウンロード

### Full 版（Homebrew / DMG）

```bash
brew install sawasige/clipnyx/clipnyx
```

または [GitHub Releases](https://github.com/sawasige/clipnyx/releases/latest) から DMG をダウンロード

### エディションの違い

| | App Store | Full |
|---|---|---|
| 配布元 | Mac App Store | Homebrew / DMG |
| サンドボックス | あり | あり |
| ダイレクトペースト | ✓ | ✓ |
| 自動アップデート | App Store 経由 | Sparkle / `brew upgrade` |

## プライバシーポリシー

[プライバシーポリシー](https://sawasige.github.io/clipnyx/privacy-policy.html)

## ライセンス

All rights reserved.
