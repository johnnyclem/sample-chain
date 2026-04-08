// WalletView.swift
// SampleChainUI
//
// Wallet connection (WalletConnect), balance display, transaction history,
// and creator earnings dashboard.

import SwiftUI
import SampleChainCore

// MARK: - Wallet View Model

/// View model for the wallet view and earnings dashboard.
@MainActor
public final class WalletViewModel: ObservableObject {
    @Published public var connectionState: WalletConnectionState = .disconnected
    @Published public var balance: WalletBalance?
    @Published public var transactions: [Transaction] = []
    @Published public var earnings: CreatorEarningsSnapshot?
    @Published public var isLoadingTransactions: Bool = false
    @Published public var selectedDashboardTab: DashboardTab = .transactions

    private let apiClient: APIClient

    public init(apiClient: APIClient = APIClient()) {
        self.apiClient = apiClient
    }

    /// Initiate wallet connection via WalletConnect.
    public func connectWallet() async {
        connectionState = .connecting

        // In production, this would use WalletConnect SDK
        // For now, simulate the connection flow
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        connectionState = .connected(WalletInfo(
            address: "0x0000000000000000000000000000000000000000",
            chainId: 8453,
            walletName: "MetaMask"
        ))
    }

    /// Disconnect the wallet.
    public func disconnectWallet() {
        connectionState = .disconnected
        balance = nil
        transactions = []
        earnings = nil
    }

    /// Load transaction history.
    public func loadTransactions() async {
        isLoadingTransactions = true
        do {
            let response = try await apiClient.execute(Endpoints.getTransactions())
            transactions = response.items
        } catch {
            // Silently fail for transactions
        }
        isLoadingTransactions = false
    }

    /// Load creator earnings data.
    public func loadEarnings() async {
        do {
            earnings = try await apiClient.execute(Endpoints.getEarnings())
        } catch {
            // Silently fail
        }
    }

    /// Refresh all wallet data.
    public func refresh() async {
        await loadTransactions()
        await loadEarnings()
    }
}

/// Dashboard tabs within the wallet view.
public enum DashboardTab: String, CaseIterable, Identifiable {
    case transactions = "Transactions"
    case earnings = "Earnings"

    public var id: String { rawValue }
}

// MARK: - Wallet View

