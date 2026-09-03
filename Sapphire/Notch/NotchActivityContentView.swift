//
//  NotchActivityContentView.swift
//  Sapphire
//
//  Live-activity content for the auto/hover-expanded notch.
//  Lifted from the pre-merge fork's NotchController helpers and adapted
//  to the current LiveActivityContent / StandardActivityData APIs.
//

import SwiftUI
import AppKit
import EventKit

private struct MaxContentWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct NotchActivityContentView: View {
    let content: LiveActivityContent
    let config: ResolvedNotchConfiguration
    let shape: CustomNotchShape
    let horizontalPadding: CGFloat
    let screen: NSScreen?
    @Binding var measuredSize: CGSize
    @Binding var showLyrics: Bool

    @EnvironmentObject private var musicWidget: MusicManager
    @EnvironmentObject private var settings: SettingsModel
    @EnvironmentObject private var timerManager: TimerManager
    @EnvironmentObject private var geminiLiveManager: GeminiLiveManager

    @State private var maxActivityContentWidth: CGFloat = 0

    var body: some View {
        // `screen` is part of the public initializer API used by NotchController
        // (multi-display sizing may consult it later).
        let _ = screen
        Group {
            switch content {
            case .full(let view, _, _):
                view
                    .padding(.horizontal, config.activityContentHorizontalPadding)
                    .clipShape(shape)
            case .standard(let data, _):
                buildStandardActivityView(from: data)
                    .clipShape(shape)
            case .none:
                EmptyView()
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { updateMeasuredSize(geo.size) }
                    .onChange(of: geo.size) { _, newSize in
                        updateMeasuredSize(newSize)
                    }
            }
        )
    }

    private func updateMeasuredSize(_ newSize: CGSize) {
        let epsilon: CGFloat = 0.5
        if abs(newSize.width - measuredSize.width) > epsilon ||
            abs(newSize.height - measuredSize.height) > epsilon {
            measuredSize = newSize
        }
    }

