// Endpoints.swift
// SampleChainCore
//
// API endpoint definitions for the SampleChain backend.

import Foundation

/// Centralized endpoint definitions for all SampleChain API calls.
///
/// Each static method returns a fully-typed ``APIRequest`` with the expected
/// response type, making it impossible to accidentally decode the wrong type.
///
/// Usage:
/// ```swift
/// let page = try await apiClient.execute(Endpoints.browseSamples(page: 1, filter: filter))
/// ```
public enum Endpoints {

    // MARK: - Samples

    /// Browse samples with optional filtering and pagination.
    public static func browseSamples(
        page: Int = 1,
        pageSize: Int = 20,
        filter: SampleFilter? = nil,
        sortBy: SampleSortField = .newest
    ) -> APIRequest<PaginatedResponse<Sample>> {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "page_size", value: "\(pageSize)"),
            URLQueryItem(name: "sort_by", value: sortBy.rawValue),
        ]

        if let filter {
            if !filter.genres.isEmpty {
                queryItems.append(URLQueryItem(name: "genres", value: filter.genres.map(\.rawValue).joined(separator: ",")))
            }
            if !filter.sampleTypes.isEmpty {
                queryItems.append(URLQueryItem(name: "sample_types", value: filter.sampleTypes.map(\.rawValue).joined(separator: ",")))
            }
            if let bpmRange = filter.bpmRange {
                queryItems.append(URLQueryItem(name: "bpm_min", value: "\(bpmRange.lowerBound)"))
                queryItems.append(URLQueryItem(name: "bpm_max", value: "\(bpmRange.upperBound)"))
            }
            if let key = filter.musicalKey {
                queryItems.append(URLQueryItem(name: "key_root", value: key.root.rawValue))
                queryItems.append(URLQueryItem(name: "key_quality", value: key.quality.rawValue))
            }
            if !filter.licenseTiers.isEmpty {
                queryItems.append(URLQueryItem(name: "license_tiers", value: filter.licenseTiers.map(\.rawValue).joined(separator: ",")))
            }
            if filter.freeOnly {
                queryItems.append(URLQueryItem(name: "free_only", value: "true"))
            }
            if let creator = filter.creatorAddress {
                queryItems.append(URLQueryItem(name: "creator", value: creator))
            }
        }

        return APIRequest(
            path: "/samples",
            method: .get,
            queryItems: queryItems
        )
    }

    /// Full-text search for samples.
    public static func searchSamples(
        query: String,
        page: Int = 1,
        pageSize: Int = 20
    ) -> APIRequest<PaginatedResponse<Sample>> {
        APIRequest(
            path: "/samples/search",
            method: .get,
            queryItems: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "page_size", value: "\(pageSize)"),
            ]
        )
    }

    /// Fetch a single sample by its on-chain token ID.
    public static func getSample(tokenId: String) -> APIRequest<Sample> {
        APIRequest(path: "/samples/\(tokenId)")
    }

    /// Fetch the audio stream URL for a sample (may be signed/temporary).
    public static func getSampleAudioURL(tokenId: String) -> APIRequest<AudioURLResponse> {
        APIRequest(path: "/samples/\(tokenId)/audio")
    }

    /// Upload a new sample audio file and metadata for minting.
    public static func createSample(metadata: CreateSampleRequest) -> APIRequest<Sample> {
        APIRequest(
            path: "/samples",
            method: .post,
            body: metadata,
            requiresAuth: true
        )
    }

    // MARK: - Creators

    /// Fetch a creator profile by wallet address.
    public static func getCreator(address: String) -> APIRequest<Creator> {
        APIRequest(path: "/creators/\(address)")
    }

    /// Fetch samples by a specific creator.
    public static func getCreatorSamples(
        address: String,
        page: Int = 1,
        pageSize: Int = 20
    ) -> APIRequest<PaginatedResponse<Sample>> {
        APIRequest(
            path: "/creators/\(address)/samples",
            queryItems: [
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "page_size", value: "\(pageSize)"),
            ]
        )
    }

    /// Update the authenticated creator's profile.
    public static func updateCreatorProfile(update: UpdateCreatorRequest) -> APIRequest<Creator> {
        APIRequest(
            path: "/creators/me",
            method: .patch,
            body: update,
            requiresAuth: true
        )
    }

    // MARK: - Library

    /// Fetch the authenticated user's owned samples.
    public static func getLibrary(
        page: Int = 1,
        pageSize: Int = 50
    ) -> APIRequest<PaginatedResponse<Sample>> {
        APIRequest(
            path: "/library",
            queryItems: [
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "page_size", value: "\(pageSize)"),
            ],
            requiresAuth: true
        )
    }

    /// Fetch the user's favorite samples.
    public static func getFavorites(
        page: Int = 1,
        pageSize: Int = 50
    ) -> APIRequest<PaginatedResponse<Sample>> {
        APIRequest(
            path: "/library/favorites",
            queryItems: [
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "page_size", value: "\(pageSize)"),
            ],
            requiresAuth: true
        )
    }

    /// Add a sample to favorites.
    public static func addFavorite(tokenId: String) -> APIRequest<EmptyResponse> {
        APIRequest(
            path: "/library/favorites/\(tokenId)",
            method: .put,
            requiresAuth: true
        )
    }

    /// Remove a sample from favorites.
    public static func removeFavorite(tokenId: String) -> APIRequest<EmptyResponse> {
        APIRequest(
            path: "/library/favorites/\(tokenId)",
            method: .delete,
            requiresAuth: true
        )
    }

    // MARK: - Authentication

    /// Request a SIWE nonce for the given wallet address.
    public static func requestNonce(address: String) -> APIRequest<NonceResponse> {
        APIRequest(
            path: "/auth/nonce",
            method: .post,
            body: NonceRequest(address: address)
        )
    }

    /// Verify a signed SIWE message and obtain a JWT.
    public static func verifySIWE(message: String, signature: String) -> APIRequest<AuthTokenResponse> {
        APIRequest(
            path: "/auth/verify",
            method: .post,
            body: VerifySIWERequest(message: message, signature: signature)
        )
    }

    /// Refresh an expiring JWT.
    public static func refreshToken(refreshToken: String) -> APIRequest<AuthTokenResponse> {
        APIRequest(
            path: "/auth/refresh",
            method: .post,
            body: RefreshTokenRequest(refreshToken: refreshToken)
        )
    }

    // MARK: - Wallet / Transactions

    /// Fetch transaction history for the authenticated wallet.
    public static func getTransactions(
        page: Int = 1,
        pageSize: Int = 50
    ) -> APIRequest<PaginatedResponse<Transaction>> {
        APIRequest(
            path: "/wallet/transactions",
            queryItems: [
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "page_size", value: "\(pageSize)"),
            ],
            requiresAuth: true
        )
    }

    /// Fetch creator earnings dashboard data.
    public static func getEarnings() -> APIRequest<CreatorEarningsSnapshot> {
        APIRequest(
            path: "/wallet/earnings",
            requiresAuth: true
        )
    }
}

