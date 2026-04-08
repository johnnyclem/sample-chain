// BrowseView.swift
// SampleChainUI
//
// Grid/list view of samples with filtering, sorting, and infinite scroll pagination.

import SwiftUI
import SampleChainCore

// MARK: - Browse View Model

/// View model for the sample browsing experience.
@MainActor
public final class BrowseViewModel: ObservableObject {
    /// Currently loaded samples.
    @Published public var samples: [Sample] = []
    /// Whether the initial load is in progress.
    @Published public var isLoading: Bool = false
    /// Whether additional pages are being loaded.
    @Published public var isLoadingMore: Bool = false
    /// Whether there are more pages to load.
    @Published public var hasMorePages: Bool = true
    /// Current error message.
    @Published public var errorMessage: String?
    /// Current sort field.
    @Published public var sortBy: SampleSortField = .newest
    /// Display mode.
    @Published public var displayMode: BrowseDisplayMode = .grid

    private var currentPage: Int = 1
    private let pageSize: Int = 20
    private let apiClient: APIClient

    public init(apiClient: APIClient = APIClient()) {
        self.apiClient = apiClient
    }

    /// Load the first page of samples.
    public func loadInitialSamples(filter: SampleFilter) async {
        isLoading = true
        errorMessage = nil
        currentPage = 1

        do {
            let response = try await apiClient.execute(
                Endpoints.browseSamples(page: 1, pageSize: pageSize, filter: filter, sortBy: sortBy)
            )
            samples = response.items
            hasMorePages = response.hasNextPage
            currentPage = 1
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Load the next page of samples (infinite scroll).
    public func loadMoreSamples(filter: SampleFilter) async {
        guard hasMorePages && !isLoadingMore else { return }
        isLoadingMore = true

        let nextPage = currentPage + 1
        do {
            let response = try await apiClient.execute(
                Endpoints.browseSamples(page: nextPage, pageSize: pageSize, filter: filter, sortBy: sortBy)
            )
            samples.append(contentsOf: response.items)
            hasMorePages = response.hasNextPage
            currentPage = nextPage
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingMore = false
    }

    /// Refresh samples (pull to refresh or filter change).
    public func refresh(filter: SampleFilter) async {
        await loadInitialSamples(filter: filter)
    }
}

/// Display mode for the browse view.
public enum BrowseDisplayMode: String, CaseIterable {
    case grid = "Grid"
    case list = "List"

    public var iconName: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .list: return "list.bullet"
        }
    }
}

// MARK: - Browse View

/// The main browse view showing a grid or list of available samples with filtering.
public struct BrowseView: View {
    @StateObject private var viewModel = BrowseViewModel()
    @EnvironmentObject private var appState: AppState
    @State private var selectedSample: Sample?
    @State private var showFilterBar: Bool = true

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            browseHeader

            // Filter bar
            if showFilterBar {
                FilterBar(filter: $appState.activeFilter)
                    .padding(.horizontal, SCSpacing.lg)
                    .padding(.vertical, SCSpacing.sm)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Divider().background(SCColor.border)

            // Content
            if viewModel.isLoading {
                loadingView
            } else if viewModel.samples.isEmpty {
                emptyStateView
            } else {
                sampleContent
            }
        }
        .background(SCColor.backgroundPrimary)
        .task {
            await viewModel.loadInitialSamples(filter: appState.activeFilter)
        }
        .onChange(of: appState.activeFilter) { _, newFilter in
            Task {
                await viewModel.refresh(filter: newFilter)
            }
        }
        .onChange(of: viewModel.sortBy) { _, _ in
            Task {
                await viewModel.refresh(filter: appState.activeFilter)
            }
        }
        .sheet(item: $selectedSample) { sample in
            SampleDetailView(sample: sample)
        }
    }

    // MARK: - Header

