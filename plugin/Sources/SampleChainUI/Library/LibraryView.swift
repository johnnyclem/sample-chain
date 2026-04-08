// LibraryView.swift
// SampleChainUI
//
// User's owned samples organized by packs, favorites, and recent items.
// Shows offline status indicators and supports batch operations.

import SwiftUI
import SampleChainCore

// MARK: - Library Section

/// Sections within the user's sample library.
public enum LibrarySection: String, CaseIterable, Identifiable {
    case all = "All Samples"
    case favorites = "Favorites"
    case recent = "Recently Added"
    case downloaded = "Downloaded"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .all: return "music.note.list"
        case .favorites: return "heart.fill"
        case .recent: return "clock.fill"
        case .downloaded: return "arrow.down.circle.fill"
        }
    }
}

// MARK: - Library View Model

/// View model for the user's sample library.
@MainActor
public final class LibraryViewModel: ObservableObject {
    @Published public var samples: [Sample] = []
    @Published public var favoriteSamples: [Sample] = []
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String?
    @Published public var selectedSection: LibrarySection = .all
    @Published public var selectedSamples: Set<UUID> = []
    @Published public var isSelectionMode: Bool = false
    @Published public var downloadedTokenIds: Set<String> = []

    private let apiClient: APIClient

    public init(apiClient: APIClient = APIClient()) {
        self.apiClient = apiClient
    }

