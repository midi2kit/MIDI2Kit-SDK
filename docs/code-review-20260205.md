# コードレビューレポート

## 概要
- **レビュー対象**: SimpleMidiController MIDI2Kit移行
- **レビュー日**: 2026-02-05
- **対象ファイル**: 9ファイル (計約3,500行)

## サマリー
- 🔴 **Critical**: 0件
- 🟡 **Warning**: 3件
- 🔵 **Suggestion**: 5件
- 💡 **Nitpick**: 4件

**総合評価**: ⭐⭐⭐⭐ 4.0/5.0

MIDI2Kitへの移行は概ね良好に実装されています。MIDI2KitServiceの抽象化レイヤーにより既存Viewとの互換性を保ちながら、新しいライブラリへの移行を実現しています。ただし、いくつかのアーキテクチャ上の問題とエラーハンドリングの改善余地があります。

---

## 🟡 Warning レベルの問題

### 🟡 W-001: MIDI2KitService.swift - エラーハンドリングの欠如

**問題**
`fetchPEData`, `fetchXProgramEdit`, `fetchProgramList` などのメソッドで、全てのエラーを無視しています。

**現在のコード** (Lines 372-389)
```swift
do {
    let response = try await pe.get("DeviceInfo", from: handle, timeout: .seconds(5))
    if let json = try? JSONSerialization.jsonObject(with: response.decodedBody) as? [String: Any] {
        device.deviceInfo = json
    }
} catch {
    // Ignore errors
}
```

**提案**
エラーをログに記録し、再試行やフォールバック戦略を検討すべきです。

```swift
do {
    let response = try await pe.get("DeviceInfo", from: handle, timeout: .seconds(5))
    if let json = try? JSONSerialization.jsonObject(with: response.decodedBody) as? [String: Any] {
        device.deviceInfo = json
    }
} catch {
    MIDILogger.pe("Failed to fetch DeviceInfo for MUID \(muid.value): \(error)")
    // Consider retry strategy for transient errors
}
```

**理由**
エラーを無視すると、デバッグが困難になり、ユーザーが問題を認識できません。少なくともログに記録すべきです。

---

### 🟡 W-002: MIDI2KitService.swift - Singletonパターンの制約

**問題**
`MIDI2KitService.shared` singletonパターンはテストとモックが困難です。

**現在のコード** (Lines 70-71)
```swift
static let shared = MIDI2KitService()
private init() {}
```

**提案**
Dependency Injectionパターンを検討してください。

```swift
@Observable
@MainActor
final class MIDI2KitService {
    // For production
    static let shared = MIDI2KitService()

    // Allow custom initialization for testing
    init(transport: CoreMIDITransport? = nil,
         ciManager: CIManager? = nil,
         peManager: PEManager? = nil) {
        self.transport = transport
        self.ciManager = ciManager
        self.peManager = peManager
    }

    // ...
}
```

**理由**
テスタビリティの向上と、将来的な複数インスタンスのサポート（例: 複数MIDI設定）が可能になります。

---

### 🟡 W-003: MIDI2KitService.swift - Actor隔離の不整合

**問題**
`MIDI2KitService`は`@MainActor`ですが、内部で`CoreMIDITransport`、`CIManager`、`PEManager`（いずれもactor）を直接保持しています。これらのactorメソッドを呼び出す際、明示的な`await`が必要ですが、MainActorからの呼び出しでパフォーマンス問題が発生する可能性があります。

**現在のコード** (Lines 95-99)
```swift
@MainActor
final class MIDI2KitService {
    private var transport: CoreMIDITransport?
    private var ciManager: CIManager?
    private var peManager: PEManager?
```

**提案**
バックグラウンドタスクでactor呼び出しを行い、結果のみMainActorで処理してください。

```swift
private func fetchPEData(for device: inout MIDI2KitDevice, muid: MIDI2Core.MUID) async {
    guard let pe = peManager, let dest = device.destination else { return }

    let handle = PEDeviceHandle(muid: muid, destination: dest)

    // Fetch on background
    let deviceInfo = await Task.detached {
        do {
            let response = try await pe.get("DeviceInfo", from: handle, timeout: .seconds(5))
            return try? JSONSerialization.jsonObject(with: response.decodedBody) as? [String: Any]
        } catch {
            return nil
        }
    }.value

    // Update on MainActor
    device.deviceInfo = deviceInfo
}
```

**理由**
MainActorからのactor呼び出しは同期的に見えますが、実際は非同期でメインスレッドをブロックする可能性があります。

---

## 🔵 Suggestion レベルの提案

### 🔵 S-001: MIDI2KitService.swift - JSONDecoder使用の推奨

**問題**
`JSONSerialization`を直接使用していますが、Swift標準の`JSONDecoder`を使用する方が型安全です。

