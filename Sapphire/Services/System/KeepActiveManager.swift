import AppKit
import Combine
import CoreGraphics
import Foundation
import os.log

@MainActor
final class KeepActiveManager: ObservableObject {
    static let shared = KeepActiveManager()

    private let settings = SettingsModel.shared

    @Published private(set) var isActive = false
    @Published private(set) var timeoutEndsAt: Date?

    private let tickInterval: TimeInterval = 60
    private let idleThreshold: TimeInterval = 120

    private var tickTimer: Timer?
    private var timeoutTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Stop if Accessibility is revoked at runtime.
        NotificationCenter.default.publisher(for: AccessibilityTrustMonitor.trustDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] note in
                let trusted = (note.userInfo?["trusted"] as? Bool) ?? AccessibilityTrustMonitor.shared.isTrusted
                if !trusted { self?.stop() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Pure policy (testable)

    nonisolated static func shouldInjectActivity(idleSeconds: TimeInterval, threshold: TimeInterval) -> Bool {
        idleSeconds >= threshold
    }

    // MARK: - Public control

    func toggle() { isActive ? stop() : start() }

    func start() {
        guard !isActive else { scheduleAutoOff(); return }

        guard AccessibilityTrustMonitor.shared.isTrusted else {
            PermissionsManager.shared.requestPermission(.accessibility)
            return // stay off until granted; user re-toggles
        }

        isActive = true
        startTickTimer()
        tick() // evaluate immediately
        scheduleAutoOff()
    }

    func stop() {
        isActive = false
        stopTickTimer()
        cancelAutoOff()
    }

    // MARK: - Tick loop

    private func startTickTimer() {
        guard tickTimer == nil else { return }
        tickTimer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func stopTickTimer() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    private func tick() {
        guard isActive else { return }
        let idle = currentIdleSeconds()
        if Self.shouldInjectActivity(idleSeconds: idle, threshold: idleThreshold) {
            postNoOpKey()
        }
    }

    private func currentIdleSeconds() -> TimeInterval {
        let anyInput = CGEventType(rawValue: ~UInt32(0))! // kCGAnyInputEventType
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    private func postNoOpKey() {
        guard let src = CGEventSource(stateID: .hidSystemState) else { return }
        let f15: CGKeyCode = 0x71
        CGEvent(keyboardEventSource: src, virtualKey: f15, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: src, virtualKey: f15, keyDown: false)?.post(tap: .cghidEventTap)
    }

    // MARK: - Auto-off (implemented in Task 4)

    private func scheduleAutoOff() { /* Task 4 */ }
    private func cancelAutoOff() {
        timeoutTask?.cancel()
        timeoutTask = nil
        timeoutEndsAt = nil
    }
}