    private var browseHeader: some View {
        HStack {
            Text("Browse Samples")
                .font(SCFont.heading1)
                .foregroundStyle(SCColor.textPrimary)

            Spacer()

            // Filter toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showFilterBar.toggle()
                }
            } label: {
                HStack(spacing: SCSpacing.xxs) {
                    Image(systemName: "line.3.horizontal.decrease")
                    Text("Filters")
                        .font(SCFont.bodySmall)
                }
                .foregroundStyle(showFilterBar ? SCColor.accent : SCColor.textSecondary)
                .padding(.horizontal, SCSpacing.sm)
                .padding(.vertical, SCSpacing.xxs)
                .background(showFilterBar ? SCColor.accentMuted : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: SCRadius.md))
            }
            .buttonStyle(.plain)

            // Sort picker
            Menu {
                ForEach(SampleSortField.allCases, id: \.self) { field in
                    Button {
                        viewModel.sortBy = field
                    } label: {
                        HStack {
                            Text(field.displayName)
                            if viewModel.sortBy == field {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: SCSpacing.xxs) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text(viewModel.sortBy.displayName)
                        .font(SCFont.bodySmall)
                }
                .foregroundStyle(SCColor.textSecondary)
                .padding(.horizontal, SCSpacing.sm)
                .padding(.vertical, SCSpacing.xxs)
            }

            // Display mode toggle
            HStack(spacing: 0) {
                ForEach(BrowseDisplayMode.allCases, id: \.self) { mode in
                    Button {
                        viewModel.displayMode = mode
                    } label: {
                        Image(systemName: mode.iconName)
                            .font(.system(size: 12))
                            .foregroundStyle(
                                viewModel.displayMode == mode ? SCColor.accent : SCColor.textTertiary
                            )
                            .frame(width: 28, height: 24)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(SCColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: SCRadius.sm))
        }
        .padding(.horizontal, SCSpacing.lg)
        .padding(.vertical, SCSpacing.md)
    }

    // MARK: - Content Views

    @ViewBuilder
    private var sampleContent: some View {
        switch viewModel.displayMode {
        case .grid:
            gridView
        case .list:
            listView
        }
    }

    private var gridView: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: SCSpacing.md)],
                spacing: SCSpacing.md
            ) {
                ForEach(viewModel.samples) { sample in
                    SampleCell(sample: sample, displayMode: .grid)
                        .onTapGesture {
                            selectedSample = sample
                        }
                        .onAppear {
                            // Infinite scroll: load more when last items appear
                            if sample.id == viewModel.samples.last?.id {
                                Task {
                                    await viewModel.loadMoreSamples(filter: appState.activeFilter)
                                }
                            }
                        }
                }
            }
            .padding(SCSpacing.lg)

            if viewModel.isLoadingMore {
                ProgressView()
                    .tint(SCColor.accent)
                    .padding()
            }
        }
    }

    private var listView: some View {
        ScrollView {
            LazyVStack(spacing: SCSpacing.xxs) {
                ForEach(viewModel.samples) { sample in
                    SampleCell(sample: sample, displayMode: .list)
                        .onTapGesture {
                            selectedSample = sample
                        }
                        .onAppear {
                            if sample.id == viewModel.samples.last?.id {
                                Task {
                                    await viewModel.loadMoreSamples(filter: appState.activeFilter)
                                }
                            }
                        }
                }
            }
            .padding(.horizontal, SCSpacing.lg)
            .padding(.vertical, SCSpacing.sm)

            if viewModel.isLoadingMore {
                ProgressView()
                    .tint(SCColor.accent)
                    .padding()
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: SCSpacing.lg) {
            ProgressView()
                .tint(SCColor.accent)
                .scaleEffect(1.5)
            Text("Loading samples...")
                .font(SCFont.body)
                .foregroundStyle(SCColor.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: SCSpacing.lg) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundStyle(SCColor.textTertiary)
            Text("No samples found")
                .font(SCFont.heading2)
                .foregroundStyle(SCColor.textPrimary)
            Text("Try adjusting your filters or search criteria.")
                .font(SCFont.body)
                .foregroundStyle(SCColor.textSecondary)
                .multilineTextAlignment(.center)

            if !appState.activeFilter.isEmpty {
                Button {
                    appState.activeFilter = SampleFilter()
                } label: {
                    Text("Clear Filters")
                        .font(SCFont.bodyMedium)
                        .foregroundStyle(SCColor.accent)
                        .padding(.horizontal, SCSpacing.lg)
                        .padding(.vertical, SCSpacing.sm)
                        .background(SCColor.accentMuted)
                        .clipShape(RoundedRectangle(cornerRadius: SCRadius.md))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
