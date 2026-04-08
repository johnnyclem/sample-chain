// Web3Service.swift
// SampleChainCore
//
// Ethereum interaction layer for reading contract state and sending transactions
// on the SampleChain smart contract.

import Foundation

// MARK: - Chain Configuration

/// Supported blockchain networks.
public enum Chain: Sendable {
    case baseMainnet
    case baseSepolia
    case localhost

    /// EIP-155 chain ID.
    public var chainId: Int {
        switch self {
        case .baseMainnet: return 8453
        case .baseSepolia: return 84532
        case .localhost: return 31337
        }
    }

    /// JSON-RPC endpoint URL.
    public var rpcURL: URL {
        switch self {
        case .baseMainnet:
            return URL(string: "https://mainnet.base.org")!
        case .baseSepolia:
            return URL(string: "https://sepolia.base.org")!
        case .localhost:
            return URL(string: "http://127.0.0.1:8545")!
        }
    }

    /// Block explorer base URL.
    public var explorerURL: URL {
        switch self {
        case .baseMainnet:
            return URL(string: "https://basescan.org")!
        case .baseSepolia:
            return URL(string: "https://sepolia.basescan.org")!
        case .localhost:
            return URL(string: "http://localhost:8545")!
        }
    }

    /// Human-readable name.
    public var displayName: String {
        switch self {
        case .baseMainnet: return "Base"
        case .baseSepolia: return "Base Sepolia (Testnet)"
        case .localhost: return "Local Development"
        }
    }
}

// MARK: - Contract Configuration

/// Configuration for the SampleChain smart contract.
public struct ContractConfiguration: Sendable {
    /// The deployed contract address.
    public let contractAddress: String
    /// The chain the contract is deployed on.
    public let chain: Chain

    public static let production = ContractConfiguration(
        contractAddress: "0x0000000000000000000000000000000000000000", // Placeholder
        chain: .baseMainnet
    )

    public static let testnet = ContractConfiguration(
        contractAddress: "0x0000000000000000000000000000000000000000", // Placeholder
        chain: .baseSepolia
    )

    public init(contractAddress: String, chain: Chain) {
        self.contractAddress = contractAddress
        self.chain = chain
    }
}

// MARK: - Web3 Error

/// Errors from the Web3 service layer.
public enum Web3Error: Error, LocalizedError, Sendable {
    case rpcError(code: Int, message: String)
    case contractCallFailed(method: String, reason: String)
    case transactionFailed(hash: String, reason: String)
    case encodingError(String)
    case decodingError(String)
    case insufficientFunds(required: String, available: String)
    case userRejected
    case networkError(Error)

