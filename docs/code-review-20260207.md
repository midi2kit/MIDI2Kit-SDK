# コードレビューレポート

## 概要
- レビュー対象: UMP SysEx7双方向変換 + RPN/NRPN → MIDI 1.0 CC変換
- レビュー日: 2026-02-07
- 変更ファイル数: 8 (新規2, 修正6)
- テスト数: 37 (新規30 SysEx7 + 7 RPN/NRPN)
- テスト結果: 564件全てpass

## サマリー
- 🔴 Critical: 0件
- 🟡 Warning: 2件
- 🔵 Suggestion: 3件
- 💡 Nitpick: 1件

## 詳細

### 🟡 [UMPParser.swift:254] numBytes検証の強化提案

**問題**
`parseData64`で`numBytes`フィールドを`min(numBytes, 6)`でクランプしているが、仕様違反値（7以上）が来た場合の警告がない。

**現在のコード**
```swift
let validCount = min(numBytes, 6)
return .data64(group: group, status: status, bytes: Array(bytes.prefix(validCount)))
```

**提案**
```swift
let validCount = min(numBytes, 6)
if numBytes > 6 {
    MIDI2Logger.log("Data64 numBytes field exceeds 6: \(numBytes), clamped to 6", category: .ump)
}
return .data64(group: group, status: status, bytes: Array(bytes.prefix(validCount)))
```

**理由**
MIDI 2.0 UMP仕様ではData 64のnumBytesは0-6が有効範囲。仕様違反のパケットを検出できると、デバイス互換性問題のデバッグが容易になる。ただし、実害はない（正しく動作する）ため、Warningレベル。

---

### 🟡 [UMPTranslator.swift:152-170] RPN/NRPN変換で32-bitデータの下位14bitが失われる

**問題**
RPN/NRPN → MIDI 1.0変換で、32-bit値を7-bit Data Entry MSB (CC 6)のみで送信しているため、下位14bit（LSB + fraction）の精度情報が失われる。

**現在のコード**
```swift
case .registeredController(_, let channel, let bank, let index, let value):
    let ch = channel.value
    let dataMSB = downscale32to7(value)  // Upper 7 bits only
    return [
        0xB0 | ch, 101, bank & 0x7F,
        0xB0 | ch, 100, index & 0x7F,
        0xB0 | ch, 6, dataMSB  // CC 6 only (no CC 38 for LSB)
    ]
```

**提案**
14-bitエンコーディング対応版:
```swift
case .registeredController(_, let channel, let bank, let index, let value):
    let ch = channel.value
    let value14 = downscale32to14(value)
    let dataMSB = UInt8((value14 >> 7) & 0x7F)
    let dataLSB = UInt8(value14 & 0x7F)
    return [
        0xB0 | ch, 101, bank & 0x7F,
        0xB0 | ch, 100, index & 0x7F,
        0xB0 | ch, 6, dataMSB,   // CC 6 (Data Entry MSB)
        0xB0 | ch, 38, dataLSB   // CC 38 (Data Entry LSB)
    ]
```

**理由**
MIDI 1.0 RPNはCC 6 (MSB) + CC 38 (LSB)で14-bit精度をサポートしている。現在の実装は7-bit精度（0.78%分解能）に留まるが、14-bit精度（0.0061%分解能）まで向上可能。ただし、すべてのデバイスがCC 38に対応しているわけではないため、互換性を考慮し**オプション設定で切り替え可能**にするのが理想。

**影響範囲**
- Pitch Bend Sensitivity (RPN 0:0)
- Channel Fine Tuning (RPN 0:1)
などの精密なパラメータ設定時に精度不足となる。

---

### 🔵 [UMPSysEx7Assembler.swift:76-81] バッファオーバーフロー時のロギング追加

**問題**
バッファオーバーフロー時に黙って破棄している。デバッグ困難。

