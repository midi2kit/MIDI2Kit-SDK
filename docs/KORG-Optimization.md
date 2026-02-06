# KORG最適化ガイド (v1.0.8+)

MIDI2Kit v1.0.8では、KORG Module ProなどのKORGデバイス向けに大幅なパフォーマンス改善を実現する最適化機能が追加されました。この最適化により、Property Exchangeのリソース取得時間を**99%以上削減**（16.4秒 → 144ms）できます。

## 主な新機能

### 1. 最適化されたリソース取得API

従来の`getResourceList()`を使用したワークフローを大幅に高速化する新しいAPIです。

#### `getOptimizedResources(from:preferVendorResources:)`

デバイスのベンダーを自動検出し、可能な場合は最適化されたパスを使用してリソース情報を取得します。

```swift
import MIDI2Kit

let client = try MIDI2Client(name: "MyApp")
try await client.start()

// デバイス検出後
let result = try await client.getOptimizedResources(from: device.muid)

if result.usedOptimizedPath {
    // KORG最適化パスが使用された（99%高速化）
    if let params = result.xParameterList {
        print("取得したパラメータ数: \(params.count)")
        for param in params {
            print("CC\(param.controlCC): \(param.displayName)")
        }
    }
} else {
    // 標準パスが使用された
    if let resources = result.standardResourceList {
        print("利用可能なリソース: \(resources.map { $0.resource })")
    }
}
```

**パフォーマンス比較:**

| アプローチ | 所要時間 | 説明 |
|----------|---------|------|
| 従来の方法（ResourceList経由） | 16.4秒 | DeviceInfo warmup + ResourceList取得 |
| **最適化パス（v1.0.8）** | **144ms** | **X-ParameterList直接取得（99.1%改善）** |

### 2. KORG専用型定義

KORGデバイスが提供する独自のProperty Exchangeリソースを扱うための型定義が追加されました。

#### PEXParameter - X-ParameterList エントリ

KORG Module Proなどのデバイスでは、`X-ParameterList`リソースでCC番号とパラメータ名のマッピングを提供します。

```swift
let params = try await client.getXParameterList(from: device.muid)

for param in params {
    print("\(param.displayName) (CC\(param.controlCC))")
    print("  範囲: \(param.effectiveMinValue) - \(param.effectiveMaxValue)")
    if let defaultValue = param.defaultValue {
        print("  デフォルト: \(defaultValue)")
    }
}
```

**便利な拡張メソッド:**

```swift
// CC番号からパラメータを検索
if let level = params.parameter(for: 11) {
    print("CC11 は \(level.displayName)")
}

// CC番号から表示名を取得
let name = params.displayName(for: 11) // "Inst Level" or "CC11"

// CC -> パラメータの辞書を作成
let dict = params.byControlCC
if let param = dict[11] {
    print(param.displayName)
}
```

#### PEXProgramEdit - X-ProgramEdit データ

現在のプログラム情報と全パラメータの現在値を取得します。

```swift
let program = try await client.getXProgramEdit(from: device.muid)

print("プログラム名: \(program.displayName)")
if let category = program.category {
    print("カテゴリ: \(category)")
}

// 全パラメータ値を取得
for (cc, value) in program.parameterValues {
    print("CC\(cc) = \(value)")
}

// 特定のCCの値を取得
if let level = program.value(for: 11) {
    print("Inst Level: \(level)")
}
```

**チャンネル指定での取得:**

```swift
// MIDI チャンネル 0 (Ch.1) のプログラムを取得
let ch1Program = try await client.getXProgramEdit(channel: 0, from: device.muid)
```

#### PEXParameterValue - パラメータ値

`PEXProgramEdit`内で使用される個々のパラメータ値を表します。

```swift
public struct PEXParameterValue: Sendable, Codable {
    public let controlCC: Int  // CC番号
    public let value: Int      // 現在値 (0-127)
}
```

### 3. Adaptive Warm-Up戦略

デバイスとの接続状態に応じて、自動的にwarm-upの必要性を判断する戦略が追加されました。

#### WarmUpStrategy

