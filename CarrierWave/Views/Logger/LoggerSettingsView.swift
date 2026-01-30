import SwiftUI

// MARK: - LoggerSettingsView

/// Settings for the logger feature
struct LoggerSettingsView: View {
    // MARK: Internal

    var body: some View {
        Form {
            licenseSection
            defaultsSection
            displaySection
        }
        .navigationTitle("Logger Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Private

    @AppStorage("userLicenseClass") private var licenseClass = "Extra"
    @AppStorage("loggerDefaultCallsign") private var defaultCallsign = ""
    @AppStorage("loggerDefaultMode") private var defaultMode = "CW"
    @AppStorage("loggerDefaultGrid") private var defaultGrid = ""
    @AppStorage("loggerSkipWizard") private var skipWizard = false
    @AppStorage("loggerShowActivityPanel") private var showActivityPanel = true
    @AppStorage("loggerShowLicenseWarnings") private var showLicenseWarnings = true

    private var licenseSection: some View {
        Section {
            Picker("License Class", selection: $licenseClass) {
                Text("Technician").tag("Technician")
                Text("General").tag("General")
                Text("Extra").tag("Extra")
            }
            .pickerStyle(.segmented)

            Toggle("Show band privilege warnings", isOn: $showLicenseWarnings)
        } header: {
            Text("License Class")
        } footer: {
            Text("Used to warn when operating outside your band privileges")
        }
    }

    private var defaultsSection: some View {
        Section {
            HStack {
                Text("Callsign")
                Spacer()
                TextField("W1AW", text: $defaultCallsign)
                    .textInputAutocapitalization(.characters)
                    .multilineTextAlignment(.trailing)
                    .font(.subheadline.monospaced())
            }

            HStack {
                Text("Grid")
                Spacer()
                TextField("FN31", text: $defaultGrid)
                    .textInputAutocapitalization(.characters)
                    .multilineTextAlignment(.trailing)
                    .font(.subheadline.monospaced())
            }

            Picker("Default Mode", selection: $defaultMode) {
                ForEach(["CW", "SSB", "FT8", "FT4", "RTTY"], id: \.self) { mode in
                    Text(mode).tag(mode)
                }
            }

            Toggle("Skip session wizard", isOn: $skipWizard)
        } header: {
            Text("Defaults")
        } footer: {
            Text("These values are pre-filled when starting a new session")
        }
    }

    private var displaySection: some View {
        Section {
            Toggle("Show frequency activity", isOn: $showActivityPanel)
        } header: {
            Text("Display")
        } footer: {
            Text("Show nearby activity on the frequency (from RBN, POTA, etc.)")
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LoggerSettingsView()
    }
}
