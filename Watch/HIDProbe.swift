import CoreBluetooth
import Foundation

@MainActor
final class HIDProbe {
    static let serviceUUID = uuid("1812")
    private static let reportMapUUID = uuid("2A4B")
    private static let reportUUID = uuid("2A4D")
    private static let controlUUID = uuid("2A4C")
    private static let protocolUUID = uuid("2A4E")
    private static let bootInputUUID = uuid("2A33")

    private let log: ProbeLog
    private let targetCentralID: UUID?
    private var values: [CBUUID: Data] = [:]
    private var input: CBMutableCharacteristic?
    private var bootInput: CBMutableCharacteristic?
    private var protocolMode: UInt8 = 1
    private var suspended = false
    private var didAutoMove = false
    private var pendingInput = PointerInputBuffer()

    init(log: ProbeLog, targetCentralID: UUID?) {
        self.log = log
        self.targetCentralID = targetCentralID
    }

    func isInput(_ characteristic: CBCharacteristic) -> Bool {
        [Self.reportUUID, Self.bootInputUUID].contains(characteristic.uuid)
    }

    private static func uuid(_ short: String) -> CBUUID {
        CBUUID(string: "0000\(short)-0000-1000-8000-00805F9B34FB")
    }

    func makeServices() throws -> [CBMutableService] {
        // Report ID 放在 0x2908 中，GATT 通知仅携带四字节报告正文。
        let reportMap = HIDReport.map
        let info = try readCharacteristic(Self.uuid("2A4A"), value: Data([0x11, 0x01, 0x00, 0x02]))
        let map = try readCharacteristic(Self.reportMapUUID, value: reportMap)
        let control = try ProbeBridge.characteristic(
            with: Self.controlUUID, properties: .writeWithoutResponse, permissions: .writeable
        )
        let mode = try ProbeBridge.characteristic(
            with: Self.protocolUUID, properties: [.read, .writeWithoutResponse], permissions: [.readable, .writeable]
        )
        values[Self.protocolUUID] = Data([1])
        let input = try ProbeBridge.characteristic(
            with: Self.reportUUID, properties: [.read, .notify, .notifyEncryptionRequired],
            permissions: [.readable, .readEncryptionRequired]
        )
        input.descriptors = try [ProbeBridge.descriptor(with: Self.uuid("2908"), value: Data([1, 1]))]
        values[Self.reportUUID] = Data([0, 0, 0, 0])
        self.input = input
        let bootInput = try ProbeBridge.characteristic(
            with: Self.bootInputUUID, properties: [.read, .notify, .notifyEncryptionRequired],
            permissions: [.readable, .readEncryptionRequired]
        )
        values[Self.bootInputUUID] = Data([0, 0, 0])
        self.bootInput = bootInput
        let manufacturer = try readCharacteristic(Self.uuid("2A29"), value: Data("Frank BLE Probe".utf8))
        // 实验用未分配标识，不冒充已有厂商或产品。
        let pnp = try readCharacteristic(Self.uuid("2A50"), value: Data([0x02, 0xFF, 0xFF, 0x01, 0x00, 0x01, 0x00]))
        let battery = try readCharacteristic(Self.uuid("2A19"), value: Data([100]))
        log.record("hid.constructed", ["reportMapBytes": "\(reportMap.count)", "encryptedNotifications": "true"])
        return try [
            ProbeBridge.service(with: Self.uuid("180A"), characteristics: [manufacturer, pnp]),
            ProbeBridge.service(with: Self.uuid("180F"), characteristics: [battery]),
            ProbeBridge.service(with: Self.serviceUUID, characteristics: [info, map, control, mode, input, bootInput]),
        ]
    }

    private func readCharacteristic(_ uuid: CBUUID, value: Data) throws -> CBMutableCharacteristic {
        values[uuid] = value
        return try ProbeBridge.characteristic(with: uuid, properties: .read, permissions: .readable)
    }

