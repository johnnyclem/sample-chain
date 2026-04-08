// KeyDetector.swift
// SampleChainDSP
//
// Musical key detection via chromagram (STFT-based) and Krumhansl-Schmuckler
// key-finding algorithm. Outputs root note + major/minor with confidence score.

import Accelerate
import AVFoundation
import Foundation
import SampleChainCore

// MARK: - Key Detection Result

/// Result of musical key detection analysis.
public struct KeyDetectionResult: Sendable {
    /// The detected musical key.
    public let key: MusicalKey
    /// Confidence score (0.0 to 1.0) of the detection.
    public let confidence: Double
    /// The raw chromagram (12-element array, one per pitch class, C through B).
    public let chromagram: [Double]
    /// All key candidates sorted by correlation score.
    public let allCandidates: [KeyCandidate]

    public init(key: MusicalKey, confidence: Double, chromagram: [Double], allCandidates: [KeyCandidate]) {
        self.key = key
        self.confidence = confidence
        self.chromagram = chromagram
        self.allCandidates = allCandidates
    }
}

/// A key candidate with its correlation score.
public struct KeyCandidate: Sendable {
    public let key: MusicalKey
    public let correlation: Double

    public init(key: MusicalKey, correlation: Double) {
        self.key = key
        self.correlation = correlation
    }
}

// MARK: - Key Detector Configuration

/// Configuration for key detection.
public struct KeyDetectorConfiguration: Sendable {
    /// FFT window size (must be a power of 2).
    public let fftSize: Int
    /// Hop size between consecutive STFT frames.
    public let hopSize: Int
    /// Reference tuning frequency for A4 (standard: 440 Hz).
    public let tuningFrequency: Double
    /// Minimum frequency to consider (Hz).
    public let minFrequency: Double
    /// Maximum frequency to consider (Hz).
    public let maxFrequency: Double

    public static let `default` = KeyDetectorConfiguration(
        fftSize: 4096,
        hopSize: 2048,
        tuningFrequency: 440.0,
        minFrequency: 65.0,   // C2
        maxFrequency: 2100.0  // C7
    )

    public init(
        fftSize: Int = 4096,
        hopSize: Int = 2048,
        tuningFrequency: Double = 440.0,
        minFrequency: Double = 65.0,
        maxFrequency: Double = 2100.0
    ) {
        self.fftSize = fftSize
        self.hopSize = hopSize
        self.tuningFrequency = tuningFrequency
        self.minFrequency = minFrequency
        self.maxFrequency = maxFrequency
    }
}

// MARK: - Krumhansl-Schmuckler Key Profiles

/// The Krumhansl-Schmuckler key profiles represent the perceptual stability
/// of each pitch class within major and minor keys.
private enum KeyProfiles {
    /// Major key profile (Krumhansl, 1990).
    static let major: [Double] = [
        6.35, 2.23, 3.48, 2.33, 4.38, 4.09,
        2.52, 5.19, 2.39, 3.66, 2.29, 2.88
    ]

    /// Minor key profile (Krumhansl, 1990).
    static let minor: [Double] = [
        6.33, 2.68, 3.52, 5.38, 2.60, 3.53,
        2.54, 4.75, 3.98, 2.69, 3.34, 3.17
    ]
}

// MARK: - Key Detector

/// Detects the musical key of an audio file.
///
/// Algorithm overview:
/// 1. Read audio and convert to mono.
/// 2. Compute STFT using Accelerate vDSP.
/// 3. Map frequency bins to pitch classes to build a chromagram.
/// 4. Average the chromagram across all frames.
/// 5. Correlate the averaged chromagram with the Krumhansl-Schmuckler
///    major and minor profiles for all 12 possible root notes.
/// 6. The key with the highest correlation is the detected key.
///
/// Usage:
/// ```swift
/// let detector = KeyDetector()
/// let result = try await detector.detect(fileURL: sampleURL)
/// print("Key: \(result.key) (confidence: \(result.confidence))")
/// ```
public final class KeyDetector: Sendable {
    private let configuration: KeyDetectorConfiguration

    public init(configuration: KeyDetectorConfiguration = .default) {
        self.configuration = configuration
    }

