# KORG Compatibility Layer - Implementation Status

KORG製デバイス（特にKORG Module Pro）で発生する特有の問題を吸収するための互換性レイヤーの実装状況です。

## 概要

KORGデバイスはMIDI-CI/PE仕様に準拠しつつも、いくつかの非標準的な動作を示します。これらの問題をライブラリ側で透過的に吸収し、アプリ開発者がシンプルなAPIを使用できるようにすることが目標です。

## 4つの主要アプローチ

### 1. DestinationStrategy（ポート解決自動化）✅ 実装済み

**問題**: KORGデバイスでは「Discovery ReplyはBluetoothソースから返るが、PE通信はModuleポートで行う必要がある」というDestination mismatch問題が発生。

**実装状況**:
| 機能 | 状態 | ファイル |
|------|------|----------|
| preferModule戦略 | ✅ | `DestinationStrategy.swift` |
| automatic戦略 | ✅ | `DestinationResolver.swift` |
| フォールバック・リトライ | ✅ | `DestinationResolver.getNextCandidate()` |
| ポートキャッシュ | ✅ | `DestinationResolver.cache` |

**使用例**:
```swift
// 自動的にModuleポートを優先
let client = try MIDI2Client(name: "MyApp", preset: .korg)

// または明示的に設定
let config = MIDI2ClientConfiguration(
    destinationStrategy: .preferModule
)
```

### 2. Inflight Limiting（流量制御）✅ 実装済み

**問題**: 短時間に大量のPEリクエストを送信するとチャンク欠落が発生。

**実装状況**:
| 機能 | 状態 | ファイル |
|------|------|----------|
| maxInflightPerDevice | ✅ | `PETransactionManager.swift` |
| 待機キュー | ✅ | `DeviceInflightState.waiters` |
| FIFO順序保証 | ✅ | `waitForDeviceSlot()` |

**設定**:
```swift
let config = MIDI2ClientConfiguration(
    maxInflightPerDevice: 2  // デフォルト値
)
```

### 3. JSONプリプロセッサ（非標準JSON対応）✅ 実装済み

**問題**: 組み込みデバイスから返されるJSONに末尾カンマ等の非標準記述が含まれることがある。

**実装状況**:
| 機能 | 状態 | ファイル |
|------|------|----------|
| 末尾カンマ除去 | ✅ | `RobustJSONDecoder.swift` |
| シングルクォート変換 | ✅ | `RobustJSONDecoder.swift` |
| コメント除去 | ✅ | `RobustJSONDecoder.swift` |
| 制御文字エスケープ | ✅ | `RobustJSONDecoder.swift` |
| 生データ保持 | ✅ | `PEDecodingDiagnostics.swift` |
| 16進ダンプ出力 | ✅ | `Data.hexDump` extensions |

**使用例**:
```swift
// 自動的にRobustJSONDecoderを使用
let deviceInfo = try response.decodeBody(PEDeviceInfo.self)

// 診断付き
let result = response.decodeBodyWithDiagnostics(PEDeviceInfo.self)
```

### 4. Diagnostics（診断情報）✅ 実装済み

**問題**: ハードウェア依存の問題はブラックボックス化しやすい。

**実装状況**:
| 機能 | 状態 | ファイル |
|------|------|----------|
| DestinationDiagnostics | ✅ | `DestinationStrategy.swift` |
| PEDecodingDiagnostics | ✅ | `PEDecodingDiagnostics.swift` |
| PETransactionManager.diagnostics | ✅ | `PETransactionManager.swift` |
| MIDI2Client.diagnostics | ✅ | `MIDI2Client.swift` |

**使用例**:
```swift
// 宛先解決の診断
if let diag = await client.lastDestinationDiagnostics {
    print(diag)
    // DestinationDiagnostics for <MUID>:
    //   Candidates: ["Bluetooth", "Module", "Session 1"]
    //   Tried: [<destID1>]
    //   Resolved: <destID2> ✓
}

// 全体診断
print(await client.diagnostics)
```

## 高レベルAPI

これらの互換性機能は `MIDI2Client` を通じて自動的に適用されます：

```swift
// シンプルな使用例 - 内部でKORG互換性処理が自動適用
let client = try MIDI2Client(name: "MyApp")
try await client.start()

for await event in await client.makeEventStream() {
    switch event {
    case .deviceDiscovered(let device):
        // DestinationStrategyが自動的にModuleポートを解決
        let info = try await client.getDeviceInfo(from: device.muid)
        print("Product: \(info.productName ?? "Unknown")")
    default:
        break
    }
}
```

## ファイル構成

```
Sources/
├── MIDI2Core/
│   └── JSON/
│       ├── RobustJSONDecoder.swift      # 非標準JSON対応
│       └── PEDecodingDiagnostics.swift  # パース診断情報
├── MIDI2PE/
│   ├── PETransactionManager.swift       # 流量制御
│   └── PEManager+RobustDecoding.swift   # RobustJSON統合
└── MIDI2Kit/
    └── HighLevelAPI/
        ├── DestinationStrategy.swift    # ポート解決戦略
        ├── DestinationResolver.swift    # 解決実装
        ├── ReceiveHub.swift             # イベント配信
        └── MIDI2Client.swift            # 統合API
```

## 今後の課題

1. **実機テスト**: KORG Module Pro以外のKORGデバイスでの検証
2. **他ベンダー対応**: Roland、Yamaha等での動作確認
3. **パフォーマンス計測**: 流量制御のチューニング
4. **エラーリカバリ**: タイムアウト時の自動リトライ戦略の改善

## 参考資料

- [KORG PE Communication Debug Report](./KORG-PE-Communication-Debug-Report.md)
- [RobustJSONDecoder Documentation](./RobustJSONDecoder.md)
- MIDI-CI Specification v1.2
