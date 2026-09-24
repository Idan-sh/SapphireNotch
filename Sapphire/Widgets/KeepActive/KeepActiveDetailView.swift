import SwiftUI

@MainActor
struct KeepActiveDetailView: View {
    @EnvironmentObject private var settings: SettingsModel
    @ObservedObject private var manager = KeepActiveManager.shared
    @ObservedObject private var permissions = PermissionsManager.shared

    private var isAccessibilityTrusted: Bool {
        permissions.accessibilityStatus == .granted || AccessibilityTrustMonitor.shared.isTrusted
    }

    private var isOnBinding: Binding<Bool> {
        Binding(
            get: { manager.isActive },
            set: { newValue in
                if newValue {
                    manager.start()
                } else {
                    manager.stop()
                }
            }
        )
    }

    private var statusText: String {
        manager.isActive ? "On" : "Off"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Toggle(isOn: isOnBinding) {
                Text("Keep Active")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            .toggleStyle(.switch)
            .tint(.accentColor)
            .interactiveCursor(.clickable)

            Text(statusText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.55))

            if !isAccessibilityTrusted {
                accessibilityPrompt
            }

            AutoOffSettingsSection(
                title: "Auto-off",
                mode: $settings.settings.keepActiveAutoOffMode,
                minutes: $settings.settings.keepActiveTimeoutMinutes,
                turnOffAt: $settings.settings.keepActiveAutoOffTime,
                endsAt: manager.timeoutEndsAt
            )
            .disabled(!manager.isActive)
            .opacity(manager.isActive ? 1 : 0.45)

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 520, height: 300, alignment: .topLeading)
        .foregroundColor(.white)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: manager.isActive ? "person.wave.2.fill" : "person.wave.2")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
            Text("Keep Active")
                .font(.system(size: 16, weight: .bold, design: .rounded))
            Spacer()
        }
    }

    private var accessibilityPrompt: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility Required")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Text("Needed to keep presence apps from going idle.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.55))
            }
            Spacer()
            Button("Grant") {
                PermissionsManager.shared.requestPermission(.accessibility)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.orange)
            .interactiveCursor(.clickable)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }
}
