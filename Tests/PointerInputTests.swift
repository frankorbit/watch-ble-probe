import CoreGraphics
import Foundation

@main
struct PointerInputTests {
    static func main() {
        var gesture = TrackpadGestureState()
        let start = Date(timeIntervalSince1970: 0)
        precondition(gesture.update(translation: .zero, time: start) == PointerDelta(horizontal: 0, vertical: 0))
        precondition(gesture.update(translation: CGSize(width: 2, height: 1), time: start) == PointerDelta(horizontal: 0, vertical: 0))
        precondition(gesture.end(time: start.addingTimeInterval(0.2)))
        _ = gesture.update(translation: .zero, time: start)
        precondition(!gesture.end(time: start.addingTimeInterval(0.5)))
        _ = gesture.update(translation: .zero, time: start)
        precondition(gesture.update(translation: CGSize(width: 10, height: -10), time: start) == PointerDelta(horizontal: 18, vertical: -18))
        precondition(gesture.update(translation: .zero, time: start) == PointerDelta(horizontal: -18, vertical: 18))
        precondition(!gesture.end(time: start.addingTimeInterval(0.1)))

        var buffer = PointerInputBuffer()
        precondition(buffer.move(dx: 300, dy: -260))
        precondition(buffer.click())
        precondition(buffer.move(dx: 8, dy: 4))
        var reports: [PointerReport] = []
        while let report = buffer.next {
            // 模拟蓝牙背压：未确认发送前，读取队首不得丢失或跳过释放。
            precondition(buffer.next == report)
            reports.append(report)
            buffer.didSend()
        }
        precondition(reports.prefix(3).reduce(0) { $0 + Int($1.dx) } == 300)
        precondition(reports.prefix(3).reduce(0) { $0 + Int($1.dy) } == -260)
        precondition(reports.map(\.buttons) == [0, 0, 0, 1, 0, 0])
        precondition(reports.last == PointerReport(buttons: 0, dx: 8, dy: 4))
        precondition(reports[3].data(bootMode: false) == Data([1, 0, 0, 0]))
        precondition(reports[4].data(bootMode: true) == Data([0, 0, 0]))

        for _ in 0 ..< 32 {
            precondition(buffer.click())
        }
        precondition(!buffer.click())
        var buttons: [UInt8] = []
        while let report = buffer.next {
            buttons.append(report.buttons); buffer.didSend()
        }
        precondition(buttons == Array(repeating: [UInt8(1), UInt8(0)], count: 32).flatMap(\.self))
        precondition(buffer.click())
        buffer.didSend()
        buffer.release()
        precondition(buffer.next == PointerReport(buttons: 0, dx: 0, dy: 0))
        buffer.clear()
        precondition(buffer.next == nil)
        print("PASS: tap/drag separation, report splitting, click order, backpressure retention, queue limits and release")
    }
}
