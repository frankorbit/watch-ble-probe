import SwiftUI

@main
struct PhoneProbeApp: App {
    @StateObject private var probe = HIDHostProbe(role: "iphone-hid")
    @Environment(\.scenePhase) private var scenePhase
    @State private var readEncrypted = ProcessInfo.processInfo.arguments.contains("--hid-read-encrypted")

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                VStack(alignment: .leading, spacing: 12) {
                    Text(probe.status).font(.headline)
                    Text(probe.result).font(.subheadline)
                    Text("只做 GATT 扫描、连接和读取；不订阅输入，不转发鼠标事件。")
                        .font(.caption)
                    Toggle("额外读取加密输入特征", isOn: $readEncrypted)
                    HStack {
                        Button("开始验证") { probe.start(readEncrypted: readEncrypted) }
                        Button("停止") { probe.stop() }
                        if let url = probe.log.fileURL {
                            ShareLink("导出日志", item: url)
                        }
                    }
                    .buttonStyle(.bordered)
                    PhoneLogView(log: probe.log)
                }
                .padding()
                .navigationTitle("Watch GATT Helper")
            }
            .task {
                UIApplication.shared.isIdleTimerDisabled = true
                if ProcessInfo.processInfo.arguments.contains("--auto-start") { probe.start() }
            }
            .onChange(of: scenePhase) { _, phase in
                UIApplication.shared.isIdleTimerDisabled = phase == .active
                probe.log.record("scene.changed", ["phase": "\(phase)"])
            }
        }
    }
}

private struct PhoneLogView: View {
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
