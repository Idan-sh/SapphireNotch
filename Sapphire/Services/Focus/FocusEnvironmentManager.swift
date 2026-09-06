//
//  FocusEnvironmentManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-25
//

import Foundation
import AppKit
import Combine

@MainActor
final class FocusEnvironmentManager {
    static let shared = FocusEnvironmentManager()

    private(set) var isActive = false

    private var hideWallpaper = false
    private var appLimitEnabled = false
    private var appLimit = 2

    private let cid = CGSMainConnectionID()
    private var refreshTimer: Timer?
    private var activeAppCancellables = Set<AnyCancellable>()
    private var wallpaperWindows: [NSWindow] = []

    private var recentApps: [String] = []
    private var hiddenWindows: Set<CGWindowID> = []
    private var hiddenBundleIDs: Set<String> = []

    static let essentials: Set<String> = [
        "com.apple.finder",
        "com.apple.systempreferences",
        "com.apple.SystemSettings",
        "com.apple.dock",
        "com.apple.controlcenter",
    ]

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.restoreHiddenWindows()
        }
    }

    // MARK: - Public API

    func configure(
        hideWallpaper: Bool,
        appLimitEnabled: Bool,
        appLimit: Int
    ) {
        self.hideWallpaper = hideWallpaper
        self.appLimitEnabled = appLimitEnabled
        self.appLimit = max(1, appLimit)
        if isActive { refresh() }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isActive else { return }
        isActive = enabled
        if enabled {
            recentApps.removeAll()
            start()
        } else {
            stop()
        }
    }

    // MARK: - Lifecycle

    private func start() {
        guard activeAppCancellables.isEmpty else { return }
        let monitor = ActiveAppMonitor.shared

        monitor.$activeAppBundleID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] bundleID in
                guard let self, let bundleID else { return }
                self.handleFrontAppChange(bundleID: bundleID)
            }
            .store(in: &activeAppCancellables)

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    private func stop() {
        activeAppCancellables.removeAll()
        refreshTimer?.invalidate()
        refreshTimer = nil

        for window in wallpaperWindows { window.orderOut(nil) }
        wallpaperWindows.removeAll()

        restoreHiddenWindows()
        recentApps.removeAll()
    }

    // MARK: - Refresh

    private func refresh() {
        guard isActive else { return }
        updateWallpaperWindows()
        if appLimitEnabled { reapplyHiddenWindows() }
    }

    // MARK: - Wallpaper hiding

    private var appliedWallpaperFrames: [NSRect] = []

    private func updateWallpaperWindows() {
        guard hideWallpaper else {
            if !wallpaperWindows.isEmpty {
                for window in wallpaperWindows { window.orderOut(nil) }
                wallpaperWindows.removeAll()
                appliedWallpaperFrames.removeAll()
            }
            return
        }

        let currentFrames = NSScreen.screens.map(\.frame)
        guard currentFrames != appliedWallpaperFrames else {
            for window in wallpaperWindows { window.orderFrontRegardless() }
            return
        }
        for window in wallpaperWindows { window.orderOut(nil) }
        wallpaperWindows.removeAll()
        appliedWallpaperFrames = currentFrames

        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
            window.isOpaque = true
            window.backgroundColor = .black
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            window.orderFrontRegardless()
            wallpaperWindows.append(window)
        }
    }

    // MARK: - App limiting

    private func handleFrontAppChange(bundleID: String) {
        guard isActive, appLimitEnabled else { return }
        if bundleID == Bundle.main.bundleIdentifier || Self.essentials.contains(bundleID) { return }

        recentApps.removeAll { $0 == bundleID }
        recentApps.insert(bundleID, at: 0)

        while recentApps.count > appLimit {
            let gone = recentApps.removeLast()
            hideWindows(of: gone)
        }
    }

    private func hideWindows(of bundleID: String) {
        hiddenBundleIDs.insert(bundleID)
        for windowNumber in windows(of: bundleID) {
            guard !hiddenWindows.contains(windowNumber) else { continue }
            _ = CGSOrderWindow(cid, windowNumber, 0, 0)
            hiddenWindows.insert(windowNumber)
        }
    }

    private func reapplyHiddenWindows() {
        guard !hiddenBundleIDs.isEmpty else { return }
        for bundleID in hiddenBundleIDs {
            for windowNumber in windows(of: bundleID) {
                guard !hiddenWindows.contains(windowNumber) else { continue }
                _ = CGSOrderWindow(cid, windowNumber, 0, 0)
                hiddenWindows.insert(windowNumber)
            }
        }
    }

    private func restoreHiddenWindows() {
        for windowNumber in hiddenWindows {
            _ = CGSOrderWindow(cid, windowNumber, 1, 0)
        }
        hiddenWindows.removeAll()
        hiddenBundleIDs.removeAll()
    }

    // MARK: - Window enumeration (CGWindowList)

    private func windows(of bundleID: String) -> Set<CGWindowID> {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var result = Set<CGWindowID>()
        for info in list {
            guard let pidValue = info[kCGWindowOwnerPID as String] as? Int,
                  let app = NSRunningApplication(processIdentifier: pid_t(pidValue)),
                  app.bundleIdentifier == bundleID else { continue }
            if let layer = info[kCGWindowLayer as String] as? Int, layer != 0 { continue }
            guard let windowNumber = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            result.insert(windowNumber)
        }
        return result
    }
}