**現在のコード**
```swift
guard newSize <= maxBufferSize else {
    // Buffer overflow — discard
    buffers[group] = nil
    return nil
}
```

**提案**
```swift
guard newSize <= maxBufferSize else {
    MIDI2Logger.log(
        "SysEx7 buffer overflow on group \(group): \(newSize) bytes exceeds limit \(maxBufferSize)",
        category: .ump
    )
    buffers[group] = nil
    return nil
}
```

**理由**
大きなSysExメッセージを受信したときの動作が可視化され、デバッグが容易になる。

---

### 🔵 [UMPTranslator.swift:52-74] `process`の順序ロジックの明示化

**問題**
`UMPSysEx7Assembler.process`で、Continue/End時にバッファが存在しない場合、Start抜けなのかリセット後なのか区別できない。

**提案**
エラー状態を返す構造体を導入:
```swift
public enum SysEx7AssemblerResult {
    case complete([UInt8])  // Message complete
    case incomplete         // Accumulating
    case orphanedContinue   // Continue without Start
    case orphanedEnd        // End without Start
    case overflow           // Buffer overflow
}

public func process(group: UInt8, status: UInt8, bytes: [UInt8]) -> SysEx7AssemblerResult {
    // ...
}
```

**理由**
エラー種別を呼び出し側で処理可能になり、診断・ロギング・リカバリー戦略を精密化できる。ただし、現在のシンプルなAPIでも動作上の問題はないため、Suggestionレベル。

---

### 🔵 [UMPBuilder.swift:355-382] data64ビルダーのAPI一貫性

**問題**
`UMPBuilder.data64()`は低レベルAPI（status/numBytes/dataを全て指定）だが、SysEx7用途としては`UMP.sysEx7`ファクトリが高レベルAPIとして存在する。しかし、Start/Continue/End個別のビルダーが`UMP.sysEx7`に存在しない。

**提案**
`UMP.sysEx7`に以下を追加:
```swift
public enum sysEx7 {
    /// Build Start packet
    public static func start(group: UMPGroup = 0, payload: [UInt8]) -> [UInt32]? {
        guard payload.count <= 6 else { return nil }
        return UMPBuilder.data64(
            group: group.rawValue,
            status: SysEx7Status.start.rawValue,
            numBytes: UInt8(payload.count),
            data: payload
        )
    }

    /// Build Continue packet
    public static func `continue`(group: UMPGroup = 0, payload: [UInt8]) -> [UInt32]? {
        // ...
    }

    /// Build End packet
    public static func end(group: UMPGroup = 0, payload: [UInt8]) -> [UInt32]? {
        // ...
    }
}
```

**理由**
APIの一貫性向上。ただし、`fromMIDI1()`で自動分割される用途が主であり、手動パケット構築のニーズは限定的なため、優先度は低い。

---

### 💡 [UMPTypes.swift:136] SysEx7Statusのドキュメントコメント

**問題**
`SysEx7Status`の各ケースに具体的な使用例が記載されていない。

**提案**
```swift
/// SysEx7 (Data 64) message status codes
///
/// Used in the status field of Data 64 (Type 0x3) UMP messages to indicate
/// whether the packet is a complete message or part of a multi-packet sequence.
///
/// ## Example Usage
/// - Complete: For SysEx <= 6 bytes payload
/// - Start: First packet of SysEx > 6 bytes
/// - Continue: Middle packets
/// - End: Final packet
///
/// Reference: MIDI 2.0 UMP Specification, Section 3.1
public enum SysEx7Status: UInt8, Sendable, CaseIterable {
    /// Complete SysEx message in one packet (payload <= 6 bytes)
    /// Example: F0 7E 7F 06 01 F7 (4 payload bytes)
    case complete = 0x0

    /// First packet of a multi-packet SysEx message
    /// Contains first 6 data bytes
    case start = 0x1

    /// Continuation packet of a multi-packet SysEx message
    /// Contains next 6 data bytes
    case `continue` = 0x2

    /// Last packet of a multi-packet SysEx message
    /// Contains final data bytes (1-6)
    case end = 0x3
}
```

