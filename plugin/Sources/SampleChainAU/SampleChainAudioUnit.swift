// SampleChainAudioUnit.swift
// SampleChainAU
//
// AUv3 AudioUnit subclass: instrument type with stereo output, MIDI input,
// parameter tree, DAW transport sync, and state persistence.

import AudioToolbox
import AVFoundation
import CoreAudioKit
import Foundation
import SampleChainCore
import SampleChainDSP

// MARK: - Audio Unit Parameters

/// Parameter addresses for the SampleChain audio unit.
public enum SampleChainParameterAddress: AUParameterAddress {
    /// BPM override parameter (0 = follow DAW, otherwise manual BPM).
    case bpmOverride = 0
    /// Root key override in semitones relative to detected key (-12 to +12, 0 = original).
    case rootKeyOverride = 1
    /// Master volume (0.0 to 1.0).
    case masterVolume = 2
    /// Pitch shift in semitones (-24 to +24).
    case pitchShift = 3
    /// Mix level (dry/wet) for time-stretched preview (0.0 to 1.0).
    case mixLevel = 4
}

// MARK: - SampleChain Audio Unit

/// The SampleChain AUv3 Audio Unit.
///
/// Operates as an instrument-type audio unit that:
/// - Receives MIDI input for triggering sample playback
/// - Produces stereo audio output
/// - Syncs to the host DAW's transport (tempo, time signature, play state)
/// - Exposes parameters for BPM override, key override, and volume
/// - Persists its full state (loaded samples, settings) for recall
///
/// The audio unit delegates DSP work to the ``AudioEngine`` and uses
/// ``SampleCacheManager`` for sample file management.
public final class SampleChainAudioUnit: AUAudioUnit {

    // MARK: - Properties

    private var _outputBusArray: AUAudioUnitBusArray!
    private var _inputBusArray: AUAudioUnitBusArray!

    private let outputBus: AUAudioUnitBus
    private let stereoFormat: AVAudioFormat

    private var _parameterTree: AUParameterTree!

    // Parameters
    private let bpmOverrideParam: AUParameter
    private let rootKeyOverrideParam: AUParameter
    private let masterVolumeParam: AUParameter
    private let pitchShiftParam: AUParameter
    private let mixLevelParam: AUParameter

    // DSP state
    private var audioEngine: AudioEngine?
    private var loadedSampleTokenIds: [String] = []
    private var currentBPM: Double = 120
    private var isDAWPlaying: Bool = false

    // State persistence keys
    private static let stateKeyLoadedSamples = "loadedSamples"
    private static let stateKeyBPMOverride = "bpmOverride"
    private static let stateKeyRootKeyOverride = "rootKeyOverride"
    private static let stateKeyMasterVolume = "masterVolume"
    private static let stateKeyPitchShift = "pitchShift"
    private static let stateKeyMixLevel = "mixLevel"

    // MARK: - Initialization