    /// Detect the musical key of an audio file.
    ///
    /// - Parameter fileURL: URL of the audio file to analyze.
    /// - Returns: The key detection result with confidence.
    /// - Throws: If the file cannot be read or processed.
    public func detect(fileURL: URL) async throws -> KeyDetectionResult {
        return try await Task.detached(priority: .userInitiated) { [self] in
            try self.performDetection(fileURL: fileURL)
        }.value
    }

    // MARK: - Core Detection Pipeline

    private func performDetection(fileURL: URL) throws -> KeyDetectionResult {
        // Step 1: Read audio
        let audioFile = try AVAudioFile(forReading: fileURL)
        let sampleRate = audioFile.processingFormat.sampleRate
        let frameCount = AVAudioFrameCount(audioFile.length)

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: audioFile.processingFormat,
            frameCapacity: frameCount
        ) else {
            throw KeyDetectorError.bufferCreationFailed
        }
        try audioFile.read(into: buffer)

        let monoSamples = convertToMono(buffer: buffer)
        guard monoSamples.count > configuration.fftSize else {
            throw KeyDetectorError.audioTooShort
        }

        // Step 2 & 3: Compute chromagram via STFT
        let chromagram = computeChromagram(samples: monoSamples, sampleRate: sampleRate)

        // Step 4: Krumhansl-Schmuckler key-finding
        let candidates = correlateWithProfiles(chromagram: chromagram)

        guard let best = candidates.first else {
            throw KeyDetectorError.analysisFailedNoKey
        }

        // Confidence: ratio of best correlation to second-best
        let secondBest = candidates.count > 1 ? candidates[1].correlation : 0
        let confidence: Double
        if secondBest > 0 {
            confidence = min(1.0, (best.correlation - secondBest) / best.correlation + 0.5)
        } else {
            confidence = 1.0
        }

