//
//  BluetoothBatteryParsing.swift
//  Sapphire
//

import Foundation

enum BluetoothBatteryParsing {
    struct ProfileBattery: Equatable {
        let name: String
        let level: Int
        let type: String
    }

    static func percent(from value: Any?) -> Int? {
        let parsed: Int?
        if let i = value as? Int {
            parsed = i
        } else if let n = value as? NSNumber {
            parsed = n.intValue
        } else if let s = value as? String {
            parsed = Int(s.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            parsed = nil
        }
        guard let parsed, (1...100).contains(parsed) else { return nil }
        return parsed
    }

    static func parseSystemProfilerBatteries(_ data: Data) -> [ProfileBattery] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let btData = json["SPBluetoothDataType"] as? [[String: Any]],
              let devices = btData.first?["device_connected"] as? [[String: Any]] else {
            return []
        }
        return devices.compactMap(parseConnectedEntry)
    }

    private static func parseConnectedEntry(_ device: [String: Any]) -> ProfileBattery? {
        let name: String
        let details: [String: Any]
        if let flatName = device["device_name"] as? String {
            name = flatName
            details = device
        } else if let nestedName = device.keys.first, let nested = device[nestedName] as? [String: Any] {
            name = nestedName
            details = nested
        } else {
            return nil
        }

        let type = details["device_minorType"] as? String ?? "unknown"
        if let level = percent(from: details["device_batteryLevelSingle"]) ?? percent(from: details["device_batteryLevel"]) {
            return ProfileBattery(name: name, level: level, type: type)
        }

        let sides = ["device_batteryLevelLeft", "device_batteryLevelRight", "device_batteryLevelCase"]
            .compactMap { percent(from: details[$0]) }
        guard !sides.isEmpty else { return nil }
        return ProfileBattery(name: name, level: sides.reduce(0, +) / sides.count, type: type)
    }
}
