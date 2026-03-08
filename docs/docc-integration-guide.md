# DocC 統合手順書

MIDI2Kit 開発リポジトリに DocC ドキュメントカタログを統合する手順。

## 前提条件

- Xcode 16.0+ / Swift 6.0+
- 開発リポジトリ: `hakaru/MIDI2Kit` (ソースコードあり)
- テンプレート: `MIDI2Kit-SDK/docs/docc-templates/`

## 現状 (2026-03-08 確認)

| 項目 | 状態 |
|------|------|
| swift-docc-plugin | 追加済み (from: "1.0.0") |
| Documentation.docc (MIDI2Kit) | 配置済み (集約型) |
| Documentation.docc (他モジュール) | 未配置 |
| チュートリアル (.tutorial) | 未作成 |
| GitHub Actions | 未配置 |
| GitHub Pages | 未設定 |

## Step 1: swift-docc-plugin のバージョンアップ

開発リポジトリの `Package.swift` の依存バージョンを更新:

```swift
// 変更前
.package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0")

// 変更後
.package(url: "https://github.com/apple/swift-docc-plugin", from: "1.4.3")
```

## Step 2: 既存カタログのシンボル整合

開発リポジトリの `Sources/MIDI2Kit/Documentation.docc/MIDI2Kit.md` を
SDK テンプレート (`docs/docc-templates/MIDI2Kit.docc/MIDI2Kit.md`) の内容で更新する。

テンプレートは 2026-03-08 時点の実コードベースと照合済み。
主な変更点:

- `ClientPreset`, `DestinationStrategy`, `WarmUpStrategy` を Topics に追加
- `MIDI2Error`, `CommunicationTrace` を追加
- `MockDevice`, `MockDevicePreset` を追加
- Responder API のシンボルを MIDI2PE モジュールに移動
- `MIDI2ConnectionPolicy` から `MatchRule` を削除 (ネスト型のため直接参照不可)

### 検証コマンド

```bash
# ビルドして未解決シンボルを検出
cd /path/to/MIDI2Kit
swift package --disable-sandbox generate-documentation --target MIDI2Kit 2>&1 | grep "warning:"
```

## Step 3: チュートリアルの配置

テンプレートからチュートリアルファイルをコピー:

```bash
cd /path/to/MIDI2Kit  # 開発リポジトリ

TEMPLATES="/path/to/MIDI2Kit-SDK/docs/docc-templates"

# チュートリアルファイル
cp "$TEMPLATES/MIDI2Kit.docc/DeviceDiscovery.tutorial" \
   Sources/MIDI2Kit/Documentation.docc/
cp "$TEMPLATES/MIDI2Kit.docc/PropertyExchange.tutorial" \
   Sources/MIDI2Kit/Documentation.docc/
cp "$TEMPLATES/MIDI2Kit.docc/CreatingResponder.tutorial" \
   Sources/MIDI2Kit/Documentation.docc/
```

## Step 4: チュートリアルのコードファイル作成

チュートリアル (`.tutorial`) は `@Code(file:)` でコードスニペットを参照する。
各ステップ用のコードファイルを `Resources/` ディレクトリに配置:

```
Sources/MIDI2Kit/Documentation.docc/
├── Resources/
│   ├── DeviceDiscovery-01.swift
│   ├── DeviceDiscovery-02.swift
│   ├── DeviceDiscovery-03.swift
│   ├── DeviceDiscovery-04.swift
│   ├── DeviceDiscovery-05.swift
│   ├── DeviceDiscovery-06.swift
│   ├── DeviceDiscovery-07.swift
│   ├── PE-01.swift
│   ├── PE-02.swift
│   ├── PE-03.swift
│   ├── PE-04.swift
│   ├── PE-05.swift
│   ├── PE-06.swift
│   ├── Responder-01.swift
│   ├── Responder-02.swift
│   ├── Responder-03.swift
│   ├── Responder-04.swift
│   ├── Responder-05.swift
│   └── Responder-06.swift
```

各ファイルにはそのステップ時点でのコード全体を記述する。
DocC Tutorial はステップごとに差分をハイライト表示する。

### コードスニペット例

**DeviceDiscovery-01.swift**:
```swift
import MIDI2Kit

@main
struct DeviceDiscoveryApp {
    static func main() async throws {
        let client = try MIDI2Client(name: "Discovery")
    }
}
```

**DeviceDiscovery-02.swift**:
```swift
import MIDI2Kit

@main
struct DeviceDiscoveryApp {
    static func main() async throws {
        var config = MIDI2ClientConfiguration()
        config.discoveryInterval = .seconds(5)
        config.deviceTimeout = .seconds(30)

        let client = try MIDI2Client(name: "Discovery", configuration: config)
    }
}
```

