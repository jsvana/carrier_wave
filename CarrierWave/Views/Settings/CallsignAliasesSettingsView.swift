import SwiftData
import SwiftUI

// MARK: - CallsignAliasesSettingsView

struct CallsignAliasesSettingsView: View {
    // MARK: Internal

    var body: some View {
        List {
            currentCallsignSection
            previousCallsignsSection
            addPreviousCallsignSection
        }
        .navigationTitle("Callsign Aliases")
        .task { await loadCallsigns() }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @State private var currentCallsign = ""
    @State private var previousCallsigns: [String] = []
    @State private var newPreviousCallsign = ""
    @State private var isLoading = true
    @State private var showingError = false
    @State private var errorMessage = ""

    private let aliasService = CallsignAliasService.shared

    // MARK: - Sections

    private var currentCallsignSection: some View {
        Section {
            HStack {
                TextField("Current Callsign", text: $currentCallsign)
                    .autocapitalization(.allCharacters)
                    .autocorrectionDisabled()

                if !currentCallsign.isEmpty {
                    Button("Save") {
                        Task { await saveCurrentCallsign() }
                    }
                    .disabled(isLoading)
                }
            }
        } header: {
            Text("Current Callsign")
        } footer: {
            Text("Your current amateur radio callsign. Auto-populated from QRZ when you connect.")
        }
    }

    private var previousCallsignsSection: some View {
        Section {
            if previousCallsigns.isEmpty {
                Text("No previous callsigns")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(previousCallsigns, id: \.self) { callsign in
                    HStack {
                        Text(callsign)
                        Spacer()
                        Button {
                            Task { await removePreviousCallsign(callsign) }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } header: {
            Text("Previous Callsigns")
        } footer: {
            Text(
                """
                Add your previous callsigns so QSOs logged under old calls are properly matched \
                during sync.
                """
            )
        }
    }

    private var addPreviousCallsignSection: some View {
        Section {
            HStack {
                TextField("Add Previous Callsign", text: $newPreviousCallsign)
                    .autocapitalization(.allCharacters)
                    .autocorrectionDisabled()

                Button("Add") {
                    Task { await addPreviousCallsign() }
                }
                .disabled(newPreviousCallsign.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func loadCallsigns() async {
        isLoading = true
        defer { isLoading = false }

        currentCallsign = await aliasService.getCurrentCallsign() ?? ""
        previousCallsigns = await aliasService.getPreviousCallsigns()
    }

    private func saveCurrentCallsign() async {
        do {
            let trimmed = currentCallsign.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                try await aliasService.clearCurrentCallsign()
            } else {
                try await aliasService.saveCurrentCallsign(trimmed)
            }
            currentCallsign = await aliasService.getCurrentCallsign() ?? ""
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func addPreviousCallsign() async {
        let callsign = newPreviousCallsign.trimmingCharacters(in: .whitespaces)
        guard !callsign.isEmpty else {
            return
        }

        do {
            try await aliasService.addPreviousCallsign(callsign)
            newPreviousCallsign = ""
            previousCallsigns = await aliasService.getPreviousCallsigns()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func removePreviousCallsign(_ callsign: String) async {
        do {
            try await aliasService.removePreviousCallsign(callsign)
            previousCallsigns = await aliasService.getPreviousCallsigns()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

// MARK: - CallsignAliasDetectionAlert

/// Helper view modifier to show callsign detection alerts
struct CallsignAliasDetectionAlert: ViewModifier {
    @Binding var unconfiguredCallsigns: Set<String>
    @Binding var showingAlert: Bool

    let onAccept: () async -> Void
    let onOpenSettings: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("Multiple Callsigns Detected", isPresented: $showingAlert) {
                Button("Add as Previous") {
                    Task { await onAccept() }
                }
                Button("Open Settings") {
                    onOpenSettings()
                }
                Button("Dismiss", role: .cancel) {}
            } message: {
                let callsignList = unconfiguredCallsigns.sorted().joined(separator: ", ")
                Text(
                    """
                    Found QSOs logged under callsigns that aren't configured: \(callsignList). \
                    Add these as your previous callsigns?
                    """
                )
            }
    }
}

extension View {
    func callsignAliasDetectionAlert(
        unconfiguredCallsigns: Binding<Set<String>>,
        showingAlert: Binding<Bool>,
        onAccept: @escaping () async -> Void,
        onOpenSettings: @escaping () -> Void
    ) -> some View {
        modifier(
            CallsignAliasDetectionAlert(
                unconfiguredCallsigns: unconfiguredCallsigns,
                showingAlert: showingAlert,
                onAccept: onAccept,
                onOpenSettings: onOpenSettings
            )
        )
    }
}
