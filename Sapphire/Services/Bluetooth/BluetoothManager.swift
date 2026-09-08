//
//  BluetoothManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-07.
//

import Foundation
import Combine
import IOBluetooth
import AppKit

struct BluetoothDeviceState: Hashable {
    enum EventType: Hashable {
        case connected, disconnected, batteryLow
    }
    let eventUUID = UUID()
    let id: String, name: String, iconName: String, eventType: EventType
    var batteryLevel: Int? = nil
    let isContinuityDevice: Bool
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.eventUUID == rhs.eventUUID }
    func hash(into hasher: inout Hasher) { hasher.combine(eventUUID) }
}

enum BluetoothWidgetPresentation {
    static func title(for device: BluetoothDeviceState?) -> String {
        device?.name ?? "Bluetooth"
    }

    static func subtitle(for device: BluetoothDeviceState?) -> String {
        guard let device, device.eventType != .disconnected else { return "No device connected" }
        if let level = device.batteryLevel { return "\(level)% battery" }
        return "Connected"
    }
}

@MainActor
class BluetoothManager: NSObject, ObservableObject {
    @Published var lastEvent: BluetoothDeviceState?

    var isBluetoothPoweredOn: Bool {
        IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON
    }

    private var connectionNotification: IOBluetoothUserNotification?
    private var disconnectionNotifications: [String: IOBluetoothUserNotification] = [:]
    private var recentlyConnectedDebounceSet: Set<String> = []

    private let iDeviceBattery = IDeviceBattery.shared
    private let batteryReader = BluetoothBatteryReader.shared
    private var periodicPollingTimer: Timer?

    private var cancellables = Set<AnyCancellable>()
    private var isProximityScanActive = false

