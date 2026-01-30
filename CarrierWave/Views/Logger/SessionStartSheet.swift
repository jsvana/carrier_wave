import SwiftUI

// MARK: - SessionStartSheet

/// Session setup wizard for starting a new logging session
struct SessionStartSheet: View {
    // MARK: Internal

    var sessionManager: LoggingSessionManager?
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                callsignSection
                modeSection
                frequencySection
                activationSection
                optionsSection
            }
            .navigationTitle("Start Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        startSession()
                    }
                    .disabled(!canStart)
                }
            }
        }
    }

    // MARK: Private

    @AppStorage("loggerDefaultCallsign") private var defaultCallsign = ""
    @AppStorage("loggerDefaultMode") private var defaultMode = "CW"
    @AppStorage("loggerDefaultGrid") private var defaultGrid = ""
    @AppStorage("loggerSkipWizard") private var skipWizard = false

    @State private var myCallsign = ""
    @State private var selectedMode = "CW"
    @State private var frequency = ""
    @State private var activationType: ActivationType = .casual
    @State private var parkReference = ""
    @State private var sotaReference = ""
    @State private var myGrid = ""

    private var canStart: Bool {
        !myCallsign.isEmpty && myCallsign.count >= 3
    }

    private var parsedFrequency: Double? {
        Double(frequency)
    }

    // MARK: - Sections

    private var callsignSection: some View {
        Section {
            TextField("Your Callsign", text: $myCallsign)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.title3.monospaced())

            if !defaultGrid.isEmpty || !myGrid.isEmpty {
                HStack {
                    Text("Grid")
                        .foregroundStyle(.secondary)
                    Spacer()
                    TextField("FN31", text: $myGrid)
                        .textInputAutocapitalization(.characters)
                        .multilineTextAlignment(.trailing)
                        .font(.subheadline.monospaced())
                }
            }
        } header: {
            Text("Station")
        } footer: {
            if myCallsign.isEmpty {
                Text("Enter your callsign to start logging")
            }
        }
        .onAppear {
            if myCallsign.isEmpty, !defaultCallsign.isEmpty {
                myCallsign = defaultCallsign
            }
            if myGrid.isEmpty, !defaultGrid.isEmpty {
                myGrid = defaultGrid
            }
            selectedMode = defaultMode
        }
    }

    private var modeSection: some View {
        Section("Mode") {
            Picker("Mode", selection: $selectedMode) {
                ForEach(["CW", "SSB", "FT8", "FT4", "RTTY", "AM", "FM"], id: \.self) { mode in
                    Text(mode).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var frequencySection: some View {
        Section {
            HStack {
                TextField("14.060", text: $frequency)
                    .keyboardType(.decimalPad)
                    .font(.title3.monospaced())

                Text("MHz")
                    .foregroundStyle(.secondary)
            }

            frequencySuggestions
        } header: {
            Text("Frequency")
        } footer: {
            Text("Optional - you can change frequency during the session")
        }
    }

    private var frequencySuggestions: some View {
        let suggestions = LoggingSession.suggestedFrequencies(for: selectedMode)
        let sortedBands = ["160m", "80m", "40m", "30m", "20m", "17m", "15m", "12m", "10m"]
            .filter { suggestions[$0] != nil }

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sortedBands, id: \.self) { band in
                    if let freq = suggestions[band] {
                        Button {
                            frequency = String(format: "%.3f", freq)
                        } label: {
                            VStack(spacing: 2) {
                                Text(band)
                                    .font(.caption.weight(.medium))
                                Text(String(format: "%.3f", freq))
                                    .font(.caption2.monospaced())
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                frequency == String(format: "%.3f", freq)
                                    ? Color.accentColor.opacity(0.2)
                                    : Color(.tertiarySystemGroupedBackground)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var activationSection: some View {
        Section("Activation Type") {
            Picker("Type", selection: $activationType) {
                ForEach(ActivationType.allCases, id: \.self) { type in
                    Label(type.displayName, systemImage: type.icon)
                        .tag(type)
                }
            }
            .pickerStyle(.segmented)

            if activationType == .pota {
                HStack {
                    Text("Park")
                        .foregroundStyle(.secondary)
                    Spacer()
                    TextField("K-1234", text: $parkReference)
                        .textInputAutocapitalization(.characters)
                        .multilineTextAlignment(.trailing)
                        .font(.subheadline.monospaced())
                }

                if let parkName = lookupParkName(parkReference) {
                    Text(parkName)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            if activationType == .sota {
                HStack {
                    Text("Summit")
                        .foregroundStyle(.secondary)
                    Spacer()
                    TextField("W4C/CM-001", text: $sotaReference)
                        .textInputAutocapitalization(.characters)
                        .multilineTextAlignment(.trailing)
                        .font(.subheadline.monospaced())
                }
            }
        }
    }

    private var optionsSection: some View {
        Section {
            Toggle("Skip wizard next time", isOn: $skipWizard)

            Button {
                saveDefaults()
            } label: {
                Label("Save as Defaults", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("Options")
        } footer: {
            Text("Defaults are used when starting a new session")
        }
    }

    private func startSession() {
        sessionManager?.startSession(
            myCallsign: myCallsign.uppercased(),
            mode: selectedMode,
            frequency: parsedFrequency,
            activationType: activationType,
            parkReference: activationType == .pota ? parkReference.uppercased() : nil,
            sotaReference: activationType == .sota ? sotaReference.uppercased() : nil,
            myGrid: myGrid.isEmpty ? nil : myGrid.uppercased()
        )

        // Save callsign as default for next time
        defaultCallsign = myCallsign.uppercased()

        onDismiss()
    }

    private func saveDefaults() {
        defaultCallsign = myCallsign.uppercased()
        defaultMode = selectedMode
        if !myGrid.isEmpty {
            defaultGrid = myGrid.uppercased()
        }
    }

    private func lookupParkName(_ reference: String) -> String? {
        guard !reference.isEmpty else {
            return nil
        }
        return POTAParksCache.shared.name(for: reference.uppercased())
    }
}

// MARK: - Preview

#Preview {
    SessionStartSheet(
        sessionManager: nil,
        onDismiss: {}
    )
}
