import Combine
import CoreBluetooth
import Foundation

@MainActor
final class PeripheralProbe: NSObject, ObservableObject {
    let log = ProbeLog(role: "watch")
    @Published private(set) var status = "尚未启动"
    private var manager: CBPeripheralManager?
    private var service: CBMutableService?
    private var notifyCharacteristic: CBMutableCharacteristic?
    private var mode = "default-init"
    private var identity = Data()
    private var echoes: [UUID: Data] = [:]
    private var pendingNotifications: [UUID: (CBCentral, Data)] = [:]
    private var didStart = false
    private var hid: HIDProbe?
    private var pendingServices: [CBMutableService] = []
    @Published private(set) var isHID: Bool
    @Published private(set) var subscribedHostCount = 0
    @Published private(set) var phoneConnected = false
    let targetCentralID: UUID?
    private var subscriptions: [UUID: Set<CBUUID>] = [:]

    override init() {
        let arguments = ProcessInfo.processInfo.arguments
        let defaults = UserDefaults.standard
        if let index = arguments.firstIndex(of: "--target-central") {
            // 仅接受显式验证过的标识；错误配置清除旧目标，禁止猜测订阅主机身份。
            let value = arguments.indices.contains(index + 1) ? UUID(uuidString: arguments[index + 1]) : nil
            defaults.set(value?.uuidString, forKey: "hidPhoneCentralID")
        }
        targetCentralID = defaults.string(forKey: "hidPhoneCentralID").flatMap(UUID.init(uuidString:))
        let savedHID = defaults.object(forKey: "hidMode") == nil || defaults.bool(forKey: "hidMode")
        isHID = arguments.contains("--hid") || (!arguments.contains("--gatt") && savedHID)
        super.init()
        UserDefaults.standard.set(isHID, forKey: "hidMode")
        log.record("hid.phoneTarget.loaded", ["central": targetCentralID?.uuidString ?? "unbound"])
    }

    func switchMode() {
        stop()
        isHID.toggle()
        UserDefaults.standard.set(isHID, forKey: "hidMode")
        start()
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        let runtime = ProcessInfo.processInfo.arguments.contains("--runtime-init")
        mode = runtime ? "runtime-init" : "default-init"
        log.record("probe.profile", ["profile": isHID ? "hid" : "gatt"])
        log.record("manager.create.begin", ["mode": mode, "authorization": "\(CBManager.authorization.rawValue)"])
        do {
            manager = try ProbeBridge.manager(with: self, runtimeInitializer: runtime)
            guard let manager else {
                fail("manager.create.nil")
                return
            }
            log.record("manager.created", ["state": "\(manager.state.rawValue)"])
            status = "等待蓝牙状态"
            if manager.state == .poweredOn { publish() }
            Task { [weak self, weak manager] in
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                guard let self, let manager, manager === self.manager, service == nil else { return }
                log.record("manager.wait.timeout", ["state": "\(manager.state.rawValue)", "mode": mode])
                status = "状态 \(manager.state.rawValue)，未发布"
            }
        } catch { fail("manager.create.exception", error: error) }
    }

    func stop() {
        cancelPointerInput()
        manager?.stopAdvertising()
        manager?.removeAllServices()
        manager?.delegate = nil
        manager = nil
        service = nil
        hid = nil
        notifyCharacteristic = nil
        pendingServices.removeAll()
        pendingNotifications.removeAll()
        echoes.removeAll()
        subscriptions.removeAll()
        subscribedHostCount = 0
        phoneConnected = false
        didStart = false
        status = "已停止，可点启动重试"
        log.record("probe.stopped")
    }