    func read(_ request: CBATTRequest, manager: CBPeripheralManager) {
        guard let value = values[request.characteristic.uuid] else {
            manager.respond(to: request, withResult: .readNotPermitted); return
        }
        guard request.offset <= value.count else {
            manager.respond(to: request, withResult: .invalidOffset); return
        }
        request.value = value.subdata(in: request.offset ..< value.count)
        manager.respond(to: request, withResult: .success)
        log.record("hid.read", [
            "uuid": request.characteristic.uuid.uuidString, "offset": "\(request.offset)",
            "central": request.central.identifier.uuidString,
        ])
    }

    func write(_ requests: [CBATTRequest], manager: CBPeripheralManager) {
        guard let first = requests.first else { return }
        guard requests.allSatisfy({ $0.central.identifier == targetCentralID }) else {
            log.record("hid.write.ignoredHost", ["central": first.central.identifier.uuidString])
            manager.respond(to: first, withResult: .writeNotPermitted)
            return
        }
        guard requests.allSatisfy({
            [Self.controlUUID, Self.protocolUUID].contains($0.characteristic.uuid)
                && $0.offset == 0 && $0.value?.count == 1 && ($0.value?.first ?? 255) <= 1
        }) else {
            manager.respond(to: first, withResult: .requestNotSupported); return
        }
        for request in requests {
            guard let value = request.value?.first else { return }
            if request.characteristic.uuid == Self.protocolUUID {
                protocolMode = value
                values[Self.protocolUUID] = Data([value])
            } else { suspended = value == 0 }
            log.record("hid.write", ["uuid": request.characteristic.uuid.uuidString, "value": "\(value)"])
        }
        manager.respond(to: first, withResult: .success)
        cancelInput(manager: manager)
    }

    func subscribed(_ characteristic: CBCharacteristic, central: CBCentral, manager: CBPeripheralManager) {
        guard isInput(characteristic), central.identifier == targetCentralID else {
            log.record("hid.subscription.ignoredHost", ["central": central.identifier.uuidString])
            return
        }
        pendingInput.release()
        flush(manager: manager)
        if ProcessInfo.processInfo.arguments.contains("--hid-auto-move"), !didAutoMove {
            didAutoMove = true
            Task { [weak self, weak manager] in
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                guard let self, let manager else { return }
                move(manager: manager)
            }
        }
    }

    private var selectedInput: CBMutableCharacteristic? {
        protocolMode == 0 ? bootInput : input
    }

    private func target(for characteristic: CBMutableCharacteristic) -> CBCentral? {
        guard let targetCentralID else { return nil }
        return characteristic.subscribedCentrals?.first { $0.identifier == targetCentralID }
    }

    private var ready: Bool {
        guard let selectedInput else { return false }
        return !suspended && target(for: selectedInput) != nil
    }

    @discardableResult
    func move(manager: CBPeripheralManager, dx: Int = 20, dy: Int = 0) -> Bool? {
        guard ready else {
            pendingInput.clear()
            log.record("hid.move.notReady")
            return nil
        }
        let accepted = pendingInput.move(dx: dx, dy: dy)
        flush(manager: manager)
        return accepted
    }

    func click(manager: CBPeripheralManager) -> Bool? {
        guard ready else {
            pendingInput.clear()
            log.record("hid.click.notReady")
            return nil
        }
        let accepted = pendingInput.click()
        log.record("hid.click.queued", ["accepted": "\(accepted)"])
        flush(manager: manager)
        return accepted
    }

    func cancelInput(manager: CBPeripheralManager) {
        pendingInput.release()
        flush(manager: manager)
    }

    func flush(manager: CBPeripheralManager) {
        guard let selectedInput, let target = target(for: selectedInput), !suspended else {
            pendingInput.clear()
            return
        }
        while let report = pendingInput.next {
            let data = report.data(bootMode: protocolMode == 0)
            // 队列满时保留报告，尤其不能丢掉左键释放；仅发送给绑定手机。
            guard manager.updateValue(data, for: selectedInput, onSubscribedCentrals: [target]) else {
                log.record("hid.input.backpressure")
                return
            }
            pendingInput.didSend()
            values[selectedInput.uuid] = data
            log.record("hid.input.enqueued", [
                "central": target.identifier.uuidString, "buttons": "\(report.buttons)",
                "dx": "\(report.dx)", "dy": "\(report.dy)", "bytes": "\(data.count)",
            ])
        }
    }
}
