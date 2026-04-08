// SearchView.swift
// SampleChainUI
//
// Full-text search with debounced search-as-you-type functionality.

import SwiftUI
import SampleChainCore
import Combine

// MARK: - Search View Model

/// View model for the search experience with debounced query handling.
@MainActor
public final class SearchViewModel: ObservableObject {
    /// Current search query text.
    @Published public var query: String = ""
    /// Search results.
    @Published public var results: [Sample] = []
    /// Whether a search is currently in progress.
    @Published public var isSearching: Bool = false
    /// Whether there are more results to load.
    @Published public var hasMoreResults: Bool = false
    /// Recent search queries for quick access.
    @Published public var recentSearches: [String] = []
    /// Error message from the last search.
    @Published public var errorMessage: String?

    private var searchTask: Task<Void, Never>?
    private var currentPage: Int = 1
    private let pageSize: Int = 20
    private let debounceInterval: Duration = .milliseconds(300)
    private let apiClient: APIClient

    public init(apiClient: APIClient = APIClient()) {
        self.apiClient = apiClient
    }

    /// Perform a debounced search when the query changes.
    public func onQueryChanged() {
        // Cancel any pending search
        searchTask?.cancel()

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedQuery.count >= 2 else {
            results = []
            isSearching = false
            return
        }

        searchTask = Task {
            // Debounce
            try? await Task.sleep(for: debounceInterval)

            guard !Task.isCancelled else { return }

            await performSearch(query: trimmedQuery, page: 1, append: false)
        }
    }

    /// Load more search results (pagination).
    public func loadMoreResults() async {
        guard hasMoreResults, !isSearching else { return }
        let nextPage = currentPage + 1
        await performSearch(query: query, page: nextPage, append: true)
    }

    /// Execute a search from recent searches or suggestion.
    public func executeSearch(_ searchQuery: String) {
        query = searchQuery
        onQueryChanged()
    }

    /// Clear search results and query.
    public func clearSearch() {
        query = ""
        results = []
        isSearching = false
        searchTask?.cancel()
    }

    // MARK: - Private

    private func performSearch(query: String, page: Int, append: Bool) async {
        if !append {
            isSearching = true
        }
        errorMessage = nil

        do {
            let response = try await apiClient.execute(
                Endpoints.searchSamples(query: query, page: page, pageSize: pageSize)
            )

            guard !Task.isCancelled else { return }

            if append {
                results.append(contentsOf: response.items)
            } else {
                results = response.items
                // Save to recent searches
                addToRecentSearches(query)
            }

            hasMoreResults = response.hasNextPage
            currentPage = page
        } catch {
            if !Task.isCancelled {
                errorMessage = error.localizedDescription
            }
        }

        isSearching = false
    }

    private func addToRecentSearches(_ query: String) {
        // Remove duplicates and keep most recent at top
        recentSearches.removeAll { $0.lowercased() == query.lowercased() }
        recentSearches.insert(query, at: 0)
        // Keep only the last 10
        if recentSearches.count > 10 {
            recentSearches = Array(recentSearches.prefix(10))
        }
    }
}

// MARK: - Search View

