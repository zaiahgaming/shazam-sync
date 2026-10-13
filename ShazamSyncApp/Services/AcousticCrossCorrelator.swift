import Foundation
import Accelerate
import AVFoundation

/// Performs hardware-accelerated acoustic cross-correlation using Apple's Accelerate (vDSP) framework
/// to align an ambient microphone recording with a downloaded reference audio track down to the millisecond.
public struct AcousticCrossCorrelator: Sendable {
    public struct AlignmentResult: Sendable {
        public let alignedOffset: TimeInterval
        public let driftMs: Int
        public let confidence: Float
    }

    private static let correlationSampleRate: Double = 8000.0

    /// Aligns `micSamples` (recorded at `micSampleRate`) against `trackFileURL` around `roughOffset`.
    public static func align(
        micSamples: [Float],
        micSampleRate: Double,
        trackFileURL: URL,
        roughOffset: TimeInterval
    ) async -> AlignmentResult {
        guard !micSamples.isEmpty, trackFileURL.isFileURL else {
            return AlignmentResult(alignedOffset: roughOffset, driftMs: 0, confidence: 1.0)
        }

        // Downsample mic buffer to 8000 Hz for fast vDSP cross-correlation
        let targetSR = correlationSampleRate
        let decimationFactor = max(1, Int((micSampleRate / targetSR).rounded()))
        let downsampledMic = stride(from: 0, to: micSamples.count, by: decimationFactor).map { micSamples[$0] }

        guard downsampledMic.count > 400 else {
            return AlignmentResult(alignedOffset: roughOffset, driftMs: 0, confidence: 1.0)
        }

        // Extract reference window [max(0, roughOffset - 6s) ... roughOffset + 12s]
        let windowStart = max(0.0, roughOffset - 6.0)
        let windowDuration: TimeInterval = 18.0

        guard let refSamples = await decodeAudioWindow(
            from: trackFileURL,
            startSeconds: windowStart,
            durationSeconds: windowDuration,
            targetSampleRate: targetSR
        ), refSamples.count > downsampledMic.count + 16 else {
            return AlignmentResult(alignedOffset: roughOffset, driftMs: 0, confidence: 1.0)
        }

        // Compute normalized energy envelopes or zero-mean signals using vDSP
        let cleanMic = normalizeZeroMean(downsampledMic)
        let cleanRef = normalizeZeroMean(refSamples)

        let resultLength = cleanRef.count - cleanMic.count + 1
        guard resultLength > 0 else {
            return AlignmentResult(alignedOffset: roughOffset, driftMs: 0, confidence: 1.0)
        }

        var correlation = [Float](repeating: 0, count: resultLength)
        cleanRef.withUnsafeBufferPointer { refPtr in
            cleanMic.withUnsafeBufferPointer { micPtr in
                guard let refBase = refPtr.baseAddress,
                      let micBase = micPtr.baseAddress else { return }
                // vDSP_conv performs cross-correlation when filter stride is +1
                vDSP_conv(
                    refBase, 1,
                    micBase, 1,
                    &correlation, 1,
                    vDSP_Length(resultLength),
                    vDSP_Length(cleanMic.count)
                )
            }
        }

        var maxVal: Float = 0
        var maxIndex: vDSP_Length = 0
        vDSP_maxvi(correlation, 1, &maxVal, &maxIndex, vDSP_Length(resultLength))

        var meanAbs: Float = 0
        vDSP_meamgv(correlation, 1, &meanAbs, vDSP_Length(resultLength))

        let peakToMean = meanAbs > 1e-6 ? (maxVal / meanAbs) : 0
        if peakToMean > 2.5 {
            let effectiveSR = micSampleRate / Double(decimationFactor)
            let aligned = windowStart + (Double(maxIndex) / effectiveSR)
            let driftMs = Int(((aligned - roughOffset) * 1000.0).rounded())
            return AlignmentResult(
                alignedOffset: aligned,
                driftMs: driftMs,
                confidence: min(1.0, peakToMean / 10.0)
            )
        }

        return AlignmentResult(alignedOffset: roughOffset, driftMs: 0, confidence: 0.5)
    }

    private static func normalizeZeroMean(_ input: [Float]) -> [Float] {
        guard !input.isEmpty else { return input }
        var mean: Float = 0
        vDSP_meanv(input, 1, &mean, vDSP_Length(input.count))
        var negMean = -mean
        var centered = [Float](repeating: 0, count: input.count)
        vDSP_vsadd(input, 1, &negMean, &centered, 1, vDSP_Length(input.count))
        return centered
    }

    private static func decodeAudioWindow(
        from fileURL: URL,
        startSeconds: TimeInterval,
        durationSeconds: TimeInterval,
        targetSampleRate: Double
    ) async -> [Float]? {
        let asset = AVURLAsset(url: fileURL)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else {
            return nil
        }

        guard let reader = try? AVAssetReader(asset: asset) else {
            return nil
        }

        let startCM = CMTime(seconds: startSeconds, preferredTimescale: 600)
        let durationCM = CMTime(seconds: durationSeconds, preferredTimescale: 600)
        reader.timeRange = CMTimeRange(start: startCM, duration: durationCM)

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: targetSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)

        guard reader.startReading() else { return nil }

        var samples: [Float] = []
        samples.reserveCapacity(Int(targetSampleRate * durationSeconds))

        while reader.status == .reading, let sampleBuffer = output.copyNextSampleBuffer() {
            if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                let length = CMBlockBufferGetDataLength(blockBuffer)
                let floatCount = length / MemoryLayout<Float>.size
                var buffer = [Float](repeating: 0, count: floatCount)
                buffer.withUnsafeMutableBytes { rawPtr in
                    if let base = rawPtr.baseAddress {
                        _ = CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: base)
                    }
                }
                samples.append(contentsOf: buffer)
            }
        }

        return samples.isEmpty ? nil : samples
    }
}
