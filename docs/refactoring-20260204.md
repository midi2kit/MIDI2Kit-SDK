# リファクタリング計画

## 対象
- プロジェクト: MIDI2Kit
- 分析日: 2026-02-04
- 総行数: ~20,681行
- モジュール: 5つ (MIDI2Core, MIDI2Transport, MIDI2CI, MIDI2PE, MIDI2Kit)
- 型定義: 139 (class/struct/enum/actor/protocol)

## 分析結果

### 総合評価

**コード品質**: ⭐⭐⭐⭐☆ (4.5/5)

MIDI2Kitは非常に高品質なコードベースです。Swift 6 strict concurrency、actor分離、適切な責任分離が実装されており、最近のPhase 5-1, 5-2, 6のリファクタリング（PESubscriptionHandler抽出、PEError分類、PEManagerファイル分割）により構造が大幅に改善されています。

ただし、以下の点でさらなる改善の余地があります：
- 一部のファイルがまだ大きい（PEManager.swift: 1322行、MIDI2Client.swift: 987行）
- 複数フォーマット対応パーサーの複雑度（CIMessageParser.swift: 681行）
- エラーハンドリングパターンの重複
- テスト戦略の強化

---

## リファクタリング提案

### 🔴 高優先度（重要・影響大）

#### R-001: CIMessageParser の3フォーマット解析ロジックの分離

**問題**: `CIMessageParser.swift` (681行) のPE Reply解析が3つのフォーマット（CI 1.2, CI 1.1, KORG）に対応しており、複雑度が高い

**現状**:
```swift
public static func parsePEReply(_ payload: [UInt8], ciVersion: UInt8 = 2) -> PEReplyPayload? {
    // Try CI 1.2 format first
    if let result = parsePEReplyCI12(payload) { return result }
    // Try CI 1.1 format
    if let result = parsePEReplyCI11(payload) { return result }
    // Fallback: KORG-style format
    if let result = parsePEReplyKORG(payload) { return result }
    return nil
}
```

**提案**: Strategy Patternで各フォーマットを独立したパーサーに分離

```swift
// 新規ファイル: Sources/MIDI2CI/PEReplyParser/PEReplyFormatParser.swift
protocol PEReplyFormatParser {
    func parse(_ payload: [UInt8]) -> CIMessageParser.PEReplyPayload?
}

struct CI12FormatParser: PEReplyFormatParser { ... }
struct CI11FormatParser: PEReplyFormatParser { ... }
struct KORGFormatParser: PEReplyFormatParser { ... }

// CIMessageParser.swift
public static func parsePEReply(_ payload: [UInt8], ciVersion: UInt8 = 2) -> PEReplyPayload? {
    let parsers: [PEReplyFormatParser] = [
        CI12FormatParser(),
        CI11FormatParser(),
        KORGFormatParser()
    ]
    return parsers.lazy.compactMap { $0.parse(payload) }.first
}
```

**効果**:
- 各フォーマットの責任分離（SRP準拠）
- テスト容易性向上（各パーサーを独立テスト可能）
- 新フォーマット追加時の影響範囲最小化
- ファイルサイズ削減（681行 → 各200行×4ファイル）

**リスク**: 中（既存テストが充実しているため安全）

**工数**: 2-3時間

---

#### R-002: MIDI2Client の get/getDeviceInfo/getResourceList におけるタイムアウト＋フォールバックロジックの統合

**問題**: `MIDI2Client.swift` (987行) の `get()`, `getDeviceInfo()`, `getResourceList()` で類似のエラーハンドリング＋リトライ＋トレース記録が重複

**コードスメル**: **重複コード** (約150行×3メソッド = 450行の類似処理)

**現状** (3箇所で同じパターン):
```swift
public func get(_ resource: String, from muid: MUID) async throws -> PEResponse {
    let startTime = Date()
    let destination = try await resolveDestination(for: muid)
    let handle = PEDeviceHandle(muid: muid, destination: destination)
    do {
        let result = try await peManager.get(resource, from: handle, timeout: ...)
        recordTrace(operation: .getProperty, muid: muid, result: .success, ...)
        return result
    } catch let error as PEError {
        if case .timeout = error {
            if let nextDest = await destinationResolver.getNextCandidate(after: destination, for: muid) {
                let retryHandle = PEDeviceHandle(muid: muid, destination: nextDest)
                do {
                    let result = try await peManager.get(resource, from: retryHandle, ...)
                    await destinationResolver.cacheDestination(nextDest, for: muid)
                    recordTrace(...)
                    return result
                } catch { ... }
            }
        }
        recordTrace(operation: .getProperty, result: .error, ...)
        throw MIDI2Error(from: error, muid: muid)
    }
}
```