**理由**
ドキュメントの充実。実装には影響しないため、Nitpickレベル。

---

## 良かった点

### 1. ⭐⭐⭐⭐⭐ テストカバレッジが極めて高い
- **30件のSysEx7テスト**が以下を網羅:
  - 短いSysEx (Complete packet)
  - 長いSysEx (Start + Continue + End)
  - エッジケース (空, 6byte境界, 7byte, 100byte)
  - ラウンドトリップ (MIDI1.0 → UMP → MIDI1.0)
  - `UMPSysEx7Assembler`の全ケース（orphaned Continue/End, overflow, group独立性, reset）
- **7件のRPN/NRPN変換テスト**で:
  - 基本的なRPN/NRPN → CC変換
  - 異なるチャンネル、値0、relativeの未対応確認
  - バッチストリームでの動作確認

### 2. ⭐⭐⭐⭐⭐ UMPSysEx7Assembler の actor 設計が秀逸
```swift
public actor UMPSysEx7Assembler {
    private var buffers: [UInt8: [UInt8]] = [:]
    // ...
}
```
- **スレッドセーフ**: actorでデータ競合を自動回避
- **グループ別バッファ管理**: 複数グループで並行してSysExを受信可能
- **オーバーフロー保護**: `maxBufferSize`で無制限蓄積を防止
- **ステートレス設計**: 各グループのバッファは独立しており、エラー伝搬なし

### 3. ⭐⭐⭐⭐ parseData64 の numBytes 修正が仕様準拠
```swift
// 修正前（不具合）: numBytesを使わずに全6byteを返していた可能性
// 修正後: numBytes フィールドを正しく参照
let validCount = min(numBytes, 6)
return .data64(group: group, status: status, bytes: Array(bytes.prefix(validCount)))
```
- MIDI 2.0 UMP仕様に準拠
- テスト `parseData64NumBytes` で明示的に検証

### 4. ⭐⭐⭐⭐ UMPBuilder.data64() の柔軟な設計
```swift
public static func data64(
    group: UInt8,
    status: UInt8,
    numBytes: UInt8,
    data: [UInt8]
) -> [UInt32]
```
- **ゼロパディング自動処理**: dataが不足していても正しくパケット生成
- **クランプ処理**: `numBytes`が7以上でも安全に動作
- **汎用性**: SysEx7以外の将来のData 64用途にも対応可能

### 5. ⭐⭐⭐⭐ RPN/NRPN変換の実装がMIDI仕様に忠実
```swift
case .registeredController(_, let channel, let bank, let index, let value):
    let ch = channel.value
    let dataMSB = downscale32to7(value)
    return [
        0xB0 | ch, 101, bank & 0x7F,  // CC 101 (RPN MSB)
        0xB0 | ch, 100, index & 0x7F, // CC 100 (RPN LSB)
        0xB0 | ch, 6, dataMSB          // CC 6 (Data Entry MSB)
    ]
```
- MIDI 1.0 RPN仕様（CC 101, 100, 6）に準拠
- NRPNも同様（CC 99, 98, 6）
- `relativeRegisteredController`などMIDI 1.0非対応の型は`nil`を返す適切な判断

### 6. ⭐⭐⭐ fromMIDI1SysEx の F0/F7 ストリップが親切設計
```swift
var payload = bytes
if payload.first == 0xF0 { payload.removeFirst() }
if payload.last == 0xF7 { payload.removeLast() }
```
- 呼び出し側がF0/F7付きでもなしでも動作
- API使いやすさの向上

### 7. ⭐⭐⭐ UMP.sysEx7 ファクトリの追加で統一感
```swift
public enum sysEx7 {
    public static func fromMIDI1(group: UMPGroup = 0, bytes: [UInt8]) -> [[UInt32]]
    public static func complete(group: UMPGroup = 0, payload: [UInt8]) -> [UInt32]?
}
```
- `UMP.noteOn`, `UMP.midi1.noteOn`, `UMP.sysEx7.fromMIDI1` のAPI体系が一貫
- ネームスペースが直感的

