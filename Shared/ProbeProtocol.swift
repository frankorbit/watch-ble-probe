import CoreBluetooth
import Foundation

@MainActor
enum ProbeProtocol {
    static let service = CBUUID(string: "F753D401-8753-43CF-A613-19C364B377B0")
    static let identity = CBUUID(string: "F753D402-8753-43CF-A613-19C364B377B0")
    static let echo = CBUUID(string: "F753D403-8753-43CF-A613-19C364B377B0")
    static let notification = CBUUID(string: "F753D404-8753-43CF-A613-19C364B377B0")
    static let localName = "WBLEProbe"
    static let hidDiscovery = CBUUID(string: "F753D410-8753-43CF-A613-19C364B377B0")
    static let hidIdentity = CBUUID(string: "F753D411-8753-43CF-A613-19C364B377B0")

    static func notificationValue(for challenge: Data) -> Data {
        Data("notify:".utf8) + challenge
    }
}

struct ProbeIdentity: Codable {
    let role: String
    let run: String
    let mode: String
    let system: String
    let simulated: Bool
}
