import Foundation
import ActivityKit
import SwiftUI

/// Represents the current pipeline state of ShazamSync.
public enum SyncPhase: String, Codable, Hashable, Sendable {
    case idle = "Idle"
    case listening = "Listening"
    case matching = "Identifying"
    case downloading = "Downloading"
    case syncing = "Phase Locking"
    case playing = "Synced & Playing"
    case paused = "Paused"

    public var symbolName: String {
        switch self {
        case .idle: return "waveform.circle"
        case .listening: return "mic.and.signal.meter.fill"
        case .matching: return "shazam.logo.fill"
        case .downloading: return "arrow.down.circle.fill"
        case .syncing: return "scope"
        case .playing: return "waveform.badge.checkmark"
        case .paused: return "pause.circle.fill"
        }
    }

    public var shortLabel: String {
        switch self {
        case .idle: return "Ready"
        case .listening: return "Listening"
        case .matching: return "Matching"
        case .downloading: return "Fetching"
        case .syncing: return "Syncing"
        case .playing: return "Synced"
        case .paused: return "Paused"
        }
    }
}

/// ActivityAttributes for the Dynamic Island and Lock Screen Live Activity.
public struct ShazamSyncAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var phase: SyncPhase
        public var songTitle: String
        public var artistName: String
        public var albumArtURL: String?
        /// Current playback position in seconds at the time `stateUpdatedAt` was recorded.
        public var currentOffset: Double
        /// Total track duration in seconds.
        public var songDuration: Double
        /// Fine cross-correlation drift adjustment in milliseconds (e.g. -14ms).
        public var syncDriftMs: Int
        /// Timestamp when the current state was anchored, enabling live timer interpolation.
        public var stateUpdatedAt: Date
        /// Whether continuous auto-listen loop mode is active.
        public var isAutoLoopEnabled: Bool

        public init(
            phase: SyncPhase,
            songTitle: String,
            artistName: String,
            albumArtURL: String? = nil,
            currentOffset: Double = 0,
            songDuration: Double = 180,
            syncDriftMs: Int = 0,
            stateUpdatedAt: Date = .now,
            isAutoLoopEnabled: Bool = true
        ) {
            self.phase = phase
            self.songTitle = songTitle
            self.artistName = artistName
            self.albumArtURL = albumArtURL
            self.currentOffset = currentOffset
            self.songDuration = max(1, songDuration)
            self.syncDriftMs = syncDriftMs
            self.stateUpdatedAt = stateUpdatedAt
            self.isAutoLoopEnabled = isAutoLoopEnabled
        }

        /// Computed start date of the song for SwiftUI's live ProgressView(timerInterval:) and Text(timerInterval:)
        public var estimatedSongStartDate: Date {
            stateUpdatedAt.addingTimeInterval(-currentOffset)
        }

        /// Computed end date of the song for SwiftUI's live ProgressView(timerInterval:)
        public var estimatedSongEndDate: Date {
            let remaining = max(1.0, songDuration - currentOffset)
            return stateUpdatedAt.addingTimeInterval(remaining)
        }

        public var timerInterval: ClosedRange<Date> {
            let start = estimatedSongStartDate
            let end = max(start.addingTimeInterval(1), estimatedSongEndDate)
            return start...end
        }
    }

    public var sessionID: String
    public var startedAt: Date

    public init(sessionID: String = UUID().uuidString, startedAt: Date = .now) {
        self.sessionID = sessionID
        self.startedAt = startedAt
    }
}

/// Cross-process IPC constants for LiveActivityIntent actions to communicate with the active app audio engine.
public enum ShazamSyncIPC {
    public static let appGroupSuite = "group.com.zaiah.shazamsync"
    public static let togglePlayNotification = "com.zaiah.shazamsync.togglePlay"
    public static let nudgeMinusNotification = "com.zaiah.shazamsync.nudgeMinus50"
    public static let nudgePlusNotification = "com.zaiah.shazamsync.nudgePlus50"
    public static let resyncNotification = "com.zaiah.shazamsync.resync"
    public static let stopNotification = "com.zaiah.shazamsync.stop"

    public static func postDarwinNotification(_ name: String) {
        let cfName = CFNotificationName(name as CFString)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            cfName,
            nil,
            nil,
            true
        )
    }
}
