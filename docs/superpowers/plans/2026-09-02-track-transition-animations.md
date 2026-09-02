# Track Transition Animations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Directional song-info slide + artwork crossfade on every now-playing track change across all music surfaces.

**Architecture:** `MusicManager` publishes `trackTransitionDirection` resolved from pending next/previous + expected queue-next URI; shared `TrackTransition` SwiftUI helpers wrap artwork and metadata at each call site.

**Tech Stack:** SwiftUI, Combine/`@Published` on `MusicManager`, Swift Testing (`SapphireTests`)

## Global Constraints

- Direction: forward = text out leading / in from trailing; backward = mirrored; neutral = opacity
- Artwork: opacity crossfade only (~0.28s easeInOut)
- Text: ~0.28s easeInOut; Reduce Motion → opacity only
- Apply on any track identity change; infer direction when possible
- Surfaces: widget, expanded player, lyrics headers, hub now-playing, lock screen pane, live activity
- Do not animate transport controls, scrubber, or next-track pill
- Spec: `docs/superpowers/specs/2026-09-02-track-transition-animations-design.md`

---

## File Structure

| File | Responsibility |
|------|----------------|
| `Sapphire/Utilities/TrackTransition.swift` | Direction enum, resolver, motion constants, `ArtworkCrossfade`, `TrackMetadataTransition` |
| `Sapphire/Services/Music/MusicManager.swift` | Pending direction, expected-next URI, publish on identity change |
| `Sapphire/Widgets/MusicPlayer/MusicPlayerViews.swift` | Wire widget + expanded player |
| `Sapphire/Widgets/MusicPlayer/LyricsViews.swift` | Wire lyrics headers |
| `Sapphire/Widgets/MusicPlayer/MusicHubViews.swift` | Wire hub now-playing art/text |
| `Sapphire/Services/LockScreen/LockScreenMusicPane.swift` | Wire lock screen cover + metadata |
| `Sapphire/LiveActivities/LiveActivityComponents.swift` | Wire `AlbumArtView` + `QuickPeekView` |
| `SapphireTests/TrackTransitionResolverTests.swift` | Resolver unit tests |

---

### Task 1: Resolver + shared UI helpers

**Files:**
- Create: `Sapphire/Utilities/TrackTransition.swift`
- Create: `SapphireTests/TrackTransitionResolverTests.swift`

**Interfaces:**
- Produces: `TrackTransitionDirection`, `TrackTransitionResolver.resolve(pending:incomingURI:expectedNextURI:)`, `TrackTransitionMotion`, `ArtworkCrossfade`, `TrackMetadataTransition`

- [ ] **Step 1: Add failing resolver tests**

```swift
import Testing
@testable import Sapphire

struct TrackTransitionResolverTests {
    @Test func pendingForwardWinsOverExpectedNext() {
        let result = TrackTransitionResolver.resolve(
            pending: .forward,
            incomingURI: "spotify:track:b",
            expectedNextURI: "spotify:track:other"
        )
        #expect(result == .forward)
    }

    @Test func pendingBackwardWins() {
        let result = TrackTransitionResolver.resolve(
            pending: .backward,
            incomingURI: "spotify:track:a",
            expectedNextURI: "spotify:track:b"
        )
        #expect(result == .backward)
    }

    @Test func matchingExpectedNextInfersForward() {
        let result = TrackTransitionResolver.resolve(
            pending: nil,
            incomingURI: "spotify:track:next",
            expectedNextURI: "spotify:track:next"
        )
        #expect(result == .forward)
    }

    @Test func unknownChangeIsNeutral() {
        let result = TrackTransitionResolver.resolve(
            pending: nil,
            incomingURI: "spotify:track:jump",
            expectedNextURI: "spotify:track:next"
        )
        #expect(result == .neutral)
    }

    @Test func emptyIncomingIsNeutral() {
        let result = TrackTransitionResolver.resolve(
            pending: nil,
            incomingURI: nil,
            expectedNextURI: "spotify:track:next"
        )
        #expect(result == .neutral)
    }
}
```

- [ ] **Step 2: Implement `TrackTransition.swift`**

Include:
- `enum TrackTransitionDirection: Equatable, Sendable { case forward, backward, neutral }`
- `enum TrackTransitionResolver` with `resolve(pending:incomingURI:expectedNextURI:)` — pending non-nil wins; else forward if URIs equal and non-empty; else neutral
- `enum TrackTransitionMotion` with `duration = 0.28`, `animation = .easeInOut(duration: duration)`
- `ArtworkCrossfade<Content: View>` — ZStack, content `.id(token)`, `.transition(.opacity)`, animate on token (force opacity if reduce motion — still opacity)
- `TrackMetadataTransition<Content: View>` — takes `identity: String`, reads `@EnvironmentObject MusicManager` + `accessibilityReduceMotion`; ZStack + clipped; transition from direction; animate on identity

```swift
extension TrackTransitionDirection {
    var textTransition: AnyTransition {
        switch self {
        case .forward:
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        case .backward:
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        case .neutral:
            return .opacity
        }
    }
}
```

- [ ] **Step 3: Run tests**

