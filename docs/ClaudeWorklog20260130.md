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

---
2026-01-30 10:04
作業項目: Phase 0-2 開始 - multiChunkTimeoutMultiplier適用
対象ファイル:
  - Sources/MIDI2Kit/HighLevelAPI/MIDI2Client.swift
  - Sources/MIDI2PE/PEManager.swift

問題内容:
  - MIDI2Client.getResourceList() で timeout を計算しているが peManager に渡していない
  - PEManager 側のデフォルトtimeoutのままになる
  - 表面上のエラー変換やログには反映されても、実際の待ち時間が伸びていない
  - 結果: マルチチャンクリクエストがタイムアウトしやすい

修正方針:
  1. MIDI2Client 各メソッドでの timeout 計算箇所を確認
  2. PEManager のメソッドが timeout パラメータを受け取れるか確認
  3. 計算した timeout を実際の PEManager 呼び出しに渡す
---

---
2026-01-30 10:06
作業項目: Phase 0-2 完了 - multiChunkTimeoutMultiplier適用
実施内容:
  1. PEManager.getResourceList() に timeout パラメータ追加
     - getResourceList(from muid:, timeout:, maxRetries:)
     - getResourceList(from device:, timeout:, maxRetries:)
     - 内部の get() 呼び出しに timeout を渡すよう修正
     - Sources/MIDI2PE/PEManager.swift:738,1001,1051

  2. MIDI2Client.getResourceList() から計算済み timeout を渡すよう修正
     - timeout = peTimeout * multiChunkTimeoutMultiplier
     - 初回リクエストとフォールバック両方に適用
     - maxRetries も configuration から渡すよう統一
     - Sources/MIDI2Kit/HighLevelAPI/MIDI2Client.swift:473,495

  3. ビルド・テスト確認
     - swift build: 成功
     - swift test: 188テスト、6失敗（既存の問題）

効果:
  - multiChunkTimeoutMultiplier が実際の PEリクエストに反映されるようになった
  - ResourceList等のマルチチャンクリクエストに十分な待ち時間が確保される
  - タイムアウト設定と実際の挙動が一致し、デバッグが容易に

決定事項:
  - P0-2 完了 ✅

次のTODO:
  - P0-3: print → logger統一
  - commit & push
---

---
2026-01-30 10:07
作業項目: Phase 0-3 開始 - print → logger統一
対象ファイル:
  - Sources/MIDI2PE/PEChunkAssembler.swift

問題内容:
  - PEChunkAssembler.addChunk() が print() を大量に出す
  - アプリ利用時にノイズになり、ログ収集も困る
  - MIDI2Logger 経由に統一されていない

修正方針:
  1. PEChunkAssembler で print() を使用している箇所を特定
  2. logger.debug() または logger.midi2Debug() に置き換え
  3. verbose フラグで制御可能にする（必要に応じて）
---

---
2026-01-30 10:12
作業項目: Phase 0-3 完了 - print → logger統一
実施内容:
  1. PEChunkAssembler に logger プロパティ追加
     - import MIDI2Core 追加
     - init(timeout:, logger:) でロガー受け取り
     - デフォルト: NullMIDI2Logger()（後方互換性）
     - Sources/MIDI2PE/PEChunkAssembler.swift:8,80

  2. 全 print() を logger 呼び出しに置換（10箇所）
     - logger.debug() × 9箇所（デバッグ情報）
     - logger.error() × 1箇所（エラー：pending state disappeared）
     - カテゴリ: "MIDI2PE"

  3. PEChunkAssembler のインスタンス生成箇所を更新
     - PETransactionManager.swift:239 - logger 渡すよう修正
     - PENotifyAssemblyManager.swift:54 - logger 渡すよう修正

  4. ビルド・テスト確認
     - swift package clean && swift test
     - 188テスト、6失敗（既存の問題）

効果:
  - print() デバッグが logger 経由に統一された
  - アプリ利用時にノイズにならず、ログレベルで制御可能に
  - OSLog 等の構造化ログ出力に統合可能
  - 本番環境でデバッグログを無効化できる

決定事項:
  - P0-3 完了 ✅
  - P0 (Critical Fixes) 全完了 ✅

次のTODO:
  - commit & push
  - P1タスク検討（RobustJSONDecoder, PEDecodingDiagnostics）
---
