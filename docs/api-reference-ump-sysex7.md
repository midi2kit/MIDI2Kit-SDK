# UMP SysEx7 / RPN/NRPN API リファレンス

MIDI2Kit v1.x

## 概要

このドキュメントでは、MIDI2Kit が提供する UMP SysEx7 (Data 64) 双方向変換機能および RPN/NRPN → MIDI 1.0 CC 近似変換機能について説明します。

### UMP SysEx7 (Data 64) とは

MIDI 2.0 では、System Exclusive (SysEx) メッセージを UMP フォーマットの **Data 64** パケットとして送信します。従来の MIDI 1.0 SysEx (F0...F7) と異なり、UMP SysEx7 は以下の特徴があります:

- **固定長パケット**: 各パケットは 2 × 32-bit ワード (64-bit)
- **最大 6 バイト/パケット**: ペイロードは 1 パケットあたり最大 6 バイト
- **マルチパケット対応**: 6 バイトを超える場合は Start → Continue... → End パケットに分割
- **ステータスコード**: Complete / Start / Continue / End の 4 種類

### RPN/NRPN → MIDI 1.0 CC 変換とは

MIDI 2.0 の RPN (Registered Controller) および NRPN (Assignable Controller) メッセージを、MIDI 1.0 互換の Control Change (CC) シーケンスに変換する機能です。

- **RPN**: CC 101/100/6 の 3 バイトシーケンスに変換
- **NRPN**: CC 99/98/6 の 3 バイトシーケンスに変換

---

## 型リファレンス

### SysEx7Status

**定義**: `Sources/MIDI2Core/UMPTypes.swift`

```swift
public enum SysEx7Status: UInt8, Sendable, CaseIterable {
    case complete = 0x0   // 完全なメッセージ (6 バイト以下)
    case start = 0x1      // マルチパケットの最初
    case `continue` = 0x2 // マルチパケットの継続
    case end = 0x3        // マルチパケットの最後
}
```

#### 使用場面

- **complete**: ペイロードが 6 バイト以下の SysEx メッセージ
- **start**: 7 バイト以上の SysEx の最初のパケット
- **continue**: 中間パケット (2 番目以降、最後以外)
- **end**: 最終パケット

---

### UMPSysEx7Assembler

**定義**: `Sources/MIDI2Core/UMP/UMPSysEx7Assembler.swift`

UMP Data 64 (SysEx7) のマルチパケットメッセージを再組み立てし、完全な MIDI 1.0 SysEx `[F0, data..., F7]` を生成する actor です。

#### プロパティ

```swift
public let maxBufferSize: Int
```

- **説明**: グループごとの最大バッファサイズ (デフォルト: 65536 バイト)
- **用途**: バッファオーバーフロー攻撃を防止

#### メソッド

##### `process(group:status:bytes:) async -> [UInt8]?`

```swift
public func process(group: UInt8, status: UInt8, bytes: [UInt8]) -> [UInt8]?
```

- **パラメータ**:
  - `group`: UMP グループ (0-15)
  - `status`: SysEx7 ステータス raw 値 (0=Complete, 1=Start, 2=Continue, 3=End)
  - `bytes`: パケットから取り出したデータバイト配列 (numBytes で既にトリミング済み)
- **戻り値**:
  - メッセージが完了した場合: `[F0, data..., F7]` の完全な MIDI 1.0 SysEx
  - 未完了/エラーの場合: `nil`
- **動作**:
  - **Complete**: 単一パケットメッセージ → 即座に `[F0, bytes..., F7]` を返す
  - **Start**: 新しいバッファを開始 → `nil` を返す
  - **Continue**: バッファに追加 → `nil` を返す
  - **End**: バッファに追加して完了 → `[F0, accumulated..., F7]` を返す

##### `reset() async`

```swift
public func reset()
```

- **説明**: 全グループのバッファをリセット

##### `reset(group:) async`

```swift
public func reset(group: UInt8)
```

- **説明**: 特定グループのバッファのみリセット

#### 使用例