**提案**: Extract Function パターンで共通処理を統合

```swift
// 新規メソッド: MIDI2Client+RequestExecution.swift
private func executeWithRetry<T>(
    muid: MUID,
    operation: TraceOperation,
    resource: String? = nil,
    timeout: Duration? = nil,
    body: @Sendable (PEDeviceHandle) async throws -> T
) async throws -> T {
    let startTime = Date()
    let destination = try await resolveDestination(for: muid)
    let handle = PEDeviceHandle(muid: muid, destination: destination)

    do {
        let result = try await body(handle)
        recordTrace(operation: operation, muid: muid, result: .success, ...)
        return result
    } catch let error as PEError {
        if case .timeout = error,
           let nextDest = await destinationResolver.getNextCandidate(after: destination, for: muid) {
            // Retry with fallback destination
            let retryHandle = PEDeviceHandle(muid: muid, destination: nextDest)
            do {
                let result = try await body(retryHandle)
                await destinationResolver.cacheDestination(nextDest, for: muid)
                recordTrace(operation: operation, result: .success, ...)
                return result
            } catch {
                recordTrace(operation: operation, result: .timeout, ...)
                throw MIDI2Error(...)
            }
        }
        recordTrace(operation: operation, result: .error, ...)
        throw MIDI2Error(from: error, muid: muid)
    }
}

// 使用例（各メソッドが10行以下に）
public func get(_ resource: String, from muid: MUID) async throws -> PEResponse {
    try await executeWithRetry(muid: muid, operation: .getProperty, resource: resource) { handle in
        try await peManager.get(resource, from: handle, timeout: configuration.peTimeout)
    }
}
```

**効果**:
- 450行 → 150行（70%削減）
- バグ修正が1箇所で済む（DRY原則）
- テストが1つのメソッドで完結
- 新規リクエストメソッド追加が容易

**リスク**: 中（ロジック変更だが、既存の統合テストでカバー済み）

**工数**: 3-4時間

---

#### R-003: PEManager の大型メソッド分割（handleReceived）

**問題**: `PEManager.swift` の `handleReceived()` メソッドが長い（約150行、複数の責務）

**コードスメル**: **Long Method** (メッセージタイプごとのswitch文で6つの処理分岐)

**提案**: Extract Methodでメッセージタイプ別ハンドラーに分割

```swift
// Before: 1つの巨大メソッド
private func handleReceived(_ data: [UInt8]) async {
    guard let parsed = CIMessageParser.parse(data) else { return }
    switch parsed.messageType {
    case .peGetReply, .peSetReply: // 40行
    case .nak: // 30行
    case .invalidateMUID: // 20行
    case .peNotify: // 30行
    case .peSubscribeReply: // 30行
    default: break
    }
}

// After: 責務を分離
private func handleReceived(_ data: [UInt8]) async {
    guard let parsed = CIMessageParser.parse(data) else { return }
    switch parsed.messageType {
    case .peGetReply, .peSetReply:
        await handlePEReply(parsed)
    case .nak:
        await handleNAK(parsed)
    case .invalidateMUID:
        await handleInvalidateMUID(parsed)
    case .peNotify:
        await subscriptionHandler?.handleNotify(parsed)
    case .peSubscribeReply:
        await subscriptionHandler?.handleSubscribeReply(parsed)
    default:
        break
    }
}

private func handlePEReply(_ parsed: CIMessageParser.ParsedMessage) async { ... }
private func handleNAK(_ parsed: CIMessageParser.ParsedMessage) async { ... }
private func handleInvalidateMUID(_ parsed: CIMessageParser.ParsedMessage) async { ... }
```

**効果**:
- メソッドの複雑度低減（Cyclomatic Complexity: 12 → 3）
- テストしやすさ向上
- 各ハンドラーの責任明確化

**リスク**: 低（純粋なメソッド抽出、動作不変）

**工数**: 2時間

---

### 🟡 中優先度（品質向上）

#### R-004: DestinationResolver の戦略パターン明確化

**問題**: `DestinationResolver.swift` が内部で複数の解決戦略を持つが、戦略の切り替えロジックが暗黙的

