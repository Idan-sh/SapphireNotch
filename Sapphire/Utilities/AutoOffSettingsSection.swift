import SwiftUI

/// In-notch auto-off controls shared by Keep Active and Caffeinate detail screens.
struct AutoOffSettingsSection: View {
    let title: String
    @Binding var mode: AutoOffMode
    @Binding var minutes: Double
    @Binding var turnOffAt: Date
    let endsAt: Date?

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
                    TextField("", value: $minutes, formatter: Self.minutesFormatter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 52)
                        .interactiveCursor(.text)
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

            if let endsAt, mode != .off {
                Text("Turns off at \(endsAt, style: .time)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let minutesFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimum = 5
        f.maximum = 480
        f.maximumFractionDigits = 0
        return f
    }()
}
