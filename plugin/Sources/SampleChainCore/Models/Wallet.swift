// Wallet.swift
// SampleChainCore
//
// Wallet state model for Ethereum wallet connection and transaction tracking.

import Foundation

// MARK: - Wallet Connection State

/// Represents the lifecycle state of a wallet connection.
public enum WalletConnectionState: Equatable, Sendable {
    /// No wallet connected; user needs to initiate connection.
    case disconnected
    /// WalletConnect pairing in progress; awaiting user approval in wallet app.
    case connecting
    /// Wallet is connected and ready for signing.
    case connected(WalletInfo)
    /// Connection or signing encountered an error.
    case error(String)
}

// MARK: - Wallet Info

/// Information about the connected wallet.
public struct WalletInfo: Codable, Equatable, Sendable {
    /// Ethereum address (0x-prefixed, checksummed).
    public let address: String
    /// Chain ID the wallet is connected to (e.g. 1 for mainnet, 8453 for Base).
    public let chainId: Int
    /// Human-readable name of the wallet app (e.g. "MetaMask", "Rainbow").
    public let walletName: String?

    public init(address: String, chainId: Int, walletName: String? = nil) {
        self.address = address
        self.chainId = chainId
        self.walletName = walletName
    }

    /// Shortened address for display (e.g. "0xAbCd...1234").
    public var shortAddress: String {
        guard address.count > 10 else { return address }
        let prefix = address.prefix(6)
        let suffix = address.suffix(4)
        return "\(prefix)...\(suffix)"
    }
}

// MARK: - Wallet Balance

/// Token balance information for display in the wallet view.
public struct WalletBalance: Codable, Equatable, Sendable {
    /// Native token balance (ETH) in wei, stored as a string to preserve precision.
    public let ethBalanceWei: String
    /// Formatted ETH balance for display (e.g. "1.2345 ETH").
    public let ethBalanceFormatted: String
    /// USD equivalent of ETH balance at current market rate.
    public let ethBalanceUSD: Decimal?

    public init(ethBalanceWei: String, ethBalanceFormatted: String, ethBalanceUSD: Decimal? = nil) {
        self.ethBalanceWei = ethBalanceWei
        self.ethBalanceFormatted = ethBalanceFormatted
        self.ethBalanceUSD = ethBalanceUSD
    }
}

// MARK: - Transaction

/// A blockchain transaction relevant to SampleChain (mints, purchases, transfers).
public struct Transaction: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    /// On-chain transaction hash (0x-prefixed hex string).
    public let txHash: String
    /// The type of SampleChain operation this transaction represents.
    public let transactionType: TransactionType
    /// Current confirmation status.
    public let status: TransactionStatus
    /// From address.
    public let from: String
    /// To address (contract address for mints/purchases).
    public let to: String
    /// ETH value transferred (in ETH, not wei).
    public let valueETH: Decimal
    /// Gas used in gwei.
    public let gasUsedGwei: Decimal?
    /// Associated sample token ID, if applicable.
    public let sampleTokenId: String?
    /// Block number when confirmed.
    public let blockNumber: Int?
    /// Timestamp of the transaction.
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        txHash: String,
        transactionType: TransactionType,
        status: TransactionStatus,
        from: String,
        to: String,
        valueETH: Decimal,
        gasUsedGwei: Decimal? = nil,
        sampleTokenId: String? = nil,
        blockNumber: Int? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.txHash = txHash
        self.transactionType = transactionType
        self.status = status
        self.from = from
        self.to = to
        self.valueETH = valueETH
        self.gasUsedGwei = gasUsedGwei
        self.sampleTokenId = sampleTokenId
        self.blockNumber = blockNumber
        self.timestamp = timestamp
    }
}

/// Classification of transaction types on the SampleChain platform.
public enum TransactionType: String, Codable, Sendable {
    /// Minting a new sample NFT.
    case mint = "mint"
    /// Purchasing an edition of a sample.
    case purchase = "purchase"
    /// Transferring a sample to another wallet.
    case transfer = "transfer"
    /// Receiving a royalty payment from a secondary sale.
    case royalty = "royalty"
    /// Withdrawing accumulated earnings.
    case withdrawal = "withdrawal"

    public var displayName: String {
        switch self {
        case .mint: return "Mint"
        case .purchase: return "Purchase"
        case .transfer: return "Transfer"
        case .royalty: return "Royalty"
        case .withdrawal: return "Withdrawal"
        }
    }
}

/// Transaction lifecycle status.
public enum TransactionStatus: String, Codable, Sendable {
    /// Transaction has been submitted but not yet included in a block.
    case pending = "pending"
    /// Transaction has been included in a block and confirmed.
    case confirmed = "confirmed"
    /// Transaction reverted on-chain.
    case failed = "failed"

    public var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .confirmed: return "Confirmed"
        case .failed: return "Failed"
        }
    }
}

// MARK: - Wallet State (Observable)

/// Observable wallet state that drives the UI.
///
/// This actor centralizes all wallet-related state mutations and ensures
/// thread-safe access from SwiftUI views and background tasks.
public actor WalletState {
    /// Current connection state.
    public private(set) var connectionState: WalletConnectionState = .disconnected
    /// Current balance (nil if not connected or not yet fetched).
    public private(set) var balance: WalletBalance?
    /// Recent transactions, ordered newest-first.
    public private(set) var transactions: [Transaction] = []
    /// Creator earnings snapshot for the connected wallet.
    public private(set) var earnings: CreatorEarningsSnapshot?

    public init() {}

    /// Update the connection state.
    public func setConnectionState(_ state: WalletConnectionState) {
        self.connectionState = state
    }

    /// Update the balance.
    public func setBalance(_ balance: WalletBalance?) {
        self.balance = balance
    }

    /// Replace the full transaction list.
    public func setTransactions(_ transactions: [Transaction]) {
        self.transactions = transactions
    }

    /// Prepend a new transaction (e.g. just submitted).
    public func addTransaction(_ transaction: Transaction) {
        self.transactions.insert(transaction, at: 0)
    }

    /// Update the status of an existing transaction by its hash.
    public func updateTransactionStatus(txHash: String, status: TransactionStatus, blockNumber: Int? = nil) {
        guard let index = transactions.firstIndex(where: { $0.txHash == txHash }) else { return }
        let old = transactions[index]
        transactions[index] = Transaction(
            id: old.id,
            txHash: old.txHash,
            transactionType: old.transactionType,
            status: status,
            from: old.from,
            to: old.to,
            valueETH: old.valueETH,
            gasUsedGwei: old.gasUsedGwei,
            sampleTokenId: old.sampleTokenId,
            blockNumber: blockNumber ?? old.blockNumber,
            timestamp: old.timestamp
        )
    }

    /// Update the earnings snapshot.
    public func setEarnings(_ earnings: CreatorEarningsSnapshot?) {
        self.earnings = earnings
    }
}
