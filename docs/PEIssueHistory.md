# Property Exchange (PE) 情報取得問題の経緯と解決記録

## 概要

MIDI2Explorer iOSアプリでKORGデバイスからProperty Exchange（PE）情報を取得できない問題の調査・修正の経緯を記録する。

---

## 問題の症状

**発生日**: 2026-01-26

**症状**:
- KORGデバイス（KORG Module Pro、製造者ID 374:4）がDiscoveryで検出される ✅
- Property Exchange（DeviceInfo, ResourceList）取得でタイムアウトエラー ❌
- エラーメッセージ: `Timeout waiting for response: DeviceInfo`

---

## 調査の時系列

### Phase 1: 初期調査 (03:46 - 04:40)

#### 発見事項

1. **Discoveryは成功**: KORGデバイスが正常に検出される
2. **PEエラー発生**: `MIDI2PE.PEError error 0` というエラー
3. **フォールバックロジック追加後も解決せず**: デバイスが応答しない

### Phase 2: Destination解決問題の発見 (05:05 - 05:15)

#### 重要な発見

**KORGデバイスのポート構造**:
```
Sources:
- Session 1
- Bluetooth

Destinations:
- Session 1  
- Bluetooth
- Module        ← ここにPEを送る必要がある！
```

**問題点**:
- Discovery ReplyはBluetoothソースから受信
- 既存のロジックはsourceIDからdestinationをマッチングしていた
- 結果としてBluetoothにPEリクエストを送信（間違い）
- **KORGはModuleポートでPEを受け付ける**

### Phase 3: Destination解決ロジック修正 (07:17 - 19:34)

#### 実施した修正

**CIManager.findDestination()の優先順位変更**:

```swift
private func findDestination(for sourceID: MIDISourceID?) async -> MIDIDestinationID? {
    let destinations = await transport.destinations
    
    // Priority 1: "Module" destination (HIGHEST PRIORITY for PE)
    if let moduleDest = destinations.first(where: { $0.name.lowercased().contains("module") }) {
        return moduleDest.destinationID
    }
    
    // Priority 2: Entity-based matching
    // Priority 3: Name-based matching
    // ...
}
```

#### 確認結果

- **UIログで「→ PE Destination: Module ✅」と表示**
- **しかしMIDITracerでは依然としてBluetoothに送信されていた**
- UIとTracerで不整合！

### Phase 4: MIDIトレース分析による詳細調査 (19:25 - 19:54)

#### Tracerログ分析

```
PE Get Inquiry(0x34) → 0x00C50052 (Bluetooth)  ← 間違ったポート
PE Get Inquiry(0x34) → 0x00C50041 (Session1)
(Module 0x00C50040にはGETが送られていない)
```

#### ポートID対応表

| Name | Type | ID (hex) |
|------|------|----------|
| Bluetooth | Source | 0x00C50040 |
| Module | Dest | 0x00C50052 |
| Bluetooth | Dest | 0x00C50041 |
| Session1 | Dest | 0x00C50016 |

**重要な発見**: Source「Bluetooth」とDestination「Module」が異なるIDを持つ

### Phase 5: ブロードキャスト方式への変更検討 (19:34)

#### 参考情報

SimpleMidiController（過去のプロジェクト）では `broadcastSysEx` で全destinationsに送信していた。

**決定事項**: PEリクエストを全destinationsにブロードキャストする方式でテスト

### Phase 6: AsyncStream競合問題の発見と修正 (19:54 - 20:05)

#### 根本原因の特定

**デバイスログで確認**:
```
PE GET Reply (0x35) が受信されている！
```

**問題**: AsyncStreamは単一コンシューマーのみ対応
- `CIManager.start()` が `transport.received` を消費
- `PEManager.startReceiving()` も `transport.received` を消費しようとする
- **競合により片方しかデータを受け取れない**

#### 実施した修正

**1. handleReceivedExternal()メソッドを追加**

CIManager:
```swift
public func handleReceivedExternal(_ received: MIDIReceivedData) {
    handleReceived(received)
}
```

