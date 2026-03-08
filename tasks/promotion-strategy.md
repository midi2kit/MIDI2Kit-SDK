# MIDI2Kit 普及・啓蒙戦略レポート

**作成日**: 2026-03-08
**対象**: MIDI2Kit v1.0.17 / Swift MIDI 2.0 ライブラリ

---

## エグゼクティブサマリー

MIDI 2.0 は2026年現在、Windows MIDI Services の正式リリース、NAMM 2026 での Piano Profile 採択、Roland・KORG 等の製品展開により、実用段階に入りつつある。一方、Apple platforms 向けの MIDI 2.0 高レベルライブラリは MIDIKit（MIDI 1.0 中心）を除けば事実上 MIDI2Kit のみであり、MIDI-CI / Property Exchange をフルサポートする唯一の Swift ライブラリとして大きな差別化要因を持つ。

この戦略では、MIDI2Kit を「Apple platforms における MIDI 2.0 開発の標準ライブラリ」として確立するための6つの柱を提案する。

---

## 1. ドキュメント戦略

### 1.1 現状分析

| ドキュメント | 状態 | 課題 |
|---|---|---|
| README.md | 充実（466行） | 情報過多、初心者が迷う |
| API.md | 詳細（1,200行超） | DocC 未対応、検索不可 |
| Architecture.md | 優れた図解 | 利用者向けでなく内部向け |
| CHANGELOG.md | 完備 | - |

### 1.2 改善計画

#### Phase 1: README のリファクタリング（優先度: 高）

```
README.md（簡潔化）
├── 30秒でわかる MIDI2Kit（What / Why / Quick Start）
├── インストール方法
├── 3つのコード例（Discovery / PE Get / Responder）
├── リンク集（ドキュメント、チュートリアル、サンプル）
└── バッジ（Swift 6、テスト数、ライセンス、Swift Package Index）
```

**方針**: 現在の README は API リファレンスと混在しているため、「5分以内に動くコードを書ける」体験に絞る。詳細は DocC や別ドキュメントに委譲。

#### Phase 2: DocC 導入（優先度: 高）

