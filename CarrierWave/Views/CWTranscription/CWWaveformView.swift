import SwiftUI

// MARK: - CWWaveformView

/// Displays a real-time waveform visualization of the CW audio signal.
/// Shows scrolling bars that are green when signal is detected.
struct CWWaveformView: View {
    // MARK: Internal

    /// Envelope samples to display (0.0-1.0 range)
    let samples: [Float]

    /// Whether the key is currently down (signal detected)
    let isKeyDown: Bool

    /// Height of the waveform view
    var height: CGFloat = 60

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(0 ..< barCount, id: \.self) { index in
                    barView(for: index, totalWidth: geometry.size.width)
                }
            }
        }
        .frame(height: height)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Private

    /// Number of bars to display
    private let barCount = 32

    @ViewBuilder
    private func barView(for index: Int, totalWidth: CGFloat) -> some View {
        let sampleIndex = sampleIndexFor(barIndex: index)
        let amplitude = sampleIndex < samples.count ? CGFloat(samples[sampleIndex]) : 0

        // Minimum bar height for visual feedback
        let minHeight: CGFloat = 4
        let maxHeight = height - 8
        let barHeight = max(minHeight, amplitude * maxHeight)

        let barWidth = (totalWidth - CGFloat(barCount - 1) * 2) / CGFloat(barCount)

        RoundedRectangle(cornerRadius: 2)
            .fill(barColor(for: amplitude))
            .frame(width: max(2, barWidth), height: barHeight)
            .frame(height: height, alignment: .center)
    }

    private func sampleIndexFor(barIndex: Int) -> Int {
        guard !samples.isEmpty else {
            return 0
        }
        let step = max(1, samples.count / barCount)
        return min(barIndex * step, samples.count - 1)
    }

    private func barColor(for amplitude: CGFloat) -> Color {
        if amplitude > 0.1 || isKeyDown {
            // Signal detected - green gradient based on amplitude
            Color.green.opacity(0.6 + Double(amplitude) * 0.4)
        } else {
            // No signal - gray
            Color(.systemGray4)
        }
    }
}

// MARK: - CWLevelMeter

/// A segmented audio level meter showing input volume.
/// Displays colored segments from red (low) through yellow to green (good) to blue (high).
struct CWLevelMeter: View {
    // MARK: Internal

    /// Current audio level (0.0 to 1.0)
    let level: Double

    /// Whether a CW signal is currently detected
    let isActive: Bool

