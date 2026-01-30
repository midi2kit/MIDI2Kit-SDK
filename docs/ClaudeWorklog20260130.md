---

---
2026-01-30 04:54
作業項目: 追加レビュー確認と評価
レビューファイル: /Users/hakaru/Downloads/MIDI2Kit_main_review_2026-01-30.md
レビュー評価:
  - アーキテクチャ: 4/5（良好）
  - 正しさ/一貫性: 2.5/5（設定と実装のズレ）
  - レジリエンス: 3/5（基本は良い）
  - デバッグ容易性: 3/5（診断機能あるが配線不足）
  - CI/テスト: 2/5（テスト失敗を握りつぶす設定）

重要指摘（P0 - 最優先）:
  1. peSendStrategy が PEManager に配線されていない 🔴
     - MIDI2ClientConfiguration.peSendStrategy 設定が未反映
     - デフォルト（broadcast）のまま動作 → timeout の外的要因
  2. multiChunkTimeoutMultiplier が実際のPEリクエストに未適用 🔴
     - getResourceList で計算しているが peManager に渡していない
     - 実際の待ち時間が伸びていない
  3. PEChunkAssembler の print デバッグがそのまま 🔴
     - logger 統一が必要

重要指摘（P1）:
  4. RobustJSONDecoder が正しいJSONを壊す可能性 🟡
     - escapeControlCharacters が改行を壊す
     - removeComments が "https://" を壊す
  5. PEDecodingDiagnostics が外に出ていない 🟡
     - lastDecodingDiagnostics プロパティが存在しない

重要指摘（P2）:
  6. CI がテスト失敗を握りつぶしている 🟢
     - || echo で失敗を成功扱い

PE timeout 切り分けチェックポイント:
  - Receive dispatcher 動作確認
  - destination 解決確認
  - RequestID 管理確認（リーク、取り違え）
  - MUID フィルタ確認
  - チャンク欠落確認

決定事項:
  - P0指摘3点は Phase 5-1 より優先度高い
  - 次回: P0修正 → Phase 5-1継続
次のTODO:
  - P0-1: peSendStrategy配線
  - P0-2: multiChunkTimeoutMultiplier適用
  - P0-3: print → logger統一
  - TODO.mdに反映
---

---
2026-01-30 06:33
作業項目: Phase 0-1 開始 - peSendStrategy配線
対象ファイル:
  - Sources/MIDI2Kit/HighLevelAPI/MIDI2Client.swift
  - Sources/MIDI2Kit/HighLevelAPI/MIDI2ClientConfiguration.swift
  - Sources/MIDI2PE/PEManager.swift
  - Sources/MIDI2PE/PESendStrategy.swift

問題内容:
  - MIDI2ClientConfiguration.peSendStrategy が PEManager に渡されていない
  - PEManager は sendStrategy をデフォルト（.broadcast）で初期化
  - 期待: .single や .fallback で副作用を抑える
  - 実際: .broadcast のまま → 他ポート/他アプリの反応でtimeout発生

修正方針:
  1. 現状の配線状況を確認（MIDI2Client.swift, PEManager.swift）
  2. MIDI2Client から PEManager へ sendStrategy を渡すよう修正
  3. fallbackStepTimeout の扱いも確認
---

---
2026-01-30 10:03
作業項目: Phase 0-1 完了 - peSendStrategy配線
実施内容:
  1. PEManager.init() に sendStrategy パラメータ追加
     - デフォルト値: .broadcast（後方互換性）
     - Sources/MIDI2PE/PEManager.swift:337

  2. MIDI2Client.init() から configuration.peSendStrategy を渡すよう修正
     - Sources/MIDI2Kit/HighLevelAPI/MIDI2Client.swift:177
     - destinationCacheTTL も configuration から渡すよう修正

  3. ビルド・テスト確認
     - swift build: 成功（警告は既存の deprecated API のみ）
     - swift test: 188テスト実行、6失敗（既存の問題、今回の修正とは無関係）

効果:
  - configuration.peSendStrategy = .fallback が PEManager に正しく反映されるようになった
  - broadcast によるタイムアウトの外的要因（他ポート/他アプリの反応）を抑制可能に
  - KORG Module等の非対称ルーティングデバイスでのタイムアウト切り分けが容易に

決定事項:
  - P0-1 完了 ✅

次のTODO:
  - P0-2: multiChunkTimeoutMultiplier適用
  - P0-3: print → logger統一
  - commit & push
---
