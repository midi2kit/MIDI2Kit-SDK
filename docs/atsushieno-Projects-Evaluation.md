# atsushieno プロジェクト評価レポート

**作成日**: 2026-02-04
**目的**: MIDI2Kit開発の参考となる知見の収集

## 概要

[atsushieno](https://github.com/atsushieno) 氏は、MIDI 2.0、オーディオプラグイン、Kotlinマルチプラットフォーム開発に特化した開発者。複数の関連プロジェクトを開発・維持しており、MIDI2Kit開発において参考となる知見が多い。

---

## プロジェクト一覧

### MIDI 2.0 / MIDI-CI 関連

| プロジェクト | 言語 | 概要 | MIDI2Kit関連度 |
|-------------|------|------|----------------|
| **ktmidi** | Kotlin | マルチプラットフォームMIDIライブラリ | ⭐⭐⭐⭐⭐ |
| **cmidi2** | C | Header-only UMP/MIDI-CI処理 | ⭐⭐⭐⭐ |
| **midicci** | C++ | MIDI-CIツール/ライブラリ | ⭐⭐⭐⭐ |
| **uapmd** | C++ | 仮想MIDI 2.0デバイス | ⭐⭐⭐ |
| **libremidi** | C++ | クロスプラットフォームMIDI (協力) | ⭐⭐⭐⭐ |

### オーディオプラグイン関連

| プロジェクト | 言語 | 概要 |
|-------------|------|------|
| **aap-core** | C/C++/Kotlin | Android Audio Plugin Framework |
| **aap-lv2** | C++ | LV2対応AAP拡張 |
| **aap-juce** | C++ | JUCE統合版AAP |

### 音楽制作ツール

| プロジェクト | 言語 | 概要 |
|-------------|------|------|
| **mugene-ng** | Kotlin | MML→MIDI 1.0/2.0コンパイラ |
| **augene-ng** | Kotlin | オーディオ生成エンジン |
| **managed-midi** | C# | クロスプラットフォームMIDI |

---

## 詳細評価

### 1. ktmidi (⭐⭐⭐⭐⭐ 最重要)

**リポジトリ**: https://github.com/atsushieno/ktmidi

**概要**:
- Kotlinマルチプラットフォーム（JVM/JS/Native）MIDIライブラリ
- MIDI 1.0、MIDI 2.0、SMF、SMF2、MIDI-CI対応
- `ktmidi-ci`モジュールでProperty Exchange実装

**MIDI2Kitへの示唆**:

| 機能 | ktmidi | MIDI2Kit | 評価 |
|------|--------|----------|------|
| UMP⇔MIDI1変換 | `UmpTranslator` | 未実装 | 参考にすべき |
| タイムアウト管理 | 未実装 | 実装済み | **MIDI2Kit優位** |
| リトライ機構 | 未実装 | 実装済み | **MIDI2Kit優位** |
| MIDI-CI 1.1対応 | 検討中 (#102) | 部分対応 | 同等 |

**参考コード**:
- `UmpTranslator`: UMP⇔MIDI 1.0変換の実装参考
- `MidiCIDevice`: MIDI-CIエージェント実装

**既知の課題** (ktmidi issues):
- #102: MIDI-CI 1.1サポート（KORGデバイス問題）
- #57: タイムアウト管理未実装

---

### 2. cmidi2 (⭐⭐⭐⭐)

**リポジトリ**: https://github.com/atsushieno/cmidi2

**概要**:
- C言語のheader-onlyライブラリ
- UMP/MIDI-CIバイナリ処理
- メモリ割り当てなしのリアルタイム対応設計

**技術的特徴**:
```c
// 32/64/128ビットパケットを整数値として直接操作
// LV2 Atomパターンに従う静的インライン関数構造
```

**MIDI2Kitへの示唆**:
- パケット処理のパフォーマンス最適化手法
- リアルタイム対応設計パターン
- **注意**: 破壊的変更が頻繁（API安定性低い）

**採用実績**:
- aap-core, aap-lv2, aap-juce
- libremidi（内部統合）

---

### 3. midicci (⭐⭐⭐⭐)

**リポジトリ**: https://github.com/atsushieno/midicci

**概要**:
- C++実装のMIDI-CIツール/ライブラリ
- ktmidi-ciのC++移植版
- トランスポート非依存設計

**ソースコード分析**:

| コンポーネント | 実装状況 | 詳細 |
|---------------|----------|------|
| PropertyChunkManager | △ | 欠落時は空応答のみ |
| タイムアウト処理 | △ | 期限切れ削除のみ |
| リトライ機構 | ❌ | 未実装 |
| エラーハンドリング | ❌ | スレッド安全性のみ |

**MIDI2Kitとの比較**:
MIDI2Kitの方が堅牢な実装を持つ（リトライ、タイムアウト、診断機能）

---

### 4. libremidi (⭐⭐⭐⭐)

**リポジトリ**: https://github.com/jcelerier/libremidi
（atsushieno氏が協力、cmidi2を統合）

**概要**:
- C++20のモダンMIDIライブラリ
- RtMidi/ModernMIDIの書き直し
- **全デスクトッププラットフォームでMIDI 2.0対応**

**MIDI 2.0サポート**:
- Windows: Windows MIDI Services
- macOS: CoreMIDI
- Linux: ALSA sequencer API

**技術的特徴**:
- ナノ秒単位の統一タイムスタンプ
- UMPストリーム処理（単一パケットだけでなく）
- 包括的なMIDI 1⇔MIDI 2変換

**MIDI2Kitへの示唆**:
- UMPストリーム処理の実装参考
- クロスプラットフォーム抽象化パターン

---

### 5. managed-midi (⭐⭐⭐)

**リポジトリ**: https://github.com/atsushieno/managed-midi

**概要**:
- C#/.NETのクロスプラットフォームMIDIライブラリ
- Linux/Mac/Windows/UWP/iOS/Android対応
- SMF操作・再生機能

**設計パターン**:

```
Bait-and-switchパッケージ戦略:
- netstandard2.0: API定義のみ（実装なし）
- プラットフォーム固有: 同名アセンブリで実装提供
```

**MIDI2Kitへの示唆**:
- クロスプラットフォーム抽象化の設計参考
- `IMidiAccess`インターフェースパターン
- **注意**: MIDI 2.0未対応、開発停滞気味

---

### 6. aap-core (⭐⭐⭐)

**リポジトリ**: https://github.com/atsushieno/aap-core

**概要**:
- Android Audio Plugin Framework
- アウトプロセス設計（Binder IPC + 共有メモリ）
- MIDI 2.0 UMP統合

**技術的特徴**:
- パラメータ変更をMIDI 2.0 UMP SysEx8で伝送
- Android 15以降でMidiUmpDeviceService実装
- GUI統合（ネイティブView/WebView）

**MIDI2Kitへの示唆**:
- MIDI 2.0をパラメータ伝送に活用するパターン
- プロセス間通信でのMIDI 2.0活用

---

### 7. mugene-ng (⭐⭐)

**リポジトリ**: https://github.com/atsushieno/mugene-ng

**概要**:
- MML→MIDI 1.0/2.0コンパイラ
- Kotlin Multiplatform
- MIDI 2.0 UMPストリーム出力対応

**MIDI2Kitへの示唆**:
- MIDI 2.0ファイル形式の実験的実装
- ktmidiエコシステムとの連携例

---

## 横断的な知見

### 1. 設計パターン

**トランスポート非依存設計**:
```
midicci, ktmidi共通:
- 双方向メッセージングシステムを抽象化
- プラットフォーム固有APIに依存しない
```

**ヘッダーオンリー設計** (cmidi2):
```
- コンパイル時に完全インライン化
- ゼロアロケーション
- リアルタイム安全
```

### 2. MIDI 2.0エコシステムの現状

**業界全体の課題**:
- 完全な相互運用性は未達成
- MIDI-CI 1.1 vs 1.2の互換性問題
- zlib+Mcoded7の相互運用性未検証

**プラットフォーム対応状況**:
| プラットフォーム | MIDI 2.0 | Property Exchange |
|-----------------|----------|-------------------|
| Windows | ✅ (MIDI Services) | △ |
| macOS | ✅ (CoreMIDI) | ❌ |
| Linux | ✅ (ALSA) | △ |
| Android | ✅ (API 35+) | △ |
| iOS | ✅ (CoreMIDI) | ❌ |

### 3. 開発者への推奨事項

atsushieno氏のブログ・ドキュメントより:

1. **段階的実装**: Discovery → Profile → Property Exchange
2. **相互運用性テスト**: 早期から複数実装間でテスト
3. **MIDI-CIは必須ではない**: UMPのみでMIDI 2.0の多くの機能は利用可能
4. **JSON形式の限界**: リアルタイム対応ではない（仕様レベルの制約）

---

## MIDI2Kitへの総合的示唆

### 優位性（維持すべき点）

| 機能 | MIDI2Kit | 他プロジェクト |
|------|----------|---------------|
| リトライ機構 | ✅ 実装済み | ❌ 未実装 |
| タイムアウト管理 | ✅ 設定可能 | ❌/△ |
| warm-upロジック | ✅ 実装済み | ❌ なし |
| DestinationCache | ✅ 実装済み | ❌ なし |
| 診断機能 | ✅ 充実 | △ 基本的 |
| KORG互換性対応 | ✅ tolerateCIVersionMismatch | △ 検討中 |

### 改善検討事項

| 機能 | 優先度 | 参考プロジェクト |
|------|--------|-----------------|
| UMP⇔MIDI1変換 | 中 | ktmidi `UmpTranslator` |
| Request IDライフサイクル | 高 | ktmidi #57 |
| zlib+Mcoded7 | 低 | ktmidi（相互運用性未検証） |
| ストリーム処理最適化 | 中 | libremidi |

### 参考にすべきコード

1. **ktmidi/UmpTranslator**: UMP⇔MIDI 1.0変換
2. **cmidi2**: パケット処理の最適化パターン
3. **libremidi**: クロスプラットフォーム抽象化
4. **managed-midi**: `IMidiAccess`インターフェース設計

---

## 参考リンク

### リポジトリ
- [ktmidi](https://github.com/atsushieno/ktmidi)
- [cmidi2](https://github.com/atsushieno/cmidi2)
- [midicci](https://github.com/atsushieno/midicci)
- [uapmd](https://github.com/atsushieno/uapmd)
- [libremidi](https://github.com/jcelerier/libremidi)
- [managed-midi](https://github.com/atsushieno/managed-midi)
- [aap-core](https://github.com/atsushieno/aap-core)
- [mugene-ng](https://github.com/atsushieno/mugene-ng)

### ブログ・ドキュメント
- [atsushieno.github.io](https://atsushieno.github.io/)
- [Understanding MIDI-CI tools](https://atsushieno.github.io/2024/01/26/midi-ci-tools.html)
- [Building MIDI 2.0 Ecosystems on Android](https://atsushieno.github.io/2024/04/12/midi2-on-android.html)
- [ktmidi, a Kotlin MPP Library](https://atsushieno.github.io/2021/05/18/ktmidi.html)

### 仕様書
- [MIDI-CI Property Exchange Specification](https://amei.or.jp/midistandardcommittee/MIDI2.0/MIDI2.0-DOCS/M2-103-UM_v1-1_Common_Rules_for_MIDI-CI_Property_Exchange.pdf)

---

## 結論

atsushieno氏のプロジェクト群は、MIDI 2.0エコシステムにおいて最も活発な開発が行われている領域の一つである。MIDI2Kitは、これらのプロジェクトと比較して**リトライ機構、タイムアウト管理、診断機能において明確な優位性**を持つ。

一方で、**UMP⇔MIDI 1.0変換**や**Request IDライフサイクル管理**についてはktmidiを参考に改善の余地がある。また、業界全体でMIDI-CIの完全な相互運用性が達成されていない現状を踏まえ、堅牢性を重視した現在のアプローチは妥当である。
