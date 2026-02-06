# セキュリティ監査レポート

## 監査概要

- **対象**: MIDI2Kit (Swift MIDI 2.0 ライブラリ)
- **日付**: 2026-02-07
- **監査範囲**: 全5モジュール (MIDI2Core, MIDI2Transport, MIDI2CI, MIDI2PE, MIDI2Kit)
- **監査タイプ**: 静的解析 (ソースコードレビュー)
- **監査フレームワーク**: OWASP Mobile Top 10 + iOS固有セキュリティ

## エグゼクティブサマリー

| 深刻度 | 件数 |
|--------|------|
| Critical | 0件 |
| High | 0件 |
| Medium | 0件 |
| Low | 2件 |
| Informational | 4件 |

**総合リスク評価**: **低**

MIDI2Kitは、セキュリティの観点から適切に設計・実装されたライブラリです。Swift 6 strict concurrencyが有効化されており、バッファサイズ制限によるDoS保護が複数箇所で実装されています。外部依存は1つのみ（ドキュメント生成用のswift-docc-plugin）で、攻撃対象面は最小化されています。

---

## 発見事項

### [SEV-001] Low: force_cast の使用

**概要**
`PEManager+RobustDecoding.swift`でforce_cast (`as!`) が使用されています。

**影響**
型が一致しない場合にランタイムクラッシュを引き起こす可能性があります。ただし、このコードパスは`PEEmptyResponseRepresentable`プロトコルに準拠した型のみが到達するため、実際のリスクは低いです。

**場所**
- ファイル: `/Users/hakaru/Desktop/Develop/MIDI2Kit/Sources/MIDI2PE/PEManager+RobustDecoding.swift`
- 行: 50-51

**証跡**
```swift
if let emptyType = T.self as? any PEEmptyResponseRepresentable.Type {
    // swiftlint:disable:next force_cast
    let emptyValue = emptyType.emptyResponse as! T
    self.saveDiagnostics(nil)
    return (emptyValue, nil)
}
```

**推奨対策**
swiftlintの無効化コメントが付与されており、開発者はリスクを認識しています。より安全にするには、`as?`とガード文を使用することを検討してください。

```swift
if let emptyType = T.self as? any PEEmptyResponseRepresentable.Type,
   let emptyValue = emptyType.emptyResponse as? T {
    self.saveDiagnostics(nil)
    return (emptyValue, nil)
}
// 型が一致しない場合のフォールバック処理
```

**参考**
- [Swift Language Guide - Type Casting](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/typecasting/)

---

### [SEV-002] Low: Zlib展開時の大きなメモリ割り当て許容

**概要**
`ZlibMcoded7.decompress`メソッドは、最大100MBまでのメモリ割り当てを許容します。悪意のある圧縮データが送信された場合、メモリを大量に消費する可能性があります。

**影響**
MIDIデバイスから悪意のある圧縮データが送信された場合、一時的にアプリケーションのメモリ使用量が増加する可能性があります。ただし、100MBの上限が設定されているため、無制限のメモリ消費は防止されています。

**場所**
- ファイル: `/Users/hakaru/Desktop/Develop/MIDI2Kit/Sources/MIDI2Core/ZlibMcoded7.swift`
- 行: 200

**証跡**
```swift
while destinationBufferSize <= 100_000_000 { // 100MB max to prevent memory exhaustion
    let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationBufferSize)
    defer { destinationBuffer.deallocate() }
    // ...
}
```

**推奨対策**
現在の実装は適切な上限を設定しています。アプリケーションの要件に応じて、この上限を調整することを検討してください。ドキュメントに、この制限について明記することを推奨します。

---

### [SEV-003] Informational: DEBUGコンパイル条件下のprint文

**概要**
`CIMessageParser.swift`内に`#if DEBUG`条件下でprint文が存在する可能性があります。また、`CoreMIDITransport.swift`にはDEBUG条件下でassertionFailureが使用されています。

**影響**
リリースビルドでは実行されないため、本番環境への影響はありません。DEBUGビルドでのみ情報が出力されます。

**場所**
- ファイル: `/Users/hakaru/Desktop/Develop/MIDI2Kit/Sources/MIDI2Transport/CoreMIDITransport.swift`
- 行: 207

**証跡**
```swift
#if DEBUG
shutdownLock.lock()
let wasProperlyShutdown = didShutdown
shutdownLock.unlock()
if !wasProperlyShutdown {
    assertionFailure("CoreMIDITransport released without calling shutdown() - this may race with in-flight sends")
}
#endif
```

**推奨対策**
現在の実装は適切です。`#if DEBUG`ガードにより、本番ビルドには含まれません。

---

### [SEV-004] Informational: CoreMIDI APIで必要なUnsafe操作

**概要**
CoreMIDI APIとの統合のため、`CoreMIDITransport.swift`と`ZlibMcoded7.swift`でunsafeポインタ操作が使用されています。

**影響**
これらのunsafe操作はAppleのCoreMIDIおよびCompressionフレームワークとの統合に必須であり、避けることができません。実装は適切にメモリ管理されており、`defer`でリソース解放が保証されています。

**場所**
- ファイル: `/Users/hakaru/Desktop/Develop/MIDI2Kit/Sources/MIDI2Transport/CoreMIDITransport.swift`
- 行: 343-346 (MIDIPacketList構築)、554-563 (EventList解析)

- ファイル: `/Users/hakaru/Desktop/Develop/MIDI2Kit/Sources/MIDI2Core/ZlibMcoded7.swift`
- 行: 171-192 (圧縮)、200-230 (展開)

**証跡**
```swift
// CoreMIDITransport.swift - MIDIPacketListの構築
let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
defer { buffer.deallocate() }

let packetList = UnsafeMutableRawPointer(buffer).bindMemory(to: MIDIPacketList.self, capacity: 1)
```

