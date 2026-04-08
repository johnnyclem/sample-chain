// SIWEAuth.swift
// SampleChainCore
//
// Sign In With Ethereum (SIWE / EIP-4361) authentication flow.

import Foundation

// MARK: - SIWE Message

/// A Sign In With Ethereum (EIP-4361) message to be signed by the user's wallet.
public struct SIWEMessage: Sendable {
    /// The domain requesting the signature (e.g. "samplechain.io").
    public let domain: String
    /// The Ethereum address performing the sign-in.
    public let address: String
    /// A human-readable statement describing what the user is signing.
    public let statement: String
    /// The URI of the requesting resource.
    public let uri: String
    /// EIP-155 Chain ID (e.g. 1 for mainnet, 8453 for Base).
    public let chainId: Int
    /// Server-generated nonce for replay protection.
    public let nonce: String
    /// ISO 8601 datetime string of when the message was issued.
    public let issuedAt: String
    /// ISO 8601 datetime string of when the message expires.
    public let expirationTime: String?
    /// Protocol version (always "1").
    public let version: String = "1"

    public init(
        domain: String,
        address: String,
        statement: String,
        uri: String,
        chainId: Int,
        nonce: String,
        issuedAt: String = ISO8601DateFormatter().string(from: Date()),
        expirationTime: String? = nil
    ) {
        self.domain = domain
        self.address = address
        self.statement = statement
        self.uri = uri
        self.chainId = chainId
        self.nonce = nonce
        self.issuedAt = issuedAt
        self.expirationTime = expirationTime
    }