BLE MIDI接続では、最初のリクエストが不安定になることがあります。warm-up戦略により、必要な場合のみwarm-upを実行して信頼性とパフォーマンスを両立します。

```swift
var config = MIDI2ClientConfiguration()

// Adaptive戦略（推奨・デフォルト）
config.warmUpStrategy = .adaptive

let client = try MIDI2Client(name: "MyApp", configuration: config)
```

**利用可能な戦略:**

| 戦略 | 動作 | 用途 |
|-----|------|-----|
| `.always` | 常にwarm-upを実行 | 最も信頼性が高いが遅い。接続問題が既知のデバイス向け |
| `.never` | warm-upを実行しない | 最速だが失敗する可能性。warm-up不要と判明しているデバイス向け |
| **`.adaptive`** | **初回は試行、失敗を記憶** | **（推奨）初回は高速、必要なデバイスのみ自動学習** |
| `.vendorBased` | ベンダー固有の最適化を使用 | KORG向けにX-ParameterListをwarmupとして使用 |

#### Adaptiveの仕組み

```
1回目のリクエスト
  → warm-upなしで試行
  → 成功 → 次回もwarm-upなし（高速）
  → 失敗 → warm-upありで再試行 → 次回からはwarm-upあり（信頼性）
```

デバイスごとに成功/失敗パターンを記憶するため、アプリケーション実行中は最適な動作を維持します。

#### キャッシュ診断

```swift
let cache = await client.warmUpCache
let diag = await cache.diagnostics

print(diag.description)
// 出力例: "WarmUpCache: 2 need warm-up, 3 don't, 5 total"
```

### 4. ベンダー別最適化設定

デバイスのベンダーごとに異なる最適化を有効化できます。

#### VendorOptimization

```swift
var config = MIDI2ClientConfiguration()

// デフォルト（KORG最適化が有効）
config.vendorOptimizations = .default

// 全ての最適化を無効化
config.vendorOptimizations = .none

// カスタム最適化
config.vendorOptimizations.enable(.skipResourceListWhenPossible, for: .korg)
config.vendorOptimizations.enable(.useXParameterListAsWarmup, for: .korg)

let client = try MIDI2Client(name: "MyApp", configuration: config)
```

**KORGで有効な最適化:**

| 最適化 | 効果 | パフォーマンス影響 |
|-------|------|-----------------|
| `.skipResourceListWhenPossible` | ResourceListを飛ばしてX-ParameterListを直接取得 | **99%高速化** |
| `.useXParameterListAsWarmup` | X-ParameterListをwarm-upとして使用 | BLE接続の安定性向上 |
| `.preferVendorResources` | 標準リソースよりベンダー固有リソースを優先 | より詳細な情報を取得 |
| `.extendedMultiChunkTimeout` | マルチチャンクレスポンスのタイムアウトを延長 | BLE環境でのタイムアウト防止 |

#### MIDIVendor列挙型

サポートされているベンダー:

```swift
public enum MIDIVendor: String {
    case korg = "KORG"
    case roland = "Roland"
    case yamaha = "Yamaha"
    case native_instruments = "Native Instruments"
    case arturia = "Arturia"
    case novation = "Novation"
    case akai = "Akai"
    case unknown = "Unknown"
}
```

ベンダーは`DeviceInfo`のmanufacturerNameから自動検出されます。

## 実用例

### 例1: KORG Module Proのパラメータ一覧を高速取得

```swift
import MIDI2Kit

let client = try MIDI2Client(name: "MIDIController")
try await client.start()

// デバイス検出を待機
for await event in await client.makeEventStream() {
    guard case .deviceDiscovered(let device) = event else { continue }
    guard device.supportsPropertyExchange else { continue }

    // KORG最適化パスで取得（144ms）
    let result = try await client.getOptimizedResources(from: device.muid)

    if let params = result.xParameterList {
        print("✅ KORG最適化: \(params.count)個のパラメータを取得")

        // CC別にグループ化して表示
        for param in params.sorted(by: { $0.controlCC < $1.controlCC }) {
            print("  CC\(String(format: "%3d", param.controlCC)): \(param.displayName)")
            if let category = param.category {
                print("         カテゴリ: \(category)")
            }
        }
    }

    break
}

await client.stop()
```

