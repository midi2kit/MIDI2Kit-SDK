# MIDI2Kit Profile Configuration 設計ドキュメント

**作成日:** 2026年3月8日
**バージョン:** Draft 1.0
**対象仕様:** MIDI-CI v1.2 (M2-101-UM), Common Rules for MIDI-CI Profiles v1.1 (M2-102-U)

---

## 目次

1. [概要](#1-概要)
2. [MIDI-CI Profile Configuration 仕様サマリー](#2-midi-ci-profile-configuration-仕様サマリー)
3. [モジュール配置の判断](#3-モジュール配置の判断)
4. [メッセージ型定義](#4-メッセージ型定義)
5. [主要な型の設計](#5-主要な型の設計)
6. [High-Level API 設計](#6-high-level-api-設計)
7. [CIManager との統合](#7-cimanager-との統合)
8. [テスト戦略](#8-テスト戦略)
9. [実装フェーズ](#9-実装フェーズ)

---

## 1. 概要

MIDI-CI Profile Configuration は、MIDI デバイスの動作を「プロファイル」単位で動的に切り替える仕組みである。例えば、MIDI コントローラーが接続先シンセサイザーに「Piano Profile」を有効化するよう要求すると、シンセはベロシティ応答やペダル動作をピアノに最適化した状態に切り替わる。

MIDI2Kit は既に Discovery と Property Exchange をサポートしており、Profile Configuration はこれらと同じ MIDI-CI SysEx メッセージ基盤の上に構築される。

### 設計目標

- MIDI-CI v1.2 仕様準拠の Profile Configuration メッセージ送受信
- 既存の actor ベース・Swift 6 Strict Concurrency アーキテクチャとの整合性
- Initiator（プロファイル照会・制御側）と Responder（プロファイル提供側）の両方をサポート
- Apple CoreMIDI の `MIDICIProfile` / `MIDICIProfileState` との相互運用性

---

## 2. MIDI-CI Profile Configuration 仕様サマリー

### 2.1 Profile ID 構造

Profile ID は 5 バイトで構成される。

```
Byte 1: Profile ID Bank (0x7E = Standard Defined, その他 = Manufacturer Specific)
Byte 2: Profile Number / Manufacturer ID byte 1
Byte 3: Profile Number / Manufacturer ID byte 2
Byte 4: Profile-specific byte
Byte 5: Profile Level (実装レベルを示す固定値セット)
```

**Standard Defined Profile** (Byte 1 = 0x7E):
- MMA/AMEI が策定した共通プロファイル
- 例: Default CC Mapping, GM Function Block, Piano Profile 等

**Manufacturer Specific Profile** (Byte 1 != 0x7E):
- Byte 1-3 がメーカー ID（3バイト Manufacturer ID と同じ体系）
- Byte 4-5 はメーカーが自由に定義

### 2.2 アドレスモデル

Profile はデバイス内の異なるスコープに適用される:

| Address 値 | スコープ | 説明 |
|-----------|---------|------|
| 0x00-0x0F | Channel | 個別 MIDI チャンネル (0-15) |
| 0x7E | Group | MIDI 2.0 Group 全体 (16チャンネル) |
| 0x7F | Function Block | Function Block 全体 (1つ以上の Group) |

### 2.3 メッセージフロー

#### Profile Inquiry フロー

```
Initiator                          Responder
    |                                  |
    |--- Profile Inquiry (0x20) ------>|
    |                                  |
    |<-- Reply to Profile Inquiry -----|
    |        (0x21)                    |
    |   [enabled profiles list]        |
    |   [disabled profiles list]       |
```

#### Set Profile On/Off フロー

```
Initiator                          Responder
    |                                  |
    |--- Set Profile On (0x22) ------->|
    |                                  |
    |<-- Profile Enabled Report -------|
    |        (0x24)                    |
    |   (broadcast to all Initiators)  |
```

```
Initiator                          Responder
    |                                  |
    |--- Set Profile Off (0x23) ------>|
    |                                  |
    |<-- Profile Disabled Report ------|
    |        (0x25)                    |
```

#### Profile Details Inquiry フロー

```
Initiator                          Responder
    |                                  |
    |--- Profile Details Inquiry ----->|
    |        (0x28)                    |
    |   [target byte 0-127]           |
    |                                  |
    |<-- Reply to Profile Details -----|
    |        (0x29)                    |
    |   [profile-specific data]        |
```

#### 通知メッセージ（Responder → Initiator）

| メッセージ | 方向 | 説明 |
|-----------|------|------|
| Profile Added Report (0x26) | Responder → Broadcast | 新プロファイルが利用可能になった |
| Profile Removed Report (0x27) | Responder → Broadcast | プロファイルが利用不可になった |
| Profile Specific Data (0x2F) | 双方向 | プロファイル固有のデータ転送 |

### 2.4 採択済みプロファイル一覧

| 仕様書番号 | プロファイル名 | 概要 |
|-----------|-------------|------|
| M2-113-UM | Default Control Change Mapping | CC のデフォルトマッピング (Volume, Pan, Mod Wheel 等) |
| M2-118-UM | GM Function Block Profile | General MIDI 2 を Function Block 単位で有効化 |
| M2-119-UM | GM Single Channel Profile | General MIDI 2 を単一チャンネルで有効化 |
| M2-120-UM | MPE Profile | MIDI Polyphonic Expression の CI 設定 |
| M2-121-UM | Drawbar Organ Profile | ドローバーオルガンの制御マッピング |
| M2-123-UM | Orchestral Articulation Profile | オーケストラ音源のアーティキュレーション選択 |

（Piano Profile は仕様策定中。Roland A-88MKII + Synthogy Ivory でプレビュー実装済み）

### 2.5 Apple CoreMIDI の Profile 関連 API

| クラス | 役割 |
|-------|------|
| `MIDICIProfile` | 5バイト Profile ID を保持。`profileID` プロパティ |
| `MIDICIProfileState` | チャンネル/ポート上の enabled/disabled profiles を管理 |
| `MIDICISession.enableProfile(_:onChannel:)` | プロファイルの有効化リクエスト |
| `MIDICISession.disableProfile(_:onChannel:)` | プロファイルの無効化リクエスト |
| `MIDICISession.profileChangedCallback` | プロファイル状態変更の通知 |

MIDI2Kit は CoreMIDI の `MIDICISession` を直接利用せず、独自の SysEx ベースの実装を行うが、`MIDICIProfile` との型変換は提供する。

---

## 3. モジュール配置の判断

### 結論: 新モジュール `MIDI2Profile` を作成

### 理由

1. **既存パターンとの一貫性**: MIDI2PE (Property Exchange) が MIDI2CI とは別モジュールとして存在するのと同様、Profile Configuration も独立モジュールとすべき。PE と Profile は MIDI-CI の上位機能であり、CI の Discovery 基盤とは関心が異なる。

2. **依存関係の最小化**: Profile Configuration を必要としないユーザーが MIDI2CI だけを使える。バイナリサイズの最適化に寄与。

3. **MIDI2CI の責務超過防止**: MIDI2CI は既に Discovery メッセージのパース/ビルド、デバイス管理を担っている。Profile の状態管理やビルトインプロファイルまで含めると肥大化する。

4. **テスト分離**: Profile 固有のテストを独立して実行できる。

### モジュール依存関係

```
MIDI2Core (Foundation - no dependencies)
    ↑
    ├─ MIDI2Transport (CoreMIDI abstraction)
    ├─ MIDI2CI (Capability Inquiry / Discovery)
    ├─ MIDI2PE (Property Exchange)
    ├─ MIDI2Profile (Profile Configuration)  ← NEW
    └─ MIDI2Kit (High-Level API)
```

`MIDI2Profile` は `MIDI2Core` に依存し、`MIDI2CI` とは peer 関係。High-Level API (`MIDI2Kit`) が `MIDI2CI` + `MIDI2Profile` を統合する。

---

## 4. メッセージ型定義

### 4.1 Sub-ID#2 定数

```swift
// MIDI2Profile/ProfileMessageSubtype.swift
public enum ProfileMessageSubtype: UInt8, Sendable {
    case profileInquiry          = 0x20
    case replyToProfileInquiry   = 0x21
    case setProfileOn            = 0x22
    case setProfileOff           = 0x23
    case profileEnabledReport    = 0x24
    case profileDisabledReport   = 0x25
    case profileAddedReport      = 0x26
    case profileRemovedReport    = 0x27
    case profileDetailsInquiry   = 0x28
    case replyToProfileDetails   = 0x29
    case profileSpecificData     = 0x2F
}
```

### 4.2 メッセージ型一覧

| Sub-ID#2 | メッセージ型 | 方向 | ペイロード |
|----------|------------|------|----------|
| 0x20 | `ProfileInquiry` | Initiator → Responder | (なし) |
| 0x21 | `ProfileInquiryReply` | Responder → Initiator | enabled profiles, disabled profiles |
| 0x22 | `SetProfileOn` | Initiator → Responder | profile ID, number of channels |
| 0x23 | `SetProfileOff` | Initiator → Responder | profile ID |
| 0x24 | `ProfileEnabledReport` | Responder → Broadcast | profile ID, number of channels |
| 0x25 | `ProfileDisabledReport` | Responder → Broadcast | profile ID, number of channels |
| 0x26 | `ProfileAddedReport` | Responder → Broadcast | profile ID |
| 0x27 | `ProfileRemovedReport` | Responder → Broadcast | profile ID |
| 0x28 | `ProfileDetailsInquiry` | Initiator → Responder | profile ID, target byte |
| 0x29 | `ProfileDetailsReply` | Responder → Initiator | profile ID, target byte, data |
| 0x2F | `ProfileSpecificData` | 双方向 | profile ID, data |

### 4.3 メッセージ構造体

```swift
// 全メッセージに共通のヘッダー情報は CIMessageHeader (既存) を再利用
// 各メッセージ型は Sendable な struct として定義

public struct ProfileInquiry: Sendable, Equatable {
    public let source: MUID
    public let destination: MUID
}

public struct ProfileInquiryReply: Sendable, Equatable {
    public let source: MUID
    public let destination: MUID
    public let enabledProfiles: [ProfileID]
    public let disabledProfiles: [ProfileID]
}

public struct SetProfileOn: Sendable, Equatable {
    public let source: MUID
    public let destination: MUID
    public let profile: ProfileID
    public let numberOfChannels: UInt16  // v1.2: multi-channel profile support
}

public struct SetProfileOff: Sendable, Equatable {
    public let source: MUID
    public let destination: MUID
    public let profile: ProfileID
}

public struct ProfileEnabledReport: Sendable, Equatable {
    public let source: MUID
    public let destination: MUID
    public let profile: ProfileID
    public let numberOfChannels: UInt16
}

public struct ProfileDisabledReport: Sendable, Equatable {
    public let source: MUID
    public let destination: MUID
    public let profile: ProfileID
    public let numberOfChannels: UInt16
}

public struct ProfileAddedReport: Sendable, Equatable {
    public let source: MUID
    public let destination: MUID
    public let profile: ProfileID
}

public struct ProfileRemovedReport: Sendable, Equatable {
    public let source: MUID
    public let destination: MUID
    public let profile: ProfileID
}

public struct ProfileDetailsInquiry: Sendable, Equatable {
    public let source: MUID
    public let destination: MUID
    public let profile: ProfileID
    public let target: UInt8  // 0-127: profile-defined inquiry target
}

public struct ProfileDetailsReply: Sendable, Equatable {
    public let source: MUID
    public let destination: MUID
    public let profile: ProfileID
    public let target: UInt8
    public let data: Data
}

public struct ProfileSpecificData: Sendable, Equatable {
    public let source: MUID
    public let destination: MUID
    public let profile: ProfileID
    public let data: Data
}
```

---

## 5. 主要な型の設計

### 5.1 ProfileID

```swift
// MIDI2Profile/ProfileID.swift

/// MIDI-CI Profile Identifier (5 bytes)
///
/// Standard Defined Profile:   [0x7E, number1, number2, number3, level]
/// Manufacturer Specific:      [mfr1, mfr2, mfr3, info, level]
public struct ProfileID: Sendable, Hashable, Codable {
    public let byte1: UInt8  // Bank: 0x7E = Standard Defined
    public let byte2: UInt8
    public let byte3: UInt8
    public let byte4: UInt8
    public let byte5: UInt8  // Profile Level

    public init(_ byte1: UInt8, _ byte2: UInt8, _ byte3: UInt8, _ byte4: UInt8, _ byte5: UInt8) {
        self.byte1 = byte1
        self.byte2 = byte2
        self.byte3 = byte3
        self.byte4 = byte4
        self.byte5 = byte5
    }

    public init(bytes: [UInt8]) {
        precondition(bytes.count == 5)
        self.byte1 = bytes[0]
        self.byte2 = bytes[1]
        self.byte3 = bytes[2]
        self.byte4 = bytes[3]
        self.byte5 = bytes[4]
    }

    /// Standard Defined Profile かどうか
    public var isStandardDefined: Bool { byte1 == 0x7E }

    /// 5バイト配列として返す
    public var bytes: [UInt8] { [byte1, byte2, byte3, byte4, byte5] }
}
```

### 5.2 ProfileAddress

```swift
// MIDI2Profile/ProfileAddress.swift

/// Profile が適用されるスコープ
public enum ProfileAddress: Sendable, Hashable {
    case channel(UInt8)      // 0x00-0x0F: individual channel
    case group               // 0x7E: entire group
    case functionBlock       // 0x7F: whole function block

    public var rawValue: UInt8 {
        switch self {
        case .channel(let ch): return ch
        case .group: return 0x7E
        case .functionBlock: return 0x7F
        }
    }

    public init?(rawValue: UInt8) {
        switch rawValue {
        case 0x00...0x0F: self = .channel(rawValue)
        case 0x7E: self = .group
        case 0x7F: self = .functionBlock
        default: return nil
        }
    }
}
```

### 5.3 Built-in Profile ID 定数

```swift
// MIDI2Profile/StandardProfiles.swift

extension ProfileID {
    /// Standard Defined Profile の名前空間
    public enum Standard {
        /// Default Control Change Mapping Profile (M2-113-UM)
        public static let defaultCCMapping = ProfileID(0x7E, 0x01, 0x00, 0x00, 0x00)

        /// General MIDI 2 Function Block Profile (M2-118-UM)
        public static let gmFunctionBlock = ProfileID(0x7E, 0x02, 0x00, 0x00, 0x00)

        /// General MIDI 2 Single Channel Profile (M2-119-UM)
        public static let gmSingleChannel = ProfileID(0x7E, 0x03, 0x00, 0x00, 0x00)

        /// MPE Profile (M2-120-UM)
        public static let mpe = ProfileID(0x7E, 0x04, 0x00, 0x00, 0x00)

        /// Drawbar Organ Profile (M2-121-UM)
        public static let drawbarOrgan = ProfileID(0x7E, 0x05, 0x00, 0x00, 0x00)

        /// Orchestral Articulation Profile (M2-123-UM)
        public static let orchestralArticulation = ProfileID(0x7E, 0x06, 0x00, 0x00, 0x00)
    }

    /// Manufacturer Specific Profile を作成
    public static func manufacturer(_ id1: UInt8, _ id2: UInt8, _ id3: UInt8, info: UInt8, level: UInt8) -> ProfileID {
        ProfileID(id1, id2, id3, info, level)
    }
}
```

**注意**: Standard Profile の byte2-byte4 の正確な値は MMA 仕様書の正式公開時に確定する。上記は仮の値であり、正式な仕様書番号に基づいて修正が必要。

### 5.4 ProfileMessageBuilder / ProfileMessageParser

既存の `CIMessageParser` / PE メッセージビルダーのパターンに準拠。

```swift
// MIDI2Profile/ProfileMessageBuilder.swift

public enum ProfileMessageBuilder: Sendable {

    /// Profile Inquiry メッセージを構築
    public static func profileInquiry(
        source: MUID,
        destination: MUID
    ) -> [UInt8]

    /// Reply to Profile Inquiry メッセージを構築
    public static func profileInquiryReply(
        source: MUID,
        destination: MUID,
        enabledProfiles: [ProfileID],
        disabledProfiles: [ProfileID]
    ) -> [UInt8]

    /// Set Profile On メッセージを構築
    public static func setProfileOn(
        source: MUID,
        destination: MUID,
        profile: ProfileID,
        numberOfChannels: UInt16
    ) -> [UInt8]

    /// Set Profile Off メッセージを構築
    public static func setProfileOff(
        source: MUID,
        destination: MUID,
        profile: ProfileID
    ) -> [UInt8]

    /// Profile Enabled Report を構築
    public static func profileEnabledReport(
        source: MUID,
        destination: MUID,
        profile: ProfileID,
        numberOfChannels: UInt16
    ) -> [UInt8]

    /// Profile Disabled Report を構築
    public static func profileDisabledReport(
        source: MUID,
        destination: MUID,
        profile: ProfileID,
        numberOfChannels: UInt16
    ) -> [UInt8]

    /// Profile Added Report を構築
    public static func profileAddedReport(
        source: MUID,
        destination: MUID,
        profile: ProfileID
    ) -> [UInt8]

    /// Profile Removed Report を構築
    public static func profileRemovedReport(
        source: MUID,
        destination: MUID,
        profile: ProfileID
    ) -> [UInt8]

    /// Profile Details Inquiry を構築
    public static func profileDetailsInquiry(
        source: MUID,
        destination: MUID,
        profile: ProfileID,
        target: UInt8
    ) -> [UInt8]

    /// Reply to Profile Details を構築
    public static func profileDetailsReply(
        source: MUID,
        destination: MUID,
        profile: ProfileID,
        target: UInt8,
        data: Data
    ) -> [UInt8]

    /// Profile Specific Data を構築
    public static func profileSpecificData(
        source: MUID,
        destination: MUID,
        profile: ProfileID,
        data: Data
    ) -> [UInt8]
}
```

```swift
// MIDI2Profile/ProfileMessageParser.swift

public enum ProfileMessageParser: Sendable {

    /// SysEx バイト列を Profile メッセージとしてパースする
    /// Sub-ID#2 が Profile Configuration 範囲外の場合は nil を返す
    public static func parse(_ bytes: [UInt8]) -> ProfileMessage?
}

/// パース結果の enum
public enum ProfileMessage: Sendable, Equatable {
    case profileInquiry(ProfileInquiry)
    case profileInquiryReply(ProfileInquiryReply)
    case setProfileOn(SetProfileOn)
    case setProfileOff(SetProfileOff)
    case profileEnabledReport(ProfileEnabledReport)
    case profileDisabledReport(ProfileDisabledReport)
    case profileAddedReport(ProfileAddedReport)
    case profileRemovedReport(ProfileRemovedReport)
    case profileDetailsInquiry(ProfileDetailsInquiry)
    case profileDetailsReply(ProfileDetailsReply)
    case profileSpecificData(ProfileSpecificData)
}
```

### 5.5 ProfileManager (actor)

既存の `PEManager` パターンに準拠した actor 設計。

```swift
// MIDI2Profile/ProfileManager.swift

/// Profile Configuration のメッセージ送受信と状態管理を担当
public actor ProfileManager {

    // MARK: - Types

    /// デバイスのプロファイル状態
    public struct DeviceProfileState: Sendable {
        public let muid: MUID
        public let enabledProfiles: [ProfileID]
        public let disabledProfiles: [ProfileID]
        public let address: ProfileAddress
    }

    /// ProfileManager からのイベント
    public enum Event: Sendable {
        case profileInquiryReply(DeviceProfileState)
        case profileEnabled(muid: MUID, profile: ProfileID, channels: UInt16)
        case profileDisabled(muid: MUID, profile: ProfileID, channels: UInt16)
        case profileAdded(muid: MUID, profile: ProfileID)
        case profileRemoved(muid: MUID, profile: ProfileID)
        case profileDetailsReply(muid: MUID, profile: ProfileID, target: UInt8, data: Data)
        case profileSpecificData(muid: MUID, profile: ProfileID, data: Data)
    }

    // MARK: - Configuration

    public let muid: MUID
    public let timeout: Duration

    // MARK: - State

    /// デバイスごとの最新プロファイル状態キャッシュ
    private var profileStates: [MUID: DeviceProfileState] = [:]

    // MARK: - Initialization

    public init(
        muid: MUID,
        transport: MIDITransport,
        timeout: Duration = .seconds(5)
    )

    // MARK: - Initiator API

    /// デバイスのプロファイル一覧を照会
    public func inquireProfiles(from muid: MUID) async throws -> DeviceProfileState

    /// プロファイルを有効化
    public func enableProfile(
        _ profile: ProfileID,
        on muid: MUID,
        numberOfChannels: UInt16 = 1
    ) async throws

    /// プロファイルを無効化
    public func disableProfile(
        _ profile: ProfileID,
        on muid: MUID
    ) async throws

    /// プロファイルの詳細情報を照会
    public func inquireProfileDetails(
        _ profile: ProfileID,
        from muid: MUID,
        target: UInt8
    ) async throws -> Data

    /// プロファイル固有データを送信
    public func sendProfileSpecificData(
        _ profile: ProfileID,
        to muid: MUID,
        data: Data
    ) async throws

    // MARK: - Event Stream

    /// イベントストリームを生成
    public func makeEventStream() -> AsyncStream<Event>

    // MARK: - Internal

    /// 受信した SysEx メッセージを処理
    func handleIncomingMessage(_ bytes: [UInt8])

    /// キャッシュされたプロファイル状態を取得
    public func cachedProfileState(for muid: MUID) -> DeviceProfileState?
}
```

### 5.6 ProfileResponder

Responder 側（自デバイスのプロファイルを提供する側）の設計。

```swift
// MIDI2Profile/ProfileResponder.swift

/// Profile Configuration の Responder 側ハンドラ
public actor ProfileResponder {

    /// プロファイルの有効化/無効化を処理するデリゲート
    public protocol Delegate: Sendable {
        /// Set Profile On リクエストを受信。true を返すと Enabled Report を送信
        func profileResponder(
            _ responder: ProfileResponder,
            shouldEnable profile: ProfileID,
            from initiator: MUID,
            numberOfChannels: UInt16
        ) async -> Bool

        /// Set Profile Off リクエストを受信。true を返すと Disabled Report を送信
        func profileResponder(
            _ responder: ProfileResponder,
            shouldDisable profile: ProfileID,
            from initiator: MUID
        ) async -> Bool

        /// Profile Details Inquiry を受信
        func profileResponder(
            _ responder: ProfileResponder,
            detailsFor profile: ProfileID,
            target: UInt8,
            from initiator: MUID
        ) async -> Data?
    }

    /// 登録済みプロファイルの状態
    public struct RegisteredProfile: Sendable {
        public let id: ProfileID
        public var isEnabled: Bool
        public var address: ProfileAddress
    }

    // MARK: - Initialization

    public init(
        muid: MUID,
        transport: MIDITransport,
        delegate: (any Delegate)? = nil
    )

    // MARK: - Profile Registration

    /// プロファイルを登録（初期状態: disabled）
    public func registerProfile(_ profile: ProfileID, address: ProfileAddress = .functionBlock)

    /// プロファイルの登録解除（Profile Removed Report を送信）
    public func unregisterProfile(_ profile: ProfileID) async

    /// プロファイルの有効/無効を変更（Report を送信）
    public func setProfileEnabled(_ profile: ProfileID, enabled: Bool) async

    /// 登録済みプロファイル一覧
    public func registeredProfiles() -> [RegisteredProfile]
}
```

---

## 6. High-Level API 設計

### 6.1 MIDI2Client への統合

既存の `MIDI2Client` に Profile 操作メソッドを追加。

```swift
// MIDI2Kit (High-Level API)

extension MIDI2Client {

    // MARK: - Profile Configuration (Initiator)

    /// デバイスがサポートするプロファイル一覧を取得
    public func getProfiles(from muid: MUID) async throws -> ProfileState

    /// プロファイルを有効化
    public func enableProfile(
        _ profile: ProfileID,
        on muid: MUID,
        numberOfChannels: UInt16 = 1
    ) async throws

    /// プロファイルを無効化
    public func disableProfile(_ profile: ProfileID, on muid: MUID) async throws

    /// プロファイルの詳細情報を取得
    public func getProfileDetails(
        _ profile: ProfileID,
        from muid: MUID,
        target: UInt8
    ) async throws -> Data
}

/// デバイスのプロファイル状態（High-Level 型）
public struct ProfileState: Sendable {
    public let enabled: [ProfileID]
    public let disabled: [ProfileID]

    /// 指定プロファイルが有効かどうか
    public func isEnabled(_ profile: ProfileID) -> Bool

    /// 指定プロファイルがサポートされているか (enabled or disabled)
    public func isSupported(_ profile: ProfileID) -> Bool
}
```

### 6.2 MIDI2Device への統合

```swift
extension MIDI2Device {

    /// デバイスがサポートするプロファイル一覧（キャッシュ付き）
    public var profileState: ProfileState? { get async throws }

    /// Profile Configuration をサポートしているか
    public var supportsProfileConfiguration: Bool { get }
}
```

### 6.3 MIDI2ClientEvent への追加

```swift
extension MIDI2ClientEvent {
    // 既存の case に追加
    case profileEnabled(device: MIDI2Device, profile: ProfileID)
    case profileDisabled(device: MIDI2Device, profile: ProfileID)
    case profileAdded(device: MIDI2Device, profile: ProfileID)
    case profileRemoved(device: MIDI2Device, profile: ProfileID)
}
```

### 6.4 MIDI2ResponderClient への統合

```swift
extension MIDI2ResponderClient {

    /// プロファイルを登録
    public func addProfile(
        _ profile: ProfileID,
        address: ProfileAddress = .functionBlock,
        handler: ProfileHandler
    ) async

    /// プロファイルの登録解除
    public func removeProfile(_ profile: ProfileID) async
}

/// プロファイルのハンドラ
public struct ProfileHandler: Sendable {
    public let onEnable: @Sendable (MUID, UInt16) async -> Bool
    public let onDisable: @Sendable (MUID) async -> Bool
    public let onDetailsInquiry: (@Sendable (MUID, UInt8) async -> Data?)?

    public init(
        onEnable: @escaping @Sendable (MUID, UInt16) async -> Bool,
        onDisable: @escaping @Sendable (MUID) async -> Bool,
        onDetailsInquiry: (@Sendable (MUID, UInt8) async -> Data?)? = nil
    )
}
```

### 6.5 使用例

```swift
// Initiator: プロファイルの照会と有効化
let client = try MIDI2Client(name: "MyApp")
try await client.start()

for await event in await client.makeEventStream() {
    if case .deviceDiscovered(let device) = event,
       device.supportsProfileConfiguration {
        // プロファイル一覧を取得
        let profiles = try await client.getProfiles(from: device.muid)
        print("Enabled: \(profiles.enabled)")
        print("Disabled: \(profiles.disabled)")

        // Default CC Mapping を有効化
        if profiles.isSupported(.Standard.defaultCCMapping) {
            try await client.enableProfile(.Standard.defaultCCMapping, on: device.muid)
        }
    }
}
```

```swift
// Responder: プロファイルの提供
let responder = try MIDI2ResponderClient(name: "MySynth")
await responder.addProfile(.Standard.defaultCCMapping) {
    ProfileHandler(
        onEnable: { initiatorMUID, channels in
            // CC マッピングを有効化する処理
            activateDefaultCCMapping()
            return true
        },
        onDisable: { initiatorMUID in
            deactivateDefaultCCMapping()
            return true
        }
    )
}
try await responder.start()
```

---

## 7. CIManager との統合

### 7.1 Discovery フローとの連携

Discovery Reply の `ciCategorySupported` ビットマップの bit 2 (0x04) が Profile Configuration サポートを示す。既存の `CIManager` が Discovery 時にこのビットを解析済みであることを前提とする。

```
CI Category Supported bitmap:
  bit 0: Reserved
  bit 1: Reserved
  bit 2: Profile Configuration
  bit 3: Property Exchange
  ...
```

### 7.2 統合アーキテクチャ

```
MIDI2Client
    ├── CIManager (Discovery)
    │     └── DiscoveredDevice.supportsProfileConfiguration
    ├── PEManager (Property Exchange)
    ├── ProfileManager (Profile Configuration)  ← NEW
    └── ProfileResponder (Profile Responder)    ← NEW (MIDI2ResponderClient 用)
```

### 7.3 メッセージルーティング

受信した MIDI-CI SysEx メッセージの Sub-ID#2 に基づいて、適切なマネージャーにルーティング:

- 0x20-0x2F → `ProfileManager` / `ProfileResponder`
- 0x30-0x3F → `PEManager`（既存）
- 0x70-0x7F → `CIManager`（既存、Discovery）

既存の `CIManager` 内のメッセージディスパッチロジックに Profile 範囲のルーティングを追加する。

### 7.4 DiscoveredDevice の拡張

```swift
extension DiscoveredDevice {
    /// Profile Configuration をサポートしているか
    public var supportsProfileConfiguration: Bool {
        ciCategorySupported & 0x04 != 0
    }
}
```

---

## 8. テスト戦略

### 8.1 テストレイヤー

既存の MockTransport パターンを活用した 3 層のテスト:

#### Layer 1: メッセージパース/ビルドの単体テスト

```swift
// ProfileMessageBuilderTests
- Profile Inquiry メッセージの正しいバイト列生成
- Reply to Profile Inquiry の enabled/disabled リストのシリアライズ
- 全 11 メッセージタイプのラウンドトリップテスト (build → parse → verify)
- 不正バイト列のパースエラー処理
- Profile ID の 5 バイト境界値テスト
```

#### Layer 2: ProfileManager / ProfileResponder の単体テスト

```swift
// ProfileManagerTests (MockTransport 使用)
- inquireProfiles: Inquiry 送信 → Reply 受信 → DeviceProfileState 返却
- enableProfile: Set Profile On 送信 → Profile Enabled Report 受信
- disableProfile: Set Profile Off 送信 → Profile Disabled Report 受信
- タイムアウト処理
- キャッシュの更新と無効化
- 複数デバイスの並行操作

// ProfileResponderTests (MockTransport 使用)
- Profile Inquiry 受信 → 登録済みプロファイル一覧の応答
- Set Profile On 受信 → Delegate 呼び出し → Enabled Report 送信
- Set Profile Off 受信 → Delegate 呼び出し → Disabled Report 送信
- Profile Details Inquiry への応答
- Profile Added/Removed Report の自動送信
```

#### Layer 3: 統合テスト

```swift
// ProfileIntegrationTests (LoopbackTransport 使用)
- Initiator ↔ Responder の完全なフロー
- Discovery → Profile Inquiry → Set Profile On の E2E フロー
- 複数 Initiator からの同時操作
- MIDI2Client + MIDI2ResponderClient の統合テスト
```

### 8.2 テスト目標

- 新規テストケース: 80+ (ProfileMessageBuilder: 30, ProfileManager: 25, ProfileResponder: 15, Integration: 10+)
- 全パスのカバレッジ、エッジケースの網羅

---

## 9. 実装フェーズ

### Phase 1: 基盤型とメッセージ処理 (推定 2-3 日)

**目標**: Profile ID とメッセージのシリアライズ/デシリアライズ

- [ ] `ProfileID` 型の実装
- [ ] `ProfileAddress` enum の実装
- [ ] `ProfileMessageSubtype` 定数
- [ ] `ProfileMessageBuilder` の全メッセージビルダー実装
- [ ] `ProfileMessageParser` の全メッセージパーサー実装
- [ ] `ProfileMessage` enum
- [ ] Standard Profile ID 定数 (`ProfileID.Standard`)
- [ ] 単体テスト: メッセージのラウンドトリップテスト (30+ tests)

**成果物**: `MIDI2Profile` モジュールの基盤。メッセージの生成とパースが完全に動作。

### Phase 2: ProfileManager (Initiator) (推定 2-3 日)

**目標**: Initiator 側の Profile 操作

- [ ] `ProfileManager` actor の実装
- [ ] `inquireProfiles()` の実装（リクエスト/レスポンスのペアリング）
- [ ] `enableProfile()` / `disableProfile()` の実装
- [ ] `inquireProfileDetails()` の実装
- [ ] `sendProfileSpecificData()` の実装
- [ ] イベントストリーム (`makeEventStream()`)
- [ ] プロファイル状態キャッシュ
- [ ] タイムアウト処理
- [ ] 単体テスト: MockTransport を使った全操作テスト (25+ tests)

**成果物**: ProfileManager が単体で動作。MockTransport でテスト済み。

### Phase 3: ProfileResponder (推定 2 日)

**目標**: Responder 側の Profile 提供

- [ ] `ProfileResponder` actor の実装
- [ ] Profile 登録/解除 API
- [ ] Profile Inquiry への自動応答
- [ ] Set Profile On/Off のデリゲート呼び出しと Report 送信
- [ ] Profile Details Inquiry への応答
- [ ] Profile Added/Removed Report の自動送信
- [ ] 単体テスト (15+ tests)

**成果物**: ProfileResponder が単体で動作。

### Phase 4: High-Level API 統合 (推定 2-3 日)

**目標**: MIDI2Client / MIDI2ResponderClient への統合

- [ ] `CIManager` のメッセージルーティング拡張 (Sub-ID#2 0x20-0x2F)
- [ ] `DiscoveredDevice.supportsProfileConfiguration` の追加
- [ ] `MIDI2Client` への Profile メソッド追加
- [ ] `MIDI2Device` への `profileState` / `supportsProfileConfiguration` 追加
- [ ] `MIDI2ClientEvent` への Profile イベント追加
- [ ] `MIDI2ResponderClient` への Profile 登録 API 追加
- [ ] `ProfileHandler` の実装
- [ ] `MIDI2ClientConfiguration` への Profile 設定追加
- [ ] 統合テスト: LoopbackTransport を使った E2E テスト (10+ tests)

**成果物**: MIDI2Client から Profile Configuration の全操作が利用可能。

### Phase 5: ドキュメントと仕上げ (推定 1 日)

- [ ] API.md / README.md への Profile Configuration セクション追加
- [ ] Package.swift への `MIDI2Profile` ターゲット追加
- [ ] マイグレーションガイドの更新
- [ ] 最終的なコードレビューとリファクタリング

### 合計推定工数: 9-12 日

### リスクと依存関係

| リスク | 影響 | 緩和策 |
|-------|------|-------|
| Standard Profile ID の正確な byte 値が未確認 | 定数が不正確になる可能性 | MMA 正式仕様書で確認後に修正 |
| 実機テスト環境の制限 | 相互運用性の検証が不十分 | LoopbackTransport での E2E テストで補完、Roland A-88MKII での実機テストを計画 |
| CIManager のメッセージルーティング変更 | 既存の Discovery/PE に影響する可能性 | 既存テスト (602 tests) のリグレッション確認 |
| numberOfChannels (v1.2 追加) の扱い | v1.1 デバイスとの互換性 | v1.1 互換モード（numberOfChannels = 0 で省略）の実装 |

---

## 参考資料

- [M2-101-UM MIDI-CI v1.2 Specification (AMEI)](https://amei-music.github.io/midi2.0-docs/amei-pdf/M2-101-UM_v1-2_MIDI-CI_Specification.pdf)
- [M2-102-U Common Rules for MIDI-CI Profiles v1.1 (AMEI)](https://amei.or.jp/midistandardcommittee/MIDI2.0/MIDI2.0-DOCS/M2-102-U_v1-1_Common_Rules_for_MIDI-CI_Profiles.pdf)
- [MIDI.org - Details about MIDI 2.0, MIDI-CI, Profiles and Property Exchange](https://midi.org/details-about-midi-2-0-midi-ci-profiles-and-property-exchange-updated-june-2023)
- [MIDI.org - 6 New Profile Specifications Adopted](https://midi.org/6-new-profile-specifications-adopted)
- [Apple - MIDICIProfile Documentation](https://developer.apple.com/documentation/coremidi/midiciprofile)
- [Apple - MIDICIProfileState Documentation](https://developer.apple.com/documentation/coremidi/midiciprofilestate)
- [Apple - MIDICISession Documentation](https://developer.apple.com/documentation/coremidi/midicisession)
- [ni-midi2 - Profile Configuration Tests](https://github.com/midi2-dev/ni-midi2/blob/main/tests/ci_profile_configuration_tests.cpp)
- [atsushieno - Understanding MIDI-CI Tools](https://atsushieno.github.io/2024/01/26/midi-ci-tools.html)