    var body: some View {
        VStack(spacing: 4) {
            // Segmented bar
            HStack(spacing: 2) {
                ForEach(0 ..< segmentCount, id: \.self) { index in
                    segmentView(at: index)
                }
            }
            .frame(height: 20)

            // Labels
            HStack {
                Text("0")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Low")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Good")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Max")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: Private

    /// Number of segments in the meter
    private let segmentCount = 12

    @ViewBuilder
    private func segmentView(at index: Int) -> some View {
        let threshold = Double(index + 1) / Double(segmentCount)
        let isLit = level >= threshold - (1.0 / Double(segmentCount))

        RoundedRectangle(cornerRadius: 2)
            .fill(segmentColor(at: index, isLit: isLit))
            .animation(.easeOut(duration: 0.05), value: isLit)
    }

    private func segmentColor(at index: Int, isLit: Bool) -> Color {
        let baseColor = colorForSegment(at: index)

        if isLit {
            return baseColor
        } else {
            return baseColor.opacity(0.25)
        }
    }

    private func colorForSegment(at index: Int) -> Color {
        let fraction = Double(index) / Double(segmentCount - 1)

        switch fraction {
        case 0 ..< 0.2:
            return Color(red: 0.6, green: 0.2, blue: 0.2)
        case 0.2 ..< 0.35:
            return Color(red: 0.6, green: 0.3, blue: 0.15)
        case 0.35 ..< 0.5:
            return Color(red: 0.55, green: 0.5, blue: 0.15)
        case 0.5 ..< 0.65:
            return Color(red: 0.4, green: 0.7, blue: 0.3)
        case 0.65 ..< 0.8:
            return Color(red: 0.3, green: 0.6, blue: 0.35)
        default:
            return Color(red: 0.2, green: 0.45, blue: 0.45)
        }
    }
}

// MARK: - CWNoiseFloorIndicator

/// Displays the current noise floor level as a segmented meter.
/// Green (low noise) on the left transitioning to red (high noise) on the right.
struct CWNoiseFloorIndicator: View {
    // MARK: Internal

    /// Current noise floor level (0.0 to 1.0)
    let noiseFloor: Float

    /// Quality assessment of the noise floor
    let quality: NoiseFloorQuality

    /// Whether currently listening
    let isListening: Bool

    var body: some View {
        VStack(spacing: 4) {
            // Segmented bar
            HStack(spacing: 2) {
                ForEach(0 ..< segmentCount, id: \.self) { index in
                    segmentView(at: index)
                }
            }
            .frame(height: 20)

            // Labels
            HStack {
                Text("Quiet")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Fair")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Noisy")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .opacity(isListening ? 1.0 : 0.5)
    }

    // MARK: Private

    /// Number of segments in the meter
    private let segmentCount = 12

    @ViewBuilder
    private func segmentView(at index: Int) -> some View {
        let threshold = Double(index + 1) / Double(segmentCount)
        let isLit = Double(noiseFloor) >= threshold - (1.0 / Double(segmentCount))

        RoundedRectangle(cornerRadius: 2)
            .fill(segmentColor(at: index, isLit: isLit))
            .animation(.easeOut(duration: 0.05), value: isLit)
    }

    private func segmentColor(at index: Int, isLit: Bool) -> Color {
        let baseColor = colorForSegment(at: index)

        if isLit {
            return baseColor
        } else {
            return baseColor.opacity(0.25)
        }
    }

    private func colorForSegment(at index: Int) -> Color {
        let fraction = Double(index) / Double(segmentCount - 1)

        // Inverted from level meter: green (good/quiet) on left, red (bad/noisy) on right
        switch fraction {
        case 0 ..< 0.2:
            // Excellent - deep green
            return Color(red: 0.2, green: 0.6, blue: 0.3)
        case 0.2 ..< 0.35:
            // Good - green
            return Color(red: 0.3, green: 0.6, blue: 0.35)
        case 0.35 ..< 0.5:
            // Fair - yellow-green
            return Color(red: 0.5, green: 0.6, blue: 0.2)
        case 0.5 ..< 0.65:
            // Getting noisy - yellow
            return Color(red: 0.6, green: 0.55, blue: 0.15)
        case 0.65 ..< 0.8:
            // Poor - orange
            return Color(red: 0.65, green: 0.4, blue: 0.15)
        default:
            // Too noisy - red
            return Color(red: 0.6, green: 0.2, blue: 0.2)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        CWWaveformView(
            samples: (0 ..< 64).map { Float.random(in: 0 ... ($0.isMultiple(of: 2) ? 0.8 : 0.3)) },
            isKeyDown: true
        )
        .padding()

        CWWaveformView(
            samples: (0 ..< 64).map { _ in Float.random(in: 0 ... 0.1) },
            isKeyDown: false
        )
        .padding()

        CWLevelMeter(level: 0.7 as Double, isActive: true)
            .padding()

        CWLevelMeter(level: 0.2 as Double, isActive: false)
            .padding()

        // Noise floor indicators
        VStack(spacing: 12) {
            CWNoiseFloorIndicator(noiseFloor: 0.05, quality: .excellent, isListening: true)
            CWNoiseFloorIndicator(noiseFloor: 0.15, quality: .good, isListening: true)
            CWNoiseFloorIndicator(noiseFloor: 0.25, quality: .fair, isListening: true)
            CWNoiseFloorIndicator(noiseFloor: 0.4, quality: .poor, isListening: true)
            CWNoiseFloorIndicator(noiseFloor: 0.6, quality: .unusable, isListening: true)
        }
        .padding()
    }
    .background(Color(.systemBackground))
}
