// AudioEngine.swift
// SampleChainDSP
//
// AVAudioEngine wrapper providing multi-track sample audition with time-pitch adjustment,
// crossfade transitions, and mixing. Supports simultaneous playback of up to 4 samples.

import AVFoundation
import Foundation

// MARK: - Playback State

/// State of a single player channel.
public enum PlaybackState: Equatable, Sendable {
    case idle
    case loading
    case playing
    case paused
    case stopped
    case error(String)
}

/// Information about a player channel.
public struct PlayerChannelInfo: Sendable {
    /// Zero-based channel index.
    public let channelIndex: Int
    /// Current playback state.
    public let state: PlaybackState
    /// The sample token ID loaded on this channel (nil if empty).
    public let sampleTokenId: String?
    /// Current playback position in seconds.
    public let currentTime: Double
    /// Total duration of the loaded audio in seconds.
    public let duration: Double
    /// Channel volume (0.0 to 1.0).
    public let volume: Float
    /// Channel pan (-1.0 = left, 0.0 = center, 1.0 = right).
    public let pan: Float
    /// Whether this channel is muted.
    public let isMuted: Bool

    public init(
        channelIndex: Int,
        state: PlaybackState = .idle,
        sampleTokenId: String? = nil,
        currentTime: Double = 0,
        duration: Double = 0,
        volume: Float = 1.0,
        pan: Float = 0.0,
        isMuted: Bool = false
    ) {
        self.channelIndex = channelIndex
        self.state = state
        self.sampleTokenId = sampleTokenId
        self.currentTime = currentTime
        self.duration = duration
        self.volume = volume
        self.pan = pan
        self.isMuted = isMuted
    }
}

// MARK: - Audio Engine Configuration

/// Configuration for the audio engine.
public struct AudioEngineConfiguration: Sendable {
    /// Maximum number of simultaneous player channels.
    public let maxChannels: Int
    /// Output sample rate.
    public let sampleRate: Double
    /// Crossfade duration in seconds when switching samples.
    public let crossfadeDuration: TimeInterval

    public static let `default` = AudioEngineConfiguration(
        maxChannels: 4,
        sampleRate: 44100,
        crossfadeDuration: 0.05
    )

    public init(maxChannels: Int = 4, sampleRate: Double = 44100, crossfadeDuration: TimeInterval = 0.05) {
        self.maxChannels = maxChannels
        self.sampleRate = sampleRate
        self.crossfadeDuration = crossfadeDuration
    }
}

// MARK: - Player Channel

/// Internal representation of a single player channel in the engine graph.
final class PlayerChannel {
    let index: Int
    let playerNode: AVAudioPlayerNode
    let timePitchNode: AVAudioUnitTimePitch
    let mixerNode: AVAudioMixerNode

    var audioFile: AVAudioFile?
    var sampleTokenId: String?
    var state: PlaybackState = .idle
    var volume: Float = 1.0 {
        didSet { mixerNode.outputVolume = isMuted ? 0 : volume }
    }
    var pan: Float = 0.0 {
        didSet { mixerNode.pan = pan }
    }
    var isMuted: Bool = false {
        didSet { mixerNode.outputVolume = isMuted ? 0 : volume }
    }

    /// Pitch shift in semitones.
    var pitchShift: Float = 0 {
        didSet { timePitchNode.pitch = pitchShift * 100 } // AVAudioUnitTimePitch uses cents
    }

    /// Playback rate multiplier (e.g. 0.5 = half speed, 2.0 = double speed).
    var rate: Float = 1.0 {
        didSet { timePitchNode.rate = rate }
    }

    init(index: Int) {
        self.index = index
        self.playerNode = AVAudioPlayerNode()
        self.timePitchNode = AVAudioUnitTimePitch()
        self.mixerNode = AVAudioMixerNode()

        // Initialize time pitch with neutral settings
        timePitchNode.pitch = 0
        timePitchNode.rate = 1.0
        timePitchNode.overlap = 8 // Higher quality time stretching
    }