    /// Formats the SIWE message according to EIP-4361 specification.
    ///
    /// The resulting string is what the user's wallet will display for signing.
    public func toMessage() -> String {
        var lines: [String] = []
        lines.append("\(domain) wants you to sign in with your Ethereum account:")
        lines.append(address)
        lines.append("")
        lines.append(statement)
        lines.append("")
        lines.append("URI: \(uri)")
        lines.append("Version: \(version)")
        lines.append("Chain ID: \(chainId)")
        lines.append("Nonce: \(nonce)")
        lines.append("Issued At: \(issuedAt)")

        if let expirationTime {
            lines.append("Expiration Time: \(expirationTime)")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Auth State

/// Represents the current authentication state.
public enum AuthState: Equatable, Sendable {
    /// User is not authenticated.
    case unauthenticated
    /// Authentication is in progress (nonce requested, awaiting wallet signature).
    case signingIn
    /// User is authenticated with a valid session.
    case authenticated(session: AuthSession)
    /// Authentication failed.
    case failed(error: String)
}

/// An authenticated session with JWT tokens.
public struct AuthSession: Codable, Equatable, Sendable {
    /// The JWT access token for API authentication.
    public let accessToken: String
    /// The refresh token for obtaining new access tokens.
    public let refreshToken: String
    /// When the access token expires.
    public let expiresAt: Date
    /// The authenticated wallet address.
    public let walletAddress: String

    public init(accessToken: String, refreshToken: String, expiresAt: Date, walletAddress: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.walletAddress = walletAddress
    }

    /// Whether the access token has expired.
    public var isExpired: Bool {
        Date() >= expiresAt
    }

    /// Whether the access token will expire within the given interval.
    public func willExpire(within interval: TimeInterval) -> Bool {
        Date().addingTimeInterval(interval) >= expiresAt
    }
}

// MARK: - Wallet Signer Protocol

/// Protocol for requesting a wallet signature.
///
/// Implementors bridge to the actual wallet connection (WalletConnect, injected provider, etc.).
public protocol WalletSigner: Sendable {
    /// Request the wallet to sign a personal message (eth_sign / personal_sign).
    ///
    /// - Parameters:
    ///   - message: The plaintext message to sign.
    ///   - address: The Ethereum address that should produce the signature.
    /// - Returns: The hex-encoded signature (0x-prefixed, 65 bytes: r + s + v).
    func signMessage(_ message: String, with address: String) async throws -> String
}

// MARK: - SIWE Auth Manager

/// Manages the Sign In With Ethereum authentication flow.
///
/// This actor coordinates between the backend API (nonce generation, signature verification)
/// and the wallet signer (user approval). It maintains the current auth state and handles
/// token refresh.
///
/// Flow:
/// 1. Request a nonce from the backend for the given wallet address.
/// 2. Construct a SIWE message embedding the nonce.
/// 3. Request the wallet to sign the message.
/// 4. Send the signed message to the backend for verification.
/// 5. Store the resulting JWT tokens.
///
/// Usage:
/// ```swift
/// let auth = SIWEAuthManager(apiClient: client, signer: walletConnectSigner)
/// try await auth.signIn(address: "0x...")
/// let token = try await auth.currentToken()
/// ```
public actor SIWEAuthManager: AuthTokenProvider {
    private let apiClient: APIClient
    private let signer: any WalletSigner
    private var session: AuthSession?
    private var refreshTask: Task<AuthSession, Error>?
    private let domain: String
    private let chainId: Int

    /// Keychain service identifier for storing the refresh token.
    private let keychainService = "io.samplechain.auth"

    public private(set) var state: AuthState = .unauthenticated

    public init(
        apiClient: APIClient,
        signer: any WalletSigner,
        domain: String = "samplechain.io",
        chainId: Int = 8453 // Base mainnet
    ) {
        self.apiClient = apiClient
        self.signer = signer
        self.domain = domain
        self.chainId = chainId
    }

    /// Perform the full SIWE sign-in flow.
    ///
    /// - Parameter address: The Ethereum wallet address to authenticate.
    /// - Throws: ``APIError`` or signing errors.
    public func signIn(address: String) async throws {
        state = .signingIn

        do {
            // Step 1: Request a nonce from the server
            let nonceResponse = try await apiClient.execute(Endpoints.requestNonce(address: address))

            // Step 2: Build the SIWE message
            let siweMessage = SIWEMessage(
                domain: domain,
                address: address,
                statement: "Sign in to SampleChain to browse, purchase, and manage your audio sample NFTs.",
                uri: "https://\(domain)",
                chainId: chainId,
                nonce: nonceResponse.nonce
            )

            let messageText = siweMessage.toMessage()

            // Step 3: Request wallet signature
            let signature = try await signer.signMessage(messageText, with: address)

            // Step 4: Verify with the backend
            let authResponse = try await apiClient.execute(
                Endpoints.verifySIWE(message: messageText, signature: signature)
            )

            // Step 5: Store the session
            let newSession = AuthSession(
                accessToken: authResponse.accessToken,
                refreshToken: authResponse.refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(authResponse.expiresIn)),
                walletAddress: address
            )
            self.session = newSession
            state = .authenticated(session: newSession)

            // Persist refresh token to keychain
            try? persistRefreshToken(authResponse.refreshToken, for: address)

        } catch {
            state = .failed(error: error.localizedDescription)
            throw error
        }
    }

    /// Sign out and clear the stored session.
    public func signOut() async {
        session = nil
        refreshTask?.cancel()
        refreshTask = nil
        state = .unauthenticated
        // Clear keychain
        clearPersistedRefreshToken()
    }

    /// Attempt to restore a session from a persisted refresh token.
    ///
    /// - Parameter address: The wallet address to restore the session for.
    /// - Returns: `true` if the session was successfully restored.
    public func restoreSession(for address: String) async -> Bool {
        guard let refreshToken = loadPersistedRefreshToken(for: address) else {
            return false
        }

        do {
            let authResponse = try await apiClient.execute(
                Endpoints.refreshToken(refreshToken: refreshToken)
            )
            let newSession = AuthSession(
                accessToken: authResponse.accessToken,
                refreshToken: authResponse.refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(authResponse.expiresIn)),
                walletAddress: address
            )
            self.session = newSession
            state = .authenticated(session: newSession)
            try? persistRefreshToken(authResponse.refreshToken, for: address)
            return true
        } catch {
            clearPersistedRefreshToken()
            state = .unauthenticated
            return false
        }
    }

    // MARK: - AuthTokenProvider

    /// Returns the current access token, refreshing if it's about to expire.
    public func currentToken() async throws -> String? {
        guard let session else { return nil }

        // If the token is still valid (with a 60-second buffer), return it
        if !session.willExpire(within: 60) {
            return session.accessToken
        }

        // Refresh the token
        return try await refreshSession().accessToken
    }

    /// Clear the stored token (called on 401 responses).
    public func clearToken() async {
        session = nil
        state = .unauthenticated
    }

    // MARK: - Token Refresh

    /// Refresh the session using the refresh token.
    ///
    /// Coalesces concurrent refresh requests to avoid multiple simultaneous refreshes.
    private func refreshSession() async throws -> AuthSession {
        // If a refresh is already in progress, wait for it
        if let existingTask = refreshTask {
            return try await existingTask.value
        }

        guard let currentSession = session else {
            throw APIError.unauthorized
        }

        let task = Task<AuthSession, Error> {
            let authResponse = try await apiClient.execute(
                Endpoints.refreshToken(refreshToken: currentSession.refreshToken)
            )
            return AuthSession(
                accessToken: authResponse.accessToken,
                refreshToken: authResponse.refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(authResponse.expiresIn)),
                walletAddress: currentSession.walletAddress
            )
        }

        refreshTask = task

        do {
            let newSession = try await task.value
            self.session = newSession
            self.state = .authenticated(session: newSession)
            self.refreshTask = nil
            try? persistRefreshToken(newSession.refreshToken, for: newSession.walletAddress)
            return newSession
        } catch {
            self.refreshTask = nil
            self.session = nil
            self.state = .unauthenticated
            clearPersistedRefreshToken()
            throw error
        }
    }

    // MARK: - Keychain Persistence (Simplified)

    /// Persist the refresh token to the keychain.
    private func persistRefreshToken(_ token: String, for address: String) throws {
        guard let data = token.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: address,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        // Delete any existing entry
        SecItemDelete(query as CFDictionary)
        // Add the new entry
        SecItemAdd(query as CFDictionary, nil)
    }

    /// Load a persisted refresh token from the keychain.
    private func loadPersistedRefreshToken(for address: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: address,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Remove the persisted refresh token from the keychain.
    private func clearPersistedRefreshToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