**現在のコード** (Lines 373-376)
```swift
let response = try await pe.get("DeviceInfo", from: handle, timeout: .seconds(5))
if let json = try? JSONSerialization.jsonObject(with: response.decodedBody) as? [String: Any] {
    device.deviceInfo = json
}
```

**提案**
```swift
struct DeviceInfoResponse: Codable {
    let manufacturer: String?
    let model: String?
    let family: String?
    let version: String?
    let serialNumber: String?
}

let response = try await pe.get("DeviceInfo", from: handle, timeout: .seconds(5))
if let info = try? JSONDecoder().decode(DeviceInfoResponse.self, from: response.decodedBody) {
    device.deviceInfo = ["model": info.model, "family": info.family, ...]
}
```

**理由**
型安全性が向上し、コンパイル時にエラーを検出できます。

---

### 🔵 S-002: MainPageView.swift - 2秒のハードコーディングされた遅延

**問題**
デバイス発見後、2秒の固定遅延でPE名を適用しています。

**現在のコード** (Lines 217-226)
```swift
.onChange(of: midi2KitService.discoveredDevices.count) { _, _ in
    Task {
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        await MainActor.run {
            if usePENames {
                applyPENames()
            }
        }
    }
}
```

**提案**
デバイスのPEデータ取得完了を監視する仕組みを追加してください。

```swift
// MIDI2KitService.swift
@Published var devicesWithPEData: Set<UInt32> = []

// MainPageView.swift
.onChange(of: midi2KitService.devicesWithPEData) { _, _ in
    if usePENames {
        applyPENames()
    }
}
```

**理由**
固定遅延は不確実で、デバイスによって適切な待機時間が異なります。

---

### 🔵 S-003: SlidersPageView.swift - displayName関数の重複

**問題**
`displayName(for index: Int)`が単に`getControllerName`を呼び出すだけの薄いラッパーです。

**現在のコード** (Lines 102-106)
```swift
func displayName(for index: Int) -> String {
    let cc = ccNumbers[index]
    return midi2KitService.getControllerName(for: cc)
}
```

**提案**
直接呼び出すか、より意味のあるロジックを追加してください。

```swift
// Option 1: Direct call
CCSliderView(
    ...
    ccName: midi2KitService.getControllerName(for: ccNumbers[index]),
    ...
)

// Option 2: Add fallback logic
func displayName(for index: Int) -> String {
    let cc = ccNumbers[index]
    let peName = midi2KitService.getControllerName(for: cc)
    return peName != "CC\(cc)" ? peName : ccNames[index]
}
```

**理由**
不要な関数は複雑性を増やします。

---

### 🔵 S-004: ProgramChangePageView.swift - hasProgramList の計算頻度

**問題**
`hasProgramList`プロパティがbody内で毎回計算されます。

**現在のコード** (Lines 114-117)
```swift
private var hasProgramList: Bool {
    guard let device = midi2KitService.discoveredDevices.first else { return false }
    return midi2KitService.deviceSupportsResource("ProgramList", device: device.muid)
}
```

**提案**
`@State`で キャッシュしてください。

```swift
@State private var hasProgramList: Bool = false

var body: some View {
    // ...
}
.onAppear {
    updateProgramListAvailability()
}
.onChange(of: midi2KitService.discoveredDevices) { _, _ in
    updateProgramListAvailability()
}

private func updateProgramListAvailability() {
    guard let device = midi2KitService.discoveredDevices.first else {
        hasProgramList = false
        return
    }
    hasProgramList = midi2KitService.deviceSupportsResource("ProgramList", device: device.muid)
}
```

**理由**
パフォーマンスの最適化と、不要な再計算の削減。

---

### 🔵 S-005: ProgramBrowserView.swift - リフレッシュ後の2秒遅延

**問題**
`refreshProgramList`で固定2秒遅延があります。

**現在のコード** (Lines 336-341)
```swift
Task {
    try? await Task.sleep(nanoseconds: 2_000_000_000)
    await MainActor.run {
        isLoading = false
    }
}
```

**提案**
実際のPE取得完了を監視してください。

```swift
private func refreshProgramList() {
    isLoading = true
    Task {
        await midi2KitService.requestProgramListForAllDevices(channel: midiChannel)
        await MainActor.run {
            isLoading = false
        }
    }
}

// MIDI2KitService.swift
func requestProgramListForAllDevices(channel: Int) async {
    await withTaskGroup(of: Void.self) { group in
        for device in discoveredDevices {
            if device.supportsPropertyExchange {
                group.addTask {
                    await self.fetchProgramList(for: device.muid, channel: channel)
                }
            }
        }
    }
}
```

**理由**
確実性とパフォーマンスの向上。

---

## 💡 Nitpick レベルの細かい指摘

