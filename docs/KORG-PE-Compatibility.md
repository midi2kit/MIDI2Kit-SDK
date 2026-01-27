# KORG Property Exchange (PE) 互換性ドキュメント

このドキュメントは、MIDI2KitでKORGデバイスとのProperty Exchange通信を実装する際に発見した問題点と解決策を記録したものです。

## 概要

KORG Module Pro (iOS) との MIDI-CI Property Exchange 通信において、標準的なMIDI-CI 1.2仕様とは異なる実装が複数発見されました。これらの違いにより、標準準拠のパーサーではKORGデバイスからの応答を正しく処理できませんでした。

**テスト環境:**
- デバイス: KORG Module Pro (iOS app)
- 接続方法: Bluetooth MIDI
- Manufacturer ID: 0x42 (66), Family ID: 0x0176 (374)

---

## 発見された問題

### 問題1: Discovery Reply のポートルーティング

**症状:** PE Inquiry を送信してもタイムアウトする

**原因:** KORGデバイスは複数のMIDIポートを公開し、Discovery ReplyとPE通信で異なるポートを使用する

**詳細:**
```
受信ポート (Discovery Reply元):
  - Bluetooth: 0x00C50040

送信先ポート:
  - Session 1: 0x00C50016
  - Bluetooth: 0x00C50041  
  - Module: 0x00C50052  ← PE通信はこちらに送る必要がある
```

**解決策:** 
宛先ポート解決時に「Module」という名前を含むポートを優先的に選択するロジックを実装:

```swift
// MIDIDestinationResolver.swift
private func findBestDestination(for sourceName: String, ...) -> MIDIEndpointRef? {
    // 1. "Module" ポートを最優先
    if let modulePort = destinations.first(where: { 
        $0.name.contains("Module") 
    }) {
        return modulePort.endpoint
    }
    // 2. フォールバック: 名前マッチング
    ...
}
```

---

### 問題2: CI Version の不一致

**症状:** PE Replyのパースが失敗する（numChunks/thisChunkが不正な値）

**原因:** KORGは `ciVersion=0x01` (CI 1.1) を報告するが、メッセージフォーマットは独自形式

**MIDI-CI 1.2 標準フォーマット:**
```
PE Reply Payload:
  [0]     requestID (1 byte)
  [1-2]   headerSize (14-bit)
  [3-4]   numChunks (14-bit)
  [5-6]   thisChunk (14-bit)
  [7-8]   dataSize (14-bit)
  [9...]  headerData (headerSize bytes)
  [...]   propertyData (dataSize bytes)
```

**KORG フォーマット:**
```
PE Reply Payload:
  [0]     requestID (1 byte)
  [1-2]   headerSize (14-bit)
  [3...]  headerData (headerSize bytes)  ← 直後にheaderData
  [...]   numChunks (14-bit)              ← headerDataの後にchunk fields
  [...]   thisChunk (14-bit)
  [...]   dataSize (14-bit)
  [...]   propertyData (dataSize bytes)
```

**解決策:**
複数のフォーマットを順番に試すフォールバック戦略を実装:

```swift
// CIMessageParser.swift
public static func parsePEReply(_ payload: [UInt8], ciVersion: UInt8 = 2) -> PEReplyPayload? {
    // 1. CI 1.2 標準フォーマットを試行
    if let result = parsePEReplyCI12(payload) {
        return result
    }
    
    // 2. CI 1.1 フォーマットを試行
    if let result = parsePEReplyCI11(payload) {
        return result
    }
    
    // 3. KORG独自フォーマットを試行
    return parsePEReplyKORG(payload)
}
```

---

### 問題3: Body内のChunk Fields

**症状:** JSONデコードエラー「Unable to convert data to a string」

**原因:** `parsePEReplyKORG()` で抽出した `propertyData` にまだchunk fieldsが含まれていた

**デバッグログ:**
```
raw=180B [01 00 01 00 2E 01 7B 22 6D 61 6E 75 66 61 63...]
         ↑numChunks ↑thisChunk ↑dataSize ↑JSON開始

decoded=157B [00 01 00 2E 01 7B A2 E1 EE 75...]  ← 不正なMcoded7デコード結果
```

**分析:**
- `01 00` = numChunks = 1
- `01 00` = thisChunk = 1  
- `2E 01` = dataSize = 0x2E | (0x01 << 7) = 46 + 128 = 174
- `7B 22 6D 61 6E...` = `{"man...` = 実際のJSONデータ

**解決策:**
`parsePEReplyKORG()` で headerData の後に chunk fields を検出・スキップ:

```swift
private static func parsePEReplyKORG(_ payload: [UInt8]) -> PEReplyPayload? {
    let requestID = payload[0] & 0x7F
    let headerSize = Int(payload[1]) | (Int(payload[2]) << 7)
    
    let headerStart = 3
    let headerEnd = headerStart + headerSize
    let headerData = Data(payload[headerStart..<headerEnd])
    
    // headerDataの後にchunk fieldsがあるか確認
    let chunkFieldsStart = headerEnd
    if chunkFieldsStart + 6 <= payload.count {
        let numChunks = Int(payload[chunkFieldsStart]) | (Int(payload[chunkFieldsStart + 1]) << 7)
        let thisChunk = Int(payload[chunkFieldsStart + 2]) | (Int(payload[chunkFieldsStart + 3]) << 7)
        let dataSize = Int(payload[chunkFieldsStart + 4]) | (Int(payload[chunkFieldsStart + 5]) << 7)
        
        // chunk fieldsが妥当な場合、dataSizeに基づいてpropertyDataを抽出
        if numChunks >= 1 && thisChunk >= 1 && thisChunk <= numChunks {
            let dataStart = chunkFieldsStart + 6
            let dataEnd = dataStart + dataSize
            if dataEnd <= payload.count {
                let propertyData = Data(payload[dataStart..<dataEnd])
                return PEReplyPayload(...)
            }
        }
    }
    
    // フォールバック: chunk fieldsなしとして処理
    ...
}
```

---

## パケットフォーマット比較

### PE Get Reply (0x35) の完全な構造

**標準 MIDI-CI 1.2:**
```
F0 7E 7F 0D 35 [ciVer] [srcMUID:4] [dstMUID:4] 
   [requestID] [headerSize:2] [numChunks:2] [thisChunk:2] [dataSize:2]
   [headerData...] [propertyData...] F7
```

**KORG 実装:**
```
F0 7E 7F 0D 35 01 [srcMUID:4] [dstMUID:4]
   [requestID] [headerSize:2] [headerData...]
   [numChunks:2] [thisChunk:2] [dataSize:2] [propertyData...] F7
```

### 実際のパケット例

**KORG DeviceInfo Response:**
```
F0 7E 7F 0D 35 01 3B 21 28 72 3C 63 35 67 
   02                          // requestID
   0E 00                       // headerSize = 14
   7B 22 73 74 61 74 75 73 22 3A 32 30 30 7D  // {"status":200}
   01 00                       // numChunks = 1
   01 00                       // thisChunk = 1
   2E 01                       // dataSize = 174
   7B 22 6D 61 6E 75 66 61 63 74 75 72 65 72 49 64 22...  // JSON body
F7
```

---

## 今後の課題

### ResourceList の schema 型不一致

**症状:** ResourceList のデコードで型エラー
```
typeMismatch(Swift.String, ... "Expected to decode String but found a dictionary instead.")
```

**原因:** MIDI-CI仕様では `schema` は文字列（JSON Schemaへの参照URL）だが、KORGは埋め込みオブジェクトとして返す

**標準:**
```json
{
  "resource": "DeviceInfo",
  "schema": "urn:midi2:pe:schema:DeviceInfo"
}
```

**KORG:**
```json
{
  "resource": "X-CustomResource",
  "schema": {
    "type": "object",
    "properties": { ... }
  }
}
```

**対応方針:** `schema` フィールドを `String` または `[String: Any]` のどちらでも受け入れる柔軟なデコーダーを実装

---

## 教訓と推奨事項

1. **複数フォーマットのフォールバック:** MIDI-CI実装はデバイスによって微妙に異なるため、複数のパース戦略を用意する

2. **詳細なログ出力:** 通信問題のデバッグには生のバイト列をログに出力することが不可欠

3. **ポートルーティングの考慮:** Bluetooth MIDI デバイスは複数のポートを持つことがあり、機能ごとに異なるポートを使用する場合がある

4. **仕様準拠の仮定を避ける:** 実デバイスは仕様書通りに実装されているとは限らない。実機テストが必須

5. **ciVersion を信頼しない:** デバイスが報告するciVersionと実際のメッセージフォーマットが一致しない場合がある

---

## 関連ファイル

- `Sources/MIDI2CI/CIMessageParser.swift` - PEReplyパーサー
- `Sources/MIDI2PE/PEManager.swift` - PE通信管理
- `Sources/MIDI2Explorer/MIDIDestinationResolver.swift` - ポート解決ロジック

---

*最終更新: 2026-01-27*