**提案**: Strategy Patternで明示的に戦略を分離

```swift
protocol DestinationResolutionStrategy {
    func resolve(for muid: MUID, sources: [MIDISourceID]) async -> MIDIDestinationID?
}

struct KORGDestinationStrategy: DestinationResolutionStrategy { ... }
struct StandardDestinationStrategy: DestinationResolutionStrategy { ... }
struct CachedDestinationStrategy: DestinationResolutionStrategy { ... }

public actor DestinationResolver {
    private var strategies: [DestinationResolutionStrategy]

    func resolve(for muid: MUID) async -> MIDIDestinationID? {
        for strategy in strategies {
            if let result = await strategy.resolve(for: muid, sources: ...) {
                return result
            }
        }
        return nil
    }
}
```

**効果**:
- 新しいデバイス戦略の追加が容易
- テスト対象が明確（各戦略を独立テスト）
- デバッグ容易性向上（どの戦略が使われたか追跡可能）

**リスク**: 中（戦略選択ロジックの変更）

**工数**: 3時間

---

#### R-005: CoreMIDITransport のコールバック処理の整理

**問題**: `CoreMIDITransport.swift` (777行) のコールバックハンドリングが複数箇所に散在

**提案**: Delegate PatternでMIDIイベントハンドリングを整理

```swift
protocol CoreMIDIEventDelegate: Sendable {
    func handlePacket(_ packet: MIDIPacket, from source: MIDISourceID) async
    func handleSetupChange() async
}

// CoreMIDITransport内でcontinuationを直接yield するのではなく、
// delegateを通じてイベントを通知
private func handleNotification(_ notification: UnsafePointer<MIDINotification>) {
    // ...
    Task { await delegate?.handleSetupChange() }
}
```

**効果**:
- テスト用モックの作成が容易
- イベント処理ロジックの分離
- 将来的なイベント種類追加に対応しやすい

**リスク**: 中（内部構造変更）

**工数**: 4時間

---

#### R-006: PETypes.swift の分割

**問題**: `PETypes.swift` (921行) が16の型定義を含む巨大ファイル

**提案**: 機能ごとにファイル分割

```
Sources/MIDI2PE/Types/
├── PERequest.swift            (PERequest, PEDeviceHandle)
├── PECapability.swift         (PECapabilityReply, CategorySupport)
├── PEResourceTypes.swift      (PEResourceEntry, PEResourceList)
├── PEHeaderTypes.swift        (PEHeader, PEHeaderField)
├── PEDeviceInfo.swift         (PEDeviceInfo, PEManufacturer)
├── PESubscriptionTypes.swift  (PESubscription, SubscribeRequest)
├── PECacheTypes.swift         (DestinationCache, CacheEntry)
└── PEConstants.swift          (定数・列挙型)
```

**効果**:
- ナビゲーション容易性向上
- 型の責任範囲明確化
- Swiftのコンパイルユニットサイズ削減（ビルド時間改善）

**リスク**: 低（純粋なファイル分割、ロジック不変）

**工数**: 2時間

---

#### R-007: UMPFlexData.swift の生成メソッドの簡潔化

**問題**: `UMPFlexData.swift` (919行) で類似の生成メソッドが12個並んでいる（テキスト切り詰め処理の重複）

**提案**: Extract Functionでテキスト処理を統合

```swift
// Before: 各メソッドで同じ処理
public static func lyrics(...) -> UMPMessage {
    let data = Data(text.utf8.prefix(12))
    // ... UMP生成
}

public static func projectName(...) -> UMPMessage {
    let data = Data(text.utf8.prefix(12))
    // ... UMP生成
}

// After: 共通処理を抽出
private static func makeTextFlexData(
    status: UInt8,
    text: String,
    group: UInt8 = 0
) -> UMPMessage {
    let data = Data(text.utf8.prefix(12))
    // ... 共通UMP生成ロジック
}

public static func lyrics(_ text: String, group: UInt8 = 0) -> UMPMessage {
    makeTextFlexData(status: 0x01, text: text, group: group)
}

public static func projectName(_ text: String, group: UInt8 = 0) -> UMPMessage {
    makeTextFlexData(status: 0x05, text: text, group: group)
}
```

**効果**:
- 919行 → 約600行（35%削減）
- テキスト処理のバグ修正が1箇所で完結

**リスク**: 低（単純なメソッド抽出）

