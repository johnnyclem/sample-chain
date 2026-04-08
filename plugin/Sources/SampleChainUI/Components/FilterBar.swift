// FilterBar.swift
// SampleChainUI
//
// Reusable filter controls for browsing and searching samples.

import SwiftUI
import SampleChainCore

// MARK: - Filter Bar

/// A horizontal bar of filter controls for genre, instrument type, BPM range,
/// key, license tier, and free/paid status.
public struct FilterBar: View {
    @Binding public var filter: SampleFilter

    @State private var showGenrePopover: Bool = false
    @State private var showTypePopover: Bool = false
    @State private var showBPMPopover: Bool = false
    @State private var showKeyPopover: Bool = false
    @State private var showLicensePopover: Bool = false
    @State private var bpmMinText: String = ""
    @State private var bpmMaxText: String = ""

    public init(filter: Binding<SampleFilter>) {
        self._filter = filter
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SCSpacing.sm) {
                // Genre filter
                filterChip(
                    label: "Genre",
                    isActive: !filter.genres.isEmpty,
                    count: filter.genres.count
                ) {
                    showGenrePopover.toggle()
                }
                .popover(isPresented: $showGenrePopover) {
                    genrePopover
                }

                // Type filter
                filterChip(
                    label: "Type",
                    isActive: !filter.sampleTypes.isEmpty,
                    count: filter.sampleTypes.count
                ) {
                    showTypePopover.toggle()
                }
                .popover(isPresented: $showTypePopover) {
                    typePopover
                }

                // BPM filter
                filterChip(
                    label: bpmFilterLabel,
                    isActive: filter.bpmRange != nil
                ) {
                    showBPMPopover.toggle()
                }
                .popover(isPresented: $showBPMPopover) {
                    bpmPopover
                }

                // Key filter
                filterChip(
                    label: filter.musicalKey.map { "Key: \($0.description)" } ?? "Key",
                    isActive: filter.musicalKey != nil
                ) {
                    showKeyPopover.toggle()
                }
                .popover(isPresented: $showKeyPopover) {
                    keyPopover
                }

                // License filter
                filterChip(
                    label: "License",
                    isActive: !filter.licenseTiers.isEmpty,
                    count: filter.licenseTiers.count
                ) {
                    showLicensePopover.toggle()
                }
                .popover(isPresented: $showLicensePopover) {
                    licensePopover
                }

                // Free only toggle
                filterChip(
                    label: "Free",
                    isActive: filter.freeOnly
                ) {
                    filter.freeOnly.toggle()
                }

                Spacer()

                // Clear all filters
                if !filter.isEmpty {
                    Button {
                        filter = SampleFilter()
                    } label: {
                        HStack(spacing: SCSpacing.xxxs) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                            Text("Clear")
                                .font(SCFont.labelSmall)
                        }
                        .foregroundStyle(SCColor.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Filter Chip

    private func filterChip(
        label: String,
        isActive: Bool,
        count: Int? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: SCSpacing.xxxs) {
                Text(label)
                    .font(SCFont.labelSmall)

                if let count, count > 0 {
                    Text("\(count)")
                        .font(SCFont.labelSmall)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(SCColor.accent)
                        .clipShape(Circle())
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(isActive ? SCColor.accent : SCColor.textSecondary)
            .padding(.horizontal, SCSpacing.md)
            .padding(.vertical, SCSpacing.xs)
            .background(isActive ? SCColor.accentMuted : SCColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: SCRadius.pill))
            .overlay(
                RoundedRectangle(cornerRadius: SCRadius.pill)
                    .strokeBorder(
                        isActive ? SCColor.accent.opacity(0.3) : SCColor.border,
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Popovers

    private var genrePopover: some View {
        VStack(alignment: .leading, spacing: SCSpacing.xs) {
            Text("Genres")
                .font(SCFont.heading3)
                .foregroundStyle(SCColor.textPrimary)
                .padding(.bottom, SCSpacing.xs)

            ForEach(Genre.allCases, id: \.self) { genre in
                Button {
                    if filter.genres.contains(genre) {
                        filter.genres.remove(genre)
                    } else {
                        filter.genres.insert(genre)
                    }
                } label: {
                    HStack {
                        Image(systemName: filter.genres.contains(genre) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(
                                filter.genres.contains(genre) ? SCColor.accent : SCColor.textTertiary
                            )
                        Text(genre.displayName)
                            .font(SCFont.body)
                            .foregroundStyle(SCColor.textPrimary)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(SCSpacing.md)
        .frame(width: 200)
    }

    private var typePopover: some View {
        VStack(alignment: .leading, spacing: SCSpacing.xs) {
            Text("Sample Type")
                .font(SCFont.heading3)
                .foregroundStyle(SCColor.textPrimary)
                .padding(.bottom, SCSpacing.xs)

            ForEach(SampleType.allCases, id: \.self) { type in
                Button {
                    if filter.sampleTypes.contains(type) {
                        filter.sampleTypes.remove(type)
                    } else {
                        filter.sampleTypes.insert(type)
                    }
                } label: {
                    HStack {
                        Image(systemName: filter.sampleTypes.contains(type)
                              ? "checkmark.square.fill" : "square")
                            .foregroundStyle(
                                filter.sampleTypes.contains(type) ? SCColor.accent : SCColor.textTertiary
                            )
                        Text(type.displayName)
                            .font(SCFont.body)
                            .foregroundStyle(SCColor.textPrimary)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(SCSpacing.md)
        .frame(width: 200)
    }

    private var bpmPopover: some View {
        VStack(alignment: .leading, spacing: SCSpacing.md) {
            Text("BPM Range")
                .font(SCFont.heading3)
                .foregroundStyle(SCColor.textPrimary)

            HStack(spacing: SCSpacing.sm) {
                TextField("Min", text: $bpmMinText)
                    .textFieldStyle(.plain)
                    .font(SCFont.mono)
                    .frame(width: 60)
                    .padding(SCSpacing.xs)
                    .background(SCColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: SCRadius.sm))

                Text("--")
                    .foregroundStyle(SCColor.textTertiary)

                TextField("Max", text: $bpmMaxText)
                    .textFieldStyle(.plain)
                    .font(SCFont.mono)
                    .frame(width: 60)
                    .padding(SCSpacing.xs)
                    .background(SCColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: SCRadius.sm))
            }

            // Preset ranges
            HStack(spacing: SCSpacing.xxs) {
                bpmPreset(label: "60-90", min: 60, max: 90)
                bpmPreset(label: "90-120", min: 90, max: 120)
                bpmPreset(label: "120-140", min: 120, max: 140)
                bpmPreset(label: "140-180", min: 140, max: 180)
            }

            HStack {
                Button("Apply") {
                    if let min = Double(bpmMinText), let max = Double(bpmMaxText), min < max {
                        filter.bpmRange = min...max
                    }
                    showBPMPopover = false
                }
                .font(SCFont.bodyMedium)
                .foregroundStyle(SCColor.accent)
                .buttonStyle(.plain)

                Spacer()

                if filter.bpmRange != nil {
                    Button("Clear") {
                        filter.bpmRange = nil
                        bpmMinText = ""
                        bpmMaxText = ""
                        showBPMPopover = false
                    }
                    .font(SCFont.bodySmall)
                    .foregroundStyle(SCColor.textTertiary)
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(SCSpacing.md)
        .frame(width: 240)
    }

    private func bpmPreset(label: String, min: Double, max: Double) -> some View {
        Button {
            bpmMinText = "\(Int(min))"
            bpmMaxText = "\(Int(max))"
            filter.bpmRange = min...max
        } label: {
            Text(label)
                .font(SCFont.labelSmall)
                .foregroundStyle(SCColor.textSecondary)
                .padding(.horizontal, SCSpacing.xs)
                .padding(.vertical, SCSpacing.xxxs)
                .background(SCColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: SCRadius.sm))
        }
        .buttonStyle(.plain)
    }

    private var keyPopover: some View {
        VStack(alignment: .leading, spacing: SCSpacing.md) {
            Text("Musical Key")
                .font(SCFont.heading3)
                .foregroundStyle(SCColor.textPrimary)

            // Grid of keys
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                ForEach(PitchClass.allCases, id: \.self) { pitch in
                    VStack(spacing: 2) {
                        // Major
                        keyButton(pitch: pitch, quality: .major)
                        // Minor
                        keyButton(pitch: pitch, quality: .minor)
                    }
                }
            }

            if filter.musicalKey != nil {
                Button("Clear") {
                    filter.musicalKey = nil
                    showKeyPopover = false
                }
                .font(SCFont.bodySmall)
                .foregroundStyle(SCColor.textTertiary)
                .buttonStyle(.plain)
            }
        }
        .padding(SCSpacing.md)
        .frame(width: 300)
    }

    private func keyButton(pitch: PitchClass, quality: ScaleQuality) -> some View {
        let key = MusicalKey(root: pitch, quality: quality)
        let isSelected = filter.musicalKey == key

        return Button {
            filter.musicalKey = isSelected ? nil : key
        } label: {
            Text("\(pitch.rawValue)\(quality == .minor ? "m" : "")")
                .font(SCFont.labelSmall)
                .foregroundStyle(isSelected ? .white : SCColor.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
                .background(isSelected ? SCColor.accent : SCColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: SCRadius.sm))
        }
        .buttonStyle(.plain)
    }

    private var licensePopover: some View {
        VStack(alignment: .leading, spacing: SCSpacing.xs) {
            Text("License Tier")
                .font(SCFont.heading3)
                .foregroundStyle(SCColor.textPrimary)
                .padding(.bottom, SCSpacing.xs)

            ForEach(LicenseTier.allCases, id: \.self) { tier in
                Button {
                    if filter.licenseTiers.contains(tier) {
                        filter.licenseTiers.remove(tier)
                    } else {
                        filter.licenseTiers.insert(tier)
                    }
                } label: {
                    HStack {
                        Image(systemName: filter.licenseTiers.contains(tier)
                              ? "checkmark.square.fill" : "square")
                            .foregroundStyle(
                                filter.licenseTiers.contains(tier) ? SCColor.accent : SCColor.textTertiary
                            )
                        Text(tier.displayName)
                            .font(SCFont.body)
                            .foregroundStyle(SCColor.textPrimary)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(SCSpacing.md)
        .frame(width: 200)
    }

    // MARK: - Helpers

    private var bpmFilterLabel: String {
        if let range = filter.bpmRange {
            return "\(Int(range.lowerBound))-\(Int(range.upperBound)) BPM"
        }
        return "BPM"
    }
}
