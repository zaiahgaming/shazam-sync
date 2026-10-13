import Foundation
import AVFoundation

/// Acquires and caches audio tracks for recognized songs.
/// Supports local disk cache, LAN shazam-sync companion server, Piped/Invidious full audio streams, and iTunes M4A streams.
public actor TrackAcquisitionService {
    public static let shared = TrackAcquisitionService()

    public struct AcquiredAudio: Sendable {
        public let fileURL: URL
        public let duration: TimeInterval
        public let sourceDescription: String
    }

    private let cacheDirectory: URL

    private let pipedInstances: [String] = [
        "https://pipedapi.kavin.rocks",
        "https://pipedapi.tokhmi.xyz",
        "https://pipedapi.moomoo.me"
    ]

    public init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.cacheDirectory = docs.appendingPathComponent("TrackCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
    }

    public func cachedFiles() -> [URL] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return urls
    }

    public func clearCache() {
        for url in cachedFiles() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    public func acquireTrack(
        for track: RecognizedTrack,
        companionServerURL: String? = nil
    ) async throws -> AcquiredAudio {
        let safeFilename = track.cacheKey.isEmpty ? track.id : track.cacheKey

        // 1. Check Local On-Device Cache
        for ext in ["m4a", "mp3", "opus", "wav"] {
            let candidate = cacheDirectory.appendingPathComponent("\(safeFilename).\(ext)")
            if FileManager.default.fileExists(atPath: candidate.path),
               let attrs = try? FileManager.default.attributesOfItem(atPath: candidate.path),
               let size = attrs[.size] as? UInt64, size > 25_000 {
                let dur = await probeDuration(of: candidate)
                return AcquiredAudio(fileURL: candidate, duration: dur, sourceDescription: "On-Device Cache")
            }
        }

        // 2. Try LAN Companion Server (if configured)
        if let base = companionServerURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           !base.isEmpty,
           let acquired = try? await fetchFromCompanionServer(base: base, track: track, safeFilename: safeFilename) {
            return acquired
        }

        // 3. Try Standalone Full Audio Stream via Piped API
        if let acquired = try? await fetchFromPipedStream(track: track, safeFilename: safeFilename) {
            return acquired
        }

        // 4. Fallback to iTunes High-Bitrate M4A Audio Stream
        if let acquired = try? await fetchFromITunesCatalog(track: track, safeFilename: safeFilename) {
            return acquired
        }

        throw URLError(.cannotLoadFromNetwork)
    }

    // MARK: - Companion Server Acquisition

    private func fetchFromCompanionServer(
        base: String,
        track: RecognizedTrack,
        safeFilename: String
    ) async throws -> AcquiredAudio {
        var normalizedBase = base
        if !normalizedBase.hasPrefix("http://") && !normalizedBase.hasPrefix("https://") {
            normalizedBase = "http://\(normalizedBase)"
        }
        if normalizedBase.hasSuffix("/") {
            normalizedBase.removeLast()
        }

        var comps = URLComponents(string: "\(normalizedBase)/acquire")
        comps?.queryItems = [
            URLQueryItem(name: "title", value: track.title),
            URLQueryItem(name: "artist", value: track.artist)
        ]
        guard let url = comps?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20

        let (tempURL, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let ext = http.mimeType?.contains("mpeg") == true ? "mp3" : "m4a"
        let dest = cacheDirectory.appendingPathComponent("\(safeFilename).\(ext)")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tempURL, to: dest)

        let dur = await probeDuration(of: dest)
        return AcquiredAudio(fileURL: dest, duration: dur, sourceDescription: "LAN Companion Server")
    }

    // MARK: - Standalone Piped Full Audio Stream

    private struct PipedSearchResponse: Decodable {
        struct Item: Decodable {
            let url: String?
            let title: String?
            let duration: Int?
        }
        let items: [Item]?
    }

    private struct PipedStreamsResponse: Decodable {
        struct AudioStream: Decodable {
            let url: String?
            let mimeType: String?
            let bitrate: Int?
        }
        let audioStreams: [AudioStream]?
        let duration: Double?
    }

    private func fetchFromPipedStream(
        track: RecognizedTrack,
        safeFilename: String
    ) async throws -> AcquiredAudio {
        let query = "\(track.title) \(track.artist) official audio"

        for instance in pipedInstances {
            guard var searchComps = URLComponents(string: "\(instance)/search") else { continue }
            searchComps.queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "filter", value: "music_songs")
            ]
            guard let searchURL = searchComps.url else { continue }

            var searchReq = URLRequest(url: searchURL)
            searchReq.timeoutInterval = 6

            guard let (searchData, searchResp) = try? await URLSession.shared.data(for: searchReq),
                  let http = searchResp as? HTTPURLResponse, http.statusCode == 200,
                  let decoded = try? JSONDecoder().decode(PipedSearchResponse.self, from: searchData),
                  let firstItem = decoded.items?.first,
                  let videoPath = firstItem.url else {
                continue
            }

            let videoID = videoPath.replacingOccurrences(of: "/watch?v=", with: "")
            guard let streamsURL = URL(string: "\(instance)/streams/\(videoID)") else { continue }

            var streamReq = URLRequest(url: streamsURL)
            streamReq.timeoutInterval = 6

            guard let (streamData, streamResp) = try? await URLSession.shared.data(for: streamReq),
                  let streamHttp = streamResp as? HTTPURLResponse, streamHttp.statusCode == 200,
                  let streamDecoded = try? JSONDecoder().decode(PipedStreamsResponse.self, from: streamData),
                  let audioStreams = streamDecoded.audioStreams else {
                continue
            }

            // Prefer mp4/m4a streams for native iOS AVFoundation hardware decoding
            let preferredStream = audioStreams
                .filter { ($0.mimeType ?? "").contains("mp4") || ($0.mimeType ?? "").contains("m4a") }
                .sorted { ($0.bitrate ?? 0) > ($1.bitrate ?? 0) }
                .first ?? audioStreams.first

            guard let audioURLString = preferredStream?.url,
                  let audioURL = URL(string: audioURLString) else {
                continue
            }

            let (tempFile, dlResp) = try await URLSession.shared.download(from: audioURL)
            guard let dlHttp = dlResp as? HTTPURLResponse, (200...299).contains(dlHttp.statusCode) else {
                continue
            }

            let dest = cacheDirectory.appendingPathComponent("\(safeFilename).m4a")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tempFile, to: dest)

            let dur = await probeDuration(of: dest)
            return AcquiredAudio(
                fileURL: dest,
                duration: dur > 1 ? dur : (streamDecoded.duration ?? 180),
                sourceDescription: "Full Audio Stream"
            )
        }

        throw URLError(.cannotFindHost)
    }

    // MARK: - iTunes Catalog Stream

    private struct ITunesSearchResponse: Decodable {
        struct ResultItem: Decodable {
            let trackName: String?
            let artistName: String?
            let previewUrl: String?
            let artworkUrl100: String?
            let trackTimeMillis: Int?
        }
        let results: [ResultItem]
    }

    private func fetchFromITunesCatalog(
        track: RecognizedTrack,
        safeFilename: String
    ) async throws -> AcquiredAudio {
        var comps = URLComponents(string: "https://itunes.apple.com/search")
        comps?.queryItems = [
            URLQueryItem(name: "term", value: "\(track.title) \(track.artist)"),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "3")
        ]
        guard let url = comps?.url else { throw URLError(.badURL) }

        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
        guard let item = decoded.results.first(where: { $0.previewUrl != nil }),
              let previewStr = item.previewUrl,
              let previewURL = URL(string: previewStr) else {
            throw URLError(.resourceUnavailable)
        }

        let (tempFile, _) = try await URLSession.shared.download(from: previewURL)
        let dest = cacheDirectory.appendingPathComponent("\(safeFilename).m4a")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tempFile, to: dest)

        let dur = await probeDuration(of: dest)
        return AcquiredAudio(fileURL: dest, duration: dur, sourceDescription: "Apple Music Stream")
    }

    private func probeDuration(of fileURL: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: fileURL)
        if let cmDur = try? await asset.load(.duration) {
            let secs = CMTimeGetSeconds(cmDur)
            if secs.isFinite && secs > 0 {
                return secs
            }
        }
        return 180.0
    }
}
