# MIDI2Kit 高レベルAPI提案

## 概要

本ドキュメントは、MIDI2Kitライブラリに対する高レベルAPI追加の要望をまとめたものである。
現状のAPIでアプリ開発者が直面している課題を解決し、より簡潔で堅牢なMIDI 2.0アプリケーション開発を可能にすることを目的とする。

**作成日**: 2026-01-26  
**ステータス**: 提案（Draft）

---

## 背景：現状の課題

### 課題1: AsyncStream競合問題 🔴 Critical

**現象**: `CIManager.start()` と `PEManager.startReceiving()` が同じ `transport.received` ストリームを消費しようとして競合する。

**影響**: 片方のマネージャーしかデータを受け取れず、Discovery は成功するが PE が動かない（またはその逆）。

**現状の回避策**:
```swift
// アプリ側でディスパッチャーを実装する必要がある
receiveDispatcherTask = Task {
    for await received in transport.received {
        await ciManager.handleReceivedExternal(received)
        await peManager.handleReceivedExternal(received.data)
    }
}
```

### 課題2: Destination解決の複雑さ 🔴 Critical

**現象**: KORGなどのデバイスは複数ポートを持ち、DiscoveryとPEで異なるポートを使用する。

**例: KORGデバイスのポート構造**:
```
Sources: Bluetooth, Session 1
Destinations: Bluetooth, Session 1, Module
```
- Discovery Reply → Bluetooth から受信
- PE Request → Module に送信する必要がある

**現状の回避策**:
```swift
// アプリ側でModule優先ロジックを実装
if let moduleDest = destinations.first(where: { $0.name.lowercased().contains("module") }) {
    return moduleDest.destinationID
}
```

### 課題3: パースエラーの露出 🟡 High

**現象**: 低レベルのパースエラーがそのままアプリに伝播する。

```swift
// 現状のエラーメッセージ
"parseFullPEReply failed for 0x35: len=245, payload[14..]: 7B 22 73..."
"Failed to decode DeviceInfo: keyNotFound(CodingKeys..."
```

### 課題4: 初期化順序の複雑さ 🟡 High

**現象**: 正しい順序で初期化しないと動作しない。

```swift
// 現状（順序を間違えると動かない）
let transport = try CoreMIDITransport(clientName: "MyApp")
let ciManager = CIManager(transport: transport, configuration: config)
let peManager = PEManager(transport: transport, sourceMUID: ciManager.muid)
let resolver = ciManager.makeDestinationResolver()
await peManager.setDestinationResolver(resolver)
try await transport.connectToAllSources()
// ここでディスパッチャーを設定...
await ciManager.startDiscovery()
```

---

## 提案するAPI

### 1. 統合クライアント `MIDI2Client` [P0]

すべての複雑さを隠蔽する単一のエントリーポイント。

```swift
/// MIDI 2.0 統合クライアント
///
/// CIManager、PEManager、Transportを内部で統合し、
/// AsyncStream競合やDestination解決を自動的に処理する。
public actor MIDI2Client {
    
    /// クライアントを初期化
    /// - Parameters:
    ///   - name: CoreMIDIクライアント名
    ///   - preset: 設定プリセット（デフォルト: .balanced）
    public init(name: String, preset: ClientPreset = .balanced) throws
    
    /// 検出されたデバイス一覧
    public var devices: [MIDI2Device] { get }
    
    /// デバイスイベントストリーム
    public var events: AsyncStream<MIDI2Event> { get }
    
    /// クライアントを開始（Discovery自動開始）
    public func start() async throws
    
    /// クライアントを停止
    public func stop() async
    
    // MARK: - PE Convenience API
    
    /// デバイス情報を取得
    public func getDeviceInfo(from muid: MUID) async throws -> PEDeviceInfo
    
    /// リソース一覧を取得
    public func getResourceList(from muid: MUID) async throws -> [PEResourceEntry]
    
    /// 汎用リソース取得
    public func get(_ resource: String, from muid: MUID) async throws -> PEResponse
    
    /// 汎用リソース設定
    public func set(_ resource: String, data: Data, to muid: MUID) async throws -> PEResponse
}

/// 設定プリセット
public enum ClientPreset {
    /// バランス型（デフォルト）
    case balanced
    
    /// Explorer向け（Discovery重視、長いタイムアウト）
    case explorer
    
    /// Controller向け（低レイテンシ重視）
    case controller
    
    /// カスタム設定
    case custom(MIDI2ClientConfiguration)
}
```

**使用例**:
```swift
import MIDI2Kit

// 1行で初期化・開始
let client = try MIDI2Client(name: "MyApp")
try await client.start()

// デバイス検出を監視
for await event in client.events {
    switch event {
    case .deviceDiscovered(let device):
        print("Found: \(device.displayName)")
        
        // PE取得も1行
        let info = try await client.getDeviceInfo(from: device.muid)
        print("Product: \(info.productName ?? "unknown")")
        
    case .deviceLost(let device):
        print("Lost: \(device.displayName)")
        
    case .error(let error):
        print("Error: \(error.localizedDescription)")
    }
}
```