    var duration: Double {
        guard let file = audioFile else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    var currentTime: Double {
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return 0
        }
        return Double(playerTime.sampleTime) / playerTime.sampleRate
    }

    var info: PlayerChannelInfo {
        PlayerChannelInfo(
            channelIndex: index,
            state: state,
            sampleTokenId: sampleTokenId,
            currentTime: currentTime,
            duration: duration,
            volume: volume,
            pan: pan,
            isMuted: isMuted
        )
    }
}

// MARK: - Audio Engine

/// High-level audio engine for previewing and auditioning samples.
///
/// Wraps `AVAudioEngine` with multiple player channels, each with independent
/// time-pitch processing. Supports:
/// - Up to 4 simultaneous sample previews
/// - Independent pitch shift and time stretch per channel
/// - Volume, pan, and mute per channel
/// - Smooth crossfade when replacing a sample on a channel
/// - Transport controls (play, pause, stop, seek)
///
/// Usage:
/// ```swift
/// let engine = AudioEngine()
/// try engine.start()
/// try await engine.loadSample(fileURL: url, onChannel: 0, tokenId: "42")
/// engine.play(channel: 0)
/// ```
public final class AudioEngine: @unchecked Sendable {
    private let avEngine: AVAudioEngine
    private let mainMixer: AVAudioMixerNode
    private var channels: [PlayerChannel]
    private let configuration: AudioEngineConfiguration
    private let lock = NSLock()

    /// Master output volume (0.0 to 1.0).
    public var masterVolume: Float {
        get { mainMixer.outputVolume }
        set { mainMixer.outputVolume = newValue }
    }

    /// Whether the engine is currently running.
    public var isRunning: Bool { avEngine.isRunning }

    public init(configuration: AudioEngineConfiguration = .default) {
        self.configuration = configuration
        self.avEngine = AVAudioEngine()
        self.mainMixer = avEngine.mainMixerNode
        self.channels = []

        setupGraph()
    }

    // MARK: - Engine Lifecycle

    /// Set up the audio processing graph.
    private func setupGraph() {
        channels = (0..<configuration.maxChannels).map { index in
            let channel = PlayerChannel(index: index)

            // Attach nodes
            avEngine.attach(channel.playerNode)
            avEngine.attach(channel.timePitchNode)
            avEngine.attach(channel.mixerNode)

            // Connect: playerNode -> timePitch -> channelMixer -> mainMixer
            let format = AVAudioFormat(standardFormatWithSampleRate: configuration.sampleRate, channels: 2)!
            avEngine.connect(channel.playerNode, to: channel.timePitchNode, format: format)
            avEngine.connect(channel.timePitchNode, to: channel.mixerNode, format: format)
            avEngine.connect(channel.mixerNode, to: mainMixer, format: format)

            return channel
        }
    }

    /// Start the audio engine.
    ///
    /// - Throws: If the engine fails to start.
    public func start() throws {
        guard !avEngine.isRunning else { return }
        try avEngine.start()
    }

    /// Stop the audio engine and all playback.
    public func stop() {
        lock.lock()
        defer { lock.unlock() }

        for channel in channels {
            channel.playerNode.stop()
            channel.state = .stopped
        }
        avEngine.stop()
    }

    // MARK: - Sample Loading

