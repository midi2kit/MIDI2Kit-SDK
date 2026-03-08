# MIDI2Kit DocC 導入計画

## 概要

MIDI2Kit に Apple 公式のドキュメント生成ツール DocC を導入し、API リファレンスとチュートリアルを GitHub Pages で公開する。

## 現状 (2026-03-08 確認)

### 完了済み
- `swift-docc-plugin` が Package.swift に追加済み (`from: "1.0.0"`)
- `Sources/MIDI2Kit/Documentation.docc/` に基本的なカタログが配置済み
  - MIDI2Kit.md, GettingStarted.md, BasicConcepts.md
  - 各モジュール説明ページ (MIDI2Core.md, MIDI2CI.md, MIDI2PE.md, MIDI2Transport.md)

### 未完了
- チュートリアル (.tutorial) 未作成
- チュートリアル用コードスニペット (Resources/) 未作成
- GitHub Actions ワークフロー未配置
- GitHub Pages 未設定
- ソースコードのドキュメントコメント整備が部分的

## 1. swift-docc-plugin

開発リポジトリに追加済み。バージョンアップを推奨:

```swift
// 現在: from: "1.0.0"
// 推奨: from: "1.4.3" (最新安定版)
dependencies: [
    .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.4.3")
]
```

> **注意**: `swift-docc-plugin` は開発時のみ使用。SDK 配布パッケージ (MIDI2Kit-SDK) には含めない。

## 2. ディレクトリ構造

### 現在の構造 (集約型)

開発リポジトリでは全モジュールのドキュメントを `Sources/MIDI2Kit/Documentation.docc/` に集約:

```
MIDI2Kit/
├── Package.swift                          (swift-docc-plugin 追加済み)
├── Sources/
│   ├── MIDI2Kit/
│   │   ├── Documentation.docc/            (既存)
│   │   │   ├── MIDI2Kit.md
│   │   │   ├── GettingStarted.md
│   │   │   ├── BasicConcepts.md
│   │   │   ├── MIDI2Core.md
│   │   │   ├── MIDI2CI.md
│   │   │   ├── MIDI2PE.md
│   │   │   └── MIDI2Transport.md
│   │   └── *.swift
│   ├── MIDI2Core/
│   ├── MIDI2CI/
│   ├── MIDI2PE/
│   ├── MIDI2Transport/
│   └── MIDI2Profile/
```

### 推奨最終構造 (分散型)

各モジュールに独自の Documentation.docc を配置する方が DocC のシンボルリンク解決に適している:

```
MIDI2Kit/
├── Package.swift
├── Sources/
│   ├── MIDI2Kit/
│   │   ├── Documentation.docc/
│   │   │   ├── MIDI2Kit.md                (モジュールトップページ)
│   │   │   ├── GettingStarted.md          (入門ガイド)
│   │   │   ├── Tutorials/
│   │   │   │   ├── DeviceDiscovery.tutorial
│   │   │   │   ├── PropertyExchange.tutorial
│   │   │   │   └── CreatingResponder.tutorial
│   │   │   └── Resources/
│   │   │       └── (コードスニペット等)
│   │   └── *.swift
│   ├── MIDI2Core/
│   │   ├── Documentation.docc/
│   │   │   ├── MIDI2Core.md
│   │   │   └── UMPConversion.md
│   │   └── *.swift
│   ├── MIDI2CI/
│   │   ├── Documentation.docc/
│   │   │   └── MIDI2CI.md
│   │   └── *.swift
│   ├── MIDI2PE/
│   │   ├── Documentation.docc/
│   │   │   └── MIDI2PE.md
│   │   └── *.swift
│   └── MIDI2Transport/
│       ├── Documentation.docc/
│       │   └── MIDI2Transport.md
│       └── *.swift
```

> **注意**: 集約型のままでも DocC ビルドは動作する。MIDI2Kit は `@_exported import` で全モジュールを re-export しているため、全シンボルが MIDI2Kit の名前空間で解決される。分散型への移行は Phase 2 で検討する。

## 3. DocC カタログ構成

### MIDI2Kit (メインモジュール)
- **MIDI2Kit.md**: ライブラリ全体の概要、モジュール構成図、Quick Start
- **GettingStarted.md**: インストール → 初期化 → デバイス検出 → PE の流れ
- **BasicConcepts.md**: UMP, MUID, MIDI-CI, PE の基本概念
- **DeviceDiscovery.tutorial**: MIDI-CI デバイス探索のハンズオン
- **PropertyExchange.tutorial**: PE GET/SET のハンズオン
- **CreatingResponder.tutorial**: Responder API でデバイス側を実装

