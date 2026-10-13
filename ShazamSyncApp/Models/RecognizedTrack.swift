import Foundation

/// Represents a validated, recognized song and its synchronization metadata.
public struct RecognizedTrack: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public let albumArtURL: URL?
    public let appleMusicURL: URL?
    /// Master offset in seconds reported by Shazam at the start of the query recording.
    public let shazamOffset: TimeInterval
    /// Fine-tuned offset in seconds after Accelerate vDSP acoustic cross-correlation.
    public var alignedOffset: TimeInterval
    /// Difference in milliseconds between alignedOffset and shazamOffset.
    public var driftMs: Int
    /// Total track duration in seconds.
    public var duration: TimeInterval
    /// Local cached file URL if downloaded.
    public var localFileURL: URL?
    /// Wall-clock timestamp when the ambient snippet recording started.
    public let recordingStartedAt: Date

    public init?(
        id: String = UUID().uuidString,
        title: String?,
        artist: String?,
        albumArtURL: URL? = nil,
        appleMusicURL: URL? = nil,
        shazamOffset: TimeInterval,
        alignedOffset: TimeInterval? = nil,
        driftMs: Int = 0,
        duration: TimeInterval = 180.0,
        localFileURL: URL? = nil,
        recordingStartedAt: Date = .now
    ) {
        // STRICT VALIDATION: Never allow empty or "Unknown" tracks
        guard let rawTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawTitle.isEmpty,
              !Self.isInvalidPlaceholder(rawTitle) else {
            return nil
        }

        let rawArtist = artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawArtist.isEmpty, !Self.isInvalidPlaceholder(rawArtist) else {
            return nil
        }

        self.id = id
        self.title = rawTitle
        self.artist = rawArtist
        self.albumArtURL = albumArtURL
        self.appleMusicURL = appleMusicURL
        self.shazamOffset = max(0, shazamOffset)
        self.alignedOffset = alignedOffset ?? max(0, shazamOffset)
        self.driftMs = driftMs
        self.duration = max(1, duration)
        self.localFileURL = localFileURL
        self.recordingStartedAt = recordingStartedAt
    }

    public static func isInvalidPlaceholder(_ text: String) -> Bool {
        let lower = text.lowercased()
        let invalidSet: Set<String> = [
            "unknown",
            "unknown artist",
            "unknown title",
            "unknown track",
            "none",
            "null",
            "n/a",
            "untitled"
        ]
        return invalidSet.contains(lower)
    }

    public var cacheKey: String {
        let combined = "\(artist) - \(title)".lowercased()
        return combined.replacingOccurrences(
            of: "[^a-z0-9\\-_ ]",
            with: "",
            options: .regularExpression
        )
    }
}