### 例2: 現在のプログラムとパラメータ値を取得

```swift
// プログラム情報を取得
let program = try await client.getXProgramEdit(from: device.muid)

print("📋 現在のプログラム: \(program.displayName)")

// パラメータ定義を取得
let params = try await client.getXParameterList(from: device.muid)

// 現在値と定義を組み合わせて表示
for param in params {
    if let currentValue = program.value(for: param.controlCC) {
        let percentage = Double(currentValue - param.effectiveMinValue) /
                        Double(param.effectiveMaxValue - param.effectiveMinValue) * 100

        print("\(param.displayName):")
        print("  現在値: \(currentValue)")
        print("  範囲: \(param.effectiveMinValue)-\(param.effectiveMaxValue)")
        print("  割合: \(String(format: "%.1f", percentage))%")
    }
}
```

### 例3: Adaptive戦略でリソースリスト取得を最適化

```swift
var config = MIDI2ClientConfiguration()
config.warmUpStrategy = .adaptive  // デフォルト

let client = try MIDI2Client(name: "MyApp", configuration: config)
try await client.start()

// 初回: warm-upなしで試行（高速）
// 成功した場合、次回もwarm-upなし
do {
    let resources = try await client.getResourceList(from: device.muid)
    print("✅ リソースリスト取得成功（warm-upなし）")
} catch {
    // 失敗した場合、自動的にwarm-upありで再試行され、次回から記憶される
    print("⚠️ 初回失敗、warm-upありで再試行中...")
}

// 2回目以降: キャッシュされた戦略を使用（自動最適化）
let resources = try await client.getResourceList(from: device.muid)
```

### 例4: ベンダー固有warm-up戦略を使用

```swift
var config = MIDI2ClientConfiguration()
config.warmUpStrategy = .vendorBased
config.vendorOptimizations = .default  // KORG最適化を有効化

let client = try MIDI2Client(name: "MyApp", configuration: config)
try await client.start()

// KORGデバイスの場合、X-ParameterListがwarmupとして使用される
// 他のベンダーの場合、.adaptiveと同じ動作
let resources = try await client.getResourceList(from: device.muid)
```

## パフォーマンス比較

実際のKORG Module Pro (BLE MIDI) での測定結果:

| 操作 | v1.0.7以前 | v1.0.8最適化パス | 改善率 |
|-----|-----------|----------------|-------|
| リソース情報取得 | 16,400ms | 144ms | **99.1%** |
| X-ParameterList取得 | 16,400ms（ResourceList経由） | 144ms（直接） | **99.1%** |
| DeviceInfo取得（warm-up） | 100-300ms | 100-300ms | 変化なし |

**最適化の仕組み:**

```
【v1.0.7以前】
1. DeviceInfo取得（warm-up） - 200ms
2. ResourceList取得 - 16,200ms (マルチチャンク、BLEで不安定)
3. 必要なリソースを検索
合計: 16,400ms

【v1.0.8最適化】
1. X-ParameterList直接取得 - 144ms (ResourceListをスキップ)
合計: 144ms

高速化率: (16,400 - 144) / 16,400 = 99.1%
```

## 設定ガイド

### KORG Module Pro向け推奨設定

```swift
var config = MIDI2ClientConfiguration()

// Adaptive warm-up（自動学習）
config.warmUpStrategy = .adaptive

// KORG最適化を有効化
config.vendorOptimizations = .default

// BLE環境向けタイムアウト延長
config.peTimeout = .seconds(5)
config.multiChunkTimeoutMultiplier = 1.5

// リトライ設定
config.maxRetries = 2
config.retryDelay = .milliseconds(100)

let client = try MIDI2Client(name: "MyApp", configuration: config)
```

### 標準MIDI 2.0デバイス向け推奨設定

```swift
// デフォルト設定で十分
let config = MIDI2ClientConfiguration()
// または
let client = try MIDI2Client(name: "MyApp", preset: .standard)
```

### デバッグ・開発向け設定