## Step 5: ローカル確認

```bash
# プレビューサーバー起動 (ブラウザで自動オープン)
swift package --disable-sandbox preview-documentation --target MIDI2Kit

# 静的サイト生成
swift package --disable-sandbox generate-documentation \
    --target MIDI2Kit \
    --output-path ./docs-output \
    --transform-for-static-hosting \
    --hosting-base-path docs
```

確認ポイント:
- [ ] 各モジュールのトップページが表示される
- [ ] Topics セクションのシンボルリンクが正しく解決される
- [ ] チュートリアルのコードステップが表示される
- [ ] 警告・エラーが出ていない

## Step 6: GitHub Actions 設定

開発リポジトリに `.github/workflows/docc.yml` を配置。
内容は `docs/docc-plan.md` の Section 5 を参照。

## Step 7: GitHub Pages 有効化

1. GitHub リポジトリ → Settings → Pages
2. Source: **GitHub Actions** を選択
3. main へのプッシュで自動デプロイが開始される

## Step 8: ソースコードのドキュメントコメント整備

DocC は `///` コメントから API リファレンスを自動生成する。
各 `public` 宣言に以下を追加:

```swift
/// 28-bit MIDI Unique Identifier used in MIDI-CI.
///
/// MUID is assigned during device discovery and uniquely identifies
/// a MIDI-CI Function Block within the MIDI network.
///
/// ```swift
/// let muid = MUID.random()
/// print(muid.value) // e.g., 0x01234567
/// ```
///
/// - Note: Valid range is 0x0000_0000 to 0x0FFF_FFFF (28 bits).
public struct MUID { ... }
```

優先順位:
1. `MIDI2Kit` モジュールの公開 API (`MIDI2Client`, `MIDI2Device` 等)
2. `MIDI2Core` の基盤型 (`MUID`, `DeviceIdentity` 等)
3. 他モジュールの主要型

## Step 9: 分散型カタログへの移行 (オプション)

現在の集約型 (全ドキュメントが MIDI2Kit の Documentation.docc 内) から、
各モジュール独自の Documentation.docc を持つ分散型に移行する場合:

```bash
cd /path/to/MIDI2Kit
TEMPLATES="/path/to/MIDI2Kit-SDK/docs/docc-templates"

# 各モジュールに Documentation.docc を作成
mkdir -p Sources/MIDI2Core/Documentation.docc
mkdir -p Sources/MIDI2CI/Documentation.docc
mkdir -p Sources/MIDI2PE/Documentation.docc
mkdir -p Sources/MIDI2Transport/Documentation.docc

# テンプレートからコピー
cp "$TEMPLATES/MIDI2Core.docc/MIDI2Core.md" Sources/MIDI2Core/Documentation.docc/
cp "$TEMPLATES/MIDI2Core.docc/UMPConversion.md" Sources/MIDI2Core/Documentation.docc/
cp "$TEMPLATES/MIDI2CI.docc/MIDI2CI.md" Sources/MIDI2CI/Documentation.docc/
cp "$TEMPLATES/MIDI2PE.docc/MIDI2PE.md" Sources/MIDI2PE/Documentation.docc/
cp "$TEMPLATES/MIDI2Transport.docc/MIDI2Transport.md" Sources/MIDI2Transport/Documentation.docc/

# MIDI2Kit の Documentation.docc からモジュール別ページを削除
rm Sources/MIDI2Kit/Documentation.docc/MIDI2Core.md
rm Sources/MIDI2Kit/Documentation.docc/MIDI2CI.md
rm Sources/MIDI2Kit/Documentation.docc/MIDI2PE.md
rm Sources/MIDI2Kit/Documentation.docc/MIDI2Transport.md
```

> **注意**: 分散型に移行すると、各モジュール独自にドキュメントをビルドできる利点があるが、
> シンボルのクロスモジュール参照が制限される。MIDI2Kit が全モジュールを re-export している
> 現在の構造では、集約型のままでも問題ない。

## チェックリスト

- [x] `swift-docc-plugin` を Package.swift に追加
- [ ] `swift-docc-plugin` のバージョンを 1.4.3 に更新
- [x] 基本的な Documentation.docc を MIDI2Kit に配置
- [ ] MIDI2Kit.md の Topics セクションを実コードと整合
- [ ] チュートリアル 3本を配置
- [ ] チュートリアル用コードスニペットを `Resources/` に作成
- [ ] `swift package preview-documentation` でローカル確認
- [ ] GitHub Actions ワークフロー配置
- [ ] GitHub Pages を有効化
- [ ] ソースコードのドキュメントコメント整備
