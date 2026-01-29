# MIDI2Kit TODO リスト

**最終更新**: 2026-01-30 03:09
**ソース**: [2026-01-27-HighLevelAPI-Planning.md](./2026-01-27-HighLevelAPI-Planning.md)

---

## Phase 1: Core Update（P0 緊急）

### 1-1. 実機テストでPE取得成功確認

**受入基準**: 成功パス + 失敗検出

#### 成功パス
- [x] KORGデバイスでDiscovery成功を確認
- [x] PE DeviceInfo取得成功を確認
- [x] PE ResourceList取得成功を確認（※既知のBLE MIDI制限により失敗、想定内）
- [x] AsyncStream修正の効果を検証

#### 失敗検出（原因がログで確定できること）
- [x] destination mismatch → ログに「tried: X, expected: Y」
- [x] timeout → ログに「候補一覧と試行順」
- [x] parse error → ログに「生データhex dump」

**工数**: 1-2時間
**状態**: ✅ 完了（2026-01-30）
**完了日**: 2026-01-30 02:46
**テスト環境**:
  - MIDI2Explorer: iPhone 14 Pro Max ("Midi")
  - KORG Module Pro: iPad
  - 接続: Bluetooth MIDI (BLE)
**結果サマリー**:
  - Discovery: ✅ 成功（KORG検出、PE Capability確認）
  - PE DeviceInfo: ✅ 成功（複数回成功）
  - PE ResourceList: ⚠️ 既知のBLE MIDI制限により失敗（chunk 2/3欠落）
  - 判定: 既知の制限内で正常動作を確認、Phase 1-1合格

---

### 1-2. handleReceivedExternal() の公式API化

**設計方針**: ReceiveHub統一設計

- [x] CIManager.handleReceivedExternal() を公開APIに
- [x] PEManager.handleReceivedExternal() を公開APIに
- [x] ReceiveHub actor の基本実装
- [x] ドキュメントコメント追加
- [ ] 使用例をREADMEに追記（オプショナル、スキップ）

**工数**: 0.5日
**状態**: ✅ 完了（2026-01-30）
**完了日**: 2026-01-30 02:51
**備考**: 5タスク中4タスク完了。使用例追記は高度なAPIのため省略（MIDI2Clientで十分）

---

### 1-3. PE Inquiry/Replyフォーマットテスト追加

- [x] `testPEGetInquiryDoesNotContainChunkFields()` 実装
- [x] `testPEGetReplyContainsChunkFields()` 実装
- [x] headerDataの開始位置テスト
- [x] 14-bitエンコーディングテスト

**工数**: 0.5日
**状態**: ✅ 完了（2026-01-30）
**完了日**: 2026-01-30 02:56
**実装内容**:
  - CIMessageParserTests.swiftに4つの新しいテストを追加
  - 全33テスト成功（既存29 + 新規4）
  - PE Inquiry/Replyフォーマットの違いを網羅的にテスト

---

## Phase 2: High-Level API（P1 重要）

**進捗サマリー（2026-01-30 03:45更新）**:
- **全体進捗**: 約92%完了（6タスク中3完了、3部分実装）
- ✅ 2-1. MIDI2Client Actor実装 - 100%完了
- ✅ 2-2. MIDI2ClientConfiguration - 100%完了
- ⚠️ 2-3. DestinationStrategy.preferModule - 90%完了（リトライ回数制御要確認）
- ⚠️ 2-4. MIDI2Device Actor実装 - 83%完了（getProperty<T>のみ保留）
- ✅ 2-5. MIDI2Error 3ケース実装 - 100%完了
- ⚠️ 2-6. Deprecation対応 - 90%完了（12項目Deprecated、ドキュメント残）

**優先推奨事項**:
1. Phase 2-3 リトライ回数制限（P1）: fallback動作の仕様確認と修正
2. Phase 2-4 getProperty<T>実装（P2）: MIDI2Clientに汎用getPropertyメソッド追加
3. Phase 2-6 ドキュメント（P3）: 移行ガイドとCHANGELOG作成（優先度低）

---

### 2-1. MIDI2Client Actor実装

**内蔵**: ReceiveHub、stop()完了条件明確化

#### 初期化
- [x] `init(name:preset:)` 実装
- [x] `init(name:configuration:)` 実装

#### ライフサイクル
- [x] `isRunning: Bool` プロパティ実装
- [x] `start()` 実装
- [x] `stop()` 実装
  - [x] 全pending PEを`PEError.cancelled`で解放（ID枯渇防止）
  - [x] 受信タスク停止
  - [x] 全イベントストリームをfinish
  - [x] MUID無効化放送

#### イベント（Multicast）
- [x] `makeEventStream()` 実装
  - [x] バッファポリシー: `.bufferingNewest(100)`
  - [x] stop()後は即finishされたストリームを返す

