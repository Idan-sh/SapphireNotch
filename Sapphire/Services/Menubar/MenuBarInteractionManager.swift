//
//  MenuBarInteractionManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-11-08
//

import Cocoa
import Combine

@MainActor
final class MenuBarInteractionManager {
    static let shared = MenuBarInteractionManager()

    // MARK: - Monitors
    private var pollingTimer: Timer?
    private var clickToken: UUID?
    private var scrollMonitor: Any?
    private var hoverTriggerTimer: Timer?

    // MARK: - State
    public var isMonitoring = false
    private var isSuspended = false
    private var disabledUntil: Date?
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        isSuspended = false
        if cancellables.isEmpty {
            SettingsModel.shared.$settings.receive(on: DispatchQueue.main).sink { [weak self] settings in
                guard let self = self, self.isMonitoring else { return }
                self.updateMonitors(for: settings)
            }.store(in: &cancellables)
        }
        updateMonitors(for: SettingsModel.shared.settings)
    }

    func setSuspended(_ suspended: Bool) {
        guard isSuspended != suspended else { return }
        isSuspended = suspended
        if suspended {
            hoverTriggerTimer?.invalidate()
            hoverTriggerTimer = nil
        }
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        isSuspended = false
        stopHoverMonitoring()
        stopClickMonitoring()
        stopScrollMonitoring()
        cancellables.removeAll()
    }

    private func updateMonitors(for settings: Settings) {
        if settings.showOnHover && pollingTimer == nil {
            startHoverMonitoring()
        } else if !settings.showOnHover && pollingTimer != nil {
            stopHoverMonitoring()
        }

        if settings.showOnClick && clickToken == nil {
            startClickMonitoring()
        } else if !settings.showOnClick && clickToken != nil {
            stopClickMonitoring()
        }

        if settings.showOnScroll && scrollMonitor == nil {
            startScrollMonitoring()
        } else if !settings.showOnScroll && scrollMonitor != nil {
            stopScrollMonitoring()
        }
    }

    func temporarilyDisable(for duration: TimeInterval) {
        disabledUntil = Date().addingTimeInterval(duration)
    }

    // MARK: - Hover Monitoring (poll mouse location — event probes on
    // ignoresMouseEvents windows do not reliably deliver enter/exit)

    private func startHoverMonitoring() {
        guard pollingTimer == nil else { return }

        let interval: TimeInterval = 0.05
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkMousePosition() }
        }
        timer.tolerance = interval * 0.4
        RunLoop.main.add(timer, forMode: .common)
        pollingTimer = timer
    }

    private func stopHoverMonitoring() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        hoverTriggerTimer?.invalidate()
        hoverTriggerTimer = nil
    }

    private func checkMousePosition() {
        guard isMonitoring, !isSuspended else { return }
        guard Date() >= (disabledUntil ?? .distantPast) else { return }

        let location = NSEvent.mouseLocation
        let isNearTop = NSScreen.screens.contains { screen in
            location.y >= (screen.frame.maxY - 30)
        }

        if isNearTop && isLocationInMenuBar(location) {
            if hoverTriggerTimer == nil {
                let delay = max(0, SettingsModel.shared.settings.showOnHoverDelay)
                let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated { self?.showHiddenItems() }
                }
                RunLoop.main.add(timer, forMode: .common)
                hoverTriggerTimer = timer
            }
        } else {
            hoverTriggerTimer?.invalidate()
            hoverTriggerTimer = nil
        }
    }

    // MARK: - Click Monitoring

    private func startClickMonitoring() {
        guard clickToken == nil else { return }

        clickToken = GlobalInputMonitor.shared.onLeftMouseDown { [weak self] in
            guard let self = self, !self.isSuspended else { return }
            guard Date() >= (self.disabledUntil ?? .distantPast) else { return }

            let location = NSEvent.mouseLocation
            if self.isLocationInMenuBar(location), self.isClickInEmptyMenuBarArea(location) {
                self.showHiddenItems()
            }
        }
    }

    private func stopClickMonitoring() {
        if let token = clickToken {
            GlobalInputMonitor.shared.remove(token)
            clickToken = nil
        }
    }

    // MARK: - Scroll Monitoring

    private func startScrollMonitoring() {
        guard scrollMonitor == nil else { return }

        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return }
            Task { @MainActor in
                guard self.isMonitoring, !self.isSuspended else { return }
                guard Date() >= (self.disabledUntil ?? .distantPast) else { return }
                guard abs(event.scrollingDeltaY) > 2 || abs(event.scrollingDeltaX) > 2 else { return }

                let location = NSEvent.mouseLocation
                if self.isLocationInMenuBar(location) {
                    self.showHiddenItems()
                }
            }
        }
    }

    private func stopScrollMonitoring() {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
    }

    // MARK: - Helpers

    private func isLocationInMenuBar(_ loc: CGPoint) -> Bool {
        guard let s = NSScreen.screens.first(where: { NSMouseInRect(loc, $0.frame, false) }) else { return false }

        let menuBarHeight = s.frame.height - s.visibleFrame.height
        let actualHeight = menuBarHeight > 0 ? menuBarHeight : 24.0
        let menuBarRect = CGRect(
            x: s.frame.origin.x,
            y: s.frame.maxY - actualHeight,
            width: s.frame.width,
            height: actualHeight
        )
        return menuBarRect.contains(loc)
    }

    private func isClickInEmptyMenuBarArea(_ loc: CGPoint) -> Bool {
        let items = MenuBarItemDetector.detectItems()
        return !items.contains { $0.frame.contains(loc) }
    }

    private func showHiddenItems() {
        (NSApp.delegate as? AppDelegate)?.statusBarController?.expand()
    }
}
