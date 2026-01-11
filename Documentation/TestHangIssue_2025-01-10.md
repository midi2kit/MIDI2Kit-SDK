# テストスイート ハング問題: 調査と解決

**発生日**: 2025年1月10日  
**解決日**: 2025年1月10日  
**対象**: MIDI2Kit テストスイート

---

## 1. 問題の概要

### 症状
- `swift test` 実行後、全てのテストが **PASS** と表示されるにもかかわらず、プロセスが終了しない
- CPU使用率は0%でハング状態
- `Test run with X tests passed after X seconds` の最終サマリーが表示されない
- `Ctrl+C` で強制終了しない限りプロセスが残り続ける

### 影響範囲
- PEManagerTests
- CIManagerTests
- PETransactionManagerTests

---

## 2. 根本原因

### 原因1: AsyncStreamのキャンセル非対応

**問題点**: Swift の `AsyncStream` は cooperative cancellation に対応していない。`Task.cancel()` を呼んでも、`for await` ループは自動的に終了しない。

```swift
// 問題のあるコード
receiveTask = Task {
    for await received in transport.received {
        // Task.cancel() を呼んでも、このループは終了しない
        await self.handleReceived(received)
    }
}
```

### 原因2: MockMIDITransportのストリーム終了処理不足

**問題点**: テスト用の `MockMIDITransport` は `AsyncStream.Continuation` を保持しているが、テスト終了時に `finish()` を呼んでいなかった。

### 原因3: stopReceiving()の不完全な実装

**問題点**: `stopReceiving()` がタスクをキャンセルするだけで、ストリームを終了させていなかった。

---

## 3. 解決策

### 3.1 Task.isCancelledチェックの追加

**全ての `for await` ループ内でキャンセルチェックを追加**

```swift
// 修正後のコード
receiveTask = Task { [weak self] in
    guard let self = self else { return }
    
    for await received in transport.received {
        // キャンセルチェックを追加
        if Task.isCancelled { break }
        await self.handleReceived(received.data)
    }
}
```

**適用箇所**:
- `PEManager.startReceiving()`
- `CIManager.start()` - receiveTask
- `CIManager.runTimeoutChecker()`
- `CIManager.startDiscovery()`

### 3.2 MockMIDITransportに shutdown() メソッド追加

```swift
public actor MockMIDITransport: MIDITransport {
    private var receivedContinuation: AsyncStream<MIDIReceivedData>.Continuation?
    private var setupChangedContinuation: AsyncStream<Void>.Continuation?
    
    /// Shutdown the transport and finish all streams
    public func shutdown() {
        receivedContinuation?.finish()
        setupChangedContinuation?.finish()
        receivedContinuation = nil
        setupChangedContinuation = nil
    }
}
```

### 3.3 テストでのクリーンアップパターン

```swift
@Test("Example test")
func exampleTest() async throws {
    let transport = MockMIDITransport()
    let manager = PEManager(transport: transport, sourceMUID: testMUID)
    
    await manager.startReceiving()
    
    // ... テストコード ...
    
    // 必ずこの順序でクリーンアップ
    await manager.stopReceiving()
    await transport.shutdown()  // ストリームを終了
}
```

---

## 4. 実装の詳細

### PEManager.swift の変更

```swift
public func startReceiving() async {
    guard receiveTask == nil else { return }
    
    // Transaction manager の状態をリセット
    await transactionManager.reset()
    
    receiveTask = Task { [weak self] in
        guard let self = self else { return }
        
        for await received in transport.received {
            // ★ キャンセルチェックを追加
            if Task.isCancelled { break }
            await self.handleReceived(received.data)
        }
    }
}

public func stopReceiving() async {
    receiveTask?.cancel()
    receiveTask = nil
    
    // タイムアウトタスクをキャンセル
    for (_, task) in timeoutTasks {
        task.cancel()
    }
    timeoutTasks.removeAll()
    
    // 待機中のcontinuationsを解放
    for continuation in pendingContinuations.values {
        continuation.resume(throwing: PEError.cancelled)
    }
    pendingContinuations.removeAll()
    
    // ... 他のクリーンアップ ...
}
```

### CIManager.swift の変更

```swift
public func start() async throws {
    guard !isRunning else { return }
    isRunning = true
    
    receiveTask = Task { [weak self] in
        guard let self else { return }
        for await received in transport.received {
            // ★ キャンセルチェックを追加
            if Task.isCancelled { break }
            await self.handleReceived(received)
        }
    }
    
    timeoutTask = Task { [weak self] in
        guard let self else { return }
        await self.runTimeoutChecker()
    }
    
    // ...
}

private func runTimeoutChecker() async {
    while !Task.isCancelled && isRunning {  // ★ 両方をチェック
        // ...
        do {
            try await Task.sleep(for: .seconds(1))
        } catch {
            break  // キャンセル時は即座に終了
        }
    }
}
```

---

## 5. デバッグ手法

### ハングの検出

```bash
# プロセスの状態確認
ps aux | grep swift

# CPU使用率が0%で長時間続く場合はハング
```

### 問題箇所の特定

```bash
# 特定のテストスイートだけ実行
swift test --filter "PEManager"

# シリアル実行で競合を除外
swift test --no-parallel

# 新しいビルドキャッシュで実行
swift test --scratch-path /tmp/midi2kit-build
```

### スレッド状態の確認

```bash
# プロセスにアタッチしてスタックトレースを取得
lldb -p <PID>
(lldb) bt all
```

---

## 6. 今後の課題

### 残存する潜在的問題

1. **並列テスト時の競合**
   - `--no-parallel` では成功するが、並列実行時にまれにハングする
   - ActorとAsyncStreamの相互作用に起因する可能性

2. **大量リクエスト時の待機キュー**
   - Per-device inflight limiting (デフォルト: 2) により、
     多数の同時リクエストが待機キューに入る
   - テスト時のアサーションを調整済み

### 推奨事項

1. **テストでは常に `shutdown()` を呼ぶ**
   - `defer` を使用してクリーンアップを保証

2. **タイムアウトを短く設定**
   - テスト用のタイムアウトは 100ms 〜 500ms に

3. **CI/CDでのタイムアウト設定**
   - テストスイート全体に10分のタイムアウトを設定

---

## 7. 関連ファイル

| ファイル | 変更内容 |
|---------|---------|
| `Sources/MIDI2PE/PEManager.swift` | Task.isCancelledチェック追加 |
| `Sources/MIDI2CI/CIManager.swift` | Task.isCancelledチェック追加 |
| `Sources/MIDI2Transport/MockMIDITransport.swift` | shutdown()メソッド追加 |
| `Tests/MIDI2KitTests/PEManagerTests.swift` | クリーンアップ順序修正 |
| `Tests/MIDI2KitTests/CIManagerTests.swift` | クリーンアップ順序修正 |

---

## 8. 参考資料

- [Swift Concurrency: AsyncStream](https://developer.apple.com/documentation/swift/asyncstream)
- [Task Cancellation](https://developer.apple.com/documentation/swift/task/iscancelled)
- [Cooperative Cancellation in Swift](https://www.swift.org/documentation/articles/cooperative-cancellation.html)
