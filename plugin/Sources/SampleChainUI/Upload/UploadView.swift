// UploadView.swift
// SampleChainUI
//
// Drag-and-drop upload area with auto-detected BPM/key, price/edition inputs,
// and mint progress tracking.

import SwiftUI
import SampleChainCore
import UniformTypeIdentifiers

// MARK: - Upload State

/// State machine for the upload/mint flow.
public enum UploadState: Equatable {
    case idle
    case analyzing
    case readyToMint
    case uploading(progress: Double)
    case minting
    case complete(tokenId: String)
    case error(String)
}

// MARK: - Upload View Model

/// View model for the sample upload and minting flow.
@MainActor
public final class UploadViewModel: ObservableObject {
    // File state
    @Published public var selectedFileURL: URL?
    @Published public var fileName: String = ""
    @Published public var fileSize: String = ""

    // Metadata
    @Published public var title: String = ""
    @Published public var description: String = ""
    @Published public var selectedGenres: Set<Genre> = []
    @Published public var selectedSampleType: SampleType = .loop
    @Published public var selectedLicenseTier: LicenseTier = .commercial

    // Detected attributes
    @Published public var detectedBPM: Double?
    @Published public var detectedKey: MusicalKey?
    @Published public var bpmOverride: String = ""
    @Published public var keyOverride: MusicalKey?

    // Commercial settings
    @Published public var priceETH: String = "0"
    @Published public var editionCount: String = "100"

    // Upload state
    @Published public var uploadState: UploadState = .idle
    @Published public var isDraggingOver: Bool = false

    /// Whether the form has enough data to proceed with minting.
    public var isReadyToMint: Bool {
        selectedFileURL != nil
            && !title.isEmpty
            && uploadState == .readyToMint
    }

    /// Effective BPM (override or detected).
    public var effectiveBPM: Double? {
        if let override = Double(bpmOverride), override > 0 {
            return override
        }
        return detectedBPM
    }

    /// Effective key (override or detected).
    public var effectiveKey: MusicalKey? {
        keyOverride ?? detectedKey
    }

    public init() {}

    /// Handle a file being dropped or selected.
    public func handleFile(_ url: URL) async {
        selectedFileURL = url
        fileName = url.lastPathComponent
        title = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        // Get file size
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            fileSize = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }

        // Analyze audio
        uploadState = .analyzing
        await analyzeAudio(url: url)
        uploadState = .readyToMint
    }

    /// Analyze the audio file for BPM and key detection.
    private func analyzeAudio(url: URL) async {
        // BPM detection would use BPMDetector
        // Key detection would use KeyDetector
        // For now, set placeholder values
        detectedBPM = nil
        detectedKey = nil

        // In production:
        // let bpmDetector = BPMDetector()
        // let bpmResult = try? await bpmDetector.detect(fileURL: url)
        // detectedBPM = bpmResult?.bpm
        //
        // let keyDetector = KeyDetector()
        // let keyResult = try? await keyDetector.detect(fileURL: url)
        // detectedKey = keyResult?.key
    }

    /// Start the upload and minting process.
    public func startMint() async {
        guard let fileURL = selectedFileURL else { return }

        // Phase 1: Upload to IPFS
        uploadState = .uploading(progress: 0)

        // Simulated progress -- in production, use APIClient.upload with progressHandler
        for i in 1...10 {
            try? await Task.sleep(nanoseconds: 200_000_000)
            uploadState = .uploading(progress: Double(i) / 10.0)
        }

        // Phase 2: Mint on-chain
        uploadState = .minting

        // In production:
        // let response = try await apiClient.upload(path: "/samples/upload", fileURL: fileURL, ...)
        // let web3 = Web3Service(...)
        // let txHash = try await web3.mintSample(...)
        // try await web3.waitForConfirmation(txHash: txHash)

        try? await Task.sleep(nanoseconds: 2_000_000_000)

        uploadState = .complete(tokenId: "0")
    }

    /// Reset the form for a new upload.
    public func reset() {
        selectedFileURL = nil
        fileName = ""
        fileSize = ""
        title = ""
        description = ""
        selectedGenres = []
        selectedSampleType = .loop
        selectedLicenseTier = .commercial
        detectedBPM = nil
        detectedKey = nil
        bpmOverride = ""
        keyOverride = nil
        priceETH = "0"
        editionCount = "100"
        uploadState = .idle
    }
}

