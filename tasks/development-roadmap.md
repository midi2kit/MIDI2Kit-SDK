# MIDI2Kit 開発方針 2026

策定日: 2026-03-08

## 1. エグゼクティブサマリー

MIDI2Kitは、Apple プラットフォーム向けの MIDI 2.0 / MIDI-CI / Property Exchange ライブラリとして、現時点で**唯一の Swift ネイティブ MIDI-CI 実装**という独自のポジションを持つ。2026年に入り、Windows 11 の MIDI 2.0 正式対応、Roland/Yamaha/KORG の製品での MIDI 2.0 実装進展、Piano Profile の実用化など、エコシステムが加速している。このタイミングを捉え、v1.1.x での機能拡充から v2.0 でのメジャーアップデートへ向けた段階的なロードマップを策定する。

---

## 2. 市場環境分析

### 2.1 MIDI 2.0 エコシステムの現状

| 領域 | 状況 |
|------|------|
| **仕様** | MIDI-CI v1.2、UMP v1.1 が最新（2023年6月更新）。Profile 仕様6件採択済み |
| **OS サポート** | macOS/iOS: CoreMIDI で UMP サポート済み。Windows 11: 2026年2月に MIDI 2.0 正式対応 |
| **ハードウェア** | Roland A-88MKII (Piano Profile)、KORG multi/poly (PE/Poly AT)、Yamaha Montage M が対応 |
| **DAW** | Logic Pro 12 (MPE ネイティブ)、Ableton Live 13 (AI マッピング)。MIDI 2.0 Protocol の完全対応は依然進行中 |
| **Profile** | Piano Profile が Roland + Synthogy (Ivory) で実用化段階。Default Controller Profile 他 6 件が採択 |

### 2.2 競合ライブラリ分析

| ライブラリ | 言語 | MIDI-CI | PE | Profile | Process Inquiry | プラットフォーム |
|-----------|------|---------|-----|---------|----------------|--------------|
| **MIDI2Kit** | Swift | Yes | Yes | No | No | Apple (iOS/macOS/tvOS/watchOS/visionOS) |
| **MIDIKit (orchetect)** | Swift | No | No | No | No | Apple (macOS/iOS/visionOS) |
| **ktmidi** | Kotlin | Yes | Yes | Partial | No | JVM/Android/JS/Native |
| **libremidi** | C++ | No | No | No | No | macOS/Linux/Windows |
| **Windows MIDI Services** | C++/C# | Yes | Yes | Yes | Partial | Windows 11 |

### 2.3 MIDI2Kit の差別化要因

1. **唯一の Swift ネイティブ MIDI-CI/PE 実装** -- MIDIKit は CoreMIDI ラッパーに留まり、MIDI-CI/PE レイヤーは未実装
2. **Swift 6 Strict Concurrency** -- actor ベースのスレッドセーフ設計
3. **実デバイス検証済み** -- KORG Module Pro / BLE MIDI での実績
4. **ベンダー最適化** -- KORG 向け 99% 高速化等の実用的最適化
5. **Responder API** -- MIDI-CI Responder としても動作可能

---

## 3. ターゲットユーザー

### 3.1 プライマリターゲット

| セグメント | ニーズ | 規模感 |
|-----------|-------|--------|
| **iOS/macOS 音楽アプリ開発者** | MIDI 2.0 デバイスとの通信、PE による設定取得/変更 | 数百〜数千人 |
| **シンセ/エフェクトプラグイン開発者** | ホストアプリとの MIDI 2.0 連携 | 数百人 |
| **楽器メーカーのアプリ開発チーム** | 自社ハードウェアのコンパニオンアプリ | 数十社 |

### 3.2 セカンダリターゲット

| セグメント | ニーズ |
|-----------|-------|
| **教育機関・研究者** | MIDI 2.0 プロトコルの学習・実験 |
| **visionOS 音楽アプリ開発者** | 空間オーディオ + MIDI の統合 |
| **MIDI コントローラーメーカー** | Profile Configuration によるプラグ&プレイ実現 |

---

## 4. ロードマップ

### 4.1 短期目標 (v1.2.x - v1.3.x) -- 2026年 3月〜6月

**テーマ: MIDI-CI の完全性を高め、実用的な Profile サポートを追加**

#### P0: Profile Configuration サポート

MIDI 2.0 エコシステムで Piano Profile が実用化段階に入っている。Profile Configuration は MIDI-CI の中核機能であり、現状未実装は大きなギャップ。

