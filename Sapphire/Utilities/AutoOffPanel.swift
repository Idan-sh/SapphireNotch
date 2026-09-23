import SwiftUI

struct AutoOffPanel: View {
    let title: String
    @Binding var mode: AutoOffMode
    @Binding var minutes: Double
    @Binding var turnOffAt: Date
    let endsAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))

            Picker("", selection: $mode) {
                ForEach(AutoOffMode.allCases) { m in
                    Text(m.displayName).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch mode {
            case .off:
                EmptyView()
            case .duration:
                HStack(spacing: 8) {
                    Slider(value: $minutes, in: 5...480, step: 5)
                    TextField("", value: $minutes, formatter: Self.minutesFormatter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 52)
                    Text("min").font(.caption).foregroundColor(.secondary)
                }
            case .time:
                DatePicker("", selection: $turnOffAt, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }

            if let endsAt, mode != .off {
                Text("Turns off at \(endsAt, style: .time)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(width: 240)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.85))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.12)))
        )
        .shadow(radius: 12, y: 6)
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
