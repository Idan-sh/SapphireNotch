import AppKit
import SwiftUI

@MainActor
struct CaffeinateDetailView: View {
    @EnvironmentObject private var settings: SettingsModel
    @ObservedObject private var manager = CaffeineManager.shared
    @ObservedObject private var lidAngleSensor = LidAngleSensor.shared

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

    private var currentAngleText: String {
        guard lidAngleSensor.isAvailable else { return "Unavailable" }
        return "\(Int(lidAngleSensor.angle.rounded()))°"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                Toggle(isOn: isOnBinding) {
                    Text("Caffeinate")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
                .toggleStyle(.switch)
                .tint(.accentColor)
                .interactiveCursor(.clickable)

                Text(statusText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))

                VStack(alignment: .leading, spacing: 12) {
                    AutoOffSettingsSection(
                        title: "Auto-off",
                        mode: $settings.settings.caffeinateAutoOffMode,
                        minutes: $settings.settings.caffeinateTimeoutMinutes,
                        turnOffAt: $settings.settings.caffeinateAutoOffTime,
                        endsAt: manager.timeoutEndsAt
                    )

                    Divider().overlay(Color.white.opacity(0.12))

                    settingsToggle(
                        title: "Prevent sleep in clamshell",
                        isOn: $settings.settings.sleepInClamshell
                    )
                    settingsToggle(
                        title: "Keep enabled after clamshell",
                        isOn: $settings.settings.persistentCaffeinateAfterClamshell
                    )

                    Divider().overlay(Color.white.opacity(0.12))

                    lidAngleSection
                }
                .disabled(!manager.isActive)
                .opacity(manager.isActive ? 1 : 0.45)
                .id(manager.isActive)
            }
            .padding(16)
        }
        .frame(width: 560, height: 360, alignment: .topLeading)
        .foregroundColor(.white)
        .preferredColorScheme(.dark)
        .onAppear { (NSApp.delegate as? AppDelegate)?.makeNotchWindowFocusable() }
        .onDisappear { (NSApp.delegate as? AppDelegate)?.revertNotchWindowFocus() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: manager.isActive ? "cup.and.heat.waves.fill" : "cup.and.heat.waves")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
            Text("Caffeinate")
                .font(.system(size: 16, weight: .bold, design: .rounded))
            Spacer()
        }
    }

    private var lidAngleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lid angle")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.85))

            HStack {
                Text("Current angle")
                    .font(.system(size: 12, design: .rounded))
                Spacer()
                Text(currentAngleText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(lidAngleSensor.isAvailable ? .white : .white.opacity(0.45))
            }

            settingsToggle(
                title: "Black out display using lid angle",
                isOn: $settings.settings.caffeinateTurnOffScreenUsingLidAngle
            )
            if settings.settings.caffeinateTurnOffScreenUsingLidAngle {
                angleSlider(
                    label: "Trigger angle",
                    value: $settings.settings.caffeinateLidAngleTrigger
                )
            }

            settingsToggle(
                title: "Pause media when nearly closed",
                isOn: $settings.settings.lidAnglePauseMediaEnabled
            )
            if settings.settings.lidAnglePauseMediaEnabled {
                angleSlider(
                    label: "Pause media trigger",
                    value: $settings.settings.lidAnglePauseMediaTrigger
                )
            }

            settingsToggle(
                title: "Mute system audio when nearly closed",
                isOn: $settings.settings.lidAngleMuteAudioEnabled
            )
            if settings.settings.lidAngleMuteAudioEnabled {
                angleSlider(
                    label: "Mute audio trigger",
                    value: $settings.settings.lidAngleMuteAudioTrigger
                )
            }
        }
    }

    private func settingsToggle(title: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
        }
        .toggleStyle(.switch)
        .tint(.accentColor)
        .interactiveCursor(.clickable)
    }

    private func angleSlider(label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.55))
                Spacer()
                Text("\(Int(value.wrappedValue.rounded()))°")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.white.opacity(0.7))
            }
            Slider(value: value, in: 0...140, step: 1)
                .interactiveCursor(.clickable)
        }
    }
}
