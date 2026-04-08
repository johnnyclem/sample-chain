// SampleChainTheme.swift
// SampleChainUI
//
// Dark theme color palette and typography system consistent with professional DAW environments.

import SwiftUI

// MARK: - Color Palette

/// The SampleChain color system. Dark-themed to integrate seamlessly with DAW environments.
public enum SCColor {
    // MARK: Backgrounds
    /// Primary background (deepest layer).
    public static let backgroundPrimary = Color(red: 0.08, green: 0.08, blue: 0.10)
    /// Secondary background (panels, cards).
    public static let backgroundSecondary = Color(red: 0.12, green: 0.12, blue: 0.14)
    /// Tertiary background (elevated surfaces, modals).
    public static let backgroundTertiary = Color(red: 0.16, green: 0.16, blue: 0.19)
    /// Surface color for interactive elements (buttons, inputs).
    public static let surface = Color(red: 0.20, green: 0.20, blue: 0.23)
    /// Hover state for surfaces.
    public static let surfaceHover = Color(red: 0.24, green: 0.24, blue: 0.27)
    /// Selected/active surface.
    public static let surfaceActive = Color(red: 0.28, green: 0.28, blue: 0.31)

    // MARK: Text
    /// Primary text (high emphasis).
    public static let textPrimary = Color(red: 0.93, green: 0.93, blue: 0.95)
    /// Secondary text (medium emphasis).
    public static let textSecondary = Color(red: 0.65, green: 0.65, blue: 0.70)
    /// Tertiary text (low emphasis, hints).
    public static let textTertiary = Color(red: 0.45, green: 0.45, blue: 0.50)
    /// Disabled text.
    public static let textDisabled = Color(red: 0.30, green: 0.30, blue: 0.35)

    // MARK: Accent
    /// Primary accent color (brand blue).
    public static let accent = Color(red: 0.30, green: 0.55, blue: 1.0)
    /// Accent hover state.
    public static let accentHover = Color(red: 0.40, green: 0.62, blue: 1.0)
    /// Accent muted (for backgrounds with accent tint).
    public static let accentMuted = Color(red: 0.30, green: 0.55, blue: 1.0).opacity(0.15)

    // MARK: Semantic
    /// Success / positive.
    public static let success = Color(red: 0.20, green: 0.78, blue: 0.45)
    /// Warning.
    public static let warning = Color(red: 0.95, green: 0.70, blue: 0.20)
    /// Error / destructive.
    public static let error = Color(red: 0.92, green: 0.30, blue: 0.30)
    /// Info.
    public static let info = Color(red: 0.35, green: 0.65, blue: 0.95)

    // MARK: Waveform
    /// Waveform fill color (played region).
    public static let waveformPlayed = Color(red: 0.30, green: 0.55, blue: 1.0)
    /// Waveform fill color (unplayed region).
    public static let waveformUnplayed = Color(red: 0.35, green: 0.35, blue: 0.40)
    /// Waveform RMS fill (inner envelope).
    public static let waveformRMS = Color(red: 0.30, green: 0.55, blue: 1.0).opacity(0.5)
    /// Playhead indicator.
    public static let playhead = Color.white

    // MARK: Borders
    /// Subtle border.
    public static let border = Color(red: 0.22, green: 0.22, blue: 0.25)
    /// Focused border.
    public static let borderFocused = Color(red: 0.30, green: 0.55, blue: 1.0)

    // MARK: NFT / Blockchain
    /// Ethereum purple for blockchain-related elements.
    public static let ethereum = Color(red: 0.45, green: 0.35, blue: 0.82)
    /// Free sample badge.
    public static let free = Color(red: 0.20, green: 0.78, blue: 0.45)
    /// Paid sample badge.
    public static let paid = Color(red: 0.95, green: 0.70, blue: 0.20)
}

// MARK: - Typography