[DocC](https://www.swift.org/documentation/docc/) を全モジュールに導入し、GitHub Pages で公開する。

```
Sources/
├── MIDI2Kit/
│   ├── Documentation.docc/
│   │   ├── MIDI2Kit.md              （モジュール概要）
│   │   ├── GettingStarted.md        （最初のステップ）
│   │   ├── DeviceDiscovery.tutorial  （インタラクティブ）
│   │   ├── PropertyExchange.tutorial
│   │   ├── CreatingResponder.tutorial
│   │   └── Resources/               （画像、動画）
│   └── ...
├── MIDI2Core/
│   ├── Documentation.docc/
│   │   ├── MIDI2Core.md
│   │   └── UMPConversion.md
│   └── ...
```

**実装手順**:
1. `swift-docc-plugin` を Package.swift に追加
2. 各モジュールの Documentation.docc カタログを作成
3. GitHub Actions で `swift package generate-documentation` を実行
4. 生成物を GitHub Pages にデプロイ

#### Phase 3: チュートリアル構成（優先度: 中）

| チュートリアル | 対象者 | 内容 |
|---|---|---|
| Getting Started | 初心者 | SPM追加 → Discovery → DeviceInfo取得 |
| Property Exchange Deep Dive | 中級者 | PE GET/SET、バッチ操作、パイプライン |
| Building a Responder | 中級者 | MIDI2ResponderClient でデバイスを作る |
| KORG Optimization | KORG ユーザー | プリセット、X-Resource、最適化 |
| UMP Conversion | 上級者 | SysEx変換、RPN/NRPN、アセンブラ |
| Migration from CoreMIDI | 移行者 | CoreMIDI 直接利用からの移行パス |

#### Phase 4: 多言語対応（優先度: 低〜中）

- **英語**: 全ドキュメントの基本言語（国際リーチのため）
- **日本語**: README_ja.md、主要チュートリアルの翻訳版
- DocC の多言語対応は現状限定的なため、日本語版は別途 Zenn Book として展開

### 1.3 参考: 成功しているライブラリのドキュメント構成

- [MIDIKit](https://github.com/orchetect/MIDIKit): DocC 採用、Swift Package Index 連携
- [Swift Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture): チュートリアル充実
- [Vapor](https://docs.vapor.codes): 独立ドキュメントサイト

---

## 2. 広報ページ（GitHub Pages）

### 2.1 サイト構成案

`midi2kit.github.io`（midi2kit org の GitHub Pages）

```
/                       → ランディングページ
/docs/                  → DocC 生成ドキュメント
/blog/                  → リリースノート、技術記事
/examples/              → サンプルコード・デモ
/community/             → コミュニティリンク
```

### 2.2 ランディングページ設計

**ファーストビュー**:
- ヘッドライン: "MIDI 2.0 for Swift"
- サブヘッドライン: "Device Discovery, Property Exchange, and UMP — all in async/await"
- CTA: "Get Started" / "View on GitHub"
- コードスニペット（5行の Discovery 例）

**セクション構成**:
1. **Features** — アイコン付き4カラムグリッド（Discovery、PE、UMP、Responder）
2. **Code Example** — タブ切替で3つのユースケース
3. **Architecture** — モジュール図（Architecture.md から流用）
4. **Compatibility** — 対応プラットフォーム・バージョン表
5. **Trusted by** — 利用プロジェクト・実績（KORG Module Pro での実証等）
6. **Get Started** — 3ステップインストールガイド

**技術スタック**: 静的サイトジェネレーター（Hugo / Jekyll / Astro）。DocC の出力を `/docs/` にホスト。

### 2.3 SEO 戦略

| キーワード | 検索意図 | 対応コンテンツ |
|---|---|---|
| `Swift MIDI 2.0` | ライブラリ探し | ランディングページ |
| `CoreMIDI MIDI 2.0 Swift` | 技術調査 | Migration ガイド |
| `MIDI-CI Swift` | 機能調査 | Discovery チュートリアル |
| `Property Exchange iOS` | 機能実装 | PE チュートリアル |
| `MIDI 2.0 library Apple` | 比較検討 | Features ページ |
| `UMP Swift` | 実装参考 | UMP Conversion ガイド |

**施策**:
- Swift Package Index への登録（Apple 公式スポンサー、最大の発見経路）
- GitHub Topics の最適化（`midi`, `midi2`, `swift`, `coremidi`, `ump`, `midi-ci`）
- Open Graph メタタグの最適化
- README にバッジ・リンクを充実

### 2.4 ブログ/コンテンツ計画

| 時期 | テーマ | 配信先 |
|---|---|---|
| 初月 | MIDI2Kit とは何か — Apple platforms の MIDI 2.0 開発を変える | ブログ、Zenn |
| 初月 | MIDI 2.0 入門: MIDI-CI Discovery を Swift で実装する | Qiita、Zenn |
| 2ヶ月目 | Property Exchange で楽器のパラメータを読み書きする | Qiita、Zenn |
| 2ヶ月目 | MIDIKit vs MIDI2Kit — 目的別ライブラリ選択ガイド | ブログ |
| 3ヶ月目 | KORG Module Pro との BLE MIDI 2.0 通信の裏側 | Zenn |
| 3ヶ月目 | visionOS で MIDI 2.0 デバイスを可視化する | ブログ、Zenn |
| 四半期ごと | リリースノート + ロードマップ更新 | ブログ |

---

## 3. コミュニティ構築

### 3.1 GitHub Discussions 活用

midi2kit/MIDI2Kit-SDK リポジトリで GitHub Discussions を有効化。

| カテゴリ | 用途 |
|---|---|
| Announcements | リリース、ロードマップ |
| Q&A | 使い方の質問 |
| Ideas | 機能リクエスト |
| Show and Tell | ユーザーの作品紹介 |
| MIDI 2.0 General | MIDI 2.0 全般の議論 |

**運用方針**:
- Issue は「バグ報告」と「具体的な機能要望」に限定
- 質問や議論は Discussions へ誘導
- テンプレートで明確に分離

### 3.2 SNS 戦略

| プラットフォーム | ターゲット | 投稿内容 | 頻度 |
|---|---|---|---|
| **X (Twitter)** | iOS/macOS 開発者、音楽テック | リリース、Tips、コードスニペット | 週2-3回 |
| **Bluesky** | テック系アーリーアダプター | 同上 | 週1-2回 |
| **Mastodon** (iosdev.space) | OSS 開発者 | 技術的な deep dive | 週1回 |

**ハッシュタグ**: `#MIDI2Kit` `#MIDI2` `#SwiftLang` `#iOSDev` `#CoreMIDI` `#MusicTech`

**投稿テンプレート**:
- リリース告知: 新機能のコード例 + リリースノートリンク
- Tips: 1つの機能にフォーカスした短いコード例
- コミュニティ: ユーザーの作品紹介、MIDI 2.0 ニュースのシェア

### 3.3 日本語技術記事

| プラットフォーム | 記事タイプ | 狙い |
|---|---|---|
| **Zenn** | Book（連載）: 「Swift で始める MIDI 2.0 開発」 | 体系的な学習コンテンツ |
| **Zenn** | 個別記事: 実装 Tips、トラブルシュート | 検索流入 |
| **Qiita** | 入門記事、比較記事 | 幅広いリーチ |
| **note** | 開発ストーリー、MIDI 2.0 の未来 | 非開発者へのリーチ |

**Zenn Book 構成案**: 「Swift で始める MIDI 2.0 開発」

1. MIDI 2.0 とは — MIDI 1.0 からの進化
2. MIDI2Kit のセットアップ
3. デバイス探索 (MIDI-CI Discovery)
4. Property Exchange でデバイス情報を取得
5. UMP メッセージの変換
6. Responder を作る — 自分のデバイスを公開
7. KORG デバイスとの連携
8. visionOS での MIDI 2.0 活用
9. トラブルシューティング

### 3.4 MIDI 2.0 コミュニティへのアウトリーチ

| コミュニティ | アクション |
|---|---|
| [midi2.dev](https://midi2.dev/) | ライブラリとして掲載申請。midi2-dev GitHub org のメンバーに連絡 |
| [MIDI.org](https://midi.org/) | 開発者リソースページへの掲載依頼 |
| MIDI Association Forum | MIDI2Kit の紹介投稿 |
| [KVR Audio](https://www.kvraudio.com/) | ニュース投稿・フォーラム参加 |
| r/swift, r/iOSProgramming | リリース告知・質問への回答 |
| r/midi, r/synthesizers | MIDI 2.0 関連の技術共有 |
| Swift Forums | Swift MIDI 関連の質問に MIDI2Kit で回答 |

---

## 4. サンプル・デモ

### 4.1 サンプルアプリ構成

#### iOS: MIDI 2.0 Device Explorer

```
MIDI2Explorer/
├── App/
│   ├── DeviceListView.swift      — 発見されたデバイス一覧
│   ├── DeviceDetailView.swift    — DeviceInfo、ResourceList 表示
│   ├── PropertyBrowserView.swift — PE リソースの閲覧・編集
│   └── UMPMonitorView.swift      — リアルタイム UMP メッセージ表示
├── Models/
└── README.md
```

**特徴**: SwiftUI、最小限のコードで MIDI2Kit の全機能をデモ。App Store への無料配布も検討。

#### macOS: MIDI 2.0 Monitor

```
MIDI2Monitor/
├── App/
│   ├── SplitView — デバイスツリー + 詳細パネル
│   ├── PacketLogView.swift       — SysEx パケットログ（MIDITracer 連携）
│   ├── PEInspectorView.swift     — PE リクエスト/レスポンスの可視化
│   └── ConnectionDiagView.swift  — 接続診断ダッシュボード
└── README.md
```

**特徴**: MIDI 2.0 開発者向けの診断ツール。MIDI2.0Workbench の Apple platform 版的位置づけ。

#### visionOS: Spatial MIDI Experience

```
MIDI2Spatial/
├── App/
│   ├── SpatialDeviceView.swift   — 3D 空間にデバイスを配置
│   ├── ParameterOrbView.swift    — PE パラメータを球体で可視化
│   └── GestureControlView.swift  — ハンドジェスチャで PE SET
└── README.md
```

**特徴**: visionOS のデモとして話題性が高い。WWDC 投稿やプレス向けに訴求力がある。

### 4.2 Swift Playgrounds パッケージ

```
MIDI2Kit-Playground.swiftpm/
├── Chapter 1: Hello MIDI 2.0
│   ├── 01-Discovery.swift
│   └── 02-DeviceInfo.swift
├── Chapter 2: Property Exchange
│   ├── 01-GetResource.swift
│   └── 02-SetResource.swift
└── Chapter 3: Building a Responder
    └── 01-SimpleResponder.swift
```

**対象**: iPad の Swift Playgrounds で実行可能。教育向け。

### 4.3 最小サンプル集

```
Examples/
├── BasicDiscovery/          — 最小の Discovery サンプル（20行）
├── PropertyExchangeGet/     — PE GET の基本例
├── BatchSetExample/         — バッチ SET の例
├── ResponderExample/        — Responder 作成例
├── UMPConversion/           — UMP 変換例
└── KORGIntegration/         — KORG 最適化例
```

各サンプルは独立した SPM パッケージとし、`swift run` で即実行可能に。

---

## 5. 開発者獲得戦略

### 5.1 ターゲット開発者層

| 層 | プロファイル | 人数規模 | 獲得難易度 | 価値 |
|---|---|---|---|---|
| **Tier 1** | iOS/macOS 音楽アプリ開発者 | 数百人 | 中 | 最高（直接的なユーザー） |
| **Tier 2** | 楽器メーカーのソフト開発者 | 数十チーム | 高 | 最高（製品採用） |
| **Tier 3** | CoreMIDI 利用中の一般開発者 | 数千人 | 低 | 高（移行需要） |
| **Tier 4** | Swift 学習者・MIDI 初心者 | 数万人 | 低 | 中（コミュニティ拡大） |
| **Tier 5** | DAW/プラグイン開発者 | 数百チーム | 高 | 高（エコシステム） |

### 5.2 オンボーディング体験の設計

**目標**: 「5分以内に最初の Discovery 成功」

```
Step 1 (30秒): SPM で追加
  → Package.swift に1行追加 or Xcode の Add Package

Step 2 (2分): Quick Start をコピペ
  → README の Quick Start コード（10行）をそのまま実行

Step 3 (2分): 結果確認
  → コンソールに発見されたデバイスが表示される
  → 「Found: KORG Module Pro」等

Step 4 (次のステップ): チュートリアルへ誘導
  → "Next: Read device properties with Property Exchange →"
```

**重要**: XCFramework（バイナリ配布）と ソースコード配布の両方を維持。
- XCFramework: ビルド時間ゼロ、CI/CD に最適
- ソースコード: デバッグ、学習、カスタマイズに最適

### 5.3 パッケージ導入の簡素化

**現状の課題**:
- SPM URL が `hakaru/MIDI2Kit`（個人アカウント）
- SDK 配布は `midi2kit/MIDI2Kit-SDK`（org）
- 混乱の可能性

**改善案**:
1. メインの SPM URL を `midi2kit/MIDI2Kit-SDK` に統一（README で明示）
2. `hakaru/MIDI2Kit` からは redirect / 案内を設置
3. Swift Package Index への登録を `midi2kit/MIDI2Kit-SDK` で行う

### 5.4 フィードバックループ

```
ユーザー → GitHub Discussions (Q&A)
         → GitHub Issues (バグ、機能要望)
         → SNS メンション
              ↓
メンテナー → トリアージ（24h以内の初回応答目標）
           → ラベル付け、マイルストーン設定
           → 月次ロードマップ更新
              ↓
リリース → CHANGELOG + ブログ + SNS 告知
         → フィードバック提供者への個別通知
```

### 5.5 発見経路の最大化

| 経路 | アクション | 優先度 |
|---|---|---|
| **Swift Package Index** | 登録、メタデータ最適化 | 最高 |
| **GitHub Topics** | `midi`, `midi2`, `swift`, `coremidi`, `ump` | 高 |
| **MIDI.org Resources** | 掲載申請 | 高 |
| **midi2.dev** | ライブラリとして掲載 | 高 |
| **Awesome Swift** リスト | PR 提出 | 中 |
| **Awesome MIDI** リスト | PR 提出 | 中 |
| **Google 検索** | SEO 最適化（ブログ、ドキュメント） | 中 |
| **Swift Forums** | 質問への回答で自然に紹介 | 中 |

---

## 6. パートナーシップ・連携

### 6.1 楽器メーカーとの連携

| メーカー | 関係性 | アクション |
|---|---|---|
| **KORG** | 既に最適化実装済み | 公式サポートの打診、共同テスト、フィードバック提供 |
| **Roland** | AMEI MIDI 2.0 WG 議長企業 | MIDI2Kit での Roland デバイスサポート検証 |
| **Yamaha** | MIDI 2.0 積極推進 | Yamaha デバイスでの動作検証、最適化 |
| **Native Instruments** | コントローラー大手 | NI デバイスとの互換性テスト |

**アプローチ**:
- KORG: 既存の最適化実績をベースに、公式パートナーシップ or テストフィードバック関係を構築
- Roland: NAMM 2026 での Roland の MIDI 2.0 プレゼンテーション（AMEI WG 議長 Takayuki Tomisawa 氏）をフックに接触
- 全般: MIDI2Kit のサンプルアプリで各社デバイスの動作を実証

### 6.2 DAW / 音楽アプリ開発者へのアプローチ

| ターゲット | アプローチ |
|---|---|
| Logic Pro / GarageBand | Apple 内部での認知（WWDC Labs 等） |
| Cubasis (Steinberg) | iOS DAW として MIDI 2.0 PE 統合の提案 |
| AUM / AudioBus 開発者 | 個人/小規模開発者向けサポート |
| indie iOS 音楽アプリ | GitHub Discussions、SNS でのコミュニティ支援 |

### 6.3 教育機関との連携

| 対象 | アクション |
|---|---|
| 大学（音楽工学、情報学） | MIDI 2.0 の教材としての提案、Swift Playgrounds 活用 |
| Apple Developer Academy | カリキュラム素材の提供 |
| 専門学校（DTM、音響） | 日本語チュートリアルの提供 |

**参考**: MIT の Julian Hamelberg 氏による [MIDI 2.0 の論文](https://dspace.mit.edu/bitstream/handle/1721.1/151396/hamelberg-jshx-meng-eecs-2023-thesis.pdf) が存在。学術界での MIDI 2.0 への関心は高まっている。

### 6.4 MMA / AMEI との関係構築

| 組織 | 現状 | アクション |
|---|---|---|
| **MMA (MIDI Manufacturers Association)** | 仕様策定組織 | 開発者メンバーとして参加検討 |
| **AMEI (音楽電子事業協会)** | 日本のMIDI標準化組織 | MIDI 2.0 WG へのオブザーバー参加 |
| **midi2.dev** | OSS コミュニティ | ライブラリの掲載、共同プロジェクト |

**AMEI の動向**:
- AMEI は MIDI 2.0 仕様を無料公開、OSS 開発を積極支援
- Windows 向け USB MIDI 2.0 ドライバの開発を資金援助した実績
- Apple platforms 向けの OSS 支援にも関心がある可能性

**midi2.dev との連携**:
- 現在 C++ ライブラリが中心（AM_MIDI2.0Lib、ni-midi2 等）
- Swift / Apple platforms 向けは空白地帯
- MIDI2Kit を midi2-dev org の公式 Swift ライブラリとして提案

---

## 7. 競合分析と差別化

### 7.1 既存ライブラリとの比較

| | MIDI2Kit | MIDIKit | libremidi | AM_MIDI2.0Lib |
|---|---|---|---|---|
| **言語** | Swift | Swift | C++ | C++ |
| **MIDI 2.0 UMP** | Full | Basic | Full | Full |
| **MIDI-CI Discovery** | Full | - | - | Partial |
| **Property Exchange** | Full (GET/SET/Subscribe) | - | - | - |
| **Responder API** | Full | - | - | Partial |
| **async/await** | Native | - | - | - |
| **Swift 6** | Full | Partial | - | - |
| **KORG 最適化** | 99% 高速化 | - | - | - |
| **テスト数** | 602 | 不明 | 不明 | 不明 |
| **visionOS** | 対応 | 対応 | - | - |

### 7.2 MIDI2Kit の明確な差別化ポイント

1. **唯一の Swift MIDI-CI / PE フルサポート** — MIDIKit は MIDI I/O に特化、MIDI2Kit は MIDI 2.0 の高レベルプロトコルをカバー
2. **async/await ネイティブ** — Swift Concurrency を前提とした設計
3. **実機検証済み** — KORG Module Pro での実証、BLE MIDI 対応
4. **Responder API** — デバイス側の実装も可能（双方向）
5. **602 テスト** — 信頼性の証明

### 7.3 ポジショニングメッセージ

> **MIDIKit**: MIDI I/O のモダンな Swift ラッパー（MIDI 1.0 中心、I/O レイヤー）
> **MIDI2Kit**: MIDI 2.0 プロトコルの完全実装（Discovery、PE、Responder）

**共存戦略**: MIDIKit と競合ではなく補完関係として位置づける。MIDIKit は MIDI I/O 層、MIDI2Kit は MIDI 2.0 プロトコル層。将来的に MIDIKit のトランスポート上で MIDI2Kit を利用する統合も可能。

---

## 8. 実行ロードマップ

### Phase 1: 基盤整備（1-2ヶ月目）

- [ ] Swift Package Index への登録
- [ ] GitHub Topics の最適化
- [ ] GitHub Discussions の有効化・カテゴリ設定
- [ ] README のリファクタリング（簡潔化）
- [ ] DocC の導入（MIDI2Kit モジュールから開始）
- [ ] SNS アカウント開設（X: @midi2kit）
- [ ] midi2.dev への掲載申請

### Phase 2: コンテンツ拡充（3-4ヶ月目）

- [ ] DocC チュートリアル作成（Getting Started、Discovery、PE）
- [ ] GitHub Pages サイト構築（ランディングページ + DocC ホスティング）
- [ ] Zenn Book 第1-3章の公開
- [ ] Qiita 入門記事の投稿（2-3本）
- [ ] 最小サンプル集（Examples/）の作成
- [ ] iOS サンプルアプリ「MIDI2 Explorer」の開発開始

### Phase 3: コミュニティ形成（5-6ヶ月目）

- [ ] iOS サンプルアプリのリリース
- [ ] macOS Monitor アプリの開発
- [ ] Zenn Book 完結
- [ ] midi2.dev コミュニティへの積極参加
- [ ] MIDI Association への開発者登録
- [ ] KORG への公式フィードバック提供

### Phase 4: エコシステム拡大（7-12ヶ月目）

- [ ] visionOS サンプルの開発
- [ ] Swift Playgrounds パッケージの作成
- [ ] AMEI / MMA との関係構築
- [ ] 他の楽器メーカーデバイスでの検証・最適化
- [ ] WWDC 関連の発表・投稿（MIDI 2.0 + visionOS）
- [ ] カンファレンスでの発表（try! Swift、iOSDC 等）

---

## 9. KPI（成果指標）

| 指標 | 3ヶ月目標 | 6ヶ月目標 | 12ヶ月目標 |
|---|---|---|---|
| GitHub Stars | 50 | 150 | 500 |
| Swift Package Index DL | 計測開始 | 月100+ | 月500+ |
| GitHub Discussions 投稿数 | 10 | 50 | 200 |
| Zenn/Qiita 記事数 | 5 | 15 | 30 |
| X フォロワー | 100 | 300 | 1,000 |
| コントリビューター数 | 1 | 3 | 10 |
| 採用プロジェクト数 | 2 | 10 | 30 |

---

## 10. リスクと対策

| リスク | 影響 | 対策 |
|---|---|---|
| Apple が CoreMIDI に MIDI-CI/PE 高レベル API を追加 | 高 | MIDI2Kit の低レベル制御・カスタマイズ性で差別化。Apple API のラッパーとして進化 |
| MIDIKit が MIDI 2.0 プロトコル層を拡充 | 中 | 先行優位を維持。PE/Responder の深い実装で差別化 |
| MIDI 2.0 の普及が遅れる | 中 | MIDI 1.0 → 2.0 ブリッジ機能の強化。UMP 変換層の充実 |
| メンテナンスのバーンアウト | 高 | コントリビューターの獲得。ドキュメント・テストの充実で参入障壁を下げる |
| バイナリ配布の制約 | 低 | ソースコード配布の併用を維持 |

---

## Sources

- [midi2.dev - MIDI 2.0 Developer Community](https://midi2.dev/)
- [MIDI2.dev GitHub Organization](https://github.com/midi2-dev)
- [MIDI.org - MIDI 2.0 Resources for Developers](https://midi.org/curated-midi-2-0-resources-for-developers)
- [Microsoft Windows MIDI Services](https://microsoft.github.io/MIDI/overview/)
- [MIDIKit - Swift CoreMIDI Wrapper](https://github.com/orchetect/MIDIKit)
- [Swift Package Index](https://swiftpackageindex.com/)
- [Swift Package Index - Apple Sponsorship](https://www.swift.org/blog/swift-package-index-developer-spotlight/)
- [DocC - Swift Documentation](https://www.swift.org/documentation/docc/)
- [Documenting a Swift Framework or Package](https://www.swift.org/documentation/docc/documenting-a-swift-framework-or-package)
- [AMEI MIDI 2.0 Specifications](https://www.amei.or.jp/committee/MIDI2.0.pdf)
- [NAMM 2026 MIDI Wrap Up](https://midi.org/namm-2026-first-wrap-up)
- [Windows MIDI 2.0 Support (The Register)](https://www.theregister.com/2026/02/18/microsoft_makes_sweet_music_with/)
- [MIDI 2.0 Workbench](https://github.com/midi2-dev/MIDI2.0Workbench)
- [libremidi - C++ MIDI Library](https://github.com/celtera/libremidi)
- [AMEI Open Source MIDI 2.0 Driver Funding](https://www.kvraudio.com/focus/amei-to-fund-open-source-midi-2-0-driver-for-windows-56224)
- [MIT MIDI 2.0 Thesis](https://dspace.mit.edu/bitstream/handle/1721.1/151396/hamelberg-jshx-meng-eecs-2023-thesis.pdf)