```swift
// CoreMIDITransport.swift - EventListの安全な反復処理
for packet in eventList.unsafeSequence() {
    let wordCount = Int(packet.pointee.wordCount)
    guard wordCount > 0 else { continue }
    // ...
}
```

**推奨対策**
現在の実装は適切です。`defer`によるリソース解放、`guard`による境界チェック、AppleのunsafeSequence() APIの使用により、メモリ安全性が確保されています。

---

### [SEV-005] Informational: バッファオーバーフロー保護の実装確認

**概要**
複数のコンポーネントでバッファサイズ制限が適切に実装されています。

**実装箇所と制限値**

| コンポーネント | ファイル | 制限値 | 目的 |
|---------------|----------|--------|------|
| SysExAssembler | SysExAssembler.swift | 1 MB (デフォルト) | SysExメッセージの断片化対策 |
| UMPSysEx7Assembler | UMPSysEx7Assembler.swift | 64 KB (デフォルト) | UMP SysEx7再組立 |
| ZlibMcoded7.decompress | ZlibMcoded7.swift | 100 MB (ハード制限) | 圧縮データ展開 |

**証跡**
```swift
// SysExAssembler.swift
public static let defaultMaxBufferSize: Int = 1_048_576  // 1 MB

// UMPSysEx7Assembler.swift
public init(maxBufferSize: Int = 65536) {  // 64 KB
    self.maxBufferSize = maxBufferSize
}

// ZlibMcoded7.swift
while destinationBufferSize <= 100_000_000 { // 100MB max
```

**評価**
DoS攻撃に対する適切な保護が実装されています。オーバーフロー発生時の診断カウンター(`overflowCount`)も提供されています。

---

### [SEV-006] Informational: Mcoded7デコードのフォールバック動作

**概要**
MIDI-CI Property Exchange応答のMcoded7デコード時に、自動フォールバックロジックが実装されています。

**動作**
1. ヘッダーが明示的にMcoded7を示す場合 → デコード
2. ボディがJSON形式で開始する場合 (`{` または `[`) → そのまま使用
3. Mcoded7として正常にデコードできる場合 → デコード結果を使用 (KORG対応)
4. それ以外 → 生データをそのまま使用

**評価**
この動作は、KORG Module Pro等の非標準実装デバイスとの互換性のために意図的に設計されています。セキュリティリスクはありませんが、予期しないデータ形式の場合に意図しない動作を引き起こす可能性があるため、ドキュメントに記載することを推奨します。

---

## 正の所見（セキュリティ強化点）

### Swift 6 Strict Concurrency

**Package.swift**で`StrictConcurrency`が有効化されており、データ競合を防止しています。

```swift
swiftSettings: [
    .enableExperimentalFeature("StrictConcurrency")
]
```

### Actor-Based設計

すべてのマネージャクラス（`CIManager`, `PEManager`, `SysExAssembler`, `UMPSysEx7Assembler`）がActorとして実装されており、スレッドセーフ性が保証されています。

### 最小限の外部依存

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.4.3")
]
```

唯一の依存は`swift-docc-plugin`（ドキュメント生成用）であり、ランタイムには含まれません。サプライチェーン攻撃のリスクは最小化されています。

### 入力検証

UMPパーサーおよびCIメッセージパーサーで適切な入力検証が実装されています。

```swift
// CIMessageParser.swift
guard data.count >= 15 else { return nil }
guard data.first == MIDICIConstants.sysExStart,
      data.last == MIDICIConstants.sysExEnd else { return nil }
```

```swift
// UMPParser.swift
guard words.count >= mt.wordCount else { return nil }
```

### ハードコードされた機密情報の不在

grep検索により、ソースコード内にハードコードされたAPIキー、パスワード、トークン等の機密情報が存在しないことを確認しました。

```
検索パターン: apiKey|secret|password|token|credential
結果: CIワークフローのRELEASE_PATのみ（CI/CD用、期待通り）
```

### HTTP通信の不在

```
検索パターン: http://
結果: 0件 (すべてHTTPSまたはローカル通信)
```

---

## 推奨事項（優先順位順）

### 短期（次回リリース）

1. **[SEV-001] force_castの安全化検討**
   - 現在swiftlint無効化で対応済みだが、より安全なパターンへの移行を検討

### 中期（将来のイテレーション）

2. **ドキュメント追加**
   - ZlibMcoded7の100MB制限についてAPI ドキュメントに明記
   - Mcoded7フォールバック動作について開発者ドキュメントに記載

3. **メモリ制限の設定可能化**
   - ZlibMcoded7.decompressの最大サイズを設定可能にすることを検討
   - アプリケーション要件に応じた調整が可能に

---

## 監査対象外・制限事項

- **動的解析**: 本監査は静的解析のみで、ファジングテストや動的解析は実施していません
- **実機テスト**: 実際のMIDIデバイスを使用した攻撃シナリオのテストは未実施
- **サードパーティ監査**: swift-docc-pluginの脆弱性監査は本監査の対象外
- **暗号化実装**: MIDI2Kitは暗号化機能を提供しないため、暗号化評価は対象外

---

## 監査結論

MIDI2Kitは、iOSアプリケーションで使用する**低リスク**のライブラリです。

- Criticalおよび High深刻度の脆弱性は発見されませんでした
- Swift 6の厳格な並行性チェックにより、データ競合リスクは最小化されています
- バッファサイズ制限によりDoS攻撃への耐性が確保されています
- 外部依存が最小限であり、サプライチェーンリスクは低いです

本監査の結果、MIDI2Kitは本番環境での使用に**適している**と判断します。

---

*監査実施: Claude Code (Opus 4.5)*
*監査日: 2026-02-07*