    private func publish() {
        guard service == nil, let manager else { return }
        log.record("gatt.construct.begin")
        do {
            #if targetEnvironment(simulator)
                let simulated = true
            #else
                let simulated = false
            #endif
            identity = try JSONEncoder().encode(ProbeIdentity(
                role: "watch", run: log.run, mode: isHID ? "hid-\(mode)" : mode,
                system: ProcessInfo.processInfo.operatingSystemVersionString, simulated: simulated
            ))
            if isHID {
                let hid = HIDProbe(log: log, targetCentralID: targetCentralID)
                self.hid = hid
                let identityChar = try ProbeBridge.characteristic(
                    with: ProbeProtocol.hidIdentity, properties: .read, permissions: .readable
                )
                let discovery = try ProbeBridge.service(with: ProbeProtocol.hidDiscovery, characteristics: [identityChar])
                pendingServices = try [discovery] + hid.makeServices()
                let service = pendingServices.removeFirst()
                self.service = service
                log.record("hid.add.begin")
                try ProbeBridge.add(service, manager: manager)
                status = "等待 HID 服务注册"
                return
            }
            let identityChar = try ProbeBridge.characteristic(
                with: ProbeProtocol.identity, properties: .read, permissions: .readable
            )
            let echoChar = try ProbeBridge.characteristic(
                with: ProbeProtocol.echo, properties: [.read, .write], permissions: [.readable, .writeable]
            )
            let notifyChar = try ProbeBridge.characteristic(
                with: ProbeProtocol.notification, properties: .notify, permissions: .readable
            )
            let service = try ProbeBridge.service(
                with: ProbeProtocol.service, characteristics: [identityChar, echoChar, notifyChar]
            )
            self.service = service
            notifyCharacteristic = notifyChar
            log.record("gatt.add.begin")
            try ProbeBridge.add(service, manager: manager)
            status = "等待服务注册回调"
        } catch { fail("gatt.publish.exception", error: error) }
    }

    private func fail(_ event: String, error: Error? = nil) {
        status = event
        log.record(event, ["error": error.map { String(describing: $0) } ?? "none"])
    }

    func moveMouse(dx: Int = 20, dy: Int = 0) {
        guard let manager, let hid else { return }
        switch hid.move(manager: manager, dx: dx, dy: dy) {
        case true?: status = "已发送给 iPhone"
        case false?: status = "发送队列繁忙，请重试"
        case nil: status = "iPhone 输入尚未就绪，未发送"
        }
    }

    func clickMouse() {
        guard let manager, let hid else { return }
        switch hid.click(manager: manager) {
        case true?: status = "已轻点 iPhone"
        case false?: status = "输入队列繁忙，请重试"
        case nil: status = "iPhone 输入尚未就绪，未点击"
        }
    }

    func cancelPointerInput() {
        guard let manager else { return }
        hid?.cancelInput(manager: manager)
    }

    private func flushNotifications() {
        guard let manager, let characteristic = notifyCharacteristic else { return }
        for (identifier, item) in pendingNotifications {
            guard manager.updateValue(item.1, for: characteristic, onSubscribedCentrals: [item.0]) else {
                log.record("notify.backpressure")
                return
            }
            pendingNotifications.removeValue(forKey: identifier)
            log.record("notify.enqueued", ["bytes": "\(item.1.count)"])
        }
    }
}

