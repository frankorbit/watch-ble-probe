import AccessorySetupKit
import Combine
import CoreBluetooth
import SwiftUI

@main
struct HIDSetupApp: App {
    @StateObject private var setup = HIDAccessorySetup()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                VStack(alignment: .leading, spacing: 12) {
                    Text(setup.status).font(.headline)
                    Text("通过系统配件选择器配置 Watch BLE 鼠标；不接收或转发鼠标事件。")
                        .font(.caption)
                    Button("配置 Watch 鼠标") { setup.showPicker() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!setup.ready || setup.pickerVisible)
                    Text("手表保持 HID 探针前台。添加成功后，仍需检查手表输入订阅及 iPhone 指针。")
                        .font(.caption)
                    SetupLogView(log: setup.log)
                }
                .padding()
                .navigationTitle("HID 系统设置探针")
            }
            .task { setup.activate() }
            .onChange(of: scenePhase) { _, phase in
                UIApplication.shared.isIdleTimerDisabled = phase == .active
                setup.log.record("scene.changed", ["phase": "\(phase)"])
            }
        }
    }
}

@MainActor
private final class HIDAccessorySetup: ObservableObject {
    let log = ProbeLog(role: "iphone-setup")
    @Published private(set) var status = "正在启用系统配件会话"
    @Published private(set) var ready = false
    @Published private(set) var pickerVisible = false
    private var session: ASAccessorySession?

    func activate() {
        guard session == nil else { return }
        UIApplication.shared.isIdleTimerDisabled = true
        let session = ASAccessorySession()
        self.session = session
        log.record("setup.activate")
        session.activate(on: .main) { [weak self] event in
            Task { @MainActor [weak self] in self?.handle(event) }
        }
    }

    func showPicker() {
        guard ready, !pickerVisible, let session else { return }
        guard let image = UIImage(systemName: "applewatch") else {
            status = "无法创建配件图片"
            log.record("setup.image.failed")
            return
        }
        let descriptor = ASDiscoveryDescriptor()
        descriptor.bluetoothServiceUUID = ProbeProtocol.hidDiscovery
        descriptor.bluetoothNameSubstring = "WBLEMouse"
        descriptor.supportedOptions = [.bluetoothHID, .bluetoothPairingLE]
        let item = ASPickerDisplayItem(name: "Watch BLE Mouse", productImage: image, descriptor: descriptor)
        pickerVisible = true
        status = "请在系统选择器中选择 Watch BLE Mouse"
        log.record("setup.picker.begin", ["service": ProbeProtocol.hidDiscovery.uuidString,
                                          "name": "WBLEMouse", "options": "bluetoothHID,bluetoothPairingLE"])
        session.showPicker(for: [item]) { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                log.record("setup.picker.completed", ["error": String(describing: error)])
                if let error {
                    pickerVisible = false
                    status = "系统设置失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func handle(_ event: ASAccessoryEvent) {
        log.record("setup.event", [
            "type": "\(event.eventType.rawValue)", "error": String(describing: event.error),
            "accessory": event.accessory?.displayName ?? "",
            "identifier": event.accessory?.bluetoothIdentifier?.uuidString ?? "",
        ])
        switch event.eventType {
        case .activated:
            ready = true
            status = "系统配件会话已就绪"
            log.record("setup.accessories", ["count": "\(session?.accessories.count ?? 0)"])
        case .invalidated:
            ready = false
            pickerVisible = false
            session = nil
            status = "系统配件会话已失效"
        case .pickerDidPresent:
            pickerVisible = true
        case .pickerDidDismiss:
            pickerVisible = false
        case .pickerSetupPairing:
            status = "系统正在配对"
        case .accessoryAdded, .accessoryChanged:
            // 配件授权与原生 HID 输入可用是两个不同的验收条件。
            status = "系统已更新配件；请检查手表订阅与手机指针"
        case .pickerSetupFailed:
            status = "系统配件设置失败"
        default:
            break
        }
        if let error = event.error { status = "系统配件错误：\(error.localizedDescription)" }
    }
}

private struct SetupLogView: View {
    @ObservedObject var log: ProbeLog

    var body: some View {
        ScrollView {
            Text(log.lines.joined(separator: "\n"))
                .font(.system(size: 10, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
