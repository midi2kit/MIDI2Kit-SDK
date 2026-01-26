# MIDI2Kit Property Exchange 安定化ロードマップ

## 概要

本ドキュメントは、MIDI2Kit の Property Exchange (PE) 機能における不安定性の根本原因分析、過去の調査経緯、および安定化に向けた実装ロードマップを統合したものである。

**作成日**: 2026-01-26  
**ステータス**: 実装計画（Approved）

---

## 第1部: 問題の全体像

### PE不安定の3つの主因

| # | 問題 | 影響度 | 状態 |
|---|------|--------|------|
| 1 | **AsyncStream単一コンシューマ問題** | 🔴 Critical | 回避策あり（アプリ側） |
| 2 | **Destination mismatch** | 🔴 Critical | 部分的対応済み |
| 3 | **PE Get Inquiryフォーマット** | 🟡 High | 修正済み（テストなし） |

### 因果関係の流れ

```
問題(1): AsyncStream競合
    ↓ PE Replyを受信できない
問題(2): Destination mismatch  
    ↓ 受信できてもMUIDが不一致
問題(3): Inquiryフォーマット
    ↓ そもそもデバイスが応答しない
```

---

## 第2部: 各問題の詳細

### 問題1: AsyncStream単一コンシューマ問題

#### 現象

SwiftのAsyncStreamは一度しか消費できない。`CIManager.start()` と `PEManager.startReceiving()` が同じ `transport.received` を消費しようとすると、**片方しかデータを受け取れない**。

#### 根本原因

```swift
// CIManager.start() 内
for await received in transport.received { ... }  // ストリーム消費

// PEManager.startReceiving() 内  
for await received in transport.received { ... }  // 競合！
```

#### 現状の回避策（アプリ側）

```swift
// MIDI2Explorer/ContentView.swift (AppState)
receiveDispatcherTask = Task {
    for await received in transport.received {
        await ciManager.handleReceivedExternal(received)
        await peManager.handleReceivedExternal(received.data)
    }
}
```

#### 問題点

- **アプリ開発者が知らないと踏む地雷**
- `ciManager.start()` を呼んではいけないという**非直感的なAPI**
- 全アプリで同じ回避策を実装する必要がある

---

### 問題2: Destination mismatch

#### 現象

KORGデバイスで「Discovery ReplyはBluetoothソースから返るが、PE通信はModuleポートで行う必要がある」という現象が発生。

#### KORGデバイスのポート構造

```
Sources:
  - Bluetooth (0x00C50040)  ← Discovery Replyはここから来る
  - Session 1

Destinations:
  - Module (0x00C50052)     ← PEはここに送る必要がある
  - Bluetooth (0x00C50041)
  - Session 1 (0x00C50016)
```

#### 根本原因

`CIManager.destination(for:)` は**Discovery時のsourceIDからdestinationを推測**するが、KORG等のデバイスでは**探索とPEで使用するポートが異なる**。

#### 現状の対応

```swift
// CIManager.findDestination() でModule優先ロジックを実装
if let moduleDest = destinations.first(where: { $0.name.lowercased().contains("module") }) {
    return moduleDest.destinationID
}
```

#### 問題点

- ロジックが**CIManager内部に埋もれている**
- PE専用のdestination解決APIがない
- タイムアウト時のフォールバック戦略がない

---

### 問題3: PE Get Inquiryフォーマット

#### 現象

PE Get Inquiryに `numChunks/thisChunk` フィールドを含めてしまっていた。MIDI-CI仕様では**Inquiryにはこれらを含めない**のが正しい。

#### 修正内容

- Inquiryから `numChunks/thisChunk` を削除
- `headerData` の開始位置を修正

#### 問題点

- **テストがないため回帰リスクがある**

---

## 第3部: 実装ロードマップ

### Phase 1: P0（最優先）- ライブラリ側での吸収

#### P0-1: 受信1本化の標準機能化

**目的**: AsyncStream競合をライブラリ内部で解決

**実装案A: TransportReceiveHub**

```swift
/// 受信データを複数の購読者に配信するハブ
public actor TransportReceiveHub {
    private let transport: any MIDITransport
    private var subscribers: [UUID: @Sendable (MIDIReceivedData) async -> Void] = [:]
    private var dispatchTask: Task<Void, Never>?
    
    public init(transport: any MIDITransport) {
        self.transport = transport
    }
    
    /// 購読を開始
    public func subscribe(
        _ handler: @escaping @Sendable (MIDIReceivedData) async -> Void
    ) -> UUID {
        let id = UUID()
        subscribers[id] = handler
        return id
    }
    
    /// 購読を解除
    public func unsubscribe(_ id: UUID) {
        subscribers.removeValue(forKey: id)
    }
    
    /// ディスパッチを開始
    public func start() {
        guard dispatchTask == nil else { return }
        
        dispatchTask = Task { [weak self] in
            guard let self else { return }
            for await received in transport.received {
                let handlers = await self.subscribers.values
                for handler in handlers {
                    await handler(received)
                }
            }
        }
    }
    
    /// ディスパッチを停止
    public func stop() {
        dispatchTask?.cancel()
        dispatchTask = nil
    }
}
```