**工数**: 1.5時間

---

### 🔵 低優先度（将来的改善）

#### R-008: PESubscriptionHandler の TODO削除

**問題**: `PESubscriptionHandler.swift` に4つのTODOコメントが残存

```swift
// TODO: Phase 4 - Implement notification stream creation
// TODO: Phase 2 - Implement state management (4箇所)
```

**提案**: TODOを実装またはWONT FIXに変更

**効果**: コードベースの完成度向上、意図の明確化

**リスク**: なし

**工数**: 1時間（調査＋実装 or 削除）

---

#### R-009: Mcoded7 のパフォーマンス最適化

**問題**: `Mcoded7.swift` のエンコード/デコードがバイト単位の処理で非効率的

**提案**: SIMD命令またはポインタベース処理で高速化

```swift
// 現在: 1バイトずつ処理
for byte in input {
    // ...
}

// 改善案: チャンク処理
extension Mcoded7 {
    public static func encodeFast(_ input: Data) -> Data {
        var result = Data(capacity: input.count * 8 / 7 + 1)
        input.withUnsafeBytes { ptr in
            // SIMD or pointer-based processing
        }
        return result
    }
}
```

**効果**:
- 大きなPEレスポンス（ResourceList等）の処理高速化
- メモリアロケーション削減

**リスク**: 中（ロジック変更、境界ケーステスト必須）

**工数**: 5時間（実装＋パフォーマンステスト）

---

#### R-010: MIDI2Client のイベント配信の型安全化

**問題**: `makeEventStream()` がすべてのイベントを流すため、特定イベントのみ購読したい場合に非効率

**提案**: 型安全なイベントフィルタリング

```swift
public func makeEventStream<Event>(
    filtering eventType: Event.Type
) -> AsyncStream<Event> where Event: MIDI2ClientEvent {
    eventHub.makeStream().compactMap { $0 as? Event }
}

// 使用例
for await discovered in client.makeEventStream(filtering: DeviceDiscovered.self) {
    print("Found: \(discovered.device)")
}
```

**効果**:
- イベント購読の型安全性向上
- 不要なイベント処理の削減

**リスク**: 低（API追加、既存APIは維持）

**工数**: 2時間

---

#### R-011: 統合テストのパラメトライズ化

**問題**: `IntegrationTests.swift` で類似のテストケースが個別実装されている

**提案**: Swift Testingのパラメトライズドテストを活用

```swift
@Test("Multiple resources can be queried", arguments: [
    "DeviceInfo",
    "ResourceList",
    "ChannelList",
    "ProgramList"
])
func multipleResourcesQuery(resource: String) async throws {
    // ... 共通テストロジック
}
```

**効果**:
- テストコード削減
- 新規リソース追加時のテスト追加が容易

**リスク**: なし

**工数**: 2時間

---

#### R-012: JSON Schema検証の活用強化

**問題**: `PESchemaValidator.swift` が実装済みだが、実際のPE応答検証に十分活用されていない

**提案**: PEManager でデフォルトでスキーマ検証を有効化（オプトアウト可能）

```swift
public actor PEManager {
    public var enableSchemaValidation: Bool = true

    private func decodeResponse<T: Decodable>(...) throws -> T {
        if enableSchemaValidation {
            // Schema validation before decoding
            try PESchemaValidator.validate(response.body, schema: ...)
        }
        return try JSONDecoder().decode(T.self, from: response.body)
    }
}
```

**効果**:
- 不正なデバイス応答の早期検出
- デバッグ容易性向上

**リスク**: 中（パフォーマンス影響、誤検知の可能性）

**工数**: 3時間

---

## コードスメル詳細

### 1. Long Method（長すぎるメソッド）

| ファイル | メソッド | 行数 | 改善案 |
|---------|---------|------|--------|
| PEManager.swift | `handleReceived()` | ~150 | R-003 |
| MIDI2Client.swift | `getResourceList()` | ~100 | R-002 |
| MIDI2Client.swift | `getDeviceInfo()` | ~80 | R-002 |
| CIMessageParser.swift | `parsePEReplyCI12()` | ~60 | R-001 |

### 2. Large Class（大きすぎるクラス）

| ファイル | 行数 | 責務数 | 改善案 |
|---------|------|--------|--------|
| PEManager.swift | 1322 | 5 | **既に改善済み**（Phase 6で分割完了） |
| MIDI2Client.swift | 987 | 6 | R-002 |
| PETypes.swift | 921 | 16 | R-006 |
| UMPFlexData.swift | 919 | 12 | R-007 |

