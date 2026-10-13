# ShazamSync for iOS 26

Ambient song recognizer, stream downloader, and sub-millisecond phase-synchronized player built for **iOS 26** with **Liquid Glass**, **Dynamic Island**, and **Lock Screen Live Activities**.

## Features

- **iOS 26 Liquid Glass Design (`GlassEffectContainer`, `.glassEffect`, `.glassEffectID`, `.glassEffectUnion`)**:
  - Uses native iOS 26 `GlassEffectContainer` and `.glassEffect(_:in:)` modifiers to render translucent, interactive glass controls that morph smoothly between listening, matching, phase-locking, and playing states.
  - Adopts `.buttonStyle(.glass)` and `.buttonStyle(.glassProminent)` along with `.glassEffectUnion` for unified millisecond nudge bars.
- **ShazamKit + Strict Validation**:
  - Uses `SHManagedSession` and `predictedCurrentMatchOffset` (plus optional LAN companion fallback) to identify songs around you.
  - Strictly rejects `"Unknown"` or unverified audio snippets.
- **Dual-Stage Acoustic Synchronization (`Accelerate` / `vDSP`)**:
  - Performs hardware-accelerated cross-correlation via `vDSP_conv` between the ambient microphone buffer and the downloaded reference audio track, compensating for intro variations and `AVAudioSession.sharedInstance().outputLatency` (AirPods / Bluetooth / speaker delay).
- **Dynamic Island & Lock Screen Live Activities (`ActivityKit` + `WidgetKit` + `AppIntents`)**:
  - Supports Compact Leading, Compact Trailing (adaptive to `isDynamicIslandLimitedInWidth`), Minimal, Expanded, Lock Screen Banner, and StandBy (`isActivityFullscreen`) presentations.
  - Interactive `LiveActivityIntent` buttons right in the Dynamic Island & Lock Screen: **`-50ms`**, **`Play/Pause`**, **`+50ms`**, and **`Re-Sync`**.
- **Lock Screen & AirPods Media Controls (`MPNowPlayingInfoCenter` & `MPRemoteCommandCenter`)**.
- **LAN Companion Mode (`shazam-sync --serve`)**:
  - Works 100% standalone on iOS, or optionally connects to your desktop running `shazam-sync --serve` on port `8765` to share its `yt-dlp` cache.
