# Clipnyx

macOS メニューバーに常駐する軽量クリップボード履歴マネージャー。

## 機能

- **クリップボード履歴の自動記録** — コピーした内容を自動で保存（最大500件）
- **ホットキーで即座にアクセス** — ⌘⇧V（カスタマイズ可能）で履歴パネルを表示
- **数字キーでダイレクト貼り付け** — 1〜9キーで素早く選択＆ペースト
- **11カテゴリの自動分類** — テキスト、画像、PDF、URL、HTML、CSV、ソースコード、カラーなど
- **カテゴリフィルタ＆テキスト検索** — 目的の履歴をすばやく発見
- **カーソル位置に直接ペースト** — Accessibility API でフォーカス要素を検出
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
| サンドボックス | あり | なし |
| ダイレクトペースト | — | ✓（Accessibility API） |
| 自動アップデート | App Store 経由 | `brew upgrade` |

## 権限（Full 版のみ）

- **アクセシビリティ** — ダイレクトペーストとカーソル位置検出に必要

## プライバシーポリシー

[プライバシーポリシー](https://sawasige.github.io/clipnyx/privacy-policy.html)

## ライセンス

All rights reserved.