    /// Load an audio file onto a player channel.
    ///
    /// - Parameters:
    ///   - fileURL: Local URL of the audio file.
    ///   - channelIndex: The channel to load onto (0-based).
    ///   - tokenId: The sample token ID for tracking.
    ///   - crossfade: Whether to crossfade from any currently playing sample.
    /// - Throws: If the file cannot be read or the channel index is invalid.
    public func loadSample(
        fileURL: URL,
        onChannel channelIndex: Int,
        tokenId: String,
        crossfade: Bool = true
    ) throws {
        guard channelIndex >= 0 && channelIndex < channels.count else {
            throw AudioEngineError.invalidChannel(channelIndex)
        }

        let channel = channels[channelIndex]

        lock.lock()
        defer { lock.unlock() }

        // Stop current playback on this channel
        if channel.state == .playing && crossfade {
            performCrossfadeOut(channel: channel)
        } else {
            channel.playerNode.stop()
        }

        // Load the new file
        let audioFile = try AVAudioFile(forReading: fileURL)
        channel.audioFile = audioFile
        channel.sampleTokenId = tokenId
        channel.state = .stopped

        // Reset time-pitch to neutral
        channel.pitchShift = 0
        channel.rate = 1.0
    }

    // MARK: - Transport Controls

    /// Start playback on a channel.
    ///
    /// - Parameters:
    ///   - channelIndex: The channel to play.
    ///   - fromTime: Optional start time in seconds (default: beginning or current position).
    ///   - loop: Whether to loop the sample.
    public func play(channel channelIndex: Int, fromTime: Double? = nil, loop: Bool = false) {
        guard channelIndex >= 0 && channelIndex < channels.count else { return }
        let channel = channels[channelIndex]
        guard let audioFile = channel.audioFile else { return }

        lock.lock()
        defer { lock.unlock() }

        channel.playerNode.stop()

        let startFrame: AVAudioFramePosition
        if let fromTime {
            startFrame = AVAudioFramePosition(fromTime * audioFile.processingFormat.sampleRate)
        } else {
            startFrame = 0
        }

        let frameCount = AVAudioFrameCount(audioFile.length - startFrame)
        guard frameCount > 0 else { return }

        if loop {
            channel.playerNode.scheduleSegment(
                audioFile,
                startingFrame: startFrame,
                frameCount: frameCount,
                at: nil
            )
            // Schedule the full file again for looping
            channel.playerNode.scheduleFile(audioFile, at: nil)
        } else {
            channel.playerNode.scheduleSegment(
                audioFile,
                startingFrame: startFrame,
                frameCount: frameCount,
                at: nil
            ) {
                DispatchQueue.main.async {
                    channel.state = .stopped
                }
            }
        }

        channel.playerNode.play()
        channel.state = .playing
    }

    /// Pause playback on a channel.
    public func pause(channel channelIndex: Int) {
        guard channelIndex >= 0 && channelIndex < channels.count else { return }
        let channel = channels[channelIndex]
        channel.playerNode.pause()
        channel.state = .paused
    }

    /// Stop playback on a channel and reset position to the beginning.
    public func stop(channel channelIndex: Int) {
        guard channelIndex >= 0 && channelIndex < channels.count else { return }
        let channel = channels[channelIndex]
        channel.playerNode.stop()
        channel.state = .stopped
    }

    /// Stop all channels.
    public func stopAll() {
        for i in 0..<channels.count {
            stop(channel: i)
        }
    }

    /// Seek to a specific time on a channel.
    ///
    /// - Parameters:
    ///   - channelIndex: The channel to seek.
    ///   - time: Target time in seconds.
    public func seek(channel channelIndex: Int, to time: Double) {
        guard channelIndex >= 0 && channelIndex < channels.count else { return }
        let wasPlaying = channels[channelIndex].state == .playing
        stop(channel: channelIndex)
        if wasPlaying {
            play(channel: channelIndex, fromTime: time)
        }
    }

    // MARK: - Channel Controls

    /// Set the volume for a channel.
    ///
    /// - Parameters:
    ///   - channelIndex: Channel index.
    ///   - volume: Volume level (0.0 to 1.0).
    public func setVolume(channel channelIndex: Int, volume: Float) {
        guard channelIndex >= 0 && channelIndex < channels.count else { return }
        channels[channelIndex].volume = max(0, min(1, volume))
    }

