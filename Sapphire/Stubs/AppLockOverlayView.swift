//
//  AppLockOverlayView.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-08-30

#if !SAPPHIRE_FULL_BUILD
import SwiftUI

struct AppLockOverlayView: View {
    let appName: String
    @ObservedObject var lockManager: AppLockManager
    let hasFaceID: Bool
    let hasTouchID: Bool
    let hasPassword: Bool
    let onFaceID: () -> Void
    let onTouchID: () -> Void
    let onSubmitPassword: (String) -> Bool
    let onQuit: (() -> Void)?
    var quitButtonTitle: String = "Quit App"

    var body: some View {
        Color.clear
    }
}

struct AppLockSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("App Lock")
                    .font(.largeTitle.bold())
                Text("App Lock requires the full Sapphire build.")
                    .foregroundStyle(.secondary)
            }
            .padding(25)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}
#endif