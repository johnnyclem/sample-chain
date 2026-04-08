// BPMDetector.swift
// SampleChainDSP
//
// Onset-detection-based tempo estimation using the Accelerate framework.
// Uses vDSP FFT for spectral analysis and autocorrelation for periodicity detection.
// Valid BPM range: 60-200 BPM.

import Accelerate
import AVFoundation
import Foundation

// MARK: - BPM Detection Result

/// Result of BPM detection analysis.
public struct BPMDetectionResult: Sendable {
    /// Primary detected tempo in BPM.
    public let bpm: Double
    /// Confidence level (0.0 to 1.0) of the primary detection.
    public let confidence: Double
    /// Alternative tempo candidates ranked by confidence.
    public let alternatives: [BPMCandidate]

    public init(bpm: Double, confidence: Double, alternatives: [BPMCandidate] = []) {
        self.bpm = bpm
        self.confidence = confidence
        self.alternatives = alternatives
    }
}

/// A BPM candidate with its confidence score.
public struct BPMCandidate: Sendable {
    public let bpm: Double
    public let confidence: Double

    public init(bpm: Double, confidence: Double) {
        self.bpm = bpm
        self.confidence = confidence
    }
}

// MARK: - BPM Detector Configuration

/// Configuration for BPM detection.
public struct BPMDetectorConfiguration: Sendable {
    /// Minimum detectable BPM.
    public let minBPM: Double
    /// Maximum detectable BPM.
    public let maxBPM: Double
    /// FFT window size (must be a power of 2).
    public let fftSize: Int
    /// Hop size between consecutive FFT frames (in samples).
    public let hopSize: Int
    /// Number of top candidates to return.
    public let maxCandidates: Int

    public static let `default` = BPMDetectorConfiguration(
        minBPM: 60,
        maxBPM: 200,
        fftSize: 2048,
        hopSize: 512,
        maxCandidates: 5
    )

    public init(
        minBPM: Double = 60,
        maxBPM: Double = 200,
        fftSize: Int = 2048,
        hopSize: Int = 512,
        maxCandidates: Int = 5
    ) {
        self.minBPM = minBPM
        self.maxBPM = maxBPM
        self.fftSize = fftSize
        self.hopSize = hopSize
        self.maxCandidates = maxCandidates
    }
}

// MARK: - BPM Detector

/// Detects the tempo (BPM) of an audio file using onset detection and autocorrelation.
///
/// Algorithm overview:
/// 1. Read audio and convert to mono.
/// 2. Compute the Short-Time Fourier Transform (STFT) using vDSP.
/// 3. Calculate the spectral flux onset detection function.
/// 4. Half-wave rectify the onset function to keep only positive changes.
/// 5. Compute the autocorrelation of the onset function.
/// 6. Find peaks in the autocorrelation corresponding to BPM in the valid range.
/// 7. Return the strongest peak as the primary BPM estimate.
///
/// Usage:
/// ```swift
/// let detector = BPMDetector()
/// let result = try await detector.detect(fileURL: sampleURL)
/// print("BPM: \(result.bpm) (confidence: \(result.confidence))")
/// ```
public final class BPMDetector: Sendable {
    private let configuration: BPMDetectorConfiguration

    public init(configuration: BPMDetectorConfiguration = .default) {
        self.configuration = configuration
    }

    /// Detect the tempo of an audio file.
    ///
    /// - Parameter fileURL: URL of the audio file to analyze.
    /// - Returns: The BPM detection result with confidence.
    /// - Throws: If the file cannot be read or processed.
    public func detect(fileURL: URL) async throws -> BPMDetectionResult {
        // Run the analysis on a background thread to avoid blocking
        return try await Task.detached(priority: .userInitiated) { [self] in
            try self.performDetection(fileURL: fileURL)
        }.value
    }

    // MARK: - Core Detection Pipeline

    private func performDetection(fileURL: URL) throws -> BPMDetectionResult {
        // Step 1: Read audio into mono float buffer
        let audioFile = try AVAudioFile(forReading: fileURL)
        let sampleRate = audioFile.processingFormat.sampleRate
        let frameCount = AVAudioFrameCount(audioFile.length)

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: audioFile.processingFormat,
            frameCapacity: frameCount
        ) else {
            throw BPMDetectorError.bufferCreationFailed
        }
        try audioFile.read(into: buffer)

        let monoSamples = convertToMono(buffer: buffer)
        guard monoSamples.count > configuration.fftSize else {
            throw BPMDetectorError.audioTooShort
        }

        // Step 2: Compute STFT and spectral flux onset detection function
        let onsetFunction = computeOnsetFunction(
            samples: monoSamples,
            sampleRate: sampleRate
        )

        guard onsetFunction.count > 1 else {
            throw BPMDetectorError.analysisFailedInsufficient
        }

