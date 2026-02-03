# MIDI-CI エコシステム分析レポート

**作成日**: 2026-02-04
**対象**: uapmd / ktmidi プロジェクトとの比較分析

## 概要

本ドキュメントは、MIDI2Kitの開発において参考となる他のMIDI 2.0/MIDI-CI実装プロジェクトの調査結果をまとめたものです。

## 調査対象プロジェクト

### 1. uapmd (Ubiquitous Audio Plugin MIDI Device)

**リポジトリ**: https://github.com/atsushieno/uapmd

**概要**:
- 音声プラグイン（VST3/AU/LV2/CLAP）を仮想MIDI 2.0デバイスとして公開するシステム
- プラグインパラメータをNRPN、プリセットをプログラムチェンジとして公開
- MIDI-CI標準プロパティ（AllCtrlList、ProgramList）を実装

**技術スタック**:
- remidy: プラグインAPI抽象化層
- ktmidi: MIDI処理（Kotlin）
- cmidi2: UMP/MIDI-CIバイナリ処理（C header-only）
- libremidi: MIDIアクセス

### 2. ktmidi

**リポジトリ**: https://github.com/atsushieno/ktmidi

**概要**:
- Kotlinマルチプラットフォーム対応MIDIライブラリ
- MIDI 1.0、MIDI 2.0、SMF、SMF2、MIDI-CIに対応
- `ktmidi-ci`モジュールでMIDI-CI/Property Exchange実装

**対応プラットフォーム**:
- ALSA、libremidi、RtMidi、CoreMIDI、Web MIDI API

### 3. cmidi2

**リポジトリ**: https://github.com/atsushieno/cmidi2

**概要**:
- Header-only MIDI 2.0 UMP/MIDI-CIバイナリ処理ライブラリ
- C言語実装、リアルタイムオーディオアプリケーション向け
- 2023年6月のMIDI 2.0仕様更新に対応

### 4. midicci

**リポジトリ**: https://github.com/atsushieno/midicci

**概要**:
- C++実装のMIDI-CIツール/ライブラリ
- ktmidi-ciのC++移植版
- トランスポート非依存設計（双方向メッセージングシステム）
- 標準MIDI-CIプロパティ対応（AllCtrlList、ProgramList、State）

**ソースコード構成**:
- `PropertyChunkManager.cpp`: チャンク処理
- `PropertyClientFacade.cpp`: クライアント側プロパティ操作
- `PropertyHostFacade.cpp`: ホスト側プロパティ操作
- `ClientConnection.cpp`: 接続管理

**実装状況（ソースコード分析）**:

| 機能 | 状態 | 詳細 |
|------|------|------|
| チャンク処理 | △ | 欠落時は空応答を返すのみ |
| タイムアウト | △ | 期限切れチャンク削除のみ |
| リトライ | ❌ | 未実装 |
| エラーハンドリング | ❌ | スレッド安全性のみ |
| CIバージョン処理 | ❌ | 未実装 |

---

## 発見された共通課題

### 課題1: MIDI-CI 1.1 vs 1.2 互換性問題

