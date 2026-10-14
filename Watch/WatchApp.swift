import SwiftUI

@main
struct WatchProbeApp: App {
    @StateObject private var probe = PeripheralProbe()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSettings = false

    var body: some Scene {
        WindowGroup {
            Group {
                if probe.isHID {
                    VStack(spacing: 6) {
                        HStack {
                            Circle().fill(probe.phoneConnected ? .green : .orange).frame(width: 6, height: 6)
                            Text(probe.phoneConnected ? "iPhone 已连接" : "等待 iPhone").font(.caption2)
                            Spacer(minLength: 0)
                            Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                                .buttonStyle(.plain)
                                .accessibilityLabel("触控板设置")
                        }
                        TrackpadView(probe: probe)
                        Text("滑动移动 · 轻点点击").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 6)
                } else {
                    ProbeSettingsView(probe: probe)
                }
            }
            .sheet(isPresented: $showingSettings) { ProbeSettingsView(probe: probe) }
            .task { probe.start() }
            .onChange(of: scenePhase) { _, phase in
                probe.log.record("scene.changed", ["phase": "\(phase)"])
                if phase != .active { probe.cancelPointerInput() }
            }
        }
    }
}

private struct TrackpadView: View {
    @ObservedObject var probe: PeripheralProbe
    @State private var gestureState = TrackpadGestureState()
    @GestureState private var touching = false

    var body: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color.blue.opacity(touching ? 0.32 : 0.16))
            .overlay {
                RoundedRectangle(cornerRadius: 20).strokeBorder(Color.blue.opacity(0.45), lineWidth: 1)
            }
            .overlay {
                Image(systemName: "cursorarrow.motionlines")
                    .font(.title2)
                    .foregroundStyle(.blue.opacity(0.65))
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 20))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($touching) { _, state, _ in state = true }
                    .onChanged { value in
                        send(gestureState.update(translation: value.translation, time: value.time))
                    }
                    .onEnded { value in
                        send(gestureState.update(translation: value.translation, time: value.time))
                        if gestureState.end(time: value.time) { probe.clickMouse() }
                    }
            )
            .onChange(of: touching) { _, isTouching in
                // 系统取消手势时也清理位移基准，避免下一次触摸跳动。
                if !isTouching { gestureState.reset() }
            }
            .onDisappear { gestureState.reset() }
            .accessibilityLabel("iPhone 触控板")
            .accessibilityHint("滑动移动指针，轻点执行左键点击")
            .accessibilityAction { probe.clickMouse() }
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: probe.moveMouse(dx: 20)
                case .decrement: probe.moveMouse(dx: -20)
                @unknown default: break
                }
            }
    }

    private func send(_ delta: PointerDelta) {
        if delta.horizontal != 0 || delta.vertical != 0 { probe.moveMouse(dx: delta.horizontal, dy: delta.vertical) }
    }
}

private struct ProbeSettingsView: View {
    @ObservedObject var probe: PeripheralProbe
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(probe.isHID ? "触控板设置" : "BLE GATT 探针").font(.headline)
                Text(probe.status).font(.caption2)
                if probe.targetCentralID == nil { Text("尚未绑定 iPhone").font(.caption2) }
                Button("启动探针") { probe.start() }
                Button("停止") { probe.stop() }
                Button(probe.isHID ? "切换到 GATT" : "切换到 iPhone 触控板") { probe.switchMode() }
                Button("完成") { dismiss() }
                Text(probe.log.lines.suffix(8).joined(separator: "\n"))
                    .font(.system(size: 9, design: .monospaced))
            }
        }
    }
}
