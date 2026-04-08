// WaveformView.swift
// SampleChainUI
//
// Canvas-based waveform visualization with playhead, zoom, and loop region selection.

import SwiftUI
import SampleChainCore

// MARK: - Waveform View

/// An interactive waveform visualization view with playhead tracking, zoom, and loop regions.
///
/// Renders the waveform using Canvas for high-performance drawing. Supports:
/// - Playhead position tracking and scrubbing
/// - Pinch-to-zoom horizontal scaling
/// - Loop region selection via drag
/// - Played/unplayed color differentiation
public struct WaveformView: View {
    public let waveformData: WaveformData
    @Binding public var playbackPosition: Double // 0.0 to 1.0
    public let isPlaying: Bool

    @State private var zoomLevel: CGFloat = 1.0
    @State private var scrollOffset: CGFloat = 0
    @State private var loopStart: Double? = nil
    @State private var loopEnd: Double? = nil
    @State private var isDraggingPlayhead: Bool = false
    @State private var isDraggingLoop: Bool = false
    @State private var hoveredPosition: Double? = nil

    public init(
        waveformData: WaveformData,
        playbackPosition: Binding<Double>,
        isPlaying: Bool = false
    ) {
        self.waveformData = waveformData
        self._playbackPosition = playbackPosition
        self.isPlaying = isPlaying
    }

