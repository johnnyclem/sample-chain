// Sample.swift
// SampleChainCore
//
// Core data model representing an on-chain audio sample NFT with full metadata.

import Foundation

// MARK: - Musical Key

/// Represents the twelve chromatic pitch classes used for key detection and transposition.
public enum PitchClass: String, Codable, CaseIterable, Sendable {
    case c = "C"
    case cSharp = "C#"
    case d = "D"
    case dSharp = "D#"
    case e = "E"
    case f = "F"
    case fSharp = "F#"
    case g = "G"
    case gSharp = "G#"
    case a = "A"
    case aSharp = "A#"
    case b = "B"

    /// Semitone index (C = 0, C# = 1, ..., B = 11).
    public var semitoneIndex: Int {
        switch self {
        case .c: return 0
        case .cSharp: return 1
        case .d: return 2
        case .dSharp: return 3
        case .e: return 4
        case .f: return 5
        case .fSharp: return 6
        case .g: return 7
        case .gSharp: return 8
        case .a: return 9
        case .aSharp: return 10
        case .b: return 11
        }
    }
}

/// Scale quality: major or minor.
public enum ScaleQuality: String, Codable, Sendable {
    case major = "major"
    case minor = "minor"
}

/// A musical key consisting of a root pitch class and quality (major/minor).
public struct MusicalKey: Codable, Equatable, Sendable, CustomStringConvertible {
    public let root: PitchClass
    public let quality: ScaleQuality

    public init(root: PitchClass, quality: ScaleQuality) {
        self.root = root
        self.quality = quality
    }

    public var description: String {
        "\(root.rawValue) \(quality.rawValue)"
    }
}

// MARK: - Sample Type

/// Classification of the audio sample by its musical function.
public enum SampleType: String, Codable, CaseIterable, Sendable {
    case loop = "loop"
    case oneShot = "one_shot"
    case drumKit = "drum_kit"
    case vocal = "vocal"
    case foley = "foley"
    case synth = "synth"
    case bass = "bass"
    case pad = "pad"
    case lead = "lead"
    case fx = "fx"
    case full = "full"

    public var displayName: String {
        switch self {
        case .loop: return "Loop"
        case .oneShot: return "One Shot"
        case .drumKit: return "Drum Kit"
        case .vocal: return "Vocal"
        case .foley: return "Foley"
        case .synth: return "Synth"
        case .bass: return "Bass"
        case .pad: return "Pad"
        case .lead: return "Lead"
        case .fx: return "FX"
        case .full: return "Full Track"
        }
    }
}

// MARK: - License Tier

/// The licensing terms under which a sample can be used.
public enum LicenseTier: String, Codable, CaseIterable, Sendable {
    /// Personal/non-commercial use only.
    case personal = "personal"
    /// Commercial use with attribution required.
    case commercial = "commercial"
    /// Full exclusive rights transfer; the buyer becomes sole licensee.
    case exclusive = "exclusive"
    /// Creative Commons Zero -- public domain dedication.
    case cc0 = "cc0"

    public var displayName: String {
        switch self {
        case .personal: return "Personal"
        case .commercial: return "Commercial"
        case .exclusive: return "Exclusive"
        case .cc0: return "CC0 (Public Domain)"
        }
    }
}

// MARK: - Genre

/// Genre tags for sample discovery and filtering.
public enum Genre: String, Codable, CaseIterable, Sendable {
    case hiphop = "hiphop"
    case electronic = "electronic"
    case house = "house"
    case techno = "techno"
    case dnb = "dnb"
    case ambient = "ambient"
    case pop = "pop"
    case rnb = "rnb"
    case jazz = "jazz"
    case classical = "classical"
    case rock = "rock"
    case world = "world"
    case experimental = "experimental"
    case other = "other"

    public var displayName: String {
        switch self {
        case .hiphop: return "Hip-Hop"
        case .electronic: return "Electronic"
        case .house: return "House"
        case .techno: return "Techno"
        case .dnb: return "Drum & Bass"
        case .ambient: return "Ambient"
        case .pop: return "Pop"
        case .rnb: return "R&B"
        case .jazz: return "Jazz"
        case .classical: return "Classical"
        case .rock: return "Rock"
        case .world: return "World"
        case .experimental: return "Experimental"
        case .other: return "Other"
        }
    }
}

// MARK: - Waveform Data

/// Pre-computed waveform peak data for efficient visualization.
public struct WaveformData: Codable, Equatable, Sendable {
    /// Normalized peak amplitude values in range [0, 1], one per display column.
    public let peaks: [Float]
    /// Duration of the source audio in seconds.
    public let durationSeconds: Double
    /// Sample rate of the source audio.
    public let sampleRate: Double

    public init(peaks: [Float], durationSeconds: Double, sampleRate: Double) {
        self.peaks = peaks
        self.durationSeconds = durationSeconds
        self.sampleRate = sampleRate
    }
}

// MARK: - Sample

