// SampleChainApp.swift
// SampleChainApp
//
// @main SwiftUI App entry point for the standalone SampleChain host application.

import SwiftUI
import SampleChainCore
import SampleChainUI
import SampleChainDSP
import SampleChainAU

// MARK: - SampleChain App

/// The standalone SampleChain macOS application.
///
/// This app serves as:
/// - A standalone host for browsing, purchasing, and managing samples
/// - A development and testing environment for the AU plugin
/// - The host application that contains the AUv3 app extension
///
/// The app uses the same SwiftUI views as the AU plugin (via ``SampleChainUI``),
/// but in a full windowed environment with menu bar, keyboard shortcuts,
/// and drag-and-drop from Finder.
@main
struct SampleChainApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        // Main window
        WindowGroup("SampleChain") {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    initializeServices()
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 800)
        .commands {
            // Custom menu commands
            sampleChainCommands
        }

        // Settings window
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }

    // MARK: - Menu Commands

    @CommandsBuilder
    private var sampleChainCommands: some Commands {
        // File menu additions
        CommandGroup(after: .newItem) {
            Button("Import Sample...") {
                importSample()
            }
            .keyboardShortcut("i", modifiers: [.command])

            Divider()
        }

        // View menu additions
        CommandMenu("Navigate") {
            ForEach(NavigationTab.allCases) { tab in
                Button(tab.rawValue) {
                    appState.selectedTab = tab
                }
                .keyboardShortcut(tab.shortcutKey ?? "1", modifiers: [.command])
            }
        }

        // Playback menu
        CommandMenu("Playback") {
            Button("Play / Pause") {
                appState.isPreviewPlaying.toggle()
            }
            .keyboardShortcut(.space, modifiers: [])

            Button("Stop") {
                appState.isPreviewPlaying = false
                appState.previewSample = nil
            }
            .keyboardShortcut(".", modifiers: [.command])

            Divider()

            Button("Clear Preview") {
                appState.previewSample = nil
                appState.isPreviewPlaying = false
            }
            .keyboardShortcut(.delete, modifiers: [.command])
        }
    }

    // MARK: - Initialization

    /// Initialize background services on app launch.
    private func initializeServices() {
        Task {
            // Initialize the sample cache
            let cache = SampleCacheManager()
            try? await cache.initialize()
        }
    }

    /// Open a file dialog for importing a sample.
    private func importSample() {
        let panel = NSOpenPanel()
        panel.title = "Import Audio Sample"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            .audio,
            .wav,
            .aiff,
        ]

        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task { @MainActor in
                    appState.selectedTab = .upload
                    // The UploadView will handle the file
                }
            }
        }
    }
}

// MARK: - Settings View

/// Application settings view.
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("cacheMaxSizeGB") private var cacheMaxSizeGB: Double = 2.0
    @AppStorage("apiEnvironment") private var apiEnvironment: String = "production"
    @AppStorage("defaultSortField") private var defaultSortField: String = "newest"
    @AppStorage("autoDetectBPM") private var autoDetectBPM: Bool = true
    @AppStorage("autoDetectKey") private var autoDetectKey: Bool = true

    var body: some View {
        TabView {
            generalSettings
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            cacheSettings
                .tabItem {
                    Label("Cache", systemImage: "internaldrive")
                }

            networkSettings
                .tabItem {
                    Label("Network", systemImage: "network")
                }
        }
        .frame(width: 500, height: 400)
    }

    private var generalSettings: some View {
        Form {
            Section("Audio Analysis") {
                Toggle("Auto-detect BPM on upload", isOn: $autoDetectBPM)
                Toggle("Auto-detect musical key on upload", isOn: $autoDetectKey)
            }

            Section("Browsing") {
                Picker("Default sort order", selection: $defaultSortField) {
                    ForEach(SampleSortField.allCases, id: \.rawValue) { field in
                        Text(field.displayName).tag(field.rawValue)
                    }
                }
            }
        }
        .padding()
    }

    private var cacheSettings: some View {
        Form {
            Section("Sample Cache") {
                HStack {
                    Text("Maximum cache size:")
                    Slider(value: $cacheMaxSizeGB, in: 0.5...10.0, step: 0.5)
                    Text("\(String(format: "%.1f", cacheMaxSizeGB)) GB")
                        .font(SCFont.mono)
                        .frame(width: 50)
                }

                HStack {
                    Text("Current cache usage:")
                    Spacer()
                    Text("-- MB") // Would be populated from SampleCacheManager
                        .font(SCFont.mono)
                        .foregroundStyle(SCColor.textSecondary)
                }

                Button("Clear Cache") {
                    Task {
                        let cache = SampleCacheManager()
                        try? await cache.clearAll()
                    }
                }
            }
        }
        .padding()
    }

    private var networkSettings: some View {
        Form {
            Section("API") {
                Picker("Environment", selection: $apiEnvironment) {
                    Text("Production").tag("production")
                    Text("Development").tag("development")
                }
            }

            Section("Blockchain") {
                Text("Connected chain: Base")
                    .foregroundStyle(SCColor.textSecondary)
                Text("RPC endpoint: https://mainnet.base.org")
                    .font(SCFont.monoSmall)
                    .foregroundStyle(SCColor.textTertiary)
            }
        }
        .padding()
    }
}
