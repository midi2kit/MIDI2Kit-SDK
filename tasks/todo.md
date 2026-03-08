# MIDI2Kit 開発計画 — 2026年3月

## チーム編成

| メンバー | 担当 | 状態 |
|---------|------|------|
| **suke** | Profile Configuration 設計・実装 | 🔧 Phase 1 完了 → Phase 2 待ち |
| **kaku** | midi2kit.github.io 広報ページ構築 | ✅ ブログデプロイ完了 (midi2kit.dev/blog/) |
| **yashichi** | DocC ドキュメント導入 | ✅ 計画・テンプレート完了 → 統合待ち |

---

## suke: Profile Configuration

### 設計フェーズ
- [x] MIDI-CI v1.2 Profile Configuration 仕様の精読
- [x] 既存 MIDI2CI / MIDI2PE モジュールとの整合性分析
- [x] Profile Configuration メッセージ型の設計
- [x] MIDI2Profile モジュール or MIDI2CI 統合の判断 → **新モジュール MIDI2Profile に決定**
- [x] High-Level API (MIDI2ProfileClient) の設計
- [x] 設計ドキュメント作成 → `docs/profile-configuration-design.md`

### 設計結果サマリー
- 全11メッセージタイプ (Sub-ID#2: 0x20-0x29, 0x2F)
- ProfileID: 5バイト (Byte1=0x7E: Standard Defined)
- ProfileManager (actor, Initiator), ProfileResponder (actor, Responder)
- 5フェーズ実装計画 (合計 9-12日)
- テスト目標: 80+

### 実装フェーズ (次のアクション)
- [x] Phase 1: 基盤型 (ProfileID, ProfileAddress, メッセージ型) — `/tmp/MIDI2Kit-dev` に実装済み、全705テスト合格
- [ ] Phase 2: ProfileManager (Initiator側)
- [ ] Phase 3: ProfileResponder (Responder側)
- [ ] Phase 4: MIDI2Client / MIDI2ResponderClient への統合
- [ ] Phase 5: Built-in Profiles + テスト仕上げ

---

## kaku: 広報ページ (midi2kit.github.io)

### 基盤構築
- [x] 静的サイト技術選定 → ビルドツール不要の HTML + CSS + JS
- [x] ランディングページ作成
  - [x] ヘッドライン: "MIDI 2.0 for Swift"
  - [x] Features セクション (4カラムグリッド)
  - [x] コード例 (タブ切替3パターン: Discovery/PE/Responder)
  - [x] アーキテクチャ図
  - [x] 対応プラットフォーム表
  - [x] Get Started (3ステップ)
- [x] SEO 最適化 (OGP, JSON-LD, sitemap.xml)

### 成果物
- `docs/website/index.html` (381行)
- `docs/website/css/style.css` (780行, ダークテーマ, #6C5CE7 アクセント)
- `docs/website/js/main.js` (51行)
- `docs/website/sitemap.xml`

### 次のアクション
- [x] midi2kit org に GitHub Pages リポジトリ作成 → 既存 (`midi2kit/midi2kit.github.io`, カスタムドメイン `midi2kit.dev`)
- [x] デプロイ準備
  - [x] GitHub Actions ワークフロー作成 (`docs/website/.github/workflows/deploy-pages.yml`)
  - [x] CNAME ファイル作成 (`midi2kit.dev`)
  - [x] robots.txt 作成
  - [x] 404.html 作成
  - [x] sitemap.xml にブログページ追加
  - [x] OGP/canonical URL をカスタムドメイン (`midi2kit.dev`) に統一
- [x] デプロイ実行 → ブログセクションを本番デザインに移植し `midi2kit.github.io` に push 完了 (2026-03-08)
  - ブログ一覧 (`blog/index.html`) + 初回記事をカスタムドメインのデザイン (Inter, 青アクセント) に統一
  - トップページのナビ・フッターに Blog リンク追加
  - HTML バリデーション CI ワークフロー追加
  - デプロイスクリプト: `scripts/deploy-website.sh`
- [ ] OG画像 (`images/og-image.png`) の作成・配置
- [x] ブログセクション構築
- [x] 初回記事: 「Introducing MIDI2Kit — MIDI 2.0 for Swift」
- [x] ランディングページにBlogリンク追加

---

## yashichi: DocC ドキュメント

### 基盤構築
- [x] DocC 導入計画書作成 → `docs/docc-plan.md`
- [x] 統合手順書作成 → `docs/docc-integration-guide.md`
- [x] 全5モジュールの DocC カタログテンプレート作成 (10ファイル)

### テンプレート成果物 (`docs/docc-templates/`)
- [x] MIDI2Kit.docc/ (5ファイル: 概要, GettingStarted, 3チュートリアル)
- [x] MIDI2Core.docc/ (2ファイル: 概要, UMPConversion)
- [x] MIDI2CI.docc/ (1ファイル: 概要)
- [x] MIDI2PE.docc/ (1ファイル: 概要)
- [x] MIDI2Transport.docc/ (1ファイル: 概要)

### 開発リポジトリ統合準備 (2026-03-08 実施)
- [x] 開発リポジトリ (hakaru/MIDI2Kit) のコードベース分析
- [x] swift-docc-plugin が Package.swift に追加済みであることを確認 (from: "1.0.0")
- [x] 既存 Documentation.docc (集約型) の存在を確認
- [x] テンプレートのシンボル名を実コードの public API と照合・修正
  - MIDI2Kit.docc: ClientPreset, DestinationStrategy, WarmUpStrategy, MIDI2Error 等追加
  - MIDI2Core.docc: UMP Message 型群、FlexData 型群、JSON ユーティリティ等追加
  - MIDI2CI.docc: ProcessInquiry 関連型、CIRole 追加
  - MIDI2PE.docc: Batch 操作、Validation、Vendor 拡張、Conditional 操作等追加
  - MIDI2Transport.docc: LoopbackTransport, ConnectionPolicy, VirtualEndpointCapable 等追加
- [x] docc-plan.md を現状に合わせて更新 (完了済み項目の反映、MIDI2Profile の言及追加)
- [x] docc-integration-guide.md を現状に合わせて更新 (既存カタログとの統合手順に変更)

### 次のアクション
- [ ] swift-docc-plugin のバージョンを 1.4.3 に更新
- [ ] 既存 MIDI2Kit.md の Topics セクションを更新済みテンプレートで置換
- [ ] チュートリアル用コードスニペット (Resources/) を作成
- [ ] DocC ビルドで未解決シンボル警告を検証・解消
- [ ] GitHub Actions で DocC 自動生成
- [ ] GitHub Pages へデプロイ (midi2kit.github.io/docs/)

---

## 共通タスク
- [ ] Swift Package Index への登録
- [ ] GitHub Topics 最適化 (midi, midi2, swift, coremidi, ump, midi-ci)
- [ ] GitHub Discussions 有効化
- [ ] README.md 簡潔化
