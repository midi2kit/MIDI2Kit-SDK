# MIDI2Client 使用ガイド (High-Level API)

## 1. 概要

`MIDI2Client` は、MIDI2Kit の統合エントリポイントです。内部で `CIManager` と `PEManager` を自動管理し、**AsyncStream の競合** や **複雑なポート解決（KORG等）** をライブラリ側で完全に隠蔽（吸収）します。

### 要件

| 項目 | 要件 |
|------|------|
| **MIDI2Kit** | v0.1.0-alpha (High-Level API 対応版) |
| **OS** | iOS 17.0+ / macOS 14.0+ |
| **言語** | Swift 5.9+ (Concurrency 必須) |

---

## 2. ライフサイクル管理

`MIDI2Client` は **Actor** であり、アプリのライフサイクルに合わせて初期化と停止を管理します。

### 完全な管理クラスの例

```swift
@MainActor
class MIDIDeviceManager: ObservableObject {
    @Published var devices: [MIDI2Device] = []
    private var monitoringTask: Task<Void, Never>?
    private let client: MIDI2Client

    init() throws {
        // 1. クライアントの初期化（アプリ名を指定）
        self.client = try MIDI2Client(
            name: "MyMIDIApp",
            discoveryInterval: 10.0, // オプション: 探索間隔
            deviceTimeout: 60.0      // オプション: 応答タイムアウト
        )
    }

    func start() async throws {
        // 2. 通信開始（Discovery放送と受信待機を開始）
        try await client.start()

        monitoringTask?.cancel()
        monitoringTask = Task {
            for await event in client.events {
                guard !Task.isCancelled else { break }
                
                switch event {
                case .deviceDiscovered(let device):
                    devices.append(device)
                case .deviceLost(let device):
                    devices.removeAll { $0.muid == device.muid }
                case .error(let error):
                    print("MIDI Error: \(error)")
                }
            }
        }
    }

    func stop() async {
        monitoringTask?.cancel()
        monitoringTask = nil
        // 3. 明示的な停止（リソース解放）
        await client.stop()
    }
}
```

> **Note**: `MIDI2Client` は `deinit` 時にもクリーンアップを試みますが、リソースの確実な解放のために**明示的な `stop()` の呼び出しを推奨**します。

---

## 3. Property Exchange (PE) の操作

`MIDI2Device` オブジェクトを通じて、型安全なリクエストとリアルタイムな値の監視が可能です。

### プロパティの取得（型安全 API）

```swift
struct PatchList: Decodable {
    let patches: [String]
}

do {
    // ジェネリック版 getProperty (推奨)
    let list = try await device.getProperty("PatchList", as: PatchList.self)
    
    // 定義済みプロパティ
    let info = try await device.deviceInfo
    print("Found: \(info.productName ?? "Unknown")")
    
} catch MIDI2Error.deviceNotResponding(let device, let timeout) {
    print("\(device.displayName) が応答しません（\(timeout)秒待機）")
} catch {
    print("Error: \(error)")
}
```

### リアルタイム監視 (SwiftUI 向け)

`observe` メソッドを使用すると、デバイス側での変更を `AsyncStream` で受け取れます。

```swift
struct DeviceVolumeView: View {
    let device: MIDI2Device
    @State private var currentVolume: Int = 0

    var body: some View {
        Text("Volume: \(currentVolume)")
            .task {
                // デバイス側の変更を購読し、UIを自動更新
                for await volume in device.observe("Volume", as: Int.self) {
                    self.currentVolume = volume
                }
            }
    }
}
```

---

## 4. エラーハンドリングと対処法

| エラー型 / 原因 | 内容 | 対処法 |
|----------------|------|--------|
| `.deviceNotResponding` | デバイスが PE に応答しない | 再接続、または Module ポートの物理接続を確認 |
| `.propertyNotSupported` | リソースが存在しない | `device.resourceList` でサポート状況を確認 |
| `.invalidResponse` | JSON パースに失敗した | ライブラリが自動修正を試みますが、解決しない場合はログを確認 |

---

## 5. デバッグと診断

```swift
// 詳細な診断情報の出力
print(await client.diagnostics)

// 最後のMIDI通信（Hex）のトレース
if let trace = client.lastCommunicationTrace {
    print("Last Trace: \(trace.hexString)")
}
```

### 診断出力例

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

## 6. 既知の制限事項

| 項目 | 制限 |
|------|------|
| **同時接続数** | 推奨最大 8 デバイス |
| **PE タイムアウト** | デフォルト 5 秒（`defaultTimeout` で変更可能） |
| **KORG 固有の挙動** | 「Module」ポートへの自動ルーティングは KORG デバイスで検証済み |
| **Bluetooth MIDI** | OS 側の接続安定性に依存 |

---

## 7. サンプルプロジェクト

完全な実装例については、GitHub リポジトリ内のサンプルを参照してください：

- **[MIDI2Explorer](https://github.com/midi2kit/MIDI2Explorer)** - 実際の KORG/Roland デバイスとの接続デモ

---

## 更新履歴

| 日時 | 内容 |
|------|------|
| 2026-01-26 | 初版作成 |
