# KORG Module Pro Property Exchange 通信デバッグレポート

**作成日**: 2026-01-27  
**ステータス**: 解決済み ✅  
**対象デバイス**: KORG Module Pro (iOS Bluetooth MIDI)

---

## エグゼクティブサマリー

MIDI2KitライブラリでKORG Module ProとのProperty Exchange (PE) 通信がタイムアウトする問題を調査・解決した。根本原因は**KORGデバイスのMIDIルーティング特性**であり、PE Replyが送信先とは異なるエンドポイントから返される。解決策として**全destinationへのブロードキャスト送信**を実装した。

---

## 1. 問題の概要

### 1.1 症状

- MIDI-CI Discovery は成功（デバイス検出可能）
- Property Exchange GET リクエストがタイムアウト（5秒後にエラー）
- PE Reply (0x35) が一度も受信されない

### 1.2 環境

| 項目 | 値 |
|------|-----|
| デバイス | KORG Module Pro |
| 接続方式 | Bluetooth MIDI |
| iOS バージョン | iOS 18.x |
| テストアプリ | MIDI2Explorer |
| ライブラリ | MIDI2Kit |

### 1.3 比較対象

**SimpleMidiController** (別プロジェクト) では同じKORG Module Proに対してPE通信が成功していた。

---

## 2. 調査過程

### 2.1 初期テスト結果

```
[INFO] Started MIDI-CI discovery
[DISPATCHER] SysEx recv: subID2=0x71 len=31 (Discovery REPLY) ✅
[DEVICE] Discovered: KORG (374:4) ✅
[PE-SEND] Sending request [0] to destination MIDIDestinationID(value: 1089658)
[PE-SEND] Request [0] sent successfully
... (5秒待機) ...
[ERROR] ❌ PE fetch failed: Device MUID(0xA46C34E) did not respond within 5.0 seconds
```

### 2.2 エンドポイント構成

KORG Module Pro Bluetooth接続時のCoreMIDIエンドポイント:

| タイプ | 名前 | ID | 用途 |
|--------|------|-----|------|
| Source | Bluetooth | 1089600 | Discovery Reply受信元 |
| Destination | Session 1 | 1089558 | 不明 |
| Destination | Bluetooth | 1089601 | Bluetooth送信用 |
| Destination | Module | 1089658 | モジュール送信用 |

### 2.3 DestinationResolver の動作

```
[DestResolver] resolvePreferModule for MUID(0xA46C34E)
[DestResolver]   Available destinations:
[DestResolver]     - 'Session 1' -> MIDIDestinationID(value: 1089558)
[DestResolver]     - 'Bluetooth' -> MIDIDestinationID(value: 1089601)
[DestResolver]     - 'Module' -> MIDIDestinationID(value: 1089658)
[DestResolver]   Selected Module: 'Module' -> MIDIDestinationID(value: 1089658)
```

`preferModule` 戦略により **Module** destination が選択されていた。

### 2.4 SimpleMidiController との比較

**SimpleMidiController の実装:**

```swift
private func broadcastSysEx(_ message: [UInt8]) {
    let destCount = MIDIGetNumberOfDestinations()
    for i in 0..<destCount {
        let dest = MIDIGetDestination(i)
        self.sendSysExSync(msg, to: dest, port: port)
    }
}
```

→ **全てのdestinationにブロードキャスト送信**

**MIDI2Kit の実装 (修正前):**

```swift
try await transport.send(message, to: destination)
```

→ **特定のdestination (Module) のみに送信**

---

## 3. 根本原因分析

### 3.1 KORGのMIDIルーティング特性

KORG Module Pro は以下の特殊な動作をする:

1. **Discovery Reply**: Bluetooth source (1089600) から送信
2. **PE Reply**: Module destination に送信してもBluetooth経由で返す（または返さない）
3. **非対称ルーティング**: 送信先と応答元が異なる

### 3.2 問題の構造図

