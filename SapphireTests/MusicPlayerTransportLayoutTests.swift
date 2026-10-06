//
//  MusicPlayerTransportLayoutTests.swift
//  SapphireTests
//

import Testing
@testable import Sapphire

struct MusicPlayerTransportLayoutTests {
    @Test func lyricsDoNotMoveTransportControls() {
        for hasAccessoryButtons in [false, true] {
            let topWithLyrics = MusicPlayerTransportLayout.controlTopPadding(
                hasAccessoryButtons: hasAccessoryButtons,
                hasDisplayableLyrics: true
            )
            let topWithoutLyrics = MusicPlayerTransportLayout.controlTopPadding(
                hasAccessoryButtons: hasAccessoryButtons,
                hasDisplayableLyrics: false
            )
            #expect(topWithLyrics == topWithoutLyrics)

            let bottomWithLyrics = MusicPlayerTransportLayout.controlBottomPadding(hasDisplayableLyrics: true)
            let bottomWithoutLyrics = MusicPlayerTransportLayout.controlBottomPadding(hasDisplayableLyrics: false)
            #expect(bottomWithLyrics == bottomWithoutLyrics)

            let slotWithLyrics = MusicPlayerTransportLayout.reservedLyricSlotHeight(hasDisplayableLyrics: true)
            let slotWithoutLyrics = MusicPlayerTransportLayout.reservedLyricSlotHeight(hasDisplayableLyrics: false)
            #expect(slotWithLyrics == slotWithoutLyrics)
        }
    }

    @Test func accessoryRowInsetStaysIndependentOfLyrics() {
        #expect(
            MusicPlayerTransportLayout.controlTopPadding(
                hasAccessoryButtons: false,
                hasDisplayableLyrics: true
            ) == 8
        )
        #expect(
            MusicPlayerTransportLayout.controlTopPadding(
                hasAccessoryButtons: true,
                hasDisplayableLyrics: true
            ) == 0
        )
        #expect(MusicPlayerTransportLayout.controlBottomPadding(hasDisplayableLyrics: true) == 4)
        #expect(MusicPlayerTransportLayout.reservedLyricSlotHeight(hasDisplayableLyrics: false) == 35)
    }
}
