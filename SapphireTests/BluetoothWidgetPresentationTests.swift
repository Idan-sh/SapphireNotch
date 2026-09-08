//
//  BluetoothWidgetPresentationTests.swift
//  Sapphire
//

import Foundation
import Testing
@testable import Sapphire

struct BluetoothWidgetPresentationTests {
    @Test func connectedDeviceWithoutBatteryIsNotReportedAsDisconnected() {
        let device = BluetoothDeviceState(
            id: "aa-bb",
            name: "WH-1000XM5",
            iconName: "headphones",
            eventType: .connected,
            batteryLevel: nil,
            isContinuityDevice: false
        )

        #expect(BluetoothWidgetPresentation.title(for: device) == "WH-1000XM5")
        #expect(BluetoothWidgetPresentation.subtitle(for: device) == "Connected")
    }

    @Test func connectedDeviceWithBatteryShowsPercentage() {
        let device = BluetoothDeviceState(
            id: "aa-bb",
            name: "AirPods Pro",
            iconName: "airpodspro",
            eventType: .connected,
            batteryLevel: 72,
            isContinuityDevice: false
        )

        #expect(BluetoothWidgetPresentation.subtitle(for: device) == "72% battery")
    }

    @Test func disconnectedEventShowsNoDeviceConnected() {
        let device = BluetoothDeviceState(
            id: "aa-bb",
            name: "WH-1000XM5",
            iconName: "headphones",
            eventType: .disconnected,
            batteryLevel: nil,
            isContinuityDevice: false
        )

        #expect(BluetoothWidgetPresentation.title(for: device) == "WH-1000XM5")
        #expect(BluetoothWidgetPresentation.subtitle(for: device) == "No device connected")
    }

    @Test func missingEventShowsGenericDisconnectedState() {
        #expect(BluetoothWidgetPresentation.title(for: nil) == "Bluetooth")
        #expect(BluetoothWidgetPresentation.subtitle(for: nil) == "No device connected")
    }
}
