// ContentView.swift
// SampleChainUI
//
// Main tab bar navigation view providing access to Browse, Search, Library, Upload, and Wallet tabs.

import SwiftUI
import SampleChainCore

// MARK: - Navigation Tab

/// The main navigation tabs of the SampleChain plugin.
public enum NavigationTab: String, CaseIterable, Identifiable {
    case browse = "Browse"
    case search = "Search"
    case library = "Library"
    case upload = "Upload"
    case wallet = "Wallet"

    public var id: String { rawValue }

    /// SF Symbol name for the tab icon.
    public var iconName: String {
        switch self {
        case .browse: return "square.grid.2x2"
        case .search: return "magnifyingglass"
        case .library: return "music.note.list"
        case .upload: return "arrow.up.circle"
        case .wallet: return "wallet.pass"
        }
    }

    /// Keyboard shortcut for the tab.
    public var shortcutKey: KeyEquivalent? {
        switch self {
        case .browse: return "1"
        case .search: return "2"
        case .library: return "3"
        case .upload: return "4"
        case .wallet: return "5"
        }
    }
}

// MARK: - App State

/// Observable app-wide state shared across all views.
@MainActor
public final class AppState: ObservableObject {
    /// The currently selected navigation tab.
    @Published public var selectedTab: NavigationTab = .browse
    /// The active sample filter (shared between Browse and Search).
    @Published public var activeFilter: SampleFilter = SampleFilter()
    /// Whether a sample is currently being previewed in the floating player.
    @Published public var isPreviewPlaying: Bool = false
    /// The sample currently loaded in the preview player, if any.
    @Published public var previewSample: Sample?
    /// Whether the app is in compact layout mode (e.g. AU plugin view).
    @Published public var isCompactMode: Bool = false
    /// Global error message to display.
    @Published public var errorMessage: String?

    public init() {}

    /// Dismiss the current error message.
    public func dismissError() {
        errorMessage = nil
    }

    /// Show a temporary error message.
    public func showError(_ message: String) {
        errorMessage = message
    }
}

// MARK: - Content View

/// The root view of the SampleChain plugin, providing tab-based navigation.
///
/// Displays a sidebar or top tab bar (adapting to available space) with sections for
/// Browse, Search, Library, Upload, and Wallet. A floating mini-player appears
/// at the bottom when a sample is being previewed.
public struct ContentView: View {
    @StateObject private var appState = AppState()
    @State private var sidebarWidth: CGFloat = 200

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            // Main content area with sidebar navigation
            NavigationSplitView {
                sidebarContent
                    .frame(minWidth: 180, idealWidth: 200)
            } detail: {
                selectedTabView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(SCColor.backgroundPrimary)
            }
            .navigationSplitViewStyle(.balanced)

            // Floating mini player
            if appState.isPreviewPlaying, let sample = appState.previewSample {
                MiniPlayerView(sample: sample)
                    .padding(.horizontal, SCSpacing.lg)
                    .padding(.bottom, SCSpacing.sm)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Error toast
            if let errorMessage = appState.errorMessage {
                errorToast(message: errorMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .environmentObject(appState)
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.25), value: appState.isPreviewPlaying)
        .animation(.easeInOut(duration: 0.2), value: appState.errorMessage)
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Logo / Title
            HStack(spacing: SCSpacing.sm) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(SCColor.accent)
                Text("SampleChain")
                    .font(SCFont.heading2)
                    .foregroundStyle(SCColor.textPrimary)
            }
            .padding(.horizontal, SCSpacing.lg)
            .padding(.vertical, SCSpacing.xl)

            Divider()
                .background(SCColor.border)

            // Navigation items
            VStack(spacing: SCSpacing.xxs) {
                ForEach(NavigationTab.allCases) { tab in
                    sidebarButton(for: tab)
                }
            }
            .padding(.horizontal, SCSpacing.sm)
            .padding(.top, SCSpacing.md)

            Spacer()