/// Core model representing an on-chain audio sample NFT.
///
/// Each ``Sample`` corresponds to a minted NFT on the SampleChain smart contract.
/// It carries all metadata needed for browsing, playback, purchase, and DAW integration.
public struct Sample: Identifiable, Codable, Equatable, Sendable {
    // MARK: On-chain identity

    /// Unique identifier derived from the NFT token ID.
    public let id: UUID
    /// The on-chain ERC-1155 token ID.
    public let tokenId: String
    /// Ethereum address of the original creator/minter.
    public let creator: String
    /// IPFS content identifier for the audio file.
    public let ipfsCid: String

    // MARK: Descriptive metadata

    /// Human-readable title.
    public let title: String
    /// Optional description or liner notes.
    public let description: String?
    /// Genre tags for discovery.
    public let genres: [Genre]
    /// Instrument/category classification.
    public let sampleType: SampleType

    // MARK: Musical metadata

    /// Tempo in beats per minute (auto-detected or user-specified).
    public let bpm: Double?
    /// Detected or user-specified musical key.
    public let musicalKey: MusicalKey?
    /// Duration of the audio in seconds.
    public let durationSeconds: Double

    // MARK: Commercial metadata

    /// License tier governing usage rights.
    public let licenseTier: LicenseTier
    /// Price in ETH (zero means free).
    public let price: Decimal
    /// Total number of editions minted (1 for 1/1, >1 for editions).
    public let editionCount: Int
    /// Number of editions remaining for purchase.
    public let editionsRemaining: Int

    // MARK: Visual / UI

    /// Pre-computed waveform visualization data.
    public let waveformData: WaveformData?
    /// Optional cover art IPFS CID.
    public let coverArtCid: String?

    // MARK: Timestamps

    /// When the sample was minted on-chain.
    public let mintedAt: Date
    /// When this record was last synced from the indexer.
    public let updatedAt: Date

    // MARK: Computed properties

    /// Whether this sample is free to acquire.
    public var isFree: Bool { price == 0 }

    /// Whether editions are still available for purchase.
    public var isAvailable: Bool { editionsRemaining > 0 }

    /// Gateway URL for streaming audio from IPFS.
    public var audioURL: URL? {
        URL(string: "https://ipfs.io/ipfs/\(ipfsCid)")
    }

    /// Gateway URL for cover art from IPFS, if present.
    public var coverArtURL: URL? {
        guard let cid = coverArtCid else { return nil }
        return URL(string: "https://ipfs.io/ipfs/\(cid)")
    }

    public init(
        id: UUID = UUID(),
        tokenId: String,
        creator: String,
        ipfsCid: String,
        title: String,
        description: String? = nil,
        genres: [Genre] = [],
        sampleType: SampleType,
        bpm: Double? = nil,
        musicalKey: MusicalKey? = nil,
        durationSeconds: Double,
        licenseTier: LicenseTier,
        price: Decimal,
        editionCount: Int,
        editionsRemaining: Int,
        waveformData: WaveformData? = nil,
        coverArtCid: String? = nil,
        mintedAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.tokenId = tokenId
        self.creator = creator
        self.ipfsCid = ipfsCid
        self.title = title
        self.description = description
        self.genres = genres
        self.sampleType = sampleType
        self.bpm = bpm
        self.musicalKey = musicalKey
        self.durationSeconds = durationSeconds
        self.licenseTier = licenseTier
        self.price = price
        self.editionCount = editionCount
        self.editionsRemaining = editionsRemaining
        self.waveformData = waveformData
        self.coverArtCid = coverArtCid
        self.mintedAt = mintedAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Sample Filter

/// Filter criteria for browsing and searching samples.
public struct SampleFilter: Equatable, Sendable {
    public var genres: Set<Genre>
    public var sampleTypes: Set<SampleType>
    public var bpmRange: ClosedRange<Double>?
    public var musicalKey: MusicalKey?
    public var licenseTiers: Set<LicenseTier>
    public var freeOnly: Bool
    public var creatorAddress: String?
    public var searchQuery: String?

    public init(
        genres: Set<Genre> = [],
        sampleTypes: Set<SampleType> = [],
        bpmRange: ClosedRange<Double>? = nil,
        musicalKey: MusicalKey? = nil,
        licenseTiers: Set<LicenseTier> = [],
        freeOnly: Bool = false,
        creatorAddress: String? = nil,
        searchQuery: String? = nil
    ) {
        self.genres = genres
        self.sampleTypes = sampleTypes
        self.bpmRange = bpmRange
        self.musicalKey = musicalKey
        self.licenseTiers = licenseTiers
        self.freeOnly = freeOnly
        self.creatorAddress = creatorAddress
        self.searchQuery = searchQuery
    }

    /// Returns `true` when no filter criteria are active.
    public var isEmpty: Bool {
        genres.isEmpty
            && sampleTypes.isEmpty
            && bpmRange == nil
            && musicalKey == nil
            && licenseTiers.isEmpty
            && !freeOnly
            && creatorAddress == nil
            && searchQuery == nil
    }
}
