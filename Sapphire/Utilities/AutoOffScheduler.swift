import Foundation

enum AutoOffScheduler {
    /// Computes when an auto-off should fire, or nil if it should not.
    /// - `.off`: nil
    /// - `.duration`: now + minutes (nil if minutes <= 0)
    /// - `.time`: next occurrence of turnOffAt's hour/minute (today if future, else tomorrow)
    static func nextFireDate(
        mode: AutoOffMode,
        minutes: Double,
        turnOffAt: Date,
        from now: Date = Date()
    ) -> Date? {
        switch mode {
        case .off:
            return nil
        case .duration:
            return minutes > 0 ? now.addingTimeInterval(minutes * 60) : nil
        case .time:
            let cal = Calendar.current
            let comps = cal.dateComponents([.hour, .minute], from: turnOffAt)
            return cal.nextDate(after: now, matching: comps, matchingPolicy: .nextTime)
        }
    }
}
