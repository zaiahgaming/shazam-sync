import Foundation
import AVFoundation
import ShazamKit
import MediaPlayer
import Observation

/// Core orchestrator for ambient listening, Shazam recognition, stream download,
/// Accelerate vDSP cross-correlation phase locking, synchronized playback, and Live Activities.
@MainActor
@Observable
public final class ShazamSyncEngine {
    public static let shared = ShazamSyncEngine()

    // MARK: - Observable State

    public var phase: SyncPhase = .idle
    public var statusMessage: String = "Tap Sync to listen & lock onto ambient music"
    public var currentTrack: RecognizedTrack?
    public var history: [RecognizedTrack] = []
    public var isAutoLoopEnabled: Bool = true
    public var listenDuration: Double = 6.0
    public var manualNudgeMs: Int = 0
    public var playbackPosition: Double = 0.0
    public var trackDuration: Double = 180.0
    public var audioSourceDescription: String = ""
    public var waveformLevels: [Float] = Array(repeating: 0.08, count: 28)
    public var companionServerURL: String = UserDefaults.standard.string(forKey: "companionServerURL") ?? "" {
        didSet {
            UserDefaults.standard.set(companionServerURL, forKey: "companionServerURL")
        }
    }

    // MARK: - Private Audio & Session Properties

    private let managedSession = SHManagedSession()
    private var audioEngine: AVAudioEngine?
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var activeTask: Task<Void, Never>?

    private var capturedSamples: [Float] = []
    private var captureSampleRate: Double = 44100.0

    private init() {
        setupRemoteTransportControls()
        registerDarwinIntentObservers()
    }

    // MARK: - Public Actions

    public func toggleSession() {
        if phase == .idle {
            startAutoSyncSession()
        } else {
            stopSession()
        }
    }

    public func startAutoSyncSession() {
        activeTask?.cancel()
        activeTask = Task {
            await runSyncLoop()
        }
    }

    public func stopSession() {
        activeTask?.cancel()
        activeTask = nil
        managedSession.cancel()
        stopAudioEngine()
        stopPlayer()
        phase = .idle
        statusMessage = "Session stopped"
        waveformLevels = Array(repeating: 0.08, count: 28)
        LiveActivityManager.shared.endAll(immediate: false)
    }

    public func togglePlayPause() {
        guard let player else {
            if phase == .idle {
                startAutoSyncSession()
            }
            return
        }

        if phase == .playing {
            player.pause()
            phase = .paused
            statusMessage = "Playback paused"
        } else if phase == .paused {
            player.play()
            phase = .playing
            statusMessage = "Synced & playing"
        }
        syncLiveActivity()
        updateNowPlayingInfo()
    }

    /// Nudges active playback by `deltaMs` milliseconds (e.g. -50 or +50) in real time.
    public func nudgeSync(byMilliseconds deltaMs: Int) {
        manualNudgeMs += deltaMs
        guard let player else { return }

        let currentSeconds = CMTimeGetSeconds(player.currentTime())
        guard currentSeconds.isFinite else { return }

        let newTarget = max(0, currentSeconds + (Double(deltaMs) / 1000.0))
        let targetCM = CMTime(seconds: newTarget, preferredTimescale: 1000)
        player.seek(to: targetCM, toleranceBefore: .zero, toleranceAfter: .zero)
        playbackPosition = newTarget

        if var track = currentTrack {
            track.driftMs += deltaMs
            currentTrack = track
        }

        syncLiveActivity()
        updateNowPlayingInfo()
    }

    public func triggerImmediateResync() {
        stopPlayer()
        startAutoSyncSession()
    }

    // MARK: - Main Auto-Find & Sync Pipeline

    private func runSyncLoop() async {
        let granted = await requestMicrophonePermission()
        guard granted else {
            phase = .idle
            statusMessage = "Microphone access is required to hear ambient music."
            return
        }

        while !Task.isCancelled {
            let matchedAndPlayed = await performSingleSyncCycle()
            if Task.isCancelled { break }

            if matchedAndPlayed {
                if !isAutoLoopEnabled {
                    phase = .idle
                    statusMessage = "Track finished."
                    LiveActivityManager.shared.endAll(immediate: false)
                    break
                } else {
                    statusMessage = "Listening for next song..."
                    try? await Task.sleep(for: .seconds(1.5))
                }
            } else {
                // Keep listening smoothly when silence or no match occurs
                try? await Task.sleep(for: .milliseconds(600))
            }
        }
    }