```swift
let assembler = UMPSysEx7Assembler()

for packet in incomingPackets {
    if case .data64(let group, let status, let bytes) = UMPParser.parse(packet) {
        if let completeSysEx = await assembler.process(
            group: group,
            status: status,
            bytes: bytes
        ) {
            // completeSysEx = [0xF0, 0x7E, 0x7F, 0x09, 0x01, 0xF7]
            handleSysEx(completeSysEx)
        }
    }
}
```

#### 重要事項

- **Per-Group 独立バッファ**: 各 UMP グループ (0-15) ごとに独立したバッファを持つ
- **バッファオーバーフロー保護**: `maxBufferSize` を超えるとバッファを破棄
- **不正パケット処理**: Start なしの Continue/End は無視される

---

## メソッドリファレンス

### UMPTranslator

**定義**: `Sources/MIDI2Core/UMP/UMPTranslator.swift`

#### SysEx7 変換メソッド

##### `fromMIDI1SysEx(_:group:) -> [[UInt32]]`

MIDI 1.0 SysEx バイト列を UMP Data 64 パケット配列に変換します。

```swift
public static func fromMIDI1SysEx(
    _ bytes: [UInt8],
    group: UMPGroup = 0
) -> [[UInt32]]
```

- **パラメータ**:
  - `bytes`: MIDI 1.0 SysEx バイト列 (F0/F7 フレーミングは有無どちらでも可)
  - `group`: UMP グループ (デフォルト: 0)
- **戻り値**: UMP パケット配列 (各パケットは 2 ワード `[UInt32]`)
- **動作**:
  1. F0 プレフィックスと F7 サフィックスを自動除去
  2. ペイロードが 6 バイト以下 → 単一 Complete パケット
  3. ペイロードが 7 バイト以上 → Start, Continue..., End パケット列

**使用例**:

```swift
// 短いSysEx (単一パケット)
let shortSysEx: [UInt8] = [0xF0, 0x7E, 0x7F, 0x09, 0x01, 0xF7]
let packets = UMPTranslator.fromMIDI1SysEx(shortSysEx, group: 0)
// packets.count == 1
// packets[0] = [word0, word1] (Complete パケット)

// 長いSysEx (マルチパケット)
let longSysEx: [UInt8] = [0xF0, 0x7E] + Array(repeating: 0x00, count: 20) + [0xF7]
let multiPackets = UMPTranslator.fromMIDI1SysEx(longSysEx, group: 0)
// multiPackets.count == 4 (Start + Continue×2 + End)

// F0/F7なしでも動作
let payloadOnly: [UInt8] = [0x7E, 0x7F, 0x09, 0x01]
let packets2 = UMPTranslator.fromMIDI1SysEx(payloadOnly, group: 0)
```

---

##### `data64ToMIDI1SysEx(_:) -> [UInt8]?`

単一の UMP Data 64 Complete パケットを MIDI 1.0 SysEx に変換します (マルチパケットには非対応)。

```swift
public static func data64ToMIDI1SysEx(_ parsed: ParsedUMPMessage) -> [UInt8]?
```

- **パラメータ**:
  - `parsed`: `UMPParser.parse()` の結果
- **戻り値**:
  - Complete パケットの場合: `[F0, data..., F7]`
  - それ以外: `nil`
- **制限**: Complete ステータスのみ対応 (Start/Continue/End は `UMPSysEx7Assembler` を使用)

**使用例**:

```swift
let words = UMPBuilder.data64(
    group: 0,
    status: SysEx7Status.complete.rawValue,
    numBytes: 4,
    data: [0x7E, 0x7F, 0x09, 0x01]
)

let parsed = UMPParser.parse(words)
if let midi1 = UMPTranslator.data64ToMIDI1SysEx(parsed) {
    // midi1 = [0xF0, 0x7E, 0x7F, 0x09, 0x01, 0xF7]
    sendToLegacyDevice(midi1)
}
```

---

#### RPN/NRPN 変換 (toMIDI1 内で自動処理)

`UMPTranslator.toMIDI1()` メソッドは、MIDI 2.0 の RPN/NRPN メッセージを自動的に MIDI 1.0 CC シーケンスに変換します。

