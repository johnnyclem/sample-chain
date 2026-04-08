// RubberbandProcessor.swift
// SampleChainDSP
//
// Wrapper for the Rubber Band C library providing high-quality time stretching
// and pitch shifting with an async Swift API.

import AVFoundation
import Foundation

// MARK: - Rubberband Options

/// Options for Rubber Band processing.
public struct RubberbandOptions: Sendable {
    /// Target BPM for time stretching. Nil means no time stretch.
    public let targetBPM: Double?
    /// Source BPM of the original audio. Required if targetBPM is set.
    public let sourceBPM: Double?
    /// Pitch shift in semitones (positive = up, negative = down). Zero means no pitch shift.
    public let semitones: Double
    /// Whether to preserve formants during pitch shifting (better for vocals).
    public let preserveFormants: Bool
    /// Processing quality: higher = better quality but slower.
    public let quality: ProcessingQuality

    public init(
        targetBPM: Double? = nil,
        sourceBPM: Double? = nil,
        semitones: Double = 0,
        preserveFormants: Bool = false,
        quality: ProcessingQuality = .high
    ) {
        self.targetBPM = targetBPM
        self.sourceBPM = sourceBPM
        self.semitones = semitones
        self.preserveFormants = preserveFormants
        self.quality = quality
    }
}

/// Processing quality levels.
public enum ProcessingQuality: Int, Sendable {
    /// Fast processing, suitable for real-time preview.
    case realtime = 0
    /// High quality, suitable for offline rendering.
    case high = 1
    /// Maximum quality, slowest processing.
    case maximum = 2
}

// MARK: - Rubberband Error

/// Errors from Rubber Band processing.
public enum RubberbandError: Error, LocalizedError, Sendable {
    case fileReadFailed(URL)
    case fileWriteFailed(URL)
    case invalidParameters(String)
    case processingFailed(String)
    case libraryNotAvailable

    public var errorDescription: String? {
        switch self {
        case .fileReadFailed(let url):
            return "Failed to read audio file: \(url.lastPathComponent)"
        case .fileWriteFailed(let url):
            return "Failed to write processed audio: \(url.lastPathComponent)"
        case .invalidParameters(let msg):
            return "Invalid processing parameters: \(msg)"
        case .processingFailed(let msg):
            return "Rubber Band processing failed: \(msg)"
        case .libraryNotAvailable:
            return "Rubber Band library is not available."
        }
    }
}

// MARK: - Rubberband C Interface

// These declarations mirror the Rubber Band C API.
// In a real build, these would come from the rubberband/rubberband-c.h header.

/// Opaque handle to a Rubber Band state instance.
typealias RubberBandState = OpaquePointer

// Rubber Band option flags (subset relevant to our usage)
private let RubberBandOptionProcessOffline: Int32 = 0x00000000
private let RubberBandOptionProcessRealTime: Int32 = 0x00000001
private let RubberBandOptionStretchElastic: Int32 = 0x00000000
private let RubberBandOptionTransientsCrisp: Int32 = 0x00000000
private let RubberBandOptionPitchHighQuality: Int32 = 0x00000000
private let RubberBandOptionFormantPreserved: Int32 = 0x01000000
private let RubberBandOptionWindowStandard: Int32 = 0x00000000
private let RubberBandOptionWindowLong: Int32 = 0x00200000
private let RubberBandOptionEngineFiner: Int32 = 0x00000020

// C function declarations -- linked at build time from librubberband
@_silgen_name("rubberband_new")
func rubberband_new(_ sampleRate: UInt32, _ channels: UInt32, _ options: Int32, _ timeRatio: Double, _ pitchScale: Double) -> RubberBandState?

@_silgen_name("rubberband_delete")
func rubberband_delete(_ state: RubberBandState)

@_silgen_name("rubberband_set_time_ratio")
func rubberband_set_time_ratio(_ state: RubberBandState, _ ratio: Double)

@_silgen_name("rubberband_set_pitch_scale")
func rubberband_set_pitch_scale(_ state: RubberBandState, _ scale: Double)

@_silgen_name("rubberband_set_expected_input_duration")
func rubberband_set_expected_input_duration(_ state: RubberBandState, _ samples: UInt32)

@_silgen_name("rubberband_study")
func rubberband_study(_ state: RubberBandState, _ input: UnsafePointer<UnsafePointer<Float>?>, _ samples: UInt32, _ final_: Int32)

@_silgen_name("rubberband_process")
func rubberband_process(_ state: RubberBandState, _ input: UnsafePointer<UnsafePointer<Float>?>, _ samples: UInt32, _ final_: Int32)

@_silgen_name("rubberband_available")
func rubberband_available(_ state: RubberBandState) -> Int32

@_silgen_name("rubberband_retrieve")
func rubberband_retrieve(_ state: RubberBandState, _ output: UnsafePointer<UnsafeMutablePointer<Float>?>, _ samples: UInt32) -> UInt32

