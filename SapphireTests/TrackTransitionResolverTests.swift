//
//  TrackTransitionResolverTests.swift
//  Sapphire
//

import Foundation
import Testing
@testable import Sapphire

struct TrackTransitionResolverTests {
    @Test func pendingForwardWinsOverExpectedNext() {
        let result = TrackTransitionResolver.resolve(
            pending: .forward,
            incomingURI: "spotify:track:b",
            expectedNextURI: "spotify:track:other"
        )
        #expect(result == .forward)
    }

    @Test func pendingBackwardWins() {
        let result = TrackTransitionResolver.resolve(
            pending: .backward,
            incomingURI: "spotify:track:a",
            expectedNextURI: "spotify:track:b"
        )
        #expect(result == .backward)
    }

    @Test func matchingExpectedNextInfersForward() {
        let result = TrackTransitionResolver.resolve(
            pending: nil,
            incomingURI: "spotify:track:next",
            expectedNextURI: "spotify:track:next"
        )
        #expect(result == .forward)
    }

    @Test func unknownChangeIsNeutral() {
        let result = TrackTransitionResolver.resolve(
            pending: nil,
            incomingURI: "spotify:track:jump",
            expectedNextURI: "spotify:track:next"
        )
        #expect(result == .neutral)
    }

    @Test func emptyIncomingIsNeutral() {
        let result = TrackTransitionResolver.resolve(
            pending: nil,
            incomingURI: nil,
            expectedNextURI: "spotify:track:next"
        )
        #expect(result == .neutral)
    }
}
