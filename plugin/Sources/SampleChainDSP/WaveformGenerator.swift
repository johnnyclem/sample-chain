// WaveformGenerator.swift
// SampleChainDSP
//
// Generates waveform peak data from audio buffers for visualization.
// Produces downsampled peak arrays suitable for rendering in WaveformView.

import Accelerate
import AVFoundation
import Foundation
import SampleChainCore

// MARK: - Waveform Generator Configuration

/// Configuration for waveform generation.
public struct WaveformGeneratorConfiguration: Sendable {
    /// Number of peak data points to generate.
    /// Corresponds to the number of display columns in the waveform view.
    public let targetPointCount: Int
    /// Whether to compute RMS values in addition to peaks (useful for filled waveforms).
    public let computeRMS: Bool

    public static let thumbnail = WaveformGeneratorConfiguration(
        targetPointCount: 100,
        computeRMS: false
    )

    public static let standard = WaveformGeneratorConfiguration(
        targetPointCount: 800,
        computeRMS: true
    )

    public static let detailed = WaveformGeneratorConfiguration(
        targetPointCount: 2000,
        computeRMS: true
    )

    public init(targetPointCount: Int = 800, computeRMS: Bool = true) {
        self.targetPointCount = targetPointCount
        self.computeRMS = computeRMS
    }
}

// MARK: - Detailed Waveform Data

/// Extended waveform data with both peak and RMS values for high-quality rendering.
public struct DetailedWaveformData: Sendable {
    /// Maximum absolute peak amplitude per column, normalized to [0, 1].
    public let peaks: [Float]
    /// Minimum sample value per column (for mirrored waveform display), normalized to [-1, 1].
    public let minPeaks: [Float]
    /// Maximum sample value per column, normalized to [-1, 1].
    public let maxPeaks: [Float]
    /// RMS (root mean square) amplitude per column, normalized to [0, 1]. Empty if RMS was not computed.
    public let rmsValues: [Float]
    /// Duration of the source audio in seconds.
    public let durationSeconds: Double
    /// Sample rate of the source audio.
    public let sampleRate: Double
    /// Number of source samples per waveform column.
    public let samplesPerColumn: Int

    public init(
        peaks: [Float],
        minPeaks: [Float],
        maxPeaks: [Float],
        rmsValues: [Float],
        durationSeconds: Double,
        sampleRate: Double,
        samplesPerColumn: Int
    ) {
        self.peaks = peaks
        self.minPeaks = minPeaks
        self.maxPeaks = maxPeaks
        self.rmsValues = rmsValues
        self.durationSeconds = durationSeconds
        self.sampleRate = sampleRate
        self.samplesPerColumn = samplesPerColumn
    }

    /// Convert to the simpler ``WaveformData`` model used in the ``Sample`` type.
    public func toWaveformData() -> WaveformData {
        WaveformData(peaks: peaks, durationSeconds: durationSeconds, sampleRate: sampleRate)
    }
}

// MARK: - Waveform Generator

/// Generates waveform visualization data from audio files or buffers.
///
/// Uses the Accelerate framework (vDSP) for efficient downsampling of audio data
/// into peak and RMS arrays suitable for rendering.
///
/// Usage:
/// ```swift
/// let generator = WaveformGenerator()
/// let waveform = try await generator.generate(from: audioFileURL, configuration: .standard)
/// // Use waveform.peaks for rendering in WaveformView
/// ```
public final class WaveformGenerator: Sendable {
    public init() {}

