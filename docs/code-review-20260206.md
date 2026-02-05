# コードレビューレポート

## 概要
- レビュー対象: v1.0.6 AsyncStream continuation race condition修正
- レビュー日: 2026-02-06
- コミット: df39f82aa27b3486a2a10cdcbad2943a6237defe
- 修正ファイル: Sources/MIDI2CI/CIManager.swift

## サマリー
- 🔴 Critical: 5件（同様のバグが他のファイルに存在）
- 🟡 Warning: 1件（テストカバレッジ不足）
- 🔵 Suggestion: 0件
- 💡 Nitpick: 0件

## 詳細

### 🔴 [CIManager.swift:170-175] AsyncStream continuation race condition修正 - 正しい

**修正内容**
```swift
// 修正前（バグ）
var continuation: AsyncStream<CIManagerEvent>.Continuation?
self.events = AsyncStream { cont in
    continuation = cont  // 遅延実行されるクロージャ
}
self.eventContinuation = continuation  // この時点でnil!

// 修正後（正しい）
let (stream, continuation) = AsyncStream<CIManagerEvent>.makeStream()
self.events = stream
self.eventContinuation = continuation
```

**評価**
✅ 修正内容は完全に正しい。AsyncStream.makeStream()を使用することで、continuationが即座に利用可能になり、race conditionが解消された。コメントも明確で、将来のメンテナーに意図が伝わる。

**理由**
AsyncStreamのクロージャは「ストリームが最初にイテレートされたとき」に実行されるため、continuationの取得が遅延する。makeStream()は即座にstreamとcontinuationのタプルを返すため、この問題を回避できる。

---

### 🔴 [LoopbackTransport.swift:60-71] 同じrace conditionが存在

**問題**
CIManagerと同じパターンのバグが存在する。

**現在のコード**
```swift
private init(role: Role) {
    self.role = role

    var receivedCont: AsyncStream<MIDIReceivedData>.Continuation?
    self.received = AsyncStream { continuation in
        receivedCont = continuation
    }

    var setupCont: AsyncStream<Void>.Continuation?
    self.setupChanged = AsyncStream { continuation in
        setupCont = continuation
    }

    self.receivedContinuation = receivedCont
    self.setupChangedContinuation = setupCont
}
```

**提案**
```swift
private init(role: Role) {
    self.role = role

    let (receivedStream, receivedCont) = AsyncStream<MIDIReceivedData>.makeStream()
    self.received = receivedStream
    self.receivedContinuation = receivedCont

    let (setupStream, setupCont) = AsyncStream<Void>.makeStream()
    self.setupChanged = setupStream
    self.setupChangedContinuation = setupCont
}
```

**理由**
LoopbackTransportはテスト用のtransportなので、イベントストリームが正しく機能することが重要。現在のコードではイベントが失われる可能性がある。

---

### 🔴 [CoreMIDITransport.swift:107-115] 同じrace conditionが存在

**問題**
本番環境で使用されるCoreMIDITransportにも同じバグが存在する。

**現在のコード**
```swift
public init(clientName: String = "MIDI2Kit") throws {
    // Initialize streams
    var receivedCont: AsyncStream<MIDIReceivedData>.Continuation?
    self.received = AsyncStream { continuation in
        receivedCont = continuation
    }
    // ... (setupChanged も同様)

    self.receivedContinuation = receivedCont
    self.setupChangedContinuation = setupCont
}
```

**提案**
```swift
public init(clientName: String = "MIDI2Kit") throws {
    // Initialize streams
    let (receivedStream, receivedCont) = AsyncStream<MIDIReceivedData>.makeStream()
    self.received = receivedStream
    self.receivedContinuation = receivedCont

    let (setupStream, setupCont) = AsyncStream<Void>.makeStream()
    self.setupChanged = setupStream
    self.setupChangedContinuation = setupCont
}
```

**理由**
CoreMIDITransportはMIDI2Kitの中核コンポーネント。received/setupChangedストリームが正しく機能しないと、すべてのMIDIイベントが失われる可能性がある。**最も優先度が高い修正**。

---

### 🔴 [MockMIDITransport.swift:45-56] 同じrace conditionが存在

**問題**
テスト用のMockTransportにも同じバグが存在する。