    private func performSingleSyncCycle() async -> Bool {
        configureAudioSessionForListening()

        phase = .listening
        statusMessage = "Listening to ambient music (\(String(format: "%.0fs", listenDuration)))..."
        LiveActivityManager.shared.startOrUpdate(
            phase: .listening,
            songTitle: "Listening Around You...",
            artistName: "Detecting ambient music",
            isAutoLoopEnabled: isAutoLoopEnabled
        )

        let recordingStartTime = Date.now
        startAmbientMeterAndCapture()

        phase = .matching
        let recognized = await recognizeCurrentAmbientAudio(startedAt: recordingStartTime)
        stopAudioEngine()

        guard !Task.isCancelled else { return false }

        // STRICT UNKNOWN FILTERING: Never download or play nil/Unknown tracks
        guard var track = recognized else {
            statusMessage = "No song recognized in chunk — still listening..."
            return false
        }

        currentTrack = track
        phase = .downloading
        statusMessage = "Found \"\(track.title)\" — acquiring audio..."
        LiveActivityManager.shared.startOrUpdate(
            phase: .downloading,
            songTitle: track.title,
            artistName: track.artist,
            albumArtURL: track.albumArtURL?.absoluteString,
            currentOffset: track.shazamOffset,
            isAutoLoopEnabled: isAutoLoopEnabled
        )

        // Acquire Track (On-Device Cache -> Companion Server -> Full Stream -> Apple Music Stream)
        guard let acquired = try? await TrackAcquisitionService.shared.acquireTrack(
            for: track,
            companionServerURL: companionServerURL
        ) else {
            statusMessage = "Could not download stream for \"\(track.title)\". Retrying..."
            return false
        }

        guard !Task.isCancelled else { return false }

        track.localFileURL = acquired.fileURL
        track.duration = acquired.duration
        trackDuration = acquired.duration
        audioSourceDescription = acquired.sourceDescription

        // Dual-Stage Phase Lock: Accelerate vDSP Cross-Correlation
        phase = .syncing
        statusMessage = "Phase-locking waveform with Accelerate vDSP..."
        LiveActivityManager.shared.startOrUpdate(
            phase: .syncing,
            songTitle: track.title,
            artistName: track.artist,
            albumArtURL: track.albumArtURL?.absoluteString,
            currentOffset: track.shazamOffset,
            songDuration: track.duration,
            isAutoLoopEnabled: isAutoLoopEnabled
        )

        let alignment = await AcousticCrossCorrelator.align(
            micSamples: capturedSamples,
            micSampleRate: captureSampleRate,
            trackFileURL: acquired.fileURL,
            roughOffset: track.shazamOffset
        )

        track.alignedOffset = alignment.alignedOffset
        track.driftMs = alignment.driftMs + manualNudgeMs
        currentTrack = track
        prependToHistory(track)

        // Calculate exact current playback target accounting for elapsed time + hardware output latency
        configureAudioSessionForPlayback()
        let hardwareOutputLatency = AVAudioSession.sharedInstance().outputLatency
        let elapsedSinceStart = Date.now.timeIntervalSince(recordingStartTime)
        let manualNudgeSeconds = Double(manualNudgeMs) / 1000.0
        let targetSeek = track.alignedOffset + elapsedSinceStart + hardwareOutputLatency + manualNudgeSeconds

        guard targetSeek < track.duration else {
            statusMessage = "\"\(track.title)\" just ended — listening for next track..."
            return false
        }

        // Launch Synchronized Playback and await completion
        await playSynchronized(track: track, fileURL: acquired.fileURL, startAtSeconds: targetSeek)
        return true
    }

    // MARK: - ShazamKit + Companion Recognition

    private func recognizeCurrentAmbientAudio(startedAt: Date) async -> RecognizedTrack? {
        // Prepare SHManagedSession and race with listenDuration
        await managedSession.prepare()
        let result = await managedSession.result()

        switch result {
        case .match(let match):
            if let item = match.mediaItems.first {
                // Use predictedCurrentMatchOffset and back-project to recording start time
                let elapsed = Date.now.timeIntervalSince(startedAt)
                let predictedNow = item.predictedCurrentMatchOffset
                let baseOffset = max(0, predictedNow > 0 ? (predictedNow - elapsed) : item.matchOffset)

                if let validTrack = RecognizedTrack(
                    id: item.shazamID ?? UUID().uuidString,
                    title: item.title,
                    artist: item.artist,
                    albumArtURL: item.artworkURL,
                    appleMusicURL: item.appleMusicURL,
                    shazamOffset: baseOffset,
                    recordingStartedAt: startedAt
                ) {
                    return validTrack
                }
            }
        case .noMatch:
            break
        case .error:
            break
        @unknown default:
            break
        }

        // Fallback: If companion server is configured, send captured audio buffer for shazamio recognition
        if !companionServerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let fallbackTrack = await recognizeViaCompanionServer(startedAt: startedAt) {
                return fallbackTrack
            }
        }

