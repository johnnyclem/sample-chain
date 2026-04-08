// SampleDetailView.swift
// SampleChainUI
//
// Full sample detail view with interactive waveform, pitch/tempo controls, and purchase button.

import SwiftUI
import SampleChainCore

// MARK: - Sample Detail View

/// Detailed view for a single sample showing full metadata, interactive waveform,
/// pitch/tempo adjustment controls, and purchase functionality.
public struct SampleDetailView: View {
    public let sample: Sample

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var isPlaying: Bool = false
    @State private var playbackPosition: Double = 0
    @State private var bpmOverride: Double = 0
    @State private var pitchShift: Double = 0
    @State private var isPurchasing: Bool = false
    @State private var isFavorite: Bool = false
    @State private var showCreatorProfile: Bool = false

    public init(sample: Sample) {
        self.sample = sample
        _bpmOverride = State(initialValue: sample.bpm ?? 120)
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header with dismiss button
                detailHeader

                // Waveform
                waveformSection

                // Transport and adjustment controls
                controlsSection

                Divider().background(SCColor.border).padding(.horizontal, SCSpacing.lg)

                // Metadata section
                metadataSection

                Divider().background(SCColor.border).padding(.horizontal, SCSpacing.lg)

                // Purchase section
                purchaseSection

                Spacer(minLength: SCSpacing.xxxl)
            }
        }
        .background(SCColor.backgroundPrimary)
        .frame(minWidth: 500, minHeight: 600)
    }

    // MARK: - Header

    private var detailHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: SCSpacing.xs) {
                Text(sample.title)
                    .font(SCFont.displayMedium)
                    .foregroundStyle(SCColor.textPrimary)

                Button {
                    showCreatorProfile = true
                } label: {
                    HStack(spacing: SCSpacing.xxs) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 14))
                        Text(shortCreatorAddress)
                            .font(SCFont.mono)
                    }
                    .foregroundStyle(SCColor.accent)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Favorite button
            Button {
                isFavorite.toggle()
            } label: {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 18))
                    .foregroundStyle(isFavorite ? SCColor.error : SCColor.textSecondary)
            }
            .buttonStyle(.plain)

            // Close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(SCColor.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(SCSpacing.lg)
    }

    // MARK: - Waveform

    private var waveformSection: some View {
        VStack(spacing: SCSpacing.sm) {
            // Interactive waveform
            if let waveformData = sample.waveformData {
                WaveformView(
                    waveformData: waveformData,
                    playbackPosition: $playbackPosition,
                    isPlaying: isPlaying
                )
                .frame(height: 120)
                .padding(.horizontal, SCSpacing.lg)
            } else {
                // Placeholder
                RoundedRectangle(cornerRadius: SCRadius.lg)
                    .fill(SCColor.surface)
                    .frame(height: 120)
                    .overlay {
                        Text("Waveform loading...")
                            .font(SCFont.body)
                            .foregroundStyle(SCColor.textTertiary)
                    }
                    .padding(.horizontal, SCSpacing.lg)
            }

            // Playback position
            HStack {
                Text(formatTime(playbackPosition * sample.durationSeconds))
                    .font(SCFont.monoSmall)
                    .foregroundStyle(SCColor.textSecondary)
                Spacer()
                Text(formatTime(sample.durationSeconds))
                    .font(SCFont.monoSmall)
                    .foregroundStyle(SCColor.textTertiary)
            }
            .padding(.horizontal, SCSpacing.lg)
        }
    }

    // MARK: - Controls

    private var controlsSection: some View {
        VStack(spacing: SCSpacing.lg) {
            // Transport
            HStack(spacing: SCSpacing.xl) {
                Spacer()

                // Skip back
                Button {
                    playbackPosition = max(0, playbackPosition - 0.1)
                } label: {
                    Image(systemName: "gobackward.5")
                        .font(.system(size: 18))
                        .foregroundStyle(SCColor.textSecondary)
                }
                .buttonStyle(.plain)

                // Play/Pause
                PlayButton(isPlaying: $isPlaying, size: .large) {
                    togglePlayback()
                }

                // Skip forward
                Button {
                    playbackPosition = min(1, playbackPosition + 0.1)
                } label: {
                    Image(systemName: "goforward.5")
                        .font(.system(size: 18))
                        .foregroundStyle(SCColor.textSecondary)
                }
                .buttonStyle(.plain)

                Spacer()
            }

            // BPM and Pitch controls
            HStack(spacing: SCSpacing.xxl) {
                // BPM control
                VStack(spacing: SCSpacing.xs) {
                    Text("BPM")
                        .font(SCFont.label)
                        .foregroundStyle(SCColor.textTertiary)

                    HStack(spacing: SCSpacing.sm) {
                        Button {
                            bpmOverride = max(40, bpmOverride - 1)
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 10, weight: .bold))
                                .frame(width: 24, height: 24)
                                .background(SCColor.surface)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)

                        Text("\(Int(bpmOverride))")
                            .font(SCFont.monoLarge)
                            .foregroundStyle(SCColor.textPrimary)
                            .frame(width: 50)

                        Button {
                            bpmOverride = min(300, bpmOverride + 1)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                                .frame(width: 24, height: 24)
                                .background(SCColor.surface)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    // Reset button
                    if let originalBPM = sample.bpm, bpmOverride != originalBPM {
                        Button("Reset") {
                            bpmOverride = originalBPM
                        }
                        .font(SCFont.labelSmall)
                        .foregroundStyle(SCColor.accent)
                        .buttonStyle(.plain)
                    }
                }

                Divider()
                    .frame(height: 60)
                    .background(SCColor.border)

                // Pitch control
                VStack(spacing: SCSpacing.xs) {
                    Text("PITCH")
                        .font(SCFont.label)
                        .foregroundStyle(SCColor.textTertiary)

                    HStack(spacing: SCSpacing.sm) {
                        Button {
                            pitchShift = max(-12, pitchShift - 1)
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 10, weight: .bold))
                                .frame(width: 24, height: 24)
                                .background(SCColor.surface)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)

                        Text(pitchShift >= 0 ? "+\(Int(pitchShift))" : "\(Int(pitchShift))")
                            .font(SCFont.monoLarge)
                            .foregroundStyle(SCColor.textPrimary)
                            .frame(width: 50)

                        Button {
                            pitchShift = min(12, pitchShift + 1)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                                .frame(width: 24, height: 24)
                                .background(SCColor.surface)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    if pitchShift != 0 {
                        Button("Reset") {
                            pitchShift = 0
                        }
                        .font(SCFont.labelSmall)
                        .foregroundStyle(SCColor.accent)
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, SCSpacing.xxxl)
        }
        .padding(.vertical, SCSpacing.lg)
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: SCSpacing.lg) {
            Text("Details")
                .font(SCFont.heading2)
                .foregroundStyle(SCColor.textPrimary)

            // Description
            if let description = sample.description {
                Text(description)
                    .font(SCFont.body)
                    .foregroundStyle(SCColor.textSecondary)
            }

            // Metadata grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: SCSpacing.md) {
                metadataItem(label: "Type", value: sample.sampleType.displayName)
                metadataItem(label: "BPM", value: sample.bpm.map { "\(Int($0))" } ?? "--")
                metadataItem(label: "Key", value: sample.musicalKey?.description ?? "--")
                metadataItem(label: "Duration", value: formatTime(sample.durationSeconds))
                metadataItem(label: "License", value: sample.licenseTier.displayName)
                metadataItem(label: "Token ID", value: "#\(sample.tokenId)")
            }

            // Genre tags
            if !sample.genres.isEmpty {
                VStack(alignment: .leading, spacing: SCSpacing.xs) {
                    Text("Genres")
                        .font(SCFont.label)
                        .foregroundStyle(SCColor.textTertiary)

                    FlowLayout(spacing: SCSpacing.xxs) {
                        ForEach(sample.genres, id: \.self) { genre in
                            Text(genre.displayName)
                                .scBadge(color: SCColor.accent)
                        }
                    }
                }
            }

            // IPFS info
            VStack(alignment: .leading, spacing: SCSpacing.xxs) {
                Text("IPFS CID")
                    .font(SCFont.label)
                    .foregroundStyle(SCColor.textTertiary)
                Text(sample.ipfsCid)
                    .font(SCFont.monoSmall)
                    .foregroundStyle(SCColor.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(SCSpacing.lg)
    }

    private func metadataItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: SCSpacing.xxxs) {
            Text(label)
                .font(SCFont.label)
                .foregroundStyle(SCColor.textTertiary)
            Text(value)
                .font(SCFont.bodyMedium)
                .foregroundStyle(SCColor.textPrimary)
        }
    }

    // MARK: - Purchase

    private var purchaseSection: some View {
        VStack(spacing: SCSpacing.lg) {
            HStack {
                VStack(alignment: .leading, spacing: SCSpacing.xxs) {
                    if sample.isFree {
                        Text("FREE")
                            .font(SCFont.displayMedium)
                            .foregroundStyle(SCColor.free)
                    } else {
                        HStack(spacing: SCSpacing.xxs) {
                            Image(systemName: "diamond.fill")
                                .foregroundStyle(SCColor.ethereum)
                            Text(formattedPrice)
                                .font(SCFont.displayMedium)
                                .foregroundStyle(SCColor.textPrimary)
                            Text("ETH")
                                .font(SCFont.heading3)
                                .foregroundStyle(SCColor.textSecondary)
                        }
                    }

                    Text("\(sample.editionsRemaining) of \(sample.editionCount) editions remaining")
                        .font(SCFont.bodySmall)
                        .foregroundStyle(SCColor.textTertiary)
                }

                Spacer()

                // Purchase button
                Button {
                    isPurchasing = true
                    // Purchase logic handled by parent
                } label: {
                    HStack(spacing: SCSpacing.sm) {
                        if isPurchasing {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        }
                        Text(sample.isFree ? "Collect" : "Purchase")
                            .font(SCFont.bodyMedium)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, SCSpacing.xxl)
                    .padding(.vertical, SCSpacing.md)
                    .background(
                        sample.isAvailable
                            ? SCColor.accent
                            : SCColor.textDisabled
                    )
                    .clipShape(RoundedRectangle(cornerRadius: SCRadius.lg))
                }
                .buttonStyle(.plain)
                .disabled(!sample.isAvailable || isPurchasing)
            }
        }
        .padding(SCSpacing.lg)
    }

    // MARK: - Helpers

    private var shortCreatorAddress: String {
        let addr = sample.creator
        guard addr.count > 10 else { return addr }
        return "\(addr.prefix(6))...\(addr.suffix(4))"
    }

    private var formattedPrice: String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 4
        return formatter.string(from: sample.price as NSDecimalNumber) ?? "0"
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func togglePlayback() {
        isPlaying.toggle()
        if isPlaying {
            appState.isPreviewPlaying = true
            appState.previewSample = sample
        } else {
            appState.isPreviewPlaying = false
        }
    }
}

// MARK: - Flow Layout

/// A horizontal flow layout that wraps items to the next line when they exceed the available width.
struct FlowLayout: Layout {
    let spacing: CGFloat

    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX)
        }

        return (
            size: CGSize(width: maxX, height: currentY + lineHeight),
            positions: positions
        )
    }
}
