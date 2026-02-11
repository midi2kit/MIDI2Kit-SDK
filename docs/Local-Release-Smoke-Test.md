# Local Release Smoke Test

GitHub Actions が使えない環境でも、公開予定バージョンの `MIDI2Kit-SDK` を利用側プロジェクトとして実際に解決・ビルド・実行できることをローカルで検証する手順です。

## 目的

- リリースタグを利用側依存として解決できることを確認する
- 主要な互換性ポイント（legacy JSON / KORG bankPC / X-ProgramEdit）を実行時に確認する
- `README.md` のみではなく、運用手順を `docs/` 配下に固定化する

## 前提

- macOS
- Xcode 16+ / Swift 6+
- `git` と `swift` コマンドが使えること

## 実行手順

```bash
git clone https://github.com/midi2kit/MIDI2Kit-SDK.git
cd MIDI2Kit-SDK
chmod +x Scripts/consumer-smoke-local.sh
Scripts/consumer-smoke-local.sh 1.0.14
```

`v` プレフィックス付きタグ、または別URL指定も可能です。

```bash
Scripts/consumer-smoke-local.sh v1.0.14 https://github.com/midi2kit/MIDI2Kit-SDK.git
```

## 成功条件

実行ログの最後に以下が出れば成功です。

```text
OK: MIDI2Kit-SDK consumer smoke passed
```

## 失敗時チェック

- `Could not resolve host: github.com` が出る場合: ネットワーク接続を確認
- `Operation not permitted` が出る場合: 実行ユーザーのキャッシュ/書き込み権限を確認
- バージョン解決失敗の場合: タグ名と公開状態（例: `1.0.14`）を確認

## リリース運用での使い方

1. リリースタグ作成前後に本スクリプトを実行
2. 成功ログを確認
3. 必要なら同内容をリリースノートに添付

