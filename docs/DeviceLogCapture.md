# デバイスログキャプチャ実装ガイド

XcodeBuildMCPを使用してiOS実機からログを取得する方法について説明します。

## 概要

XcodeBuildMCPの `start_device_log_cap` / `stop_device_log_cap` ツールを使用することで、実機で動作するアプリのログをリモートから取得できます。

## 重要な注意点

### ✅ キャプチャされるもの
- `print()` ステートメントの出力
- `stderr` / `stdout` への出力
- `NSLog()` の出力

### ❌ キャプチャされないもの
- `OSLog` (`Logger`) の出力
- `os_log()` の出力

OSLogはAppleの統合ログシステムに出力されるため、`start_device_log_cap`のコンソールキャプチャでは取得できません。

## 実装方法

### 1. アプリ側の実装

ログ出力関数で `print()` を使用します：

```swift
public func addLog(_ type: LogType, _ message: String) {
    // コンソール出力（デバイスログキャプチャ用）
    let typeStr: String
    switch type {
    case .info: typeStr = "INFO"
    case .error: typeStr = "ERROR"
    case .device: typeStr = "DEVICE"
    case .pe: typeStr = "PE"
    }
    print("[\(typeStr)] \(message)")
    
    // UI用のログ配列にも追加
    let entry = LogEntry(type: type, message: message)
    logs.insert(entry, at: 0)
}
```

### 2. XcodeBuildMCPでのログ取得手順

#### Step 1: セッション設定
```
session-set-defaults:
  workspacePath: /path/to/YourApp.xcworkspace
  scheme: YourApp
  deviceId: DEVICE-UDID
```

#### Step 2: ビルド・インストール
```
build_device
install_app_device(appPath: "/path/to/YourApp.app")
```

#### Step 3: ログキャプチャ開始
```
start_device_log_cap(bundleId: "com.example.YourApp")
```
→ Session IDが返される（例: `abc12345-...`）
→ アプリが自動的に起動される

#### Step 4: アプリを操作
デバイス上でアプリを操作してログを発生させる

#### Step 5: ログキャプチャ停止・取得
```
stop_device_log_cap(logSessionId: "abc12345-...")
```
→ キャプチャされたログが返される

## 出力例

```
--- Captured Logs ---

--- Device log capture for bundle ID: dev.midi2kit.MIDI2Explorer on device: 3217817C-... ---
[INFO] Started MIDI-CI discovery (MUID: MUID(0xCE04CD3))
[DEVICE] Discovered: KORG (374:4)
[DEVICE] Updated: KORG (374:4)
19:47:43  Enabling developer disk image services.
19:47:43  Acquired usage assertion.
Launched application with dev.midi2kit.MIDI2Explorer bundle identifier.
Waiting for the application to terminate...
App terminated due to signal 15.

--- Device log capture ended (exit code: 1) ---
```

## ログフォーマットの推奨

視認性を高めるため、以下のフォーマットを推奨：

```
[TYPE] メッセージ
```

タイプ例：
- `[INFO]` - 一般情報
- `[ERROR]` - エラー
- `[DEVICE]` - デバイス関連
- `[PE]` - Property Exchange
- `[TRACE]` - 詳細トレース

## トラブルシューティング

### ログが出力されない場合

1. **print()を使用しているか確認**
   - OSLogやLoggerではなく、print()を使用する

2. **アプリが正常に起動しているか確認**
   - `start_device_log_cap`はアプリを起動する
   - 起動に失敗するとログも出力されない

3. **Session IDが正しいか確認**
   - `stop_device_log_cap`には正しいSession IDを渡す

### exit code: 1 について

ログ取得後のメッセージで `exit code: 1` が表示されることがありますが、これは `stop_device_log_cap` がアプリを終了させたことを示しており、正常動作です。

## 関連ツール

| ツール | 説明 |
|--------|------|
| `start_device_log_cap` | ログキャプチャ開始＆アプリ起動 |
| `stop_device_log_cap` | ログキャプチャ停止＆ログ取得 |
| `launch_app_device` | アプリ起動（ログキャプチャなし） |
| `list_devices` | 接続デバイス一覧 |

## MIDI2Explorer固有の実装

MIDI2Explorerでは `ContentView.swift` の `AppState.addLog()` メソッドでログを出力しています：

```swift
// /MIDI2ExplorerPackage/Sources/MIDI2ExplorerFeature/ContentView.swift

public func addLog(_ type: LogEntry.LogType, _ message: String) {
    // Output to console for device log capture
    let typeStr: String
    switch type {
    case .info: typeStr = "INFO"
    case .error: typeStr = "ERROR"
    case .device: typeStr = "DEVICE"
    case .pe: typeStr = "PE"
    }
    print("[\(typeStr)] \(message)")
    
    let entry = LogEntry(type: type, message: message)
    logs.insert(entry, at: 0)
    if logs.count > 100 {
        logs.removeLast()
    }
}
```

---

*最終更新: 2026-01-26*
