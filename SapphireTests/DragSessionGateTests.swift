//
//  DragSessionGateTests.swift
//  Sapphire
//

import Foundation
import Testing
@testable import Sapphire

struct DragSessionGateTests {
    @Test func leftoverFileURLIsNotAnActiveDrag() {
        #expect(DragSessionGate.hasActiveDragSession(
            pasteboardChangeCountAtMouseDown: 19,
            pasteboardChangeCount: 19,
            pasteboardContainsFileURL: true,
            isWindowDragging: false,
            leftMouseIsDown: true
        ) == false)
    }

    @Test func fileURLWrittenAfterMouseDownIsAnActiveDrag() {
        #expect(DragSessionGate.hasActiveDragSession(
            pasteboardChangeCountAtMouseDown: 19,
            pasteboardChangeCount: 20,
            pasteboardContainsFileURL: true,
            isWindowDragging: false,
            leftMouseIsDown: true
        ) == true)
    }

    @Test func windowMoveWhileMouseIsDownIsAnActiveDrag() {
        #expect(DragSessionGate.hasActiveDragSession(
            pasteboardChangeCountAtMouseDown: 19,
            pasteboardChangeCount: 19,
            pasteboardContainsFileURL: true,
            isWindowDragging: true,
            leftMouseIsDown: true
        ) == true)
    }

    @Test func releasedMouseIsNotAnActiveDrag() {
        #expect(DragSessionGate.hasActiveDragSession(
            pasteboardChangeCountAtMouseDown: 19,
            pasteboardChangeCount: 20,
            pasteboardContainsFileURL: true,
            isWindowDragging: true,
            leftMouseIsDown: false
        ) == false)
    }
}
