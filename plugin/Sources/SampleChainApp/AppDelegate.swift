// AppDelegate.swift
// SampleChainApp
//
// NSApplicationDelegate for handling drag-and-drop from Finder, file associations,
// and application lifecycle events.

import AppKit
import Foundation
import UniformTypeIdentifiers
import SampleChainCore
import SampleChainDSP

// MARK: - App Delegate

/// Application delegate handling macOS-specific lifecycle events, file handling,
/// and drag-and-drop support.
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// URLs that were opened via Finder double-click or drag-drop onto the dock icon.
    private var pendingFileURLs: [URL] = []

    /// The audio engine instance for standalone playback.
    private(set) var audioEngine: AudioEngine?

    // MARK: - Application Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Configure the audio engine for standalone use
        let engine = AudioEngine(configuration: .default)
        do {
            try engine.start()
            self.audioEngine = engine
        } catch {
            print("SampleChain: Failed to start audio engine: \(error.localizedDescription)")
        }

        // Register for file drag-and-drop on the dock icon
        NSApp.registerForRemoteNotifications()

        // Process any files that were queued before the app finished launching
        processPendingFiles()

        // Set the app appearance to dark mode
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Clean up audio engine
        audioEngine?.stop()
        audioEngine = nil
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep the app running even if all windows are closed (common for audio apps)
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Reopen the main window when clicking the dock icon
        if !flag {
            // Re-show the main window
            for window in sender.windows {
                window.makeKeyAndOrderFront(self)
                break
            }
        }
        return true
    }

    // MARK: - File Handling

    /// Called when audio files are opened via Finder (double-click, "Open With", etc.).
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.compactMap { URL(fileURLWithPath: $0) }
        handleOpenedFiles(urls)
        sender.reply(toOpenOrPrint: .success)
    }

    /// Called when files are opened via URL scheme or drag-drop onto dock icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        handleOpenedFiles(urls)
    }

    /// Handle files opened from external sources.
    ///
    /// Validates that the files are supported audio formats, then routes them
    /// to the appropriate handler (upload view or direct preview).
    private func handleOpenedFiles(_ urls: [URL]) {
        let supportedExtensions = Set(["wav", "aiff", "aif", "mp3", "flac", "ogg", "m4a", "caf"])

        let audioURLs = urls.filter { url in
            supportedExtensions.contains(url.pathExtension.lowercased())
        }

        guard !audioURLs.isEmpty else {
            showUnsupportedFileAlert(urls: urls)
            return
        }

        // If the app hasn't finished launching, queue the files
        if NSApp.isRunning {
            processAudioFiles(audioURLs)
        } else {
            pendingFileURLs.append(contentsOf: audioURLs)
        }
    }

    /// Process pending files that were opened before the app finished launching.
    private func processPendingFiles() {
        guard !pendingFileURLs.isEmpty else { return }
        processAudioFiles(pendingFileURLs)
        pendingFileURLs.removeAll()
    }

    /// Route opened audio files to the upload view or preview player.
    private func processAudioFiles(_ urls: [URL]) {
        // For a single file, load it for preview or navigate to upload
        // For multiple files, navigate to upload view with batch mode

        // Post a notification that views can observe
        NotificationCenter.default.post(
            name: .sampleChainDidOpenFiles,
            object: nil,
            userInfo: ["urls": urls]
        )

        // Also try to load the first file into the engine for preview
        if let firstURL = urls.first, let engine = audioEngine {
            do {
                let channelIndex = engine.firstAvailableChannel() ?? 0
                try engine.loadSample(
                    fileURL: firstURL,
                    onChannel: channelIndex,
                    tokenId: "local-\(firstURL.lastPathComponent)"
                )
                engine.play(channel: channelIndex)
            } catch {
                print("SampleChain: Failed to load file for preview: \(error.localizedDescription)")
            }
        }
    }

    /// Show an alert for unsupported file types.
    private func showUnsupportedFileAlert(urls: [URL]) {
        let alert = NSAlert()
        alert.messageText = "Unsupported File Format"
        alert.informativeText = "SampleChain supports WAV, AIFF, MP3, FLAC, and other common audio formats."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Services

    /// Register services for the macOS Services menu (e.g. "Open in SampleChain").
    @objc func openInSampleChain(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let items = pboard.pasteboardItems else { return }

        var urls: [URL] = []
        for item in items {
            if let urlString = item.string(forType: .fileURL),
               let url = URL(string: urlString) {
                urls.append(url)
            }
        }

        if !urls.isEmpty {
            handleOpenedFiles(urls)
        }
    }
}

// MARK: - Notification Names

public extension Notification.Name {
    /// Posted when audio files are opened from Finder or drag-and-drop.
    /// The `userInfo` dictionary contains an "urls" key with `[URL]` value.
    static let sampleChainDidOpenFiles = Notification.Name("SampleChainDidOpenFiles")
}

// MARK: - Drag and Drop Support

/// Drag-and-drop destination for the main window.
///
/// This extension adds support for dragging audio files from Finder directly
/// into the app window, which routes them to the upload or preview flow.
extension NSView {
    /// Register a view for receiving audio file drops.
    func registerForAudioFileDrop() {
        registerForDraggedTypes([.fileURL])
    }
}
