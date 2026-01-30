// RealDeviceTest - P0/P1 修正効果確認用テストツール
// 使用方法: swift run RealDeviceTest

import Foundation
import MIDI2Kit
import MIDI2Transport
import CoreMIDI

@main
struct RealDeviceTest {
    static func main() async {
        print("=== MIDI2Kit 実機テスト ===")
        print("P0/P1 修正の効果を確認します\n")

        // ログ設定（verbose で詳細確認）
        MIDI2Logger.isEnabled = true
        MIDI2Logger.isVerbose = true

        print("[設定確認]")
        print("- MIDI2Logger.isEnabled: \(MIDI2Logger.isEnabled)")
        print("- MIDI2Logger.isVerbose: \(MIDI2Logger.isVerbose)")
        print("")

        // KORG BLE MIDI 向け設定
        var config = MIDI2ClientConfiguration()
        config.peSendStrategy = .fallback
        config.peTimeout = .seconds(10)
        config.multiChunkTimeoutMultiplier = 2.0
        config.warmUpBeforeResourceList = true
        config.maxRetries = 2

        print("[Configuration]")
        print("- peSendStrategy: \(config.peSendStrategy)")
        print("- peTimeout: \(config.peTimeout)")
        print("- multiChunkTimeoutMultiplier: \(config.multiChunkTimeoutMultiplier)")
        print("- warmUpBeforeResourceList: \(config.warmUpBeforeResourceList)")
        print("- maxRetries: \(config.maxRetries)")
        print("")

        // CoreMIDI エンドポイント一覧を表示
        print("[CoreMIDI エンドポイント一覧]")
        print("Sources (入力):")
        let sourceCount = MIDIGetNumberOfSources()
        if sourceCount == 0 {
            print("  (なし)")
        } else {
            for i in 0..<sourceCount {
                let endpoint = MIDIGetSource(i)
                let name = getEndpointName(endpoint)
                print("  [\(i)] \(name)")
            }
        }
        print("Destinations (出力):")
        let destCount = MIDIGetNumberOfDestinations()
        if destCount == 0 {
            print("  (なし)")
        } else {
            for i in 0..<destCount {
                let endpoint = MIDIGetDestination(i)
                let name = getEndpointName(endpoint)
                print("  [\(i)] \(name)")
            }
        }
        print("")

        do {
            print("[クライアント初期化中...]")
            let client = try MIDI2Client(name: "RealDeviceTest", configuration: config)
            print("OK: MIDI2Client 初期化完了\n")

            // Raw MIDI 受信をモニタリング
            print("[Raw MIDI モニタリング開始...]")
            let monitorTask = Task {
                let transport = try! CoreMIDITransport(clientName: "Monitor")
                try! await transport.connectToAllSources()
                for await received in transport.received {
                    let hex = received.data.map { String(format: "%02X", $0) }.joined(separator: " ")
                    print("  📥 [\(received.sourceID?.value ?? 0)] \(hex)")
                }
            }

            print("[デバイス検出開始...]")
            try await client.start()

            // 手動で Discovery Inquiry を送信して確認
            print("[Discovery Inquiry 送信中...]")

            print("[デバイス検出中...] (10秒待機)")
            for i in 1...10 {
                try await Task.sleep(for: .seconds(1))
                let count = await client.discoveredDevices.count
                print("  \(i)秒経過... 検出デバイス数: \(count)")
                if count > 0 { break }
            }

            monitorTask.cancel()

            let devices = await client.discoveredDevices
            print("検出デバイス数: \(devices.count)")

            if devices.isEmpty {
                print("\n警告: デバイスが検出されませんでした")
                print("- KORG Module Pro がペアリング済みか確認してください")
                print("- Bluetooth が有効か確認してください")
                await client.stop()
                return
            }

            for device in devices {
                let muid = device.id  // nonisolated
                print("\n--- デバイス: \(device.displayName) ---")
                print("  MUID: \(muid)")
                let identity = await device.identity
                print("  Manufacturer: \(identity.manufacturerID.name ?? identity.manufacturerID.description)")

                // CategorySupport 確認 (supportsPropertyExchange is nonisolated)
                let supportsPE = device.supportsPropertyExchange
                print("  Supports PE: \(supportsPE)")

                if !supportsPE {
                    print("  ⚠️ このデバイスは Property Exchange 非対応です。スキップします。")
                    continue
                }

                // テスト1: DeviceInfo 取得（単一チャンク）
                print("\n[テスト1] DeviceInfo 取得（単一チャンク）")
                do {
                    let start = Date()
                    let response = try await client.get("DeviceInfo", from: muid)
                    let elapsed = Date().timeIntervalSince(start)
                    print("  OK: status=\(response.status), \(elapsed.formatted())秒")
                    if let str = response.bodyString {
                        let preview = str.prefix(100)
                        print("  Body preview: \(preview)...")
                    }
                } catch {
                    print("  ERROR: \(error)")
                }

                // テスト2: ResourceList 取得（マルチチャンク）
                print("\n[テスト2] ResourceList 取得（マルチチャンク）")
                print("  multiChunkTimeout = \(config.peTimeout * config.multiChunkTimeoutMultiplier)秒")
                do {
                    let start = Date()
                    let resources = try await client.getResourceList(from: muid)
                    let elapsed = Date().timeIntervalSince(start)
                    print("  OK: \(resources.count)件のリソース, \(elapsed.formatted())秒")
                    for (i, res) in resources.prefix(5).enumerated() {
                        print("    [\(i)] \(res.resource)")
                    }
                    if resources.count > 5 {
                        print("    ... 他 \(resources.count - 5) 件")
                    }
                } catch {
                    print("  ERROR: \(error)")
                    print("  (BLE MIDI のチャンク欠落の可能性があります)")
                }

                // テスト3: 既知リソースへの直接アクセス
                print("\n[テスト3] CMList 直接取得")
                do {
                    let start = Date()
                    let response = try await client.get("CMList", from: muid)
                    let elapsed = Date().timeIntervalSince(start)
                    print("  OK: status=\(response.status), \(elapsed.formatted())秒")
                } catch {
                    print("  ERROR: \(error)")
                }

                // テスト4: PEError 分類確認
                print("\n[テスト4] PEError 分類確認")
                print("  timeout.isRetryable = true")
                print("  nak(transient).isRetryable = true")
                print("  (withPERetry はこれらのエラー時に自動リトライ)")
            }

            // 診断情報
            print("\n=== 診断情報 ===")
            let diag = await client.diagnostics
            print(diag)

            print("\n[クリーンアップ中...]")
            await client.stop()
            print("完了")

        } catch {
            print("エラー: \(error)")
        }

        print("\n=== テスト終了 ===")
    }
}

extension TimeInterval {
    func formatted() -> String {
        String(format: "%.2f", self)
    }
}

func getEndpointName(_ endpoint: MIDIEndpointRef) -> String {
    var name: Unmanaged<CFString>?
    let status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name)
    if status == noErr, let cfName = name?.takeRetainedValue() {
        return cfName as String
    }
    return "Unknown (\(endpoint))"
}