**現在のコード**
```swift
public init() {
    var receivedCont: AsyncStream<MIDIReceivedData>.Continuation?
    self.received = AsyncStream { continuation in
        receivedCont = continuation
    }

    var setupCont: AsyncStream<Void>.Continuation?
    self.setupChanged = AsyncStream { continuation in
        setupCont = continuation
    }

    self.receivedContinuation = receivedCont
    self.setupChangedContinuation = setupCont
}
```

**提案**
```swift
public init() {
    let (receivedStream, receivedCont) = AsyncStream<MIDIReceivedData>.makeStream()
    self.received = receivedStream
    self.receivedContinuation = receivedCont

    let (setupStream, setupCont) = AsyncStream<Void>.makeStream()
    self.setupChanged = setupStream
    self.setupChangedContinuation = setupCont
}
```

**理由**
MockTransportはテストで広く使用されている。現在のテストが偶然パスしている可能性があり、将来のテスト追加時に問題が顕在化する恐れがある。

---

### 🔴 [PESubscriptionManager.swift:175-179] 同じrace conditionが存在

**問題**
Subscriptionの自動再接続を担うPESubscriptionManagerにも同じバグが存在する。

**現在のコード**
```swift
public init(
    peManager: PEManager,
    ciManager: CIManager,
    logger: any MIDI2Logger = NullMIDI2Logger()
) {
    self.peManager = peManager
    self.ciManager = ciManager
    self.logger = logger

    // Create event stream
    var continuation: AsyncStream<PESubscriptionEvent>.Continuation?
    self.events = AsyncStream { cont in
        continuation = cont
    }
    self.eventContinuation = continuation
}
```

**提案**
```swift
public init(
    peManager: PEManager,
    ciManager: CIManager,
    logger: any MIDI2Logger = NullMIDI2Logger()
) {
    self.peManager = peManager
    self.ciManager = ciManager
    self.logger = logger

    let (stream, continuation) = AsyncStream<PESubscriptionEvent>.makeStream()
    self.events = stream
    self.eventContinuation = continuation
}
```

**理由**
PESubscriptionManagerのeventsストリームは、subscription状態の変化を通知する重要な機能。イベントが失われると、アプリケーションがsubscription状態を正しく追跡できなくなる。

---

### 🟡 [CIManagerTests.swift] イベントストリームのテストカバレッジ不足

**問題**
CIManagerTests.swiftに`events`ストリームを直接テストするケースが存在しない。

**現在の状況**
- 7つのテストが存在
- デバイス登録・削除のロジックはテストされている
- しかし、`manager.events`をイテレートしてイベントを検証するテストがない

**提案**
以下のようなテストを追加:

```swift
@Test("CIManager emits deviceDiscovered event")
func emitsDeviceDiscoveredEvent() async throws {
    let transport = MockMIDITransport()
    defer { Task { await transport.shutdown() } }
    await transport.addDestination(MIDIDestinationInfo(
        destinationID: MIDIDestinationID(1),
        name: "Test"
    ))

    let manager = CIManager(transport: transport)
    let managerMUID = manager.muid

    try await manager.start()

    // Start listening to events
    var receivedEvents: [CIManagerEvent] = []
    let eventTask = Task {
        for await event in manager.events {
            receivedEvents.append(event)
            if case .deviceDiscovered = event {
                break  // Got the event we're looking for
            }
        }
    }

    // Simulate Discovery Reply
    let deviceMUID = MUID(rawValue: 0xABCDEF0)!
    let reply = CIMessageBuilder.discoveryReply(
        sourceMUID: deviceMUID,
        destinationMUID: managerMUID,
        deviceIdentity: DeviceIdentity(
            manufacturerID: .korg,
            familyID: 0x0001,
            modelID: 0x0002,
            versionID: 0x00010000
        ),
        categorySupport: .propertyExchange
    )

    await transport.simulateReceive(reply, from: MIDISourceID(1))

    // Wait for event
    try await Task.sleep(for: .milliseconds(200))
    eventTask.cancel()

    // Verify event was emitted
    #expect(receivedEvents.count >= 1)
    let firstEvent = receivedEvents.first
    if case .deviceDiscovered(let device) = firstEvent {
        #expect(device.muid == deviceMUID)
    } else {
        Issue.record("Expected deviceDiscovered event, got \(String(describing: firstEvent))")
    }

    await manager.stop()
}

@Test("CIManager emits deviceLost event on timeout")
func emitsDeviceLostEvent() async throws {
    // Similar test for deviceLost event
    // ...
}
```