        // Step 3: Half-wave rectify
        let rectified = halfWaveRectify(onsetFunction)

        // Step 4: Compute autocorrelation
        let autocorrelation = computeAutocorrelation(rectified)

        // Step 5: Find BPM peaks
        let onsetRate = sampleRate / Double(configuration.hopSize) // Frames per second
        let candidates = findBPMPeaks(
            autocorrelation: autocorrelation,
            onsetRate: onsetRate
        )

        guard let best = candidates.first else {
            return BPMDetectionResult(bpm: 120, confidence: 0, alternatives: [])
        }

        return BPMDetectionResult(
            bpm: best.bpm,
            confidence: best.confidence,
            alternatives: Array(candidates.dropFirst())
        )
    }

    // MARK: - Signal Processing Steps

    /// Convert a multi-channel audio buffer to mono.
    private func convertToMono(buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        if channelCount == 1 {
            return Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        }

        // Mix down to mono by averaging all channels
        var monoSamples = [Float](repeating: 0, count: frameLength)
        for ch in 0..<channelCount {
            let channelPtr = channelData[ch]
            vDSP_vadd(monoSamples, 1, channelPtr, 1, &monoSamples, 1, vDSP_Length(frameLength))
        }

        var divisor = Float(channelCount)
        vDSP_vsdiv(monoSamples, 1, &divisor, &monoSamples, 1, vDSP_Length(frameLength))

        return monoSamples
    }

    /// Compute the onset detection function using spectral flux.
    ///
    /// For each STFT frame, computes the magnitude spectrum and calculates
    /// the positive difference (spectral flux) from the previous frame.
    private func computeOnsetFunction(samples: [Float], sampleRate: Double) -> [Float] {
        let fftSize = configuration.fftSize
        let hopSize = configuration.hopSize
        let log2n = vDSP_Length(log2(Float(fftSize)))

        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return []
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        let halfSize = fftSize / 2
        let numFrames = (samples.count - fftSize) / hopSize + 1

        // Hann window
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        var onsetFunction = [Float]()
        onsetFunction.reserveCapacity(numFrames)

        var previousMagnitude = [Float](repeating: 0, count: halfSize)
        var windowedFrame = [Float](repeating: 0, count: fftSize)
        var realPart = [Float](repeating: 0, count: halfSize)
        var imagPart = [Float](repeating: 0, count: halfSize)
        var magnitude = [Float](repeating: 0, count: halfSize)

        for frameIndex in 0..<numFrames {
            let offset = frameIndex * hopSize

            // Apply window
            vDSP_vmul(
                Array(samples[offset..<(offset + fftSize)]), 1,
                window, 1,
                &windowedFrame, 1,
                vDSP_Length(fftSize)
            )

            // Perform FFT
            windowedFrame.withUnsafeMutableBufferPointer { framePtr in
                realPart.withUnsafeMutableBufferPointer { realPtr in
                    imagPart.withUnsafeMutableBufferPointer { imagPtr in
                        var splitComplex = DSPSplitComplex(
                            realp: realPtr.baseAddress!,
                            imagp: imagPtr.baseAddress!
                        )

                        // Convert to split complex
                        framePtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) { complexPtr in
                            vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(halfSize))
                        }

                        // Forward FFT
                        vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))
                    }
                }
            }

            // Compute magnitude spectrum
            realPart.withUnsafeBufferPointer { realPtr in
                imagPart.withUnsafeBufferPointer { imagPtr in
                    magnitude.withUnsafeMutableBufferPointer { magPtr in
                        var splitComplex = DSPSplitComplex(
                            realp: UnsafeMutablePointer(mutating: realPtr.baseAddress!),
                            imagp: UnsafeMutablePointer(mutating: imagPtr.baseAddress!)
                        )
                        vDSP_zvabs(&splitComplex, 1, magPtr.baseAddress!, 1, vDSP_Length(halfSize))
                    }
                }
            }

            // Spectral flux: sum of positive differences from previous frame
            var flux: Float = 0
            for bin in 0..<halfSize {
                let diff = magnitude[bin] - previousMagnitude[bin]
                if diff > 0 {
                    flux += diff
                }
            }

            onsetFunction.append(flux)
            previousMagnitude = magnitude
        }

        return onsetFunction
    }

    /// Half-wave rectify: keep only positive values, set negatives to zero.
    private func halfWaveRectify(_ signal: [Float]) -> [Float] {
        // Subtract the mean to center the signal
        var mean: Float = 0
        vDSP_meanv(signal, 1, &mean, vDSP_Length(signal.count))

        var result = [Float](repeating: 0, count: signal.count)
        var negMean = -mean
        vDSP_vsadd(signal, 1, &negMean, &result, 1, vDSP_Length(signal.count))

        // Threshold to zero
        var threshold: Float = 0
        vDSP_vthres(result, 1, &threshold, &result, 1, vDSP_Length(signal.count))

        return result
    }

    /// Compute the autocorrelation of a signal using FFT-based method.
    ///
    /// The autocorrelation reveals periodicities in the onset function
    /// that correspond to the tempo.
    private func computeAutocorrelation(_ signal: [Float]) -> [Float] {
        // Pad to next power of 2 for FFT (zero-padded to avoid circular correlation artifacts)
        let paddedLength = Int(pow(2, ceil(log2(Double(signal.count * 2)))))
        let log2n = vDSP_Length(log2(Float(paddedLength)))

        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return []
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        var padded = [Float](repeating: 0, count: paddedLength)
        padded.replaceSubrange(0..<signal.count, with: signal)

        let halfLength = paddedLength / 2
        var realPart = [Float](repeating: 0, count: halfLength)
        var imagPart = [Float](repeating: 0, count: halfLength)

        // Forward FFT
        padded.withUnsafeMutableBufferPointer { paddedPtr in
            realPart.withUnsafeMutableBufferPointer { realPtr in
                imagPart.withUnsafeMutableBufferPointer { imagPtr in
                    var splitComplex = DSPSplitComplex(
                        realp: realPtr.baseAddress!,
                        imagp: imagPtr.baseAddress!
                    )
                    paddedPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfLength) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(halfLength))
                    }
                    vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))

                    // Compute power spectrum (magnitude squared)
                    // R = R*R + I*I, I = 0
                    vDSP_zvmags(&splitComplex, 1, realPtr.baseAddress!, 1, vDSP_Length(halfLength))
                    vDSP_vclr(imagPtr.baseAddress!, 1, vDSP_Length(halfLength))

                    // Inverse FFT to get autocorrelation
                    vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Inverse))

                    // Normalize
                    var scale = 1.0 / Float(paddedLength)
                    vDSP_vsmul(realPtr.baseAddress!, 1, &scale, realPtr.baseAddress!, 1, vDSP_Length(halfLength))
                }
            }
        }

        // Convert back to interleaved format
        var result = [Float](repeating: 0, count: paddedLength)
        realPart.withUnsafeBufferPointer { realPtr in
            imagPart.withUnsafeBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(
                    realp: UnsafeMutablePointer(mutating: realPtr.baseAddress!),
                    imagp: UnsafeMutablePointer(mutating: imagPtr.baseAddress!)
                )
                result.withUnsafeMutableBufferPointer { resultPtr in
                    resultPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfLength) { complexPtr in
                        vDSP_ztoc(&splitComplex, 1, complexPtr, 2, vDSP_Length(halfLength))
                    }
                }
            }
        }

        return Array(result.prefix(signal.count))
    }

    /// Find BPM peaks in the autocorrelation within the valid range.
    private func findBPMPeaks(autocorrelation: [Float], onsetRate: Double) -> [BPMCandidate] {
        // Convert BPM range to lag range
        let minLag = Int(onsetRate * 60.0 / configuration.maxBPM)
        let maxLag = Int(onsetRate * 60.0 / configuration.minBPM)

        guard minLag >= 0 && maxLag < autocorrelation.count && minLag < maxLag else {
            return []
        }

        // Find peaks in the autocorrelation within the valid lag range
        var peaks: [(lag: Int, value: Float)] = []

        for lag in (minLag + 1)..<min(maxLag, autocorrelation.count - 1) {
            let prev = autocorrelation[lag - 1]
            let current = autocorrelation[lag]
            let next = autocorrelation[lag + 1]

            // Local maximum
            if current > prev && current > next && current > 0 {
                peaks.append((lag: lag, value: current))
            }
        }

        // Sort by value (strongest periodicity first)
        peaks.sort { $0.value > $1.value }

        // Normalize confidence by the maximum peak value
        let maxValue = peaks.first?.value ?? 1.0

        // Convert lags to BPM
        let candidates = peaks.prefix(configuration.maxCandidates).map { peak -> BPMCandidate in
            let bpm = (onsetRate * 60.0) / Double(peak.lag)
            let confidence = Double(peak.value / maxValue)
            // Round BPM to nearest 0.1
            let roundedBPM = (bpm * 10).rounded() / 10
            return BPMCandidate(bpm: roundedBPM, confidence: confidence)
        }

        return candidates
    }
}

// MARK: - BPM Detector Errors

/// Errors from BPM detection.
public enum BPMDetectorError: Error, LocalizedError {
    case bufferCreationFailed
    case audioTooShort
    case analysisFailedInsufficient

    public var errorDescription: String? {
        switch self {
        case .bufferCreationFailed:
            return "Failed to create audio buffer for analysis."
        case .audioTooShort:
            return "Audio is too short for reliable BPM detection."
        case .analysisFailedInsufficient:
            return "Insufficient data for BPM analysis."
        }
    }
}
