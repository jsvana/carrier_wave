import SwiftUI

// MARK: - CWWaveformView

/// Displays a real-time waveform visualization of the CW audio signal.
/// Shows scrolling bars that are green when signal is detected.
struct CWWaveformView: View {
    /// Envelope samples to display (0.0-1.0 range)
    let samples: [Float]

    /// Whether the key is currently down (signal detected)
    let isKeyDown: Bool

    /// Height of the waveform view
    var height: CGFloat = 60

    /// Number of bars to display
    private let barCount = 32

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
        guard !samples.isEmpty else { return 0 }
        let step = max(1, samples.count / barCount)
        return min(barIndex * step, samples.count - 1)
    }

    private func barColor(for amplitude: CGFloat) -> Color {
        if amplitude > 0.1 || isKeyDown {
            // Signal detected - green gradient based on amplitude
            return Color.green.opacity(0.6 + Double(amplitude) * 0.4)
        } else {
            // No signal - gray
            return Color(.systemGray4)
        }
    }
}

// MARK: - CWLevelMeter

/// Simple horizontal level meter for signal strength
struct CWLevelMeter: View {
    /// Current level (0.0-1.0)
    let level: Float

    /// Whether signal is detected
    let isActive: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))

                // Level bar
                RoundedRectangle(cornerRadius: 4)
                    .fill(isActive ? Color.green : Color(.systemGray4))
                    .frame(width: geometry.size.width * CGFloat(level))
            }
        }
        .frame(height: 8)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        CWWaveformView(
            samples: (0 ..< 64).map { Float.random(in: 0 ... ($0 % 2 == 0 ? 0.8 : 0.3)) },
            isKeyDown: true
        )
        .padding()

        CWWaveformView(
            samples: (0 ..< 64).map { _ in Float.random(in: 0 ... 0.1) },
            isKeyDown: false
        )
        .padding()

        CWLevelMeter(level: 0.7, isActive: true)
            .padding()

        CWLevelMeter(level: 0.2, isActive: false)
            .padding()
    }
    .background(Color(.systemBackground))
}
