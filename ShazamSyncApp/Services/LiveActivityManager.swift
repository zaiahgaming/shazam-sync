import Foundation
import ActivityKit

/// Manages starting, updating, and ending Dynamic Island and Lock Screen Live Activities.
@MainActor
public final class LiveActivityManager {
    public static let shared = LiveActivityManager()

    private var currentActivity: Activity<ShazamSyncAttributes>?

    private init() {}

    public var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    public func startOrUpdate(
        phase: SyncPhase,
        songTitle: String,
        artistName: String,
        albumArtURL: String? = nil,
        currentOffset: Double = 0,
        songDuration: Double = 180,
        syncDriftMs: Int = 0,
        isAutoLoopEnabled: Bool = true,
        alertOnMatch: Bool = false
    ) {
        guard areActivitiesEnabled else { return }

        let state = ShazamSyncAttributes.ContentState(
            phase: phase,
            songTitle: songTitle,
            artistName: artistName,
            albumArtURL: albumArtURL,
            currentOffset: currentOffset,
            songDuration: songDuration,
            syncDriftMs: syncDriftMs,
            stateUpdatedAt: .now,
            isAutoLoopEnabled: isAutoLoopEnabled
        )

        let content = ActivityContent(
            state: state,
            staleDate: Date.now.addingTimeInterval(3600),
            relevanceScore: phase == .playing ? 100 : 75
        )

        if let existing = currentActivity ?? Activity<ShazamSyncAttributes>.activities.first {
            currentActivity = existing
            Task {
                var alertConfig: AlertConfiguration? = nil
                if alertOnMatch {
                    alertConfig = AlertConfiguration(
                        title: "Synced: \(songTitle)",
                        body: "\(artistName) — Locked at \(String(format: "%.1fs", currentOffset))",
                        sound: .default
                    )
                }
                await existing.update(content, alertConfiguration: alertConfig)
            }
        } else {
            let attributes = ShazamSyncAttributes()
            do {
                currentActivity = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
            } catch {
                // Gracefully ignore if device limit is reached
            }
        }
    }

    public func endAll(immediate: Bool = false) {
        Task {
            let finalState = ShazamSyncAttributes.ContentState(
                phase: .idle,
                songTitle: "Session Ended",
                artistName: "ShazamSync",
                currentOffset: 0,
                songDuration: 1,
                syncDriftMs: 0,
                stateUpdatedAt: .now,
                isAutoLoopEnabled: false
            )
            let finalContent = ActivityContent(state: finalState, staleDate: nil)
            let policy: ActivityUIDismissalPolicy = immediate ? .immediate : .default

            for activity in Activity<ShazamSyncAttributes>.activities {
                await activity.end(finalContent, dismissalPolicy: policy)
            }
            currentActivity = nil
        }
    }
}