    @ViewBuilder
    private func buildStandardActivityView(from data: StandardActivityData) -> some View {
        VStack(spacing: 0) {
            let left = buildLeftView(for: data)
            let right = buildRightView(for: data)

            HStack(spacing: 0) {
                HStack {
                    Spacer()
                    left
                        .fixedSize()
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(key: MaxContentWidthPreferenceKey.self, value: geo.size.width)
                            }
                        )
                }
                Spacer().frame(width: config.initialSize.width)
                HStack {
                    right
                        .fixedSize()
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(key: MaxContentWidthPreferenceKey.self, value: geo.size.width)
                            }
                        )
                    Spacer()
                }
            }
            .hidden()
            .frame(height: 0)
            .onPreferenceChange(MaxContentWidthPreferenceKey.self) { newMaxWidth in
                withAnimation(config.activityToActivityAnimation) {
                    maxActivityContentWidth = newMaxWidth
                }
            }

            GeometryReader { geometry in
                let totalWidth = geometry.size.width
                HStack(spacing: 0) {
                    HStack(alignment: .center) {
                        left
                        Spacer(minLength: 0)
                    }
                    .frame(width: (totalWidth - config.initialSize.width) / 2, alignment: .leading)

                    Spacer()
                        .frame(width: config.initialSize.width)

                    HStack(alignment: .center) {
                        Spacer(minLength: 0)
                        right
                    }
                    .frame(width: (totalWidth - config.initialSize.width) / 2, alignment: .trailing)
                }
                .frame(height: geometry.size.height, alignment: .center)
            }
            .frame(width: maxActivityContentWidth * 2 + config.initialSize.width)
            .frame(height: config.initialSize.height)
            .padding(.horizontal, horizontalPadding)

            if let bottomView = getBottomView(for: data) {
                VStack {
                    bottomView
                        .padding(.bottom, config.activityContentBottomPadding)
                }
                .padding(.horizontal, horizontalPadding)
            }
        }
    }

    private func getBottomView(for data: StandardActivityData) -> AnyView? {
        switch data {
        case .music(let bottomContentType):
            switch bottomContentType {
            case .none:
                return nil
            case .peek(let title, let artist):
                return AnyView(QuickPeekView(title: title, artist: artist))
            case .lyrics(let text, let id):
                let view = Text(text)
                    .font(.system(size: NotchConfiguration.lyricsFontSize, weight: .semibold, design: .rounded))
                    .foregroundColor(musicWidget.accentColor.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: NotchConfiguration.lyricsMaxWidth)
                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                    .id("lyric-\(id.uuidString)")
                    .onTapGesture { showLyrics = true }
                return AnyView(view)
            case .upNext(let title, let artist, let artworkURL):
                return AnyView(
                    MusicUpNextView(title: title, artist: artist, artworkURL: artworkURL)
                )
            }
        case .sports(_, let bottom):
            switch bottom {
            case .none:
                return nil
            case .commentary(let text, let id):
                let view = Text(text)
                    .font(.system(size: NotchConfiguration.lyricsFontSize, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: NotchConfiguration.lyricsMaxWidth)
                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                    .id("sports-comment-\(id)")
                return AnyView(view)
            }
        case .focusSession:
            return AnyView(
                FocusStreakWeekStrip(days: 7, showLetters: false)
                    .environmentObject(FocusSessionManager.shared)
                    .padding(.top, 2)
            )
        default:
            return nil
        }
    }

    @ViewBuilder
    private func buildLeftView(for data: StandardActivityData) -> some View {
        switch data {
        case .music: AlbumArtView()
        case .intelligenceAgent: IntelligenceAgentActivityView.left()
        case .weather(let data): WeatherActivityView.left(for: data)
        case .calendar: CalendarProximityActivityView.left()
        case .reminder: ReminderProximityActivityView.left()
        case .timer: TimerActivityView.left(timerManager: timerManager)
        case .focusSession: FocusSessionActivityView.left()
        case .battery(let state, let style, let timeRemaining, let systemState):
            switch style {
            case .persistent: PersistentBatteryActivityView.left(for: state, timeRemaining: timeRemaining, systemState: systemState)
            case .default: DefaultBatteryActivityView.left(for: state, systemState: systemState)
            case .compact: CompactBatteryActivityView.left(for: state, systemState: systemState)
            }
        case .desktop(let number): DesktopActivityView.left(for: number)
        case .focus(let mode): FocusModeActivityView.left(for: mode)
        case .fileShelf: FileShelfActivityView.left()
        case .fileProgress(let task): FileProgressLiveActivityView.left(for: task)
        case .bluetooth(let device):
            switch device.eventType {
            case .connected:
                if device.isContinuityDevice { BluetoothConnectedContinuityView.left(for: device) }
                else { BluetoothConnectedPeripheralView.left(for: device) }
            case .disconnected: BluetoothDisconnectedView.left(for: device)
            case .batteryLow: BluetoothBatteryLowView.left(for: device)
            }
        case .audioSwitch(let event): AudioSwitchActivityView.left(for: event)
        case .geminiLive: GeminiActiveActivityView.left()
        case .sports(let payload, _): SportsLiveActivityView.left(for: payload, preferLogo: settings.settings.sportsPreferLogo)
        case .finance(let payload): FinanceLiveActivityView.left(for: payload)
        case .microphone:
            MicrophoneLiveActivityView.left { MicrophoneUsageManager.shared.toggleMute() }
        case .nearDrop: NearDropCompactActivityView.left()
        case .hud(let type): SystemHUDSlimActivityView.left(type: type, settings: settings)
        case .lockScreen: LockScreenLiveActivityView.left()
        case .updateAvailable: UpdateAvailableActivityView.left()
        case .unlocked: LockScreenLiveActivityView.left()
        case .stats(let payload): statsLiveActivityView.left(for: payload, selectedStats: settings.settings.selectedStats, selectedSensorKeys: settings.settings.selectedSensorKeys)
        }
    }

    @ViewBuilder
    private func buildRightView(for data: StandardActivityData) -> some View {
        switch data {
        case .music: WaveformView()
        case .intelligenceAgent(let status, let stepTitle, let current, let total):
            IntelligenceAgentActivityView.right(status: status, stepTitle: stepTitle, current: current, total: total)
        case .weather(let data): WeatherActivityView.right(for: data)
        case .calendar(let event): CalendarProximityActivityView.right(event: event)
        case .reminder(let reminder): ReminderProximityActivityView.right(reminder: reminder)
        case .timer: TimerActivityView.right(timerManager: timerManager)
        case .focusSession: FocusSessionActivityView.right()
        case .battery(let state, let style, let timeRemaining, let systemState):
            switch style {
            case .persistent: PersistentBatteryActivityView.right(for: state, systemState: systemState)
            case .default: DefaultBatteryActivityView.right(for: state, timeRemaining: timeRemaining, systemState: systemState)
            case .compact: CompactBatteryActivityView.right(for: state)
            }
        case .desktop(let number): DesktopActivityView.right(for: number)
        case .focus(let mode): FocusModeActivityView.right(for: mode, displayMode: settings.settings.focusDisplayMode)
        case .fileShelf(let count): FileShelfActivityView.right(count: count)
        case .fileProgress(let task): FileProgressLiveActivityView.right(for: task)
        case .bluetooth(let device):
            switch device.eventType {
            case .connected:
                if device.isContinuityDevice { BluetoothConnectedContinuityView.right(for: device) }
                else { BluetoothConnectedPeripheralView.right(for: device) }
            case .disconnected: BluetoothDisconnectedView.right(for: device)
            case .batteryLow: BluetoothBatteryLowView.right(for: device)
            }
        case .audioSwitch(let event): AudioSwitchActivityView.right(for: event)
        case .geminiLive(let payload):
            GeminiActiveActivityView.right(isMuted: payload.isMicMuted) { geminiLiveManager.toggleMicrophone() }
        case .sports(let payload, _):
            SportsLiveActivityView.right(for: payload, preferLogo: settings.settings.sportsPreferLogo)
        case .finance(let payload):
            FinanceLiveActivityView.right(for: payload)
        case .microphone: MicrophoneLiveActivityView.right { MicrophoneUsageManager.shared.toggleMute() }
        case .nearDrop(let payload): NearDropCompactActivityView.right(payload: payload)
        case .hud(let type): SystemHUDSlimActivityView.right(type: type, settings: SettingsModel.shared)
        case .lockScreen: LockScreenLiveActivityView.right()
        case .updateAvailable(let version): UpdateAvailableActivityView.right(version: version)
        case .unlocked: LockScreenLiveActivityView.right()
        case .stats(let payload): statsLiveActivityView.right(for: payload, selectedStats: settings.settings.selectedStats, selectedSensorKeys: settings.settings.selectedSensorKeys)
        }
    }
}