    /// Set the pan for a channel.
    ///
    /// - Parameters:
    ///   - channelIndex: Channel index.
    ///   - pan: Pan position (-1.0 = left, 0.0 = center, 1.0 = right).
    public func setPan(channel channelIndex: Int, pan: Float) {
        guard channelIndex >= 0 && channelIndex < channels.count else { return }
        channels[channelIndex].pan = max(-1, min(1, pan))
    }

    /// Toggle mute for a channel.
    public func toggleMute(channel channelIndex: Int) {
        guard channelIndex >= 0 && channelIndex < channels.count else { return }
        channels[channelIndex].isMuted.toggle()
    }

    /// Set pitch shift for a channel.
    ///
    /// - Parameters:
    ///   - channelIndex: Channel index.
    ///   - semitones: Pitch shift in semitones (e.g. -12 to +12).
    public func setPitch(channel channelIndex: Int, semitones: Float) {
        guard channelIndex >= 0 && channelIndex < channels.count else { return }
        channels[channelIndex].pitchShift = semitones
    }

    /// Set playback rate for a channel (time stretch without pitch change).
    ///
    /// - Parameters:
    ///   - channelIndex: Channel index.
    ///   - rate: Playback rate (0.25 to 4.0; 1.0 = normal).
    public func setRate(channel channelIndex: Int, rate: Float) {
        guard channelIndex >= 0 && channelIndex < channels.count else { return }
        channels[channelIndex].rate = max(0.25, min(4.0, rate))
    }

    /// Set the playback rate to match a target BPM given the source BPM.
    ///
    /// - Parameters:
    ///   - channelIndex: Channel index.
    ///   - sourceBPM: The original BPM of the loaded sample.
    ///   - targetBPM: The desired playback BPM.
    public func matchBPM(channel channelIndex: Int, sourceBPM: Double, targetBPM: Double) {
        guard sourceBPM > 0 else { return }
        let rate = Float(targetBPM / sourceBPM)
        setRate(channel: channelIndex, rate: rate)
    }

    // MARK: - Channel Info

    /// Get information about a specific channel.
    public func channelInfo(_ channelIndex: Int) -> PlayerChannelInfo? {
        guard channelIndex >= 0 && channelIndex < channels.count else { return nil }
        return channels[channelIndex].info
    }

    /// Get information about all channels.
    public func allChannelInfo() -> [PlayerChannelInfo] {
        channels.map { $0.info }
    }

    /// Find the first available (idle or stopped) channel.
    public func firstAvailableChannel() -> Int? {
        channels.first(where: { $0.state == .idle || $0.state == .stopped })?.index
    }

    // MARK: - Crossfade

    /// Perform a crossfade-out on a channel.
    private func performCrossfadeOut(channel: PlayerChannel) {
        let steps = 20
        let stepDuration = configuration.crossfadeDuration / Double(steps)
        let originalVolume = channel.volume

        // Ramp volume down over the crossfade duration
        for step in 0..<steps {
            let delay = stepDuration * Double(step)
            let targetVolume = originalVolume * Float(1.0 - Double(step) / Double(steps))
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                channel.mixerNode.outputVolume = targetVolume
            }
        }

        // Stop after crossfade completes
        DispatchQueue.main.asyncAfter(deadline: .now() + configuration.crossfadeDuration) {
            channel.playerNode.stop()
            channel.mixerNode.outputVolume = originalVolume
            channel.state = .stopped
        }
    }
}

// MARK: - Audio Engine Error

/// Errors specific to the audio engine.
public enum AudioEngineError: Error, LocalizedError {
    case invalidChannel(Int)
    case engineNotRunning
    case fileLoadFailed(URL, Error)

    public var errorDescription: String? {
        switch self {
        case .invalidChannel(let index):
            return "Invalid channel index: \(index)"
        case .engineNotRunning:
            return "Audio engine is not running."
        case .fileLoadFailed(let url, let error):
            return "Failed to load audio file at \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }
}
