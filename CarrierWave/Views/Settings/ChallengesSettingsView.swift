import SwiftData
import SwiftUI

// MARK: - ChallengesSettingsView

struct ChallengesSettingsView: View {
    // MARK: Internal

    var body: some View {
        List {
            Section {
                TextField("Callsign", text: $userCallsign)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            } header: {
                Text("Your Station")
            } footer: {
                Text("Your callsign is sent to challenge servers when you join.")
            }

            Section {
                ForEach(sources) { source in
                    sourceRow(source)
                }
                .onDelete(perform: deleteSources)

                Button {
                    showingAddSource = true
                } label: {
                    Label("Add Server", systemImage: "plus")
                }
            } header: {
                Text("Challenge Servers")
            } footer: {
                Text("Challenge servers host competitions and track leaderboards.")
            }
        }
        .navigationTitle("Challenges")
        .onAppear {
            if syncService == nil {
                syncService = ChallengesSyncService(modelContext: modelContext)
            }
            Task {
                await ensureOfficialSource()
            }
        }
        .sheet(isPresented: $showingAddSource) {
            AddChallengeServerSheet(syncService: syncService)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext

    @AppStorage("userCallsign") private var userCallsign = ""

    @Query(sort: \ChallengeSource.name) private var sources: [ChallengeSource]

    @State private var syncService: ChallengesSyncService?
    @State private var showingAddSource = false
    @State private var showingError = false
    @State private var errorMessage = ""

    private func sourceRow(_ source: ChallengeSource) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(source.name)
                        .font(.body)

                    if source.isOfficial {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }

                Text(source.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let error = source.lastError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(error)
            } else if source.lastFetched != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private func deleteSources(at offsets: IndexSet) {
        for index in offsets {
            let source = sources[index]
            // Don't allow deleting official source
            if source.isOfficial {
                errorMessage = "Cannot remove the official challenge server"
                showingError = true
                continue
            }
            modelContext.delete(source)
        }
        try? modelContext.save()
    }

    private func ensureOfficialSource() async {
        guard let syncService else {
            return
        }

        do {
            _ = try syncService.getOrCreateOfficialSource()
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

// MARK: - AddChallengeServerSheet

struct AddChallengeServerSheet: View {
    // MARK: Internal

    let syncService: ChallengesSyncService?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Server URL", text: $url)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    TextField("Display Name", text: $name)
                } footer: {
                    Text("Enter the URL of a community challenge server.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addSource()
                    }
                    .disabled(url.isEmpty || name.isEmpty || isAdding)
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @State private var url = ""
    @State private var name = ""
    @State private var isAdding = false
    @State private var errorMessage: String?

    private func addSource() {
        guard let syncService else {
            return
        }

        isAdding = true
        errorMessage = nil

        do {
            _ = try syncService.addCommunitySource(url: url, name: name)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isAdding = false
        }
    }
}

#Preview {
    NavigationStack {
        ChallengesSettingsView()
    }
    .modelContainer(for: ChallengeSource.self, inMemory: true)
}
