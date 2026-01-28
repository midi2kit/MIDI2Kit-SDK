# PESendStrategy 設計書

## 1. 背景と問題

### 1.1 現状の問題

KORG Module Pro対応のため、PEリクエストを**全Destination**にブロードキャスト送信している。

```
現状: PE Request → 全Destinationに送信（broadcast）
```

**問題点:**
- 単一デバイス環境では動作する
- **Logic Pro等の他アプリ/デバイスが同居すると副作用リスク**
  - 不要なSysEx受信
  - ログ汚染
  - 予期せぬ反応

### 1.2 KORG特有の問題

KORGデバイスは以下の非対称ルーティングを持つ：
- Discovery応答: Bluetoothポートから返る
- PE応答: Moduleポートから返る（または逆）
- どのポートに送信しても応答が別ポートから返ることがある

このため「正しい送信先を1つに決められない」状況が発生。

---

## 2. 解決策: PESendStrategy

### 2.1 戦略の種類

```swift
public enum PESendStrategy: Sendable {
    /// 単一Destinationに送信（標準的なMIDI 2.0デバイス向け）
    case single
    
    /// 全Destinationにブロードキャスト（デバッグ・緊急用）
    case broadcast
    
    /// 段階的フォールバック（推奨）
    /// 1. 推測されるポート（"Module"等）に送信
    /// 2. タイムアウト → 成功履歴があればそこに送信
    /// 3. それでもタイムアウト → broadcast
    case fallback
    
    /// 学習済みのDestinationのみに送信
    /// （成功Destinationキャッシュを利用）
    case learned
}
```

### 2.2 フォールバック戦略の流れ

```
┌─────────────────────────────────────────────────────────┐
│                    PE Request                           │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│ Step 1: キャッシュにヒットするか？                        │
│         (MUID → 成功Destination)                        │
└─────────────────────────────────────────────────────────┘
          │                              │
         Yes                            No
          │                              │
          ▼                              ▼
┌──────────────────┐     ┌─────────────────────────────────┐
│ キャッシュ先に送信 │     │ Step 2: 推測ポートに送信         │
│ (Unicast)        │     │ - "Module" を含む名前           │
└──────────────────┘     │ - DestinationStrategy.preferModule │
          │              └─────────────────────────────────┘
          ▼                              │
     ┌────────┐                    Timeout?
     │ 成功？ │                          │
     └────────┘                    ┌─────┴─────┐
      Yes │ No                    Yes         No
          │  │                     │           │
          │  ▼                     ▼           ▼
          │ キャッシュ無効化  ┌────────────────┐  成功
          │                 │ Step 3: Broadcast │  ↓
          ▼                 └────────────────┘ キャッシュ更新
       完了                        │
                                   ▼
                              成功時: キャッシュ更新
```

### 2.3 成功Destinationキャッシュ

```swift
/// 成功したMUID → Destinationのマッピング
actor DestinationCache {
    /// キャッシュエントリ
    struct Entry: Sendable {
        let destinationID: MIDIEntityRef
        let lastSuccess: Date
        var successCount: Int
    }
    
    private var cache: [MUID: Entry] = [:]
    
    /// 成功を記録
    func recordSuccess(muid: MUID, destination: MIDIEntityRef)
    
    /// キャッシュされたDestinationを取得
    func getCachedDestination(for muid: MUID) -> MIDIEntityRef?
    
    /// キャッシュを無効化
    func invalidate(muid: MUID)
    
    /// 古いエントリをクリア（TTL: 30分等）
    func pruneStale(olderThan: TimeInterval)
}
```

## 3. 現状の実装調査結果

### 3.1 Broadcast実装箇所

**ファイル**: `Sources/MIDI2PE/PEManager.swift`
**メソッド**: `scheduleSendForRequest()`

```swift
private func scheduleSendForRequest(
    requestID: UInt8,
    message: [UInt8],
    destination: MIDIDestinationID  // ← 受け取るが無視
) {
    // ...
    sendTasks[requestID] = Task { [weak self] in
        // WORKAROUND: Broadcast to all destinations for KORG compatibility
        // KORG devices may not respond when sent to specific destinations,
        // but will respond when the message reaches them via broadcast.
        try await transport.broadcast(message)  // ← 全Destinationに送信
    }
}
```

### 3.2 比較: Subscribeは単一送信

```swift
private func scheduleSendForSubscribe(
    requestID: UInt8,
    message: [UInt8],
    destination: MIDIDestinationID
) {
    // ...
    try await transport.send(message, to: destination)  // ← 単一Destination
}
```

### 3.3 問題の構造

| メソッド | 送信方法 | 副作用リスク |
|---|---|---|
| scheduleSendForRequest | broadcast() | 高（Logic Pro等に影響） |
| scheduleSendForSubscribe | send() | 低 |

---

## 4. 実装計画

### Phase 1: 現状調査
1. `PEManager`のbroadcast実装箇所を特定
2. 現在の`DestinationResolver`との連携を確認
3. 影響範囲の洗い出し

### Phase 2: 基盤実装
1. `PESendStrategy` enum追加
2. `DestinationCache` actor実装
3. `MIDI2ClientConfiguration`に`peSendStrategy`追加

### Phase 3: PEManager修正
1. `scheduleSendForRequest()`の修正
2. フォールバックロジックの実装
3. 成功時のキャッシュ更新

### Phase 4: テスト
1. 単体テスト（MockMIDITransport）
2. 実機テスト（KORGのみ）
3. **シナリオC: Logic Pro + KORG同居テスト**

---

## 4. Configuration拡張

```swift
public struct MIDI2ClientConfiguration {
    // ... 既存プロパティ ...
    
    // MARK: - PE Send Strategy
    
    /// PE送信戦略（デフォルト: .fallback）
    public var peSendStrategy: PESendStrategy = .fallback
    
    /// フォールバック時の各ステップのタイムアウト（デフォルト: 500ms）
    public var fallbackStepTimeout: Duration = .milliseconds(500)
    
    /// キャッシュの有効期限（デフォルト: 30分）
    public var destinationCacheTTL: Duration = .seconds(1800)
}
```

---

## 5. 受け入れ条件

### 必須（v1.0ブロッカー）
- [ ] `PESendStrategy.fallback`がデフォルトで動作
- [ ] KORGでDeviceInfo取得が成功
- [ ] Logic Pro同居環境で副作用なし（SysEx漏れなし）
- [ ] 成功Destinationがキャッシュされ、2回目以降はUnicast

### 推奨
- [ ] キャッシュヒット率のログ出力
- [ ] 診断情報に送信戦略の状態を含む
- [ ] Broadcast使用時の警告ログ

---

## 6. リスクと軽減策

| リスク | 影響 | 軽減策 |
|---|---|---|
| フォールバックがKORGで動かない | PE取得失敗 | 最終段階でbroadcastに落ちる |
| キャッシュが古くなる | 誤ったDestinationに送信 | TTL + タイムアウト時の無効化 |
| 複数デバイスで混乱 | キャッシュ衝突 | MUIDをキーにするため衝突なし |

---

## 7. 関連ドキュメント

- [KORG-PE-Compatibility.md](./KORG-PE-Compatibility.md)
- [KORG-Module-Pro-Limitations.md](./KORG-Module-Pro-Limitations.md)
- [DestinationStrategy.swift](../Sources/MIDI2Kit/HighLevelAPI/DestinationStrategy.swift)
- [EvaluationReview-2026-01-28.md](./EvaluationReview-2026-01-28.md)
