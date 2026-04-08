// OfflineRenderer.swift
// SampleChainDSP
//
// High-quality offline WAV rendering with Rubberband time-stretching/pitch-shifting,
// normalization to -1 dBFS, and deterministic cache filenames.

import AVFoundation
import Foundation
import Accelerate

// MARK: - Render Configuration

/// Configuration for offline audio rendering.
public struct RenderConfiguration: Sendable {
    /// Output sample rate in Hz.
    public let sampleRate: Double
    /// Output bit depth.
    public let bitDepth: BitDepth
    /// Target peak normalization level in dBFS (e.g. -1.0).
    public let normalizationLevelDBFS: Double
    /// Number of output channels (1 = mono, 2 = stereo).
    public let channelCount: Int
    /// Whether to apply a short fade-in/fade-out to avoid clicks.
    public let applyFades: Bool
    /// Fade duration in seconds.
    public let fadeDuration: Double

    public static let `default` = RenderConfiguration(
        sampleRate: 44100,
        bitDepth: .float32,
        normalizationLevelDBFS: -1.0,
        channelCount: 2,
        applyFades: true,
        fadeDuration: 0.005 // 5ms
    )

    public static let highQuality = RenderConfiguration(
        sampleRate: 48000,
        bitDepth: .int24,
        normalizationLevelDBFS: -1.0,
        channelCount: 2,
        applyFades: true,
        fadeDuration: 0.005
    )

    public init(
        sampleRate: Double = 44100,
        bitDepth: BitDepth = .float32,
        normalizationLevelDBFS: Double = -1.0,
        channelCount: Int = 2,
        applyFades: Bool = true,
        fadeDuration: Double = 0.005
    ) {
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.normalizationLevelDBFS = normalizationLevelDBFS
        self.channelCount = channelCount
        self.applyFades = applyFades
        self.fadeDuration = fadeDuration
    }
}

/// Output bit depth for rendered audio.
public enum BitDepth: Int, Sendable {
    case int16 = 16
    case int24 = 24
    case float32 = 32
}

// MARK: - Render Progress

/// Progress information for an offline render job.
public struct RenderProgress: Sendable {
    /// Current phase of the render pipeline.
    public let phase: RenderPhase
    /// Fraction complete within the current phase (0.0 to 1.0).
    public let phaseProgress: Double
    /// Overall progress (0.0 to 1.0).
    public let overallProgress: Double

    public init(phase: RenderPhase, phaseProgress: Double, overallProgress: Double) {
        self.phase = phase
        self.phaseProgress = phaseProgress
        self.overallProgress = overallProgress
    }
}

/// Phases of the offline rendering pipeline.
public enum RenderPhase: String, Sendable {
    case reading = "Reading audio"
    case timeStretching = "Time stretching"
    case pitchShifting = "Pitch shifting"
    case normalizing = "Normalizing"
    case writing = "Writing output"
    case complete = "Complete"
}

// MARK: - Render Error

/// Errors from offline rendering.
public enum RenderError: Error, LocalizedError, Sendable {
    case inputFileNotFound(URL)
    case readFailed(Error)
    case writeFailed(Error)
    case renderFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .inputFileNotFound(let url):
            return "Input file not found: \(url.lastPathComponent)"
        case .readFailed(let error):
            return "Failed to read input: \(error.localizedDescription)"
        case .writeFailed(let error):
            return "Failed to write output: \(error.localizedDescription)"
        case .renderFailed(let msg):
            return "Render failed: \(msg)"
        case .cancelled:
            return "Render was cancelled."
        }
    }
}

// MARK: - Offline Renderer

