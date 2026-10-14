import Combine
import CoreBluetooth
import Foundation

@MainActor
final class HIDHostProbe: NSObject, ObservableObject {
    let log: ProbeLog
    @Published private(set) var result = "尚未完成属性验证"
    @Published private(set) var status = "HID 连接检查未启动"
    private var manager: CBCentralManager?
    private var peer: CBPeripheral?
    private var active = false
    private var generation = UUID()
    private var identityVerified = false
    private var mapVerified = false
    private var reportReferenceVerified = false
    private var hidFound = false
    private var encryptedReadPassed = false
    private var infoVerified = false
    private var protocolVerified = false
    private var didVerify = false
    private var watchRun = ""
    private let standardScan = ProcessInfo.processInfo.arguments.contains("--hid-standard-scan")
    private var readEncrypted = ProcessInfo.processInfo.arguments.contains("--hid-read-encrypted")

    init(role: String = "mac-hid") {
        log = ProbeLog(role: role)
        super.init()
    }

    func start(readEncrypted: Bool? = nil) {
        guard !active else { return }
        active = true
        if let readEncrypted { self.readEncrypted = readEncrypted }
        result = "尚未完成属性验证"
        status = "1/5 等待蓝牙授权"
        infoVerified = false
        protocolVerified = false
        didVerify = false
        watchRun = ""
        identityVerified = false
        mapVerified = false
        reportReferenceVerified = false
        hidFound = false
        encryptedReadPassed = false
        generation = UUID()
        let attempt = generation
        log.record("hid.scan.begin", ["filter": standardScan ? "1812" : ProbeProtocol.hidDiscovery.uuidString,
                                      "readEncrypted": "\(self.readEncrypted)"])
        manager = CBCentralManager(delegate: self, queue: .main)
        Task { [weak self] in
            do { try await Task.sleep(for: .seconds(90)) } catch { return }
            guard let self, active, generation == attempt else { return }
            log.record("hid.observation.ended", [
                "connected": "\(peer?.state == .connected)", "identityVerified": "\(identityVerified)",
                "hidFound": "\(hidFound)", "reportMapVerified": "\(mapVerified)",
                "reportReferenceVerified": "\(reportReferenceVerified)", "encryptedReadPassed": "\(encryptedReadPassed)",
            ])
            stop()
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
        status = "已停止；\(status)"
    }

    private func verifyIdentity(_ data: Data, peripheral: CBPeripheral) {
        do {
            let identity = try JSONDecoder().decode(ProbeIdentity.self, from: data)
            guard identity.role == "watch", !identity.simulated, identity.mode.hasPrefix("hid-"),
                  UUID(uuidString: identity.run) != nil
            else {
                log.record("hid.identity.invalid"); stop(); return
            }
            identityVerified = true
            watchRun = identity.run
            status = "3/5 手表身份通过，枚举 HID 服务"
            log.record("hid.identity.verified", ["watchRun": identity.run, "mode": identity.mode, "system": identity.system])
            // 确认自有探针身份后才枚举全部服务，不依赖可能被系统缓存的广播名称。
            peripheral.discoverServices(nil)
        } catch {
            log.record("hid.identity.failed", ["error": String(describing: error)])
            stop()
        }
    }

    private func connect(_ peripheral: CBPeripheral, central: CBCentralManager, source: String) {
        guard peer == nil, active else { return }
        peer = peripheral
        peripheral.delegate = self
        central.stopScan()
        status = "2/5 已找到探针，建立连接"
        log.record("hid.connect.begin", ["source": source, "identifier": peripheral.identifier.uuidString])
        central.connect(peripheral)
    }

    private func checkVerification() {
        guard !didVerify, identityVerified, hidFound, infoVerified, mapVerified, protocolVerified,
              reportReferenceVerified, !readEncrypted || encryptedReadPassed else { return }
        didVerify = true
        status = "5/5 HID 属性读取验证通过"
        result = "GATT 通过；系统鼠标接管仍需检查手表订阅与手机指针"
        log.record("hid.gatt.verified", ["watchRun": watchRun, "encryptedReadPassed": "\(encryptedReadPassed)"])
    }
}

extension HIDHostProbe: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central === manager, active else { return }
        log.record("hid.central.state", ["state": "\(central.state.rawValue)"])
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: [standardScan ? CBUUID(string: "1812") : ProbeProtocol.hidDiscovery])
            status = standardScan ? "2/5 扫描标准 HID UUID" : "2/5 扫描自定义发现 UUID"
            let connected = central.retrieveConnectedPeripherals(withServices: [ProbeProtocol.hidDiscovery])
            log.record("hid.systemConnected.candidates", ["count": "\(connected.count)"])
            if let peripheral = connected.first {
                // 已由系统连接的设备可能不再广播，仍须读取探针身份验证。
                connect(peripheral, central: central, source: "systemConnected")
            }
        }
    }

    func centralManager(
        _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any], rssi RSSI: NSNumber
    ) {
        guard central === manager, active, peer == nil else { return }
        let advertised = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let overflow = advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? []
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        log.record("hid.advertisement", [
            "name": peripheral.name ?? "", "localName": localName, "rssi": RSSI.stringValue,
            "services": advertised.map(\.uuidString).joined(separator: ","),
            "overflow": overflow.map(\.uuidString).joined(separator: ","),
            "connectable": String(describing: advertisementData[CBAdvertisementDataIsConnectable] ?? "unknown"),
        ])
        // 标准 HID 扫描可能发现其他键鼠，必须额外匹配本实验的 UUID。
        if standardScan, !(advertised + overflow).contains(ProbeProtocol.hidDiscovery) { return }
        connect(peripheral, central: central, source: "advertisement")
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard central === manager, peripheral === peer, active else { return }
        log.record("hid.peer.connected", ["identifier": peripheral.identifier.uuidString])
        status = "3/5 已连接，校验手表会话"
        peripheral.discoverServices([ProbeProtocol.hidDiscovery])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard central === manager, peripheral === peer, active else { return }
        log.record("hid.connection.failed", ["error": String(describing: error)])
        stop()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard central === manager, peripheral === peer, active else { return }
        log.record("hid.disconnected", ["error": String(describing: error)])
    }
}

