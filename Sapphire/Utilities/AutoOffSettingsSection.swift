import AppKit
import SwiftUI

/// In-notch auto-off controls shared by Keep Active and Caffeinate detail screens.
struct AutoOffSettingsSection: View {
    let title: String
    @Binding var mode: AutoOffMode
    @Binding var minutes: Double
    @Binding var turnOffAt: Date

    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var minutesFieldFocused: Bool
    @State private var minutesText = ""
    @State private var clickOutsideMonitor: Any?
    /// When the slider (or binding) changes minutes, blur without re-committing typed text.
    @State private var skipCommitOnBlur = false

    private var previewEndsAt: Date? {
        AutoOffScheduler.nextFireDate(mode: mode, minutes: minutes, turnOffAt: turnOffAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.85))

            Picker("", selection: $mode) {
                ForEach(AutoOffMode.allCases) { m in
                    Text(m.displayName).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .interactiveCursor(.clickable)
            .onChange(of: mode) { _, _ in
                resignMinutesField()
            }

            switch mode {
            case .off:
                EmptyView()
            case .duration:
                HStack(spacing: 8) {
                    Slider(value: $minutes, in: 5...480, step: 5)
                        .interactiveCursor(.clickable)
                        .onChange(of: minutes) { oldValue, newValue in
                            // Keep the field in sync even while focused; otherwise resign
                            // would commit the stale typed value and overwrite the slider.
                            minutesText = displayMinutesText(for: newValue)
                            if minutesFieldFocused {
                                skipCommitOnBlur = true
                                resignMinutesField()
                            }
                            guard isEnabled,
                                  Int(oldValue.rounded()) != Int(newValue.rounded()),
                                  SettingsModel.shared.settings.hapticFeedbackEnabled
                            else { return }
                            // Native Force Touch tick for discrete slider steps.
                            NSHapticFeedbackManager.defaultPerformer.perform(
                                .alignment,
                                performanceTime: .now
                            )
                        }
                    TextField("", text: $minutesText)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 52)
                        .focused($minutesFieldFocused)
                        .interactiveCursor(.text)
                        // TextField + NumberFormatter only validates on commit; limit live input here.
                        .onChange(of: minutesText) { _, newValue in
                            let limited = String(newValue.filter(\.isNumber).prefix(3))
                            if minutesText != limited { minutesText = limited }
                        }
                        .onSubmit { resignMinutesField() }
                        .onChange(of: minutesFieldFocused) { _, isFocused in
                            if isFocused {
                                minutesText = displayMinutesText(for: minutes)
                                installClickOutsideMonitor()
                            } else {
                                if skipCommitOnBlur {
                                    skipCommitOnBlur = false
                                } else {
                                    commitMinutesText()
                                }
                                removeClickOutsideMonitor()
                            }
                        }
                        .onAppear { minutesText = displayMinutesText(for: minutes) }
                        .onDisappear {
                            resignMinutesField()
                        }
                    Text("min")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.55))
                }
            case .time:
                DatePicker("", selection: $turnOffAt, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .colorScheme(.dark)
                    .interactiveCursor(.clickable)
                    .onChange(of: turnOffAt) { _, _ in
                        resignMinutesField()
                    }
            }

            if let previewEndsAt, mode != .off {
                Text("Turns off at \(previewEndsAt, style: .time)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onDisappear { removeClickOutsideMonitor() }
    }

    private func displayMinutesText(for value: Double) -> String {
        String(Int(value.rounded()))
    }

    private func commitMinutesText() {
        let parsed = Double(minutesText) ?? minutes
        let stepped = (parsed / 5).rounded() * 5
        let safe = stepped.isNaN || stepped.isInfinite ? 60 : stepped
        minutes = min(480, max(5, safe))
        minutesText = displayMinutesText(for: minutes)
    }

    private func resignMinutesField() {
        guard minutesFieldFocused else {
            removeClickOutsideMonitor()
            return
        }
        minutesFieldFocused = false
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()
        clickOutsideMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            if !Self.eventHitsTextInput(event) {
                DispatchQueue.main.async {
                    minutesFieldFocused = false
                    event.window?.makeFirstResponder(nil)
                }
            }
            return event
        }
    }

    private func removeClickOutsideMonitor() {
        if let clickOutsideMonitor {
            NSEvent.removeMonitor(clickOutsideMonitor)
            self.clickOutsideMonitor = nil
        }
    }

    private static func eventHitsTextInput(_ event: NSEvent) -> Bool {
        guard let contentView = event.window?.contentView else { return false }
        var view: NSView? = contentView.hitTest(event.locationInWindow)
        while let current = view {
            if current is NSTextField || current is NSTextView { return true }
            view = current.superview
        }
        return false
    }
}