**理由**
今回のバグは「イベントストリームが機能しない」という問題だったが、既存のテストでは検出できなかった。イベントストリームを直接テストすることで、将来の同様のバグを防げる。

---

## 良かった点

### ✅ 明確なコメントとコミットメッセージ
修正コードに以下の明確なコメントが追加されている:

```swift
// Use makeStream() to ensure continuation is available immediately
// The old closure-based approach had a race condition where continuation
// was nil until the stream was first iterated
```

コミットメッセージも問題と解決策を的確に説明しており、将来のメンテナーに役立つ。

### ✅ 根本原因の正しい理解
AsyncStreamのクロージャが遅延実行されるという仕様を正しく理解し、適切な解決策（makeStream()）を選択している。

### ✅ GitHub issue連携
コミットメッセージに`Fixes midi2kit/MIDI2Kit-SDK#1`を含めることで、issueが自動クローズされる仕組みを活用している。

---

## 総評

### 修正内容の評価: ⭐⭐⭐⭐⭐ 5.0/5
CIManager.swiftの修正は完璧。問題の本質を正確に理解し、最適な解決策を実装している。

### コードベース全体の評価: ⭐⭐ 2.0/5（緊急対応必要）
**同じバグが他の4ファイルに存在**しており、特にCoreMIDITransportは本番環境で使用される中核コンポーネントのため、早急な修正が必要。

### 推奨アクション（優先度順）

1. **🔴 最優先**: CoreMIDITransport.swift修正（本番環境に影響）
2. **🔴 高優先**: MockMIDITransport.swift修正（テストの信頼性）
3. **🔴 高優先**: LoopbackTransport.swift修正（テストの信頼性）
4. **🔴 中優先**: PESubscriptionManager.swift修正（機能の信頼性）
5. **🟡 中優先**: イベントストリームの統合テスト追加（回帰防止）
6. **🔵 低優先**: ReceiveHub.swiftの確認（makeStream()の逆パターンで正しい実装）

### 技術的負債の指摘
プロジェクト全体で「AsyncStream初期化」パターンに一貫性がない。以下の2パターンが混在:

- **パターンA（バグあり）**: クロージャベース - `AsyncStream { cont in ... }`
- **パターンB（正しい）**: makeStream() - `AsyncStream<T>.makeStream()`

今後は**パターンBを標準パターン**として採用し、コーディング規約に明記することを推奨。

### 再発防止策
1. Linter/Static Analyzerで「AsyncStream { }パターン」を検出するルール追加
2. プロジェクトのCLAUDE.mdに「AsyncStream初期化は必ずmakeStream()を使用」と明記
3. SwiftTestingで「イベントストリームの動作テスト」をテンプレート化

---

## 参考情報

### AsyncStream.makeStream() vs クロージャ初期化

| 方式 | continuation取得タイミング | 推奨用途 |
|------|---------------------------|---------|
| `AsyncStream { }` | ストリームの最初のイテレート時（遅延） | 単発使用のストリーム |
| `.makeStream()` | 即座に取得 | **actorのプロパティとして保持する場合（推奨）** |

### 影響範囲の調査結果

```bash
# AsyncStream初期化パターンの検索結果
makeStream():                1ファイル  ✅ CIManager.swift（修正済み）
AsyncStream { クロージャ }:  7ファイル  🔴 4ファイルにバグあり

バグあり:
- Sources/MIDI2Transport/LoopbackTransport.swift
- Sources/MIDI2Transport/CoreMIDITransport.swift
- Sources/MIDI2Transport/MockMIDITransport.swift
- Sources/MIDI2PE/PESubscriptionManager.swift

バグなし（正しい使用例）:
- Sources/MIDI2PE/PEManager.swift（dict経由で管理）
- Sources/MIDI2PE/PESubscriptionHandler.swift（dict経由で管理）
- Sources/MIDI2Kit/HighLevelAPI/ReceiveHub.swift（makeStream()パターン）
```

---

## 次のステップ

1. 本レビューレポートをチームで共有
2. 🔴 Critical修正のプルリクエスト作成（v1.0.7候補）
3. 🟡 テストケース追加のissue作成
4. コーディング規約の更新（CLAUDE.md）
5. CI/CDパイプラインにLintルール追加の検討

---

**レビュアー**: Claude Opus 4.5
**レビュー完了日時**: 2026-02-06 00:26 JST
