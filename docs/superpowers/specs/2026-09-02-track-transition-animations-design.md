# Track Transition Animations Design

**Date:** 2026-09-02  
**Status:** Approved for implementation  
**Repo:** SapphireNotch  
**Primary surfaces:** Music widget, expanded player, lyrics, hub, lock screen, live activity

## Problem

When the now-playing track changes, title/artist/album text and album artwork snap or weakly fade. There is no directional cue for next vs previous, and the cover does not consistently crossfade.

## Goals

1. On track change, **song info text slides directionally**: next → out left / in from right; previous → mirrored.
2. **Album cover crossfades**: previous fades out while the next fades in.
3. Apply on **every track change** when direction can be known; use **neutral fade** for text when direction is unknown. Cover still crossfades.
4. Cover **minimized widget, expanded player, and all other track info/artwork surfaces** (lyrics headers, music hub now-playing, lock screen music pane, live activity art/title).
5. Motion feel: **snappy** (~0.25–0.3s easeInOut).

## Non-goals

- Animating transport controls, progress scrubber, or next-track pill
- Redesigning player layout
- Sliding the album cover (fade only)
- Queuing multiple skip animations; latest track wins

## Decision

**Approach:** Central transition signal on `MusicManager` + shared SwiftUI wrappers.

Rejected alternatives:

- View-local direction tracking — duplicates logic; external skips diverge across surfaces
- Identity-only `.transition` without direction — cannot meet next/previous direction for auto-advance

## Architecture

```
MusicManager
  ├── pendingDirection (set by nextTrack / previousTrack)
  ├── expectedNextURI (from queue head / Apple Music next)
  └── trackTransitionDirection (published on identity change)

TrackTransition (utilities)
  ├── TrackTransitionDirection + resolver
  ├── TrackTransitionMotion (duration/animation)
  ├── ArtworkCrossfade container
  └── TrackMetadataTransition container

Call sites wrap existing artwork / metadata blocks
```

### Direction resolution (priority)

1. Pending direction from Sapphire `nextTrack()` / `previousTrack()`
2. Infer `.forward` when incoming URI equals the last known expected-next URI
3. Otherwise `.neutral`

Source switches, clear/empty now-playing, and unknown jumps use `.neutral`.

### Motion

| Element | Forward | Backward | Neutral / Reduce Motion |
|--------|---------|----------|-------------------------|
| Text | asymmetric horizontal slide + opacity | mirrored | opacity only |
| Artwork | opacity crossfade | opacity crossfade | opacity crossfade |

Duration: **0.28s** `easeInOut` for both.

### Components

- **`ArtworkCrossfade`**: `ZStack` keyed by `currentTrackArtworkToken` (or equivalent identity); `.transition(.opacity)`.
- **`TrackMetadataTransition`**: clips content; applies directional text transition from published direction; respects `accessibilityReduceMotion` (force neutral).

### Surfaces

| Surface | Artwork | Text |
|---------|---------|------|
| `MusicWidgetView` | yes | yes |
| `MusicPlayerView` | yes | yes |
| Lyrics detail headers | yes | yes |
| Music hub now-playing headers | yes | yes |
| Lock screen music pane | yes (main cover; ambient may keep slower ease) | yes |
| Live activity `AlbumArtView` + peek title | yes | yes |

### Edge cases

- Rapid skips: replace with latest identity; no animation backlog
- Same-album art: still crossfade on token/identity change
- Spotify live canvas: keep canvas swap; still-art path uses standard crossfade
- Reduce Motion: opacity only for text and cover

## Testing

- Unit tests for pure direction resolver (`SapphireTests`)
- Manual acceptance: directional next/previous on widget + expanded; auto-advance when next known; unknown jump → neutral text; rapid skips; same-album fade; lock screen / lyrics / hub / live activity; Reduce Motion

## Success criteria

Skipping next/previous feels directional and snappy on all listed surfaces; unknown changes still soft-crossfade the cover without a wrong slide.
