//
//  NotchCursorCoordinator.swift
//  Sapphire
//

import AppKit

@MainActor
final class NotchCursorCoordinator {
    private struct Region {
        weak var view: InteractiveCursorAnchorView?
        let cursor: InteractiveCursor
    }

    private var regions: [Region] = []
    private var activeCursor: InteractiveCursor?

    func setRegion(view: InteractiveCursorAnchorView, cursor: InteractiveCursor) {
        regions.removeAll { $0.view === view || $0.view == nil }
        regions.append(Region(view: view, cursor: cursor))
    }

    func removeRegion(view: InteractiveCursorAnchorView) {
        regions.removeAll { $0.view === view || $0.view == nil }
        syncCursor()
    }

    func syncCursor() {
        guard let window = regions.compactMap({ $0.view?.window }).first else {
            clearActiveCursor()
            return
        }

        let mouse = window.mouseLocationOutsideOfEventStream
        var hitCursor: InteractiveCursor?

        for region in regions.reversed() {
            guard let view = region.view else { continue }
            let local = view.convert(mouse, from: nil)
            guard view.bounds.contains(local) else { continue }
            hitCursor = region.cursor
            break
        }

        apply(hitCursor)
    }

    private func apply(_ cursor: InteractiveCursor?) {
        if let cursor {
            guard activeCursor != cursor else { return }
            activeCursor = cursor
            cursor.nsCursor.set()
        } else {
            clearActiveCursor()
        }
    }

    private func clearActiveCursor() {
        guard activeCursor != nil else { return }
        activeCursor = nil
        NSCursor.arrow.set()
    }
}
