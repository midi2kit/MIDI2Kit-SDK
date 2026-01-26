# MIDI2Kit 高レベルAPI設計会議 議事録

**日付**: 2026年1月27日  
**目的**: docs以下の提案ドキュメントを分析し、統合TODOリストを作成する

---

## 1. 分析対象ドキュメント

| ファイル | 内容 |
|----------|------|
| PE_Stability_Roadmap.md | PE安定化の3つの主因と実装ロードマップ |
| HighLevelAPIProposal.md | MIDI2Client/MIDI2Device等の高レベルAPI提案 |
| MIDI2ClientGuide.md | 高レベルAPI使用ガイド（将来版） |
| PEIssueHistory.md | PE問題の調査経緯と解決記録 |
| PE_Implementation_Notes.md | MIDI-CI 1.2 メッセージフォーマット仕様 |
| 2026-01-26.md | プロジェクト活動報告 |

---

## 2. 特定された3つの主要問題

### 問題1: AsyncStream単一コンシューマ問題 🔴 Critical

**現象**: `CIManager.start()` と `PEManager.startReceiving()` が同じ `transport.received` ストリームを消費しようとして競合。

**現状の回避策**（アプリ側で実装）:
```swift
receiveDispatcherTask = Task {
    for await received in transport.received {
        await ciManager.handleReceivedExternal(received)
        await peManager.handleReceivedExternal(received.data)
    }
}
```

**問題点**: アプリ開発者が知らないと踏む地雷。`start()` を呼んではいけない非直感的なAPI。

### 問題2: Destination mismatch 🔴 Critical

**現象**: KORGデバイスで「Discovery ReplyはBluetoothソースから返るが、PE通信はModuleポートで行う必要がある」。

**KORGのポート構造**:
```
Sources:  Bluetooth, Session 1
Destinations: Bluetooth, Session 1, Module ← PEはここ
```

### 問題3: PE Get Inquiryフォーマット 🟡 High

**現象**: Inquiryに `numChunks/thisChunk` フィールドを含めてしまっていた。

**修正済み**: ただしテストがないため回帰リスクあり。

---

## 3. 外部レビューからの追加要件

### 3-1. Multicast対応イベントストリーム

**問題**: `events` プロパティだと単一コンシューマ問題が再発。

**解決策**: メソッドで新規ストリームを生成。
```swift
func makeEventStream() -> AsyncStream<MIDI2ClientEvent>
```

### 3-2. 構造化された設定API

**提案**:
```swift
public struct MIDI2ClientConfiguration: Sendable {
    public var discoveryInterval: Duration = .seconds(10)
    public var deviceTimeout: Duration = .seconds(60)
    public var peTimeout: Duration = .seconds(5)
    public var destinationStrategy: DestinationStrategy = .preferModule
}

// 初期化
init(name: String, preset: ClientPreset = .default)
init(name: String, configuration: MIDI2ClientConfiguration)
```

### 3-3. stop() / deinit の責務明確化

1. **受信タスクの強制終了**: MIDITransport の監視を停止
2. **未完了トランザクションの破棄**: 全 pendingContinuations を `PEError.cancelled` で再開
3. **購読のクリーンアップ**: ベストエフォートで unsubscribe、内部ストリームを `finish()`
4. **MUID 無効化**: Invalidate メッセージを放送

### 3-4. フォールバック付きDestination解決

- 初回リクエストがタイムアウト → 次優先ポートへ**1回だけ自動リトライ**
- 解決成功したポートIDはMUID有効期間中キャッシュ

### 3-5. JSONプリプロセッサ（耐障害性パース）

- 非標準JSON（末尾カンマ等）を `JSONDecoder` 前に正規表現で自動修復
- デコード失敗時は `invalidResponse` エラーに生データ（Data）を付随

### 3-6. MIDI2Error 体系

| ケース | 意味 | 包含情報 |
|--------|------|----------|
| `.deviceNotResponding` | PE応答なし | device, timeout |
| `.propertyNotSupported` | リソースが存在しない | resource |
| `.communicationFailed` | 物理的な切断・トランスポートエラー | underlying Error |

