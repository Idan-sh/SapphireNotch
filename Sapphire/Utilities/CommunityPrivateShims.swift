//
//  CommunityPrivateShims.swift
//  Sapphire
//
//  Minimal stand-ins for symbols that live in the private Sapphire package
//  on upstream but are referenced by the public tree.
//

import SwiftUI
import CoreGraphics

enum SapphireSyntheticEventMarker {
    /// Matches the upstream marker used to ignore synthetic paste key events.
    static let plainTextPaste: Int64 = 0x5A50_4852_5054_5354 // "SAPRPTST"
}

/// Upstream bridges ScreenCaptureKit picker results into the notch.
/// Community builds keep picker wiring via ContentPickerHelper elsewhere.
struct GeminiPickerBridge: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    /// Measures the view's ideal size into a binding (upstream helper).
    func measureIdealSize(into size: Binding<CGSize>) -> some View {
        background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: IdealSizePreferenceKey.self, value: geo.size)
                    .onAppear {
                        let newSize = geo.size
                        if abs(newSize.width - size.wrappedValue.width) > 0.5
                            || abs(newSize.height - size.wrappedValue.height) > 0.5 {
                            size.wrappedValue = newSize
                        }
                    }
                    .onChange(of: geo.size) { _, newSize in
                        if abs(newSize.width - size.wrappedValue.width) > 0.5
                            || abs(newSize.height - size.wrappedValue.height) > 0.5 {
                            size.wrappedValue = newSize
                        }
                    }
            }
        )
        .onPreferenceChange(IdealSizePreferenceKey.self) { newSize in
            if abs(newSize.width - size.wrappedValue.width) > 0.5
                || abs(newSize.height - size.wrappedValue.height) > 0.5 {
                size.wrappedValue = newSize
            }
        }
    }
}

private struct IdealSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