// MARK: - Sort Fields

/// Available sort fields for sample browsing.
public enum SampleSortField: String, CaseIterable, Sendable {
    case newest = "newest"
    case oldest = "oldest"
    case priceAsc = "price_asc"
    case priceDesc = "price_desc"
    case bpmAsc = "bpm_asc"
    case bpmDesc = "bpm_desc"
    case popular = "popular"

    public var displayName: String {
        switch self {
        case .newest: return "Newest"
        case .oldest: return "Oldest"
        case .priceAsc: return "Price: Low to High"
        case .priceDesc: return "Price: High to Low"
        case .bpmAsc: return "BPM: Low to High"
        case .bpmDesc: return "BPM: High to Low"
        case .popular: return "Most Popular"
        }
    }
}

// MARK: - Request / Response DTOs

/// Request body for creating a new sample.
public struct CreateSampleRequest: Codable, Sendable {
    public let title: String
    public let description: String?
    public let genres: [Genre]
    public let sampleType: SampleType
    public let bpm: Double?
    public let musicalKey: MusicalKey?
    public let licenseTier: LicenseTier
    public let price: Decimal
    public let editionCount: Int
    /// IPFS CID of the uploaded audio file.
    public let audioCid: String
    /// Optional IPFS CID for cover art.
    public let coverArtCid: String?

    public init(
        title: String,
        description: String? = nil,
        genres: [Genre] = [],
        sampleType: SampleType,
        bpm: Double? = nil,
        musicalKey: MusicalKey? = nil,
        licenseTier: LicenseTier,
        price: Decimal,
        editionCount: Int,
        audioCid: String,
        coverArtCid: String? = nil
    ) {
        self.title = title
        self.description = description
        self.genres = genres
        self.sampleType = sampleType
        self.bpm = bpm
        self.musicalKey = musicalKey
        self.licenseTier = licenseTier
        self.price = price
        self.editionCount = editionCount
        self.audioCid = audioCid
        self.coverArtCid = coverArtCid
    }
}

/// Request body for updating a creator profile.
public struct UpdateCreatorRequest: Codable, Sendable {
    public let displayName: String?
    public let bio: String?
    public let avatarCid: String?
    public let websiteURL: URL?
    public let socialLinks: SocialLinks?

    public init(
        displayName: String? = nil,
        bio: String? = nil,
        avatarCid: String? = nil,
        websiteURL: URL? = nil,
        socialLinks: SocialLinks? = nil
    ) {
        self.displayName = displayName
        self.bio = bio
        self.avatarCid = avatarCid
        self.websiteURL = websiteURL
        self.socialLinks = socialLinks
    }
}

/// Response containing an audio streaming URL.
public struct AudioURLResponse: Codable, Sendable {
    public let url: URL
    public let expiresAt: Date
}

/// Request body for nonce generation.
public struct NonceRequest: Codable, Sendable {
    public let address: String
}

/// Response containing a SIWE nonce.
public struct NonceResponse: Codable, Sendable {
    public let nonce: String
    public let expiresAt: Date
}

/// Request body for SIWE verification.
public struct VerifySIWERequest: Codable, Sendable {
    public let message: String
    public let signature: String
}

/// Response containing JWT tokens after authentication.
public struct AuthTokenResponse: Codable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresIn: Int
}

/// Request body for token refresh.
public struct RefreshTokenRequest: Codable, Sendable {
    public let refreshToken: String
}
