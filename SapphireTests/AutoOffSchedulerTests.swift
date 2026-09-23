import Foundation
import Testing
@testable import Sapphire

struct AutoOffSchedulerTests {
    private func date(y: Int, m: Int, d: Int, h: Int, min: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = h; c.minute = min
        return Calendar.current.date(from: c)!
    }

    @Test func offModeReturnsNil() {
        let now = date(y: 2026, m: 9, d: 23, h: 10, min: 0)
        #expect(AutoOffScheduler.nextFireDate(mode: .off, minutes: 60, turnOffAt: now, from: now) == nil)
    }

    @Test func durationAddsMinutes() {
        let now = date(y: 2026, m: 9, d: 23, h: 10, min: 0)
        let fire = AutoOffScheduler.nextFireDate(mode: .duration, minutes: 90, turnOffAt: now, from: now)
        #expect(fire == now.addingTimeInterval(90 * 60))
    }

    @Test func durationZeroReturnsNil() {
        let now = date(y: 2026, m: 9, d: 23, h: 10, min: 0)
        #expect(AutoOffScheduler.nextFireDate(mode: .duration, minutes: 0, turnOffAt: now, from: now) == nil)
    }

    @Test func timeTodayWhenFuture() {
        let now = date(y: 2026, m: 9, d: 23, h: 10, min: 0)
        let target = date(y: 2000, m: 1, d: 1, h: 18, min: 0) // only hour/minute used
        let fire = AutoOffScheduler.nextFireDate(mode: .time, minutes: 0, turnOffAt: target, from: now)
        #expect(fire == date(y: 2026, m: 9, d: 23, h: 18, min: 0))
    }

    @Test func timeTomorrowWhenPast() {
        let now = date(y: 2026, m: 9, d: 23, h: 19, min: 0)
        let target = date(y: 2000, m: 1, d: 1, h: 18, min: 0)
        let fire = AutoOffScheduler.nextFireDate(mode: .time, minutes: 0, turnOffAt: target, from: now)
        #expect(fire == date(y: 2026, m: 9, d: 24, h: 18, min: 0))
    }
}
