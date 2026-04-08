// PlayButton.swift
// SampleChainUI
//
// Animated play/pause button with multiple size variants.

import SwiftUI

// MARK: - Play Button Size

/// Size variants for the play/pause button.
public enum PlayButtonSize {
    case small
    case medium
    case large

    var diameter: CGFloat {
        switch self {
        case .small: return 28
        case .medium: return 40
        case .large: return 56
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .small: return 10
        case .medium: return 14
        case .large: return 20
        }
    }
}

// MARK: - Play Button

/// An animated circular play/pause button.
///
/// Transitions smoothly between play and pause states with a scale animation.
/// Supports three size variants: small, medium, and large.
///
/// Usage:
/// ```swift
/// PlayButton(isPlaying: $isPlaying, size: .medium) {
///     audioEngine.togglePlayback()
/// }
/// ```
public struct PlayButton: View {
    @Binding public var isPlaying: Bool
    public let size: PlayButtonSize
    public let action: () -> Void

    @State private var isPressed: Bool = false
    @State private var isHovered: Bool = false

    public init(
        isPlaying: Binding<Bool>,
        size: PlayButtonSize = .medium,
        action: @escaping () -> Void
    ) {
        self._isPlaying = isPlaying
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isPlaying.toggle()
            }
            action()
        } label: {
            ZStack {
                // Background circle
                Circle()
                    .fill(backgroundFill)
                    .frame(width: size.diameter, height: size.diameter)
                    .scaleEffect(isPressed ? 0.9 : (isHovered ? 1.05 : 1.0))
                    .shadow(
                        color: SCColor.accent.opacity(isHovered ? 0.3 : 0.1),
                        radius: isHovered ? 8 : 4,
                        x: 0,
                        y: 2
                    )

                // Play/Pause icon
                Group {
                    if isPlaying {
                        pauseIcon
                    } else {
                        playIcon
                    }
                }
                .transition(.scale.combined(with: .opacity))
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPlaying)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    isPressed = true
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Icon Shapes

    /// Play triangle icon (pointing right).
    private var playIcon: some View {
        // Offset slightly right to visually center the triangle
        Image(systemName: "play.fill")
            .font(.system(size: size.iconSize, weight: .semibold))
            .foregroundStyle(.white)
            .offset(x: size.iconSize * 0.05)
    }

    /// Pause icon (two vertical bars).
    private var pauseIcon: some View {
        Image(systemName: "pause.fill")
            .font(.system(size: size.iconSize, weight: .semibold))
            .foregroundStyle(.white)
    }

    // MARK: - Background

    private var backgroundFill: some ShapeStyle {
        if isPlaying {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [SCColor.accent, SCColor.accent.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        } else {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [SCColor.accent, SCColor.accentHover],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }
}

// MARK: - Animated Equalizer (for playing state indicator)

/// A small animated equalizer icon that indicates audio is playing.
/// Can be used alongside sample titles or in list rows.
public struct AnimatedEqualizer: View {
    public let isAnimating: Bool
    public let barCount: Int
    public let color: Color

    @State private var barHeights: [CGFloat]

    public init(isAnimating: Bool = true, barCount: Int = 3, color: Color = SCColor.accent) {
        self.isAnimating = isAnimating
        self.barCount = barCount
        self.color = color
        self._barHeights = State(initialValue: (0..<barCount).map { _ in CGFloat.random(in: 0.3...1.0) })
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 3, height: isAnimating ? barHeights[index] * 16 : 4)
                    .animation(
                        isAnimating
                            ? .easeInOut(duration: Double.random(in: 0.3...0.6))
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.1)
                            : .easeOut(duration: 0.2),
                        value: isAnimating
                    )
            }
        }
        .frame(width: CGFloat(barCount) * 5, height: 16)
        .onAppear {
            if isAnimating {
                animateBars()
            }
        }
        .onChange(of: isAnimating) { _, newValue in
            if newValue {
                animateBars()
            }
        }
    }

    private func animateBars() {
        withAnimation {
            barHeights = (0..<barCount).map { _ in CGFloat.random(in: 0.3...1.0) }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct PlayButton_Previews: View {
    @State private var isPlaying = false

    var body: some View {
        VStack(spacing: 20) {
            PlayButton(isPlaying: $isPlaying, size: .small) {}
            PlayButton(isPlaying: $isPlaying, size: .medium) {}
            PlayButton(isPlaying: $isPlaying, size: .large) {}

            AnimatedEqualizer(isAnimating: isPlaying)
        }
        .padding()
        .background(SCColor.backgroundPrimary)
    }
}
#endif