---

### 2. 自動Destination解決 [P0]

ライブラリ内部でデバイス固有のポートマッピングを処理。

```swift
/// Destination解決戦略
public enum DestinationStrategy: Sendable {
    /// 自動（デバイス固有ルールを適用）
    case automatic
    
    /// Module優先（KORG等向け）
    case preferModule
    
    /// 名前マッチング優先
    case preferNameMatch
    
    /// カスタムロジック
    case custom(@Sendable (MUID, [MIDIDestinationInfo]) async -> MIDIDestinationID?)
}

// 内部実装例
internal struct DevicePortMapping {
    /// 既知のデバイス固有ルール
    static let knownMappings: [ManufacturerID: PortMappingRule] = [
        .korg: .preferPortContaining("Module"),
        .roland: .preferPortContaining("MIDI"),
        // ...
    ]
}
```

**アプリ開発者の視点**:
```swift
// 現状（複雑）
let destination = await ciManager.destination(for: device.muid)
guard let dest = destination else { throw ... }
let handle = PEDeviceHandle(muid: device.muid, destination: dest)
let info = try await peManager.getDeviceInfo(from: handle)

// 提案（シンプル）
let info = try await client.getDeviceInfo(from: device.muid)
```

---

### 3. リッチなデバイスオブジェクト `MIDI2Device` [P1]

```swift
/// MIDI 2.0 デバイス
///
/// DiscoveredDeviceを拡張し、PE操作やサブスクリプションを
/// 直接メソッドとして提供する。
public actor MIDI2Device: Identifiable {
    
    // MARK: - Identity
    
    public nonisolated let muid: MUID
    public nonisolated let identity: DeviceIdentity
    public var displayName: String { get }
    
    // MARK: - Capabilities
    
    public var supportsPropertyExchange: Bool { get }
    public var supportsProfileConfiguration: Bool { get }
    
    // MARK: - Property Exchange (Cached)
    
    /// デバイス情報（キャッシュあり）
    public var deviceInfo: PEDeviceInfo? { get async throws }
    
    /// リソース一覧（キャッシュあり）
    public var resourceList: [PEResourceEntry]? { get async throws }
    
    /// キャッシュをクリア
    public func invalidateCache()
    
    // MARK: - Property Exchange (Direct)
    
    /// リソースを取得
    public func get(_ resource: String) async throws -> PEResponse
    
    /// チャンネル指定でリソースを取得
    public func get(_ resource: String, channel: Int) async throws -> PEResponse
    
    /// リソースを設定
    public func set(_ resource: String, data: Data) async throws -> PEResponse
    
    // MARK: - Subscriptions
    
    /// リソースの変更を購読
    public func subscribe(to resource: String) async throws -> AsyncStream<PENotification>
    
    /// 購読を解除
    public func unsubscribe(from resource: String) async throws
}
```

**使用例**:
```swift
let device = client.devices.first!

// キャッシュ付きプロパティアクセス
if let info = try await device.deviceInfo {
    print("Product: \(info.productName ?? "unknown")")
}

// サブスクリプション
let notifications = try await device.subscribe(to: "ProgramInfo")
for await notification in notifications {
    print("Program changed: \(notification.data)")
}
```

---

### 4. エラーの抽象化 [P1]

```swift
/// MIDI 2.0 エラー
public enum MIDI2Error: Error, LocalizedError {
    
    // MARK: - Connection Errors
    
    /// デバイスが応答しない
    case deviceNotResponding(device: MIDI2Device?, timeout: Duration)
    
    /// デバイスが見つからない
    case deviceNotFound(muid: MUID)
    
    /// 接続が切断された
    case connectionLost(device: MIDI2Device?, reason: String?)
    
    // MARK: - Protocol Errors
    
    /// プロパティがサポートされていない
    case propertyNotSupported(resource: String, device: MIDI2Device?)
    
    /// デバイスがビジー
    case deviceBusy(device: MIDI2Device?, retryAfter: Duration?)
    
    /// プロトコルバージョン不一致
    case protocolMismatch(expected: String, actual: String)
    
    // MARK: - Internal Errors
    
    /// 通信エラー（内部詳細を含む）
    case communicationError(underlying: Error, suggestion: String?)
    
    /// パースエラー（内部詳細を含む）
    case parseError(context: String, underlying: Error?)
    
    // MARK: - LocalizedError
    
    public var errorDescription: String? {
        switch self {
        case .deviceNotResponding(let device, let timeout):
            let name = device?.displayName ?? "Device"
            return "\(name) is not responding (timeout: \(timeout.formatted()))."
            
        case .deviceNotFound(let muid):
            return "Device not found: \(muid)"
            
        case .propertyNotSupported(let resource, let device):
            let name = device?.displayName ?? "Device"
            return "\(name) does not support '\(resource)'."
            
        case .deviceBusy(let device, let retryAfter):
            let name = device?.displayName ?? "Device"
            if let retry = retryAfter {
                return "\(name) is busy. Try again in \(retry.formatted())."
            }
            return "\(name) is busy. Please try again later."
            
        case .communicationError(_, let suggestion):
            if let suggestion {
                return "Communication error. \(suggestion)"
            }
            return "Communication error. Check device connection."
            
        default:
            return nil
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .deviceNotResponding:
            return "Try reconnecting the device or restarting the app."
        case .deviceBusy(_, let retryAfter):
            if retryAfter != nil {
                return "The request will be retried automatically."
            }
            return "Wait a moment and try again."
        default:
            return nil
        }
    }
}
```

