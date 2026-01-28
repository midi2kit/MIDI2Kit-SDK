# MIDI2Kit 実装評価レビュー (2026-01-28)

## 概要

本ドキュメントは `MIDI2Kit_main_evaluation_proposal_2026-01-28_v2.md` の評価提案書をレビューし、疑問点と次のアクションを整理したものです。

---

## 1. 評価サマリー

### 主要コンポーネント評価

| コンポーネント | 評価 | 状況 | 備考 |
|---|---|---|---|
| **MIDI2Client** | S | 実装完了・設計通り | Transport → CI → PE の初期化順序を隠蔽、DX向上 |
| **ReceiveHub** | S | クリティカル修正完了 | AsyncStream競合問題を根本解決、マルチキャスト配信ハブ |
| **DestinationResolver** | A | 戦略実装済み | KORG対応 `.preferModule` 戦略、改善余地あり |
| **MIDI2Device** | A | 実装完了 | PE情報キャッシュ、便利なアクセサ提供 |

### ドキュメント整合性

| 計画ドキュメントの項目 | 実装状況 | 整合性 |
|---|---|---|
| AsyncStream競合解決 | ReceiveHub 実装済み | ✅ 一致 |
| Destination解決戦略 | DestinationStrategy 実装済み | ✅ 一致 |
| イベントシステム | MIDI2ClientEvent 実装済み | ✅ 一致 |
| 設定オブジェクト | MIDI2ClientConfiguration 実装済み | ✅ 一致 |
| エラーの抽象化 | MIDI2Error 実装済み | ✅ 一致 |
| APIのDeprecation | DocCで「Recommended」表記 | ✅ 明示的deprecation不要と判断 |

---

## 2. 確認が必要な疑問点

### 疑問点 1: DestinationResolver↔PEManager連携のフォールバックロジック

**計画書の記述:**
> 「タイムアウト時の自動フォールバック（1回だけリトライ）」のロジックが、DestinationResolver 単体ではなく PEManager との連携部分でどのように実装されているか

**確認項目:**
- [ ] `DestinationResolver.swift` のフォールバック実装
- [ ] `PEManager` との連携でのリトライ動作
- [ ] 結合テストでの動作確認

### 疑問点 2: CIMessageParserのヘッダーサイズガード

**背景:**
`BLE-MIDI-PacketLoss-Analysis.md` で報告された問題:
- Chunk 2/3 (headerSize=0) が CI11 フォーマットと誤認される

**確認項目:**
- [ ] `CIMessageParser.swift` に `headerSize > 0` のガード処理があるか
- [ ] 中間チャンク（headerSize=0）の適切なハンドリング

**Note:** 00:14のワークログで `parsePEReplyCI12()` を修正し、中間チャンクをパース可能にしたが、CI11側のガードは別途確認が必要。

### 疑問点 3: RobustJSONDecoderのプリプロセス処理

**計画書の記述:**
> `RobustJSONDecoder.md` にある「末尾カンマの削除」などのプリプロセス処理が、実際に PEManager のデコードフローに組み込まれているか

**確認項目:**
- [ ] `RobustJSONDecoder.swift` の実装内容
- [ ] PEManagerでのデコード時に使用されているか
- [ ] プリプロセス処理（末尾カンマ削除、コメント除去等）の有無

### 疑問点 4: スマートリトライのデフォルト設定

**評価書の記述:**
> 「回数を増やす」「間隔を詰める」といったアグレッシブなリトライロジックがデフォルトで有効になっているか

**現在の設定（MIDI2ClientConfiguration）:**
```swift
maxRetries: Int = 2           // 合計3回試行
retryDelay: Duration = .milliseconds(100)
multiChunkTimeoutMultiplier: Double = 1.5
```

**確認項目:**
- [ ] デフォルト設定が適切か
- [ ] KORG向けの推奨設定がドキュメント化されているか

---

## 3. 推奨アクションへの対応状況

| 評価書の推奨アクション | 状況 | 詳細 |
|---|---|---|
| 1. Deprecationの明示 | ✅ 対応不要 | DocCで「High-Level API (Recommended)」と記載済み。明示的な `@available(*, deprecated)` は不要と判断（01:26ワークログ参照） |
| 2. 実機検証 (Phase 1-1) | ⚠️ 追加検証推奨 | preferModuleでKORG Module Pro実機テスト。Discovery (Bluetooth) → PE Request (Module) のハンドオーバー確認 |
| 3. JSON Decoderの強化 | ⚠️ 確認必要 | RobustJSONDecoderのプリプロセス処理がPEManagerに組み込まれているか確認 |

---

## 4. BLEパケット欠落問題への対応状況

### 対応済み

1. **CI12パーサー修正** (00:14)
   - `parsePEReplyCI12()` を修正
   - KORGの中間チャンク（chunk 2/3）をパース可能に

2. **DestinationResolver改善** (00:06)
   - Session 1フォールバック追加
   - `.preferModule` 戦略実装

3. **warm-upロジック** (00:00)
   - ResourceList取得前にDeviceInfo取得
   - BLE接続の安定化

4. **リトライ機能** (01:08)
   - `maxRetries`, `retryDelay` を Configuration に追加
   - タイムアウト時の自動リトライ

### 未対応/保留

1. **CIMessageParserのCI11ガード**
   - headerSize > 0 のガード処理確認が必要

2. **チャンク間ディレイ**
   - PEManager内部の変更が必要、保留中

---

## 5. 次のアクション計画

### 優先度: 高

1. **コード確認**
   - [ ] CIMessageParser.swift のヘッダーサイズガード
   - [ ] RobustJSONDecoder.swift のプリプロセス処理
   - [ ] PEManagerでのデコードフロー

2. **実機検証**
   - [ ] preferModule戦略でKORG Module Proテスト
   - [ ] Discovery → PE ハンドオーバーの動作確認

### 優先度: 中

3. **ドキュメント更新**
   - [ ] KORG向け推奨設定の明文化
   - [ ] リトライ設定のチューニングガイド

### 優先度: 低

4. **将来の改善**
   - [ ] チャンク間ディレイの実装（PEManager変更が必要）
   - [ ] 追加デバイスでのテスト（KORG以外）

---

## 6. 総合評価

> 実装は計画書に非常に忠実であり、品質は高いです。特に並行処理周り（Actor, Sendable, ReceiveHub）の設計は堅牢で、Swift 6 時代に適したモダンな実装になっています。

**Phase 1完了時点での達成状況:**
- ✅ Core Stability（Discovery、DeviceInfo安定）
- ✅ High-Level API（MIDI2Client、MIDI2Logger完成）
- ✅ Resilience Features（リトライ機能実装）
- ⚠️ KORG ResourceListのchunk 2欠落（KORG側の問題、MIDI2Kitでは解決不可）

---

## 関連ドキュメント

- [HighLevelAPIProposal.md](./HighLevelAPIProposal.md)
- [2026-01-27-HighLevelAPI-Planning.md](./2026-01-27-HighLevelAPI-Planning.md)
- [KORG-PE-Compatibility.md](./KORG-PE-Compatibility.md)
- [KORG-Module-Pro-Limitations.md](./KORG-Module-Pro-Limitations.md)
- [BLE-MIDI-PacketLoss-Analysis.md](./technical/BLE-MIDI-PacketLoss-Analysis.md)
- [RobustJSONDecoder.md](./technical/RobustJSONDecoder.md)