/// High-quality offline audio renderer.
///
/// Renders audio files through the Rubberband time-stretching/pitch-shifting pipeline
/// with proper normalization and output formatting. Uses deterministic cache filenames
/// so identical render requests can be served from cache.
///
/// Pipeline:
/// 1. Read source audio file.
/// 2. Apply time stretching and/or pitch shifting via ``RubberbandProcessor``.
/// 3. Normalize audio to the target dBFS level.
/// 4. Apply fade-in/fade-out to prevent clicks.
/// 5. Write output as WAV.
///
/// Usage:
/// ```swift
/// let renderer = OfflineRenderer()
/// let outputURL = try await renderer.render(
///     inputURL: sampleURL,
///     rubberbandOptions: RubberbandOptions(targetBPM: 128, sourceBPM: 120),
///     configuration: .highQuality,
///     progressHandler: { progress in print("\(progress.phase): \(progress.overallProgress)") }
/// )
/// ```
public actor OfflineRenderer {
    private let rubberbandProcessor: RubberbandProcessor
    private let cacheDirectory: URL

    public init(cacheDirectory: URL? = nil) {
        let cacheDir = cacheDirectory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("SampleChainRender")
        self.cacheDirectory = cacheDir
        self.rubberbandProcessor = RubberbandProcessor(
            outputDirectory: cacheDir.appendingPathComponent("rubberband")
        )
    }

    /// Render an audio file with time/pitch processing and normalization.
    ///
    /// - Parameters:
    ///   - inputURL: Source audio file URL.
    ///   - rubberbandOptions: Time-stretching and pitch-shifting options. Nil for pass-through.
    ///   - configuration: Output format and normalization settings.
    ///   - progressHandler: Optional callback for render progress.
    /// - Returns: URL of the rendered output file.
    public func render(
        inputURL: URL,
        rubberbandOptions: RubberbandOptions? = nil,
        configuration: RenderConfiguration = .default,
        progressHandler: (@Sendable (RenderProgress) -> Void)? = nil
    ) async throws -> URL {
        // Generate deterministic output filename
        let outputURL = cacheFileURL(
            for: inputURL,
            options: rubberbandOptions,
            configuration: configuration
        )

        // Check cache
        if FileManager.default.fileExists(atPath: outputURL.path) {
            progressHandler?(RenderProgress(phase: .complete, phaseProgress: 1.0, overallProgress: 1.0))
            return outputURL
        }

        // Phase 1: Read source audio
        progressHandler?(RenderProgress(phase: .reading, phaseProgress: 0, overallProgress: 0))

        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw RenderError.inputFileNotFound(inputURL)
        }

        // Phase 2-3: Time stretching / pitch shifting via Rubberband
        let processedURL: URL
        if let options = rubberbandOptions {
            progressHandler?(RenderProgress(phase: .timeStretching, phaseProgress: 0, overallProgress: 0.1))
            processedURL = try await rubberbandProcessor.process(inputURL: inputURL, options: options)
            progressHandler?(RenderProgress(phase: .timeStretching, phaseProgress: 1.0, overallProgress: 0.5))
        } else {
            processedURL = inputURL
        }

        // Phase 4: Read processed audio, normalize, and write output
        try await renderWithNormalization(
            inputURL: processedURL,
            outputURL: outputURL,
            configuration: configuration,
            progressHandler: progressHandler
        )

        progressHandler?(RenderProgress(phase: .complete, phaseProgress: 1.0, overallProgress: 1.0))
        return outputURL
    }

    /// Remove all cached rendered files.
    public func clearCache() throws {
        if FileManager.default.fileExists(atPath: cacheDirectory.path) {
            try FileManager.default.removeItem(at: cacheDirectory)
        }
    }

    // MARK: - Normalization and Writing

    private func renderWithNormalization(
        inputURL: URL,
        outputURL: URL,
        configuration: RenderConfiguration,
        progressHandler: (@Sendable (RenderProgress) -> Void)?
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            // Read the processed audio
            let inputFile = try AVAudioFile(forReading: inputURL)
            let frameCount = AVAudioFrameCount(inputFile.length)
            let inputFormat = inputFile.processingFormat

            guard let readBuffer = AVAudioPCMBuffer(
                pcmFormat: inputFormat,
                frameCapacity: frameCount
            ) else {
                throw RenderError.renderFailed("Failed to allocate read buffer")
            }
            try inputFile.read(into: readBuffer)

            progressHandler?(RenderProgress(phase: .normalizing, phaseProgress: 0, overallProgress: 0.6))

            guard let floatData = readBuffer.floatChannelData else {
                throw RenderError.renderFailed("No float data in buffer")
            }

            let sampleCount = Int(readBuffer.frameLength)
            let channelCount = Int(inputFormat.channelCount)

            // Find peak level across all channels
            var globalPeak: Float = 0
            for ch in 0..<channelCount {
                var channelPeak: Float = 0
                vDSP_maxmgv(floatData[ch], 1, &channelPeak, vDSP_Length(sampleCount))
                globalPeak = max(globalPeak, channelPeak)
            }

            // Compute normalization gain to reach target dBFS
            // target linear = 10^(dBFS/20)
            let targetLinear = Float(pow(10.0, configuration.normalizationLevelDBFS / 20.0))
            let gain: Float = (globalPeak > 0) ? (targetLinear / globalPeak) : 1.0

            // Apply gain to all channels
            for ch in 0..<channelCount {
                var g = gain
                vDSP_vsmul(floatData[ch], 1, &g, floatData[ch], 1, vDSP_Length(sampleCount))
            }

            progressHandler?(RenderProgress(phase: .normalizing, phaseProgress: 0.5, overallProgress: 0.7))

            // Apply fade-in and fade-out
            if configuration.applyFades {
                let fadeSamples = Int(configuration.fadeDuration * inputFormat.sampleRate)
                let actualFadeSamples = min(fadeSamples, sampleCount / 2)

                for ch in 0..<channelCount {
                    // Fade in
                    for i in 0..<actualFadeSamples {
                        let factor = Float(i) / Float(actualFadeSamples)
                        floatData[ch][i] *= factor
                    }
                    // Fade out
                    for i in 0..<actualFadeSamples {
                        let index = sampleCount - 1 - i
                        let factor = Float(i) / Float(actualFadeSamples)
                        floatData[ch][index] *= factor
                    }
                }
            }

            progressHandler?(RenderProgress(phase: .writing, phaseProgress: 0, overallProgress: 0.8))

            // Prepare output format
            let outputSampleRate = configuration.sampleRate
            let outputChannels = AVAudioChannelCount(configuration.channelCount)

            let commonFormat: AVAudioCommonFormat
            let bitsPerChannel: UInt32
            switch configuration.bitDepth {
            case .int16:
                commonFormat = .pcmFormatInt16
                bitsPerChannel = 16
            case .int24:
                commonFormat = .pcmFormatInt32 // CoreAudio uses Int32 container for 24-bit
                bitsPerChannel = 24
            case .float32:
                commonFormat = .pcmFormatFloat32
                bitsPerChannel = 32
            }

            let outputSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: outputSampleRate,
                AVNumberOfChannelsKey: outputChannels,
                AVLinearPCMBitDepthKey: bitsPerChannel,
                AVLinearPCMIsFloatKey: configuration.bitDepth == .float32,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: true,
            ]

            // Create output directory
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            // If sample rate or channel count differs, convert
            let outputFormat = AVAudioFormat(
                commonFormat: commonFormat,
                sampleRate: outputSampleRate,
                channels: outputChannels,
                interleaved: false
            )!

            let outputFile = try AVAudioFile(
                forWriting: outputURL,
                settings: outputSettings,
                commonFormat: commonFormat,
                interleaved: false
            )

            // If no conversion needed, write directly
            if inputFormat.sampleRate == outputSampleRate && channelCount == Int(outputChannels) {
                try outputFile.write(from: readBuffer)
            } else {
                // Use AVAudioConverter for sample rate / channel conversion
                guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
                    throw RenderError.renderFailed("Failed to create audio converter")
                }

                let outputFrameCapacity = AVAudioFrameCount(
                    Double(sampleCount) * outputSampleRate / inputFormat.sampleRate
                ) + 1024

                guard let outputBuffer = AVAudioPCMBuffer(
                    pcmFormat: outputFormat,
                    frameCapacity: outputFrameCapacity
                ) else {
                    throw RenderError.renderFailed("Failed to allocate output buffer")
                }

                var isDone = false
                let status = converter.convert(to: outputBuffer, error: nil) { _, outStatus in
                    if isDone {
                        outStatus.pointee = .noDataNow
                        return nil
                    }
                    isDone = true
                    outStatus.pointee = .haveData
                    return readBuffer
                }

                guard status != .error else {
                    throw RenderError.renderFailed("Audio conversion failed")
                }

                try outputFile.write(from: outputBuffer)
            }

            progressHandler?(RenderProgress(phase: .writing, phaseProgress: 1.0, overallProgress: 0.95))
        }.value
    }

    // MARK: - Deterministic Cache Filenames

    /// Generate a deterministic output file URL based on input and processing parameters.
    ///
    /// Identical inputs and parameters always produce the same filename, enabling
    /// cache hits without reprocessing.
    private func cacheFileURL(
        for inputURL: URL,
        options: RubberbandOptions?,
        configuration: RenderConfiguration
    ) -> URL {
        let inputName = inputURL.deletingPathExtension().lastPathComponent

        var hashInput = inputName
        if let opts = options {
            hashInput += "_bpm\(opts.targetBPM ?? 0)_src\(opts.sourceBPM ?? 0)_st\(opts.semitones)_q\(opts.quality.rawValue)"
        }
        hashInput += "_sr\(Int(configuration.sampleRate))_bd\(configuration.bitDepth.rawValue)_ch\(configuration.channelCount)_n\(configuration.normalizationLevelDBFS)"

        let hash = hashInput.utf8.reduce(UInt64(5381)) { ($0 << 5) &+ $0 &+ UInt64($1) }
        let fileName = "\(inputName)_\(String(hash, radix: 16)).wav"

        return cacheDirectory.appendingPathComponent("rendered").appendingPathComponent(fileName)
    }
}