##### RPN → MIDI 1.0 CC 変換

**MIDI 2.0 入力**:
```swift
let rpn = UMPMIDI2ChannelVoice.registeredController(
    group: 0,
    channel: 0,
    bank: 0,    // RPN MSB
    index: 0,   // RPN LSB
    value: 0x40000000  // 32-bit 値
)
```

**MIDI 1.0 出力** (`toMIDI1()` の結果):
```swift
[
    0xB0, 101, 0,    // CC 101 (RPN MSB) = 0
    0xB0, 100, 0,    // CC 100 (RPN LSB) = 0
    0xB0, 6, 32      // CC 6 (Data Entry MSB) = 32 (downscaled from 0x40000000)
]
```

**使用例**:
```swift
let rpn = UMP.rpn(channel: 0, bank: 0, index: 0, value: 0x40000000)
if let midi1 = UMPTranslator.toMIDI1(rpn) {
    // midi1 = [0xB0, 101, 0, 0xB0, 100, 0, 0xB0, 6, 32]
    sendToLegacyMIDIDevice(midi1)
}
```

---

##### NRPN → MIDI 1.0 CC 変換

**MIDI 2.0 入力**:
```swift
let nrpn = UMPMIDI2ChannelVoice.assignableController(
    group: 0,
    channel: 0,
    bank: 1,    // NRPN MSB
    index: 2,   // NRPN LSB
    value: 0x60000000  // 32-bit 値
)
```

**MIDI 1.0 出力** (`toMIDI1()` の結果):
```swift
[
    0xB0, 99, 1,     // CC 99 (NRPN MSB) = 1
    0xB0, 98, 2,     // CC 98 (NRPN LSB) = 2
    0xB0, 6, 48      // CC 6 (Data Entry MSB) = 48 (downscaled from 0x60000000)
]
```

**使用例**:
```swift
let nrpn = UMP.nrpn(channel: 0, bank: 1, index: 2, value: 0x60000000)
if let midi1 = UMPTranslator.toMIDI1(nrpn) {
    // midi1 = [0xB0, 99, 1, 0xB0, 98, 2, 0xB0, 6, 48]
    sendToLegacyMIDIDevice(midi1)
}
```

---

### UMPBuilder

**定義**: `Sources/MIDI2Core/UMPBuilder.swift`

#### `data64(group:status:numBytes:data:) -> [UInt32]`

UMP Data 64 (SysEx7) パケットを構築します。

```swift
public static func data64(
    group: UInt8,
    status: UInt8,
    numBytes: UInt8,
    data: [UInt8]
) -> [UInt32]
```

- **パラメータ**:
  - `group`: UMP グループ (0-15)
  - `status`: SysEx7 ステータス (0=Complete, 1=Start, 2=Continue, 3=End)
  - `numBytes`: 有効データバイト数 (0-6)
  - `data`: データバイト配列 (最大 6 バイト; 超過分は無視、不足分は 0 埋め)
- **戻り値**: 2 ワード `[UInt32]`

**使用例**:

```swift
// Complete パケット (4 バイト)
let packet1 = UMPBuilder.data64(
    group: 0,
    status: SysEx7Status.complete.rawValue,
    numBytes: 4,
    data: [0x7E, 0x7F, 0x09, 0x01]
)

// Start パケット (6 バイトフル)
let packet2 = UMPBuilder.data64(
    group: 0,
    status: SysEx7Status.start.rawValue,
    numBytes: 6,
    data: [0x7E, 0x00, 0x01, 0x02, 0x03, 0x04]
)

// Continue パケット
let packet3 = UMPBuilder.data64(
    group: 0,
    status: SysEx7Status.continue.rawValue,
    numBytes: 6,
    data: [0x05, 0x06, 0x07, 0x08, 0x09, 0x0A]
)

// End パケット (2 バイト)
let packet4 = UMPBuilder.data64(
    group: 0,
    status: SysEx7Status.end.rawValue,
    numBytes: 2,
    data: [0x0B, 0x0C]
)
```

