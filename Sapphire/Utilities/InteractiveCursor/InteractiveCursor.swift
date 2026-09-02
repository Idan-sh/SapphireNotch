//
//  InteractiveCursor.swift
//  Sapphire
//

import AppKit
import SwiftUI

enum InteractiveCursor: Equatable {
    case clickable
    case draggable
    case resize
    case resizeHorizontal
    case resizeVertical
    case text

    var nsCursor: NSCursor {
        switch self {
        case .clickable: .pointingHand
        case .draggable: .openHand
        case .resize: .crosshair
        case .resizeHorizontal: .resizeLeftRight
        case .resizeVertical: .resizeUpDown
        case .text: .iBeam
        }
    }
}

enum InteractiveCursorBackend: Equatable {
    case standard
    case notch
}

private struct InteractiveCursorBackendKey: EnvironmentKey {
    static let defaultValue: InteractiveCursorBackend = .standard
}

private struct NotchCursorCoordinatorKey: EnvironmentKey {
    static let defaultValue: NotchCursorCoordinator? = nil
}

extension EnvironmentValues {
    var interactiveCursorBackend: InteractiveCursorBackend {
        get { self[InteractiveCursorBackendKey.self] }
        set { self[InteractiveCursorBackendKey.self] = newValue }
    }

    var notchCursorCoordinator: NotchCursorCoordinator? {
        get { self[NotchCursorCoordinatorKey.self] }
        set { self[NotchCursorCoordinatorKey.self] = newValue }
    }
}

extension View {
    func interactiveCursor(_ cursor: InteractiveCursor = .clickable) -> some View {
        modifier(InteractiveCursorModifier(cursor: cursor))
    }

    func interactiveCursorRoot(coordinator: NotchCursorCoordinator) -> some View {
        environment(\.interactiveCursorBackend, .notch)
            .environment(\.notchCursorCoordinator, coordinator)
    }

    /// Applies the standard pointing-hand cursor for tappable non-`Button` views.
    func clickable(onTap action: @escaping () -> Void) -> some View {
        interactiveCursor(.clickable)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }

    /// Applies the standard pointing-hand cursor for tappable non-`Button` views (counted tap).
    func clickable(count: Int, onTap action: @escaping () -> Void) -> some View {
        interactiveCursor(.clickable)
            .contentShape(Rectangle())
            .onTapGesture(count: count, perform: action)
    }
}

private struct InteractiveCursorModifier: ViewModifier {
    @Environment(\.interactiveCursorBackend) private var backend
    @Environment(\.notchCursorCoordinator) private var coordinator
    let cursor: InteractiveCursor

    func body(content: Content) -> some View {
        switch backend {
        case .notch:
            content.overlay {
                if let coordinator {
                    InteractiveCursorAnchorRepresentable(cursor: cursor, coordinator: coordinator)
                        .allowsHitTesting(false)
                }
            }
        case .standard:
            content.modifier(StandardInteractiveCursorModifier(cursor: cursor))
        }
    }
}

private struct StandardInteractiveCursorModifier: ViewModifier {
    let cursor: InteractiveCursor
    @State private var isInside = false

    func body(content: Content) -> some View {
        content.onHover { hovering in
            if hovering {
                guard !isInside else { return }
                isInside = true
                cursor.nsCursor.set()
            } else if isInside {
                isInside = false
                NSCursor.arrow.set()
            }
        }
    }
}

struct SapphireInteractiveButtonStyle: ButtonStyle {
    var cursor: InteractiveCursor

    init(_ cursor: InteractiveCursor = .clickable) {
        self.cursor = cursor
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .interactiveCursor(cursor)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == SapphireInteractiveButtonStyle {
    static func sapphireInteractive(_ cursor: InteractiveCursor = .clickable) -> SapphireInteractiveButtonStyle {
        SapphireInteractiveButtonStyle(cursor)
    }
}

private struct InteractiveCursorAnchorRepresentable: NSViewRepresentable {
    var cursor: InteractiveCursor
    var coordinator: NotchCursorCoordinator

    func makeNSView(context: Context) -> InteractiveCursorAnchorView {
        let view = InteractiveCursorAnchorView()
        view.cursor = cursor
        view.coordinator = coordinator
        return view
    }

    func updateNSView(_ nsView: InteractiveCursorAnchorView, context: Context) {
        nsView.cursor = cursor
        nsView.coordinator = coordinator
        nsView.registerWithCoordinator()
    }

    static func dismantleNSView(_ nsView: InteractiveCursorAnchorView, coordinator: ()) {
        nsView.unregisterFromCoordinator()
    }
}

final class InteractiveCursorAnchorView: NSView {
    var cursor: InteractiveCursor = .clickable
    weak var coordinator: NotchCursorCoordinator?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerWithCoordinator()
    }

    override func layout() {
        super.layout()
        registerWithCoordinator()
    }

    func registerWithCoordinator() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        coordinator?.setRegion(view: self, cursor: cursor)
    }

    func unregisterFromCoordinator() {
        coordinator?.removeRegion(view: self)
    }

    deinit {
        unregisterFromCoordinator()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
