# Claude Worklog 2026-02-07

## 継続タスク
- リリース自動化の検討

---
2026-02-07 00:12
作業項目: リリース自動化Hook検討
追加機能の説明:
  ユーザーから以下の自動化要望:
  1. hakaru/MIDI2Kit でリリース時 → midi2kit/MIDI2Kit-SDK へXCFramework展開
  2. 展開後の検証（チェックサム、API確認）
  3. midi2kit/midi2kit.github.io のドキュメント更新

  GitHub Actions vs Claude Code Hooks の選択肢を調査中。
決定事項:
  - 現状の手動プロセスを調査して自動化範囲を特定
次のTODO:
  - 既存のCI/CD設定を確認
  - midi2kit.github.io の構成を確認
  - 自動化方針を提案
---

---
2026-02-07 00:15
作業項目: リリース自動化方針の提案
追加機能の説明:
  CI/CD調査結果に基づき、自動化方針を提案。
  現状: ci.yml(swift test のみ)、build-xcframework.sh(ローカル)、SDK/docsは全手動
  調査結果:
  - MIDI2Kit: .github/workflows/ci.yml = swift build + swift test + iOS sim build
  - MIDI2Kit-SDK: GitHub Actionsなし
  - midi2kit.github.io: 静的HTML、自動化なし
  - build-xcframework.sh: 3プラットフォーム×5モジュール → dist/
  方針提案:
  - Option A: GitHub Actions (MIDI2Kit側にrelease.ymlワークフロー)
    - タグプッシュで自動トリガー
    - macOS runnerでXCFramework生成
    - MIDI2Kit-SDKにcross-repo dispatch
    - midi2kit.github.io更新
  - Option B: ローカルリリーススクリプト
    - シェルスクリプト1発で全工程実行
    - 手動トリガーだが自動化された手順
  - Option C: Claude Code Hooks
    - コミット/タグ時にHookでスクリプト起動
決定事項:
  - 3つの選択肢をユーザーに提示
次のTODO:
  - ユーザーの選択に基づき実装
---

---
2026-02-07 00:18
作業項目: GitHub Actions リリース自動化 設計・実装
追加機能の説明:
  ユーザーがGitHub Actionsを選択。以下の自動化パイプラインを設計・実装する:
  1. MIDI2Kit: release.yml — タグpushトリガー → テスト → XCFramework生成 → SDK展開
  2. MIDI2Kit-SDK: update-sdk.yml — repository_dispatch受信 → Package.swift更新 → リリース作成
  3. midi2kit.github.io: update-docs.yml — repository_dispatch受信 → CHANGELOG更新
  必要なもの:
  - cross-repo dispatch用のGitHub PAT (RELEASE_PAT secret)
  - build-xcframework.shの改修（CI対応）
  - macOS runner (macos-14)
決定事項:
  - GitHub Actions (Option A) で進める
  - 3リポジトリにワークフロー配置
次のTODO:
  - 既存build-xcframework.shの内容確認
  - 各ワークフロー作成
  - PAT設定手順の説明
---

---
2026-02-07 00:27
作業項目: GitHub Actions リリース自動化パイプライン実装
追加機能の説明:
  3つのリポジトリに GitHub Actions ワークフローを作成:
  1. hakaru/MIDI2Kit/.github/workflows/release.yml (新規)
     - v*タグpushトリガー
     - 4ジョブ構成: test → build-xcframework → create-sdk-release → dispatch-updates
     - テスト実行、XCFramework生成(既存スクリプト利用)、SDK側リリース作成、dispatch送信
     - concurrency制御で並行リリース防止
     - checksumをjob outputsで伝搬
  2. midi2kit/MIDI2Kit-SDK/.github/workflows/update-package.yml (新規)
     - repository_dispatch (update-package) トリガー
     - Package.swiftのURL・checksum自動更新(sed)
     - CHANGELOG.md自動エントリ追加
     - 検証ステップ(5URLカウント確認)
  3. midi2kit/midi2kit.github.io/.github/workflows/update-docs.yml (新規)
     - repository_dispatch (update-docs) トリガー
     - index.htmlのヒーローバッジ・Quick Startバージョン更新
     - 変更なし時はコミットスキップ
決定事項:
  - cross-repo操作にはRELEASE_PAT secretを使用
  - build-xcframework.shは変更不要(CI上でそのまま動作)
  - create-sdk-releaseとdispatch-updatesはubuntu-latest(macOS不要)
  - Package.swiftのchecksum更新はsedの範囲指定で正確にマッチ
次のTODO:
  - RELEASE_PAT を hakaru/MIDI2Kit の Secrets に登録(手動)
  - テスト用タグ v0.0.1-test で発火テスト
  - 必要に応じてbuild-xcframework.shのCI対応修正
---

---
2026-02-07 00:32
作業項目: RELEASE_PAT 設定手順の詳細説明
追加機能の説明:
  ユーザーからRELEASE_PATの手動設定手順の詳細を求められた。
  Fine-grained PAT の作成手順とSecrets登録手順を説明。
決定事項:
  なし
次のTODO:
  - ユーザーがPAT設定を完了後、テスト用タグで発火テスト
---

---
2026-02-07 00:45
作業項目: ワークフロー未発火の原因調査
追加機能の説明:
  release.ymlがローカルにあるだけでリモートにpushされていなかった。
  GitHub Actionsはリモート上のワークフローファイルを読むため発火しない。
決定事項:
  - release.ymlをmainにpushしてからタグを打ち直す必要がある
次のTODO:
  - release.ymlをコミット＆push
  - テスト用タグを削除して打ち直し
---
