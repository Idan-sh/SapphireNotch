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
    @Published private(set) var isWindowDragging: Bool = false

    private let settingsModel: SettingsModel
    private var cancellables = Set<AnyCancellable>()

    private let kAXMainWindowAttribute = "AXMainWindow" as CFString
    private let kAXFullScreenAttribute = "AXFullScreen" as CFString

    private var mouseDragMonitor: Any?
    private var mouseUpMonitor: Any?
    private var lastDragCheckTime: TimeInterval = 0
    private var dragStartWindowOrigins: [CGWindowID: CGPoint] = [:]
    private var lastWindowDragObservationEnabled: Bool?
    private let windowDragOriginThreshold: CGFloat = 6

    deinit {
        if let monitor = mouseDragMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = mouseUpMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

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
                guard self.lastWindowDragObservationEnabled != observationEnabled else { return }
                self.lastWindowDragObservationEnabled = observationEnabled
                self.setupWindowDragMonitoring()
            }
            .store(in: &cancellables)

        updateActiveAppState()
        setupWindowDragMonitoring()
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

    // MARK: - Window Drag Detection

    private func setupWindowDragMonitoring() {
        teardownWindowDragMonitoring()

        let settings = settingsModel.settings
        let observationEnabled = settings.snapOnWindowDragEnabled || settings.snapDragEnabled
        lastWindowDragObservationEnabled = observationEnabled
        guard observationEnabled else { return }

        mouseDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            Task { @MainActor in
                self?.handleMouseDraggedForWindowMove()
            }
        }

        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            Task { @MainActor in
                self?.handleMouseUpForWindowMove()
            }
        }
    }

    private func teardownWindowDragMonitoring() {
        if let monitor = mouseDragMonitor {
            NSEvent.removeMonitor(monitor)
            mouseDragMonitor = nil
        }
        if let monitor = mouseUpMonitor {
            NSEvent.removeMonitor(monitor)
            mouseUpMonitor = nil
        }
        dragStartWindowOrigins.removeAll()
        if isWindowDragging {
            isWindowDragging = false
        }
    }

    private func handleMouseDraggedForWindowMove() {
        let now = CACurrentMediaTime()
        if now - lastDragCheckTime < 0.03 { return }
        lastDragCheckTime = now

        guard NSEvent.pressedMouseButtons == 1 else { return }
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              frontmostApp.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return
        }

        let frames = layerZeroWindowFrames(for: frontmostApp.processIdentifier)
        guard !frames.isEmpty else { return }

        if dragStartWindowOrigins.isEmpty {
            for (windowID, frame) in frames {
                dragStartWindowOrigins[windowID] = frame.origin
            }
            return
        }

        for (windowID, frame) in frames {
            guard let startOrigin = dragStartWindowOrigins[windowID] else {
                // New window mid-drag (e.g. tab tear-off); wait until it moves.
                dragStartWindowOrigins[windowID] = frame.origin
                continue
            }

            let dx = abs(frame.origin.x - startOrigin.x)
            let dy = abs(frame.origin.y - startOrigin.y)
            if dx >= windowDragOriginThreshold || dy >= windowDragOriginThreshold {
                isWindowDragging = true
                return
            }
        }
    }

    private func handleMouseUpForWindowMove() {
        dragStartWindowOrigins.removeAll()
        if isWindowDragging {
            isWindowDragging = false
        }
    }

    private func layerZeroWindowFrames(for pid: pid_t) -> [CGWindowID: CGRect] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return [:]
        }

        var result: [CGWindowID: CGRect] = [:]
        for info in list {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == pid else { continue }
            if let layer = info[kCGWindowLayer as String] as? Int, layer != 0 { continue }
            guard let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"], let height = bounds["Height"],
                  width >= 200, height >= 120,
                  let x = bounds["X"], let y = bounds["Y"] else {
                continue
            }
            result[windowID] = CGRect(x: x, y: y, width: width, height: height)
        }
        return result
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
