import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

@main
struct ShazamSyncWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ShazamSyncLiveActivity()
    }
}

struct ShazamSyncLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShazamSyncAttributes.self) { context in
            // Lock Screen, Home Screen Banner, and StandBy presentation
            LockScreenLiveActivityView(
                state: context.state,
                isStale: context.isStale
            )
            .activityBackgroundTint(Color.black.opacity(0.65))
            .activitySystemActionForegroundColor(.cyan)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded Leading Region
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.cyan, .blue, .purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 36, height: 36)

                            Image(systemName: context.state.phase.symbolName)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .symbolEffect(.pulse, isActive: context.state.phase == .listening || context.state.phase == .playing)
                        }
                        Text(context.state.phase.shortLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.cyan)
                    }
                    .accessibilityLabel("Status: \(context.state.phase.rawValue)")
                }

                // Expanded Trailing Region
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.horizontal.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                            Text(String(format: "%+dms", context.state.syncDriftMs))
                                .font(.caption2.monospacedDigit().weight(.bold))
                                .foregroundStyle(.green)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.18), in: Capsule())

                        if context.isStale {
                            Text("Stale")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    .accessibilityLabel("Acoustic sync offset \(context.state.syncDriftMs) milliseconds")
                }

                // Expanded Center Region
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 3) {
                        Text(context.state.songTitle)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .contentTransition(.interpolate)

                        Text(context.state.artistName)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                    .padding(.top, 2)
                }

                // Expanded Bottom Region: Progress Bar + Interactive LiveActivityIntent Controls
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        if context.state.phase == .playing {
                            ProgressView(
                                timerInterval: context.state.timerInterval,
                                countsDown: false
                            ) {
                                EmptyView()
                            } currentValueLabel: {
                                EmptyView()
                            }
                            .tint(.cyan)
                            .labelsHidden()
                        } else {
                            ProgressView(
                                value: min(context.state.currentOffset, context.state.songDuration),
                                total: max(1, context.state.songDuration)
                            )
                            .tint(.cyan)
                        }

                        // Interactive Controls using AppIntents (LiveActivityIntent)
                        HStack(spacing: 12) {
                            Button(intent: NudgeBackwardIntent()) {
                                Label("-50ms", systemImage: "gobackward.minus")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                            .background(Color.white.opacity(0.14), in: Capsule())
                            .accessibilityLabel("Nudge sync backward 50 milliseconds")

                            Button(intent: TogglePlaybackIntent()) {
                                Image(systemName: context.state.phase == .playing ? "pause.fill" : "play.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .frame(width: 38, height: 28)
                            }
                            .buttonStyle(.plain)
                            .background(Color.cyan.opacity(0.3), in: Capsule())
                            .accessibilityLabel(context.state.phase == .playing ? "Pause" : "Play")

                            Button(intent: NudgeForwardIntent()) {
                                Label("+50ms", systemImage: "goforward.plus")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                            .background(Color.white.opacity(0.14), in: Capsule())
                            .accessibilityLabel("Nudge sync forward 50 milliseconds")

                            Button(intent: ResyncAmbientIntent()) {
                                Image(systemName: "dot.radiowaves.left.and.right")
                                    .font(.system(size: 13, weight: .bold))
                                    .frame(width: 32, height: 28)
                            }
                            .buttonStyle(.plain)
                            .background(Color.purple.opacity(0.35), in: Capsule())
                            .accessibilityLabel("Re-sync ambient audio")
                        }
                        .foregroundStyle(.white)
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                CompactLeadingView(phase: context.state.phase)
            } compactTrailing: {
                CompactTrailingView(state: context.state)
            } minimal: {
                ZStack {
                    Circle()
                        .fill(Color.cyan.opacity(0.25))
                        .frame(width: 26, height: 26)
                    Image(systemName: context.state.phase.symbolName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.cyan)
                }
                .accessibilityLabel("ShazamSync \(context.state.phase.rawValue)")
            }
            .keylineTint(.cyan)
        }
    }
}

// MARK: - Dynamic Island Compact Views (supporting isDynamicIslandLimitedInWidth)

struct CompactLeadingView: View {
    let phase: SyncPhase

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.cyan, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 24, height: 24)
            Image(systemName: phase.symbolName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
        }
        .accessibilityLabel("ShazamSync \(phase.shortLabel)")
    }
}

struct CompactTrailingView: View {
    let state: ShazamSyncAttributes.ContentState

    var body: some View {
        ViewThatFits(in: .horizontal) {
            if state.phase == .playing {
                Text(timerInterval: state.timerInterval, countsDown: false)
                    .monospacedDigit()
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.cyan)
                    .frame(maxWidth: 48)
                    .contentTransition(.numericText(countsDown: false))
            } else {
                Text(state.phase.shortLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.cyan)
                    .lineLimit(1)
            }

            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.cyan)
        }
    }
}

// MARK: - Lock Screen & StandBy Live Activity View

struct LockScreenLiveActivityView: View {
    @Environment(\.isActivityFullscreen) private var isStandByFullscreen
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    let state: ShazamSyncAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.cyan, .blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: isStandByFullscreen ? 56 : 46, height: isStandByFullscreen ? 56 : 46)

                    Image(systemName: state.phase.symbolName)
                        .font(.system(size: isStandByFullscreen ? 26 : 20, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(state.phase.rawValue.uppercased())
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(.cyan)

                        if state.phase == .playing {
                            Text(String(format: "LOCKED %+dms", state.syncDriftMs))
                                .font(.caption2.monospacedDigit().weight(.bold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.18), in: Capsule())
                        }
                    }

                    Text(state.songTitle)
                        .font(isStandByFullscreen ? .title3.weight(.bold) : .headline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(state.artistName)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }

                Spacer()

                if state.phase == .playing && !isLuminanceReduced {
                    Text(timerInterval: state.timerInterval, countsDown: false)
                        .font(.subheadline.monospacedDigit().weight(.bold))
                        .foregroundStyle(.cyan)
                        .contentTransition(.numericText(countsDown: false))
                }
            }

            if state.phase == .playing {
                ProgressView(
                    timerInterval: state.timerInterval,
                    countsDown: false
                ) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(.cyan)
                .labelsHidden()
            } else {
                ProgressView(
                    value: min(state.currentOffset, state.songDuration),
                    total: max(1, state.songDuration)
                )
                .tint(.cyan)
            }

            if !isLuminanceReduced {
                HStack(spacing: 10) {
                    Button(intent: NudgeBackwardIntent()) {
                        Label("-50ms", systemImage: "gobackward.minus")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .background(Color.white.opacity(0.14), in: Capsule())

                    Button(intent: TogglePlaybackIntent()) {
                        Label(
                            state.phase == .playing ? "Pause" : "Play",
                            systemImage: state.phase == .playing ? "pause.fill" : "play.fill"
                        )
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .background(Color.cyan.opacity(0.28), in: Capsule())

                    Button(intent: NudgeForwardIntent()) {
                        Label("+50ms", systemImage: "goforward.plus")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .background(Color.white.opacity(0.14), in: Capsule())

                    Button(intent: ResyncAmbientIntent()) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .background(Color.purple.opacity(0.32), in: Capsule())
                }
                .foregroundStyle(.white)
            }
        }
        .padding(14)
        .accessibilityElement(children: .contain)
    }
}
