import Foundation
import Testing
@testable import Sapphire

struct KeepActiveIdlePolicyTests {
    @Test func belowThresholdDoesNotInject() {
        #expect(KeepActiveManager.shouldInjectActivity(idleSeconds: 119, threshold: 120) == false)
    }

    @Test func atThresholdInjects() {
        #expect(KeepActiveManager.shouldInjectActivity(idleSeconds: 120, threshold: 120) == true)
    }

    @Test func aboveThresholdInjects() {
        #expect(KeepActiveManager.shouldInjectActivity(idleSeconds: 500, threshold: 120) == true)
    }
}