---

## 4. 追加レビューからの重要指摘（4項目）

### 指摘1: ReceiveHub統一設計 🔴 必須

**問題**: `makeEventStream()` で回避方針は書けているが、実装で「複数購読にどう配るか」を決めないと別形態でハマりが再発する。

**採用する仕様**:

```swift
/// 内部の受信ハブ - transport受信もevents配信も同じ設計で統一
internal actor ReceiveHub {
    private var subscribers: [UUID: AsyncStream<MIDI2ClientEvent>.Continuation] = [:]
    
    /// バッファポリシー
    let bufferPolicy: AsyncStream<MIDI2ClientEvent>.Continuation.BufferingPolicy = .bufferingNewest(100)
    
    /// 新規ストリームを生成（呼び出しごとに独立）
    func makeStream() -> AsyncStream<MIDI2ClientEvent> {
        AsyncStream(bufferingPolicy: bufferPolicy) { continuation in
            let id = UUID()
            subscribers[id] = continuation
            continuation.onTermination = { _ in
                Task { await self.removeSubscriber(id) }
            }
        }
    }
    
    /// 全購読者にイベントを配信
    func broadcast(_ event: MIDI2ClientEvent) {
        for continuation in subscribers.values {
            continuation.yield(event)  // バッファ超過時は古いものをdrop
        }
    }
    
    /// stop()時に全ストリームをfinish
    func finishAll() {
        for continuation in subscribers.values {
            continuation.finish()
        }
        subscribers.removeAll()
    }
}
```

**設計方針**:
- transport受信 → `ReceiveHub` → CI/PE両マネージャー
- events配信 → 同じ `ReceiveHub` 設計パターン
- バッファポリシー: `.bufferingNewest(100)` でdrop方針を明示

### 指摘2: Destination fallback の安全弁 🔴 必須

**採用する仕様**:

| ルール | 内容 |
|--------|------|
| リトライ回数 | **1リクエスト内で最大1回** |
| キャッシュ | 成功したらMUID寿命中固定 |
| 診断情報 | 失敗時は `diagnostics` に候補一覧/試行順/最後のdestを記録 |

```swift
/// Destination解決の診断情報
public struct DestinationDiagnostics: Sendable {
    public let muid: MUID
    public let candidates: [MIDIDestinationInfo]   // 候補一覧
    public let triedOrder: [MIDIDestinationID]     // 試行順
    public let lastAttempted: MIDIDestinationID?   // 最後に試したdest
    public let resolvedDestination: MIDIDestinationID?  // 成功時のdest
    public let failureReason: String?              // 失敗理由
}
```

### 指摘3: stop() の観測可能な完了条件 🔴 必須

**採用する仕様**:

| 条件 | 挙動 |
|------|------|
| `stop()` 後の `makeEventStream()` | 即座に `finish()` されたストリームを返す（新規イベントは来ない） |
| pending PE | **必ず** `PEError.cancelled` で解放される（ID枯渇防止） |
| 状態確認 | `isRunning: Bool` プロパティで確認可能 |

```swift
public actor MIDI2Client {
    /// クライアントが稼働中かどうか
    public var isRunning: Bool { get }
    
    /// stop()後のmakeEventStream()は即finish
    public func makeEventStream() -> AsyncStream<MIDI2ClientEvent> {
        guard isRunning else {
            // 即座にfinishされたストリームを返す
            return AsyncStream { $0.finish() }
        }
        return hub.makeStream()
    }
    
    public func stop() async {
        isRunning = false
        
        // 1. 全pending PEをcancelledで解放（ID枯渇防止）
        await peManager.cancelAllPending()
        
        // 2. 受信タスク停止
        receiveTask?.cancel()
        
        // 3. 全イベントストリームをfinish
        await hub.finishAll()
        
        // 4. MUID無効化放送
        await ciManager.invalidateMUID()
    }
}
```

### 指摘4: Phase 1-1 の受入基準追加 🟡 推奨

**採用する受入基準**:

Phase 1-1 実機テストの合格条件:

| # | 条件 | 内容 |
|---|------|------|
| ✅ | 成功パス | KORGでDiscovery成功 → PE DeviceInfo取得成功 |
| ✅ | **失敗検出** | 失敗時に「原因がログで確定できる」 |
| | | - destination mismatch → ログに「tried: X, expected: Y」 |
| | | - timeout → ログに「候補一覧と試行順」 |
| | | - parse error → ログに「生データhex dump」 |

```swift
// 失敗時のログ出力例
logger.error("""
    PE Request failed:
    - MUID: \(muid)
    - Resource: \(resource)
    - Candidates: \(candidates.map { $0.name })
    - Tried: \(triedOrder)
    - Last destination: \(lastAttempted?.name ?? "none")
    - Reason: \(failureReason)
    """)
```

---

## 5. 採用した3フェーズロードマップ（更新版）

### Phase 1: Core Update（P0 緊急）

| # | タスク | 詳細 | 工数 | 状態 |
|---|--------|------|------|------|
| 1-1 | **実機テストでPE取得成功確認** | 受入基準: 成功パス + 失敗検出 | 1-2時間 | ⏳ |
| 1-2 | handleReceivedExternal() の公式API化 | ReceiveHub設計で統一 | 0.5日 | 📋 |
| 1-3 | PE Inquiry/Replyフォーマットテスト追加 | 回帰防止 | 0.5日 | 📋 |

### Phase 2: High-Level API（P1 重要）

| # | タスク | 詳細 | 工数 | 状態 |
|---|--------|------|------|------|
| 2-1 | **MIDI2Client Actor実装** | ReceiveHub内蔵、stop()完了条件明確化 | 2-3日 | 📋 |
| 2-2 | **MIDI2ClientConfiguration** | 4プロパティ | 0.5日 | 📋 |
| 2-3 | **DestinationStrategy.preferModule** | fallback安全弁 + diagnostics | 1日 | 📋 |
| 2-4 | **MIDI2Device Actor実装** | getProperty<T>, キャッシュ | 1-2日 | 📋 |
| 2-5 | **MIDI2Error 3ケース実装** | | 0.5日 | 📋 |

### Phase 3: Resilience（P2 改善）

| # | タスク | 詳細 | 工数 | 状態 |
|---|--------|------|------|------|
| 3-1 | **JSONプリプロセッサ** | 非標準JSON自動修復 | 0.5日 | 📋 |
| 3-2 | **マルチキャストイベントシステム完成** | ReceiveHub最適化 | 1日 | 📋 |
| 3-3 | デバッグ支援（diagnostics, trace） | DestinationDiagnostics含む | 0.5日 | 📋 |
| 3-4 | README/ドキュメント更新 | KORG互換性、高レベルAPI使用法 | 0.5日 | 📋 |
| 3-5 | Coreリポジトリ Public化 | | 0.5日 | 📋 |

---

## 6. 設計決定事項（更新版）

### 6-1. MIDI2Client API設計（最終版）

```swift
/// MIDI 2.0 統合クライアント
public actor MIDI2Client {
    
    // MARK: - Internal
    
    private let hub: ReceiveHub  // 統一されたマルチキャスト配信
    private var isRunning: Bool = false
    
    // MARK: - Initialization
    
    /// プリセットで初期化
    public init(name: String, preset: ClientPreset = .default) throws
    
    /// カスタム設定で初期化
    public init(name: String, configuration: MIDI2ClientConfiguration) throws
    
    // MARK: - Lifecycle
    
    /// クライアントが稼働中かどうか
    public var isRunning: Bool { get }
    
    /// クライアントを開始（Discovery自動開始）
    public func start() async throws
    
    /// クライアントを停止
    /// 【保証】
    /// - 全pending PEは必ずPEError.cancelledで解放
    /// - 全イベントストリームはfinish()される
    /// - stop()後のmakeEventStream()は即finish
    public func stop() async
    
    // MARK: - Events (Multicast対応)
    
    /// 新しいイベントストリームを生成
    /// - 呼び出すたびに新規ストリームを返す
    /// - バッファポリシー: bufferingNewest(100)
    /// - stop()後は即finishされたストリームを返す
    public func makeEventStream() -> AsyncStream<MIDI2ClientEvent>
    
    // MARK: - Devices
    
    /// 検出されたデバイス一覧
    public var devices: [MIDI2Device] { get async }
    
    // MARK: - PE Convenience
    
    public func getDeviceInfo(from muid: MUID) async throws -> PEDeviceInfo
    public func getResourceList(from muid: MUID) async throws -> [PEResourceEntry]
    public func get(_ resource: String, from muid: MUID) async throws -> PEResponse
    
    // MARK: - Diagnostics
    
    /// 最後のDestination解決診断情報
    public var lastDestinationDiagnostics: DestinationDiagnostics? { get async }
}
```