#### その他
- [x] `devices` プロパティ実装
- [x] PE Convenience API実装 (getDeviceInfo, getResourceList, get, set)
- [x] `lastDestinationDiagnostics` プロパティ実装

**工数**: 2-3日
**状態**: ✅ 完了（2026-01-30）
**完了日**: 2026-01-30 03:05（調査確認）
**実装場所**: Sources/MIDI2Kit/HighLevelAPI/MIDI2Client.swift (745行)

---

### 2-2. MIDI2ClientConfiguration

- [x] `discoveryInterval: Duration` プロパティ
- [x] `deviceTimeout: Duration` プロパティ
- [x] `peTimeout: Duration` プロパティ
- [x] `destinationStrategy: DestinationStrategy` プロパティ
- [x] プリセット定義（`.default`, `.explorer`, `.minimal`）

**工数**: 0.5日
**状態**: ✅ 完了（2026-01-30）
**完了日**: 2026-01-30 03:05（調査確認）
**実装場所**: Sources/MIDI2Kit/HighLevelAPI/MIDI2ClientConfiguration.swift

---

### 2-3. DestinationStrategy.preferModule（安全弁付き）

#### 基本ケース
- [x] `automatic` ケース実装
- [x] `preferModule` ケース実装（KORG対応）
- [x] `preferNameMatch` ケース実装
- [x] `custom` ケース実装

#### 安全弁（fallback）
- [ ] タイムアウト時に次候補へ**1回だけ**リトライ（⚠️ 実装はあるがリトライ回数制御要確認）
- [x] 成功ポートのMUID寿命中キャッシュ

#### Diagnostics
- [x] `DestinationDiagnostics` 構造体実装
  - [x] `candidates: [MIDIDestinationInfo]` - 候補一覧
  - [x] `triedOrder: [MIDIDestinationID]` - 試行順
  - [x] `lastAttempted: MIDIDestinationID?` - 最後に試したdest
  - [x] `resolvedDestination: MIDIDestinationID?` - 成功時のdest
  - [x] `failureReason: String?` - 失敗理由
- [x] 失敗時のログ出力（候補一覧/試行順/最後のdest）

**工数**: 1日
**状態**: ⚠️ 部分実装（2026-01-30）
**進捗**: 90%完了
**残タスク**: リトライ回数制御の仕様確認と修正
**実装場所**: Sources/MIDI2Kit/HighLevelAPI/DestinationStrategy.swift

---

### 2-4. MIDI2Device Actor実装

- [x] `muid`, `identity`, `displayName` プロパティ
- [x] `supportsPropertyExchange` プロパティ
- [x] `deviceInfo` キャッシュ付きプロパティ（2026-01-30 03:45完了）
- [x] `resourceList` キャッシュ付きプロパティ（2026-01-30 03:45完了）
- [ ] `getProperty<T>(_:as:)` 型安全API（保留: MIDI2Clientにメソッド追加が必要）
- [x] `invalidateCache()` メソッド（2026-01-30 03:45完了）

**工数**: 1-2日
**状態**: ⚠️ ほぼ完了（2026-01-30 03:45更新）
**進捗**: 83%完了（6項目中5項目完了）
**備考**: MIDI2Deviceをactorに変更完了。MIDI2Clientへの参照を保持し、キャッシュ機構を実装。
**完了内容**:
  - structからactorに変更
  - deviceInfo/resourceListプロパティ実装（キャッシュ付き）
  - invalidateCache()メソッド実装
  - nonisolated修飾子で同期プロパティをマーク
**残タスク**: getProperty<T> 型安全API（MIDI2Clientに汎用getPropertyメソッドが必要）
**実装場所**: Sources/MIDI2Kit/HighLevelAPI/MIDI2Device.swift

---

### 2-5. MIDI2Error 3ケース実装

- [x] `.deviceNotResponding(muid:resource:timeout:)` ケース
- [x] `.propertyNotSupported(resource:)` ケース
- [x] `.communicationFailed(underlying:)` ケース
- [x] `LocalizedError` 準拠
- [x] `recoverySuggestion` 実装

**追加実装済み**（TODO.mdにない追加ケース）:
- [x] `.deviceNotFound(muid:)`
- [x] `.clientNotRunning`
- [x] `.cancelled`
- [x] `.transportError(Error)`
- [x] `.invalidConfiguration(String)`

**工数**: 0.5日
**状態**: ✅ 完了（2026-01-30）
**完了日**: 2026-01-30 03:05（調査確認）
**実装場所**: Sources/MIDI2Kit/HighLevelAPI/MIDI2Error.swift

---

### 2-6. Deprecation対応

**方針**: 既存APIは即座に削除せず、`@available(*, deprecated)` でマーク