    public var body: some View {
        GeometryReader { geometry in
            let size = geometry.size

            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: SCRadius.md)
                    .fill(SCColor.backgroundSecondary)

                // Waveform canvas
                Canvas { context, canvasSize in
                    drawWaveform(
                        context: &context,
                        size: canvasSize,
                        peaks: waveformData.peaks,
                        playheadPosition: playbackPosition
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: SCRadius.md))

                // Loop region overlay
                if let start = loopStart, let end = loopEnd {
                    loopRegionOverlay(size: size, start: start, end: end)
                }

                // Playhead
                playheadLine(size: size)

                // Hover position indicator
                if let hoverPos = hoveredPosition, !isDraggingPlayhead {
                    hoverLine(size: size, position: hoverPos)
                }

                // Time label at hover position
                if let hoverPos = hoveredPosition {
                    timeLabel(size: size, position: hoverPos)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let position = Double(value.location.x / size.width)
                        let clampedPosition = max(0, min(1, position))
                        isDraggingPlayhead = true
                        playbackPosition = clampedPosition
                    }
                    .onEnded { _ in
                        isDraggingPlayhead = false
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoveredPosition = Double(location.x / size.width)
                case .ended:
                    hoveredPosition = nil
                }
            }
            .gesture(
                MagnificationGesture()
                    .onChanged { scale in
                        zoomLevel = max(1.0, min(10.0, zoomLevel * scale))
                    }
            )
        }
    }

    // MARK: - Drawing

    /// Draw the waveform using Canvas context.
    private func drawWaveform(
        context: inout GraphicsContext,
        size: CGSize,
        peaks: [Float],
        playheadPosition: Double
    ) {
        guard !peaks.isEmpty else { return }

        let midY = size.height / 2
        let peakCount = peaks.count
        let stepWidth = size.width / CGFloat(peakCount)

        // Determine the playhead index
        let playheadIndex = Int(playheadPosition * Double(peakCount))

        // Draw played waveform (left of playhead)
        var playedPath = Path()
        playedPath.move(to: CGPoint(x: 0, y: midY))

        // Upper half
        for i in 0..<min(playheadIndex + 1, peakCount) {
            let x = CGFloat(i) * stepWidth + stepWidth / 2
            let amplitude = CGFloat(peaks[i]) * (size.height / 2 - 2)
            playedPath.addLine(to: CGPoint(x: x, y: midY - amplitude))
        }

        let playheadX = CGFloat(playheadPosition) * size.width
        playedPath.addLine(to: CGPoint(x: playheadX, y: midY))

        // Lower half (mirror)
        for i in stride(from: min(playheadIndex, peakCount - 1), through: 0, by: -1) {
            let x = CGFloat(i) * stepWidth + stepWidth / 2
            let amplitude = CGFloat(peaks[i]) * (size.height / 2 - 2)
            playedPath.addLine(to: CGPoint(x: x, y: midY + amplitude))
        }

        playedPath.closeSubpath()
        context.fill(playedPath, with: .color(SCColor.waveformPlayed))

        // Draw unplayed waveform (right of playhead)
        if playheadIndex < peakCount {
            var unplayedPath = Path()
            unplayedPath.move(to: CGPoint(x: playheadX, y: midY))

            // Upper half
            for i in max(0, playheadIndex)..<peakCount {
                let x = CGFloat(i) * stepWidth + stepWidth / 2
                let amplitude = CGFloat(peaks[i]) * (size.height / 2 - 2)
                unplayedPath.addLine(to: CGPoint(x: x, y: midY - amplitude))
            }

            unplayedPath.addLine(to: CGPoint(x: size.width, y: midY))

            // Lower half (mirror)
            for i in stride(from: peakCount - 1, through: max(0, playheadIndex), by: -1) {
                let x = CGFloat(i) * stepWidth + stepWidth / 2
                let amplitude = CGFloat(peaks[i]) * (size.height / 2 - 2)
                unplayedPath.addLine(to: CGPoint(x: x, y: midY + amplitude))
            }

            unplayedPath.closeSubpath()
            context.fill(unplayedPath, with: .color(SCColor.waveformUnplayed))
        }

        // Center line
        var centerLine = Path()
        centerLine.move(to: CGPoint(x: 0, y: midY))
        centerLine.addLine(to: CGPoint(x: size.width, y: midY))
        context.stroke(centerLine, with: .color(SCColor.border.opacity(0.3)), lineWidth: 0.5)
    }

    // MARK: - Overlays

    /// The playhead vertical line indicator.
    private func playheadLine(size: CGSize) -> some View {
        let x = CGFloat(playbackPosition) * size.width
        return Rectangle()
            .fill(SCColor.playhead)
            .frame(width: isDraggingPlayhead ? 2 : 1)
            .frame(height: size.height)
            .offset(x: x - size.width / 2)
            .shadow(color: SCColor.playhead.opacity(0.5), radius: isDraggingPlayhead ? 4 : 2)
            .animation(.easeOut(duration: 0.05), value: playbackPosition)
    }

    /// Hover position indicator line.
    private func hoverLine(size: CGSize, position: Double) -> some View {
        let x = CGFloat(position) * size.width
        return Rectangle()
            .fill(SCColor.textTertiary.opacity(0.3))
            .frame(width: 1)
            .frame(height: size.height)
            .offset(x: x - size.width / 2)
            .allowsHitTesting(false)
    }

    /// Loop region highlight overlay.
    private func loopRegionOverlay(size: CGSize, start: Double, end: Double) -> some View {
        let startX = CGFloat(start) * size.width
        let endX = CGFloat(end) * size.width
        let width = endX - startX

        return Rectangle()
            .fill(SCColor.accent.opacity(0.1))
            .frame(width: max(0, width), height: size.height)
            .overlay(
                Rectangle()
                    .strokeBorder(SCColor.accent.opacity(0.5), lineWidth: 1)
            )
            .offset(x: startX - size.width / 2 + width / 2)
            .allowsHitTesting(false)
    }

    /// Time label at the hover/drag position.
    private func timeLabel(size: CGSize, position: Double) -> some View {
        let timeSeconds = position * waveformData.durationSeconds
        let minutes = Int(timeSeconds) / 60
        let seconds = Int(timeSeconds) % 60
        let millis = Int((timeSeconds.truncatingRemainder(dividingBy: 1)) * 100)
        let timeString = String(format: "%d:%02d.%02d", minutes, seconds, millis)

        let x = CGFloat(position) * size.width

        return Text(timeString)
            .font(SCFont.monoSmall)
            .foregroundStyle(SCColor.textPrimary)
            .padding(.horizontal, SCSpacing.xxs)
            .padding(.vertical, 1)
            .background(SCColor.backgroundTertiary.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: SCRadius.sm))
            .offset(x: x - size.width / 2)
            .offset(y: -(size.height / 2 + 12))
            .allowsHitTesting(false)
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension WaveformData {
    /// Generate sample waveform data for previews.
    static func preview(pointCount: Int = 200) -> WaveformData {
        let peaks = (0..<pointCount).map { i -> Float in
            let t = Float(i) / Float(pointCount)
            let envelope = sin(Float.pi * t) // Fade in/out envelope
            let wave = sin(t * 20) * 0.3 + sin(t * 7) * 0.5 + Float.random(in: 0...0.2)
            return abs(wave * envelope)
        }
        return WaveformData(peaks: peaks, durationSeconds: 4.0, sampleRate: 44100)
    }
}
#endif