        return nil
    }

    private struct CompanionRecognizeResponse: Decodable {
        let matched: Bool
        let title: String?
        let artist: String?
        let offset: Double?
        let trackId: String?
    }

    private func recognizeViaCompanionServer(startedAt: Date) async -> RecognizedTrack? {
        // Ensure we have at least 4 seconds of captured audio
        if capturedSamples.count < Int(captureSampleRate * 3.5) {
            try? await Task.sleep(for: .seconds(listenDuration))
        }
        guard !capturedSamples.isEmpty else { return nil }

        var base = companionServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.hasPrefix("http://") && !base.hasPrefix("https://") {
            base = "http://\(base)"
        }
        if base.hasSuffix("/") { base.removeLast() }

        guard let url = URL(string: "\(base)/recognize") else { return nil }
        guard let wavData = encodeWAVData(samples: capturedSamples, sampleRate: Int(captureSampleRate)) else {
            return nil
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 12

        guard let (data, resp) = try? await URLSession.shared.upload(for: req, from: wavData),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(CompanionRecognizeResponse.self, from: data),
              decoded.matched else {
            return nil
        }

        return RecognizedTrack(
            id: decoded.trackId ?? UUID().uuidString,
            title: decoded.title,
            artist: decoded.artist,
            shazamOffset: decoded.offset ?? 0,
            recordingStartedAt: startedAt
        )
    }

    // MARK: - Synchronized AVPlayer Execution

    private func playSynchronized(
        track: RecognizedTrack,
        fileURL: URL,
        startAtSeconds: TimeInterval
    ) async {
        stopPlayer()

        let item = AVPlayerItem(url: fileURL)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.automaticallyWaitsToMinimizeStalling = false
        self.player = newPlayer

        let targetCM = CMTime(seconds: startAtSeconds, preferredTimescale: 1000)
        await newPlayer.seek(to: targetCM, toleranceBefore: .zero, toleranceAfter: .zero)

        newPlayer.play()
        phase = .playing
        playbackPosition = startAtSeconds
        statusMessage = "Synced at \( formatSeconds(startAtSeconds) ) (\(String(format: "%+dms", track.driftMs)))"

        LiveActivityManager.shared.startOrUpdate(
            phase: .playing,
            songTitle: track.title,
            artistName: track.artist,
            albumArtURL: track.albumArtURL?.absoluteString,
            currentOffset: startAtSeconds,
            songDuration: track.duration,
            syncDriftMs: track.driftMs,
            isAutoLoopEnabled: isAutoLoopEnabled,
            alertOnMatch: true
        )
        updateNowPlayingInfo()

        // Periodic UI observer
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] cmTime in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let secs = CMTimeGetSeconds(cmTime)
                if secs.isFinite {
                    self.playbackPosition = secs
                }
                if self.phase == .playing {
                    self.animatePlaybackWaveform()
                }
            }
        }

        // Wait until track ends or session is cancelled
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var resumed = false
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { _ in
                if !resumed {
                    resumed = true
                    continuation.resume()
                }
            }
        }
    }

    private func stopPlayer() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        player?.pause()
        player = nil
    }

    // MARK: - Ambient Audio Capture & Metering

    private func startAmbientMeterAndCapture() {
        stopAudioEngine()
        capturedSamples.removeAll(keepingCapacity: true)

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }
        captureSampleRate = format.sampleRate

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))

            // Compute RMS for live Liquid Glass waveform visualizer
            var rms: Float = 0
            for s in samples { rms += s * s }
            rms = sqrt(rms / Float(max(1, frameLength)))
            let normalizedLevel = min(1.0, max(0.06, rms * 6.5))

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.capturedSamples.append(contentsOf: samples)
                self.pushWaveformLevel(normalizedLevel)
            }
        }

        do {
            try engine.start()
            self.audioEngine = engine
        } catch {
            // SHManagedSession may manage audio input directly
        }
    }

    private func stopAudioEngine() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
    }

    private func pushWaveformLevel(_ level: Float) {
        var next = waveformLevels
        if !next.isEmpty {
            next.removeFirst()
        }
        next.append(level)
        waveformLevels = next
    }

    private func animatePlaybackWaveform() {
        var next = waveformLevels
        if !next.isEmpty {
            next.removeFirst()
        }
        let synthetic = Float.random(in: 0.25...0.92)
        next.append(synthetic)
        waveformLevels = next
    }

    // MARK: - Audio Session & Permissions

    private func requestMicrophonePermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    private func configureAudioSessionForListening() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.defaultToSpeaker, .allowBluetoothHFP, .allowAirPlay, .mixWithOthers]
        )
        try? session.setActive(true)
    }

    private func configureAudioSessionForPlayback() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            .playback,
            mode: .default,
            options: [.allowAirPlay]
        )
        try? session.setActive(true)
    }

    // MARK: - Lock Screen Now Playing & Remote Command Center

    private func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.triggerImmediateResync() }
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyPlaybackDuration: track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: playbackPosition,
            MPNowPlayingInfoPropertyPlaybackRate: phase == .playing ? 1.0 : 0.0
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func syncLiveActivity() {
        guard let track = currentTrack else { return }
        LiveActivityManager.shared.startOrUpdate(
            phase: phase,
            songTitle: track.title,
            artistName: track.artist,
            albumArtURL: track.albumArtURL?.absoluteString,
            currentOffset: playbackPosition,
            songDuration: track.duration,
            syncDriftMs: track.driftMs,
            isAutoLoopEnabled: isAutoLoopEnabled
        )
    }

    // MARK: - Darwin Notification Observers (from Dynamic Island / Lock Screen LiveActivityIntents)

    private func registerDarwinIntentObservers() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()

        let register: (String) -> Void = { name in
            CFNotificationCenterAddObserver(
                center,
                Unmanaged.passUnretained(self).toOpaque(),
                { _, _, cfName, _, _ in
                    guard let rawName = cfName?.rawValue as String? else { return }
                    Task { @MainActor in
                        ShazamSyncEngine.shared.handleDarwinNotification(rawName)
                    }
                },
                name as CFString,
                nil,
                .deliverImmediately
            )
        }

        register(ShazamSyncIPC.togglePlayNotification)
        register(ShazamSyncIPC.nudgeMinusNotification)
        register(ShazamSyncIPC.nudgePlusNotification)
        register(ShazamSyncIPC.resyncNotification)
        register(ShazamSyncIPC.stopNotification)
    }

    private func handleDarwinNotification(_ name: String) {
        switch name {
        case ShazamSyncIPC.togglePlayNotification:
            togglePlayPause()
        case ShazamSyncIPC.nudgeMinusNotification:
            nudgeSync(byMilliseconds: -50)
        case ShazamSyncIPC.nudgePlusNotification:
            nudgeSync(byMilliseconds: 50)
        case ShazamSyncIPC.resyncNotification:
            triggerImmediateResync()
        case ShazamSyncIPC.stopNotification:
            stopSession()
        default:
            break
        }
    }

    // MARK: - Helpers

    private func prependToHistory(_ track: RecognizedTrack) {
        history.removeAll { $0.cacheKey == track.cacheKey }
        history.insert(track, at: 0)
        if history.count > 30 {
            history.removeLast()
        }
    }

    public func formatSeconds(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let tenths = Int((seconds - floor(seconds)) * 10)
        return String(format: "%d:%02d.%d", mins, secs, tenths)
    }

    private func encodeWAVData(samples: [Float], sampleRate: Int) -> Data? {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate * Int(numChannels) * Int(bitsPerSample / 8))
        let blockAlign = numChannels * (bitsPerSample / 8)
        let dataSize = UInt32(samples.count * 2)
        let chunkSize = 36 + dataSize

        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        data.append(withUnsafeBytes(of: chunkSize.littleEndian) { Data($0) })
        data.append(contentsOf: "WAVEfmt ".utf8)
        data.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: numChannels.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        data.append(contentsOf: "data".utf8)
        data.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })

        var int16Samples = samples.map { s -> Int16 in
            let clamped = max(-1.0, min(1.0, s))
            return Int16(clamped * 32767.0).littleEndian
        }
        int16Samples.withUnsafeBufferPointer { ptr in
            data.append(UnsafeBufferPointer(
                start: UnsafeRawPointer(ptr.baseAddress)?.assumingMemoryBound(to: UInt8.self),
                count: samples.count * 2
            ))
        }
        return data
    }
}