        return KeyDetectionResult(
            key: best.key,
            confidence: confidence,
            chromagram: chromagram,
            allCandidates: candidates
        )
    }

    // MARK: - Signal Processing

    /// Convert a multi-channel buffer to mono.
    private func convertToMono(buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        if channelCount == 1 {
            return Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        }

        var mono = [Float](repeating: 0, count: frameLength)
        for ch in 0..<channelCount {
            vDSP_vadd(mono, 1, channelData[ch], 1, &mono, 1, vDSP_Length(frameLength))
        }
        var divisor = Float(channelCount)
        vDSP_vsdiv(mono, 1, &divisor, &mono, 1, vDSP_Length(frameLength))
        return mono
    }

    /// Compute the averaged chromagram from the STFT of the audio.
    ///
    /// Maps each FFT bin to its nearest pitch class (C=0, C#=1, ..., B=11)
    /// and accumulates energy per pitch class across all frames.
    private func computeChromagram(samples: [Float], sampleRate: Double) -> [Double] {
        let fftSize = configuration.fftSize
        let hopSize = configuration.hopSize
        let log2n = vDSP_Length(log2(Float(fftSize)))
        let halfSize = fftSize / 2

        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return [Double](repeating: 0, count: 12)
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        let numFrames = (samples.count - fftSize) / hopSize + 1

        // Hann window
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        // Precompute bin-to-pitch-class mapping
        let binToPitchClass = computeBinToPitchClassMapping(
            fftSize: fftSize,
            sampleRate: sampleRate
        )

        // Accumulate chroma energy
        var chromaAccumulator = [Double](repeating: 0, count: 12)
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

            // FFT
            windowedFrame.withUnsafeMutableBufferPointer { framePtr in
                realPart.withUnsafeMutableBufferPointer { realPtr in
                    imagPart.withUnsafeMutableBufferPointer { imagPtr in
                        var splitComplex = DSPSplitComplex(
                            realp: realPtr.baseAddress!,
                            imagp: imagPtr.baseAddress!
                        )
                        framePtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) { complexPtr in
                            vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(halfSize))
                        }
                        vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))

                        // Magnitude spectrum
                        vDSP_zvabs(&splitComplex, 1, &magnitude, 1, vDSP_Length(halfSize))
                    }
                }
            }

            // Map magnitude bins to pitch classes
            for bin in 0..<halfSize {
                if let pitchClass = binToPitchClass[bin] {
                    chromaAccumulator[pitchClass] += Double(magnitude[bin])
                }
            }
        }

        // Normalize the chromagram
        let maxChroma = chromaAccumulator.max() ?? 1.0
        if maxChroma > 0 {
            for i in 0..<12 {
                chromaAccumulator[i] /= maxChroma
            }
        }

        return chromaAccumulator
    }

    /// Map each FFT bin to its nearest pitch class (0-11) or nil if out of range.
    private func computeBinToPitchClassMapping(fftSize: Int, sampleRate: Double) -> [Int?] {
        let halfSize = fftSize / 2
        let binFrequencyResolution = sampleRate / Double(fftSize)

        return (0..<halfSize).map { bin -> Int? in
            let frequency = Double(bin) * binFrequencyResolution

            // Skip frequencies outside our range
            guard frequency >= configuration.minFrequency && frequency <= configuration.maxFrequency else {
                return nil
            }

            // Convert frequency to pitch class using equal temperament
            // MIDI note number: 69 + 12 * log2(frequency / 440)
            let midiNote = 69.0 + 12.0 * log2(frequency / configuration.tuningFrequency)
            let pitchClass = Int(round(midiNote)) % 12

            // Ensure positive modulo
            return ((pitchClass % 12) + 12) % 12
        }
    }

    // MARK: - Krumhansl-Schmuckler Correlation

    /// Correlate the chromagram with all 24 major and minor key profiles.
    ///
    /// For each of the 12 root notes, rotates the chromagram so that the
    /// root note aligns with index 0, then computes the Pearson correlation
    /// with both the major and minor profiles.
    private func correlateWithProfiles(chromagram: [Double]) -> [KeyCandidate] {
        let pitchClasses = PitchClass.allCases
        var candidates: [KeyCandidate] = []

        for (rootIndex, pitchClass) in pitchClasses.enumerated() {
            // Rotate chromagram so that the current root is at index 0
            let rotated = rotateChromagram(chromagram, by: rootIndex)

            // Correlate with major profile
            let majorCorrelation = pearsonCorrelation(rotated, KeyProfiles.major)
            candidates.append(KeyCandidate(
                key: MusicalKey(root: pitchClass, quality: .major),
                correlation: majorCorrelation
            ))

            // Correlate with minor profile
            let minorCorrelation = pearsonCorrelation(rotated, KeyProfiles.minor)
            candidates.append(KeyCandidate(
                key: MusicalKey(root: pitchClass, quality: .minor),
                correlation: minorCorrelation
            ))
        }

        // Sort by correlation (highest first)
        candidates.sort { $0.correlation > $1.correlation }

        return candidates
    }

    /// Rotate a chromagram array so that the given pitch class index becomes index 0.
    private func rotateChromagram(_ chromagram: [Double], by offset: Int) -> [Double] {
        let n = chromagram.count
        return (0..<n).map { chromagram[($0 + offset) % n] }
    }

    /// Compute the Pearson correlation coefficient between two vectors.
    private func pearsonCorrelation(_ x: [Double], _ y: [Double]) -> Double {
        let n = Double(x.count)
        guard n > 0 else { return 0 }

        let sumX = x.reduce(0, +)
        let sumY = y.reduce(0, +)
        let sumXY = zip(x, y).map(*).reduce(0, +)
        let sumX2 = x.map { $0 * $0 }.reduce(0, +)
        let sumY2 = y.map { $0 * $0 }.reduce(0, +)

        let numerator = n * sumXY - sumX * sumY
        let denominator = sqrt((n * sumX2 - sumX * sumX) * (n * sumY2 - sumY * sumY))

        guard denominator > 0 else { return 0 }
        return numerator / denominator
    }
}

// MARK: - Key Detector Errors

/// Errors from key detection.
public enum KeyDetectorError: Error, LocalizedError {
    case bufferCreationFailed
    case audioTooShort
    case analysisFailedNoKey

    public var errorDescription: String? {
        switch self {
        case .bufferCreationFailed:
            return "Failed to create audio buffer for key analysis."
        case .audioTooShort:
            return "Audio is too short for reliable key detection."
        case .analysisFailedNoKey:
            return "Could not determine musical key."
        }
    }
}