---

### 5. イベントシステム [P1]

```swift
/// MIDI 2.0 クライアントイベント
public enum MIDI2Event: Sendable {
    
    // MARK: - Device Lifecycle
    
    /// デバイスが検出された
    case deviceDiscovered(MIDI2Device)
    
    /// デバイス情報が更新された
    case deviceUpdated(MIDI2Device)
    
    /// デバイスが切断された
    case deviceLost(MIDI2Device)
    
    // MARK: - Connection
    
    /// Discovery開始
    case discoveryStarted
    
    /// Discovery停止
    case discoveryStopped
    
    // MARK: - Errors
    
    /// エラー発生（回復可能）
    case error(MIDI2Error)
    
    /// 警告（情報提供のみ）
    case warning(String)
}
```

---

### 6. デバッグ支援 [P2]

```swift
extension MIDI2Client {
    
    /// ログレベル
    public var logLevel: LogLevel { get set }
    
    /// 最後の通信トレース
    public var lastCommunicationTrace: String { get }
    
    /// 診断情報
    public var diagnostics: String { get async }
}

public enum LogLevel {
    case none
    case error
    case warning
    case info
    case debug
    case trace
}
```

**診断出力例**:
```
=== MIDI2Client Diagnostics ===
Status: Running
MUID: 0x12345678
Discovery interval: 10.0s
Device timeout: 60.0s

Connected Devices: 1
  - KORG Module Pro (0x87654321)
    PE: ✓  Profile: ✗  Protocol: ✗
    Port mapping: Discovery=Bluetooth, PE=Module
    Last seen: 2.3s ago

Pending Requests: 0
Active Subscriptions: 0
```

---

## 実装優先度

| 優先度 | 項目 | 理由 | 工数見積 |
|--------|------|------|----------|
| 🔴 P0 | AsyncStream競合の内部解決 | 現状アプリが壊れる | 小 |
| 🔴 P0 | 自動Destination解決 | KORGで動かない | 中 |
| 🟡 P1 | 統合クライアント `MIDI2Client` | APIの簡素化 | 大 |
| 🟡 P1 | エラーの抽象化 `MIDI2Error` | デバッグ困難 | 中 |
| 🟡 P1 | イベントシステム `MIDI2Event` | 一貫性のあるAPI | 小 |
| 🟢 P2 | `MIDI2Device` リッチオブジェクト | DX向上 | 中 |
| 🟢 P2 | デバッグ支援内蔵 | トラブルシュート | 小 |

---

## 移行パス

### Phase 1: 内部修正（破壊的変更なし）

1. AsyncStream競合を内部で解決（`handleReceivedExternal`を内部化）
2. Destination解決ロジックを強化（Module優先ルール内蔵）
3. エラーメッセージの改善

### Phase 2: 新API追加（既存API維持）

1. `MIDI2Client` を新規追加
2. `MIDI2Device` を新規追加
3. `MIDI2Error` を新規追加
4. 既存の `CIManager` / `PEManager` は非推奨化せず維持

### Phase 3: ドキュメント・サンプル

1. 新APIのドキュメント作成
2. MIDI2Explorerを新APIで書き直し（サンプル兼用）
3. 移行ガイド作成

---

## 参考：理想的な使用フロー

```swift
import MIDI2Kit

@main
struct MyMIDIApp: App {
    @State private var client: MIDI2Client?
    @State private var devices: [MIDI2Device] = []
    
    var body: some Scene {
        WindowGroup {
            DeviceListView(devices: devices)
                .task {
                    await startMIDI()
                }
        }
    }
    
    func startMIDI() async {
        do {
            // 1行で初期化
            let client = try MIDI2Client(name: "MyMIDIApp")
            self.client = client
            
            // 開始（Discovery自動）
            try await client.start()
            
            // イベント監視
            for await event in client.events {
                switch event {
                case .deviceDiscovered(let device):
                    devices.append(device)
                    
                    // PE情報取得も簡単
                    if let info = try? await device.deviceInfo {
                        print("Found: \(info.productName ?? device.displayName)")
                    }
                    
                case .deviceLost(let device):
                    devices.removeAll { $0.muid == device.muid }
                    
                case .error(let error):
                    // ユーザーフレンドリーなエラー
                    print(error.localizedDescription)
                    
                default:
                    break
                }
            }
        } catch {
            print("Failed to start MIDI: \(error)")
        }
    }
}
```

---

## 更新履歴

| 日時 | 内容 |
|------|------|
| 2026-01-26 | 初版作成 |