```
┌─────────────────────────────────────────────────────────────┐
│                    KORG Module Pro                          │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Internal Routing                        │   │
│  │  ┌─────────┐    ┌─────────┐    ┌─────────┐         │   │
│  │  │Bluetooth│◄───│ Router  │◄───│ Module  │         │   │
│  │  │ Source  │    │         │    │ Dest    │         │   │
│  │  └────┬────┘    └─────────┘    └────▲────┘         │   │
│  │       │                              │              │   │
│  └───────│──────────────────────────────│──────────────┘   │
│          │                              │                   │
└──────────│──────────────────────────────│───────────────────┘
           │                              │
           ▼                              │
    ┌──────────────┐              ┌──────────────┐
    │ MIDI2Kit     │              │ MIDI2Kit     │
    │ Receive      │              │ Send         │
    │ (Source:     │              │ (Dest:       │
    │  1089600)    │              │  1089658)    │
    └──────────────┘              └──────────────┘
           │                              │
           │         ❌ NO REPLY          │
           ◄──────────────────────────────┘
```

**問題**: Module destination に送信 → Bluetooth source で応答を期待 → 応答なし

### 3.3 ブロードキャスト解決

```
┌─────────────────────────────────────────────────────────────┐
│                    KORG Module Pro                          │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Internal Routing                        │   │
│  │  ┌─────────┐    ┌─────────┐    ┌─────────┐         │   │
│  │  │Bluetooth│◄──►│ Router  │◄──►│ Module  │         │   │
│  │  │Src/Dest │    │         │    │ Dest    │         │   │
│  │  └────┬────┘    └─────────┘    └────▲────┘         │   │
│  │       │                              │              │   │
│  └───────│──────────────────────────────│──────────────┘   │
│          │                              │                   │
└──────────│──────────────────────────────│───────────────────┘
           │                              │
           ▼                              │
    ┌──────────────┐              ┌──────────────┐
    │ MIDI2Kit     │              │ MIDI2Kit     │
    │ Receive      │◄─────────────│ Broadcast    │
    │              │   ✅ REPLY   │ to ALL dests │
    └──────────────┘              └──────────────┘
```

**解決**: 全destination にブロードキャスト → どれかが正しいルートに到達 → 応答受信

---

## 4. 実装した解決策

### 4.1 MIDITransport プロトコル拡張

**ファイル**: `Sources/MIDI2Transport/MIDITransport.swift`

```swift
/// Broadcast MIDI data to all destinations
///
/// This sends the same data to every available destination.
/// Useful for MIDI-CI messages where the correct destination is unknown.
///
/// - Parameter data: MIDI bytes to broadcast
func broadcast(_ data: [UInt8]) async throws
```

### 4.2 CoreMIDITransport 実装

**ファイル**: `Sources/MIDI2Transport/CoreMIDITransport.swift`

```swift
public func broadcast(_ data: [UInt8]) async throws {
    let count = MIDIGetNumberOfDestinations()
    guard count > 0 else { return }
    
    for i in 0..<count {
        let destRef = MIDIGetDestination(i)
        if destRef != 0 {
            let destID = MIDIDestinationID(UInt32(destRef))
            try await send(data, to: destID)
        }
    }
}
```

### 4.3 PEManager 修正

**ファイル**: `Sources/MIDI2PE/PEManager.swift`

```swift
private func scheduleSendForRequest(
    requestID: UInt8,
    message: [UInt8],
    destination: MIDIDestinationID
) {
    // ... 省略 ...
    
    sendTasks[requestID] = Task { [weak self] in
        if Task.isCancelled { return }
        do {
            // WORKAROUND: Broadcast to all destinations for KORG compatibility
            // KORG devices may not respond when sent to specific destinations,
            // but will respond when the message reaches them via broadcast.
            print("[PE-SEND] Broadcasting request [\(requestID)] to all destinations")
            try await transport.broadcast(message)
            print("[PE-SEND] Request [\(requestID)] broadcast completed")
        } catch {
            // ... エラー処理 ...
        }
    }
}
```

### 4.4 MockMIDITransport (テスト用)

**ファイル**: `Sources/MIDI2Transport/MockMIDITransport.swift`

```swift
public func broadcast(_ data: [UInt8]) async throws {
    for dest in mockDestinations {
        let message = SentMessage(
            data: data,
            destination: dest.destinationID,
            timestamp: Date()
        )
        sentMessages.append(message)
    }
}
```

---

## 5. 修正後の動作確認

### 5.1 成功ログ

