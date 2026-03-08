# MIDI 2.0 最新動向調査レポート

**調査日:** 2026年3月8日

---

## 目次

1. [macOS の MIDI 2.0 サポート状況](#1-macos-の-midi-20-サポート状況)
2. [Windows の MIDI 2.0 サポート状況](#2-windows-の-midi-20-サポート状況)
3. [MIDI 2.0 仕様の最新アップデート](#3-midi-20-仕様の最新アップデート)
4. [業界動向](#4-業界動向)

---

## 1. macOS の MIDI 2.0 サポート状況

### 現在の状況

Apple は 2021年10月に CoreMIDI へ USB MIDI 2.0 サポートを追加し、OS レベルでの MIDI 2.0 対応を業界に先駆けて実現した。

#### CoreMIDI の MIDI 2.0 API

| 機能 | 対応バージョン | 備考 |
|------|--------------|------|
| UMP (Universal MIDI Packet) 送受信 | macOS 11+ / iOS 14+ | `MIDIEventPacket` によるUMPフォーマット |
| MIDI 1.0 ⇔ 2.0 プロトコル自動変換 | macOS 11+ | システム全体で自動的に変換 |
| USB MIDI 2.0 クラスドライバ | macOS 11+ | クラス準拠デバイスは追加ドライバ不要 |
| MIDI-CI Discovery | macOS 14+ | `MIDICIDiscoveryManager` による自動検出 |
| MIDI-CI Session | macOS 14+ | `MIDICISession` + `MIDICIDiscoveredNode` |
| UMP Endpoint 作成 | iOS 18+ / macOS 15+ | アプリからの UMP エンドポイント公開 |

#### 主要 API クラス

- **`MIDICIDiscoveryManager`**: MIDI-CI Discovery メッセージを全 MIDI デスティネーションに送信し、応答を `MIDICIDiscoveredNode` として集約
- **`MIDICISession`**: Discovery 後に Initiator として MIDI-CI セッションを確立
- **`MIDIEventPacket`**: UMP フォーマットの MIDI イベントを表現
- **`MIDI2NoteOn` / `MIDI2NoteOff` 等**: MIDI 2.0 プロトコルのメッセージ生成ヘルパー

### 最近の変更点

- **macOS 15 (Sequoia)**: UMP エンドポイント作成 API の追加、MIDI-CI 関連 API の安定化
- **macOS 16 (Tahoe)** の互換性: KORG 等メーカーが macOS 26 での動作確認を進行中（KORG 互換性チャートが公開されている）
- WWDC 2025 では MIDI 2.0 に関する大きな新規発表は確認されていないが、既存 API の改善は継続

### 今後の見通し

- Apple は CoreMIDI を「MIDI 2.0-capable system-wide」として位置づけており、macOS/iOS のアップデートごとに API の成熟が進む見込み
- Property Exchange や Profile Configuration の CoreMIDI レベルでのネイティブサポート拡充が期待される
- Network MIDI 2.0 トランスポートへの対応も将来的に予想される

### 関連ライブラリ

- **[MIDIKit](https://github.com/orchetect/MIDIKit)**: Swift 製の CoreMIDI ラッパー。MIDI 2.0 UMP サポートを含むモダンな API を提供

---

## 2. Windows の MIDI 2.0 サポート状況

### 現在の状況

**Windows MIDI Services が 2026年2月に Windows 11 へ正式リリース。** これは Windows における MIDI サポートの最大のアップデートであり、MIDI 2.0 のネイティブサポートを実現した。

#### リリースタイムライン

| 時期 | マイルストーン |
|------|--------------|
| 2025年2月5日 | Windows Insider (Canary Channel) でプレビュー公開 |
| 2025年2月28日 | App SDK and Tools RC3 リリース |
| 2025年3月7日 | WinRT MIDI 1.0 タイムスタンプ修正パッチ |
| 2025年12月5日 | App SDK RC1 |
| 2026年2月17日 | Windows 11 (24H2/25H2) への正式ロールアウト開始 |
| 2026年 Q1 | SDK 1.0 および Tools パッケージ正式リリース予定 |

#### アーキテクチャ

Windows MIDI Services は以下の2つのコンポーネントで構成：

1. **インボックスコンポーネント**: Windows Update 経由で配信
   - MIDI サービス本体
   - MIDI 2.0 カーネルドライバ
   - WinMM / WinRT MIDI 1.0 API との後方互換レイヤー

2. **SDK Runtime & Tools パッケージ**: 別途ダウンロード
   - App SDK (Windows.Devices.Midi2 API)
   - MIDI コンソールツール
   - MIDI Settings アプリ
   - PowerShell プロジェクション

#### 主要機能

- **UMP ネイティブ**: 全体が UMP 中心の設計
- **マルチクライアント**: すべての MIDI 1.0 ポートと MIDI 2.0 エンドポイントが複数アプリから同時利用可能
- **低レイテンシー**: マイクロ秒単位のタイムスタンプとスケジューリング
- **USB 3.x 対応**: USB Full-Speed 制限なし
- **ループバック**: ドライバなしでアプリ間 MIDI 通信が可能
- **カスタムエンドポイント名**: 従来名・新スタイル名・完全カスタム名をサポート
- **OEM ドライバ不要**: クラス準拠デバイスはインボックスドライバで動作

### 最近の変更点

- **2026年2月**: Windows 11 への段階的ロールアウト開始（Windows Update 経由）
- **MIDI 1.0 強化**: マルチクライアント対応、安定性向上、デバイス命名改善、自動 MIDI 2.0 変換
- Steinberg Cubase、Cakewalk Sonar、Algoriddim djay Pro 等で発生していたタイムスタンプバグの修正

### 今後のロードマップ

- **Network MIDI 2.0**: Ethernet/Wi-Fi 経由の MIDI 2.0 トランスポート（SuperBooth、NAMM 2026 でデモ済み）
- **BLE MIDI 1.0 / 2.0**: Bluetooth 経由の MIDI サポート
- **仮想パッチベイ**: 高度な MIDI ルーティング機能
- オープンソースプロジェクトとして [GitHub](https://github.com/microsoft/MIDI) で開発継続

---

## 3. MIDI 2.0 仕様の最新アップデート

### 現在の仕様体系

2023年5月29日に MMA (MIDI Manufacturers Association) と AMEI が採択した仕様群が現行最新版。3年間の開発期間を経て、350ページ超の詳細仕様として無料公開されている。

#### コア仕様一覧

| 仕様書番号 | 名称 | バージョン |
|-----------|------|-----------|
| M2-100-U | MIDI 2.0 Specification Overview | v1.1 |
| M2-101-UM | MIDI Capability Inquiry (MIDI-CI) | v1.2 |
| M2-102-U | Common Rules for MIDI-CI Profiles | v1.1 |
| M2-103-UM | Common Rules for Property Exchange | v1.1 |
| M2-104-UM | UMP Format & MIDI 2.0 Protocol | v1.1.1 |
| M2-116-U | MIDI Clip File (SMF2) | v1.0 (新規) |

### MIDI-CI v1.2 の主な変更点

- Discovery プロセスの改善
- プロトコルネゴシエーションの強化
- エラーハンドリングの改善
- 後方互換性の確保

### Property Exchange v1.1

- JSON ベースのキー/バリュー形式で SysEx メッセージ内にデータを格納
- デバイス設定、コントローラー一覧と解像度、パッチリスト（名前・メタデータ付き）、メーカー情報等を照会・取得・設定可能
- Profile と組み合わせることで、デバイスの自動設定が実現

### Profile Configuration v1.1

- デバイスの用途に応じた動的設定を実現
- 例: コントロールサーフェスが「ミキサー」プロファイルで問い合わせるとフェーダー・パンポットにマッピング、「ドローバーオルガン」プロファイルなら仮想ドローバーにマッピング
- **Piano Profile**: Roland A88MKII + Synthogy Ivory での実装が先行

### Network MIDI 2.0 トランスポート

- **Network MIDI 2.0 (UDP)**: ローカルエリアネットワーク上で MIDI 1.0 / MIDI 2.0 UMP パケットを送受信するための公式仕様
- RTP-MIDI とは異なる新規設計。低レイテンシーなローカルネットワークに最適化
- RTP-MIDI は後方互換ブリッジとして位置づけ、新規開発には Network MIDI 2.0 を推奨

### 今後の見通し

- 2023年のメジャーアップデート以降、大きな仕様変更は確認されていない
- Profile の種類拡充（エフェクトプロファイル等）が進行中
- Network MIDI 2.0 の実装が広がることで、仕様のフィードバックに基づく改訂が予想される

---

## 4. 業界動向

### 主要メーカーの MIDI 2.0 対応状況

#### KORG

| 製品 | MIDI 2.0 機能 | 状況 |
|------|-------------|------|
| **Keystage** (MIDIコントローラー) | Property Exchange による自動設定 | 出荷中 |
| **multi/poly** (シンセサイザー) | Property Exchange、ポリフォニックアフタータッチ | 出荷中 |
| **multi/poly module** | Property Exchange（デスクトップ/ラック版） | 2025年 NAMM で発表、出荷中 |
| **multi/poly Native** | Property Exchange（ソフトウェア版） | 2025年3月リリース |
| **wavestate / opsix / modwave** | Keystage との Property Exchange 連携 | ファームウェアアップデートで対応 |

KORG は Keystage + シンセサイザー群での Property Exchange 連携により、MIDI 2.0 の実用的なエコシステムを最も積極的に展開している。

#### Roland

| 製品 | MIDI 2.0 機能 | 状況 |
|------|-------------|------|
| **A-88MKII** | Piano Profile、MIDI 2.0 Ready | ファームウェア更新で対応 |

Roland は Piano Profile の策定に貢献。Synthogy Ivory 3 との連携で Piano Profile の実動デモを NAMM 2025 で実施。

#### Yamaha

- AMEI（日本 MIDI 規格委員会）を通じた仕様策定への貢献
- Amenote（AMEI 関連）による Windows 向け MIDI 2.0 オープンソースドライバの開発資金提供
- **Montage M**: NAMM 2025 で Windows MIDI 2.0 との連携デモを実施

#### StudioLogic

- **SL MK2 シリーズ** (73鍵/88鍵): MIDI 2.0 対応を発表。高解像度、豊かなダイナミクスを実現
- **SL88 GT**: グレードハンマーアクション搭載フラグシップモデル

#### Rhodes

- 新型 Rhodes Piano が MIDI 2.0 対応準備中
- MIDI9 の Dave Starkey が Synthogy Ivory との互換性コーディングを支援

#### その他

- **Amenote / Bome / MusicKraken / Kissbox**: Network MIDI 2.0 トランスポート対応製品を展開

### DAW の MIDI 2.0 対応状況

| DAW | MIDI 2.0 対応レベル | 詳細 |
|-----|-------------------|------|
| **Cubase 14** | 高 | MIDI 2.0 → VST3 変換、高解像度ベロシティ/CC/アフタータッチ/ピッチベンド。NAMM 2025 で特別版デモ |
| **Cubase 13** | 中 | MIDI 2.0 メッセージの VST3 変換、高解像度データ対応 |
| **Logic Pro** | 中 | MIDI 2.0 内部処理、Property Exchange によるデバイス固有コントロール自動表示 |
| **Studio One 6+** | 中 | MIDI 2.0 Protocol Discovery/Negotiation、Property Exchange、Profile 設定 |
| **Nuendo 13** | 中 | Cubase 13 と同等の MIDI 2.0 サポート |
| **MultitrackStudio** | 高 | MIDI 2.0 CVM/VCM、MIDI-CI、Property Exchange、Program List 対応 |
| **Ableton Live** | 低 | ベータ版で実装中、フルサポートは今後のリリース予定 |

### MIDI 2.0 ライブラリ/SDK の動向

#### libremidi (C++)

- **最新版**: v4.5.0 (2025年1月8日)
- **対応プラットフォーム**: macOS 11+、Linux (Kernel 6.5+)、Windows 11 (MIDI Services 経由)
- **特徴**: 全デスクトッププラットフォームで MIDI 2.0 サポート、ネットワークバックエンド (OSC 経由)
- **URL**: [github.com/celtera/libremidi](https://github.com/celtera/libremidi)

#### AM_MIDI2.0Lib (C++)

- MMA 公式の MIDI 2.0 リファレンス実装
- **URL**: [github.com/midi2-dev/AM_MIDI2.0Lib](https://github.com/midi2-dev/AM_MIDI2.0Lib)

#### MIDIKit (Swift)

- macOS/iOS 向け CoreMIDI ラッパー、MIDI 2.0 UMP サポート
- **URL**: [github.com/orchetect/MIDIKit](https://github.com/orchetect/MIDIKit)

#### ktmidi (Kotlin)

- Kotlin Multiplatform 対応の MIDI 1.0/2.0 ライブラリ
- **URL**: [github.com/atsushieno/ktmidi](https://github.com/atsushieno/ktmidi)

#### ni-midi2 (C++)

- libremidi と相互運用可能な UMP ライブラリ

### アクセシビリティ

- NAMM 2025 で Music Accessibility Standard SIG がボイスコマンドによる MIDI デバイス制御デモを実施
- AI 技術とスクリーンリーダーを活用した MIDI デバイスアクセシビリティの向上

---

## まとめ

### 2025-2026年の主要トレンド

1. **Windows の MIDI 2.0 正式サポート**: 2026年2月の Windows MIDI Services 正式リリースにより、Windows と macOS の両方で OS レベルの MIDI 2.0 サポートが実現。これは MIDI 2.0 普及の最大の転換点。

2. **Property Exchange の実用化**: KORG が Keystage エコシステムで Property Exchange の実用的なユースケースを確立。デバイス間の自動設定が現実のワークフローに。

3. **Piano Profile の成熟**: Roland A88MKII + Synthogy Ivory を軸に、Piano Profile が最初の実用プロファイルとして定着。エフェクトプロファイルも策定中。

4. **Network MIDI 2.0 の登場**: Ethernet/Wi-Fi 経由の MIDI 2.0 トランスポートが実製品で展開開始。Windows でもプレビュー対応。

5. **DAW の段階的対応**: Cubase が最も積極的、Logic Pro と Studio One が追随。Ableton Live は開発中。

### MIDI2Kit-SDK への示唆

- Windows MIDI Services の正式リリースにより、Windows 向け MIDI 2.0 SDK の需要が急増する可能性
- Property Exchange と Profile Configuration の実装サポートが差別化要因になりうる
- Network MIDI 2.0 トランスポートへの早期対応が競争優位性を生む可能性
- libremidi v4.5.0 が全プラットフォーム対応を達成しており、C++ 領域での競合として認識が必要

---

## Sources

- [Apple - Incorporating MIDI 2 into your apps](https://developer.apple.com/documentation/coremidi/incorporating-midi-2-into-your-apps)
- [Apple - Core MIDI Documentation](https://developer.apple.com/documentation/coremidi/)
- [Apple - MIDI Capability Inquiry](https://developer.apple.com/documentation/coremidi/midi_capability_inquiry/publishing_and_discovering_midi_capabilities/)
- [Windows Experience Blog - Making music with MIDI just got a real boost in Windows 11](https://blogs.windows.com/windowsexperience/2026/02/17/making-music-with-midi-just-got-a-real-boost-in-windows-11/)
- [Microsoft - About Windows MIDI Services](https://microsoft.github.io/MIDI/)
- [Microsoft MIDI GitHub Releases](https://github.com/microsoft/MIDI/releases)
- [Windows Central - Windows 11 discovers MIDI 2.0 in 2026](https://www.windowscentral.com/microsoft/windows-11/windows-11-gets-midi-2-0-support)
- [The Register - Windows 11 finally hits right note: MIDI 2.0 support arrives](https://www.theregister.com/2026/02/18/microsoft_makes_sweet_music_with/)
- [Neowin - Windows 11 finally supports MIDI 2.0](https://www.neowin.net/news/windows-11-finally-supports-midi-20/)
- [MIDI.org - MIDI 2.0 Coming to Windows 11](https://midi.org/midi-2-0-coming-to-windows-11)
- [MIDI.org - The MIDI Association NAMM 2025](https://midi.org/the-midi-association-namm-2025)
- [MIDI.org - Network MIDI 2.0 (UDP) Overview](https://midi.org/network-midi-2-0-udp-overview)
- [MIDI.org - Details about MIDI 2.0, MIDI-CI, Profiles and Property Exchange](https://midi.org/details-about-midi-2-0-midi-ci-profiles-and-property-exchange-updated-june-2023)
- [AMEI - MIDI 2.0 Specification Overview v1.1](https://amei.or.jp/midistandardcommittee/MIDI2.0/MIDI2.0-DOCS/M2-100-U_v1-1_MIDI_2-0_Specification_Overview.pdf)
- [KVR Audio - AMEI and The MIDI Association update MIDI 2.0 core specifications](https://www.kvraudio.com/focus/amei-and-the-midi-association-update-midi-2-0-core-specifications-58039)
- [Sound on Sound - MIDI 2.0 specifications updated](https://www.soundonsound.com/news/midi-20-specifications-updated)
- [Production Expert - Windows 11 Adds MIDI 2.0 Support](https://www.production-expert.com/production-expert-1/windows-11-adds-midi-20-support-with-new-windows-midi-services)
- [KORG - How to use MIDI 2.0 Property Exchange with Keystage](https://support.korguser.net/hc/en-us/articles/23239583169561-How-to-use-MIDI-2-0-Property-Exchange-with-Keystage)
- [KORG - multi/poly module](https://www.korg.com/us/products/synthesizers/multipoly_module/)
- [Synthogy - Piano Profile NAMM 2025](https://synthogy.com/article/synthogy-and-roland-preview-piano-profile-NAMM-2025)
- [DepartureMusic - MIDI 2.0 DAW Implementation Guide](https://www.departuremusic.com/midi-2-0-daw-implementation/)
- [libremidi GitHub](https://github.com/celtera/libremidi)
- [AM_MIDI2.0Lib GitHub](https://github.com/midi2-dev/AM_MIDI2.0Lib)
- [MIDIKit GitHub](https://github.com/orchetect/MIDIKit)
- [Wikipedia - MIDI 2.0](https://en.wikipedia.org/wiki/MIDI_2.0)