extension PeripheralProbe: @preconcurrency CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral === manager else { return }
        log.record("manager.state", ["state": "\(peripheral.state.rawValue)", "authorization": "\(CBManager.authorization.rawValue)"])
        status = "蓝牙状态 \(peripheral.state.rawValue)"
        if peripheral.state == .poweredOn { publish() }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard peripheral === manager else { return }
        if let error { fail("gatt.add.failed", error: error); return }
        log.record("gatt.add.succeeded", ["uuid": service.uuid.uuidString])
        do {
            if !pendingServices.isEmpty {
                try ProbeBridge.add(pendingServices.removeFirst(), manager: peripheral)
                return
            }
            var advertisedServices = [ProbeProtocol.service]
            if isHID {
                advertisedServices = [ProbeProtocol.hidDiscovery, CBUUID(string: "1812")]
                if ProcessInfo.processInfo.arguments.contains("--hid-custom-only") {
                    advertisedServices = [ProbeProtocol.hidDiscovery]
                }
            }
            log.record("advertise.begin", ["requestedUUIDs": advertisedServices.map(\.uuidString).joined(separator: ",")])
            try ProbeBridge.advertise(with: peripheral, data: [
                CBAdvertisementDataLocalNameKey: isHID ? "WBLEMouse" : ProbeProtocol.localName,
                CBAdvertisementDataServiceUUIDsKey: advertisedServices,
            ])
        } catch { fail("advertise.exception", error: error) }
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        guard peripheral === manager else { return }
        if let error { fail("advertise.failed", error: error); return }
        status = isHID ? "等待 iPhone 连接" : "广播中，等待 Mac 验证"
        log.record("advertise.callback", ["isAdvertising": "\(peripheral.isAdvertising)"])
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        guard peripheral === manager else { return }
        if let hid, request.characteristic.uuid != ProbeProtocol.hidIdentity {
            hid.read(request, manager: peripheral); return
        }
        let value: Data
        switch request.characteristic.uuid {
        case ProbeProtocol.identity, ProbeProtocol.hidIdentity: value = identity
        case ProbeProtocol.echo: value = echoes[request.central.identifier] ?? Data()
        default: peripheral.respond(to: request, withResult: .readNotPermitted); return
        }
        guard request.offset <= value.count else {
            peripheral.respond(to: request, withResult: .invalidOffset)
            return
        }
        request.value = value.subdata(in: request.offset ..< value.count)
        peripheral.respond(to: request, withResult: .success)
        log.record("gatt.read", ["uuid": request.characteristic.uuid.uuidString, "offset": "\(request.offset)",
                                 "central": request.central.identifier.uuidString])
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        guard peripheral === manager else { return }
        if let hid { hid.write(requests, manager: peripheral); return }
        guard let first = requests.first else { return }
        guard requests.allSatisfy({
            $0.characteristic.uuid == ProbeProtocol.echo && $0.offset == 0 && ($0.value?.count ?? 0) == 16
        }) else {
            peripheral.respond(to: first, withResult: .invalidAttributeValueLength)
            return
        }
        for request in requests {
            guard let value = request.value else { return }
            echoes[request.central.identifier] = value
            pendingNotifications[request.central.identifier] = (request.central, ProbeProtocol.notificationValue(for: value))
            log.record("gatt.write", ["challenge": value.base64EncodedString()])
        }
        peripheral.respond(to: first, withResult: .success)
        flushNotifications()
        status = "已处理读写，结果以 Mac 为准"
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        guard peripheral === manager else { return }
        if let hid, !hid.isInput(characteristic) { return }
        subscriptions[central.identifier, default: []].insert(characteristic.uuid)
        subscribedHostCount = subscriptions.count
        phoneConnected = targetCentralID.flatMap { subscriptions[$0] }?.isEmpty == false
        log.record("notify.subscribed", ["uuid": characteristic.uuid.uuidString, "central": central.identifier.uuidString])
        if isHID { status = phoneConnected ? "iPhone 已连接" : "等待 iPhone 连接" }
        hid?.subscribed(characteristic, central: central, manager: peripheral)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        guard peripheral === manager else { return }
        subscriptions[central.identifier]?.remove(characteristic.uuid)
        if subscriptions[central.identifier]?.isEmpty == true { subscriptions.removeValue(forKey: central.identifier) }
        subscribedHostCount = subscriptions.count
        phoneConnected = targetCentralID.flatMap { subscriptions[$0] }?.isEmpty == false
        log.record("notify.unsubscribed", ["uuid": characteristic.uuid.uuidString, "central": central.identifier.uuidString])
        if isHID { status = phoneConnected ? "iPhone 已连接" : "等待 iPhone 连接" }
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        guard peripheral === manager else { return }
        hid?.flush(manager: peripheral)
        flushNotifications()
    }
}
