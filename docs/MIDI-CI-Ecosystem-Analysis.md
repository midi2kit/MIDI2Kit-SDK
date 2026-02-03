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

## MIDI2Kit vs ktmidi 機能比較

| 機能 | MIDI2Kit | ktmidi |
|------|----------|--------|
| **リトライ機能** | ✅ 実装済み | ❌ 未実装 |
| **warm-upロジック** | ✅ 実装済み | ❌ なし |
| **DestinationCache** | ✅ 実装済み | ❌ なし |
| **タイムアウト管理** | ✅ 実装済み | ❌ 未実装 |
| **診断機能** | ✅ 充実 | △ 基本的 |
| **MIDI-CI 1.1対応** | △ 部分的 | △ 検討中 |
| **zlib+Mcoded7** | ❌ 未対応 | △ 限定的 |
| **マルチプラットフォーム** | iOS/macOS | JVM/JS/Native |

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
- [ktmidi issue #102: MIDI-CI 1.1サポート](https://github.com/atsushieno/ktmidi/issues/102)
- [ktmidi issue #57: タイムアウト管理](https://github.com/atsushieno/ktmidi/issues/57)
- [Understanding MIDI-CI tools (Blog)](https://atsushieno.github.io/2024/01/26/midi-ci-tools.html)
- [MIDI-CI Property Exchange Specification](https://amei.or.jp/midistandardcommittee/MIDI2.0/MIDI2.0-DOCS/M2-103-UM_v1-1_Common_Rules_for_MIDI-CI_Property_Exchange.pdf)

---

## 結論

MIDI2Kitの実装アプローチは業界の他の実装と比較して正しい方向にあり、特にリトライ機構、タイムアウト管理、診断機能において優位性がある。ktmidiも同じKORG互換性問題に直面しており、MIDI2Kitの`tolerateCIVersionMismatch`アプローチは妥当な解決策である。

今後はRequest IDライフサイクル管理の厳密化と、将来的なzlib+Mcoded7対応を検討することで、より堅牢なMIDI 2.0実装を目指す。
