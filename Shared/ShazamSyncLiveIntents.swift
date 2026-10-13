import Foundation
import AppIntents
import ActivityKit

/// Toggles Play / Pause directly from the Dynamic Island or Lock Screen Live Activity.
public struct TogglePlaybackIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Toggle Synced Playback"
    public static var description = IntentDescription("Pauses or resumes the synchronized track.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        ShazamSyncIPC.postDarwinNotification(ShazamSyncIPC.togglePlayNotification)
        return .result()
    }
}

/// Nudges the playback synchronization backward by 50ms from the Dynamic Island or Lock Screen.
public struct NudgeBackwardIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Nudge Sync -50ms"
    public static var description = IntentDescription("Shifts playback 50 milliseconds earlier to fine-tune phase lock.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        ShazamSyncIPC.postDarwinNotification(ShazamSyncIPC.nudgeMinusNotification)
        return .result()
    }
}

/// Nudges the playback synchronization forward by 50ms from the Dynamic Island or Lock Screen.
public struct NudgeForwardIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Nudge Sync +50ms"
    public static var description = IntentDescription("Shifts playback 50 milliseconds later to fine-tune phase lock.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        ShazamSyncIPC.postDarwinNotification(ShazamSyncIPC.nudgePlusNotification)
        return .result()
    }
}

/// Triggers an immediate ambient re-listen and acoustic re-sync.
public struct ResyncAmbientIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Re-Sync Ambient Audio"
    public static var description = IntentDescription("Listens to ambient music again and re-aligns playback.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        ShazamSyncIPC.postDarwinNotification(ShazamSyncIPC.resyncNotification)
        return .result()
    }
}

/// Stops synchronized playback and ends the Live Activity.
public struct StopSyncIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Stop ShazamSync"
    public static var description = IntentDescription("Stops playback and ends the current session.")
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        ShazamSyncIPC.postDarwinNotification(ShazamSyncIPC.stopNotification)
        return .result()
    }
}