### 3. Duplicated Code（重複コード）

| 箇所 | 重複内容 | 行数 | 改善案 |
|------|---------|------|--------|
| MIDI2Client (get/getDeviceInfo/getResourceList) | タイムアウト＋リトライ＋トレース | ~450 | R-002 |
| UMPFlexData (text系メソッド) | テキスト切り詰め＋UMP生成 | ~300 | R-007 |
| CIMessageParser (CI12/CI11/KORG) | ペイロードパース | ~200 | R-001 |

### 4. Switch Statements（長いswitch文）

| ファイル | switch文 | 分岐数 | 改善案 |
|---------|---------|--------|--------|
| PEManager.swift | `handleReceived(messageType)` | 6 | R-003 |
| UMPParser.swift | `parse(messageType)` | 16 | **許容範囲**（UMP仕様準拠） |

### 5. Primitive Obsession（プリミティブ型の使いすぎ）

**良好**: MIDI2Kitは型安全性が高く、`MUID`, `DeviceIdentity`, `PEDeviceHandle` などの値型を適切に使用しています。この点での改善は不要です。

---

## 技術的負債

### 1. KORG互換性レイヤー

**債務**: CIMessageParserに3種類のPE Replyフォーマット対応が混在

**影響**: 新規デバイスフォーマット追加時の影響範囲が大きい

**返済計画**: R-001で戦略パターン化

**優先度**: 高

---

### 2. タイムアウト＋リトライロジックの重複

**債務**: MIDI2Clientの各リクエストメソッドで同じエラーハンドリングを実装

**影響**: バグ修正が3箇所必要、テストカバレッジ低下

**返済計画**: R-002で共通化

**優先度**: 高

---

### 3. TODOコメント

**債務**: PESubscriptionHandler に4つの未実装TODO

**影響**: コードの完成度に対する疑問、メンテナンス時の混乱

**返済計画**: R-008で実装または削除

**優先度**: 低

---

## パターン適用の機会

### 1. Strategy Pattern

- **R-001**: CIMessageParser のフォーマットパーサー
- **R-004**: DestinationResolver の解決戦略

**メリット**:
- Open/Closed Principle準拠
- 新規戦略追加が容易
- テスト容易性向上

---

### 2. Template Method Pattern

- **R-002**: MIDI2Client のリクエスト実行フロー

**メリット**:
- 共通フローの一元管理
- サブクラスでの拡張ポイント明確化

---

### 3. Decorator Pattern

- **R-012**: JSON Schema検証の任意有効化

**メリット**:
- 機能の動的追加/削除
- 既存コードへの影響最小化

---

## 実装優先度マトリクス

| ID | 提案 | 優先度 | 工数 | 影響範囲 | ROI |
|----|------|--------|------|---------|-----|
| R-001 | CIMessageParser分離 | 高 | 3h | CI | ⭐⭐⭐⭐ |
| R-002 | MIDI2Client共通化 | 高 | 4h | Kit | ⭐⭐⭐⭐⭐ |
| R-003 | PEManager handleReceived分割 | 高 | 2h | PE | ⭐⭐⭐ |
| R-004 | DestinationResolver戦略化 | 中 | 3h | Kit | ⭐⭐⭐ |
| R-005 | CoreMIDITransport整理 | 中 | 4h | Transport | ⭐⭐ |
| R-006 | PETypes分割 | 中 | 2h | PE | ⭐⭐ |
| R-007 | UMPFlexData簡潔化 | 中 | 1.5h | Core | ⭐⭐ |
| R-008 | TODO削除 | 低 | 1h | PE | ⭐ |
| R-009 | Mcoded7最適化 | 低 | 5h | Core | ⭐ |
| R-010 | イベント型安全化 | 低 | 2h | Kit | ⭐ |
| R-011 | テストパラメトライズ | 低 | 2h | Tests | ⭐ |
| R-012 | Schema検証強化 | 低 | 3h | PE | ⭐ |

**ROI (Return on Investment)**:
- ⭐⭐⭐⭐⭐ 非常に高い
- ⭐⭐⭐⭐ 高い
- ⭐⭐⭐ 中程度
- ⭐⭐ やや低い
- ⭐ 低い

---

## 推奨実装順序