---

### UMP.sysEx7 ファクトリ

**定義**: `Sources/MIDI2Core/UMP/UMP.swift`

#### `fromMIDI1(group:bytes:) -> [[UInt32]]`

MIDI 1.0 SysEx を UMP Data 64 パケット配列に変換します (`UMPTranslator.fromMIDI1SysEx` のラッパー)。

```swift
public static func fromMIDI1(
    group: UMPGroup = 0,
    bytes: [UInt8]
) -> [[UInt32]]
```

**使用例**:

```swift
let sysEx: [UInt8] = [0xF0, 0x7E, 0x7F, 0x09, 0x01, 0xF7]
let packets = UMP.sysEx7.fromMIDI1(group: 0, bytes: sysEx)

// Transport経由で送信
for packet in packets {
    try await transport.send(packet)
}
```

---

#### `complete(group:payload:) -> [UInt32]?`

単一 Complete パケットを構築します (ペイロード ≤ 6 バイトの場合のみ)。

```swift
public static func complete(
    group: UMPGroup = 0,
    payload: [UInt8]
) -> [UInt32]?
```

- **パラメータ**:
  - `group`: UMP グループ (デフォルト: 0)
  - `payload`: SysEx データ (F0/F7 なし、最大 6 バイト)
- **戻り値**:
  - 成功: 2 ワード `[UInt32]`
  - ペイロードが 6 バイト超過: `nil`

**使用例**:

```swift
// 成功例
if let packet = UMP.sysEx7.complete(group: 0, payload: [0x7E, 0x7F, 0x09, 0x01]) {
    try await transport.send(packet)
}

// 失敗例 (7 バイト → nil)
let tooLong = UMP.sysEx7.complete(payload: Array(repeating: 0, count: 7))
// tooLong == nil
```

---

## 使用パターン

### パターン 1: 単一パケット変換

```swift
// MIDI 1.0 → UMP (単一パケット)
let sysEx: [UInt8] = [0xF0, 0x7E, 0x7F, 0x09, 0x01, 0xF7]
let packets = UMP.sysEx7.fromMIDI1(bytes: sysEx)

// UMP → MIDI 1.0
let parsed = UMPParser.parse(packets[0])
if let midi1 = UMPTranslator.data64ToMIDI1SysEx(parsed) {
    print(midi1)  // [0xF0, 0x7E, 0x7F, 0x09, 0x01, 0xF7]
}
```

---

### パターン 2: マルチパケット変換

```swift
// MIDI 1.0 → UMP (マルチパケット)
let longSysEx: [UInt8] = [0xF0, 0x7E] + Array(repeating: 0x00, count: 20) + [0xF7]
let packets = UMPTranslator.fromMIDI1SysEx(longSysEx, group: 0)

print(packets.count)  // 4 (Start + Continue×2 + End)

// UMP → MIDI 1.0 (Assembler 使用)
let assembler = UMPSysEx7Assembler()

for packet in packets {
    let parsed = UMPParser.parse(packet)
    if case .data64(let group, let status, let bytes) = parsed {
        if let completeSysEx = await assembler.process(
            group: group,
            status: status,
            bytes: bytes
        ) {
            print(completeSysEx)  // [0xF0, 0x7E, 0x00, ..., 0xF7]
        }
    }
}
```

---

### パターン 3: ラウンドトリップ (MIDI 1.0 → UMP → MIDI 1.0)

```swift
let originalSysEx: [UInt8] = [0xF0, 0x43, 0x12, 0x00, 0x51, 0x01, 0x00, 0x7F, 0xF7]

// 1. MIDI 1.0 → UMP
let packets = UMPTranslator.fromMIDI1SysEx(originalSysEx, group: 0)

// 2. UMP → MIDI 1.0
let assembler = UMPSysEx7Assembler()
var reconstructed: [UInt8]?

for packet in packets {
    let parsed = UMPParser.parse(packet)
    if case .data64(let group, let status, let bytes) = parsed {
        if let result = await assembler.process(
            group: group,
            status: status,
            bytes: bytes
        ) {
            reconstructed = result
        }
    }
}

// 3. 検証
if let reconstructed = reconstructed {
    print(reconstructed == originalSysEx)  // true
}
```

