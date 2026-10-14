import CoreGraphics
import Foundation

struct PointerDelta: Equatable {
    var horizontal: Int
    var vertical: Int
}

struct TrackpadGestureState {
    private var beganAt: Date?
    private var lastTranslation = CGSize.zero
    private var remainder = CGSize.zero
    private var dragged = false
    var sensitivity = 1.8

    mutating func update(translation: CGSize, time: Date) -> PointerDelta {
        if beganAt == nil { beganAt = time }
        if hypot(translation.width, translation.height) >= 5 { dragged = true }
        guard dragged else { return PointerDelta(horizontal: 0, vertical: 0) }
        let horizontal = (translation.width - lastTranslation.width) * sensitivity + remainder.width
        let vertical = (translation.height - lastTranslation.height) * sensitivity + remainder.height
        lastTranslation = translation
        let delta = PointerDelta(horizontal: Int(horizontal), vertical: Int(vertical))
        remainder = CGSize(width: horizontal - Double(delta.horizontal), height: vertical - Double(delta.vertical))
        return delta
    }

    mutating func end(time: Date) -> Bool {
        let isTap = beganAt.map { time.timeIntervalSince($0) <= 0.35 } == true && !dragged
        reset()
        return isTap
    }

    mutating func reset() {
        beganAt = nil
        lastTranslation = .zero
        remainder = .zero
        dragged = false
    }
}

struct PointerReport: Equatable {
    var buttons: UInt8
    var dx: Int8
    var dy: Int8

    func data(bootMode: Bool) -> Data {
        var bytes = Data([buttons, UInt8(bitPattern: dx), UInt8(bitPattern: dy)])
        if !bootMode { bytes.append(0) }
        return bytes
    }
}

struct PointerInputBuffer {
    private enum Operation {
        case motion(Int, Int)
        case buttons(UInt8)
    }

    private var operations: [Operation] = []
    private let capacity = 64

    mutating func move(dx: Int, dy: Int) -> Bool {
        guard dx != 0 || dy != 0 else { return true }
        if case let .motion(horizontal, vertical) = operations.last {
            // 仅合并相邻位移；不能跨越按下/释放边界。
            operations[operations.count - 1] = .motion(clamp(horizontal + dx), clamp(vertical + dy))
            return true
        }
        guard operations.count < capacity else { return false }
        operations.append(.motion(clamp(dx), clamp(dy)))
        return true
    }

    mutating func click() -> Bool {
        // 为按下和释放同时预留位置，禁止只排入按下。
        guard operations.count <= capacity - 2 else { return false }
        operations.append(.buttons(1))
        operations.append(.buttons(0))
        return true
    }

    mutating func release() {
        operations = [.buttons(0)]
    }

    mutating func clear() {
        operations.removeAll()
    }

    var next: PointerReport? {
        switch operations.first {
        case let .motion(horizontal, vertical):
            PointerReport(
                buttons: 0, dx: Int8(max(-127, min(127, horizontal))), dy: Int8(max(-127, min(127, vertical)))
            )
        case let .buttons(buttons): PointerReport(buttons: buttons, dx: 0, dy: 0)
        case nil: nil
        }
    }

    mutating func didSend() {
        guard let report = next else { return }
        if case let .motion(horizontal, vertical) = operations.first {
            let remainingX = horizontal - Int(report.dx)
            let remainingY = vertical - Int(report.dy)
            if remainingX != 0 || remainingY != 0 {
                operations[0] = .motion(remainingX, remainingY)
                return
            }
        }
        operations.removeFirst()
    }

    private func clamp(_ value: Int) -> Int {
        max(-2048, min(2048, value))
    }
}