### 6-2. MIDI2ClientConfiguration

```swift
public struct MIDI2ClientConfiguration: Sendable {
    public var discoveryInterval: Duration = .seconds(10)
    public var deviceTimeout: Duration = .seconds(60)
    public var peTimeout: Duration = .seconds(5)
    public var destinationStrategy: DestinationStrategy = .preferModule
    
    public static let `default` = MIDI2ClientConfiguration()
    public static let explorer = MIDI2ClientConfiguration(
        discoveryInterval: .seconds(5),
        deviceTimeout: .seconds(120)
    )
}
```

### 6-3. DestinationStrategy（安全弁付き）

```swift
public enum DestinationStrategy: Sendable {
    /// 自動（デバイス固有ルールを適用）
    case automatic
    
    /// Module優先（KORG等向け）- デフォルト
    /// - タイムアウト時: 次候補へ1回だけリトライ
    /// - 成功時: MUID寿命中キャッシュ
    case preferModule
    
    /// 名前マッチング優先
    case preferNameMatch
    
    /// カスタムロジック
    case custom(@Sendable (MUID, [MIDIDestinationInfo]) async -> MIDIDestinationID?)
}
```

### 6-4. DestinationDiagnostics（新規）

```swift
/// Destination解決の診断情報
public struct DestinationDiagnostics: Sendable {
    public let muid: MUID
    public let candidates: [MIDIDestinationInfo]
    public let triedOrder: [MIDIDestinationID]
    public let lastAttempted: MIDIDestinationID?
    public let resolvedDestination: MIDIDestinationID?
    public let failureReason: String?
    public let timestamp: Date
}
```

---

## 7. 次のアクション（優先順）

1. **Phase 1-1**: 実機テスト（受入基準: 成功パス + 失敗検出）
2. **Phase 1-2**: handleReceivedExternal() 公式化（ReceiveHub設計）
3. **Phase 1-3**: PE Inquiryテスト追加（回帰封じ）
4. **Phase 2-1/2-3**: MIDI2Client + preferModule/fallback/caching

---

## 8. 関連ドキュメント

| ドキュメント | 内容 |
|-------------|------|
| [PE_Stability_Roadmap.md](./PE_Stability_Roadmap.md) | 詳細な問題分析とロードマップ |
| [HighLevelAPIProposal.md](./HighLevelAPIProposal.md) | 元の高レベルAPI提案 |
| [PEIssueHistory.md](./PEIssueHistory.md) | PE問題の調査経緯 |
| [TODO.md](./TODO.md) | チェックボックス形式のTODOリスト |

---

## 9. Deprecation計画

MIDI2Client導入により隠蔽されるAPIをDeprecatedとしてマークし、将来的に削除する計画。

### 9-1. Deprecationの方針

| 方針 | 内容 |
|------|------|
| **段階的移行** | 既存APIは即座に削除せず、`@available(*, deprecated)` でマーク |
| **移行期間** | v1.0までは両方のAPIを維持、v2.0で削除検討 |
| **メッセージ** | 代替APIへの移行方法を明示 |

### 9-2. CIManagerのDeprecated API