**ktmidi issue [#102](https://github.com/atsushieno/ktmidi/issues/102)**

#### 問題の詳細

KORGデバイス（Keystage、Multipoly、Wavestate、Modwave）との互換性テストで発見：

| デバイス | 状況 |
|----------|------|
| Keystage | CIバージョン＋サイズチェック削除で動作 |
| Multipoly | CIバージョン＋サイズチェック削除で動作 |
| Wavestate | 応答なし |
| Modwave | 応答なし |

#### 技術的原因

- MIDI-CI 1.1のDiscoveryReplyがMIDI-CI 1.2仕様のサイズ要件を満たさない
- 厳密なバージョンチェックにより接続不可

#### 対処方法

```
CIバージョンチェックの緩和 + メッセージサイズ検証の緩和
```

#### MIDI2Kitでの対応

`MIDI2ClientConfiguration.tolerateCIVersionMismatch` 設定で同等の対処を実装済み。

---

### 課題2: タイムアウト/リトライ管理

**ktmidi issue [#57](https://github.com/atsushieno/ktmidi/issues/57)**

#### 必要な管理項目

1. **RequestID管理**
   - 0-127の範囲で再利用
   - アクティブなIDの追跡が必要

2. **サブスクリプション管理**
   - 永続的に残存する可能性
   - ライフサイクル管理が必要

3. **Discoveryタイムアウト**
   - 3秒後にDiscoveryReplyを破棄可能
   - 仕様に基づくタイムアウト処理

#### ktmidiの状況

> "タイマーベースのセッション管理が未実装"

#### MIDI2Kitでの対応

| 機能 | MIDI2Kit | ktmidi |
|------|----------|--------|
| リトライ機能 | ✅ `maxRetries`, `retryDelay` | ❌ |
| タイムアウト設定 | ✅ `peTimeout`, `multiChunkTimeoutMultiplier` | ❌ |
| warm-upロジック | ✅ `warmUpBeforeResourceList` | ❌ |

---

### 課題3: Property Exchange チャンク処理

#### 仕様

- 各チャンクは同一Request IDを使用
- 大きなPEメッセージが小さなリクエストをブロックする可能性
- 複数メッセージの同時送受信をサポート

#### ktmidiの実装

> "responses are simply logged (although nicely chunked)"

#### MIDI2Kitでの対応

- `PEChunkAssembler`: チャンク組み立て
- `PETransactionManager`: トランザクション管理
- CI12パーサー修正: KORGの中間チャンク対応

---

## MIDI2Kit vs ktmidi vs midicci 機能比較

| 機能 | MIDI2Kit | ktmidi | midicci |
|------|----------|--------|---------|
| **リトライ機能** | ✅ 実装済み | ❌ 未実装 | ❌ 未実装 |
| **warm-upロジック** | ✅ 実装済み | ❌ なし | ❌ なし |
| **DestinationCache** | ✅ 実装済み | ❌ なし | ❌ なし |
| **タイムアウト管理** | ✅ 実装済み | ❌ 未実装 | △ 削除のみ |
| **チャンク欠落対応** | ✅ リトライ | △ ログのみ | ❌ 空応答 |
| **診断機能** | ✅ 充実 | △ 基本的 | ❌ なし |
| **MIDI-CI 1.1対応** | △ 部分的 | △ 検討中 | ❌ なし |
| **エラーハンドリング** | ✅ 構造化 | △ 基本的 | ❌ 最小限 |
| **zlib+Mcoded7** | ❌ 未対応 | △ 限定的 | ❌ 未対応 |
| **言語/プラットフォーム** | Swift/iOS,macOS | Kotlin/JVM,JS,Native | C++/クロス |

---

## MIDI2Kitの優位点

### 1. 堅牢なリトライ機構

```swift
// MIDI2ClientConfiguration
maxRetries: Int = 2
retryDelay: Duration = .milliseconds(100)
multiChunkTimeoutMultiplier: Double = 1.5
```

### 2. warm-upロジック

BLE MIDI接続の安定化のため、ResourceList取得前にDeviceInfoを取得：

```swift
warmUpBeforeResourceList: Bool = true
```

### 3. DestinationCache（学習機能）

成功したMUID→Destinationマッピングをキャッシュし、次回以降の送信で活用。

### 4. 診断機能

```swift
client.diagnostics
client.lastDestinationDiagnostics
```

---

## 両者共通の未解決課題

### 1. KORGマルチチャンク応答のパケットロス

- ResourceList（3チャンク）でchunk 2が高頻度で欠落
- CoreMIDI/仮想MIDIポートのバッファリング問題の可能性
- **根本解決は困難**（デバイス/OS側の制限）

### 2. MIDI-CI 1.1デバイスの完全サポート

- 厳密なCI 1.2準拠 vs 後方互換性のトレードオフ
- メッセージサイズ検証の緩和による潜在的リスク

---

## 今後の改善検討事項

### 参考にすべき点

1. **Request ID 0-127の厳密なライフサイクル管理**
   - アクティブIDの追跡
   - 再利用ポリシーの明確化

2. **サブスクリプションのタイムアウト設計**
   - 永続化防止
   - 自動クリーンアップ

3. **zlib+Mcoded7エンコーディング対応**（将来）
   - 大容量データ転送の効率化
   - 相互運用性の検証が必要

---

## 参考リンク

- [uapmd - GitHub](https://github.com/atsushieno/uapmd)
- [ktmidi - GitHub](https://github.com/atsushieno/ktmidi)
- [cmidi2 - GitHub](https://github.com/atsushieno/cmidi2)
- [midicci - GitHub](https://github.com/atsushieno/midicci)
- [ktmidi issue #102: MIDI-CI 1.1サポート](https://github.com/atsushieno/ktmidi/issues/102)
- [ktmidi issue #57: タイムアウト管理](https://github.com/atsushieno/ktmidi/issues/57)
- [Understanding MIDI-CI tools (Blog)](https://atsushieno.github.io/2024/01/26/midi-ci-tools.html)
- [Building MIDI 2.0 Ecosystems on Android (Blog)](https://atsushieno.github.io/2024/04/12/midi2-on-android.html)
- [ktmidi, a Kotlin MPP Library (Blog)](https://atsushieno.github.io/2021/05/18/ktmidi.html)
- [MIDI-CI Property Exchange Specification](https://amei.or.jp/midistandardcommittee/MIDI2.0/MIDI2.0-DOCS/M2-103-UM_v1-1_Common_Rules_for_MIDI-CI_Property_Exchange.pdf)

---

## 業界知見（ブログ記事より）

### 相互運用性の課題

各MIDI-CI実装間での完全な相互運用性は達成されていない：

| ツール | 制限事項 |
|--------|----------|
| JUCE CapabilityInquiryDemo | Process Inquiry未対応、UI非直感的 |
| ktmidi-ci-tool | zlib実装がJVM/Androidのみ |
| MIDI 2.0 Workbench | Property Exchangeテストにブロッキング問題 |
| Apple CoreMIDI | Property Exchange/Process Inquiry未対応 |

### Property Exchangeの根本的な問題

1. **JSON形式はリアルタイム対応ではない**
   - パース負荷が高い
   - 構造化データの即時処理が困難

2. **エンコーディングの複雑性**
   - ASCII、Mcoded7、zlib+Mcoded7の3種類
   - zlib圧縮の相互運用性が未検証

3. **Process Inquiryの設計欠陥**
   - 複数レスポンダーからの並行応答待機が技術的に不可能

### UMP変換

ktmidiの`UmpTranslator`クラスにより、UMP⇔MIDI 1.0の双方向変換が可能。これによりMIDI 1.0 DAWでもUMPデバイスを利用できる。

### MIDI 2.0ファイル形式

SMF 2.0相当の標準ファイル形式がまだ存在せず、DAWのMIDI 2.0インポート機能に影響。

### 開発者への推奨事項（ブログより）

1. **段階的実装**: Discovery → Profile Configuration → Property Exchangeの優先順位で
2. **早期相互運用性テスト**: 複数実装間での接続テストを初期から実施
3. **仕様の理解**: MIDI-CI本仕様とCommon Rules for PEの両方を理解する必要
4. **MIDI-CIは必須ではない**: UMP対応のみでMIDI 2.0機能の多くは利用可能

---

## 結論

MIDI2Kitの実装アプローチは業界の他の実装（ktmidi、midicci）と比較して正しい方向にあり、特にリトライ機構、タイムアウト管理、チャンク欠落対応、診断機能において明確な優位性がある。

ktmidiとmidiciは両方ともタイムアウト管理やリトライ機構が未実装であり、MIDI2Kitが最も堅牢な実装を持つ。ktmidiも同じKORG互換性問題に直面しており、MIDI2Kitの`tolerateCIVersionMismatch`アプローチは妥当な解決策である。

### 今後の方針

**優先度高:**
- Request IDライフサイクル管理の厳密化
- 相互運用性テストの継続

**優先度中:**
- UMP⇔MIDI 1.0変換機能の検討

**優先度低（相互運用性検証困難）:**
- zlib+Mcoded7エンコーディング対応

### 注意事項

- Apple CoreMIDIはProperty Exchange/Process Inquiry未対応という制約がある
- JSON形式のリアルタイム性限界は仕様レベルの問題
- 業界全体で完全な相互運用性は未達成であり、MIDI2Kitも例外ではない