### MIDI2Core (分散型移行時)
- **MIDI2Core.md**: 基盤型 (MUID, DeviceIdentity, Mcoded7) の説明
- **UMPConversion.md**: UMP 変換の概念と使い方ガイド

### MIDI2CI (分散型移行時)
- **MIDI2CI.md**: CIManager, Discovery フロー、メッセージ構造

### MIDI2PE (分散型移行時)
- **MIDI2PE.md**: PE プロトコル、トランザクション管理、サブスクリプション

### MIDI2Transport (分散型移行時)
- **MIDI2Transport.md**: CoreMIDI 抽象化、接続管理、SysEx アセンブリ

## 4. ローカルビルド

```bash
# プレビュー (ブラウザで開く)
swift package --disable-sandbox preview-documentation --target MIDI2Kit

# 静的サイト生成
swift package --disable-sandbox generate-documentation \
    --target MIDI2Kit \
    --output-path ./docs-output \
    --transform-for-static-hosting \
    --hosting-base-path MIDI2Kit
```

### 全モジュール一括生成スクリプト (分散型の場合)

```bash
#!/bin/bash
# scripts/generate-docc.sh
set -euo pipefail

OUTPUT_DIR="./docs-output"
HOSTING_BASE="MIDI2Kit"
TARGETS=("MIDI2Kit" "MIDI2Core" "MIDI2CI" "MIDI2PE" "MIDI2Transport")

rm -rf "$OUTPUT_DIR"

for target in "${TARGETS[@]}"; do
    echo "Generating docs for $target..."
    swift package --disable-sandbox generate-documentation \
        --target "$target" \
        --output-path "$OUTPUT_DIR/$target" \
        --transform-for-static-hosting \
        --hosting-base-path "$HOSTING_BASE/$target"
done

echo "Done. Output: $OUTPUT_DIR/"
```

## 5. GitHub Actions 自動生成・デプロイ

### ワークフロー: `.github/workflows/docc.yml`

```yaml
name: DocC

on:
  push:
    branches: [main]
  release:
    types: [published]

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: "pages"
  cancel-in-progress: true

jobs:
  build:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.2.app

      - name: Generate DocC
        run: |
          swift package --disable-sandbox generate-documentation \
            --target MIDI2Kit \
            --output-path ./docs-output \
            --transform-for-static-hosting \
            --hosting-base-path docs

      - name: Upload Pages artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: ./docs-output

  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
```

## 6. GitHub Pages ホスティング

### 設定手順

1. GitHub リポジトリ → Settings → Pages
2. Source: **GitHub Actions** を選択
3. ワークフロー実行後、以下の URL でアクセス可能:
   - `https://hakaru.github.io/MIDI2Kit/docs/documentation/midi2kit/`

## 7. 注意事項

### binaryTarget との互換性

SDK リポジトリ (MIDI2Kit-SDK) は `binaryTarget` のみのため、DocC は直接生成できない。
DocC は**開発リポジトリ** (hakaru/MIDI2Kit) のソースコードから生成する。

### シンボルリンクの自動生成

DocC はソースコード内の `///` ドキュメントコメントから API リファレンスを自動生成する。
カタログ内の `.md` ファイルは概要・チュートリアル・ガイドのみ管理し、
API の詳細はソースコードのドキュメントコメントに記述する。

### DocC の Topic セクション

各モジュールの `.md` ファイルでは `## Topics` セクションを使い、
シンボルをカテゴリ別にグルーピングする。未指定のシンボルは DocC が自動配置する。

### MIDI2Profile モジュール

開発リポジトリに `Sources/MIDI2Profile/` が存在するが、現時点では `MIDI2Profile.swift` のみの初期段階。
DocC カタログは Profile 機能が成熟した段階で追加する。

## 8. 実施スケジュール (推奨)

| Phase | 内容 | 状態 |
|-------|------|------|
| 1 | swift-docc-plugin 追加 + カタログ配置 | **完了** (バージョンアップ推奨) |
| 2 | モジュール概要ページ作成 | **完了** (シンボル整合は要検証) |
| 3 | ソースコードのドキュメントコメント整備 | 未着手 |
| 4 | チュートリアル 3本作成 | 未着手 |
| 5 | GitHub Actions + Pages 設定 | 未着手 |
| 6 | レビュー・調整 | 未着手 |