/// The SampleChain typography system. Uses SF Pro (system font) with DAW-appropriate sizing.
public enum SCFont {
    // MARK: Display
    /// Large display heading (e.g. page titles).
    public static let displayLarge = Font.system(size: 28, weight: .bold, design: .default)
    /// Medium display heading.
    public static let displayMedium = Font.system(size: 24, weight: .bold, design: .default)

    // MARK: Headings
    /// Section heading.
    public static let heading1 = Font.system(size: 20, weight: .semibold, design: .default)
    /// Subsection heading.
    public static let heading2 = Font.system(size: 17, weight: .semibold, design: .default)
    /// Minor heading.
    public static let heading3 = Font.system(size: 15, weight: .medium, design: .default)

    // MARK: Body
    /// Standard body text.
    public static let body = Font.system(size: 13, weight: .regular, design: .default)
    /// Body text with medium weight.
    public static let bodyMedium = Font.system(size: 13, weight: .medium, design: .default)
    /// Smaller body text.
    public static let bodySmall = Font.system(size: 12, weight: .regular, design: .default)

    // MARK: Labels
    /// Standard label.
    public static let label = Font.system(size: 11, weight: .medium, design: .default)
    /// Small label (badges, tags).
    public static let labelSmall = Font.system(size: 10, weight: .medium, design: .default)

    // MARK: Monospaced (for BPM, key, addresses, etc.)
    /// Monospaced numbers and technical values.
    public static let mono = Font.system(size: 13, weight: .regular, design: .monospaced)
    /// Small monospaced text.
    public static let monoSmall = Font.system(size: 11, weight: .regular, design: .monospaced)
    /// Large monospaced text (BPM display, price).
    public static let monoLarge = Font.system(size: 17, weight: .semibold, design: .monospaced)
}

// MARK: - Spacing

/// Standardized spacing values for consistent layout.
public enum SCSpacing {
    public static let xxxs: CGFloat = 2
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 6
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 20
    public static let xxl: CGFloat = 24
    public static let xxxl: CGFloat = 32
    public static let xxxxl: CGFloat = 48
}

// MARK: - Corner Radius

/// Standardized corner radius values.
public enum SCRadius {
    public static let sm: CGFloat = 4
    public static let md: CGFloat = 6
    public static let lg: CGFloat = 8
    public static let xl: CGFloat = 12
    public static let pill: CGFloat = 999
}

// MARK: - Shadow

/// Standardized shadow definitions.
public enum SCShadow {
    public static let sm = SCShadowStyle(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
    public static let md = SCShadowStyle(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
    public static let lg = SCShadowStyle(color: .black.opacity(0.4), radius: 12, x: 0, y: 6)
}

/// Shadow style parameters.
public struct SCShadowStyle {
    public let color: Color
    public let radius: CGFloat
    public let x: CGFloat
    public let y: CGFloat
}

// MARK: - View Modifiers

/// Applies the SampleChain dark card style to a view.
public struct SCCardModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .background(SCColor.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: SCRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: SCRadius.lg)
                    .strokeBorder(SCColor.border, lineWidth: 0.5)
            )
    }
}

/// Applies the SampleChain badge style to a view.
public struct SCBadgeModifier: ViewModifier {
    let color: Color

    public func body(content: Content) -> some View {
        content
            .font(SCFont.labelSmall)
            .foregroundStyle(color)
            .padding(.horizontal, SCSpacing.xs)
            .padding(.vertical, SCSpacing.xxxs)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: SCRadius.sm))
    }
}

// MARK: - View Extensions

public extension View {
    /// Apply the standard card styling.
    func scCard() -> some View {
        modifier(SCCardModifier())
    }

    /// Apply a colored badge style.
    func scBadge(color: Color = SCColor.accent) -> some View {
        modifier(SCBadgeModifier(color: color))
    }

    /// Apply the SampleChain shadow.
    func scShadow(_ style: SCShadowStyle = SCShadow.md) -> some View {
        shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}