Run: `xcodebuild test -scheme Sapphire -destination 'platform=macOS' -only-testing:SapphireTests/TrackTransitionResolverTests`

Expected: PASS

- [ ] **Step 4: Commit** (only if user requested commits)

---

### Task 2: MusicManager transition signal

**Files:**
- Modify: `Sapphire/Services/Music/MusicManager.swift`

**Interfaces:**
- Consumes: `TrackTransitionResolver`, `TrackTransitionDirection`
- Produces: `@Published private(set) var trackTransitionDirection`

- [ ] **Step 1: Add state**

```swift
@Published private(set) var trackTransitionDirection: TrackTransitionDirection = .neutral
private var pendingTrackTransitionDirection: TrackTransitionDirection?
private var expectedNextTrackURI: String?
```

- [ ] **Step 2: Maintain `expectedNextTrackURI`**

Whenever `nativeQueue` or `appleMusicNextTrack` is assigned/updated, set:

```swift
expectedNextTrackURI = nativeQueue.first?.uri
    ?? appleMusicNextTrack.map { "apple:\($0.title)|\($0.artist)" }
```

(Use Apple Music’s stable id if available; otherwise title|artist key.)

- [ ] **Step 3: Set pending in skip APIs**

In `nextTrack()` set `pendingTrackTransitionDirection = .forward` before skip.  
In `previousTrack()` set `pendingTrackTransitionDirection = .backward` before skip.

- [ ] **Step 4: Publish on identity change**

Add:

```swift
private func publishTrackTransition(incomingURI: String?) {
    let resolved = TrackTransitionResolver.resolve(
        pending: pendingTrackTransitionDirection,
        incomingURI: incomingURI,
        expectedNextURI: expectedNextTrackURI
    )
    pendingTrackTransitionDirection = nil
    trackTransitionDirection = resolved
}
```

Call from:
- Media Remote `hasTrackChanged` block (use payload URI / trackIdentity)
- `handleSpotifyTrackAdvanced` when track non-nil (use `track.uri`) — call **before** mutating queue head removal so `expectedNextTrackURI` still matches
- `syncConnectNowPlayingMetadata` when URI/identity changes

On clear/reset now-playing paths, set `trackTransitionDirection = .neutral` and clear pending.

- [ ] **Step 5: Manual smoke** — skip next/previous; confirm `trackTransitionDirection` flips in debugger if needed

---

### Task 3: Wire primary player surfaces

**Files:**
- Modify: `Sapphire/Widgets/MusicPlayer/MusicPlayerViews.swift`

- [ ] **Step 1: Expanded `artworkSection`**

Wrap still artwork `Image` in `ArtworkCrossfade(token: musicManager.currentTrackArtworkToken)` (keep canvas path as-is).

- [ ] **Step 2: Expanded title/artist block**

Wrap the metadata `VStack` (the button content with title/artist) in:

```swift
TrackMetadataTransition(identity: "track-\(musicManager.uri ?? musicManager.title ?? "")-\(musicManager.artist ?? "")") {
  // existing VStack
}
```

Remove redundant `.id` on the outer button if the wrapper owns identity, or keep button action outside the transitioning content.

- [ ] **Step 3: `MusicWidgetView`**

Wrap `albumArt` image in `ArtworkCrossfade(token:)`.  
Wrap `MusicInfoView` in `TrackMetadataTransition` with the existing info identity string; remove weak value animations that fight the transition.

---

### Task 4: Wire remaining surfaces

**Files:**
- Modify: `Sapphire/Widgets/MusicPlayer/LyricsViews.swift`
- Modify: `Sapphire/Widgets/MusicPlayer/MusicHubViews.swift`
- Modify: `Sapphire/Services/LockScreen/LockScreenMusicPane.swift`
- Modify: `Sapphire/LiveActivities/LiveActivityComponents.swift`

- [ ] **Step 1: Lyrics headers** — wrap small artwork + title/artist stacks with helpers (detached + inline headers that show now-playing chrome).

- [ ] **Step 2: Hub** — wrap Apple Music now view art/text and Spotify now-playing hero art/text.

- [ ] **Step 3: Lock screen** — wrap main cover(s) and title/artist/album stacks; leave ambient blur timing alone or only key opacity to token without directional slide.

- [ ] **Step 4: Live activity** — update `AlbumArtView` to crossfade on `currentTrackArtworkToken` (remove `.animation(nil, ...)`); wrap `QuickPeekView` text with metadata transition using title+artist identity.

---

### Task 5: Verification

- [ ] **Step 1: Run resolver tests** (same command as Task 1)
- [ ] **Step 2: Manual acceptance checklist from spec**
- [ ] **Step 3: Fix any clip/layout regressions** (ensure wrappers don’t expand hit targets oddly)

---

## Spec coverage

| Spec requirement | Task |
|------------------|------|
| Directional text slide | 1, 3, 4 |
| Artwork crossfade | 1, 3, 4 |
| Any track change + infer / neutral | 2 |
| All listed surfaces | 3, 4 |
| Snappy 0.28s ease | 1 |
| Reduce Motion | 1 |
| Rapid skips / same-album fade | 2 + helpers |
| Resolver tests | 1 |
