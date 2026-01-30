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

---
2026-01-30 10:13
作業項目: Phase 0 完了確認 & Phase 1 開始
Phase 0 完了サマリ:
  - P0-1: peSendStrategy配線 ✅
  - P0-2: multiChunkTimeoutMultiplier適用 ✅
  - P0-3: print → logger統一 ✅
  - 全コミット済み、push完了

Phase 1 開始: P1-4 RobustJSONDecoder 安全化
対象ファイル:
  - Sources/MIDI2Core/JSON/RobustJSONDecoder.swift

問題内容:
  1. escapeControlCharacters() が JSON文字列外の改行まで置換しうる
     - pretty JSON（整形済みJSON）を壊す可能性
     - 文字列リテラル内のみを対象にすべき
  2. removeComments() が "https://" の // をコメント扱いして壊す
     - lookbehind だけでは不十分
     - 文字列外のみを厳密に保証すべき

現状の影響:
  - 標準 decode が失敗した時だけなので被害は限定的
  - しかし JSON以外の原因の時にさらに壊して診断を難しくする

修正方針:
  1. RobustJSONDecoder の preprocess 処理を確認
  2. escapeControlCharacters と removeComments の実装を確認
  3. 安全な実装に修正（文字列リテラル内外を正しく判定）
---

---
2026-01-30 10:15
作業項目: Phase 1-4 完了 - RobustJSONDecoder 安全化
実施内容:
  1. removeComments() を状態機械で書き直し
     - 文字列リテラル内の // や /* */ を保護
     - 文字列境界を正しく追跡（エスケープも処理）
     - "https://example.com" 等のURLを壊さない
     - Sources/MIDI2Core/JSON/RobustJSONDecoder.swift:204

  2. escapeControlCharacters() を安全化
     - pretty JSON（複数行・インデント有り）を検出してスキップ
     - compact JSON のみ処理対象にする
     - 文字列リテラル内のみ制御文字をエスケープ
     - 構造的な改行・タブは保護
     - Sources/MIDI2Core/JSON/RobustJSONDecoder.swift:278

  3. ビルド・テスト確認
     - swift build: 成功
     - swift test: 188テスト、6失敗（既存の問題）

効果:
  - valid な pretty JSON を壊さなくなった
  - URL等を含むJSONを正しく処理できる
  - 誤診断（壊れたJSONをさらに壊す）を防止
  - デバッグが容易になった

決定事項:
  - P1-4 完了 ✅

次のTODO:
  - commit & push
  - P1-5: PEDecodingDiagnostics の外部公開
---

---
2026-01-30 10:16
作業項目: Phase 1-5 開始 - PEDecodingDiagnostics の外部公開
対象ファイル:
  - Sources/MIDI2Core/JSON/PEDecodingDiagnostics.swift
  - Sources/MIDI2PE/PEManager+RobustDecoding.swift
  - Sources/MIDI2PE/PEManager.swift

問題内容:
  1. PEDecodingDiagnostics のUsageに `lastDecodingDiagnostics` プロパティがあるが実装されていない
  2. decodeResponse() 内で diagnostics を生成しているが throw 時に捨てている
  3. ユーザーがデコードエラーの詳細情報にアクセスできない

修正方針:
  1. PEManager に lastDecodingDiagnostics プロパティ追加
  2. デコード時に diagnostics を保存
  3. エラーに diagnostics を付帯させるか、lastDecodingDiagnostics で取得可能にする
---

---
2026-01-30 10:19
作業項目: Phase 1-5 完了 - PEDecodingDiagnostics の外部公開
実施内容:
  1. PEManager に lastDecodingDiagnostics プロパティ追加
     - nonisolated(unsafe) internal storage for synchronous access
     - public computed property for external access
     - Sources/MIDI2PE/PEManager.swift:293

  2. decodeResponse() で diagnostics を保存するよう修正
     - 成功時（preprocessed あり）: diagnostics を保存
     - 成功時（preprocessed なし）: diagnostics をクリア
     - 失敗時: diagnostics を保存してから throw
     - Sources/MIDI2PE/PEManager+RobustDecoding.swift:18,59,72

  3. saveDiagnostics() ヘルパーメソッド追加
     - 同期的に diagnostics を保存（throwing context から呼べる）
     - Sources/MIDI2PE/PEManager+RobustDecoding.swift:18

  4. ビルド確認
     - swift build: 成功（警告は既存の deprecated API のみ）

効果:
  - ユーザーが await peManager.lastDecodingDiagnostics で診断情報にアクセス可能に
  - デコードエラー時の詳細情報（raw data, preprocessed data, parse error等）が取得できる
  - Usage例が実装と一致するようになった
  - デバッグが大幅に容易になった

決定事項:
  - P1-5 完了 ✅
  - Phase 1 (P1タスク) 全完了 ✅

次のTODO:
  - commit & push
  - Phase 0 & Phase 1 完了サマリ
  - 次のステップ検討（P2タスク or Phase 5-1復帰）
---