extension HIDHostProbe: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral === peer, active else { return }
        if let error {
            log.record("hid.discovery.failed", ["error": String(describing: error)]); return
        }
        if !identityVerified {
            guard let service = peripheral.services?.first(where: { $0.uuid == ProbeProtocol.hidDiscovery }) else {
                log.record("hid.identity.serviceMissing"); stop(); return
            }
            peripheral.discoverCharacteristics([ProbeProtocol.hidIdentity], for: service)
            return
        }
        hidFound = peripheral.services?.contains(where: { $0.uuid == CBUUID(string: "1812") }) ?? false
        log.record("hid.services.enumerated", ["hidFound": "\(hidFound)"])
        for service in peripheral.services ?? [] {
            log.record("hid.service.discovered", ["uuid": service.uuid.uuidString])
            // 系统会合并手表其他服务；仅读取本实验需要的 HID 属性。
            if service.uuid == CBUUID(string: "1812") { peripheral.discoverCharacteristics(nil, for: service) }
        }
        status = hidFound ? "4/5 已发现 HID，读取属性与描述符" : "已连接手表，但未发现 HID 服务"
        if !hidFound { result = "身份通过，但系统未暴露 HID 服务" }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral === peer, active else { return }
        log.record("hid.characteristics.discovered", [
            "service": service.uuid.uuidString, "error": String(describing: error),
            "characteristics": (service.characteristics ?? []).map(\.uuid.uuidString).joined(separator: ","),
        ])
        guard error == nil else { return }
        if !identityVerified, !(service.characteristics ?? []).contains(where: { $0.uuid == ProbeProtocol.hidIdentity }) {
            result = "发现服务但缺少身份特征"
            log.record("hid.identity.characteristicMissing"); stop(); return
        }
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == ProbeProtocol.hidIdentity {
                peripheral.readValue(for: characteristic)
            } else if identityVerified {
                let encrypted = [CBUUID(string: "2A4D"), CBUUID(string: "2A33")].contains(characteristic.uuid)
                if characteristic.properties.contains(.read), !encrypted || readEncrypted {
                    peripheral.readValue(for: characteristic)
                }
                if characteristic.uuid == CBUUID(string: "2A4D") { peripheral.discoverDescriptors(for: characteristic) }
            }
        }
        // 不自行订阅输入报告，不把 BLE 数据转换成系统鼠标事件。
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === peer, active else { return }
        log.record("hid.characteristic.read", [
            "uuid": characteristic.uuid.uuidString, "error": String(describing: error),
            "bytes": "\(characteristic.value?.count ?? 0)", "value": characteristic.value?.base64EncodedString() ?? "",
        ])
        guard error == nil, let data = characteristic.value else { return }
        if characteristic.uuid == ProbeProtocol.hidIdentity { verifyIdentity(data, peripheral: peripheral) }
        if characteristic.uuid == CBUUID(string: "2A4B") {
            mapVerified = data == HIDReport.map
            log.record("hid.reportMap.checked", ["matches": "\(mapVerified)"])
        }
        if characteristic.uuid == CBUUID(string: "2A4A") { infoVerified = data == Data([0x11, 0x01, 0x00, 0x02]) }
        if characteristic.uuid == CBUUID(string: "2A4E") { protocolVerified = data.count == 1 && (data.first ?? 255) <= 1 }
        if characteristic.uuid == CBUUID(string: "2A4D") { encryptedReadPassed = data.count == 4 }
        checkVerification()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === peer, active else { return }
        log.record("hid.descriptors.discovered", [
            "uuid": characteristic.uuid.uuidString, "error": String(describing: error),
            "descriptors": (characteristic.descriptors ?? []).map(\.uuid.uuidString).joined(separator: ","),
        ])
        guard error == nil else { return }
        for descriptor in characteristic.descriptors ?? [] {
            peripheral.readValue(for: descriptor)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
        guard peripheral === peer, active else { return }
        let data = descriptor.value as? Data
        log.record("hid.descriptor.read", [
            "uuid": descriptor.uuid.uuidString, "error": String(describing: error),
            "value": data?.base64EncodedString() ?? String(describing: descriptor.value),
        ])
        if error == nil, descriptor.uuid == CBUUID(string: "2908") { reportReferenceVerified = data == Data([1, 1]) }
        checkVerification()
    }
}