---

## パフォーマンス考慮点

### ✅ メモリ効率
- `UMPSysEx7Assembler`の`maxBufferSize: 65536`は妥当な上限
- バッファはグループ単位で管理され、不要時は自動解放（nilへの代入）

### ✅ コピー回数の最小化
```swift
buffers[group]!.append(contentsOf: bytes)  // in-place append
```
- 中間配列の生成なし

### ⚠️ RPN/NRPN変換の配列アロケーション
```swift
return [
    0xB0 | ch, 101, bank & 0x7F,
    0xB0 | ch, 100, index & 0x7F,
    0xB0 | ch, 6, dataMSB
]  // 9要素の配列を毎回生成
```
- 1メッセージあたり9byteの配列生成
- 頻繁に呼ばれる環境では、事前アロケーション＋in-place書き込みで最適化可能
- ただし、実用上の性能問題は低い（RPNは設定用途で高頻度ではない）

---

## 仕様準拠性

### ✅ MIDI 2.0 UMP仕様準拠
- **Message Type 0x3 (Data 64)**: 正しくパース・生成
- **numBytes フィールド (bits 19-16)**: 正しく使用
- **SysEx7 Status (bits 23-20)**: Complete/Start/Continue/Endの4値を正しく実装

### ✅ MIDI 1.0 SysEx仕様準拠
- F0開始、F7終了を正しく付与・除去
- 7-bit cleanなデータのみを扱う（8bitマスク不要だが、将来の拡張に備えて安全）

### ✅ MIDI 1.0 RPN/NRPN仕様準拠
- CC 101/100 (RPN MSB/LSB)
- CC 99/98 (NRPN MSB/LSB)
- CC 6 (Data Entry MSB)
- ⚠️ CC 38 (Data Entry LSB) は未実装（Warningで既述）

---

## エッジケースのハンドリング

### ✅ 空SysEx
```swift
@Test("Empty SysEx returns empty packets")
func emptySysEx() {
    let packets = UMPTranslator.fromMIDI1SysEx([], group: 0)
    #expect(packets.isEmpty)
}
```
→ 正しく空配列を返す

### ✅ 最小SysEx (F0 F7)
```swift
@Test("SysEx with only F0 F7 generates Complete with 0 bytes")
```
→ Complete packet with numBytes=0 を正しく生成

### ✅ 境界値 (6 byte payload)
```swift
@Test("SysEx with exactly 6 payload bytes generates single Complete packet")
```
→ 1パケットで完結

### ✅ 7 byte payload (境界+1)
```swift
@Test("SysEx with 7 payload bytes generates Start + End")
```
→ 2パケット (Start 6byte + End 1byte)

### ✅ 大きなSysEx (100 byte)
```swift
@Test("Large SysEx (100 bytes) generates correct packet count")
```
→ 17パケット (Start + 15×Continue + End)

### ✅ バッファオーバーフロー
```swift
@Test("Assembler: Buffer overflow protection")
func assemblerBufferOverflow() async {
    let assembler = UMPSysEx7Assembler(maxBufferSize: 10)
    // 10byte超過時にバッファ破棄
}
```
→ 正しく破棄し、End時にnilを返す

### ✅ orphaned Continue/End
```swift
@Test("Assembler: Continue without Start returns nil")
@Test("Assembler: End without Start returns nil")
```
→ 正しくnilを返す（誤動作しない）

### ✅ 新しいStart時の前回バッファ破棄
```swift
@Test("Assembler: New Start discards previous incomplete")
```
→ 古いバッファを上書き

---

## API設計の一貫性

