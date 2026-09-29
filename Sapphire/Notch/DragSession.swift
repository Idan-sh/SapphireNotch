//
//  DragSession.swift
//  Sapphire
//

import AppKit

/// The drag pasteboard keeps file URLs after a drag ends. A file URL counts
/// only when the pasteboard change count moved during this gesture.
enum DragSessionGate {
    static func hasActiveDragSession(
        pasteboardChangeCountAtMouseDown: Int,
        pasteboardChangeCount: Int,
        pasteboardContainsFileURL: Bool,
        isWindowDragging: Bool,
        leftMouseIsDown: Bool
    ) -> Bool {
        guard leftMouseIsDown else { return false }
        if isWindowDragging { return true }
        return pasteboardContainsFileURL && pasteboardChangeCount != pasteboardChangeCountAtMouseDown
    }
}

enum DragPasteboard {
    static func fileURLs(from pasteboard: NSPasteboard = NSPasteboard(name: .drag)) -> [URL] {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], !urls.isEmpty {
            return urls
        }

        guard let items = pasteboard.pasteboardItems else { return [] }
        var urls: [URL] = []
        for item in items {
            guard let path = item.string(forType: .fileURL) else { continue }
            let decoded = path.removingPercentEncoding ?? path
            if let url = URL(string: decoded), url.isFileURL {
                urls.append(url)
            } else if decoded.hasPrefix("/") {
                urls.append(URL(fileURLWithPath: decoded))
            }
        }
        return urls
    }

    static func containsFileURL(in pasteboard: NSPasteboard = NSPasteboard(name: .drag)) -> Bool {
        if !fileURLs(from: pasteboard).isEmpty { return true }
        return pasteboard.types?.contains(.fileURL) == true
    }
}

struct DragSessionCallbacks {
    var onMouseDown: () -> Void = {}
    var onMouseDragged: () -> Void = {}
    var onMouseUp: () -> Void = {}
}

/// Owns pointer-drag detection: one pair of mouse monitors, the pasteboard
/// baseline, and whether a real window is moving.
@MainActor
final class DragSession: ObservableObject {
    static let shared = DragSession()

    @Published private(set) var isWindowDragging = false

    private var pasteboardChangeCountAtMouseDown: Int = 0
    private var observesWindowMovement = false
    private var dragStartWindowOrigins: [CGWindowID: CGPoint] = [:]
    private var lastWindowDragCheckTime: TimeInterval = 0
    private let windowDragOriginThreshold: CGFloat = 6

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var clientCount = 0
    private var callbacks: [UUID: DragSessionCallbacks] = [:]

    private init() {
        pasteboardChangeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
    }

    func setWindowDragObservation(_ enabled: Bool) {
        guard enabled != observesWindowMovement else { return }
        observesWindowMovement = enabled
        if enabled {
            retainMonitoring()
        } else {
            endWindowDrag()
            releaseMonitoring()
        }
    }

    @discardableResult
    func addCallbacks(_ callbacks: DragSessionCallbacks) -> UUID {
        let id = UUID()
        self.callbacks[id] = callbacks
        retainMonitoring()
        return id
    }

    func removeCallbacks(_ id: UUID) {
        guard callbacks.removeValue(forKey: id) != nil else { return }
        releaseMonitoring()
    }

    var hasActiveDragSession: Bool {
        let pasteboard = NSPasteboard(name: .drag)
        let changeCount = pasteboard.changeCount
        let containsFileURL = changeCount != pasteboardChangeCountAtMouseDown
            && DragPasteboard.containsFileURL(in: pasteboard)
        return DragSessionGate.hasActiveDragSession(
            pasteboardChangeCountAtMouseDown: pasteboardChangeCountAtMouseDown,
            pasteboardChangeCount: changeCount,
            pasteboardContainsFileURL: containsFileURL,
            isWindowDragging: isWindowDragging,
            leftMouseIsDown: NSEvent.pressedMouseButtons == 1
        )
    }

    private func retainMonitoring() {
        clientCount += 1
        if globalMonitor == nil {
            installMonitors()
        }
    }

    private func releaseMonitoring() {
        clientCount = max(0, clientCount - 1)
        guard clientCount == 0 else { return }
        removeMonitors()
        endWindowDrag()
    }

    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        let handle: (NSEvent) -> Void = { [weak self] event in
            let changeCount: Int? = (event.type == .leftMouseDown || event.type == .leftMouseUp)
                ? NSPasteboard(name: .drag).changeCount
                : nil
            Task { @MainActor in
                self?.handle(event.type, pasteboardChangeCount: changeCount)
            }
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handle)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            handle(event)
            return event
        }
    }

    private func removeMonitors() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func handle(_ type: NSEvent.EventType, pasteboardChangeCount: Int?) {
        switch type {
        case .leftMouseDown:
            noteMouseDown(changeCount: pasteboardChangeCount ?? pasteboardChangeCountAtMouseDown)
        case .leftMouseDragged:
            noteMouseDragged()
        case .leftMouseUp:
            noteMouseUp(changeCount: pasteboardChangeCount ?? NSPasteboard(name: .drag).changeCount)
        default:
            break
        }
    }

    private func noteMouseDown(changeCount: Int) {
        pasteboardChangeCountAtMouseDown = changeCount
        endWindowDrag()
        for callbacks in callbacks.values {
            callbacks.onMouseDown()
        }
    }

    private func noteMouseDragged() {
        updateWindowDrag()
        for callbacks in callbacks.values {
            callbacks.onMouseDragged()
        }
    }

    private func noteMouseUp(changeCount: Int) {
        pasteboardChangeCountAtMouseDown = changeCount
        endWindowDrag()
        for callbacks in callbacks.values {
            callbacks.onMouseUp()
        }
    }

    private func endWindowDrag() {
        dragStartWindowOrigins.removeAll()
        if isWindowDragging {
            isWindowDragging = false
        }
    }

    private func updateWindowDrag() {
        guard observesWindowMovement else { return }
        let now = CACurrentMediaTime()
        if now - lastWindowDragCheckTime < 0.03 { return }
        lastWindowDragCheckTime = now

        guard NSEvent.pressedMouseButtons == 1 else {
            if NSEvent.pressedMouseButtons == 0 {
                endWindowDrag()
            }
            return
        }
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              frontmostApp.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return
        }

        let frames = layerZeroWindowFrames(for: frontmostApp.processIdentifier)
        guard !frames.isEmpty else { return }

        if dragStartWindowOrigins.isEmpty {
            for (windowID, frame) in frames {
                dragStartWindowOrigins[windowID] = frame.origin
            }
            return
        }

        for (windowID, frame) in frames {
            guard let startOrigin = dragStartWindowOrigins[windowID] else {
                dragStartWindowOrigins[windowID] = frame.origin
                continue
            }
            let dx = abs(frame.origin.x - startOrigin.x)
            let dy = abs(frame.origin.y - startOrigin.y)
            if dx >= windowDragOriginThreshold || dy >= windowDragOriginThreshold {
                isWindowDragging = true
                return
            }
        }
    }

    private func layerZeroWindowFrames(for pid: pid_t) -> [CGWindowID: CGRect] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return [:]
        }

        var result: [CGWindowID: CGRect] = [:]
        for info in list {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == pid else { continue }
            if let layer = info[kCGWindowLayer as String] as? Int, layer != 0 { continue }
            guard let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"], let height = bounds["Height"],
                  width >= 200, height >= 120,
                  let x = bounds["X"], let y = bounds["Y"] else {
                continue
            }
            result[windowID] = CGRect(x: x, y: y, width: width, height: height)
        }
        return result
    }
}
