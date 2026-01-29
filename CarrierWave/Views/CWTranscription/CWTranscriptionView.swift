import SwiftUI

// MARK: - CWTranscriptionView

/// Main CW transcription view with audio visualization and decoded transcript.
struct CWTranscriptionView: View {
    @StateObject private var service = CWTranscriptionService()
    @Environment(\.dismiss) private var dismiss

    /// Optional callback when user wants to log a QSO
    var onLog: ((String) -> Void)?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Status bar
                statusBar
                    .padding(.horizontal)
                    .padding(.top, 8)

                // Waveform visualization
                CWWaveformView(
                    samples: service.waveformSamples,
                    isKeyDown: service.isKeyDown
                )
                .padding()

                // Transcript area
                transcriptArea
                    .padding(.horizontal)

                // Detected callsign bar
                if service.detectedCallsign != nil {
                    CWDetectedCallsignBar(
                        callsign: service.detectedCallsign,
                        allCallsigns: service.detectedCallsigns,
                        onUse: { callsign in
                            onLog?(callsign)
                        }
                    )
                    .padding(.horizontal)
                    .padding(.top, 8)
                }

                Spacer()

                // Control buttons
                controlBar
                    .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("CW Transcription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        service.stopListening()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        settingsMenu
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    // MARK: - Status Bar

    @ViewBuilder
    private var statusBar: some View {
        HStack {
            // Listening indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)

                Text(statusText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(statusColor)
            }

            Spacer()

            // WPM display
            HStack(spacing: 4) {
                Text("\(service.estimatedWPM)")
                    .font(.title3.weight(.semibold).monospaced())

                Text("WPM")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.systemGray5))
            .clipShape(Capsule())
        }
    }

    private var statusColor: Color {
        switch service.state {
        case .idle:
            .secondary
        case .listening:
            .green
        case .error:
            .red
        }
    }

    private var statusText: String {
        switch service.state {
        case .idle:
            "Ready"
        case .listening:
            "Listening"
        case let .error(message):
            message
        }
    }

    // MARK: - Transcript Area

    @ViewBuilder
    private var transcriptArea: some View {
        if service.transcript.isEmpty, service.currentLine.isEmpty {
            CWEmptyTranscriptView(isListening: service.isListening)
                .frame(minHeight: 200)
        } else {
            CWTranscriptView(
                entries: service.transcript,
                currentLine: service.currentLine
            )
            .frame(minHeight: 200)
        }
    }

    // MARK: - Control Bar

    @ViewBuilder
    private var controlBar: some View {
        VStack(spacing: 16) {
            // Level meter
            if service.isListening {
                CWLevelMeter(
                    level: service.peakAmplitude,
                    isActive: service.isKeyDown
                )
            }

            // Action buttons
            HStack(spacing: 16) {
                // Copy button
                Button {
                    let text = service.copyTranscript()
                    UIPasteboard.general.string = text
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .disabled(service.transcript.isEmpty && service.currentLine.isEmpty)

                // Clear button
                Button {
                    service.clearTranscript()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(service.transcript.isEmpty && service.currentLine.isEmpty)

                Spacer()

                // Main start/stop button
                Button {
                    if service.isListening {
                        service.stopListening()
                    } else {
                        Task {
                            await service.startListening()
                        }
                    }
                } label: {
                    Label(
                        service.isListening ? "Stop" : "Start",
                        systemImage: service.isListening ? "stop.fill" : "mic.fill"
                    )
                    .font(.headline)
                    .frame(minWidth: 100)
                }
                .buttonStyle(.borderedProminent)
                .tint(service.isListening ? .red : .green)
            }
        }
    }

    // MARK: - Settings Menu

    @ViewBuilder
    private var settingsMenu: some View {
        // Tone frequency picker
        Menu("Tone Frequency") {
            ForEach([500, 550, 600, 650, 700, 750, 800], id: \.self) { freq in
                Button {
                    service.toneFrequency = Double(freq)
                } label: {
                    HStack {
                        Text("\(freq) Hz")
                        if Int(service.toneFrequency) == freq {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        Divider()

        // WPM presets
        Menu("Set WPM") {
            ForEach([10, 15, 20, 25, 30, 35, 40], id: \.self) { wpm in
                Button {
                    service.setWPM(wpm)
                } label: {
                    HStack {
                        Text("\(wpm) WPM")
                        if service.estimatedWPM == wpm {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    CWTranscriptionView()
}