- [ ] **Profile Discovery** -- Initiator/Responder 間の Profile 照会
- [ ] **Profile Enable/Disable** -- Profile の有効化/無効化メッセージ
- [ ] **Profile Specific Data** -- Profile 固有データの送受信
- [ ] **Built-in Profiles** -- Piano Profile、Default Controller Profile の型安全な定義
- [ ] **MIDI2ProfileClient** -- Profile 管理用の High-Level API
- [ ] 新モジュール `MIDI2Profile` の追加

```
推定工数: 3-4週間
リリース: v1.2.0
```

#### P1: MIDI 2.0 Channel Voice Messages 拡充

UMPBuilder/UMPParser は基本的な Channel Voice をサポートしているが、MIDI 2.0 固有の高解像度メッセージの完全サポートが必要。

- [ ] **Per-Note Controllers** -- ノート単位の CC (MIDI 2.0 固有)
- [ ] **Per-Note Pitch Bend** -- ノート単位のピッチベンド
- [ ] **Per-Note Management** -- ノート管理メッセージ
- [ ] **Registered/Assignable Per-Note Controllers** -- 登録済み/割当可能コントローラー
- [ ] **UMP Stream Messages** -- Endpoint Discovery / Function Block 等

```
推定工数: 2-3週間
リリース: v1.2.x または v1.3.0
```

#### P2: テストカバレッジ・CI 改善

- [ ] コードカバレッジ計測の導入（602 テストの網羅率可視化）
- [ ] Profile Configuration のテスト追加（目標: +50 テスト）
- [ ] GitHub Actions の代替 CI 検討（現在ローカル検証のみ）

```
推定工数: 1-2週間
```

### 4.2 中期目標 (v1.4.x - v1.5.x) -- 2026年 6月〜9月

**テーマ: Process Inquiry と高度なデバイス連携**

#### P0: Process Inquiry サポート

MIDI-CI v1.2 で規定された Process Inquiry は、デバイスの MIDI メッセージ処理状態の照会を可能にする。MIDI 2.0 準拠の最低互換要件にも含まれる。

- [ ] **Process Inquiry Messages** -- MIDI Message Report 要求/応答
- [ ] **Capability Inquiry for Process** -- 対応 MIDI メッセージタイプの照会
- [ ] High-Level API への統合
- [ ] 新モジュール `MIDI2PI` の追加（または MIDI2CI に統合）

```
推定工数: 2-3週間
リリース: v1.4.0
```

#### P1: visionOS 最適化

visionOS 26 のリリースと VIS (Virtual Immersive Studio) の登場により、空間オーディオ + MIDI の統合ニーズが高まる。

- [ ] visionOS 26 での動作検証と最適化
- [ ] 空間オーディオ連携のサンプルコード
- [ ] RealityKit + MIDI2Kit の統合ガイド
- [ ] visionOS 固有の UI パターン（3D MIDI コントローラー等）のデモ

```
推定工数: 2週間
リリース: v1.4.x
```

#### P2: ベンダー最適化の拡張

KORG 向け最適化の成功パターンを他メーカーへ展開。

- [ ] **Roland 最適化** -- A-88MKII との Piano Profile 連携テスト
- [ ] **Yamaha 最適化** -- Montage M との PE 互換性確認
- [ ] **VendorOptimization プラグイン機構** -- サードパーティがベンダー固有最適化を追加可能に

```
推定工数: 2-3週間
リリース: v1.5.0
```

#### P3: パフォーマンス最適化

- [ ] メモリプロファイリング -- 大量デバイス接続時のメモリ使用量計測・削減
- [ ] レイテンシ計測 -- PE 操作のエンドツーエンドレイテンシ可視化
- [ ] BLE MIDI 信頼性向上 -- パケットロス時の再送戦略改善

```
推定工数: 1-2週間
```

### 4.3 長期目標 (v2.0) -- 2026年 9月〜2027年 3月

**テーマ: メジャーバージョンアップと拡張性の確立**

#### P0: v2.0 アーキテクチャ刷新

v1.x の実績を踏まえ、API の整理と拡張性の向上を図る。

- [ ] **API の整理** -- v1.x で非推奨にしたAPIの削除、命名規則の統一
- [ ] **モジュール構成の見直し** -- MIDI2Profile / MIDI2PI の正式統合
- [ ] **Protocol-oriented Transport** -- CoreMIDI 以外のトランスポート（Network MIDI 等）への拡張
- [ ] **Swift 6+ 新機能の活用** -- Typed throws、パフォーマンス改善

