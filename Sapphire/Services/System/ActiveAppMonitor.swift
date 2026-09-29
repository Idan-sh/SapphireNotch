//
//  ActiveAppMonitor.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-09.
//

import AppKit
import Combine
import ApplicationServices
import os.log

private let activeAppLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "ActiveAppMonitor")

extension Notification.Name {
    static let activeAppDidChange = Notification.Name("com.sapphire.activeAppDidChange")
}

@MainActor
class ActiveAppMonitor: ObservableObject {

    static let shared = ActiveAppMonitor()

    @Published private(set) var isLyricsAllowedForActiveApp: Bool = true
    @Published private(set) var activeAppBundleID: String?
    @Published private(set) var isFullScreen: Bool = false
    @Published private(set) var fullScreenDisplayID: CGDirectDisplayID? = nil

    private let settingsModel: SettingsModel
    private var cancellables = Set<AnyCancellable>()

    private let kAXMainWindowAttribute = "AXMainWindow" as CFString
    private let kAXFullScreenAttribute = "AXFullScreen" as CFString

    private init() {
        self.settingsModel = SettingsModel.shared

        let spaceChangePublisher = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification).map { _ in () }
        let appChangePublisher = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification).map { _ in () }

        Publishers.Merge(spaceChangePublisher, appChangePublisher)
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateActiveAppState() }
            .store(in: &cancellables)

        $activeAppBundleID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateLyricPermission() }
            .store(in: &cancellables)

        settingsModel.$settings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] settings in
                guard let self else { return }
                self.updateLyricPermission()

                let observationEnabled = settings.snapOnWindowDragEnabled || settings.snapDragEnabled
                DragSession.shared.setWindowDragObservation(observationEnabled)
            }
            .store(in: &cancellables)

        updateActiveAppState()
        DragSession.shared.setWindowDragObservation(
            settingsModel.settings.snapOnWindowDragEnabled || settingsModel.settings.snapDragEnabled
        )
    }

    private func updateActiveAppState() {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication, let bundleID = frontmostApp.bundleIdentifier else {
            if isFullScreen != false { isFullScreen = false }
            if activeAppBundleID != nil { activeAppBundleID = nil }
            return
        }
        guard bundleID != Bundle.main.bundleIdentifier else {
            return
        }

        if activeAppBundleID != bundleID {
            activeAppBundleID = bundleID
            NotificationCenter.default.post(name: .activeAppDidChange, object: nil)
        }

        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        var window: AnyObject?

        AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute, &window)

        var isCurrentlyFullScreen = false
        var currentlyFullScreenDisplayID: CGDirectDisplayID? = nil
        if let window = window {
            let windowElement = window as! AXUIElement
            var isFullScreenValue: AnyObject?

            let result = AXUIElementCopyAttributeValue(windowElement, kAXFullScreenAttribute, &isFullScreenValue)

            if result == .success, let isFullScreenNumber = isFullScreenValue as? NSNumber {
                isCurrentlyFullScreen = isFullScreenNumber.boolValue
            }

            if isCurrentlyFullScreen {
                currentlyFullScreenDisplayID = displayID(forFullScreenWindow: windowElement)
            }
        }

        if self.isFullScreen != isCurrentlyFullScreen || self.fullScreenDisplayID != currentlyFullScreenDisplayID {
            activeAppLog.info("full-screen state changed: isFullScreen=\(isCurrentlyFullScreen) displayID=\(currentlyFullScreenDisplayID.map(String.init) ?? "nil") app=\(bundleID)")
            self.isFullScreen = isCurrentlyFullScreen
            self.fullScreenDisplayID = currentlyFullScreenDisplayID
        }
    }

    private func updateLyricPermission() {
        let newPermissionState: Bool = {
            guard settingsModel.settings.showLyricsInLiveActivity else { return false }
            guard let activeBundleID = activeAppBundleID else { return true }
            if let isAllowed = settingsModel.settings.musicAppStates[activeBundleID] { return isAllowed }
            var isBrowser = false
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: activeBundleID),
               let bundle = Bundle(url: appURL),
               let urlTypes = bundle.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] {
                isBrowser = urlTypes.contains { ($0["CFBundleURLSchemes"] as? [String])?.contains("http") ?? false }
            }
            return !isBrowser
        }()
        if isLyricsAllowedForActiveApp != newPermissionState {
            isLyricsAllowedForActiveApp = newPermissionState
        }
    }

    private func displayID(forFullScreenWindow windowElement: AXUIElement) -> CGDirectDisplayID? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionValue = positionRef, let sizeValue = sizeRef else {
            return nil
        }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }

        let center = NSPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) else {
            return nil
        }
        return screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