**実装案B: MIDI2KitSession（より高レベル）**

```swift
/// CI + PE を統合管理するセッション
public actor MIDI2KitSession {
    public let transport: any MIDITransport
    public let ciManager: CIManager
    public let peManager: PEManager
    
    private let hub: TransportReceiveHub
    private var ciSubscription: UUID?
    private var peSubscription: UUID?
    
    public init(name: String, configuration: CIManagerConfiguration = .default) throws {
        let transport = try CoreMIDITransport(clientName: name)
        self.transport = transport
        self.hub = TransportReceiveHub(transport: transport)
        
        // autoStartDiscovery: false で初期化（ストリーム競合回避）
        var config = configuration
        config.autoStartDiscovery = false
        
        self.ciManager = CIManager(transport: transport, configuration: config)
        self.peManager = PEManager(transport: transport, sourceMUID: ciManager.muid)
        
        // destinationResolverを自動設定
        let resolver = ciManager.makeDestinationResolver()
        Task { await peManager.setDestinationResolver(resolver) }
    }
    
    /// セッションを開始（正しい順序で全て起動）
    public func start() async throws {
        try await transport.connectToAllSources()
        
        // 受信ハブを開始
        await hub.start()
        
        // CI/PEを購読
        ciSubscription = await hub.subscribe { [weak self] received in
            await self?.ciManager.handleReceivedExternal(received)
        }
        peSubscription = await hub.subscribe { [weak self] received in
            await self?.peManager.handleReceivedExternal(received.data)
        }
        
        // Discovery開始
        await ciManager.startDiscovery()
    }
    
    /// セッションを停止
    public func stop() async {
        if let id = ciSubscription {
            await hub.unsubscribe(id)
        }
        if let id = peSubscription {
            await hub.unsubscribe(id)
        }
        await hub.stop()
        await ciManager.stop()
        await peManager.stopReceiving()
    }
    
    /// デバイスイベントストリーム
    public var events: AsyncStream<CIManagerEvent> {
        ciManager.events
    }
    
    /// 検出されたデバイス
    public var devices: [DiscoveredDevice] {
        get async { await ciManager.discoveredDevices }
    }
}
```

**推奨**: 案Bの `MIDI2KitSession` を採用。これにより：
- 「`start()` を呼んではいけない」という罠が消える
- 正しい初期化順序がAPI化される
- 将来の `MIDI2Client` への移行パスになる

---

#### P0-2: DestinationResolver PE向け強化

**目的**: PE専用のdestination解決ロジックを明示的に提供

**実装**:

```swift
extension CIManager {
    /// PE通信用のdestinationを解決
    ///
    /// Discovery用の `destination(for:)` とは異なり、
    /// PE専用のポート選択ルールを適用する。
    ///
    /// 優先順位:
    /// 1. "Module" を含むdestination（KORG等）
    /// 2. Entity-basedマッチング
    /// 3. 名前マッチング
    /// 4. キャッシュされたdestination
    public func destinationForPropertyExchange(_ muid: MUID) async -> MIDIDestinationID? {
        // 既存の resolveDestinationForPE() を公開APIに昇格
        return await resolveDestinationForPE(muid: muid)
    }
}

extension PEManager {
    /// タイムアウト時にフォールバックでリトライ
    public func getWithFallback(
        _ resource: String,
        from muid: MUID,
        timeout: Duration = defaultTimeout
    ) async throws -> PEResponse {
        do {
            return try await get(resource, from: muid, timeout: timeout)
        } catch PEError.timeout {
            // 全destinationsに順次試行（1回だけ）
            logger.notice("Timeout, trying fallback broadcast", category: "PEManager")
            return try await broadcastGet(resource, from: muid, timeout: timeout)
        }
    }
    
    /// 全destinationsに順次試行
    private func broadcastGet(
        _ resource: String,
        from muid: MUID,
        timeout: Duration
    ) async throws -> PEResponse {
        let destinations = await transport.destinations
        
        for dest in destinations {
            do {
                let handle = PEDeviceHandle(muid: muid, destination: dest.destinationID)
                return try await get(resource, from: handle, timeout: timeout)
            } catch {
                continue
            }
        }
        
        throw PEError.timeout(resource: resource)
    }
}
```

