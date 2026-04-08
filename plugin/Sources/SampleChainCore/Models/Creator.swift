// Creator.swift
// SampleChainCore
//
// Creator profile model representing a sample producer/artist on SampleChain.

import Foundation

// MARK: - Creator

/// Profile of a creator (producer/artist) on the SampleChain platform.
///
/// Creators are identified by their Ethereum wallet address. Profile metadata
/// is stored off-chain and linked via the backend API.
public struct Creator: Identifiable, Codable, Equatable, Sendable {
    /// Unique identifier (matches the backend database record ID).
    public let id: UUID
    /// Ethereum wallet address (0x-prefixed, checksummed).
    public let walletAddress: String
    /// Display name chosen by the creator.
    public let displayName: String
    /// Optional short biography.
    public let bio: String?
    /// IPFS CID for the creator's profile avatar image.
    public let avatarCid: String?
    /// Optional external website URL.
    public let websiteURL: URL?
    /// Optional social media links.
    public let socialLinks: SocialLinks?

    // MARK: Statistics

    /// Total number of samples minted by this creator.
    public let totalSamples: Int
    /// Total number of unique collectors who own this creator's samples.
    public let uniqueCollectors: Int
    /// Cumulative sales volume in ETH.
    public let totalVolumeETH: Decimal
    /// Whether the creator has been verified by the platform.
    public let isVerified: Bool

    // MARK: Timestamps

    /// When the creator profile was first created (first mint or registration).
    public let joinedAt: Date
    /// When the profile was last updated.
    public let updatedAt: Date

    // MARK: Computed

    /// Gateway URL for the avatar image, if available.
    public var avatarURL: URL? {
        guard let cid = avatarCid else { return nil }
        return URL(string: "https://ipfs.io/ipfs/\(cid)")
    }

    /// Shortened wallet address for display (e.g. "0xAbCd...1234").
    public var shortAddress: String {
        guard walletAddress.count > 10 else { return walletAddress }
        let prefix = walletAddress.prefix(6)
        let suffix = walletAddress.suffix(4)
        return "\(prefix)...\(suffix)"
    }

    public init(
        id: UUID = UUID(),
        walletAddress: String,
        displayName: String,
        bio: String? = nil,
        avatarCid: String? = nil,
        websiteURL: URL? = nil,
        socialLinks: SocialLinks? = nil,
        totalSamples: Int = 0,
        uniqueCollectors: Int = 0,
        totalVolumeETH: Decimal = 0,
        isVerified: Bool = false,
        joinedAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.walletAddress = walletAddress
        self.displayName = displayName
        self.bio = bio
        self.avatarCid = avatarCid
        self.websiteURL = websiteURL
        self.socialLinks = socialLinks
        self.totalSamples = totalSamples
        self.uniqueCollectors = uniqueCollectors
        self.totalVolumeETH = totalVolumeETH
        self.isVerified = isVerified
        self.joinedAt = joinedAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Social Links

/// Collection of social media profile links for a creator.
public struct SocialLinks: Codable, Equatable, Sendable {
    public let twitter: String?
    public let instagram: String?
    public let soundcloud: String?
    public let spotify: String?
    public let bandcamp: String?

    public init(
        twitter: String? = nil,
        instagram: String? = nil,
        soundcloud: String? = nil,
        spotify: String? = nil,
        bandcamp: String? = nil
    ) {
        self.twitter = twitter
        self.instagram = instagram
        self.soundcloud = soundcloud
        self.spotify = spotify
        self.bandcamp = bandcamp
    }
}

// MARK: - Creator Statistics Snapshot

/// A point-in-time snapshot of aggregated creator statistics for the earnings dashboard.
public struct CreatorEarningsSnapshot: Codable, Equatable, Sendable {
    /// Total lifetime earnings in ETH.
    public let totalEarningsETH: Decimal
    /// Earnings in the current calendar month.
    public let monthlyEarningsETH: Decimal
    /// Number of sales in the current calendar month.
    public let monthlySalesCount: Int
    /// Earnings from secondary-market royalties (lifetime).
    public let royaltyEarningsETH: Decimal
    /// Historical earnings data points for charting (date -> ETH amount).
    public let earningsHistory: [EarningsDataPoint]

    public init(
        totalEarningsETH: Decimal,
        monthlyEarningsETH: Decimal,
        monthlySalesCount: Int,
        royaltyEarningsETH: Decimal,
        earningsHistory: [EarningsDataPoint]
    ) {
        self.totalEarningsETH = totalEarningsETH
        self.monthlyEarningsETH = monthlyEarningsETH
        self.monthlySalesCount = monthlySalesCount
        self.royaltyEarningsETH = royaltyEarningsETH
        self.earningsHistory = earningsHistory
    }
}

/// A single data point in an earnings time series.
public struct EarningsDataPoint: Codable, Equatable, Sendable, Identifiable {
    public var id: Date { date }
    public let date: Date
    public let amountETH: Decimal

    public init(date: Date, amountETH: Decimal) {
        self.date = date
        self.amountETH = amountETH
    }
}