```
[INFO] Started MIDI-CI discovery
[DISPATCHER] SysEx recv: subID2=0x71 len=31 (Discovery REPLY) ✅
[DEVICE] Discovered: KORG (374:4) ✅
[PE-SEND] Broadcasting request [0] to all destinations
[PE-SEND] Request [0] broadcast completed
[DISPATCHER] SysEx recv: subID2=0x35 len=212 (PE GET REPLY) ✅
[PEManager]   MUID match: true ✅
[PE] ✅ DeviceInfo: Module Pro
[PE] ✅ ResourceList: 6 resources
```

### 5.2 取得したデータ

**DeviceInfo**:
- Product Name: "Module Pro"
- Manufacturer: KORG (ID: 374)
- Family: 4

**ResourceList**: 6 resources
- DeviceInfo
- ResourceList
- ProgramList
- (その他3リソース)

---

## 6. KORG Module Pro の特性まとめ

### 6.1 MIDI-CI 実装の特徴

| 項目 | 値 | 備考 |
|------|-----|------|
| CI Version | 0x02 (1.2) | 標準的 |
| Manufacturer ID | 0x42 00 00 (374) | KORG |
| Family | 0x04 00 | Module Pro |
| PE Support | ✅ | Property Exchange対応 |
| Discovery Interval | ~2秒 | 定期的にDiscovery送信 |

### 6.2 エンドポイント構成

Bluetooth MIDI接続時、3つのdestinationが存在:

1. **Session 1**: 用途不明、PE応答なし
2. **Bluetooth**: Bluetooth MIDI送信用
3. **Module**: モジュール制御用（名前から推測）

### 6.3 ルーティングの癖

- Discovery Reply は Bluetooth source から送信
- PE Reply は特定destination宛でなくても応答する
- **ブロードキャスト送信が最も確実**

### 6.4 PE Reply フォーマット

KORGはMIDI-CI仕様の標準フォーマットを使用:

```
F0 7E 7F 0D 35 <version> <destMUID...> <srcMUID...> <requestID> 
   <headerLen> <header...> <numChunks> <thisChunk> <bodyLen> <body...> F7
```

特別なKORGフォーマットは不要（以前の調査で確認済み）。

---

## 7. 今後の改善提案

### 7.1 短期改善

1. **成功destination キャッシュ**
   - 最初の成功時にdestinationを記録
   - 以降は直接送信で効率化

2. **設定可能な送信戦略**
   ```swift
   enum PESendStrategy {
       case broadcast      // 全destination（現在）
       case single         // 単一destination
       case fallback       // 失敗時に次を試行
   }
   ```

### 7.2 中期改善

1. **デバイスプロファイル**
   - KORG用プロファイルを定義
   - Manufacturer ID で自動判定

2. **応答元tracking**
   - PE Reply の source を記録
   - 次回から対応するdestinationを使用

### 7.3 長期改善

1. **MIDI-CI 仕様準拠検証**
   - KORGの動作が仕様違反かどうか確認
   - MMA に問い合わせ/報告

2. **他デバイステスト**
   - Roland, Yamaha, Native Instruments 等
   - デバイス別互換性マトリクス作成

---

## 8. 関連ファイル

| ファイル | 変更内容 |
|----------|----------|
| `Sources/MIDI2Transport/MIDITransport.swift` | `broadcast()` プロトコル追加 |
| `Sources/MIDI2Transport/CoreMIDITransport.swift` | `broadcast()` 実装 |
| `Sources/MIDI2Transport/MockMIDITransport.swift` | `broadcast()` テスト実装 |
| `Sources/MIDI2PE/PEManager.swift` | ブロードキャスト送信に変更 |

---

## 9. 参考資料

