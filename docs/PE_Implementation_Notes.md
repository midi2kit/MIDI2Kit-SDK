# MIDI2Kit Property Exchange 実装ノート

## PE メッセージフォーマット (MIDI-CI 1.2)

### PE Get Inquiry (0x34)

```
Offset  Size  Field
------  ----  -----
0       1     Universal SysEx ID (0x7E)
1       1     Device ID (0x7F = broadcast)
2       1     Sub-ID#1 (0x0D = MIDI-CI)
3       1     Sub-ID#2 (0x34 = PE Get Inquiry)
4       1     MIDI-CI Version
5       4     Source MUID (28-bit, LSB first)
9       4     Destination MUID (28-bit, LSB first)
13      1     Request ID (7-bit)
14      2     Header Size (14-bit, LSB first)
16      N     Header Data (JSON)
```

**注意**: numChunks/thisChunk/dataSize は含まない

### PE Get Reply (0x35)

```
Offset  Size  Field
------  ----  -----
0       1     Universal SysEx ID (0x7E)
1       1     Device ID (0x7F = broadcast)
2       1     Sub-ID#1 (0x0D = MIDI-CI)
3       1     Sub-ID#2 (0x35 = PE Get Reply)
4       1     MIDI-CI Version
5       4     Source MUID (28-bit, LSB first)
9       4     Destination MUID (28-bit, LSB first)
13      1     Request ID (7-bit)
14      2     Header Size (14-bit, LSB first)
16      N     Header Data (JSON)        ← Header Sizeの直後
16+N    2     Num Chunks (14-bit)
18+N    2     This Chunk (14-bit)
20+N    2     Data Size (14-bit)
22+N    M     Property Data (JSON)
```

**重要**: Header Data は Header Size の直後に配置される

## DeviceInfo JSON フォーマット

### 標準 MIDI-CI 形式

```json
{
  "manufacturerName": "KORG Inc.",
  "productName": "Module Pro",
  "familyName": "KORG Module",
  "softwareVersion": "5.0.10",
  "productInstanceId": "..."
}
```

### KORG 形式 (互換対応)

```json
{
  "manufacturerId": [66, 0, 0],
  "manufacturer": "KORG Inc.",
  "familyId": [118, 1],
  "family": "KORG Module",
  "modelId": [4, 0],
  "model": "Module Pro",
  "versionId": [9, 0, 5, 0],
  "version": "5.0.10"
}
```

### PEDeviceInfo 実装

```swift
public struct PEDeviceInfo: Sendable, Codable {
    enum CodingKeys: String, CodingKey {
        // Standard MIDI-CI keys
        case manufacturerName
        case productName
        case productInstanceID = "productInstanceId"
        case softwareVersion
        case familyName
        case modelName
        
        // KORG alternative keys
        case manufacturer
        case model
        case family
        case version
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Try standard first, fall back to KORG
        manufacturerName = try container.decodeIfPresent(String.self, forKey: .manufacturerName)
            ?? container.decodeIfPresent(String.self, forKey: .manufacturer)
        
        productName = try container.decodeIfPresent(String.self, forKey: .productName)
            ?? container.decodeIfPresent(String.self, forKey: .model)
        
        // ... etc
    }
}
```

## 14-bit エンコーディング

MIDI-CIでは2バイトフィールドは14-bitエンコーディング（各バイトの上位1ビットは0）:

```swift
// Encode
let lsb = UInt8(value & 0x7F)
let msb = UInt8((value >> 7) & 0x7F)

// Decode
let value = Int(lsb) | (Int(msb) << 7)
```

## 参考資料

- MIDI-CI 1.2 Specification (M2-105-UM)
- MIDI 2.0 Property Exchange Specification (M2-104-UM)