    override init() {
        super.init()
        ud.register(defaults: ["readBTDevice": true, "readBTHID": true, "readIDevice": true, "updateInterval": 1])

        SPBluetoothDataModel.shared.refeshData { [weak self] _ in
            guard let self = self else { return }
            self.checkForInitiallyConnectedDevices()
        }

        Task {
            await batteryReader.refreshAllBatteries()
        }

        startPollingServices()

        self.connectionNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAirPodsUpdate(_:)),
            name: .didUpdateAirPodsBattery,
            object: nil
        )

        AuthenticationManager.shared.$isScanning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isScanning in
                self?.isProximityScanActive = isScanning
            }
            .store(in: &cancellables)
    }

    deinit {
        periodicPollingTimer?.invalidate()
        connectionNotification?.unregister()
        disconnectionNotifications.values.forEach { $0.unregister() }
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleAirPodsUpdate(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.handleAirPodsUpdateOnMain(notification)
        }
    }

    @MainActor
    private func handleAirPodsUpdateOnMain(_ notification: Notification) {
        guard !isProximityScanActive else { return }

        guard let userInfo = notification.userInfo,
              let bleName = userInfo["name"] as? String,
              let level = userInfo["level"] as? Int else {
            return
        }

        guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice],
              let classicDevice = pairedDevices.first(where: {
                  guard let classicName = $0.name else { return false }
                  let cleanClassic = classicName.replacingOccurrences(of: "(ANC)", with: "").replacingOccurrences(of: " ", with: "").lowercased()
                  let cleanBLE = bleName.replacingOccurrences(of: "- Find My", with: "").replacingOccurrences(of: "’s", with: "").replacingOccurrences(of: " ", with: "").lowercased()
                  return cleanBLE.contains(cleanClassic) || cleanClassic.contains(cleanBLE)
              }) else {
            return
        }

        publishConnectedEvent(for: classicDevice, batteryLevel: level)
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        Task { @MainActor [weak self] in
            self?.handleDeviceConnected(device: device)
        }
    }

    @MainActor
    private func handleDeviceConnected(device: IOBluetoothDevice) {
        guard !isProximityScanActive else {
            registerForDisconnect(device: device)
            return
        }

        guard let address = device.addressString, device.name != nil else { return }

        if recentlyConnectedDebounceSet.contains(address) { return }
        recentlyConnectedDebounceSet.insert(address)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.recentlyConnectedDebounceSet.remove(address)
        }

        playConnectionSound()
        publishConnectedEvent(for: device, batteryLevel: device.normalizedBatteryPercent)
        scheduleBatteryRefresh(for: device)
        registerForDisconnect(device: device)
    }

    private func findBatteryLevel(for device: IOBluetoothDevice) async -> Int? {
        if let immediate = device.normalizedBatteryPercent { return immediate }
        guard let name = device.name else { return nil }

        MagicBattery.shared.getIOBTBattery()
        if let cached = cachedBattery(named: name) { return cached }

        await withCheckedContinuation { continuation in
            SPBluetoothDataModel.shared.refeshData { _ in continuation.resume() } error: { continuation.resume() }
        }

        MagicBattery.shared.getIOBTBattery()
        if let cached = cachedBattery(named: name) { return cached }

        if let match = await BluetoothBatteryReader.getSystemProfileBatteries().first(where: { $0.name == name }) {
            return BluetoothBatteryParsing.percent(from: match.level)
        }

        await batteryReader.refreshAllBatteries()
        return cachedBattery(named: name) ?? device.normalizedBatteryPercent
    }

    private func cachedBattery(named name: String) -> Int? {
        BluetoothBatteryParsing.percent(from: AirBatteryModel.getByName(name)?.batteryLevel)
    }

    @MainActor
    private func publishConnectedEvent(for device: IOBluetoothDevice, batteryLevel: Int?) {
        guard let address = device.addressString, let name = device.name else { return }
        lastEvent = BluetoothDeviceState(
            id: address,
            name: name,
            iconName: IconMapper.icon(for: device),
            eventType: .connected,
            batteryLevel: batteryLevel,
            isContinuityDevice: isContinuityDevice(name: name)
        )
    }

    private func scheduleBatteryRefresh(for device: IOBluetoothDevice) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await self?.updateBatteryIfAvailable(for: device)
        }
    }

    @MainActor
    private func updateBatteryIfAvailable(for device: IOBluetoothDevice) async {
        guard device.isConnected(), let batteryLevel = await findBatteryLevel(for: device) else { return }
        if lastEvent?.id == device.addressString, lastEvent?.eventType == .connected, lastEvent?.batteryLevel == batteryLevel {
            return
        }
        publishConnectedEvent(for: device, batteryLevel: batteryLevel)
    }

    private func playConnectionSound() {
        playBluetoothSound("head_gestures_double_nod")
    }

    private func playDisconnectionSound() {
        playBluetoothSound("jbl_cancel")
    }

    private func playBluetoothSound(_ resource: String) {
        guard SettingsModel.shared.settings.bluetoothNotifySound else { return }
        if let soundURL = Bundle.main.url(forResource: resource, withExtension: "caf") {
            NSSound(contentsOf: soundURL, byReference: true)?.play()
        } else {
            NSSound(named: "Tink")?.play()
        }
    }

    private func registerForDisconnect(device: IOBluetoothDevice) {
        guard let address = device.addressString else { return }
        if self.disconnectionNotifications[address] == nil {
            self.disconnectionNotifications[address] = device.register(
                forDisconnectNotification: self,
                selector: #selector(self.deviceDisconnected(_:device:))
            )
        }
    }

    @objc private func deviceDisconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        Task { @MainActor [weak self] in
            self?.handleDeviceDisconnected(device: device)
        }
    }

    @MainActor
    private func handleDeviceDisconnected(device: IOBluetoothDevice) {
        guard !isProximityScanActive else {
            if let address = device.addressString, let notificationToRemove = disconnectionNotifications.removeValue(forKey: address) {
                notificationToRemove.unregister()
            }
            return
        }

        guard let address = device.addressString, let name = device.name else { return }

        playDisconnectionSound()

        lastEvent = BluetoothDeviceState(
            id: address, name: name, iconName: IconMapper.icon(for: device),
            eventType: .disconnected, isContinuityDevice: isContinuityDevice(name: name)
        )

        if let notificationToRemove = disconnectionNotifications.removeValue(forKey: address) {
            notificationToRemove.unregister()
        }
    }

    private func checkForInitiallyConnectedDevices() {
        guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }
        for device in pairedDevices where device.isConnected() {
            handleDeviceConnected(device: device)
        }
    }

    private func startPollingServices() {
        periodicPollingTimer?.invalidate()
        periodicPollingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollForIDeviceUpdates()
            }
        }
    }

    private func pollForIDeviceUpdates() {
        iDeviceBattery.scanDevices()
        Task { await batteryReader.refreshAllBatteries() }
        guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }
        for device in pairedDevices where device.isConnected() {
            Task { await self.updateBatteryIfAvailable(for: device) }
        }
    }

    private func isContinuityDevice(name: String) -> Bool {
        let lowercasedName = name.lowercased()
        let keywords = ["macbook", "imac", "mac mini", "mac studio", "mac pro", "iphone", "ipad", "apple watch", "vision pro"]
        return keywords.contains { lowercasedName.contains($0) }
    }
}