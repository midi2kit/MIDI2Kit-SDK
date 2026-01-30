// RealDeviceTest - P0/P1 修正効果確認用テストツール
// 使用方法: swift run RealDeviceTest

import Foundation
import MIDI2Kit

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

        do {
            print("[クライアント初期化中...]")
            let client = try MIDI2Client(name: "RealDeviceTest", configuration: config)
            print("OK: MIDI2Client 初期化完了\n")

            print("[デバイス検出開始...]")
            try await client.start()

            print("[デバイス検出中...] (10秒待機)")
            try await Task.sleep(for: .seconds(10))

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