    /// Load the user's library.
    public func loadLibrary() async {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await apiClient.execute(Endpoints.getLibrary())
            samples = response.items
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Load favorite samples.
    public func loadFavorites() async {
        do {
            let response = try await apiClient.execute(Endpoints.getFavorites())
            favoriteSamples = response.items
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Toggle favorite status for a sample.
    public func toggleFavorite(sample: Sample) async {
        let isFavorited = favoriteSamples.contains(where: { $0.id == sample.id })

        do {
            if isFavorited {
                try await apiClient.executeVoid(Endpoints.removeFavorite(tokenId: sample.tokenId))
                favoriteSamples.removeAll { $0.id == sample.id }
            } else {
                try await apiClient.executeVoid(Endpoints.addFavorite(tokenId: sample.tokenId))
                favoriteSamples.append(sample)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Toggle selection of a sample for batch operations.
    public func toggleSelection(_ sampleId: UUID) {
        if selectedSamples.contains(sampleId) {
            selectedSamples.remove(sampleId)
        } else {
            selectedSamples.insert(sampleId)
        }
    }

    /// Select all visible samples.
    public func selectAll() {
        selectedSamples = Set(displayedSamples.map(\.id))
    }

    /// Deselect all samples.
    public func deselectAll() {
        selectedSamples.removeAll()
    }

    /// Check if a sample is downloaded for offline use.
    public func isDownloaded(_ sample: Sample) -> Bool {
        downloadedTokenIds.contains(sample.tokenId)
    }

    /// The samples to display based on the selected section.
    public var displayedSamples: [Sample] {
        switch selectedSection {
        case .all:
            return samples
        case .favorites:
            return favoriteSamples
        case .recent:
            return samples.sorted { $0.mintedAt > $1.mintedAt }
        case .downloaded:
            return samples.filter { downloadedTokenIds.contains($0.tokenId) }
        }
    }
}

// MARK: - Library View

/// The user's sample library view with organization, offline indicators, and batch operations.
public struct LibraryView: View {
    @StateObject private var viewModel = LibraryViewModel()
    @EnvironmentObject private var appState: AppState
    @State private var selectedSample: Sample?

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            libraryHeader

            // Section tabs
            sectionTabs

            Divider().background(SCColor.border)

            // Content
            if viewModel.isLoading {
                loadingView
            } else if viewModel.displayedSamples.isEmpty {
                emptyStateView
            } else {
                sampleList
            }

            // Batch action bar
            if viewModel.isSelectionMode && !viewModel.selectedSamples.isEmpty {
                batchActionBar
            }
        }
        .background(SCColor.backgroundPrimary)
        .task {
            await viewModel.loadLibrary()
            await viewModel.loadFavorites()
        }
        .sheet(item: $selectedSample) { sample in
            SampleDetailView(sample: sample)
        }
    }

    // MARK: - Header

    private var libraryHeader: some View {
        HStack {
            Text("My Library")
                .font(SCFont.heading1)
                .foregroundStyle(SCColor.textPrimary)

            Text("\(viewModel.samples.count) samples")
                .font(SCFont.bodySmall)
                .foregroundStyle(SCColor.textTertiary)

            Spacer()

            // Selection mode toggle
            Button {
                viewModel.isSelectionMode.toggle()
                if !viewModel.isSelectionMode {
                    viewModel.deselectAll()
                }
            } label: {
                Text(viewModel.isSelectionMode ? "Done" : "Select")
                    .font(SCFont.bodyMedium)
                    .foregroundStyle(SCColor.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, SCSpacing.lg)
        .padding(.vertical, SCSpacing.md)
    }

    // MARK: - Section Tabs

    private var sectionTabs: some View {
        HStack(spacing: SCSpacing.xxs) {
            ForEach(LibrarySection.allCases) { section in
                Button {
                    viewModel.selectedSection = section
                } label: {
                    HStack(spacing: SCSpacing.xxs) {
                        Image(systemName: section.iconName)
                            .font(.system(size: 11))
                        Text(section.rawValue)
                            .font(SCFont.bodySmall)
                    }
                    .foregroundStyle(
                        viewModel.selectedSection == section ? SCColor.accent : SCColor.textSecondary
                    )
                    .padding(.horizontal, SCSpacing.md)
                    .padding(.vertical, SCSpacing.xs)
                    .background(
                        viewModel.selectedSection == section ? SCColor.accentMuted : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: SCRadius.md))
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, SCSpacing.lg)
        .padding(.vertical, SCSpacing.sm)
    }

    // MARK: - Sample List

    private var sampleList: some View {
        ScrollView {
            LazyVStack(spacing: SCSpacing.xxs) {
                ForEach(viewModel.displayedSamples) { sample in
                    librarySampleRow(sample)
                }
            }
            .padding(.horizontal, SCSpacing.lg)
            .padding(.vertical, SCSpacing.sm)
        }
    }

    private func librarySampleRow(_ sample: Sample) -> some View {
        HStack(spacing: SCSpacing.md) {
            // Selection checkbox
            if viewModel.isSelectionMode {
                Image(systemName: viewModel.selectedSamples.contains(sample.id)
                      ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(
                        viewModel.selectedSamples.contains(sample.id)
                        ? SCColor.accent : SCColor.textTertiary
                    )
                    .onTapGesture {
                        viewModel.toggleSelection(sample.id)
                    }
            }

            // Sample cell content
            SampleCell(sample: sample, displayMode: .list)

            // Offline indicator
            if viewModel.isDownloaded(sample) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(SCColor.success)
            } else {
                Image(systemName: "cloud")
                    .font(.system(size: 14))
                    .foregroundStyle(SCColor.textTertiary)
            }

            // Favorite indicator
            Button {
                Task {
                    await viewModel.toggleFavorite(sample: sample)
                }
            } label: {
                Image(systemName: viewModel.favoriteSamples.contains(where: { $0.id == sample.id })
                      ? "heart.fill" : "heart")
                    .font(.system(size: 14))
                    .foregroundStyle(
                        viewModel.favoriteSamples.contains(where: { $0.id == sample.id })
                        ? SCColor.error : SCColor.textTertiary
                    )
            }
            .buttonStyle(.plain)
        }
        .onTapGesture {
            if viewModel.isSelectionMode {
                viewModel.toggleSelection(sample.id)
            } else {
                selectedSample = sample
            }
        }
    }

    // MARK: - Batch Action Bar

    private var batchActionBar: some View {
        HStack(spacing: SCSpacing.lg) {
            Text("\(viewModel.selectedSamples.count) selected")
                .font(SCFont.bodyMedium)
                .foregroundStyle(SCColor.textPrimary)

            Spacer()

            Button {
                // Download selected samples for offline use
            } label: {
                HStack(spacing: SCSpacing.xxs) {
                    Image(systemName: "arrow.down.circle")
                    Text("Download")
                }
                .font(SCFont.bodySmall)
                .foregroundStyle(SCColor.accent)
            }
            .buttonStyle(.plain)

            Button {
                // Export selected samples
            } label: {
                HStack(spacing: SCSpacing.xxs) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export")
                }
                .font(SCFont.bodySmall)
                .foregroundStyle(SCColor.accent)
            }
            .buttonStyle(.plain)

            Button("Select All") {
                viewModel.selectAll()
            }
            .font(SCFont.bodySmall)
            .foregroundStyle(SCColor.accent)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, SCSpacing.lg)
        .padding(.vertical, SCSpacing.md)
        .background(SCColor.backgroundTertiary)
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: SCSpacing.lg) {
            ProgressView()
                .tint(SCColor.accent)
                .scaleEffect(1.5)
            Text("Loading library...")
                .font(SCFont.body)
                .foregroundStyle(SCColor.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: SCSpacing.lg) {
            Image(systemName: viewModel.selectedSection.iconName)
                .font(.system(size: 48))
                .foregroundStyle(SCColor.textTertiary)

            Text(emptyStateTitle)
                .font(SCFont.heading2)
                .foregroundStyle(SCColor.textPrimary)

            Text(emptyStateMessage)
                .font(SCFont.body)
                .foregroundStyle(SCColor.textSecondary)
                .multilineTextAlignment(.center)

            if viewModel.selectedSection == .all {
                Button {
                    appState.selectedTab = .browse
                } label: {
                    Text("Browse Samples")
                        .font(SCFont.bodyMedium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, SCSpacing.xxl)
                        .padding(.vertical, SCSpacing.md)
                        .background(SCColor.accent)
                        .clipShape(RoundedRectangle(cornerRadius: SCRadius.lg))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateTitle: String {
        switch viewModel.selectedSection {
        case .all: return "No samples yet"
        case .favorites: return "No favorites"
        case .recent: return "Nothing recent"
        case .downloaded: return "No downloads"
        }
    }

    private var emptyStateMessage: String {
        switch viewModel.selectedSection {
        case .all: return "Purchase or collect samples to build your library."
        case .favorites: return "Tap the heart icon on samples you love."
        case .recent: return "Your recently added samples will appear here."
        case .downloaded: return "Download samples for offline access in your DAW."
        }
    }
}