    /// Generate waveform data from an audio file URL.
    ///
    /// - Parameters:
    ///   - fileURL: URL of the audio file.
    ///   - configuration: Waveform generation settings.
    /// - Returns: Detailed waveform data for visualization.
    /// - Throws: If the file cannot be read.
    public func generate(
        from fileURL: URL,
        configuration: WaveformGeneratorConfiguration = .standard
    ) async throws -> DetailedWaveformData {
        return try await Task.detached(priority: .userInitiated) { [self] in
            let audioFile = try AVAudioFile(forReading: fileURL)
            let frameCount = AVAudioFrameCount(audioFile.length)
            let sampleRate = audioFile.processingFormat.sampleRate

            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: audioFile.processingFormat,
                frameCapacity: frameCount
            ) else {
                throw WaveformError.bufferCreationFailed
            }
            try audioFile.read(into: buffer)

            return self.generateFromBuffer(
                buffer: buffer,
                sampleRate: sampleRate,
                configuration: configuration
            )
        }.value
    }

    /// Generate waveform data from an AVAudioPCMBuffer.
    ///
    /// - Parameters:
    ///   - buffer: The audio buffer containing sample data.
    ///   - sampleRate: The sample rate of the audio.
    ///   - configuration: Waveform generation settings.
    /// - Returns: Detailed waveform data for visualization.
    public func generateFromBuffer(
        buffer: AVAudioPCMBuffer,
        sampleRate: Double,
        configuration: WaveformGeneratorConfiguration = .standard
    ) -> DetailedWaveformData {
        guard let channelData = buffer.floatChannelData else {
            return emptyWaveform(sampleRate: sampleRate)
        }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        guard frameLength > 0 else {
            return emptyWaveform(sampleRate: sampleRate)
        }

        // Mix to mono for waveform calculation
        let monoSamples: [Float]
        if channelCount == 1 {
            monoSamples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        } else {
            var mono = [Float](repeating: 0, count: frameLength)
            for ch in 0..<channelCount {
                vDSP_vadd(mono, 1, channelData[ch], 1, &mono, 1, vDSP_Length(frameLength))
            }
            var divisor = Float(channelCount)
            vDSP_vsdiv(mono, 1, &divisor, &mono, 1, vDSP_Length(frameLength))
            monoSamples = mono
        }

        let targetCount = min(configuration.targetPointCount, frameLength)
        let samplesPerColumn = frameLength / targetCount
        let durationSeconds = Double(frameLength) / sampleRate

        guard samplesPerColumn > 0 else {
            return emptyWaveform(sampleRate: sampleRate)
        }

        // Compute peaks using vDSP
        var peaks = [Float](repeating: 0, count: targetCount)
        var minPeaks = [Float](repeating: 0, count: targetCount)
        var maxPeaks = [Float](repeating: 0, count: targetCount)
        var rmsValues = [Float](repeating: 0, count: configuration.computeRMS ? targetCount : 0)

        monoSamples.withUnsafeBufferPointer { samplesPtr in
            guard let baseAddress = samplesPtr.baseAddress else { return }

            for i in 0..<targetCount {
                let startIndex = i * samplesPerColumn
                let count = min(samplesPerColumn, frameLength - startIndex)
                guard count > 0 else { continue }

                let blockPtr = baseAddress.advanced(by: startIndex)

                // Maximum absolute value (peak)
                var absPeak: Float = 0
                vDSP_maxmgv(blockPtr, 1, &absPeak, vDSP_Length(count))
                peaks[i] = absPeak

                // Minimum value in the block
                var minVal: Float = 0
                vDSP_minv(blockPtr, 1, &minVal, vDSP_Length(count))
                minPeaks[i] = minVal

                // Maximum value in the block
                var maxVal: Float = 0
                vDSP_maxv(blockPtr, 1, &maxVal, vDSP_Length(count))
                maxPeaks[i] = maxVal

                // RMS
                if configuration.computeRMS {
                    var rms: Float = 0
                    vDSP_rmsqv(blockPtr, 1, &rms, vDSP_Length(count))
                    rmsValues[i] = rms
                }
            }
        }

        // Normalize peaks to [0, 1]
        var globalPeak: Float = 0
        vDSP_maxv(peaks, 1, &globalPeak, vDSP_Length(targetCount))

        if globalPeak > 0 {
            var scale = 1.0 / globalPeak
            vDSP_vsmul(peaks, 1, &scale, &peaks, 1, vDSP_Length(targetCount))
            vDSP_vsmul(minPeaks, 1, &scale, &minPeaks, 1, vDSP_Length(targetCount))
            vDSP_vsmul(maxPeaks, 1, &scale, &maxPeaks, 1, vDSP_Length(targetCount))

            if configuration.computeRMS {
                vDSP_vsmul(rmsValues, 1, &scale, &rmsValues, 1, vDSP_Length(targetCount))
            }
        }

        return DetailedWaveformData(
            peaks: peaks,
            minPeaks: minPeaks,
            maxPeaks: maxPeaks,
            rmsValues: rmsValues,
            durationSeconds: durationSeconds,
            sampleRate: sampleRate,
            samplesPerColumn: samplesPerColumn
        )
    }

    /// Generate waveform data from raw float samples.
    ///
    /// - Parameters:
    ///   - samples: Array of mono float samples.
    ///   - sampleRate: The sample rate.
    ///   - configuration: Waveform generation settings.
    /// - Returns: Simple ``WaveformData`` for the ``Sample`` model.
    public func generateSimple(
        from samples: [Float],
        sampleRate: Double,
        configuration: WaveformGeneratorConfiguration = .thumbnail
    ) -> WaveformData {
        guard !samples.isEmpty else {
            return WaveformData(peaks: [], durationSeconds: 0, sampleRate: sampleRate)
        }

        let targetCount = min(configuration.targetPointCount, samples.count)
        let samplesPerColumn = samples.count / targetCount
        let durationSeconds = Double(samples.count) / sampleRate

        guard samplesPerColumn > 0 else {
            return WaveformData(peaks: [], durationSeconds: 0, sampleRate: sampleRate)
        }

        var peaks = [Float](repeating: 0, count: targetCount)

        samples.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            for i in 0..<targetCount {
                let startIndex = i * samplesPerColumn
                let count = min(samplesPerColumn, samples.count - startIndex)
                guard count > 0 else { continue }
                var peak: Float = 0
                vDSP_maxmgv(base.advanced(by: startIndex), 1, &peak, vDSP_Length(count))
                peaks[i] = peak
            }
        }

        // Normalize
        var globalPeak: Float = 0
        vDSP_maxv(peaks, 1, &globalPeak, vDSP_Length(targetCount))
        if globalPeak > 0 {
            var scale = 1.0 / globalPeak
            vDSP_vsmul(peaks, 1, &scale, &peaks, 1, vDSP_Length(targetCount))
        }

        return WaveformData(peaks: peaks, durationSeconds: durationSeconds, sampleRate: sampleRate)
    }

    // MARK: - Private

    private func emptyWaveform(sampleRate: Double) -> DetailedWaveformData {
        DetailedWaveformData(
            peaks: [],
            minPeaks: [],
            maxPeaks: [],
            rmsValues: [],
            durationSeconds: 0,
            sampleRate: sampleRate,
            samplesPerColumn: 0
        )
    }
}

// MARK: - Waveform Error

/// Errors from waveform generation.
public enum WaveformError: Error, LocalizedError {
    case bufferCreationFailed
    case invalidAudioFormat

    public var errorDescription: String? {
        switch self {
        case .bufferCreationFailed:
            return "Failed to create audio buffer for waveform generation."
        case .invalidAudioFormat:
            return "Audio format is not supported for waveform generation."
        }
    }
}