---

### Phase 2: P1 - テスト強化

#### P1-1: PE Get Inquiryフォーマットテスト

```swift
final class PEInquiryFormatTests: XCTestCase {
    
    func testPEGetInquiryDoesNotContainChunkFields() {
        let inquiry = CIMessageBuilder.peGetInquiry(
            sourceMUID: MUID(0x12345678),
            destinationMUID: MUID(0x87654321),
            requestID: 1,
            headerData: Data("{\"resource\":\"DeviceInfo\"}".utf8)
        )
        
        // Universal SysEx header (14 bytes) + header
        // numChunks/thisChunk は含まれないこと
        XCTAssertEqual(inquiry.count, 14 + /* headerData length */)
        
        // headerDataの開始位置が正しいこと
        let headerStart = 14
        XCTAssertEqual(inquiry[headerStart], 0x7B) // '{' の ASCII
    }
    
    func testPEGetReplyContainsChunkFields() {
        // Replyにはchunkフィールドが含まれることを確認
        let reply = CIMessageBuilder.peGetReply(
            sourceMUID: MUID(0x12345678),
            destinationMUID: MUID(0x87654321),
            requestID: 1,
            headerData: Data(),
            propertyData: Data(),
            numChunks: 1,
            thisChunk: 1
        )
        
        // numChunks/thisChunk が正しい位置にあること
        XCTAssertEqual(reply[14], 1) // numChunks
        XCTAssertEqual(reply[16], 1) // thisChunk
    }
}
```

---

### Phase 3: P2 - UX改善

#### P2-1: エラーのリトライ可能判定

```swift
extension PEError {
    /// このエラーはリトライで解決する可能性があるか
    public var isRetryable: Bool {
        switch self {
        case .timeout:
            return true
        case .deviceBusy:
            return true
        case .transportError:
            return true
        case .deviceNotFound:
            return false
        case .invalidResponse:
            return false
        case .cancelled:
            return false
        case .requestIDExhausted:
            return true  // 待てば解放される
        case .noDestination:
            return false
        case .validationFailed:
            return false
        case .nak(let details):
            return details.isTransient
        }
    }
    
    /// 推奨リトライ間隔
    public var suggestedRetryDelay: Duration? {
        switch self {
        case .timeout:
            return .seconds(1)
        case .deviceBusy:
            return .seconds(2)
        case .requestIDExhausted:
            return .milliseconds(500)
        default:
            return nil
        }
    }
}
```

---

## 第4部: 実装スケジュール

| Phase | 項目 | 工数 | 担当 | 状態 |
|-------|------|------|------|------|
| P0-1 | TransportReceiveHub / MIDI2KitSession | 2-3日 | - | 📋 計画 |
| P0-2 | destinationForPropertyExchange() | 1日 | - | 📋 計画 |
| P1-1 | PE Inquiryテスト | 0.5日 | - | 📋 計画 |
| P2-1 | isRetryable追加 | 0.5日 | - | 📋 計画 |

---

## 第5部: 検証チェックリスト

### MIDI2Explorer側での確認事項

| チェック項目 | 確認方法 | 状態 |
|-------------|----------|------|
| 受信ディスパッチが1本 | `receiveDispatcherTask` の存在確認 | ✅ 対応済み |
| destination mismatchログ | MUID不一致の警告ログ確認 | ✅ ログ追加済み |
| PE Get Inquiry修正 | MIDI2Kitバージョン確認 | ⚠️ 要確認 |

### 実機テスト項目

| テスト項目 | デバイス | 期待結果 |
|-----------|----------|----------|
| Discovery | KORG Module Pro | デバイス検出成功 |
| PE DeviceInfo取得 | KORG Module Pro | 製品名取得成功 |
| PE ResourceList取得 | KORG Module Pro | リソース一覧取得成功 |
| 再接続後のPE | KORG Module Pro | 再接続後も動作 |

---

## 第6部: 関連ドキュメント

| ドキュメント | 内容 |
|-------------|------|
| [PEIssueHistory.md](./PEIssueHistory.md) | PE問題の調査経緯 |
| [HighLevelAPIProposal.md](./HighLevelAPIProposal.md) | 高レベルAPI提案 |
| [MIDI2ClientGuide.md](./MIDI2ClientGuide.md) | 将来のAPI使用ガイド（提案） |
| [DeviceLogCapture.md](./DeviceLogCapture.md) | デバイスログ取得方法 |

---

## 更新履歴

| 日時 | 内容 |
|------|------|
| 2026-01-26 19:23 | 初版作成 - 問題分析・ロードマップ統合 |