```
推定工数: 4-6週間
リリース: v2.0.0
```

#### P1: クロスプラットフォーム対応の検討

Windows 11 の MIDI 2.0 対応により、クロスプラットフォーム需要は存在するが、現実的な優先度を見極める。

- [ ] **Transport 抽象化の強化** -- CoreMIDI 依存部分の分離
- [ ] **Linux (ALSA) Transport** -- Swift on Linux + ALSA バインディング（実験的）
- [ ] **libremidi ブリッジ** -- C++ ライブラリとの相互運用性調査

> **判断基準**: Swift on Linux のエコシステム成熟度、実ユーザーからの需要次第。Apple プラットフォーム最優先の方針は維持する。

```
推定工数: 調査 1週間 → 実装判断
```

#### P2: MIDI Clip File (SMF2) サポート

MIDI 2.0 June 2023 仕様で追加された新しいファイルフォーマット。

- [ ] SMF2 読み込み/書き出し
- [ ] Delta Clockstamps メッセージ対応
- [ ] レガシー SMF との変換

```
推定工数: 2-3週間
```

---

## 5. 技術的改善ロードマップ

| 項目 | 時期 | 内容 |
|------|------|------|
| **テストカバレッジ** | 短期 | カバレッジ計測導入、目標 80%+ |
| **CI/CD** | 短期 | GitHub Actions または代替 CI でのビルド・テスト自動化 |
| **パフォーマンス** | 中期 | Instruments による PE レイテンシ/メモリ使用量のベースライン計測 |
| **ドキュメント生成** | 中期 | DocC による API ドキュメント自動生成 |
| **セキュリティ** | 継続 | 定期的なセキュリティ監査の継続 |

---

## 6. エコシステム戦略

### 6.1 サンプルアプリ

| アプリ | 目的 | 時期 |
|-------|------|------|
| **MIDI2Explorer** | デバイス発見 + PE ブラウザ（既存の拡張） | 短期 |
| **MIDI2ProfileDemo** | Profile Configuration のデモ（Piano Profile 対応） | 短期 |
| **MIDI2ResponderDemo** | Responder API のショーケース | 中期 |
| **MIDI2SpatialController** | visionOS + MIDI の統合デモ | 中期 |

### 6.2 ドキュメント・チュートリアル

| コンテンツ | 内容 | 時期 |
|-----------|------|------|
| **Getting Started ガイド** | 5分でデバイス発見 + PE 取得まで | 短期 |
| **Profile Configuration ガイド** | Piano Profile 実装チュートリアル | 短期 (Profile 実装後) |
| **ベンダー対応ガイド** | KORG/Roland/Yamaha 各社デバイスとの接続方法 | 中期 |
| **Architecture Decision Records** | 設計判断の記録（技術者向け） | 継続 |

### 6.3 コミュニティ戦略

- **GitHub Discussions** -- 質問・機能要望の受付
- **サンプルコードの充実** -- ユースケースごとのミニマルな例
- **MIDI Association との連携** -- 仕様準拠テストへの参加検討
- **Swift Package Index** 登録の維持・更新

---

## 7. 差別化戦略まとめ

### MIDI2Kit のユニークバリュー

```
┌──────────────────────────────────────────────────────────────┐
│                    MIDI2Kit の差別化マトリクス                    │
├──────────────────────┬───────────┬──────────┬───────────────┤
│                      │ MIDI2Kit  │ MIDIKit  │ ktmidi        │
├──────────────────────┼───────────┼──────────┼───────────────┤
│ MIDI-CI Discovery    │ ●         │ ○        │ ●             │
│ Property Exchange    │ ●         │ ○        │ ●             │
│ Profile Config       │ △ (計画)  │ ○        │ △             │
│ Process Inquiry      │ △ (計画)  │ ○        │ ○             │
│ Responder API        │ ●         │ ○        │ ●             │
│ Swift Concurrency    │ ●         │ ●        │ N/A           │
│ 実デバイス検証        │ ●         │ △        │ △             │
│ ベンダー最適化        │ ●         │ ○        │ ○             │
│ visionOS             │ ●         │ ●        │ ○             │
│ Apple 全プラットフォーム│ ●        │ △        │ △ (iOS のみ)   │
├──────────────────────┴───────────┴──────────┴───────────────┤
│ ● = サポート済み  △ = 部分的/計画中  ○ = 未サポート            │
└──────────────────────────────────────────────────────────────┘
```

### 競争優位の維持方針

