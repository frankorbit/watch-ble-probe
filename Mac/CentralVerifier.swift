import Combine
import CoreBluetooth
import Foundation

@MainActor
final class CentralVerifier: NSObject, ObservableObject {
    let log = ProbeLog(role: "mac")
    @Published private(set) var status = "尚未开始"
    private var manager: CBCentralManager?
    private var peer: CBPeripheral?
    private var echo: CBCharacteristic?
    private var notification: CBCharacteristic?
    private var challenge = Data()
    private var peerIdentity: ProbeIdentity?
    private var readPassed = false
    private var notifyPassed = false
    private var writePassed = false
    private var finished = false
    private var active = false
    private var generation = UUID()

    func start() {
        guard !active else { return }
        active = true
        finished = false
        peerIdentity = nil
        echo = nil
        notification = nil
        readPassed = false
        notifyPassed = false
        writePassed = false
        challenge = Data(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16).utf8)
        generation = UUID()
        let attempt = generation
        status = "等待蓝牙授权"
        log.record("verification.begin", ["challenge": challenge.base64EncodedString(), "attempt": attempt.uuidString])
        manager = CBCentralManager(delegate: self, queue: .main)
        Task { [weak self] in
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
            guard let self, generation == attempt, active, !finished else { return }
            fail("verification.timeout")
        }
    }

    func stop() {
        active = false
        manager?.stopScan()
        if let peer { manager?.cancelPeripheralConnection(peer) }
        peer?.delegate = nil
        peer = nil
        manager?.delegate = nil
        manager = nil
        if !finished { status = "已停止" }
        log.record("verification.stopped")
    }

    private func fail(_ event: String, error: Error? = nil) {
        guard active, !finished else { return }
        finished = true
        status = event
        log.record(event, ["error": error.map { String(describing: $0) } ?? "none"])
        stop()
    }

    private func checkSuccess() {
        guard readPassed, notifyPassed, writePassed, let identity = peerIdentity, !finished else { return }
        finished = true
        status = "普通 GATT 真机验证通过"
        log.record("gatt.verified", ["watchRun": identity.run, "mode": identity.mode, "system": identity.system])
        stop()
    }

    private func verifyIdentity(_ value: Data, peripheral: CBPeripheral) {
        do {
            let identity = try JSONDecoder().decode(ProbeIdentity.self, from: value)
            guard identity.role == "watch", !identity.simulated, UUID(uuidString: identity.run) != nil else {
                fail("identity.invalid"); return
            }
            peerIdentity = identity
            log.record("identity.verified", ["watchRun": identity.run, "mode": identity.mode, "system": identity.system])
            if let notification { peripheral.setNotifyValue(true, for: notification) }
        } catch { fail("identity.decode.failed", error: error) }
    }
}

extension CentralVerifier: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central === manager, active else { return }
        log.record("central.state", ["state": "\(central.state.rawValue)"])
        if central.state == .poweredOn {
            status = "扫描 Watch 探针（60 秒）"
            central.scanForPeripherals(withServices: [ProbeProtocol.service])
        }
    }

    func centralManager(
        _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
        advertisementData _: [String: Any], rssi RSSI: NSNumber
    ) {
        guard active, peer == nil else { return }
        peer = peripheral
        peripheral.delegate = self
        central.stopScan()
        log.record("peer.discovered", ["name": peripheral.name ?? "unknown", "rssi": RSSI.stringValue])
        status = "连接并发现服务"
        central.connect(peripheral)
    }

    func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log.record("peer.connected")
        peripheral.discoverServices([ProbeProtocol.service])
    }

    func centralManager(_: CBCentralManager, didFailToConnect _: CBPeripheral, error: Error?) {
        fail("peer.connection.failed", error: error)
    }

    func centralManager(_: CBCentralManager, didDisconnectPeripheral _: CBPeripheral, error: Error?) {
        fail("peer.disconnected", error: error)
    }
}

extension CentralVerifier: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { fail("services.failed", error: error); return }
        guard let service = peripheral.services?.first(where: { $0.uuid == ProbeProtocol.service }) else {
            fail("service.missing"); return
        }
        peripheral.discoverCharacteristics([ProbeProtocol.identity, ProbeProtocol.echo, ProbeProtocol.notification], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error { fail("characteristics.failed", error: error); return }
        let characteristics = service.characteristics ?? []
        echo = characteristics.first { $0.uuid == ProbeProtocol.echo }
        notification = characteristics.first { $0.uuid == ProbeProtocol.notification }
        guard let identity = characteristics.first(where: { $0.uuid == ProbeProtocol.identity }), echo != nil, notification != nil else {
            fail("characteristics.missing"); return
        }
        log.record("characteristics.discovered")
        peripheral.readValue(for: identity)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard active, !finished else { return }
        if let error { fail("value.failed", error: error); return }
        guard let value = characteristic.value else { fail("value.nil"); return }
        switch characteristic.uuid {
        case ProbeProtocol.identity:
            verifyIdentity(value, peripheral: peripheral)
        case ProbeProtocol.echo:
            guard value == challenge else { fail("readback.mismatch"); return }
            readPassed = true
            log.record("readback.verified")
        case ProbeProtocol.notification:
            guard value == ProbeProtocol.notificationValue(for: challenge) else { fail("notify.mismatch"); return }
            notifyPassed = true
            log.record("notify.verified")
        default: return
        }
        checkSuccess()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error { fail("notify.subscribe.failed", error: error); return }
        guard characteristic.isNotifying, let echo else { fail("notify.notEnabled"); return }
        log.record("notify.enabled")
        peripheral.writeValue(challenge, for: echo, type: .withResponse)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { fail("write.failed", error: error); return }
        writePassed = true
        log.record("write.acknowledged")
        peripheral.readValue(for: characteristic)
    }
}