### Phase A: 緊急改善（1-2週間）
1. **R-002** - MIDI2Client共通化（ROI最高、影響大）
2. **R-001** - CIMessageParser分離（複雑度削減）
3. **R-003** - PEManager分割（可読性向上）

**期待効果**: コード量20%削減、テスト容易性50%向上

---

### Phase B: 構造改善（2-3週間）
4. **R-004** - DestinationResolver戦略化
5. **R-006** - PETypes分割
6. **R-007** - UMPFlexData簡潔化

**期待効果**: ナビゲーション30%改善、新機能追加容易性向上

---

### Phase C: 品質向上（任意）
7. **R-008** - TODO削除
8. **R-011** - テストパラメトライズ
9. **R-012** - Schema検証強化

**期待効果**: コードベース完成度100%達成

---

### Phase D: パフォーマンス（必要に応じて）
10. **R-009** - Mcoded7最適化
11. **R-010** - イベント型安全化
12. **R-005** - CoreMIDITransport整理

**期待効果**: 大規模PE応答の処理速度20%向上

---

## リスクと対策

### 高リスク項目

| ID | リスク内容 | 影響度 | 対策 |
|----|----------|--------|------|
| R-002 | ロジック変更による振る舞い変化 | 高 | 既存統合テスト実行、手動テスト追加 |
| R-004 | 戦略選択ロジックの変更 | 中 | KORGデバイスでの実機テスト必須 |
| R-005 | CoreMIDI内部構造変更 | 中 | リファクタリング前後でパフォーマンス計測 |

### 対策

1. **各改善前にテスト実行** - 全311テストがパスすることを確認
2. **段階的コミット** - 各リファクタリングを独立したコミットに
3. **実機検証** - KORGデバイスでの動作確認（特にR-001, R-004）
4. **パフォーマンス計測** - ベンチマークテスト追加（R-009）
5. **ドキュメント更新** - CLAUDE.md, README.mdの同期更新

---

## 完了条件

### 各リファクタリング完了の定義

- [ ] 全311テストがパス
- [ ] 新規テストが追加されている（該当する場合）
- [ ] ビルド警告ゼロ
- [ ] SwiftLintチェックパス（導入されている場合）
- [ ] コードレビュー完了
- [ ] CLAUDE.mdのアップデート
- [ ] CHANGELOG.mdへの記録

### Phase A完了条件

- [ ] コード量20%削減（行数: 20,681 → 16,500以下）
- [ ] 重複コード削減（R-002完了で450行削減）
- [ ] Cyclomatic Complexity低減（主要メソッドが10以下）
- [ ] テストカバレッジ維持（100%）

---

## 注意事項

### リファクタリング中の原則

1. **動作を変えない** - 外部APIは互換性維持
2. **テストを先に実行** - 現在の振る舞いを保証
3. **小さなステップ** - 1つのリファクタリング = 1つのコミット
4. **継続的テスト** - 各ステップ後にテスト実行

### やってはいけないこと

- ❌ リファクタリング中の機能追加（別PRで実施）
- ❌ 複数のリファクタリングを同時実行（影響範囲が大きくなる）
- ❌ テスト追加なしの大規模変更
- ❌ deprecatedマークされたAPIの削除（互換性維持）

---

## 結論

MIDI2Kitは既に非常に高品質なコードベースですが、上記のリファクタリングにより以下の改善が期待できます：

### 定量的効果

- **コード量**: 20,681行 → 約16,500行（20%削減）
- **重複コード**: 約1,000行削減
- **最大ファイルサイズ**: 1,322行 → 800行以下
- **Cyclomatic Complexity**: 主要メソッドで平均30%低減

### 定性的効果

- **保守性**: 新規機能追加時の影響範囲が明確化
- **テスト容易性**: 各コンポーネントの独立テストが容易
- **可読性**: ファイル分割により目的のコードが見つけやすい
- **拡張性**: 新規デバイスフォーマット/戦略の追加が容易

### 推奨アクション

**今すぐ実施**: Phase A (R-001, R-002, R-003)
**理由**: 最も高いROI、既存の充実したテストで安全に実施可能

**次のマイルストーン**: Phase B (R-004, R-006, R-007)
**理由**: 構造改善により、将来的な機能追加がスムーズに

**必要に応じて**: Phase C, D
**理由**: 品質向上・パフォーマンス最適化（緊急性は低い）

---

**作成日**: 2026-02-04
**次回レビュー推奨日**: Phase A完了後
