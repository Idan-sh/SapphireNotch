import AppKit
import SwiftUI

enum FeatureGateStyle {
    static let disabledTint = Color.white.opacity(0.22)

    static func tint(isActive: Bool) -> Color {
        isActive ? Color.accentColor : disabledTint
    }
}

extension View {
    /// Disables interaction and forces gray (vs accent) chrome while inactive.
    /// Also rebuilds AppKit controls so enabled appearance isn't stuck stale.
    func featureGated(_ isActive: Bool) -> some View {
        disabled(!isActive)
            .opacity(isActive ? 1 : 0.45)
            .tint(FeatureGateStyle.tint(isActive: isActive))
            .id(isActive)
    }

    /// Notch panels are non-key by default; AppKit controls stay gray until focusable.
    func notchDetailKeyboardFocus() -> some View {
        onAppear { (NSApp.delegate as? AppDelegate)?.makeNotchWindowFocusable() }
            .onDisappear { (NSApp.delegate as? AppDelegate)?.revertNotchWindowFocus() }
    }
}
