// swiftlint:disable function_body_length
// Solar Panel View for Logger
//
// Displays current solar conditions including K-index,
// solar flux, and propagation forecast.

import SwiftUI

// MARK: - SolarPanelView

struct SolarPanelView: View {
    // MARK: Internal

    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if isLoading {
                loadingView
            } else if let error = errorMessage {
                errorView(error)
            } else if let conditions {
                conditionsView(conditions)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        .task {
            await loadData()
        }
    }

    // MARK: Private

    @State private var conditions: SolarConditions?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let noaaClient = NOAAClient()

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "sun.max.fill")
                .foregroundStyle(.orange)

            Text("Solar Conditions")
                .font(.headline)

            Spacer()

            Button {
                Task { await loadData() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14))
            }
            .buttonStyle(.borderless)

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding()
    }

    // MARK: - Content Views

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading solar data...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await loadData() }
            }
            .font(.caption)
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private func conditionsView(_ conditions: SolarConditions) -> some View {
        VStack(spacing: 16) {
            // Propagation rating
            propagationBadge(conditions)

            // Metrics grid
            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], spacing: 12
            ) {
                metricCard(
                    title: "K-Index",
                    value: String(format: "%.1f", conditions.kIndex),
                    icon: "gauge",
                    color: kIndexColor(conditions.kIndex)
                )

                if let flux = conditions.solarFlux {
                    metricCard(
                        title: "SFI",
                        value: "\(Int(flux))",
                        icon: "sun.max",
                        color: sfiColor(flux)
                    )
                } else {
                    metricCard(
                        title: "SFI",
                        value: "--",
                        icon: "sun.max",
                        color: .secondary
                    )
                }

                if let spots = conditions.sunspots {
                    metricCard(
                        title: "Sunspots",
                        value: "\(spots)",
                        icon: "circle.dotted",
                        color: .orange
                    )
                } else {
                    metricCard(
                        title: "A-Index",
                        value: conditions.aIndex.map { "\($0)" } ?? "--",
                        icon: "waveform.path",
                        color: .purple
                    )
                }
            }

            // Band conditions summary
            bandConditionsSummary(conditions)

            // Last updated
            Text("Updated: \(conditions.timestamp.formatted(date: .omitted, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }

    private func propagationBadge(_ conditions: SolarConditions) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(propagationColor(conditions.propagationRating))
                .frame(width: 12, height: 12)

            Text(conditions.propagationRating)
                .font(.title3)
                .fontWeight(.semibold)

            Text("Propagation")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(propagationColor(conditions.propagationRating).opacity(0.1))
        .clipShape(Capsule())
    }

    private func metricCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(color)

            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func bandConditionsSummary(_ conditions: SolarConditions) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HF Band Outlook")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                ForEach(["80m", "40m", "20m", "15m", "10m"], id: \.self) { band in
                    bandIndicator(band: band, conditions: conditions)
                }
            }
        }
    }

    private func bandIndicator(band: String, conditions: SolarConditions) -> some View {
        let quality = bandQuality(band: band, kIndex: conditions.kIndex, sfi: conditions.solarFlux)

        return VStack(spacing: 2) {
            Circle()
                .fill(qualityColor(quality))
                .frame(width: 8, height: 8)
            Text(band)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func propagationColor(_ rating: String) -> Color {
        switch rating {
        case "Excellent": .green
        case "Good": .blue
        case "Fair": .yellow
        case "Poor": .orange
        default: .red
        }
    }

    private func kIndexColor(_ kIndex: Double) -> Color {
        switch kIndex {
        case 0 ..< 2: .green
        case 2 ..< 3: .blue
        case 3 ..< 4: .yellow
        case 4 ..< 5: .orange
        default: .red
        }
    }

    private func sfiColor(_ sfi: Double) -> Color {
        switch sfi {
        case 150...: .green
        case 100...: .blue
        case 70...: .yellow
        default: .orange
        }
    }

    private func bandQuality(band: String, kIndex: Double, sfi: Double?) -> Int {
        // Simplified band quality estimation
        // Returns 0 (poor) to 3 (excellent)
        let flux = sfi ?? 100

        let baseQuality: Int =
            switch band {
            case "80m",
                 "40m":
                // Lower bands better at night, less affected by K-index
                kIndex < 4 ? 2 : 1
            case "20m":
                // 20m is usually reliable
                flux > 100 ? 3 : 2
            case "15m":
                // Needs higher SFI
                flux > 120 ? 3 : (flux > 90 ? 2 : 1)
            case "10m":
                // Very sensitive to solar conditions
                flux > 140 ? 3 : (flux > 110 ? 2 : (flux > 80 ? 1 : 0))
            default:
                2
            }

        // Reduce quality if K-index is high
        let kPenalty = kIndex >= 5 ? 2 : (kIndex >= 4 ? 1 : 0)
        return max(0, baseQuality - kPenalty)
    }

    private func qualityColor(_ quality: Int) -> Color {
        switch quality {
        case 3: .green
        case 2: .blue
        case 1: .yellow
        default: .red
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            conditions = try await noaaClient.fetchSolarConditions()
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

#Preview {
    SolarPanelView {}
        .padding()
}
