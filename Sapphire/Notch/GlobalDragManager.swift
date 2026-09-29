//
//  GlobalDragManager.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-12.
//

import AppKit
import Combine
import QuartzCore

@MainActor
class GlobalDragManager: ObservableObject {
    static let shared = GlobalDragManager()

    @Published private(set) var isDraggingInActivationZone: Bool = false

    private var dragEventsToken: UUID?
    private var activationTimer: Timer?
    private var isInsideActivationRect: Bool = false
    private let dragState = DragStateManager.shared

    private var lastDragProcessTime: TimeInterval = 0
    private let dragThrottleInterval: TimeInterval = 0.05

    private init() {}

    func startMonitoring() {
        guard dragEventsToken == nil else { return }

        dragEventsToken = DragSession.shared.addCallbacks(DragSessionCallbacks(
            onMouseDown: { [weak self] in
                guard let self, self.isDraggingInActivationZone else { return }
                self.endDrag()
            },
            onMouseDragged: { [weak self] in
                self?.handleDrag()
            },
            onMouseUp: { [weak self] in
                self?.endDrag()
            }
        ))
    }

    func stopMonitoring() {
        if let dragEventsToken {
            DragSession.shared.removeCallbacks(dragEventsToken)
            self.dragEventsToken = nil
        }

        activationTimer?.invalidate()
        activationTimer = nil
        isInsideActivationRect = false
    }

    func endDrag() {
        if isDraggingInActivationZone {
            isDraggingInActivationZone = false
        }

        dragState.isDraggingFromShelf = false
        activationTimer?.invalidate()
        activationTimer = nil
        isInsideActivationRect = false
    }

    private func handleDrag() {
        let now = CACurrentMediaTime()
        if now - lastDragProcessTime < dragThrottleInterval {
            return
        }
        lastDragProcessTime = now

        Task { @MainActor in
            self.processDrag()
        }
    }

    private func processDrag() {
        guard !dragState.isDraggingFromShelf else { return }
        guard !isDraggingInActivationZone else { return }

        let mouseLocation = NSEvent.mouseLocation
        let zoneWidth: CGFloat = 290
        let zoneHeight: CGFloat = 43

        guard let screenWithCursor = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) else {
            isInsideActivationRect = false
            activationTimer?.invalidate()
            activationTimer = nil
            return
        }

        let notchWindowOnScreen = CursorPosition.visibleNotchWindows.first { window in
            window.screen?.displayID == screenWithCursor.displayID
        }
        let activationRect: CGRect
        if let notchWindow = notchWindowOnScreen {
            let frame = notchWindow.frame
            let width = min(frame.width + 40, frame.width + 120)
            let height = min(56, frame.height * 0.35) + 12
            activationRect = CGRect(
                x: frame.midX - width / 2,
                y: frame.maxY - height,
                width: width,
                height: height
            )
        } else {
            let visibleMaxY = screenWithCursor.visibleFrame.maxY
            activationRect = CGRect(
                x: screenWithCursor.visibleFrame.midX - (zoneWidth / 2),
                y: visibleMaxY - zoneHeight,
                width: zoneWidth,
                height: zoneHeight
            )
        }

        guard activationRect.contains(mouseLocation) else {
            isInsideActivationRect = false
            activationTimer?.invalidate()
            activationTimer = nil
            return
        }

        // Ignore in-app gestures near the notch (tab reorder, text selection, etc.).
        guard DragSession.shared.hasActiveDragSession else {
            if isInsideActivationRect {
                isInsideActivationRect = false
                activationTimer?.invalidate()
                activationTimer = nil
            }
            return
        }

        guard !isInsideActivationRect else { return }

        isInsideActivationRect = true
        activationTimer?.invalidate()
        let delay = max(0.05, SettingsModel.shared.settings.snapActivationDelay)
        activationTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard DragSession.shared.hasActiveDragSession,
                      activationRect.contains(NSEvent.mouseLocation),
                      !self.isDraggingInActivationZone else { return }

                self.isDraggingInActivationZone = true
            }
        }
    }

}