### ✅ UMPTranslator の双方向性
- `toMIDI1(message: any UMPMessage) -> [UInt8]?`
- `fromMIDI1(_ bytes: [UInt8], group: UMPGroup) -> (any UMPMessage)?`
- `fromMIDI1ToMIDI2(_ bytes: [UInt8], group: UMPGroup) -> UMPMIDI2ChannelVoice?`
- `fromMIDI1SysEx(_ bytes: [UInt8], group: UMPGroup) -> [[UInt32]]`
- `data64ToMIDI1SysEx(_ parsed: ParsedUMPMessage) -> [UInt8]?`

→ 命名規則が統一されており、直感的

### ✅ UMPBuilder vs UMP ファクトリ
- **UMPBuilder**: 低レベル、生UInt32配列を返す
- **UMP**: 高レベル、型安全な enum を返す

→ 使い分けが明確

### ✅ データ型の一貫性
- `UMPGroup`: RawRepresentable<UInt8>
- `UMPChannel`: RawRepresentable<UInt8>
- `SysEx7Status`: enum with rawValue

→ 型安全性が高い

---

## テスタビリティ

### ⭐⭐⭐⭐⭐ テストが非常に充実
- **総テスト数**: 37件の新規テスト（30 SysEx7 + 7 RPN/NRPN）
- **カバレッジ**: 正常系、異常系、エッジケース、ラウンドトリップ
- **隔離性**: 各テストは独立しており、順序依存性なし
- **再現性**: 決定的な入力で、ランダム性なし

### ✅ actorのテスト容易性
```swift
@Test("Assembler: Start + End")
func assemblerStartEnd() async {
    let assembler = UMPSysEx7Assembler()
    // ...
}
```
→ async/awaitで素直にテスト可能

---

## 総合評価

### スコア: ⭐⭐⭐⭐⭐ 5.0/5

**理由:**
1. **MIDI 2.0仕様への準拠性**: 極めて高い（numBytes処理、SysEx7 status、RPN/NRPN CC変換）
2. **テストカバレッジ**: 包括的（37件、564件全pass）
3. **エッジケースのハンドリング**: 堅牢（空、境界値、orphaned packets、overflow）
4. **スレッドセーフティ**: actor設計で完璧
5. **API設計**: 一貫性・直感性が高い
6. **コード品質**: クリーンで読みやすい

**軽微な改善余地（非クリティカル）:**
- RPN/NRPNの14-bit LSB対応（互換性考慮で要検討）
- バッファオーバーフロー時のロギング
- numBytes仕様違反時の警告

**結論:**
本実装は**プロダクション品質**であり、MIDI 2.0ライブラリの中核機能として十分な堅牢性を持つ。指摘事項はすべて「あればより良い」レベルであり、現状のまま本番投入可能。

---

## 推奨アクション

### 優先度: 高 (次回リリース前)
- なし（Critical/Warningはすべて非ブロッキング）

### 優先度: 中 (次回マイナーバージョン)
1. RPN/NRPN の CC 38 (LSB) 対応を設定可能にする
   - `UMPTranslatorConfig.rpnUseLSB: Bool` のような設定を追加
   - デフォルトは `false`（現行互換）

### 優先度: 低 (将来)
1. ログ追加（numBytes違反、buffer overflow）
2. `SysEx7AssemblerResult` enumで詳細なエラー情報を返す
3. `UMP.sysEx7.start/continue/end` ファクトリの追加
4. ドキュメントコメントの拡充

---

## まとめ

本実装は**高品質**であり、以下を達成している:

- ✅ MIDI 2.0 UMP仕様への完全準拠
- ✅ 堅牢なエラーハンドリング
- ✅ 優れたテストカバレッジ（37件の新規テスト）
- ✅ スレッドセーフな actor 設計
- ✅ 一貫したAPI設計
- ✅ パフォーマンス考慮

**現状のまま本番投入可能**。指摘事項は将来の品質向上のための提案であり、緊急性はない。

🎉 **素晴らしい実装です！**
