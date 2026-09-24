import SwiftUI

/// In-notch auto-off controls shared by Keep Active and Caffeinate detail screens.
struct AutoOffSettingsSection: View {
    let title: String
    @Binding var mode: AutoOffMode
    @Binding var minutes: Double
    @Binding var turnOffAt: Date

    @FocusState private var minutesFieldFocused: Bool
    @State private var minutesText = ""

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

            switch mode {
            case .off:
                EmptyView()
            case .duration:
                HStack(spacing: 8) {
                    Slider(value: $minutes, in: 5...480, step: 5)
                        .interactiveCursor(.clickable)
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
                        .onSubmit {
                            commitMinutesText()
                            minutesFieldFocused = false
                        }
                        .onChange(of: minutesFieldFocused) { _, isFocused in
                            if isFocused {
                                minutesText = displayMinutesText(for: minutes)
                            } else {
                                commitMinutesText()
                            }
                        }
                        .onChange(of: minutes) { _, newValue in
                            guard !minutesFieldFocused else { return }
                            minutesText = displayMinutesText(for: newValue)
                        }
                        .onAppear { minutesText = displayMinutesText(for: minutes) }
                        .onDisappear {
                            if minutesFieldFocused { minutesFieldFocused = false }
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
            }

            if let previewEndsAt, mode != .off {
                Text("Turns off at \(previewEndsAt, style: .time)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
}