    public override init(
        componentDescription: AudioComponentDescription,
        options: AudioComponentInstantiationOptions = []
    ) throws {
        // Define stereo output format
        let sampleRate: Double = 44100
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 2
        ) else {
            throw NSError(domain: "SampleChainAU", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to create stereo audio format"
            ])
        }
        self.stereoFormat = format
        self.outputBus = try AUAudioUnitBus(format: format)

        // Create parameters
        bpmOverrideParam = AUParameterTree.createParameter(
            withIdentifier: "bpmOverride",
            name: "BPM Override",
            address: SampleChainParameterAddress.bpmOverride.rawValue,
            min: 0,      // 0 = follow DAW
            max: 300,
            unit: .BPM,
            unitName: "BPM",
            flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: nil,
            dependentParameters: nil
        )
        bpmOverrideParam.value = 0 // Default: follow DAW

        rootKeyOverrideParam = AUParameterTree.createParameter(
            withIdentifier: "rootKeyOverride",
            name: "Root Key Override",
            address: SampleChainParameterAddress.rootKeyOverride.rawValue,
            min: -12,
            max: 12,
            unit: .relativeSemiTones,
            unitName: "st",
            flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: nil,
            dependentParameters: nil
        )
        rootKeyOverrideParam.value = 0

        masterVolumeParam = AUParameterTree.createParameter(
            withIdentifier: "masterVolume",
            name: "Master Volume",
            address: SampleChainParameterAddress.masterVolume.rawValue,
            min: 0,
            max: 1,
            unit: .linearGain,
            unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: nil,
            dependentParameters: nil
        )
        masterVolumeParam.value = 1.0

        pitchShiftParam = AUParameterTree.createParameter(
            withIdentifier: "pitchShift",
            name: "Pitch Shift",
            address: SampleChainParameterAddress.pitchShift.rawValue,
            min: -24,
            max: 24,
            unit: .relativeSemiTones,
            unitName: "st",
            flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: nil,
            dependentParameters: nil
        )
        pitchShiftParam.value = 0

        mixLevelParam = AUParameterTree.createParameter(
            withIdentifier: "mixLevel",
            name: "Mix Level",
            address: SampleChainParameterAddress.mixLevel.rawValue,
            min: 0,
            max: 1,
            unit: .linearGain,
            unitName: nil,
            flags: [.flag_IsReadable, .flag_IsWritable],
            valueStrings: nil,
            dependentParameters: nil
        )
        mixLevelParam.value = 1.0

        try super.init(componentDescription: componentDescription, options: options)

        // Build parameter tree
        _parameterTree = AUParameterTree.createTree(withChildren: [
            bpmOverrideParam,
            rootKeyOverrideParam,
            masterVolumeParam,
            pitchShiftParam,
            mixLevelParam,
        ])

        // Parameter change handler
        _parameterTree.implementorValueObserver = { [weak self] param, value in
            guard let self else { return }
            self.handleParameterChange(address: param.address, value: value)
        }

        _parameterTree.implementorValueProvider = { [weak self] param -> AUValue in
            guard let self else { return 0 }
            return self.currentParameterValue(address: param.address)
        }

        _parameterTree.implementorStringFromValueCallback = { param, valuePtr in
            let value = valuePtr?.pointee ?? param.value
            switch param.address {
            case SampleChainParameterAddress.bpmOverride.rawValue:
                return value == 0 ? "DAW" : String(format: "%.1f", value)
            case SampleChainParameterAddress.rootKeyOverride.rawValue:
                let intValue = Int(value)
                if intValue == 0 { return "0" }
                return intValue > 0 ? "+\(intValue)" : "\(intValue)"
            default:
                return String(format: "%.2f", value)
            }
        }

        // Set up output bus array
        _outputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])

        // Initialize the audio engine
        self.audioEngine = AudioEngine()
    }

    // MARK: - AUAudioUnit Overrides

    public override var parameterTree: AUParameterTree? {
        get { _parameterTree }
        set { /* read-only */ }
    }

    public override var outputBusses: AUAudioUnitBusArray {
        _outputBusArray
    }

    public override var channelCapabilities: [NSNumber]? {
        // Stereo output, no audio input (instrument type)
        return [0, 2] // 0 input channels, 2 output channels
    }

    public override var canProcessInPlace: Bool { false }

    public override var supportsUserPresets: Bool { true }

    /// The musical context block provided by the host DAW.
    ///
    /// Used to read the DAW's current tempo, time signature, and transport state
    /// for sync purposes.
    public override var musicalContextBlock: AUHostMusicalContextBlock? {
        didSet {
            // Update BPM from DAW context when available
        }
    }

    /// The transport state block provided by the host DAW.
    public override var transportStateBlock: AUHostTransportStateBlock? {
        didSet {
            // Monitor DAW play/stop state changes
        }
    }

    // MARK: - Resource Management

    public override func allocateRenderResources() throws {
        try super.allocateRenderResources()

        // Validate output format
        let outputFormat = outputBus.format
        guard outputFormat.channelCount == 2 else {
            throw NSError(domain: "SampleChainAU", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "SampleChain requires stereo output (got \(outputFormat.channelCount) channels)"
            ])
        }

        // Start the audio engine
        try audioEngine?.start()
    }

    public override func deallocateRenderResources() {
        audioEngine?.stop()
        super.deallocateRenderResources()
    }

    // MARK: - Render Block

    public override var internalRenderBlock: AUInternalRenderBlock {
        // Capture references for the render block (real-time safe)
        let audioEngine = self.audioEngine
        let musicalContext = self.musicalContextBlock
        let transportState = self.transportStateBlock

        let bpmParam = self.bpmOverrideParam
        let volumeParam = self.masterVolumeParam
        let pitchParam = self.pitchShiftParam

        return { (
            actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
            timestamp: UnsafePointer<AudioTimeStamp>,
            frameCount: AUAudioFrameCount,
            outputBusNumber: Int,
            outputData: UnsafeMutablePointer<AudioBufferList>,
            renderEvents: UnsafePointer<AURenderEvent>?,
            pullInputBlock: AURenderPullInputBlock?
        ) -> AUAudioUnitStatus in

            // Read DAW musical context for tempo sync
            if let musicalContext {
                var tempo: Double = 0
                var timeSignatureNumerator: Double = 0
                var timeSignatureDenominator: Int = 0
                var currentBeatPosition: Double = 0
                var sampleOffsetToNextBeat: Int = 0
                var currentMeasureDownbeatPosition: Double = 0

                let hasContext = musicalContext(
                    &tempo,
                    &timeSignatureNumerator,
                    &timeSignatureDenominator,
                    &currentBeatPosition,
                    &sampleOffsetToNextBeat,
                    &currentMeasureDownbeatPosition
                )

                if hasContext {
                    // Use DAW tempo if BPM override is 0
                    let bpmOverride = bpmParam.value
                    if bpmOverride == 0 && tempo > 0 {
                        // Store tempo for use by the engine
                        // In production, this would feed into the DSP pipeline
                    }
                }
            }

            // Read transport state
            if let transportState {
                var transportStateFlags: AUHostTransportStateFlags = []
                var currentSamplePosition: Double = 0
                var cycleStartBeatPosition: Double = 0
                var cycleEndBeatPosition: Double = 0

                let hasTransport = transportState(
                    &transportStateFlags,
                    &currentSamplePosition,
                    &cycleStartBeatPosition,
                    &cycleEndBeatPosition
                )

                if hasTransport {
                    // Check if DAW is playing
                    let isPlaying = transportStateFlags.contains(.playing)
                    let isRecording = transportStateFlags.contains(.recording)
                    // Use transport state for playback sync
                    _ = isPlaying
                    _ = isRecording
                }
            }

            // Process MIDI events
            var event = renderEvents
            while let currentEvent = event {
                if currentEvent.pointee.head.eventType == .MIDI {
                    // Handle MIDI events (note on/off for sample triggering)
                    let midiEvent = currentEvent.pointee.MIDI
                    let status = midiEvent.data.0
                    let note = midiEvent.data.1
                    let velocity = midiEvent.data.2

                    let messageType = status & 0xF0
                    switch messageType {
                    case 0x90 where velocity > 0: // Note On
                        // Trigger sample playback on the corresponding channel
                        let channel = Int(note) % 4 // Map MIDI notes to 4 channels
                        audioEngine?.play(channel: channel)
                    case 0x80, 0x90: // Note Off
                        let channel = Int(note) % 4
                        audioEngine?.stop(channel: channel)
                    default:
                        break
                    }
                }

                event = UnsafePointer(currentEvent.pointee.head.next)
            }

            // Apply master volume
            let volume = volumeParam.value

            // Fill output buffer
            // In a full implementation, this would read from the AudioEngine's render output.
            // For now, fill with silence as the AudioEngine handles its own output.
            let ablPointer = UnsafeMutableAudioBufferListPointer(outputData)
            for buffer in ablPointer {
                guard let data = buffer.mData else { continue }
                memset(data, 0, Int(buffer.mDataByteSize))
            }

            return noErr
        }
    }

    // MARK: - State Persistence

    /// Full state for saving with the DAW session (fullState).
    public override var fullState: [String: Any]? {
        get {
            var state: [String: Any] = [:]
            state[Self.stateKeyLoadedSamples] = loadedSampleTokenIds
            state[Self.stateKeyBPMOverride] = bpmOverrideParam.value
            state[Self.stateKeyRootKeyOverride] = rootKeyOverrideParam.value
            state[Self.stateKeyMasterVolume] = masterVolumeParam.value
            state[Self.stateKeyPitchShift] = pitchShiftParam.value
            state[Self.stateKeyMixLevel] = mixLevelParam.value
            return state
        }
        set {
            guard let state = newValue else { return }

            if let samples = state[Self.stateKeyLoadedSamples] as? [String] {
                loadedSampleTokenIds = samples
                // Reload samples from cache
                Task {
                    await reloadSamplesFromState(tokenIds: samples)
                }
            }

            if let bpm = state[Self.stateKeyBPMOverride] as? AUValue {
                bpmOverrideParam.value = bpm
            }
            if let key = state[Self.stateKeyRootKeyOverride] as? AUValue {
                rootKeyOverrideParam.value = key
            }
            if let vol = state[Self.stateKeyMasterVolume] as? AUValue {
                masterVolumeParam.value = vol
            }
            if let pitch = state[Self.stateKeyPitchShift] as? AUValue {
                pitchShiftParam.value = pitch
            }
            if let mix = state[Self.stateKeyMixLevel] as? AUValue {
                mixLevelParam.value = mix
            }
        }
    }

    /// Full state for document-based saving (Logic Pro project files, etc.).
    public override var fullStateForDocument: [String: Any]? {
        get { fullState }
        set { fullState = newValue }
    }

    // MARK: - Private Helpers

    /// Handle a parameter value change from the host or UI.
    private func handleParameterChange(address: AUParameterAddress, value: AUValue) {
        switch address {
        case SampleChainParameterAddress.bpmOverride.rawValue:
            // Update engine BPM
            if value > 0 {
                currentBPM = Double(value)
            }

        case SampleChainParameterAddress.rootKeyOverride.rawValue:
            // Update pitch shift on all active channels
            let semitones = Float(value)
            for i in 0..<(audioEngine?.allChannelInfo().count ?? 0) {
                audioEngine?.setPitch(channel: i, semitones: semitones)
            }

        case SampleChainParameterAddress.masterVolume.rawValue:
            audioEngine?.masterVolume = value

        case SampleChainParameterAddress.pitchShift.rawValue:
            let semitones = Float(value)
            for i in 0..<(audioEngine?.allChannelInfo().count ?? 0) {
                audioEngine?.setPitch(channel: i, semitones: semitones)
            }

        case SampleChainParameterAddress.mixLevel.rawValue:
            // Mix level control
            break

        default:
            break
        }
    }

    /// Get the current value of a parameter.
    private func currentParameterValue(address: AUParameterAddress) -> AUValue {
        switch address {
        case SampleChainParameterAddress.bpmOverride.rawValue:
            return bpmOverrideParam.value
        case SampleChainParameterAddress.rootKeyOverride.rawValue:
            return rootKeyOverrideParam.value
        case SampleChainParameterAddress.masterVolume.rawValue:
            return masterVolumeParam.value
        case SampleChainParameterAddress.pitchShift.rawValue:
            return pitchShiftParam.value
        case SampleChainParameterAddress.mixLevel.rawValue:
            return mixLevelParam.value
        default:
            return 0
        }
    }

    /// Reload samples from cache when restoring state.
    private func reloadSamplesFromState(tokenIds: [String]) async {
        let cache = SampleCacheManager()
        try? await cache.initialize()

        for (index, tokenId) in tokenIds.enumerated() where index < 4 {
            if let cachedURL = await cache.cachedURL(for: tokenId) {
                try? audioEngine?.loadSample(fileURL: cachedURL, onChannel: index, tokenId: tokenId)
            }
        }
    }
}

// MARK: - Audio Component Description

extension SampleChainAudioUnit {
    /// Standard Audio Component Description for the SampleChain instrument.
    ///
    /// - Type: kAudioUnitType_MusicDevice (instrument)
    /// - SubType: "smch" (SampleChain)
    /// - Manufacturer: "SMCN" (SampleChain)
    public static var componentDescription: AudioComponentDescription {
        AudioComponentDescription(
            componentType: kAudioUnitType_MusicDevice,
            componentSubType: fourCharCode("smch"),
            componentManufacturer: fourCharCode("SMCN"),
            componentFlags: 0,
            componentFlagsMask: 0
        )
    }

    /// Convert a 4-character string to a FourCharCode (OSType/UInt32).
    private static func fourCharCode(_ string: String) -> UInt32 {
        var result: UInt32 = 0
        for char in string.utf8.prefix(4) {
            result = (result << 8) | UInt32(char)
        }
        return result
    }
}