/// Wallet management view with connection, balance, transactions, and earnings dashboard.
public struct WalletView: View {
    @StateObject private var viewModel = WalletViewModel()
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: SCSpacing.xxl) {
                switch viewModel.connectionState {
                case .disconnected:
                    disconnectedView
                case .connecting:
                    connectingView
                case .connected(let walletInfo):
                    connectedView(walletInfo: walletInfo)
                case .error(let message):
                    errorView(message: message)
                }
            }
            .padding(SCSpacing.xxl)
        }
        .background(SCColor.backgroundPrimary)
    }

    // MARK: - Disconnected State

    private var disconnectedView: some View {
        VStack(spacing: SCSpacing.xxl) {
            Spacer(minLength: SCSpacing.xxxxl)

            Image(systemName: "wallet.pass.fill")
                .font(.system(size: 64))
                .foregroundStyle(SCColor.ethereum)

            VStack(spacing: SCSpacing.sm) {
                Text("Connect Your Wallet")
                    .font(SCFont.displayMedium)
                    .foregroundStyle(SCColor.textPrimary)

                Text("Connect an Ethereum wallet to browse, purchase, and manage your samples.")
                    .font(SCFont.body)
                    .foregroundStyle(SCColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            Button {
                Task {
                    await viewModel.connectWallet()
                }
            } label: {
                HStack(spacing: SCSpacing.sm) {
                    Image(systemName: "link")
                    Text("Connect with WalletConnect")
                        .font(SCFont.heading3)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, SCSpacing.xxxl)
                .padding(.vertical, SCSpacing.md)
                .background(SCColor.ethereum)
                .clipShape(RoundedRectangle(cornerRadius: SCRadius.lg))
            }
            .buttonStyle(.plain)

            // Alternative connection methods
            HStack(spacing: SCSpacing.lg) {
                Text("or connect with:")
                    .font(SCFont.bodySmall)
                    .foregroundStyle(SCColor.textTertiary)

                Button("MetaMask") {}
                    .font(SCFont.bodySmall)
                    .foregroundStyle(SCColor.accent)
                    .buttonStyle(.plain)

                Button("Coinbase Wallet") {}
                    .font(SCFont.bodySmall)
                    .foregroundStyle(SCColor.accent)
                    .buttonStyle(.plain)
            }

            Spacer(minLength: SCSpacing.xxxxl)
        }
    }

    // MARK: - Connecting State

    private var connectingView: some View {
        VStack(spacing: SCSpacing.xxl) {
            Spacer()

            ProgressView()
                .tint(SCColor.ethereum)
                .scaleEffect(2)

            VStack(spacing: SCSpacing.sm) {
                Text("Connecting...")
                    .font(SCFont.heading1)
                    .foregroundStyle(SCColor.textPrimary)

                Text("Approve the connection in your wallet app.")
                    .font(SCFont.body)
                    .foregroundStyle(SCColor.textSecondary)
            }

            Button("Cancel") {
                viewModel.disconnectWallet()
            }
            .font(SCFont.bodyMedium)
            .foregroundStyle(SCColor.textSecondary)
            .buttonStyle(.plain)

            Spacer()
        }
    }

    // MARK: - Connected State

    private func connectedView(walletInfo: WalletInfo) -> some View {
        VStack(spacing: SCSpacing.xxl) {
            // Wallet info card
            walletInfoCard(walletInfo: walletInfo)

            // Balance card
            balanceCard

            // Dashboard tabs
            dashboardSection

            // Transaction list or earnings
            switch viewModel.selectedDashboardTab {
            case .transactions:
                transactionsList
            case .earnings:
                earningsDashboard
            }
        }
        .task {
            await viewModel.refresh()
        }
    }

    private func walletInfoCard(walletInfo: WalletInfo) -> some View {
        HStack(spacing: SCSpacing.md) {
            // Wallet icon
            Circle()
                .fill(SCColor.ethereum.opacity(0.2))
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: "wallet.pass.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(SCColor.ethereum)
                }

            VStack(alignment: .leading, spacing: SCSpacing.xxs) {
                HStack(spacing: SCSpacing.sm) {
                    if let name = walletInfo.walletName {
                        Text(name)
                            .font(SCFont.bodyMedium)
                            .foregroundStyle(SCColor.textPrimary)
                    }
                    Circle()
                        .fill(SCColor.success)
                        .frame(width: 8, height: 8)
                    Text("Connected")
                        .font(SCFont.labelSmall)
                        .foregroundStyle(SCColor.success)
                }

                Text(walletInfo.address)
                    .font(SCFont.monoSmall)
                    .foregroundStyle(SCColor.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text("Chain: \(chainName(for: walletInfo.chainId))")
                    .font(SCFont.labelSmall)
                    .foregroundStyle(SCColor.textTertiary)
            }

            Spacer()

            // Copy address button
            Button {
                // Copy to clipboard
                #if canImport(AppKit)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(walletInfo.address, forType: .string)
                #endif
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 14))
                    .foregroundStyle(SCColor.textTertiary)
            }
            .buttonStyle(.plain)

            // Disconnect button
            Button {
                viewModel.disconnectWallet()
            } label: {
                Text("Disconnect")
                    .font(SCFont.bodySmall)
                    .foregroundStyle(SCColor.error)
            }
            .buttonStyle(.plain)
        }
        .padding(SCSpacing.lg)
        .scCard()
    }

    private var balanceCard: some View {
        HStack(spacing: SCSpacing.xxl) {
            // ETH Balance
            VStack(alignment: .leading, spacing: SCSpacing.xxs) {
                Text("Balance")
                    .font(SCFont.label)
                    .foregroundStyle(SCColor.textTertiary)
                HStack(spacing: SCSpacing.xs) {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(SCColor.ethereum)
                    Text(viewModel.balance?.ethBalanceFormatted ?? "0.0000 ETH")
                        .font(SCFont.displayMedium)
                        .foregroundStyle(SCColor.textPrimary)
                }
                if let usd = viewModel.balance?.ethBalanceUSD {
                    Text("$\(usd)")
                        .font(SCFont.bodySmall)
                        .foregroundStyle(SCColor.textTertiary)
                }
            }

            Divider()
                .frame(height: 50)
                .background(SCColor.border)

            // Earnings summary
            VStack(alignment: .leading, spacing: SCSpacing.xxs) {
                Text("Total Earnings")
                    .font(SCFont.label)
                    .foregroundStyle(SCColor.textTertiary)
                Text(viewModel.earnings.map { "\($0.totalEarningsETH) ETH" } ?? "-- ETH")
                    .font(SCFont.heading1)
                    .foregroundStyle(SCColor.success)
                Text(viewModel.earnings.map { "\($0.monthlySalesCount) sales this month" } ?? "")
                    .font(SCFont.bodySmall)
                    .foregroundStyle(SCColor.textTertiary)
            }

            Spacer()
        }
        .padding(SCSpacing.lg)
        .scCard()
    }

    // MARK: - Dashboard Section

    private var dashboardSection: some View {
        HStack(spacing: SCSpacing.xxs) {
            ForEach(DashboardTab.allCases) { tab in
                Button {
                    viewModel.selectedDashboardTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(SCFont.bodyMedium)
                        .foregroundStyle(
                            viewModel.selectedDashboardTab == tab
                            ? SCColor.accent : SCColor.textSecondary
                        )
                        .padding(.horizontal, SCSpacing.lg)
                        .padding(.vertical, SCSpacing.sm)
                        .background(
                            viewModel.selectedDashboardTab == tab
                            ? SCColor.accentMuted : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: SCRadius.md))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Transactions List

    private var transactionsList: some View {
        VStack(spacing: SCSpacing.sm) {
            if viewModel.isLoadingTransactions {
                ProgressView()
                    .tint(SCColor.accent)
                    .padding()
            } else if viewModel.transactions.isEmpty {
                VStack(spacing: SCSpacing.md) {
                    Image(systemName: "clock")
                        .font(.system(size: 32))
                        .foregroundStyle(SCColor.textTertiary)
                    Text("No transactions yet")
                        .font(SCFont.body)
                        .foregroundStyle(SCColor.textSecondary)
                }
                .padding(.vertical, SCSpacing.xxxl)
            } else {
                ForEach(viewModel.transactions) { transaction in
                    transactionRow(transaction)
                }
            }
        }
    }

    private func transactionRow(_ tx: Transaction) -> some View {
        HStack(spacing: SCSpacing.md) {
            // Type icon
            Circle()
                .fill(transactionColor(tx.transactionType).opacity(0.15))
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: transactionIcon(tx.transactionType))
                        .font(.system(size: 14))
                        .foregroundStyle(transactionColor(tx.transactionType))
                }

            // Details
            VStack(alignment: .leading, spacing: 2) {
                Text(tx.transactionType.displayName)
                    .font(SCFont.bodyMedium)
                    .foregroundStyle(SCColor.textPrimary)

                Text(tx.txHash.prefix(10) + "..." + tx.txHash.suffix(6))
                    .font(SCFont.monoSmall)
                    .foregroundStyle(SCColor.textTertiary)
            }

            Spacer()

            // Amount
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 2) {
                    Text(tx.valueETH == 0 ? "0" : "\(tx.valueETH)")
                        .font(SCFont.mono)
                        .foregroundStyle(SCColor.textPrimary)
                    Text("ETH")
                        .font(SCFont.labelSmall)
                        .foregroundStyle(SCColor.textTertiary)
                }

                // Status badge
                Text(tx.status.displayName)
                    .font(SCFont.labelSmall)
                    .foregroundStyle(statusColor(tx.status))
            }
        }
        .padding(SCSpacing.md)
        .scCard()
    }

    // MARK: - Earnings Dashboard

    private var earningsDashboard: some View {
        VStack(spacing: SCSpacing.lg) {
            if let earnings = viewModel.earnings {
                // Stats grid
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], spacing: SCSpacing.md) {
                    earningsStat(label: "Total Earnings", value: "\(earnings.totalEarningsETH) ETH")
                    earningsStat(label: "This Month", value: "\(earnings.monthlyEarningsETH) ETH")
                    earningsStat(label: "Royalties", value: "\(earnings.royaltyEarningsETH) ETH")
                    earningsStat(label: "Monthly Sales", value: "\(earnings.monthlySalesCount)")
                }

                // Earnings chart placeholder
                VStack(alignment: .leading, spacing: SCSpacing.sm) {
                    Text("Earnings Over Time")
                        .font(SCFont.heading3)
                        .foregroundStyle(SCColor.textPrimary)

                    // Simple bar chart using earnings history
                    if !earnings.earningsHistory.isEmpty {
                        HStack(alignment: .bottom, spacing: 2) {
                            ForEach(earnings.earningsHistory) { point in
                                let maxAmount = earnings.earningsHistory.map(\.amountETH).max() ?? 1
                                let normalizedHeight = maxAmount > 0
                                    ? CGFloat(truncating: (point.amountETH / maxAmount) as NSDecimalNumber)
                                    : 0

                                RoundedRectangle(cornerRadius: 2)
                                    .fill(SCColor.accent)
                                    .frame(height: max(4, normalizedHeight * 100))
                            }
                        }
                        .frame(height: 100)
                        .padding(.horizontal, SCSpacing.sm)
                    } else {
                        RoundedRectangle(cornerRadius: SCRadius.md)
                            .fill(SCColor.surface)
                            .frame(height: 100)
                            .overlay {
                                Text("No earnings data yet")
                                    .font(SCFont.bodySmall)
                                    .foregroundStyle(SCColor.textTertiary)
                            }
                    }
                }
                .padding(SCSpacing.lg)
                .scCard()
            } else {
                VStack(spacing: SCSpacing.md) {
                    ProgressView()
                        .tint(SCColor.accent)
                    Text("Loading earnings...")
                        .font(SCFont.body)
                        .foregroundStyle(SCColor.textSecondary)
                }
                .padding(.vertical, SCSpacing.xxxl)
            }
        }
    }

    private func earningsStat(label: String, value: String) -> some View {
        VStack(spacing: SCSpacing.xs) {
            Text(label)
                .font(SCFont.label)
                .foregroundStyle(SCColor.textTertiary)
            Text(value)
                .font(SCFont.monoLarge)
                .foregroundStyle(SCColor.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(SCSpacing.md)
        .scCard()
    }

    // MARK: - Error State

    private func errorView(message: String) -> some View {
        VStack(spacing: SCSpacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(SCColor.error)
            Text("Connection Failed")
                .font(SCFont.heading1)
                .foregroundStyle(SCColor.textPrimary)
            Text(message)
                .font(SCFont.body)
                .foregroundStyle(SCColor.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                Task {
                    await viewModel.connectWallet()
                }
            } label: {
                Text("Try Again")
                    .font(SCFont.bodyMedium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, SCSpacing.xxl)
                    .padding(.vertical, SCSpacing.sm)
                    .background(SCColor.accent)
                    .clipShape(RoundedRectangle(cornerRadius: SCRadius.lg))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SCSpacing.xxxxl)
    }

    // MARK: - Helpers

    private func chainName(for chainId: Int) -> String {
        switch chainId {
        case 1: return "Ethereum Mainnet"
        case 8453: return "Base"
        case 84532: return "Base Sepolia"
        default: return "Chain \(chainId)"
        }
    }

    private func transactionIcon(_ type: TransactionType) -> String {
        switch type {
        case .mint: return "plus.circle"
        case .purchase: return "cart"
        case .transfer: return "arrow.right.circle"
        case .royalty: return "dollarsign.circle"
        case .withdrawal: return "arrow.up.circle"
        }
    }

    private func transactionColor(_ type: TransactionType) -> Color {
        switch type {
        case .mint: return SCColor.accent
        case .purchase: return SCColor.paid
        case .transfer: return SCColor.info
        case .royalty: return SCColor.success
        case .withdrawal: return SCColor.ethereum
        }
    }

    private func statusColor(_ status: TransactionStatus) -> Color {
        switch status {
        case .pending: return SCColor.warning
        case .confirmed: return SCColor.success
        case .failed: return SCColor.error
        }
    }
}