```swift
var config = MIDI2ClientConfiguration(preset: .explorer)

// ロギングを有効化
MIDI2Logger.isEnabled = true
MIDI2Logger.isVerbose = true

let client = try MIDI2Client(name: "MyApp", configuration: config)
try await client.start()

// 診断情報を確認
let diag = await client.diagnostics
print(diag)
```

## トラブルシューティング

### 最適化パスが使用されない

**症状:** `result.usedOptimizedPath`が`false`になる

**原因:**
- デバイスがKORGとして認識されていない
- ベンダー最適化が無効化されている
- X-ParameterListリソースが利用できない

**解決方法:**

```swift
// 1. ベンダー検出を確認
let info = try await client.getDeviceInfo(from: device.muid)
let vendor = MIDIVendor.detect(from: info.manufacturerName)
print("検出されたベンダー: \(vendor)")

// 2. 最適化設定を確認
let config = await client.configuration
print("vendorOptimizations: \(config.vendorOptimizations)")

// 3. ログを確認
MIDI2Logger.isVerbose = true
let result = try await client.getOptimizedResources(from: device.muid)
```

### Adaptive戦略が学習しない

**症状:** 毎回warm-upが実行される、または実行されない

**原因:**
- キャッシュがクリアされた
- デバイスキーの生成に失敗している

**解決方法:**

```swift
// キャッシュの状態を確認
let cache = await client.warmUpCache
let diag = await cache.diagnostics
print(diag)

// 特定デバイスのキャッシュをクリア
if let info = try await client.getDeviceInfo(from: device.muid) {
    let key = WarmUpCache.deviceKey(
        manufacturer: info.manufacturerName,
        model: info.modelName
    )
    await cache.clear(for: key)
}
```

### X-ParameterListのデコードエラー

**症状:** `MIDI2Error.invalidResponse`でX-ParameterListのデコードに失敗

**原因:**
- デバイスが非標準のJSON形式を返している
- controlccフィールドが欠落している

**解決方法:**

```swift
// 生データを確認
let response = try await client.get("X-ParameterList", from: device.muid)
print("Status: \(response.statusCode)")
print("Body: \(response.bodyString ?? "(empty)")")

// RobustJSONDecoderの診断情報を確認
if let diag = await client.peManager.lastDecodingDiagnostics {
    print("Raw: \(diag.rawData)")
    print("Error: \(diag.parseError ?? "(none)")")
}
```

## 後方互換性

v1.0.8では以下の後方互換性が維持されています:

### 非推奨API

```swift
// 非推奨（v1.0.8+）
config.warmUpBeforeResourceList = true

// 推奨
config.warmUpStrategy = .always
```

`warmUpBeforeResourceList`プロパティは引き続き使用できますが、内部的には`warmUpStrategy`にマッピングされます。

### 既存コードへの影響

v1.0.8の新機能はオプトイン方式のため、既存のコードは変更なしで動作します:

- デフォルトで`.adaptive`戦略が有効（warm-up動作は自動最適化）
- デフォルトでKORG最適化が有効（`getOptimizedResources()`を使用しない限り影響なし）
- 既存の`getResourceList()`は引き続き動作（warm-up戦略のみ影響）

## まとめ

MIDI2Kit v1.0.8では、以下の新機能によりKORGデバイスとのやり取りが大幅に高速化されました:

✅ **99%高速化** - `getOptimizedResources()`で16.4秒→144ms
✅ **KORG専用型** - `PEXParameter`, `PEXProgramEdit`でタイプセーフなAPI
✅ **Adaptive戦略** - デバイスごとに自動学習して最適化
✅ **ベンダー最適化** - KORGに特化した最適化をデフォルトで有効化

既存のアプリケーションも、設定変更なしでadaptive戦略の恩恵を受けられます。さらにパフォーマンスを追求する場合は、`getOptimizedResources()`の使用を検討してください。

## 関連ドキュメント

- [README.md](../README.md) - MIDI2Kitの基本的な使い方
- [CHANGELOG.md](../CHANGELOG.md) - v1.0.8の詳細な変更履歴
- [KORG-Module-Pro-Limitations.md](./KORG-Module-Pro-Limitations.md) - KORGデバイスの既知の制限
- [MigrationGuide.md](./MigrationGuide.md) - 低レベルAPIからの移行ガイド
