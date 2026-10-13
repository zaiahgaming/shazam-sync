import SwiftUI

struct ContentView: View {
    @State private var engine = ShazamSyncEngine.shared
    @State private var showingSettings = false
    @State private var showingHistory = false
    @Namespace private var glassNamespace

    var body: some View {
        NavigationStack {
            ZStack {
                // Full-bleed Ambient Liquid Background
                ambientBackgroundLayer

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Top Status Pill & Auto-Loop Toggle in a Liquid Glass Container
                        topStatusBar

                        // Morphing Hero Centerpiece (Sonic Orb <-> Track Sync Card)
                        heroSection

                        // Live Acoustic Waveform & Phase-Lock Meter
                        waveformGlassCard

                        // Interactive Liquid Glass Transport & Sub-Millisecond Nudge Bar
                        transportAndNudgeControls

                        // Session History Preview
                        if !engine.history.isEmpty {
                            recentHistoryCard
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("ShazamSync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        showingHistory = true
                    } label: {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsSheetView(engine: engine)
            }
            .sheet(isPresented: $showingHistory) {
                HistorySheetView(engine: engine)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Ambient Background Layer

    private var ambientBackgroundLayer: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.05, blue: 0.14),
                    Color(red: 0.07, green: 0.03, blue: 0.20),
                    Color(red: 0.02, green: 0.12, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Glowing radial orbs behind the Liquid Glass surfaces
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            phaseAccentColor.opacity(0.45),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 220
                    )
                )
                .frame(width: 420, height: 420)
                .offset(x: -60, y: -140)
                .blur(radius: 30)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.purple.opacity(0.38),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 200
                    )
                )
                .frame(width: 380, height: 380)
                .offset(x: 90, y: 180)
                .blur(radius: 35)
        }
    }

    // MARK: - Top Status Pill Bar (Liquid Glass Container)

    private var topStatusBar: some View {
        GlassEffectContainer(spacing: 20.0) {
            HStack(spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: engine.phase.symbolName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(phaseAccentColor)
                        .symbolEffect(.pulse, isActive: engine.phase != .idle)

                    Text(engine.phase.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular.tint(phaseAccentColor.opacity(0.25)))
                .glassEffectID("statusPill", in: glassNamespace)

                Spacer()

                Button {
                    withAnimation(.snappy) {
                        engine.isAutoLoopEnabled.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: engine.isAutoLoopEnabled ? "repeat.circle.fill" : "repeat.1.circle")
                            .font(.system(size: 15, weight: .bold))
                        Text(engine.isAutoLoopEnabled ? "Auto-Loop ON" : "Single Track")
                            .font(.caption.weight(.bold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .glassEffect(
                    engine.isAutoLoopEnabled
                        ? .regular.tint(.cyan.opacity(0.3)).interactive()
                        : .regular.interactive()
                )
                .glassEffectID("loopToggle", in: glassNamespace)
            }
        }
    }

    // MARK: - Hero Centerpiece (Morphing Liquid Glass Container)

    private var heroSection: some View {
        GlassEffectContainer(spacing: 32.0) {
            VStack(spacing: 20) {
                // Interactive Sonic Shazam-Sync Orb
                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                        engine.toggleSession()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.cyan.opacity(0.7), .purple.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2.5
                            )
                            .frame(width: 148, height: 148)

                        VStack(spacing: 8) {
                            Image(systemName: engine.phase == .idle ? "shazam.logo.fill" : engine.phase.symbolName)
                                .font(.system(size: 46, weight: .bold))
                                .foregroundStyle(.white)
                                .symbolEffect(.bounce, value: engine.phase)

                            Text(engine.phase == .idle ? "TAP TO SYNC" : "ACTIVE")
                                .font(.caption2.weight(.heavy))
                                .tracking(1.4)
                                .foregroundStyle(.cyan)
                        }
                        .frame(width: 140, height: 140)
                    }
                }
                .buttonStyle(.plain)
                .glassEffect(
                    .regular.tint(phaseAccentColor.opacity(0.35)).interactive(),
                    in: Circle()
                )
                .glassEffectID("sonicOrb", in: glassNamespace)

                // Status Subtitle
                Text(engine.statusMessage)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)

                // Morphing Recognized Track Card
                if let track = engine.currentTrack {
                    recognizedTrackGlassCard(track)
                        .glassEffectID("recognizedTrackCard", in: glassNamespace)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }

    private func recognizedTrackGlassCard(_ track: RecognizedTrack) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                AsyncImage(url: track.albumArtURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            LinearGradient(
                                colors: [.cyan, .blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Image(systemName: "music.note")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .frame(width: 68, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text(engine.audioSourceDescription.isEmpty ? "SHAZAM MATCHED" : engine.audioSourceDescription.uppercased())
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(.cyan)
                    }

                    Text(track.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(track.artist)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }

                Spacer()
            }

            // Live Synchronized Seek Progress
            VStack(spacing: 6) {
                ProgressView(
                    value: min(engine.playbackPosition, max(1, engine.trackDuration)),
                    total: max(1, engine.trackDuration)
                )
                .tint(.cyan)

                HStack {
                    Text(engine.formatSeconds(engine.playbackPosition))
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(.cyan)

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "scope")
                            .font(.caption2)
                        Text(String(format: "Phase Drift: %+dms", track.driftMs))
                            .font(.caption2.monospacedDigit().weight(.semibold))
                    }
                    .foregroundStyle(.green)

                    Spacer()

                    Text(engine.formatSeconds(engine.trackDuration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .padding(18)
        .glassEffect(.regular.tint(.blue.opacity(0.18)), in: .rect(cornerRadius: 24.0))
    }

    // MARK: - Live Acoustic Waveform Card

    private var waveformGlassCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Acoustic Phase Telemetry", systemImage: "waveform.path.ecg")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.cyan)
                Spacer()
                Text(String(format: "Manual Offset: %+dms", engine.manualNudgeMs))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }

            HStack(alignment: .center, spacing: 4) {
                ForEach(Array(engine.waveformLevels.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.cyan, .purple],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: max(6, CGFloat(level) * 52))
                        .animation(.easeOut(duration: 0.12), value: level)
                }
            }
            .frame(height: 56)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 22.0))
    }

    // MARK: - Interactive Liquid Glass Transport & Fine-Sync Nudge Bar

    private var transportAndNudgeControls: some View {
        GlassEffectContainer(spacing: 16.0) {
            VStack(spacing: 14) {
                // Fine-Sync Millisecond Nudge Controls unified via glassEffectUnion
                HStack(spacing: 10) {
                    Button {
                        engine.nudgeSync(byMilliseconds: -50)
                    } label: {
                        Text("-50ms")
                            .font(.caption.monospacedDigit().weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive())
                    .glassEffectUnion(id: "nudgeControls", namespace: glassNamespace)

                    Button {
                        engine.nudgeSync(byMilliseconds: -10)
                    } label: {
                        Text("-10ms")
                            .font(.caption.monospacedDigit().weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive())
                    .glassEffectUnion(id: "nudgeControls", namespace: glassNamespace)

                    Button {
                        engine.nudgeSync(byMilliseconds: 10)
                    } label: {
                        Text("+10ms")
                            .font(.caption.monospacedDigit().weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive())
                    .glassEffectUnion(id: "nudgeControls", namespace: glassNamespace)

                    Button {
                        engine.nudgeSync(byMilliseconds: 50)
                    } label: {
                        Text("+50ms")
                            .font(.caption.monospacedDigit().weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive())
                    .glassEffectUnion(id: "nudgeControls", namespace: glassNamespace)
                }
                .foregroundStyle(.white)

                // Primary Action Buttons using iOS 26 .buttonStyle(.glass) & .buttonStyle(.glassProminent)
                HStack(spacing: 14) {
                    Button {
                        engine.togglePlayPause()
                    } label: {
                        Label(
                            engine.phase == .playing ? "Pause" : "Play",
                            systemImage: engine.phase == .playing ? "pause.fill" : "play.fill"
                        )
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.cyan)

                    Button {
                        engine.triggerImmediateResync()
                    } label: {
                        Label("Re-Sync Now", systemImage: "dot.radiowaves.left.and.right")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glass)

                    if engine.phase != .idle {
                        Button(role: .destructive) {
                            engine.stopSession()
                        } label: {
                            Image(systemName: "stop.fill")
                                .font(.subheadline.weight(.bold))
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
        }
    }

    // MARK: - Recent Synced Songs Card

    private var recentHistoryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Recently Synced Tracks", systemImage: "music.note.list")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(engine.history.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.cyan)
            }

            ForEach(engine.history.prefix(4)) { item in
                HStack(spacing: 12) {
                    Image(systemName: "waveform.badge.checkmark")
                        .foregroundStyle(.cyan)
                        .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(item.artist)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(String(format: "@ %.1fs", item.alignedOffset))
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundStyle(.green)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 22.0))
    }

    private var phaseAccentColor: Color {
        switch engine.phase {
        case .idle: return .blue
        case .listening, .matching: return .cyan
        case .downloading, .syncing: return .purple
        case .playing: return .green
        case .paused: return .orange
        }
    }
}

// MARK: - Settings & Companion Server Sheet

struct SettingsSheetView: View {
    @Bindable var engine: ShazamSyncEngine
    @Environment(\.dismiss) private var dismiss
    @State private var cachedCount: Int = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Ambient Recognition & Sync") {
                    Stepper(
                        value: $engine.listenDuration,
                        in: 4.0...10.0,
                        step: 0.5
                    ) {
                        HStack {
                            Text("Listen Window")
                            Spacer()
                            Text(String(format: "%.1fs", engine.listenDuration))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Toggle("Continuous Auto-Loop", isOn: $engine.isAutoLoopEnabled)

                    HStack {
                        Text("Manual Calibration Offset")
                        Spacer()
                        Text(String(format: "%+dms", engine.manualNudgeMs))
                            .monospacedDigit()
                            .foregroundStyle(.cyan)
                        Button("Reset") {
                            engine.manualNudgeMs = 0
                        }
                        .font(.caption)
                    }
                }

                Section {
                    TextField("http://192.168.0.100:8765", text: $engine.companionServerURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("LAN shazam-sync Companion Server (Optional)")
                } footer: {
                    Text("Leave blank for 100% standalone on-device ShazamKit + stream resolution. Or enter your Mac/Linux IP running `shazam-sync --serve` to share its yt-dlp cache.")
                }

                Section("On-Device Audio Cache") {
                    HStack {
                        Text("Cached Tracks")
                        Spacer()
                        Text("\(cachedCount) files")
                            .foregroundStyle(.secondary)
                    }

                    Button(role: .destructive) {
                        Task {
                            await TrackAcquisitionService.shared.clearCache()
                            cachedCount = await TrackAcquisitionService.shared.cachedFiles().count
                        }
                    } label: {
                        Label("Clear Audio Cache", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                cachedCount = await TrackAcquisitionService.shared.cachedFiles().count
            }
        }
    }
}

// MARK: - Session History Sheet

struct HistorySheetView: View {
    var engine: ShazamSyncEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if engine.history.isEmpty {
                    ContentUnavailableView(
                        "No Synced Songs Yet",
                        systemImage: "shazam.logo",
                        description: Text("Songs recognized around you will appear here with their phase-lock telemetry.")
                    )
                } else {
                    ForEach(engine.history) { track in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(track.title)
                                .font(.headline)
                            Text(track.artist)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 12) {
                                Label(String(format: "Matched @ %.2fs", track.alignedOffset), systemImage: "clock")
                                Label(String(format: "Drift %+dms", track.driftMs), systemImage: "scope")
                            }
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.cyan)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Sync History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
