// SampleCell.swift
// SampleChainUI
//
// Individual sample cell component for grid and list display modes.
// Shows waveform thumbnail, metadata badges, price, and play button.

import SwiftUI
import SampleChainCore

// MARK: - Sample Cell

/// A cell displaying a single sample with its metadata, suitable for grid or list layouts.
public struct SampleCell: View {
    public let sample: Sample
    public let displayMode: BrowseDisplayMode

    @EnvironmentObject private var appState: AppState
    @State private var isHovered: Bool = false
    @State private var isPlaying: Bool = false

    public init(sample: Sample, displayMode: BrowseDisplayMode = .grid) {
        self.sample = sample
        self.displayMode = displayMode
    }

    public var body: some View {
        Group {
            switch displayMode {
            case .grid:
                gridCell
            case .list:
                listCell
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    // MARK: - Grid Cell

    private var gridCell: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Waveform area with play button overlay
            ZStack {
                waveformThumbnail
                    .frame(height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: SCRadius.lg, style: .continuous))

                // Play button overlay (visible on hover)
                if isHovered {
                    PlayButton(isPlaying: $isPlaying, size: .medium) {
                        togglePlayback()
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }

            // Metadata
            VStack(alignment: .leading, spacing: SCSpacing.xs) {
                // Title
                Text(sample.title)
                    .font(SCFont.bodyMedium)
                    .foregroundStyle(SCColor.textPrimary)
                    .lineLimit(1)

                // Creator
                Text(shortCreatorAddress)
                    .font(SCFont.monoSmall)
                    .foregroundStyle(SCColor.textTertiary)
                    .lineLimit(1)

                // Badges row
                HStack(spacing: SCSpacing.xxs) {
                    // BPM badge
                    if let bpm = sample.bpm {
                        Text("\(Int(bpm)) BPM")
                            .scBadge(color: SCColor.accent)
                    }

                    // Key badge
                    if let key = sample.musicalKey {
                        Text(key.description)
                            .scBadge(color: SCColor.info)
                    }

                    // Type badge
                    Text(sample.sampleType.displayName)
                        .scBadge(color: SCColor.textSecondary)

                    Spacer()
                }

                // Price row
                HStack {
                    priceLabel
                    Spacer()
                    editionLabel
                }
            }
            .padding(SCSpacing.md)
        }
        .background(isHovered ? SCColor.surfaceHover : SCColor.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: SCRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: SCRadius.lg)
                .strokeBorder(SCColor.border, lineWidth: 0.5)
        )
    }

    // MARK: - List Cell

    private var listCell: some View {
        HStack(spacing: SCSpacing.md) {
            // Play button
            PlayButton(isPlaying: $isPlaying, size: .small) {
                togglePlayback()
            }

            // Waveform thumbnail
            waveformThumbnail
                .frame(width: 80, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: SCRadius.sm))

            // Title and creator
            VStack(alignment: .leading, spacing: 2) {
                Text(sample.title)
                    .font(SCFont.bodyMedium)
                    .foregroundStyle(SCColor.textPrimary)
                    .lineLimit(1)
                Text(shortCreatorAddress)
                    .font(SCFont.monoSmall)
                    .foregroundStyle(SCColor.textTertiary)
                    .lineLimit(1)
            }
            .frame(minWidth: 120)

            Spacer()

            // BPM
            if let bpm = sample.bpm {
                Text("\(Int(bpm))")
                    .font(SCFont.mono)
                    .foregroundStyle(SCColor.textSecondary)
                    .frame(width: 45, alignment: .trailing)
            } else {
                Text("--")
                    .font(SCFont.mono)
                    .foregroundStyle(SCColor.textTertiary)
                    .frame(width: 45, alignment: .trailing)
            }

            // Key
            if let key = sample.musicalKey {
                Text(key.description)
                    .font(SCFont.mono)
                    .foregroundStyle(SCColor.textSecondary)
                    .frame(width: 55, alignment: .center)
            } else {
                Text("--")
                    .font(SCFont.mono)
                    .foregroundStyle(SCColor.textTertiary)
                    .frame(width: 55, alignment: .center)
            }

            // Type
            Text(sample.sampleType.displayName)
                .font(SCFont.labelSmall)
                .foregroundStyle(SCColor.textSecondary)
                .frame(width: 60, alignment: .center)

            // Duration
            Text(formattedDuration)
                .font(SCFont.mono)
                .foregroundStyle(SCColor.textSecondary)
                .frame(width: 45, alignment: .trailing)

            // Price
            priceLabel
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, SCSpacing.md)
        .padding(.vertical, SCSpacing.sm)
        .background(isHovered ? SCColor.surfaceHover : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: SCRadius.sm))
    }

    // MARK: - Shared Components

    /// Waveform thumbnail using the sample's pre-computed peak data.
    private var waveformThumbnail: some View {
        GeometryReader { geometry in
            if let waveformData = sample.waveformData, !waveformData.peaks.isEmpty {
                WaveformThumbnailShape(peaks: waveformData.peaks)
                    .fill(SCColor.waveformUnplayed.opacity(0.6))
                    .background(SCColor.backgroundPrimary.opacity(0.5))
            } else {
                // Placeholder waveform
                RoundedRectangle(cornerRadius: SCRadius.sm)
                    .fill(SCColor.surface)
                    .overlay {
                        Image(systemName: "waveform")
                            .font(.system(size: 16))
                            .foregroundStyle(SCColor.textTertiary)
                    }
            }
        }
    }

    /// Price label formatted for display.
    @ViewBuilder
    private var priceLabel: some View {
        if sample.isFree {
            Text("FREE")
                .font(SCFont.label)
                .foregroundStyle(SCColor.free)
                .padding(.horizontal, SCSpacing.xs)
                .padding(.vertical, SCSpacing.xxxs)
                .background(SCColor.free.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: SCRadius.sm))
        } else {
            HStack(spacing: 2) {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(SCColor.ethereum)
                Text(formattedPrice)
                    .font(SCFont.monoSmall)
                    .foregroundStyle(SCColor.paid)
            }
        }
    }

    /// Edition count label.
    private var editionLabel: some View {
        Text("\(sample.editionsRemaining)/\(sample.editionCount)")
            .font(SCFont.labelSmall)
            .foregroundStyle(SCColor.textTertiary)
    }

    // MARK: - Helpers

    private var shortCreatorAddress: String {
        let addr = sample.creator
        guard addr.count > 10 else { return addr }
        return "\(addr.prefix(6))...\(addr.suffix(4))"
    }

    private var formattedDuration: String {
        let minutes = Int(sample.durationSeconds) / 60
        let seconds = Int(sample.durationSeconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var formattedPrice: String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 4
        return formatter.string(from: sample.price as NSDecimalNumber) ?? "0"
    }

    private func togglePlayback() {
        if isPlaying {
            isPlaying = false
            appState.isPreviewPlaying = false
            appState.previewSample = nil
        } else {
            isPlaying = true
            appState.isPreviewPlaying = true
            appState.previewSample = sample
        }
    }
}

// MARK: - Waveform Thumbnail Shape

/// A simple filled waveform shape for use in sample cell thumbnails.
private struct WaveformThumbnailShape: Shape {
    let peaks: [Float]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard peaks.count > 1 else { return path }

        let stepWidth = rect.width / CGFloat(peaks.count)
        let midY = rect.midY

        // Upper half
        path.move(to: CGPoint(x: 0, y: midY))
        for (index, peak) in peaks.enumerated() {
            let x = CGFloat(index) * stepWidth + stepWidth / 2
            let amplitude = CGFloat(peak) * rect.height / 2
            path.addLine(to: CGPoint(x: x, y: midY - amplitude))
        }
        path.addLine(to: CGPoint(x: rect.width, y: midY))

        // Lower half (mirror)
        for (index, peak) in peaks.enumerated().reversed() {
            let x = CGFloat(index) * stepWidth + stepWidth / 2
            let amplitude = CGFloat(peak) * rect.height / 2
            path.addLine(to: CGPoint(x: x, y: midY + amplitude))
        }

        path.closeSubpath()
        return path
    }
}
