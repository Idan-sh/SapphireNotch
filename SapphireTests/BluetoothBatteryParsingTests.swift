//
//  BluetoothBatteryParsingTests.swift
//  Sapphire
//

import Foundation
import Testing
@testable import Sapphire

struct BluetoothBatteryParsingTests {
    @Test func percentCoercesIntAndPercentString() {
        #expect(BluetoothBatteryParsing.percent(from: 70) == 70)
        #expect(BluetoothBatteryParsing.percent(from: 0) == nil)
        #expect(BluetoothBatteryParsing.percent(from: 101) == nil)
        #expect(BluetoothBatteryParsing.percent(from: "70%") == 70)
        #expect(BluetoothBatteryParsing.percent(from: " 8 %") == 8)
        #expect(BluetoothBatteryParsing.percent(from: NSNumber(value: 55)) == 55)
        #expect(BluetoothBatteryParsing.percent(from: nil) == nil)
    }

    @Test func nestedSystemProfilerJSONReadsSingleBattery() {
        let json = """
        {
          "SPBluetoothDataType": [{
            "device_connected": [{
              "Idan's XM4 Headphones": {
                "device_address": "80:99:E7:8E:AE:FD",
                "device_minorType": "Headset",
                "device_batteryLevelSingle": "70%"
              }
            }]
          }]
        }
        """.data(using: .utf8)!

        let results = BluetoothBatteryParsing.parseSystemProfilerBatteries(json)
        #expect(results.count == 1)
        #expect(results[0].name == "Idan's XM4 Headphones")
        #expect(results[0].level == 70)
        #expect(results[0].type == "Headset")
    }

    @Test func nestedSystemProfilerJSONWithoutBatteryReturnsEmpty() {
        let json = """
        {
          "SPBluetoothDataType": [{
            "device_connected": [{
              "Idan's XM4 Headphones": {
                "device_address": "80:99:E7:8E:AE:FD",
                "device_minorType": "Headset"
              }
            }]
          }]
        }
        """.data(using: .utf8)!

        #expect(BluetoothBatteryParsing.parseSystemProfilerBatteries(json).isEmpty)
    }

    @Test func flatSystemProfilerJSONStillParses() {
        let json = """
        {
          "SPBluetoothDataType": [{
            "device_connected": [{
              "device_name": "WH-1000XM5",
              "device_minorType": "Headset",
              "device_batteryLevelSingle": "42%"
            }]
          }]
        }
        """.data(using: .utf8)!

        let results = BluetoothBatteryParsing.parseSystemProfilerBatteries(json)
        #expect(results.map(\.name) == ["WH-1000XM5"])
        #expect(results.map(\.level) == [42])
    }
}