| API | 理由 | 代替API |
|-----|------|----------|
| `init(transport:)` | MIDI2Clientが内部で管理 | `MIDI2Client.init(name:)` |
| `start()` | AsyncStream競合の罠 | `MIDI2Client.start()` |
| `stop()` | 同上 | `MIDI2Client.stop()` |
| `startDiscovery()` | 同上 | `MIDI2Client.start()` が自動開始 |
| `stopDiscovery()` | 同上 | 不要（stop()で停止） |
| `events` プロパティ | 単一コンシューマ問題 | `MIDI2Client.makeEventStream()` |
| `destination(for:)` | MIDI2Clientが自動解決 | 不要（内部で解決） |
| `makeDestinationResolver()` | 同上 | 不要 |

### 9-3. PEManagerのDeprecated API

| API | 理由 | 代替API |
|-----|------|----------|
| `init(transport:sourceMUID:)` | MIDI2Clientが内部で管理 | `MIDI2Client.init(name:)` |
| `startReceiving()` | AsyncStream競合の罠 | `MIDI2Client.start()` |
| `stopReceiving()` | 同上 | `MIDI2Client.stop()` |
| `destinationResolver` プロパティ | MIDI2Clientが自動設定 | 不要 |
| `get(_:from:PEDeviceHandle)` | MUIDのみAPIへ移行 | `MIDI2Client.get(_:from:MUID)` |
| `set(_:data:to:PEDeviceHandle)` | 同上 | `MIDI2Client.set(_:data:to:MUID)` |
| `handleReceivedExternal(_:)` | MIDI2Clientが内部で呼び出し | 不要（内部化） |

### 9-4. 維持するAPI（Deprecatedしない）

| API | 理由 |
|-----|------|
| `PEDeviceHandle` | 低レベルアクセスが必要な場合に有用 |
| `PERequest` / `PEResponse` | データ構造として維持 |
| `PEError` | エラー型として維持（MIDI2Errorにラップ） |
| `DiscoveredDevice` | MIDI2Deviceへの変換元として維持 |
| `CIMessageBuilder` / `CIMessageParser` | 低レベルプロトコル操作用 |

### 9-5. Deprecationコード例

```swift
// CIManager.swift
extension CIManager {
    @available(*, deprecated, message: "Use MIDI2Client instead. CIManager.start() causes AsyncStream conflicts.")
    public func start() async throws {
        // 既存実装
    }
    
    @available(*, deprecated, renamed: "MIDI2Client.makeEventStream()")
    public nonisolated var events: AsyncStream<CIManagerEvent> {
        // 既存実装
    }
}

// PEManager.swift
extension PEManager {
    @available(*, deprecated, message: "Use MIDI2Client instead. PEManager.startReceiving() causes AsyncStream conflicts.")
    public func startReceiving() async {
        // 既存実装
    }
    
    @available(*, deprecated, message: "Use MIDI2Client.get(_:from:MUID) instead")
    public func get(
        _ resource: String,
        from device: PEDeviceHandle,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        // 既存実装
    }
}
```

### 9-6. 移行ガイド例

```swift
// Before (v0.x - Deprecated)
let transport = try CoreMIDITransport(clientName: "MyApp")
let ciManager = CIManager(transport: transport)
let peManager = PEManager(transport: transport, sourceMUID: ciManager.muid)
peManager.destinationResolver = ciManager.makeDestinationResolver()

// ❗ AsyncStream競合の罠を踏む
try await ciManager.start()
await peManager.startReceiving()

for await event in ciManager.events {
    // ...
}

// After (v1.0+ - Recommended)
let client = try MIDI2Client(name: "MyApp")
try await client.start()

for await event in client.makeEventStream() {
    switch event {
    case .deviceDiscovered(let device):
        // PEも簡単
        let info = try await client.getDeviceInfo(from: device.muid)
    // ...
    }
}
```

---

## 更新履歴

| 日時 | 内容 |
|------|------|
| 2026-01-27 19:32 | 初版作成 - docs分析・レビュー吸収・TODOリスト統合 |
| 2026-01-27 19:37 | 追加レビュー反映 - ReceiveHub統一設計、fallback安全弁、stop()完了条件、Phase1-1受入基準 |
| 2026-01-27 19:43 | Deprecation計画追加 - CIManager/PEManagerのDeprecated API一覧、移行ガイド |