### 💡 N-001: MIDI2KitService.swift - 型エイリアスの使用

**現在のコード** (Lines 19-20)
```swift
struct MIDI2KitDevice: Identifiable, Equatable {
    let id: UUID = UUID()
```

**提案**
```swift
typealias MIDI2DeviceID = UUID

struct MIDI2KitDevice: Identifiable, Equatable {
    let id: MIDI2DeviceID = .init()
```

**理由**
将来的にIDの型を変更する際の柔軟性が向上します。

---

### 💡 N-002: MIDI2KitService.swift - コメントの改善

**現在のコード** (Lines 531-535)
```swift
// MARK: - Notification Extension

extension Notification.Name {
    // Reuse existing notification name for compatibility
    // static let xProgramEditDidUpdate is already defined in MIDICIManager
}
```

**提案**
```swift
// MARK: - Notification Extension

extension Notification.Name {
    /// Notification posted when X-ProgramEdit data is updated
    /// - Note: Defined in MIDICIManager for backward compatibility
    // static let xProgramEditDidUpdate is already defined in MIDICIManager
}
```

**理由**
ドキュメントの明確性が向上します。

---

### 💡 N-003: MainPageView.swift - MIDILogger使用の一貫性

**現在のコード** (Lines 229-265)
```swift
MIDILogger.pe("Received xProgramEditDidUpdate notification")
// ...
MIDILogger.debug("No MIDI 2.0 device found for slider sync")
// ...
MIDILogger.pe("Syncing \(currentValues.count) parameter values to sliders")
// ...
MIDILogger.debug("Slider[\(i)] CC\(cc) = \(value)")
```

**提案**
ログレベルを統一するか、ログカテゴリを分離してください。

```swift
MIDILogger.debug("[PE] Received xProgramEditDidUpdate notification")
MIDILogger.debug("[Sync] No MIDI 2.0 device found for slider sync")
MIDILogger.debug("[Sync] Syncing \(currentValues.count) parameter values to sliders")
MIDILogger.debug("[Sync] Slider[\(i)] CC\(cc) = \(value)")
```

**理由**
ログの可読性とフィルタリングが向上します。

---

### 💡 N-004: SliderSettingRow.swift - 関数名の明確化

**現在のコード** (Lines 111-127)
```swift
func getPEName() -> String? {
    getPENameFor(cc: ccNumber)
}

func getPENameFor(cc: Int) -> String? {
    let name = midi2KitService.getControllerName(for: cc)
    return name != "CC\(cc)" ? name : nil
}
```

**提案**
```swift
private func propertyExchangeName(for cc: Int) -> String? {
    let name = midi2KitService.getControllerName(for: cc)
    return name != "CC\(cc)" ? name : nil
}

private var propertyExchangeName: String? {
    propertyExchangeName(for: ccNumber)
}
```

**理由**
命名規則の一貫性とSwiftらしい命名になります。

---

## 良かった点 ✨

1. **抽象化レイヤーの導入**: `MIDI2KitService`により、既存Viewへの影響を最小限に抑えながらMIDI2Kitへ移行できている
2. **型安全なMUID管理**: `MIDI2KitDevice`構造体により、MUIDとデスティネーションの対応を保証
3. **段階的な移行**: 既存のMIDICIManagerとの並行運用が可能な設計
4. **PE名の自動適用**: デバイス発見後、自動的にコントローラー名を取得・適用
5. **エラー回復の考慮**: タイムアウトやエラー時も基本機能は継続
6. **一貫したアーキテクチャ**: 全Viewで`MIDI2KitService.shared`を使用する一貫したパターン

---

## 総評

SimpleMidiControllerのMIDI2Kit移行は、アーキテクチャ的に健全なアプローチで実装されています。`MIDI2KitService`抽象化レイヤーにより、既存コードへの影響を最小限に抑えながら、新しいライブラリの機能を活用できています。

主な改善点は以下の通りです:

1. **エラーハンドリングの強化**: 全てのエラーを無視するのではなく、ログ記録と再試行戦略の導入
2. **非同期処理の最適化**: MainActorからのactor呼び出しを見直し、バックグラウンドタスクの活用
3. **固定遅延の排除**: イベント駆動型のアーキテクチャへの移行
4. **テスタビリティの向上**: Dependency Injectionパターンの導入検討

これらの改善を行うことで、より堅牢で保守性の高いコードベースになります。現状でも実用レベルの品質は達成されており、段階的な改善で十分対応可能です。

**推奨する次のステップ**:
1. W-001のエラーログ追加（即座に適用可能）
2. S-002, S-005の固定遅延を排除（中期的改善）
3. W-002のDI対応（長期的リファクタリング）
4. 実機テストでの動作確認と、エッジケースの洗い出し
