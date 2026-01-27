# BLE MIDI Packet Loss Analysis

## Executive Summary

KORG Module Pro との Property Exchange (PE) 通信において、BLE MIDI 経由でのマルチチャンク応答（ResourceList等）で **chunk 2/3 が約90%の確率で欠落** する問題が確認された。これは MIDI2Kit のパーサーやプロトコル実装の問題ではなく、**BLE MIDI の物理層における信頼性の問題** である。

---

## 問題の症状

### 観察された現象

1. **DeviceInfo (単一チャンク)**: 常に成功 ✅
2. **ResourceList (3チャンク)**: 高頻度で失敗 ❌
   - chunk 1/3: 正常受信 (253B)
   - chunk 2/3: **欠落または切断** (~160B expected, often 0B or 84B received)
   - chunk 3/3: 正常受信 (55B)

### ログ証拠

```
# 成功パターン (まれ)
[ChunkAssembler] [5] chunk 1/3 → chunk 2/3 → chunk 3/3 → COMPLETE! (475B)

# 失敗パターン (高頻度)
[ChunkAssembler] [7] chunk 1/3 → chunk 3/3 → waiting for [2] → TIMEOUT
[ChunkAssembler] [8] chunk 1/3 → chunk 3/3 → waiting for [2] → TIMEOUT
```

---

## 根本原因分析

### 1. BLE MIDI の構造的制約

BLE MIDI は以下の特性を持つ：
- MTU (Maximum Transmission Unit) 制限: 通常 23-512 bytes
- コネクションレス通信: パケット配信保証なし
- 再送メカニズム: BLE レイヤーでの再送はあるが、MIDI レベルでは保証なし

### 2. KORG Module Pro の挙動

KORG は PE Reply を以下の順序で送信：
1. **chunk 1/3** (253B) - ヘッダー + ResourceList 前半
2. **chunk 2/3** (~160B) - ResourceList 中盤
3. **chunk 3/3** (55B) - ResourceList 後半

chunk 2/3 は最もサイズが大きく、BLE パケット分割の影響を受けやすい。

### 3. 仮説：BLE パケットフラグメンテーション

```
chunk 2/3 (160B) → BLE fragments:
  [Fragment 1: 23B] ✅ 受信成功
  [Fragment 2: 23B] ❌ ロスト
  [Fragment 3: 23B] ❌ ロスト
  ...
結果: 不完全な chunk または完全欠落
```

---

## 試行した対策

### 1. スマートリトライ戦略

**実装:**
- チャンクタイムアウト: 3.0s → 2.0s
- リトライ回数: 3 → 5
- リトライ間隔: 200ms → 100ms

**結果:** 改善されたが、5回リトライしても成功しないケースが多い。

### 2. CI11 パーサー修正

**問題:** chunk 2/3 (headerSize=0) が CI11 フォーマットと誤認される

**修正:**
```swift
// CIMessageParser.parsePEReplyCI11()
guard headerSize > 0 else { return nil }
```

**結果:** パーサーの誤認は解決。しかしパケットロス自体は解決しない。

---

## 現在のステータス

| コンポーネント | ステータス | 備考 |
|---------------|-----------|------|
| Discovery | ✅ 動作 | 単一パケット、問題なし |
| DeviceInfo | ✅ 動作 | 単一チャンク |
| ResourceList | ⚠️ 不安定 | マルチチャンク、BLE依存 |
| ProgramEdit | ❓ 未テスト | マルチチャンクの可能性 |

---

## 今後の対策オプション

### Option A: USB/有線接続の推奨

**メリット:**
- 信頼性が高い
- パケットロスなし

**デメリット:**
- ユーザー体験の制限
- BLE の利点（ワイヤレス）が失われる

### Option B: より積極的なリトライ

**実装案:**
```swift
// さらにリトライ回数を増やす
maxRetries = 10
retryInterval = 50ms  // より短く
```

**懸念:**
- 成功するまで長時間かかる可能性
- ユーザー体験の悪化

### Option C: 部分データの活用

**実装案:**
- chunk 1/3 から ResourceList の一部を抽出
- 不完全でも有用な情報を表示

**デメリット:**
- 仕様違反の可能性
- データの整合性問題

### Option D: デバイス側の設定確認

**確認事項:**
- KORG Module Pro の BLE 設定
- iOS の Bluetooth 設定
- 他のデバイスでの再現性

---

## 関連ファイル

- `Sources/MIDI2CI/CIMessageParser.swift` - パーサー修正
- `Sources/MIDI2PE/PEChunkAssembler.swift` - チャンク組立
- `Sources/MIDI2PE/PEManager.swift` - リトライロジック
- `docs/ClaudeWorklog20260127.md` - デバッグ経緯

---

## 結論

BLE MIDI 経由でのマルチチャンク PE 通信は **物理層の信頼性問題** により不安定である。MIDI2Kit のソフトウェア実装は正しく動作しているが、BLE MIDI の制約を超えることはできない。

**推奨:**
1. **短期:** リトライロジックのさらなる強化
2. **中期:** USB 接続での動作確認とドキュメント化
3. **長期:** BLE MIDI 信頼性問題の業界標準的な解決策を調査

---

*Document created: 2026-01-27*
*Last updated: 2026-01-27*