            // Version info
            Text("v1.0.0")
                .font(SCFont.labelSmall)
                .foregroundStyle(SCColor.textTertiary)
                .padding(.horizontal, SCSpacing.lg)
                .padding(.bottom, SCSpacing.lg)
        }
        .background(SCColor.backgroundSecondary)
    }

    private func sidebarButton(for tab: NavigationTab) -> some View {
        Button {
            appState.selectedTab = tab
        } label: {
            HStack(spacing: SCSpacing.md) {
                Image(systemName: tab.iconName)
                    .font(.system(size: 14))
                    .frame(width: 20)
                Text(tab.rawValue)
                    .font(SCFont.bodyMedium)
                Spacer()
            }
            .padding(.horizontal, SCSpacing.md)
            .padding(.vertical, SCSpacing.sm)
            .foregroundStyle(
                appState.selectedTab == tab ? SCColor.accent : SCColor.textSecondary
            )
            .background(
                appState.selectedTab == tab ? SCColor.accentMuted : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: SCRadius.md))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var selectedTabView: some View {
        switch appState.selectedTab {
        case .browse:
            BrowseView()
        case .search:
            SearchView()
        case .library:
            LibraryView()
        case .upload:
            UploadView()
        case .wallet:
            WalletView()
        }
    }

    // MARK: - Error Toast

    private func errorToast(message: String) -> some View {
        HStack(spacing: SCSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(SCColor.error)
            Text(message)
                .font(SCFont.body)
                .foregroundStyle(SCColor.textPrimary)
            Spacer()
            Button {
                appState.dismissError()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(SCColor.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(SCSpacing.md)
        .background(SCColor.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: SCRadius.lg))
        .scShadow(SCShadow.lg)
        .padding(.horizontal, SCSpacing.xxl)
        .padding(.top, SCSpacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Mini Player View

/// A floating mini-player bar showing the currently previewing sample.
struct MiniPlayerView: View {
    let sample: Sample
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: SCSpacing.md) {
            // Waveform thumbnail
            RoundedRectangle(cornerRadius: SCRadius.sm)
                .fill(SCColor.surface)
                .frame(width: 48, height: 32)
                .overlay {
                    if let waveform = sample.waveformData {
                        MiniWaveformShape(peaks: waveform.peaks)
                            .stroke(SCColor.accent, lineWidth: 1)
                            .padding(4)
                    }
                }

            // Sample info
            VStack(alignment: .leading, spacing: 2) {
                Text(sample.title)
                    .font(SCFont.bodyMedium)
                    .foregroundStyle(SCColor.textPrimary)
                    .lineLimit(1)

                HStack(spacing: SCSpacing.xs) {
                    if let bpm = sample.bpm {
                        Text("\(Int(bpm)) BPM")
                            .font(SCFont.monoSmall)
                            .foregroundStyle(SCColor.textSecondary)
                    }
                    if let key = sample.musicalKey {
                        Text(key.description)
                            .font(SCFont.monoSmall)
                            .foregroundStyle(SCColor.textSecondary)
                    }
                }
            }

            Spacer()

            // Transport controls
            Button {
                // Toggle play/pause handled by parent
            } label: {
                Image(systemName: "pause.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(SCColor.textPrimary)
            }
            .buttonStyle(.plain)

            Button {
                appState.isPreviewPlaying = false
                appState.previewSample = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12))
                    .foregroundStyle(SCColor.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, SCSpacing.lg)
        .padding(.vertical, SCSpacing.sm)
        .background(SCColor.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: SCRadius.lg))
        .scShadow(SCShadow.lg)
    }
}

/// Simple waveform shape for the mini player thumbnail.
private struct MiniWaveformShape: Shape {
    let peaks: [Float]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard peaks.count > 1 else { return path }

        let stepWidth = rect.width / CGFloat(peaks.count - 1)
        let midY = rect.midY

        path.move(to: CGPoint(x: 0, y: midY))

        for (index, peak) in peaks.enumerated() {
            let x = CGFloat(index) * stepWidth
            let amplitude = CGFloat(peak) * rect.height / 2
            path.addLine(to: CGPoint(x: x, y: midY - amplitude))
        }

        return path
    }
}