// MARK: - Upload View

/// Upload view with drag-and-drop, auto-detection, metadata form, and mint progress.
public struct UploadView: View {
    @StateObject private var viewModel = UploadViewModel()
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: SCSpacing.xxl) {
                // Header
                uploadHeader

                // Content based on state
                switch viewModel.uploadState {
                case .idle:
                    dropZone
                case .analyzing:
                    analyzingView
                case .readyToMint:
                    VStack(spacing: SCSpacing.xxl) {
                        fileInfoBar
                        metadataForm
                        commercialSettings
                        mintButton
                    }
                case .uploading(let progress):
                    progressView(phase: "Uploading to IPFS...", progress: progress)
                case .minting:
                    progressView(phase: "Minting on-chain...", progress: nil)
                case .complete(let tokenId):
                    completionView(tokenId: tokenId)
                case .error(let message):
                    errorView(message: message)
                }
            }
            .padding(SCSpacing.xxl)
        }
        .background(SCColor.backgroundPrimary)
    }

    // MARK: - Header

    private var uploadHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: SCSpacing.xxs) {
                Text("Upload Sample")
                    .font(SCFont.heading1)
                    .foregroundStyle(SCColor.textPrimary)
                Text("Upload your audio and mint it as an NFT on SampleChain.")
                    .font(SCFont.body)
                    .foregroundStyle(SCColor.textSecondary)
            }
            Spacer()
        }
    }

    // MARK: - Drop Zone

    private var dropZone: some View {
        VStack(spacing: SCSpacing.lg) {
            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 48))
                .foregroundStyle(viewModel.isDraggingOver ? SCColor.accent : SCColor.textTertiary)

            Text("Drop audio file here")
                .font(SCFont.heading2)
                .foregroundStyle(SCColor.textPrimary)

            Text("WAV, AIFF, FLAC, or MP3 -- Max 100 MB")
                .font(SCFont.body)
                .foregroundStyle(SCColor.textSecondary)

            Text("or")
                .font(SCFont.bodySmall)
                .foregroundStyle(SCColor.textTertiary)

            Button {
                // Open file picker
                openFilePicker()
            } label: {
                Text("Choose File")
                    .font(SCFont.bodyMedium)
                    .foregroundStyle(SCColor.accent)
                    .padding(.horizontal, SCSpacing.xxl)
                    .padding(.vertical, SCSpacing.sm)
                    .overlay(
                        RoundedRectangle(cornerRadius: SCRadius.lg)
                            .strokeBorder(SCColor.accent, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SCSpacing.xxxxl)
        .background(
            RoundedRectangle(cornerRadius: SCRadius.xl)
                .strokeBorder(
                    viewModel.isDraggingOver ? SCColor.accent : SCColor.border,
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
        )
        .background(
            viewModel.isDraggingOver
                ? SCColor.accentMuted
                : SCColor.backgroundSecondary
        )
        .clipShape(RoundedRectangle(cornerRadius: SCRadius.xl))
        .onDrop(of: [.audio, .fileURL], isTargeted: $viewModel.isDraggingOver) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    // MARK: - File Info Bar

    private var fileInfoBar: some View {
        HStack(spacing: SCSpacing.md) {
            Image(systemName: "doc.fill")
                .font(.system(size: 20))
                .foregroundStyle(SCColor.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.fileName)
                    .font(SCFont.bodyMedium)
                    .foregroundStyle(SCColor.textPrimary)
                    .lineLimit(1)
                Text(viewModel.fileSize)
                    .font(SCFont.bodySmall)
                    .foregroundStyle(SCColor.textTertiary)
            }

            Spacer()

            // Detected BPM and Key
            if let bpm = viewModel.detectedBPM {
                Text("\(Int(bpm)) BPM")
                    .scBadge(color: SCColor.accent)
            }
            if let key = viewModel.detectedKey {
                Text(key.description)
                    .scBadge(color: SCColor.info)
            }

            // Change file button
            Button {
                viewModel.reset()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(SCColor.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(SCSpacing.md)
        .scCard()
    }

    // MARK: - Metadata Form

    private var metadataForm: some View {
        VStack(alignment: .leading, spacing: SCSpacing.lg) {
            Text("Metadata")
                .font(SCFont.heading2)
                .foregroundStyle(SCColor.textPrimary)

            // Title
            formField(label: "Title") {
                TextField("Sample title", text: $viewModel.title)
                    .textFieldStyle(.plain)
                    .font(SCFont.body)
                    .padding(SCSpacing.sm)
                    .background(SCColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: SCRadius.md))
            }

            // Description
            formField(label: "Description (optional)") {
                TextField("Describe your sample...", text: $viewModel.description, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(SCFont.body)
                    .lineLimit(3...6)
                    .padding(SCSpacing.sm)
                    .background(SCColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: SCRadius.md))
            }

            // Sample Type
            formField(label: "Sample Type") {
                Picker("Type", selection: $viewModel.selectedSampleType) {
                    ForEach(SampleType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.menu)
            }

            // Genre tags
            formField(label: "Genres") {
                FlowLayout(spacing: SCSpacing.xxs) {
                    ForEach(Genre.allCases, id: \.self) { genre in
                        Button {
                            if viewModel.selectedGenres.contains(genre) {
                                viewModel.selectedGenres.remove(genre)
                            } else {
                                viewModel.selectedGenres.insert(genre)
                            }
                        } label: {
                            Text(genre.displayName)
                                .font(SCFont.labelSmall)
                                .foregroundStyle(
                                    viewModel.selectedGenres.contains(genre)
                                    ? SCColor.accent : SCColor.textSecondary
                                )
                                .padding(.horizontal, SCSpacing.sm)
                                .padding(.vertical, SCSpacing.xxs)
                                .background(
                                    viewModel.selectedGenres.contains(genre)
                                    ? SCColor.accentMuted : SCColor.surface
                                )
                                .clipShape(RoundedRectangle(cornerRadius: SCRadius.pill))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // BPM Override
            HStack(spacing: SCSpacing.xxl) {
                formField(label: "BPM") {
                    HStack {
                        TextField(
                            viewModel.detectedBPM.map { "\(Int($0))" } ?? "Auto-detect",
                            text: $viewModel.bpmOverride
                        )
                        .textFieldStyle(.plain)
                        .font(SCFont.mono)
                        .padding(SCSpacing.sm)
                        .background(SCColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: SCRadius.md))
                        .frame(width: 100)

                        if viewModel.detectedBPM != nil {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(SCColor.success)
                                .font(.system(size: 14))
                        }
                    }
                }

                formField(label: "Key") {
                    HStack {
                        if let key = viewModel.effectiveKey {
                            Text(key.description)
                                .font(SCFont.mono)
                                .foregroundStyle(SCColor.textPrimary)
                                .padding(SCSpacing.sm)
                                .background(SCColor.surface)
                                .clipShape(RoundedRectangle(cornerRadius: SCRadius.md))
                        } else {
                            Text("Auto-detect")
                                .font(SCFont.mono)
                                .foregroundStyle(SCColor.textTertiary)
                                .padding(SCSpacing.sm)
                                .background(SCColor.surface)
                                .clipShape(RoundedRectangle(cornerRadius: SCRadius.md))
                        }
                    }
                }
            }
        }
        .padding(SCSpacing.lg)
        .scCard()
    }

    // MARK: - Commercial Settings

    private var commercialSettings: some View {
        VStack(alignment: .leading, spacing: SCSpacing.lg) {
            Text("Pricing & License")
                .font(SCFont.heading2)
                .foregroundStyle(SCColor.textPrimary)

            // License tier
            formField(label: "License") {
                Picker("License", selection: $viewModel.selectedLicenseTier) {
                    ForEach(LicenseTier.allCases, id: \.self) { tier in
                        Text(tier.displayName).tag(tier)
                    }
                }
                .pickerStyle(.segmented)
            }

            HStack(spacing: SCSpacing.xxl) {
                // Price
                formField(label: "Price (ETH)") {
                    HStack(spacing: SCSpacing.xxs) {
                        Image(systemName: "diamond.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(SCColor.ethereum)
                        TextField("0", text: $viewModel.priceETH)
                            .textFieldStyle(.plain)
                            .font(SCFont.mono)
                            .padding(SCSpacing.sm)
                            .background(SCColor.surface)
                            .clipShape(RoundedRectangle(cornerRadius: SCRadius.md))
                            .frame(width: 120)
                    }
                }

                // Edition count
                formField(label: "Editions") {
                    TextField("100", text: $viewModel.editionCount)
                        .textFieldStyle(.plain)
                        .font(SCFont.mono)
                        .padding(SCSpacing.sm)
                        .background(SCColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: SCRadius.md))
                        .frame(width: 120)
                }
            }

            // Price note
            if viewModel.priceETH == "0" {
                HStack(spacing: SCSpacing.xxs) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                    Text("Free samples can still be collected as editions.")
                        .font(SCFont.bodySmall)
                }
                .foregroundStyle(SCColor.textTertiary)
            }
        }
        .padding(SCSpacing.lg)
        .scCard()
    }

    // MARK: - Mint Button

    private var mintButton: some View {
        Button {
            Task {
                await viewModel.startMint()
            }
        } label: {
            HStack(spacing: SCSpacing.sm) {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 14))
                Text("Mint Sample")
                    .font(SCFont.heading3)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, SCSpacing.md)
            .background(
                viewModel.isReadyToMint ? SCColor.accent : SCColor.textDisabled
            )
            .clipShape(RoundedRectangle(cornerRadius: SCRadius.lg))
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.isReadyToMint)
    }

    // MARK: - Progress View

    private func progressView(phase: String, progress: Double?) -> some View {
        VStack(spacing: SCSpacing.xxl) {
            if let progress {
                ProgressView(value: progress)
                    .tint(SCColor.accent)
                    .frame(width: 300)
            } else {
                ProgressView()
                    .tint(SCColor.accent)
                    .scaleEffect(1.5)
            }

            Text(phase)
                .font(SCFont.heading2)
                .foregroundStyle(SCColor.textPrimary)

            if let progress {
                Text("\(Int(progress * 100))%")
                    .font(SCFont.monoLarge)
                    .foregroundStyle(SCColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SCSpacing.xxxxl)
    }

    private var analyzingView: some View {
        VStack(spacing: SCSpacing.lg) {
            ProgressView()
                .tint(SCColor.accent)
                .scaleEffect(1.5)
            Text("Analyzing audio...")
                .font(SCFont.heading2)
                .foregroundStyle(SCColor.textPrimary)
            Text("Detecting BPM and musical key")
                .font(SCFont.body)
                .foregroundStyle(SCColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SCSpacing.xxxxl)
    }

    // MARK: - Completion

    private func completionView(tokenId: String) -> some View {
        VStack(spacing: SCSpacing.xxl) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(SCColor.success)

            Text("Sample Minted!")
                .font(SCFont.displayMedium)
                .foregroundStyle(SCColor.textPrimary)

            Text("Your sample is now live on SampleChain.")
                .font(SCFont.body)
                .foregroundStyle(SCColor.textSecondary)

            Text("Token ID: #\(tokenId)")
                .font(SCFont.mono)
                .foregroundStyle(SCColor.textSecondary)

            Button {
                viewModel.reset()
            } label: {
                Text("Upload Another")
                    .font(SCFont.bodyMedium)
                    .foregroundStyle(SCColor.accent)
                    .padding(.horizontal, SCSpacing.xxl)
                    .padding(.vertical, SCSpacing.sm)
                    .overlay(
                        RoundedRectangle(cornerRadius: SCRadius.lg)
                            .strokeBorder(SCColor.accent, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SCSpacing.xxxxl)
    }

    // MARK: - Error

    private func errorView(message: String) -> some View {
        VStack(spacing: SCSpacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(SCColor.error)

            Text("Upload Failed")
                .font(SCFont.heading1)
                .foregroundStyle(SCColor.textPrimary)

            Text(message)
                .font(SCFont.body)
                .foregroundStyle(SCColor.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                viewModel.uploadState = .readyToMint
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

    private func formField<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: SCSpacing.xs) {
            Text(label)
                .font(SCFont.label)
                .foregroundStyle(SCColor.textTertiary)
            content()
        }
    }

    private func openFilePicker() {
        // In production, this would use NSOpenPanel
        // let panel = NSOpenPanel()
        // panel.allowedContentTypes = [.audio, .wav, .aiff]
        // ...
    }

    private func handleDrop(providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else {
                return
            }

            Task { @MainActor in
                await viewModel.handleFile(url)
            }
        }
    }
}