/// Full-text search view with debounced search-as-you-type, recent searches, and results.
public struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @EnvironmentObject private var appState: AppState
    @FocusState private var isSearchFieldFocused: Bool
    @State private var selectedSample: Sample?

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Search header
            searchHeader

            Divider().background(SCColor.border)

            // Content
            if viewModel.isSearching && viewModel.results.isEmpty {
                searchingView
            } else if !viewModel.query.isEmpty && viewModel.results.isEmpty && !viewModel.isSearching {
                noResultsView
            } else if viewModel.results.isEmpty {
                recentSearchesView
            } else {
                searchResultsList
            }
        }
        .background(SCColor.backgroundPrimary)
        .sheet(item: $selectedSample) { sample in
            SampleDetailView(sample: sample)
        }
    }

    // MARK: - Search Header

    private var searchHeader: some View {
        VStack(spacing: SCSpacing.md) {
            HStack(spacing: SCSpacing.md) {
                // Search field
                HStack(spacing: SCSpacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundStyle(SCColor.textTertiary)

                    TextField("Search samples, creators, genres...", text: $viewModel.query)
                        .font(SCFont.body)
                        .textFieldStyle(.plain)
                        .foregroundStyle(SCColor.textPrimary)
                        .focused($isSearchFieldFocused)
                        .onChange(of: viewModel.query) { _, _ in
                            viewModel.onQueryChanged()
                        }
                        .onSubmit {
                            viewModel.onQueryChanged()
                        }

                    if !viewModel.query.isEmpty {
                        Button {
                            viewModel.clearSearch()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(SCColor.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }

                    if viewModel.isSearching {
                        ProgressView()
                            .tint(SCColor.accent)
                            .scaleEffect(0.7)
                    }
                }
                .padding(.horizontal, SCSpacing.md)
                .padding(.vertical, SCSpacing.sm)
                .background(SCColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: SCRadius.lg))
            }

            // Result count
            if !viewModel.results.isEmpty {
                HStack {
                    Text("\(viewModel.results.count) results")
                        .font(SCFont.bodySmall)
                        .foregroundStyle(SCColor.textTertiary)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, SCSpacing.lg)
        .padding(.vertical, SCSpacing.md)
        .onAppear {
            isSearchFieldFocused = true
        }
    }

    // MARK: - Results

    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: SCSpacing.xxs) {
                ForEach(viewModel.results) { sample in
                    SampleCell(sample: sample, displayMode: .list)
                        .onTapGesture {
                            selectedSample = sample
                        }
                        .onAppear {
                            if sample.id == viewModel.results.last?.id {
                                Task {
                                    await viewModel.loadMoreResults()
                                }
                            }
                        }
                }
            }
            .padding(.horizontal, SCSpacing.lg)
            .padding(.vertical, SCSpacing.sm)
        }
    }

    // MARK: - States

    private var searchingView: some View {
        VStack(spacing: SCSpacing.lg) {
            ProgressView()
                .tint(SCColor.accent)
                .scaleEffect(1.5)
            Text("Searching...")
                .font(SCFont.body)
                .foregroundStyle(SCColor.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsView: some View {
        VStack(spacing: SCSpacing.lg) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(SCColor.textTertiary)
            Text("No results found")
                .font(SCFont.heading2)
                .foregroundStyle(SCColor.textPrimary)
            Text("Try different keywords or adjust your search terms.")
                .font(SCFont.body)
                .foregroundStyle(SCColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recentSearchesView: some View {
        VStack(alignment: .leading, spacing: SCSpacing.lg) {
            if !viewModel.recentSearches.isEmpty {
                VStack(alignment: .leading, spacing: SCSpacing.md) {
                    HStack {
                        Text("Recent Searches")
                            .font(SCFont.heading3)
                            .foregroundStyle(SCColor.textSecondary)
                        Spacer()
                        Button("Clear") {
                            viewModel.recentSearches = []
                        }
                        .font(SCFont.bodySmall)
                        .foregroundStyle(SCColor.accent)
                        .buttonStyle(.plain)
                    }

                    ForEach(viewModel.recentSearches, id: \.self) { query in
                        Button {
                            viewModel.executeSearch(query)
                        } label: {
                            HStack(spacing: SCSpacing.sm) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 12))
                                    .foregroundStyle(SCColor.textTertiary)
                                Text(query)
                                    .font(SCFont.body)
                                    .foregroundStyle(SCColor.textPrimary)
                                Spacer()
                                Image(systemName: "arrow.up.left")
                                    .font(.system(size: 10))
                                    .foregroundStyle(SCColor.textTertiary)
                            }
                            .padding(.vertical, SCSpacing.xs)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, SCSpacing.lg)
                .padding(.top, SCSpacing.lg)
            } else {
                VStack(spacing: SCSpacing.md) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundStyle(SCColor.textTertiary)
                    Text("Search for samples")
                        .font(SCFont.heading2)
                        .foregroundStyle(SCColor.textPrimary)
                    Text("Search by title, creator, genre, instrument, or keyword.")
                        .font(SCFont.body)
                        .foregroundStyle(SCColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer()
        }
    }
}
