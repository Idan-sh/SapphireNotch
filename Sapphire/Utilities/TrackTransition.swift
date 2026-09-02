//
//  TrackTransition.swift
//  Sapphire
//

import SwiftUI

enum TrackTransitionDirection: Equatable, Sendable {
    case forward
    case backward
    case neutral
}

enum TrackTransitionResolver {
    static func resolve(
        pending: TrackTransitionDirection?,
        incomingURI: String?,
        expectedNextURI: String?
    ) -> TrackTransitionDirection {
        if let pending {
            return pending
        }

        let incoming = normalizeURI(incomingURI)
        let expected = normalizeURI(expectedNextURI)
        guard !incoming.isEmpty, !expected.isEmpty, incoming == expected else {
            return .neutral
        }
        return .forward
    }

    static func normalizeURI(_ uri: String?) -> String {
        var value = uri?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if value.hasPrefix("cid:") {
            value = String(value.dropFirst(4))
        } else if value.hasPrefix("uid:") {
            value = String(value.dropFirst(4))
        }
        return value
    }
}

enum TrackTransitionMotion {
    static let duration: TimeInterval = 0.28
    static var animation: Animation { .easeInOut(duration: duration) }
}

struct TrackTransitionEvent: Equatable {
    var token: String = ""
    var direction: TrackTransitionDirection = .neutral
}

private struct TrackTransitionWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ArtworkCrossfade<Content: View>: View {
    let token: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            content()
                .id(token)
                .transition(.opacity)
        }
        .animation(TrackTransitionMotion.animation, value: token)
    }
}

/// Push-style metadata slide: old and new sit in adjacent panes and move together
/// inside a clipped window (no stacked overlap).
struct TrackMetadataTransition<Content: View>: View {
    @EnvironmentObject private var musicManager: MusicManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Unused — kept for call-site compatibility.
    var identity: String = ""
    var alignment: Alignment = .leading
    @ViewBuilder var content: () -> Content

    @State private var width: CGFloat = 0
    @State private var settledSnapshot: AnyView?
    @State private var outgoingSnapshot: AnyView?
    @State private var lastToken: String = ""
    @State private var slideDirection: TrackTransitionDirection = .neutral
    /// 0 = showing outgoing pane, 1 = showing incoming pane.
    @State private var progress: CGFloat = 1
    @State private var clearTask: Task<Void, Never>?
    @State private var pendingPush: (token: String, direction: TrackTransitionDirection)?

    var body: some View {
        let event = musicManager.trackTransitionEvent

        ZStack(alignment: alignment) {
            // Layout anchor (keeps height/width without drawing).
            content()
                .opacity(0)
                .accessibilityHidden(true)

            slideLayers
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: TrackTransitionWidthKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(TrackTransitionWidthKey.self) { newWidth in
            let clamped = max(0, newWidth)
            guard abs(clamped - width) > 0.5 else { return }
            width = clamped
            if let pending = pendingPush, clamped > 1 {
                pendingPush = nil
                runPush(token: pending.token, direction: pending.direction)
            }
        }
        .clipped()
        .onAppear {
            lastToken = event.token
            settledSnapshot = AnyView(pane(erasedContent()))
            progress = 1
            outgoingSnapshot = nil
        }
        .onChange(of: event.token) { _, newToken in
            guard newToken != lastToken else { return }
            requestPush(token: newToken, direction: event.direction)
        }
    }

    @ViewBuilder
    private var slideLayers: some View {
        let w = max(width, 1)

        if let outgoingSnapshot, slideDirection != .neutral {
            // Adjacent panes in an HStack — never stacked on top of each other.
            HStack(spacing: 0) {
                if slideDirection == .forward {
                    outgoingSnapshot
                        .frame(width: w, alignment: alignment)
                    content()
                        .frame(width: w, alignment: alignment)
                } else {
                    content()
                        .frame(width: w, alignment: alignment)
                    outgoingSnapshot
                        .frame(width: w, alignment: alignment)
                }
            }
            .offset(x: stripOffset(width: w))
            .frame(width: w, alignment: .leading)
            .clipped()
            .allowsHitTesting(progress >= 0.999)
        } else {
            content()
                .frame(maxWidth: .infinity, alignment: alignment)
        }
    }

    private func stripOffset(width w: CGFloat) -> CGFloat {
        switch slideDirection {
        case .forward:
            // [old][new] → slide left from 0 to -w
            return -w * progress
        case .backward:
            // [new][old] → slide right from -w to 0
            return -w * (1 - progress)
        case .neutral:
            return 0
        }
    }

    private func pane<V: View>(_ view: V) -> some View {
        view.frame(maxWidth: .infinity, alignment: alignment)
    }

    private func erasedContent() -> some View {
        content()
    }

    private func requestPush(token: String, direction: TrackTransitionDirection) {
        lastToken = token
        let resolved = reduceMotion ? TrackTransitionDirection.neutral : direction

        if resolved == .neutral {
            pendingPush = nil
            clearTask?.cancel()
            outgoingSnapshot = nil
            progress = 1
            settledSnapshot = AnyView(pane(erasedContent()))
            return
        }

        if width <= 1 {
            // Wait until we know the window width so panes don't overlap.
            pendingPush = (token, resolved)
            settledSnapshot = AnyView(pane(erasedContent()))
            return
        }

        runPush(token: token, direction: resolved)
    }

    private func runPush(token: String, direction: TrackTransitionDirection) {
        clearTask?.cancel()
        pendingPush = nil

        let previous = settledSnapshot ?? AnyView(pane(erasedContent()))
        settledSnapshot = AnyView(pane(erasedContent()))
        slideDirection = direction
        outgoingSnapshot = previous

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            progress = 0
        }

        clearTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, lastToken == token else { return }
            withAnimation(TrackTransitionMotion.animation) {
                progress = 1
            }
            let ns = UInt64(TrackTransitionMotion.duration * 1_250_000_000)
            try? await Task.sleep(nanoseconds: ns)
            guard !Task.isCancelled, lastToken == token else { return }
            outgoingSnapshot = nil
            settledSnapshot = AnyView(pane(erasedContent()))
        }
    }
}