// MARK: - Rubberband Processor

/// High-level async wrapper around the Rubber Band time-stretching and pitch-shifting library.
///
/// Processes audio files offline for maximum quality. Results are cached with
/// deterministic filenames to avoid reprocessing identical requests.
///
/// Usage:
/// ```swift
/// let processor = RubberbandProcessor()
/// let outputURL = try await processor.process(
///     inputURL: sampleFile,
///     options: RubberbandOptions(targetBPM: 128, sourceBPM: 120, semitones: 2)
/// )
/// ```
public actor RubberbandProcessor {
    private let outputDirectory: URL
    private let blockSize: Int = 4096

    public init(outputDirectory: URL? = nil) {
        if let dir = outputDirectory {
            self.outputDirectory = dir
        } else {
            self.outputDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("SampleChainRubberband")
        }
    }

    /// Process an audio file with time stretching and/or pitch shifting.
    ///
    /// - Parameters:
    ///   - inputURL: URL of the source audio file.
    ///   - options: Processing parameters (BPM, semitones, quality).
    /// - Returns: URL of the processed audio file.
    /// - Throws: ``RubberbandError`` on failure.
    public func process(inputURL: URL, options: RubberbandOptions) async throws -> URL {
        // Check for no-op
        let timeRatio = computeTimeRatio(options: options)
        let pitchScale = computePitchScale(semitones: options.semitones)

        if abs(timeRatio - 1.0) < 0.001 && abs(pitchScale - 1.0) < 0.001 {
            // No processing needed; return input as-is
            return inputURL
        }

        // Generate deterministic output filename
        let outputURL = try outputFileURL(for: inputURL, options: options)

        // Check if already processed
        if FileManager.default.fileExists(atPath: outputURL.path) {
            return outputURL
        }

        // Perform processing on a background thread
        return try await Task.detached(priority: .userInitiated) { [self] in
            try await self.performProcessing(
                inputURL: inputURL,
                outputURL: outputURL,
                timeRatio: timeRatio,
                pitchScale: pitchScale,
                options: options
            )
        }.value
    }

    /// Remove all cached processed files.
    public func clearCache() throws {
        if FileManager.default.fileExists(atPath: outputDirectory.path) {
            try FileManager.default.removeItem(at: outputDirectory)
        }
    }

    // MARK: - Private Processing

    private func performProcessing(
        inputURL: URL,
        outputURL: URL,
        timeRatio: Double,
        pitchScale: Double,
        options: RubberbandOptions
    ) async throws -> URL {
        // Read input file
        let inputFile = try AVAudioFile(forReading: inputURL)
        let sampleRate = UInt32(inputFile.processingFormat.sampleRate)
        let channelCount = UInt32(inputFile.processingFormat.channelCount)
        let totalFrames = UInt32(inputFile.length)

        // Build Rubber Band options flags
        var rbOptions: Int32 = RubberBandOptionProcessOffline
            | RubberBandOptionStretchElastic
            | RubberBandOptionTransientsCrisp
            | RubberBandOptionPitchHighQuality

        if options.preserveFormants {
            rbOptions |= RubberBandOptionFormantPreserved
        }

        switch options.quality {
        case .realtime:
            rbOptions |= RubberBandOptionWindowStandard
        case .high:
            rbOptions |= RubberBandOptionWindowLong
        case .maximum:
            rbOptions |= RubberBandOptionWindowLong | RubberBandOptionEngineFiner
        }

        // Create Rubber Band state
        guard let state = rubberband_new(sampleRate, channelCount, rbOptions, timeRatio, pitchScale) else {
            throw RubberbandError.libraryNotAvailable
        }
        defer { rubberband_delete(state) }

        rubberband_set_expected_input_duration(state, totalFrames)

        // Read all audio data into buffers
        guard let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: inputFile.processingFormat,
            frameCapacity: AVAudioFrameCount(totalFrames)
        ) else {
            throw RubberbandError.fileReadFailed(inputURL)
        }
        try inputFile.read(into: inputBuffer)

        guard let floatData = inputBuffer.floatChannelData else {
            throw RubberbandError.fileReadFailed(inputURL)
        }

        // Study phase (offline mode): analyze the entire input for optimal stretching
        let blockSize = UInt32(self.blockSize)
        var offset: UInt32 = 0

        while offset < totalFrames {
            let remaining = totalFrames - offset
            let count = min(blockSize, remaining)
            let isFinal: Int32 = (offset + count >= totalFrames) ? 1 : 0

            // Build array of channel pointers at the current offset
            var channelPointers = (0..<Int(channelCount)).map { ch -> UnsafePointer<Float>? in
                UnsafePointer(floatData[ch].advanced(by: Int(offset)))
            }

            channelPointers.withUnsafeBufferPointer { ptrs in
                rubberband_study(state, ptrs.baseAddress!, count, isFinal)
            }

            offset += count
        }

        // Process phase: feed input and collect output
        let estimatedOutputFrames = Int(Double(totalFrames) * timeRatio) + blockSize.hashValue
        var outputBuffers = (0..<Int(channelCount)).map { _ in
            [Float](repeating: 0, count: estimatedOutputFrames)
        }
        var outputOffset = 0

        offset = 0
        while offset < totalFrames {
            let remaining = totalFrames - offset
            let count = min(blockSize, remaining)
            let isFinal: Int32 = (offset + count >= totalFrames) ? 1 : 0

            var channelPointers = (0..<Int(channelCount)).map { ch -> UnsafePointer<Float>? in
                UnsafePointer(floatData[ch].advanced(by: Int(offset)))
            }

            channelPointers.withUnsafeBufferPointer { ptrs in
                rubberband_process(state, ptrs.baseAddress!, count, isFinal)
            }

            // Retrieve available output
            while rubberband_available(state) > 0 {
                let available = UInt32(rubberband_available(state))
                let retrieveCount = min(available, blockSize)

                // Allocate temporary output channel buffers
                var tempBuffers = (0..<Int(channelCount)).map { _ in
                    [Float](repeating: 0, count: Int(retrieveCount))
                }

                var outputPointers = (0..<Int(channelCount)).map { ch -> UnsafeMutablePointer<Float>? in
                    tempBuffers[ch].withUnsafeMutableBufferPointer { $0.baseAddress }
                }

                let retrieved = outputPointers.withUnsafeMutableBufferPointer { ptrs -> UInt32 in
                    rubberband_retrieve(state, ptrs.baseAddress!, retrieveCount)
                }

                // Append to output buffers
                for ch in 0..<Int(channelCount) {
                    let endIndex = outputOffset + Int(retrieved)
                    // Grow output buffer if needed
                    while outputBuffers[ch].count < endIndex {
                        outputBuffers[ch].append(contentsOf: [Float](repeating: 0, count: Int(blockSize)))
                    }
                    outputBuffers[ch].replaceSubrange(
                        outputOffset..<endIndex,
                        with: tempBuffers[ch].prefix(Int(retrieved))
                    )
                }
                outputOffset += Int(retrieved)
            }

            offset += count
        }

        // Ensure output directory exists
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Write output to WAV file
        let outputFormat = AVAudioFormat(
            standardFormatWithSampleRate: Double(sampleRate),
            channels: AVAudioChannelCount(channelCount)
        )!

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: AVAudioFrameCount(outputOffset)
        ) else {
            throw RubberbandError.fileWriteFailed(outputURL)
        }
        outputBuffer.frameLength = AVAudioFrameCount(outputOffset)

        guard let outputFloatData = outputBuffer.floatChannelData else {
            throw RubberbandError.fileWriteFailed(outputURL)
        }

        for ch in 0..<Int(channelCount) {
            outputBuffers[ch].withUnsafeBufferPointer { srcPtr in
                outputFloatData[ch].update(from: srcPtr.baseAddress!, count: outputOffset)
            }
        }

        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: outputFormat.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try outputFile.write(from: outputBuffer)

        return outputURL
    }

    // MARK: - Helpers

    /// Compute the time ratio from the BPM options.
    private func computeTimeRatio(options: RubberbandOptions) -> Double {
        guard let targetBPM = options.targetBPM, let sourceBPM = options.sourceBPM, sourceBPM > 0 else {
            return 1.0
        }
        return sourceBPM / targetBPM
    }

    /// Compute the pitch scale from semitones.
    /// Each semitone is a factor of 2^(1/12).
    private func computePitchScale(semitones: Double) -> Double {
        pow(2.0, semitones / 12.0)
    }

    /// Generate a deterministic output file URL based on input file and processing parameters.
    ///
    /// This ensures that identical processing requests produce the same filename,
    /// enabling cache hits without reprocessing.
    private func outputFileURL(for inputURL: URL, options: RubberbandOptions) throws -> URL {
        let inputName = inputURL.deletingPathExtension().lastPathComponent
        let timeRatio = computeTimeRatio(options: options)
        let pitchScale = computePitchScale(semitones: options.semitones)

        // Create a deterministic hash from input file name + processing parameters
        let paramString = "\(inputName)_tr\(String(format: "%.4f", timeRatio))_ps\(String(format: "%.4f", pitchScale))_q\(options.quality.rawValue)"
        let hash = paramString.utf8.reduce(UInt64(5381)) { ($0 << 5) &+ $0 &+ UInt64($1) }
        let fileName = "\(inputName)_\(String(hash, radix: 16)).wav"

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        return outputDirectory.appendingPathComponent(fileName)
    }
}