---

### パターン 4: 非同期ストリーム処理

```swift
actor SysExHandler {
    private let assembler = UMPSysEx7Assembler()

    func handleIncomingPacket(_ words: [UInt32]) async {
        let parsed = UMPParser.parse(words)

        guard case .data64(let group, let status, let bytes) = parsed else {
            return
        }

        if let completeSysEx = await assembler.process(
            group: group,
            status: status,
            bytes: bytes
        ) {
            await processSysEx(completeSysEx)
        }
    }

    private func processSysEx(_ data: [UInt8]) async {
        // ここで完全な SysEx を処理
        print("Received SysEx: \(data.count) bytes")
    }
}

let handler = SysExHandler()

// パケット受信時
for packet in incomingPackets {
    await handler.handleIncomingPacket(packet)
}
```

---

## 注意事項

### Data 64 と Data 128 の違い

| 特徴 | Data 64 (SysEx7) | Data 128 (SysEx8) |
|------|------------------|-------------------|
| パケットサイズ | 64-bit (2 ワード) | 128-bit (4 ワード) |
| ペイロード/パケット | 最大 6 バイト | 最大 14 バイト |
| データ範囲 | 0x00-0x7F (7-bit) | 0x00-0xFF (8-bit) |
| MIDI 1.0 互換 | ✅ 完全互換 | ❌ 変換必要 |

**選択基準**:
- **Data 64 (SysEx7)**: MIDI 1.0 デバイスとの相互運用が必要な場合
- **Data 128 (SysEx8)**: MIDI 2.0 専用で高速転送が必要な場合

---

### バッファオーバーフロー保護

`UMPSysEx7Assembler` は、悪意のある無限 Continue パケットからシステムを保護します:

```swift
let assembler = UMPSysEx7Assembler(maxBufferSize: 8192)  // 8KB制限

// 8KB を超える Continue パケットが来ると自動的にバッファ破棄
```

**推奨値**:
- **デフォルト** (65536 バイト): 一般的な用途
- **組み込みシステム** (4096-8192 バイト): メモリ制約がある場合
- **サーバー** (131072 バイト): 大量の同時接続を処理する場合

---

### Per-Group 独立バッファ

UMP グループ (0-15) ごとに独立したバッファを持つため、複数のデバイスから同時に SysEx を受信しても混在しません:

```swift
let assembler = UMPSysEx7Assembler()

// Group 0 のパケット
await assembler.process(group: 0, status: 1, bytes: [0x7E, 0x00, 0x01, 0x02, 0x03, 0x04])

// Group 1 のパケット (独立して処理)
await assembler.process(group: 1, status: 1, bytes: [0x43, 0x12, 0x00, 0x51, 0x01, 0x00])

// Group 0 の継続パケット
await assembler.process(group: 0, status: 3, bytes: [0x05, 0x06])
// → Group 0 のメッセージが完了
```

---

### RPN/NRPN 値のダウンスケール

MIDI 2.0 の 32-bit 値を MIDI 1.0 の 7-bit 値 (CC 6) に変換する際、上位 7 ビットのみが使用されます:

```swift
let rpn = UMP.rpn(channel: 0, bank: 0, index: 0, value: 0x40000000)
if let midi1 = UMPTranslator.toMIDI1(rpn) {
    let dataMSB = midi1[8]  // CC 6 の値
    // dataMSB == 0x40000000 >> 25 == 32
}
```

**精度損失**: 32-bit → 7-bit 変換により下位 25 ビットの情報が失われます。

---

## 関連リンク

- [MIDI 2.0 UMP Specification](https://www.midi.org/specifications)
- [CLAUDE.md - Project Documentation](../CLAUDE.md)
- [UMP Message Types Reference](../CLAUDE.md#ump-message-types)

---

**ドキュメントバージョン**: 1.0
**最終更新**: 2026-02-07
**API バージョン**: MIDI2Kit 1.x (564 tests passing)