    public var errorDescription: String? {
        switch self {
        case .rpcError(let code, let message):
            return "RPC error \(code): \(message)"
        case .contractCallFailed(let method, let reason):
            return "Contract call '\(method)' failed: \(reason)"
        case .transactionFailed(let hash, let reason):
            return "Transaction \(hash) failed: \(reason)"
        case .encodingError(let msg):
            return "ABI encoding error: \(msg)"
        case .decodingError(let msg):
            return "ABI decoding error: \(msg)"
        case .insufficientFunds(let required, let available):
            return "Insufficient funds. Required: \(required), Available: \(available)"
        case .userRejected:
            return "Transaction was rejected by the user."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Transaction Signer Protocol

/// Protocol for signing and sending Ethereum transactions.
///
/// Implementors bridge to the actual wallet (WalletConnect, hardware wallet, etc.).
public protocol TransactionSigner: Sendable {
    /// Send a transaction and return the transaction hash.
    ///
    /// - Parameter transaction: The transaction parameters.
    /// - Returns: The transaction hash (0x-prefixed hex string).
    func sendTransaction(_ transaction: EthTransaction) async throws -> String
}

/// Ethereum transaction parameters.
public struct EthTransaction: Sendable {
    public let from: String
    public let to: String
    public let data: String // Hex-encoded calldata
    public let value: String // Wei value as hex string
    public let gasLimit: String? // Optional gas limit as hex string

    public init(from: String, to: String, data: String, value: String = "0x0", gasLimit: String? = nil) {
        self.from = from
        self.to = to
        self.data = data
        self.value = value
        self.gasLimit = gasLimit
    }
}

// MARK: - On-Chain Sample Info

/// Sample information as stored in the smart contract.
public struct OnChainSampleInfo: Sendable {
    /// Token ID.
    public let tokenId: String
    /// Creator address.
    public let creator: String
    /// IPFS CID of the audio.
    public let ipfsCid: String
    /// Price in wei.
    public let priceWei: String
    /// Total supply of editions.
    public let totalSupply: Int
    /// Number of editions minted so far.
    public let mintedCount: Int
    /// Royalty percentage (basis points, e.g. 500 = 5%).
    public let royaltyBps: Int
    /// Whether the sample is active (not paused or burned).
    public let isActive: Bool

    public init(
        tokenId: String,
        creator: String,
        ipfsCid: String,
        priceWei: String,
        totalSupply: Int,
        mintedCount: Int,
        royaltyBps: Int,
        isActive: Bool
    ) {
        self.tokenId = tokenId
        self.creator = creator
        self.ipfsCid = ipfsCid
        self.priceWei = priceWei
        self.totalSupply = totalSupply
        self.mintedCount = mintedCount
        self.royaltyBps = royaltyBps
        self.isActive = isActive
    }
}

// MARK: - Web3 Service

/// Service for interacting with the SampleChain smart contract on Ethereum/Base.
///
/// Provides read-only contract calls via JSON-RPC and write operations via the
/// ``TransactionSigner`` protocol (which bridges to the user's wallet).
///
/// Usage:
/// ```swift
/// let web3 = Web3Service(configuration: .testnet, signer: walletConnectSigner)
/// let sampleInfo = try await web3.getSampleInfo(tokenId: "42")
/// let txHash = try await web3.purchaseSample(tokenId: "42", from: "0x...")
/// ```
public actor Web3Service {
    private let configuration: ContractConfiguration
    private let session: URLSession
    private var signer: (any TransactionSigner)?
    private var rpcRequestId: Int = 0

    public init(configuration: ContractConfiguration, signer: (any TransactionSigner)? = nil) {
        self.configuration = configuration
        self.session = URLSession.shared
        self.signer = signer
    }

    /// Set or update the transaction signer.
    public func setSigner(_ signer: any TransactionSigner) {
        self.signer = signer
    }

    // MARK: - Read Operations

    /// Get the ETH balance of an address.
    ///
    /// - Parameter address: Ethereum address (0x-prefixed).
    /// - Returns: Balance in wei as a hex string.
    public func getBalance(of address: String) async throws -> String {
        let result: String = try await rpcCall(method: "eth_getBalance", params: [address, "latest"])
        return result
    }

    /// Get the current block number.
    public func getBlockNumber() async throws -> Int {
        let result: String = try await rpcCall(method: "eth_blockNumber", params: [String]())
        guard let blockNumber = Int(result.dropFirst(2), radix: 16) else {
            throw Web3Error.decodingError("Invalid block number: \(result)")
        }
        return blockNumber
    }

    /// Read on-chain sample info from the contract.
    ///
    /// Calls `getSample(uint256)` on the SampleChain contract.
    ///
    /// - Parameter tokenId: The token ID to look up.
    /// - Returns: The on-chain sample information.
    public func getSampleInfo(tokenId: String) async throws -> OnChainSampleInfo {
        // Encode function call: getSample(uint256)
        // Function selector: keccak256("getSample(uint256)") = first 4 bytes
        let selector = "0x" + keccak256Selector("getSample(uint256)")
        let paddedTokenId = padLeft(tokenId, to: 64)
        let calldata = selector + paddedTokenId

        let result: String = try await ethCall(to: configuration.contractAddress, data: calldata)

        // Decode the ABI-encoded result
        // Expected: (address creator, string ipfsCid, uint256 priceWei, uint256 totalSupply,
        //            uint256 mintedCount, uint256 royaltyBps, bool isActive)
        return try decodeSampleInfo(tokenId: tokenId, hexData: result)
    }

    /// Check how many editions of a sample an address owns.
    ///
    /// Calls `balanceOf(address,uint256)` (ERC-1155).
    ///
    /// - Parameters:
    ///   - address: The owner address.
    ///   - tokenId: The token ID.
    /// - Returns: The number of editions owned.
    public func balanceOf(address: String, tokenId: String) async throws -> Int {
        let selector = "0x" + keccak256Selector("balanceOf(address,uint256)")
        let paddedAddress = padLeft(String(address.dropFirst(2)), to: 64)
        let paddedTokenId = padLeft(tokenId, to: 64)
        let calldata = selector + paddedAddress + paddedTokenId

        let result: String = try await ethCall(to: configuration.contractAddress, data: calldata)
        guard let balance = Int(result.dropFirst(2).prefix(64), radix: 16) else {
            throw Web3Error.decodingError("Invalid balance result: \(result)")
        }
        return balance
    }

    /// Get the total number of samples minted on the contract.
    public func totalSamples() async throws -> Int {
        let selector = "0x" + keccak256Selector("totalSamples()")
        let result: String = try await ethCall(to: configuration.contractAddress, data: selector)
        guard let count = Int(result.dropFirst(2).prefix(64), radix: 16) else {
            throw Web3Error.decodingError("Invalid total samples result: \(result)")
        }
        return count
    }

    // MARK: - Write Operations

    /// Purchase an edition of a sample.
    ///
    /// Sends a `purchase(uint256)` transaction with the sample price as msg.value.
    ///
    /// - Parameters:
    ///   - tokenId: The token ID of the sample to purchase.
    ///   - from: The buyer's wallet address.
    ///   - priceWei: The price in wei (hex string).
    /// - Returns: The transaction hash.
    public func purchaseSample(tokenId: String, from: String, priceWei: String) async throws -> String {
        guard let signer else {
            throw Web3Error.userRejected
        }

        let selector = "0x" + keccak256Selector("purchase(uint256)")
        let paddedTokenId = padLeft(tokenId, to: 64)
        let calldata = "0x" + selector.dropFirst(2) + paddedTokenId

        let transaction = EthTransaction(
            from: from,
            to: configuration.contractAddress,
            data: calldata,
            value: priceWei
        )

        return try await signer.sendTransaction(transaction)
    }

    /// Mint a new sample on the contract.
    ///
    /// Sends a `mint(string,uint256,uint256,uint256)` transaction.
    ///
    /// - Parameters:
    ///   - from: The creator's wallet address.
    ///   - ipfsCid: IPFS CID of the audio file.
    ///   - priceWei: Price per edition in wei (hex string).
    ///   - totalSupply: Total number of editions.
    ///   - royaltyBps: Royalty percentage in basis points (e.g. 500 = 5%).
    /// - Returns: The transaction hash.
    public func mintSample(
        from: String,
        ipfsCid: String,
        priceWei: String,
        totalSupply: Int,
        royaltyBps: Int
    ) async throws -> String {
        guard let signer else {
            throw Web3Error.userRejected
        }

        // Encode: mint(string ipfsCid, uint256 priceWei, uint256 totalSupply, uint256 royaltyBps)
        let selector = keccak256Selector("mint(string,uint256,uint256,uint256)")

        // ABI encoding for dynamic types (string) requires offset + length + data
        // Simplified encoding - in production, use a proper ABI encoder
        let priceHex = padLeft(String(priceWei.dropFirst(2)), to: 64)
        let supplyHex = padLeft(String(totalSupply, radix: 16), to: 64)
        let royaltyHex = padLeft(String(royaltyBps, radix: 16), to: 64)

        // String offset (4 * 32 bytes = 128 = 0x80)
        let stringOffset = padLeft("80", to: 64)
        let cidBytes = Array(ipfsCid.utf8)
        let cidLength = padLeft(String(cidBytes.count, radix: 16), to: 64)
        let cidHex = cidBytes.map { String(format: "%02x", $0) }.joined()
        let paddedCidHex = cidHex + String(repeating: "0", count: (64 - cidHex.count % 64) % 64)

        let calldata = "0x" + selector + stringOffset + priceHex + supplyHex + royaltyHex + cidLength + paddedCidHex

        let transaction = EthTransaction(
            from: from,
            to: configuration.contractAddress,
            data: calldata,
            value: "0x0"
        )

        return try await signer.sendTransaction(transaction)
    }

    /// Wait for a transaction to be confirmed.
    ///
    /// - Parameters:
    ///   - txHash: The transaction hash to monitor.
    ///   - confirmations: Number of block confirmations to wait for (default: 1).
    ///   - timeoutSeconds: Maximum time to wait (default: 120 seconds).
    /// - Returns: The transaction receipt.
    public func waitForConfirmation(
        txHash: String,
        confirmations: Int = 1,
        timeoutSeconds: TimeInterval = 120
    ) async throws -> TransactionReceipt {
        let deadline = Date().addingTimeInterval(timeoutSeconds)

        while Date() < deadline {
            if let receipt = try await getTransactionReceipt(txHash: txHash) {
                if let receiptBlock = receipt.blockNumber {
                    let currentBlock = try await getBlockNumber()
                    if currentBlock - receiptBlock >= confirmations {
                        return receipt
                    }
                }
            }
            // Poll every 2 seconds
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }

        throw Web3Error.transactionFailed(hash: txHash, reason: "Confirmation timeout after \(Int(timeoutSeconds))s")
    }

    /// Get the block explorer URL for a transaction.
    public func explorerURL(forTransaction txHash: String) -> URL {
        configuration.chain.explorerURL.appendingPathComponent("tx/\(txHash)")
    }

    // MARK: - Private Helpers

    /// Perform a JSON-RPC call and return the decoded result.
    private func rpcCall<T: Decodable>(method: String, params: [Any]) async throws -> T {
        rpcRequestId += 1
        let requestBody: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
            "id": rpcRequestId,
        ]

        var request = URLRequest(url: configuration.chain.rpcURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, _) = try await session.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Web3Error.decodingError("Invalid JSON-RPC response")
        }

        if let error = json["error"] as? [String: Any],
           let code = error["code"] as? Int,
           let message = error["message"] as? String {
            throw Web3Error.rpcError(code: code, message: message)
        }

        guard let result = json["result"] else {
            throw Web3Error.decodingError("Missing 'result' in JSON-RPC response")
        }

        // For simple string results
        if let stringResult = result as? T {
            return stringResult
        }

        // For complex results, re-encode and decode
        let resultData = try JSONSerialization.data(withJSONObject: result)
        return try JSONDecoder().decode(T.self, from: resultData)
    }

    /// Perform an eth_call (read-only contract call).
    private func ethCall(to: String, data: String) async throws -> String {
        let callObject: [String: String] = ["to": to, "data": data]
        let result: String = try await rpcCall(method: "eth_call", params: [callObject, "latest"])
        return result
    }

    /// Get a transaction receipt.
    private func getTransactionReceipt(txHash: String) async throws -> TransactionReceipt? {
        do {
            let result: TransactionReceipt = try await rpcCall(
                method: "eth_getTransactionReceipt",
                params: [txHash]
            )
            return result
        } catch {
            // Receipt not yet available
            return nil
        }
    }

    /// Compute the first 4 bytes of the keccak256 hash of a function signature.
    ///
    /// In production, this would use a proper keccak256 implementation.
    /// This is a placeholder that returns a precomputed selector.
    private func keccak256Selector(_ signature: String) -> String {
        // Placeholder: In production, compute keccak256 and take first 4 bytes.
        // For now, return a deterministic 8-char hex string derived from the signature.
        let hash = signature.utf8.reduce(UInt32(0)) { ($0 &<< 5) &+ $0 &+ UInt32($1) }
        return String(format: "%08x", hash)
    }

    /// Pad a hex string with leading zeros to the specified length.
    private func padLeft(_ hex: String, to length: Int) -> String {
        let clean = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        let padCount = max(0, length - clean.count)
        return String(repeating: "0", count: padCount) + clean
    }

    /// Decode ABI-encoded sample info from a hex string.
    private func decodeSampleInfo(tokenId: String, hexData: String) throws -> OnChainSampleInfo {
        let data = String(hexData.dropFirst(2)) // Remove 0x prefix
        guard data.count >= 7 * 64 else {
            throw Web3Error.decodingError("Insufficient data for sample info decoding")
        }

        // Each 32-byte word is 64 hex characters
        func word(at index: Int) -> String {
            let start = data.index(data.startIndex, offsetBy: index * 64)
            let end = data.index(start, offsetBy: 64)
            return String(data[start..<end])
        }

        let creatorHex = word(at: 0)
        let creator = "0x" + String(creatorHex.suffix(40))

        // Word 1 is offset to string data (skip for now, use word 5+ for string)
        let priceWei = "0x" + word(at: 2)
        let totalSupply = Int(word(at: 3), radix: 16) ?? 0
        let mintedCount = Int(word(at: 4), radix: 16) ?? 0
        let royaltyBps = Int(word(at: 5), radix: 16) ?? 0
        let isActive = Int(word(at: 6), radix: 16) ?? 0 != 0

        return OnChainSampleInfo(
            tokenId: tokenId,
            creator: creator,
            ipfsCid: "", // Decoded from dynamic string data in production
            priceWei: priceWei,
            totalSupply: totalSupply,
            mintedCount: mintedCount,
            royaltyBps: royaltyBps,
            isActive: isActive
        )
    }
}

// MARK: - Transaction Receipt

/// Decoded Ethereum transaction receipt from JSON-RPC.
public struct TransactionReceipt: Codable, Sendable {
    public let transactionHash: String
    public let blockNumber: Int?
    public let status: String? // "0x1" for success, "0x0" for failure
    public let gasUsed: String?

    /// Whether the transaction succeeded.
    public var isSuccess: Bool {
        status == "0x1"
    }

    enum CodingKeys: String, CodingKey {
        case transactionHash
        case blockNumber
        case status
        case gasUsed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transactionHash = try container.decode(String.self, forKey: .transactionHash)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        gasUsed = try container.decodeIfPresent(String.self, forKey: .gasUsed)

        // blockNumber comes as a hex string from the RPC
        if let blockHex = try container.decodeIfPresent(String.self, forKey: .blockNumber) {
            let clean = blockHex.hasPrefix("0x") ? String(blockHex.dropFirst(2)) : blockHex
            blockNumber = Int(clean, radix: 16)
        } else {
            blockNumber = nil
        }
    }
}
