//
//  AppBlocker.swift
//  Sapphire
//
//  Community shim for the private AppBlocker / AppShieldView types.
//  Provides enough API surface for Focus sessions without the private package.
//

import AppKit
import SwiftUI
import Combine

@MainActor
final class AppBlocker {
    var isBlocked: ((String) -> Bool)?
    var makeShieldContent: ((String, String) -> AnyView)?
    var onAppActivated: ((String, String, NSRunningApplication) -> Void)?
    var forceClosesOnActivation: Bool = false

    private(set) var isBlocking: Bool = false
    private var activationObserver: NSObjectProtocol?

    func setBlocking(_ enabled: Bool) {
        isBlocking = enabled
        if enabled {
            startObserving()
            refresh()
        } else {
            stopObserving()
            removeAllShields()
        }
    }

    func refresh() {
        guard isBlocking else { return }
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier,
                  bundleID != Bundle.main.bundleIdentifier,
                  isBlocked?(bundleID) == true else { continue }
            if forceClosesOnActivation {
                app.hide()
            }
        }
    }

    func removeAllShields() {}

    func unshield(bundleID: String) {}

    private func startObserving() {
        stopObserving()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self,
                      let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let bundleID = app.bundleIdentifier else { return }
                let appName = app.localizedName ?? bundleID
                self.onAppActivated?(appName, bundleID, app)
                if self.isBlocking, self.isBlocked?(bundleID) == true, self.forceClosesOnActivation {
                    app.hide()
                }
            }
        }
    }

    private func stopObserving() {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }
}

enum AppShieldMode {
    case focus(
        intensity: FocusIntensity,
        onUnblockNow: () -> Void,
        onSnooze: (Int) -> Void,
        onRequestUnblock: () -> Void,
        remainingUnblockTime: () -> TimeInterval?,
        onHide: () -> Void
    )
}

struct AppShieldView: View {
    let appName: String
    let mode: AppShieldMode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(appName) is blocked")
                .font(.headline)
            Text("Focus session is active.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if case .focus(_, let onUnblockNow, let onSnooze, let onRequestUnblock, _, let onHide) = mode {
                HStack {
                    Button("Unblock", action: onUnblockNow)
                    Button("Snooze 5m") { onSnooze(5) }
                    Button("Request") { onRequestUnblock() }
                    Button("Hide", action: onHide)
                }
                .buttonStyle(.sapphireInteractive())
            }
        }
        .padding()
    }
}
