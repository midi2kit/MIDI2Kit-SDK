# RobustJSONDecoder

耐障害性のあるJSONデコーダー。組み込みMIDIデバイスからの非標準JSONレスポンスを処理するために設計されています。

## 背景

多くのMIDIデバイス（特にKORGなど）は、厳密なJSONパーサーでは拒否される非標準的なJSONを返します：

| 問題 | 例 | 修正後 |
|------|-----|--------|
| 末尾カンマ | `{"a": 1, "b": 2,}` | `{"a": 1, "b": 2}` |
| シングルクォート | `{'name': 'value'}` | `{"name": "value"}` |
| コメント | `// comment` or `/* */` | (削除) |
| 制御文字 | 未エスケープの改行等 | `\n`, `\t` |
| 未引用キー | `{key: "value"}` | `{"key": "value"}` |

## 使用方法

### 基本的な使用

```swift
import MIDI2Core

let decoder = RobustJSONDecoder()

// 標準使用 - 必要に応じて自動修復
let deviceInfo: PEDeviceInfo = try decoder.decode(PEDeviceInfo.self, from: data)
```

### 診断付きデコード

デバッグ時に詳細情報が必要な場合：

```swift
let result = decoder.decodeWithDiagnostics(PEDeviceInfo.self, from: data)

switch result {
case .success(let value, let wasFixed):
    if wasFixed {
        print("⚠️ JSON was automatically fixed before decoding")
    }
    // valueを使用

case .failure(let error, let rawData, let attemptedFix):
    print("❌ Decode failed: \(error)")
    print("Raw data hex: \(rawData.hexDumpPreview)")
    if let fixed = attemptedFix {
        print("Attempted fix: \(String(data: fixed, encoding: .utf8) ?? "N/A")")
    }
}
```

### PEResponseとの統合

```swift
// PEResponse便利メソッド
let response = try await peManager.get("DeviceInfo", from: device)
let deviceInfo = try response.decodeBody(PEDeviceInfo.self)

// または診断付き
let result = response.decodeBodyWithDiagnostics(PEDeviceInfo.self)
```

## API リファレンス

### RobustJSONDecoder

```swift
public struct RobustJSONDecoder {
    /// 前処理を有効にするかどうか（デフォルト: true）
    public var enablePreprocessing: Bool
    
    /// オプションのロガー
    public var logger: ((String) -> Void)?
    
    /// デコード（自動修復付き）
    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T
    
    /// 診断付きデコード
    public func decodeWithDiagnostics<T: Decodable>(
        _ type: T.Type, 
        from data: Data
    ) -> DecodeResult<T>
    
    /// 前処理のみ実行
    public func preprocess(_ data: Data) -> (Data, Bool)
}
```

### DecodeResult

```swift
public enum DecodeResult<T> {
    /// 成功 - wasFixedは前処理が適用されたかどうか
    case success(value: T, wasFixed: Bool)
    
    /// 失敗 - 元データと試行した修正データを含む
    case failure(error: Error, rawData: Data, attemptedFix: Data?)
    
    /// 成功時の値を取得
    public var value: T? { ... }
    
    /// 成功かどうか
    public var isSuccess: Bool { ... }
}
```

### Data拡張

```swift
extension Data {
    /// 16進ダンププレビュー（最初の64バイト）
    public var hexDumpPreview: String
    
    /// 完全な16進ダンプ
    public var hexDump: String
    
    /// xxd形式のフォーマット済み16進ダンプ
    public func hexDumpFormatted(bytesPerLine: Int = 16) -> String
}
```

## 前処理の詳細

### 1. コメント除去

```
// 入力
{"name": "value" /* comment */}

// 出力
{"name": "value" }
```

### 2. 末尾カンマ修正

```
// 入力
{"items": [1, 2, 3,], "name": "test",}

// 出力
{"items": [1, 2, 3], "name": "test"}
```

### 3. シングルクォート変換

```
// 入力
{'manufacturer': 'KORG', 'model': 'Module'}

// 出力
{"manufacturer": "KORG", "model": "Module"}
```

### 4. 制御文字エスケープ

文字列内の生の制御文字（タブ、改行等）をエスケープシーケンスに変換します。

### 5. 未引用キー修正

```
// 入力
{name: "value", count: 42}

// 出力
{"name": "value", "count": 42}
```

## エラーハンドリング

### RobustJSONError

前処理後もデコードが失敗した場合：

```swift
public enum RobustJSONError: Error {
    case decodingFailed(
        originalError: Error,      // 最初のデコードエラー
        preprocessedError: Error,  // 前処理後のデコードエラー
        rawData: Data,             // 元データ
        fixedData: Data            // 修正を試みたデータ
    )
}
```

## 設計上の考慮事項

### なぜ前処理アプローチか

1. **後方互換性**: 標準的なJSONは変更なく通過
2. **透明性**: `wasFixed`フラグで修正の有無を通知
3. **デバッグ可能性**: 元データと修正データの両方を保持
4. **段階的対応**: まず標準パースを試み、失敗時のみ前処理

### パフォーマンス

- 標準JSONは追加オーバーヘッドなしでパース
- 前処理は失敗時のみ実行
- 文字列操作は正規表現を使用（複雑なパターンに対応）

## 関連ファイル

- `Sources/MIDI2Core/JSON/RobustJSONDecoder.swift` - 実装
- `Sources/MIDI2Core/JSON/PEDecodingDiagnostics.swift` - 診断情報
- `Sources/MIDI2PE/PEManager+RobustDecoding.swift` - PEManager統合