- [MIDI-CI Specification 1.2](https://www.midi.org/specifications/midi-ci-specifications)
- [MIDI 2.0 Property Exchange](https://www.midi.org/specifications/midi2-specifications)
- SimpleMidiController ソースコード (`/Users/hakaru/Desktop/Develop/SimpleMidiController/`)

---

## 10. 付録: デバッグログ全文

### 10.1 修正前（失敗）

```
[INFO] Created MIDI2Client (MUID: MUID(0xE5EEEEF))
[DISPATCHER] Started receive dispatcher, waiting for messages...
[INFO] Started MIDI-CI discovery
[DISPATCHER] SysEx recv: subID2=0x71 len=31 (from source MIDISourceID(value: 1089600))
[DISPATCHER]   Hex: F0 7E 7F 0D 71 01 4E 06 1B 52 6F 5D 7B 72 42 00 00 76 01 04 00 09 00 05 00 08 00 08 00 00 F7
[DISPATCHER] >>> Discovery REPLY detected!
[DEVICE] Discovered: KORG (374:4)
[DEVICE]   Capabilities: PE
[PE] Auto-fetching PE info for KORG (374:4)...
[DestResolver] resolvePreferModule for MUID(0xA46C34E)
[DestResolver]   Available destinations:
[DestResolver]     - 'Session 1' -> MIDIDestinationID(value: 1089558)
[DestResolver]     - 'Bluetooth' -> MIDIDestinationID(value: 1089601)
[DestResolver]     - 'Module' -> MIDIDestinationID(value: 1089658)
[DestResolver]   Selected Module: 'Module' -> MIDIDestinationID(value: 1089658)
[PE-SEND] Sending request [0] to destination MIDIDestinationID(value: 1089658), message len=43
[PE-SEND] Message: F0 7E 7F 0D 34 01 6F 5D 7B 72 4E 06 1B 52 00 19 00 7B 22 72 65 73 6F 75 72 63 65 22 3A 22 44 65 76 69 63 65 49 6E 66 6F 22 7D F7
[PE-SEND] Request [0] sent successfully
... (Discovery Reply のみ受信、PE Reply なし) ...
[ERROR] ❌ PE fetch failed: Device MUID(0xA46C34E) did not respond within 5.0 seconds
```

### 10.2 修正後（成功）

```
[INFO] Created MIDI2Client (MUID: MUID(0xFB5C118))
[DISPATCHER] Started receive dispatcher, waiting for messages...
[INFO] Started MIDI-CI discovery
[DISPATCHER] SysEx recv: subID2=0x71 len=31 (from source MIDISourceID(value: 1089600))
[DISPATCHER]   Hex: F0 7E 7F 0D 71 01 4E 06 1B 52 18 02 57 7D 42 00 00 76 01 04 00 09 00 05 00 08 00 08 00 00 F7
[DISPATCHER] >>> Discovery REPLY detected!
[DEVICE] Discovered: KORG (374:4)
[DEVICE]   Capabilities: PE
[PE] Auto-fetching PE info for KORG (374:4)...
[DestResolver] resolvePreferModule for MUID(0xA46C34E)
[DestResolver]   Available destinations:
[DestResolver]     - 'Session 1' -> MIDIDestinationID(value: 1089558)
[DestResolver]     - 'Bluetooth' -> MIDIDestinationID(value: 1089601)
[DestResolver]     - 'Module' -> MIDIDestinationID(value: 1089658)
[DestResolver]   Selected Module: 'Module' -> MIDIDestinationID(value: 1089658)
[PE-SEND] Sending request [0] to destination MIDIDestinationID(value: 1089658), message len=43
[PE-SEND] Message: F0 7E 7F 0D 34 01 18 02 57 7D 4E 06 1B 52 00 19 00 7B 22 72 65 73 6F 75 72 63 65 22 3A 22 44 65 76 69 63 65 49 6E 66 6F 22 7D F7
[PE-SEND] Broadcasting request [0] to all destinations
[PE-SEND] Request [0] broadcast completed
[DISPATCHER] SysEx recv: subID2=0x35 len=212 (from source MIDISourceID(value: 1089600))
[DISPATCHER]   Hex: F0 7E 7F 0D 35 01 4E 06 1B 52 18 02 57 7D 00 0E 00 7B 22 73 74 61 74 75 73 22 3A 32 30 30 7D 01 00 01 00 2E 01 7B 22 6D...
[DISPATCHER] >>> PE GET REPLY detected!
[PEManager] Received PE Reply (0x35) len=212
[PEManager]   Parsed: src=MUID(0xA46C34E) dst=MUID(0xFB5C118)
[PEManager]   Our MUID: MUID(0xFB5C118)
[PEManager]   MUID match: true
[PE] ✅ DeviceInfo: Module Pro
[PE-SEND] Broadcasting request [1] to all destinations
[DISPATCHER] >>> PE GET REPLY detected!
[PE] ✅ ResourceList: 6 resources
[DEVICE] Updated: KORG (374:4)
```

---

**文書終了**