PEManager:
```swift
public func handleReceivedExternal(_ data: [UInt8]) async {
    await handleReceived(data)
}
```

**2. AppStateで単一ディスパッチャーを実装**

```swift
// CRITICAL FIX: AsyncStream can only be consumed once!
receiveDispatcherTask = Task { [weak self] in
    for await received in transport.received {
        guard let self else { break }
        
        // Dispatch to CIManager for Discovery handling
        await ciManager.handleReceivedExternal(received)
        
        // Dispatch to PEManager for PE handling
        await peManager.handleReceivedExternal(received.data)
    }
}
```

**3. CIManager.start()でautoStartDiscovery=falseに設定**

- `start()` ではstream消費を開始しない
- `startDiscovery()` のみ呼び出してブロードキャストを開始

---

## 修正後のアーキテクチャ

```
┌─────────────────────────────────────────────────┐
│                  AppState                        │
│                                                 │
│  ┌─────────────────────────────────────────┐   │
│  │     receiveDispatcherTask               │   │
│  │                                         │   │
│  │  for await received in transport.received │   │
│  │       ↓                    ↓            │   │
│  │  ciManager.           peManager.        │   │
│  │  handleReceivedExternal()  handleReceivedExternal() │
│  └─────────────────────────────────────────┘   │
│                                                 │
└─────────────────────────────────────────────────┘
```

---

## 関連するコード変更箇所

### 1. MIDI2Kit/Sources/MIDI2CI/CIManager.swift

- `handleReceivedExternal()` メソッド追加
- `makeDestinationResolver()` でModule優先ロジック実装
- `resolveDestinationForPE()` メソッド追加
- `findDestination()` でModule優先順位を最上位に変更

### 2. MIDI2Kit/Sources/MIDI2PE/PEManager.swift

- `handleReceivedExternal()` メソッド追加
- `scheduleSendForRequest()` で全destinationsへブロードキャスト（デバッグ用）

### 3. MIDI2Explorer/ContentView.swift (AppState)

- `receiveDispatcherTask` で単一ディスパッチャー実装
- `CIManagerConfiguration` で `autoStartDiscovery: false` 設定
- PEReply受信時のMUIDマッチング確認ログ追加

---

## 未解決・今後のTODO

### 1. 実機テストによる動作確認 🔄
- AsyncStream競合修正の効果を実機で検証
- KORGデバイスでPE取得が成功することを確認

### 2. テストコード追加
- PE Inquiry/Reply形式のユニットテスト
- AsyncStream競合のケースをカバーするテスト

### 3. ブロードキャスト vs 特定Destination送信
- 現在は全destinationsにブロードキャスト（デバッグ用）
- 本番ではModule優先のロジックで特定destinationのみに送信すべきか検討

### 4. README更新
- KORG互換性に関する注意事項を追記

---

## 学んだ教訓

### 1. MIDI 2.0デバイスのポートマッピングは複雑

多くのMIDIハードウェア（KORG、Roland等）では:
- Discovery Replyは「Bluetooth」ポートから来る
- Property Exchange通信は「Module」ポートで受け付ける
- **同じデバイスでもポートによって機能が分かれている**

### 2. SwiftのAsyncStreamは単一コンシューマー

- `AsyncStream` は一度しか消費できない
- 複数のコンポーネントが同じストリームを消費しようとすると競合
- **解決策**: 単一のディスパッチャータスクで複数に配布

### 3. UIログとTracerログの両方で確認

- UIで「Module選択」と表示されていても、実際の送信先が違う場合がある
- **MIDITracerで実際のバイト列を確認することが重要**

---

## 参考資料

- `/Users/hakaru/Desktop/Develop/SimpleMidiController/docs/KORG_PropertyExchange_Investigation.md`
  - KORGデバイスのPE調査履歴（Mcoded7不使用など）
  
- `/Users/hakaru/Desktop/Develop/MIDI2Kit/docs/DeviceLogCapture.md`
  - XcodeBuildMCPを使用したデバイスログ取得方法

---

## 更新履歴

| 日時 | 内容 |
|------|------|
| 2026-01-26 18:50 | 本ドキュメント作成 |
