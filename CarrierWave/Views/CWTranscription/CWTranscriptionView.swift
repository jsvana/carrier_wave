import SwiftUI

// MARK: - CWTranscriptionView

/// Main CW transcription view with audio visualization and decoded transcript.
struct CWTranscriptionView: View {
    // MARK: Internal

    /// Whether the view is presented modally (shows Close button)
    var isModal: Bool = false

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
                .padding(.horizontal)
                .padding(.top)

                // Level meter
                CWLevelMeter(
                    level: service.isListening ? Double(service.peakAmplitude) : 0,
                    isActive: service.isKeyDown
                )
                .padding(.horizontal)

                // Noise floor indicator
                noiseFloorSection
                    .padding(.horizontal)
                    .padding(.bottom)

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
                if isModal {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") {
                            service.stopListening()
                            dismiss()
                        }
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

    // MARK: Private

    @StateObject private var service = CWTranscriptionService()
    @Environment(\.dismiss) private var dismiss

    private var statusColor: Color {
        switch service.state {
        case .idle:
            .secondary
        case .listening:
            if service.isCalibrating {
                .orange
            } else if service.isNoiseTooHigh {
                .yellow
            } else {
                .green
            }
        case .error:
            .red
        }
    }

    private var statusText: String {
        switch service.state {
        case .idle:
            "Ready"
        case .listening:
            if service.isCalibrating {
                "Calibrating..."
            } else if service.isNoiseTooHigh {
                "High Noise"
            } else {
                "Listening"
            }
        case let .error(message):
            message
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        VStack(spacing: 12) {
            // Status indicator row
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 10, height: 10)

                    Text(statusText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(statusColor)
                }

                Spacer()
            }

            // Settings controls
            settingsControls
        }
    }

    // MARK: - Settings Controls

    private var settingsControls: some View {
        VStack(spacing: 8) {
            // Backend selector
            HStack {
                Text("Decoder")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)

                Picker("Backend", selection: $service.selectedBackend) {
                    ForEach(CWDecoderBackend.allCases) { backend in
                        Text(backend.rawValue).tag(backend)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!service.canChangeBackend)
            }

            // WPM control
            HStack {
                Text("WPM")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { Double(service.estimatedWPM) },
                        set: { service.setWPM(Int($0)) }
                    ),
                    in: 5 ... 50,
                    step: 1
                )

                Text("\(service.estimatedWPM)")
                    .font(.subheadline.monospaced())
                    .frame(width: 30, alignment: .trailing)
            }

            // Tone frequency control
            HStack {
                Text("Tone")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)

                Slider(
                    value: $service.toneFrequency,
                    in: 400 ... 1_000,
                    step: 10
                )

                Text("\(Int(service.toneFrequency))")
                    .font(.subheadline.monospaced())
                    .frame(width: 40, alignment: .trailing)
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Noise Floor Section

    private var noiseFloorSection: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Noise Floor")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if service.isListening, service.isNoiseTooHigh {
                    Label("Move away from noise source", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            CWNoiseFloorIndicator(
                noiseFloor: service.noiseFloor,
                quality: service.noiseFloorQuality,
                isListening: service.isListening
            )
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

    private var controlBar: some View {
        VStack(spacing: 16) {
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
        // Decoder backend selection
        Section("Decoder Backend") {
            ForEach(CWDecoderBackend.allCases) { backend in
                Button {
                    if service.canChangeBackend {
                        service.selectedBackend = backend
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(backend.rawValue)
                            Text(backend.shortDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if service.selectedBackend == backend {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .disabled(!service.canChangeBackend)
            }
        }

        // WPM presets for quick access
        Section("WPM Presets") {
            ForEach([15, 20, 25, 30], id: \.self) { wpm in
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

        // Tone presets for quick access
        Section("Tone Presets") {
            ForEach([600, 700, 800], id: \.self) { freq in
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
    }
}

// MARK: - Preview

#Preview {
    CWTranscriptionView()
}