1. **MIDI-CI 完全実装のリード維持** -- Profile + Process Inquiry を早期実装し、Swift エコシステムで唯一の完全 MIDI-CI ライブラリを維持
2. **実デバイス検証の継続** -- ラボ環境での机上実装ではなく、実機テストに基づく品質保証
3. **ベンダー最適化のプラットフォーム化** -- KORG の成功事例を他メーカーへ展開
4. **Apple プラットフォームへの深いコミットメント** -- visionOS/watchOS 含む全プラットフォーム対応

---

## 8. リスクと対策

| リスク | 影響度 | 対策 |
|--------|--------|------|
| Apple が CoreMIDI に MIDI-CI を内蔵 | 高 | Higher-level API（ベンダー最適化、Responder）での差別化維持 |
| MIDI 2.0 普及の遅延 | 中 | MIDI 1.0 互換レイヤーの充実、UMP 変換機能の強化 |
| MIDIKit が MIDI-CI を実装 | 中 | 実デバイス検証済みの品質と、ベンダー最適化で差別化 |
| テスト用ハードウェアの不足 | 中 | MockTransport の充実、仮想 MIDI デバイスのテストカバレッジ強化 |
| 個人開発のリソース制約 | 高 | 優先順位の厳格な管理、P0 フォーカス |

---

## 9. KPI

| 指標 | 現在 | 6ヶ月目標 | 12ヶ月目標 |
|------|------|----------|-----------|
| テスト数 | 602 | 750+ | 900+ |
| テストカバレッジ | 未計測 | 75%+ | 85%+ |
| MIDI-CI 機能網羅率 | 60% (Discovery+PE) | 80% (+Profile) | 95% (+PI) |
| サンプルアプリ数 | 1 | 3 | 5 |
| 対応デバイス確認数 | 1 (KORG) | 3 (+Roland, Yamaha) | 5+ |
| SPM ダウンロード数 | - | ベースライン計測 | 成長率追跡 |

---

## 10. 次のアクション

1. **即座**: Profile Configuration の仕様精読と設計着手
2. **1週間以内**: v1.2.0 のマイルストーン作成と GitHub Issues 起票
3. **2週間以内**: Profile Discovery/Enable の基本実装
4. **1ヶ月以内**: Piano Profile のデモアプリ動作確認

---

## Sources

- [MIDI 2.0 - Wikipedia](https://en.wikipedia.org/wiki/MIDI_2.0)
- [Windows 11 MIDI 2.0 support (2026)](https://www.windowscentral.com/microsoft/windows-11/windows-11-gets-midi-2-0-support)
- [Making music with MIDI - Windows Experience Blog](https://blogs.windows.com/windowsexperience/2026/02/17/making-music-with-midi-just-got-a-real-boost-in-windows-11/)
- [6 New Profile Specifications Adopted - MIDI.org](https://midi.org/6-new-profile-specifications-adopted)
- [MIDI-CI Profiles and Property Exchange - MIDI.org](https://midi.org/details-about-midi-2-0-midi-ci-profiles-and-property-exchange-updated-june-2023)
- [MIDIKit (orchetect)](https://github.com/orchetect/MIDIKit)
- [ktmidi (atsushieno)](https://github.com/atsushieno/ktmidi)
- [libremidi (celtera)](https://github.com/celtera/libremidi)
- [Experience the Future of MIDI at NAMM 2025 - Synthogy](https://synthogy.com/article/synthogy-and-roland-preview-piano-profile-NAMM-2025)
- [MIDI Controllers in 2026 - DLK Music Pro](https://news.dlkmusicpro.com/midi-controllers-in-2026-when-expression-finally-catches-up/)
- [Apple CoreMIDI Documentation](https://developer.apple.com/documentation/coremidi/)
- [Incorporating MIDI 2 into your apps - Apple](https://developer.apple.com/documentation/coremidi/incorporating-midi-2-into-your-apps)
- [KORG at NAMM 2025](https://www.korg.com/us/news/2025/0121/)
- [MIDI Association NAMM 2025](https://midi.org/the-midi-association-namm-2025)
- [visionOS 26 - Apple](https://www.apple.com/newsroom/2025/06/visionos-26-introduces-powerful-new-spatial-experiences-for-apple-vision-pro/)
- [MIDI-CI v1.2 Specification (AMEI)](https://amei-music.github.io/midi2.0-docs/amei-pdf/M2-101-UM_v1-2_MIDI-CI_Specification.pdf)
- [Understanding MIDI-CI tools - atsushieno](https://atsushieno.github.io/2024/01/26/midi-ci-tools.html)
