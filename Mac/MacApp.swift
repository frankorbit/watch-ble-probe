import AppKit
import SwiftUI

@main
struct MacVerifierApp: App {
    @StateObject private var verifier = CentralVerifier()
    @StateObject private var hidProbe = HIDHostProbe()
    private let isHID = ProcessInfo.processInfo.arguments.contains("--hid-connect")

    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text("Watch BLE 真机验证端").font(.title2)
                Text(isHID ? hidProbe.status : verifier.status).font(.headline)
                Text(isHID ? "检查 HID 服务发现与连接，系统鼠标识别需单独验证。" : "验证自定义 GATT 的读写和通知。")
                HStack {
                    Button("开始验证") { isHID ? hidProbe.start() : verifier.start() }
                    Button("停止") { isHID ? hidProbe.stop() : verifier.stop() }
                    Button("显示日志文件") {
                        if let url = (isHID ? hidProbe.log : verifier.log).fileURL {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                }
                MacLogView(log: isHID ? hidProbe.log : verifier.log)
            }
            .padding()
            .frame(minWidth: 760, minHeight: 460)
            .task {
                if isHID {
                    hidProbe.start()
                } else if ProcessInfo.processInfo.arguments.contains("--auto-start") {
                    verifier.start()
                }
            }
        }
    }
}

private struct MacLogView: View {
    @ObservedObject var log: ProbeLog

    var body: some View {
        ScrollView {
            Text(log.lines.joined(separator: "\n"))
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