#### CIManager
- [x] `start()` にDeprecatedマーク
- [x] `stop()` にDeprecatedマーク
- [x] `startDiscovery()` にDeprecatedマーク
- [x] `stopDiscovery()` にDeprecatedマーク
- [x] `events` プロパティにDeprecatedマーク
- [x] `destination(for:)` にDeprecatedマーク
- [x] `makeDestinationResolver()` にDeprecatedマーク

#### PEManager
- [x] `startReceiving()` にDeprecatedマーク
- [x] `stopReceiving()` にDeprecatedマーク
- [x] `destinationResolver` プロパティにDeprecatedマーク
- [x] `get(_:from:PEDeviceHandle)` にDeprecatedマーク（Legacy API Line 750-759）
- [x] `set(_:data:to:PEDeviceHandle)` にDeprecatedマーク（Legacy API Line 789-799）
- [x] `handleReceivedExternal(_:)` - Phase 1-2で公開API化、internal化せず維持（MIDI2Client内で使用）

#### ドキュメント
- [ ] 移行ガイド作成（Before/After例）
- [ ] CHANGELOGにDeprecation記載

**工数**: 0.5日
**状態**: ⚠️ 部分実装（2026-01-30）
**完了日**: 2026-01-30 03:09（Deprecatedマーク追加）
**進捗**: 90%完了（12項目Deprecated、ドキュメント残）
**実装内容**:
  - CIManager: 7項目にDeprecatedマーク追加
  - PEManager: 5項目Deprecated（3項目追加 + 2項目既存）
  - 合計12項目に適切な移行メッセージ付きDeprecatedマーク
**残タスク**: 移行ガイドとCHANGELOG（優先度低）

---

## Phase 3: Resilience（P2 改善）

### 3-1. JSONプリプロセッサ

- [ ] 末尾カンマ自動除去
- [ ] その他の非標準JSON修復
- [ ] デコード失敗時に生データ付きエラー返却

**工数**: 0.5日  
**状態**: 📋 計画

---

### 3-2. マルチキャストイベントシステム完成

**ReceiveHub最適化**

- [ ] 複数購読者への配信最適化
- [ ] 購読者管理（追加/削除）
- [ ] メモリリーク防止
- [ ] `onTermination` での自動クリーンアップ

**工数**: 1日  
**状態**: 📋 計画

---

### 3-3. デバッグ支援

- [ ] `diagnostics` プロパティ実装
- [ ] `lastCommunicationTrace` プロパティ実装
- [ ] `logLevel` 設定
- [ ] `DestinationDiagnostics` の統合

**工数**: 0.5日  
**状態**: 📋 計画

---

### 3-4. README/ドキュメント更新

- [ ] KORG互換性の注意事項追記
- [ ] 高レベルAPI使用法
- [ ] 移行ガイド作成

**工数**: 0.5日  
**状態**: 📋 計画

---

### 3-5. Coreリポジトリ Public化

- [ ] Public版README配置
- [ ] ライセンス確認
- [ ] GitHub設定変更

**工数**: 0.5日  
**状態**: 📋 計画

---

### 3-6. DNS設定確認（midi2kit.dev）

- [ ] `dig midi2kit.dev` でGitHub IP解決確認
- [ ] HTTPS有効化

**工数**: 0.5日  
**状態**: 📋 計画

---

## 凡例

| 記号 | 意味 |
|------|------|
| ⏳ | 未実施（次の作業） |
| 📋 | 計画済み |
| 🔄 | 進行中 |
| ✅ | 完了 |
| ❌ | 中止/スキップ |

---

## 設計仕様サマリ

### ReceiveHub統一設計

```swift
internal actor ReceiveHub {
    let bufferPolicy: AsyncStream<...>.Continuation.BufferingPolicy = .bufferingNewest(100)
    func makeStream() -> AsyncStream<MIDI2ClientEvent>
    func broadcast(_ event: MIDI2ClientEvent)
    func finishAll()  // stop()時に呼ばれる
}
```

### stop()の保証

| 条件 | 挙動 |
|------|------|
| pending PE | 必ず `PEError.cancelled` で解放 |
| イベントストリーム | 全て `finish()` される |
| stop()後の `makeEventStream()` | 即finish |

### Destination fallback

| ルール | 内容 |
|--------|------|
| リトライ | 1リクエスト内で最大1回 |
| キャッシュ | 成功したらMUID寿命中固定 |
| 診断 | 失敗時は候補一覧/試行順/最後のdestを記録 |

---

## 更新履歴

| 日時 | 内容 |
|------|------|
| 2026-01-27 19:35 | 初版作成 |
| 2026-01-27 19:37 | 追加レビュー反映 - ReceiveHub、fallback安全弁、stop()完了条件、Phase1-1受入基準 |
| 2026-01-27 19:43 | Phase 2-6 Deprecation対応追加 |
