//
//  WaveformTransientIconTests.swift
//  Sapphire
//

import Foundation
import Testing
@testable import Sapphire

struct WaveformTransientIconTests {
    @Test func playPauseTransientsClearOnHoverExit() {
        #expect(WaveformView.TransientIcon.paused.shouldClearOnHoverExit)
        #expect(WaveformView.TransientIcon.played.shouldClearOnHoverExit)
    }

    @Test func skipTransientsPersistOnHoverExit() {
        #expect(!WaveformView.TransientIcon.skippedForward.shouldClearOnHoverExit)
        #expect(!WaveformView.TransientIcon.skippedBackward.shouldClearOnHoverExit)
    }
}
