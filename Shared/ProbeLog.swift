import Combine
import Foundation

@MainActor
final class ProbeLog: ObservableObject {
    @Published private(set) var lines: [String] = []
    @Published private(set) var fileURL: URL?
    let run = UUID().uuidString
    private var file: FileHandle?

    init(role: String) {
        do {
            let root = try FileManager.default.url(
                for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            ).appendingPathComponent("WatchBLEProbe", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let url = root.appendingPathComponent("\(role)-\(run).jsonl")
            try Data().write(to: url, options: .atomic)
            file = try FileHandle(forWritingTo: url)
            fileURL = url
        } catch {
            lines.append("日志文件创建失败：\(error)")
        }
        record("session.started", ["role": role, "system": ProcessInfo.processInfo.operatingSystemVersionString])
    }

    func record(_ event: String, _ fields: [String: String] = [:]) {
        var entry = fields
        entry["event"] = event
        entry["run"] = run
        entry["timestamp"] = ISO8601DateFormatter().string(from: Date())
        do {
            var data = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys])
            data.append(0x0A)
            FileHandle.standardOutput.write(data)
            if let file {
                try file.write(contentsOf: data)
                // 私有调用可能直接终止进程，调用前的记录必须及时落盘。
                try file.synchronize()
            }
        } catch {
            lines.append("日志写入失败：\(error)")
        }
        lines.append("\(event) \(fields)")
        if lines.count > 150 { lines.removeFirst(lines.count - 150) }
    }
}
