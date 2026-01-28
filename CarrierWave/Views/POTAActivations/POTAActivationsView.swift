// POTA Activations view
//
// Displays activations grouped by park, with upload status per activation
// and ability to upload pending QSOs to POTA.

import SwiftData
import SwiftUI

// MARK: - POTAActivationsContentView

struct POTAActivationsContentView: View {
    // MARK: Internal

    let potaClient: POTAClient?
    let potaAuth: POTAAuthService
    let tourState: TourState

    var body: some View {
        Group {
            if activations.isEmpty {
                emptyStateView
            } else {
                activationsList
            }
        }
        .miniTour(.potaActivations, tourState: tourState)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if isAuthenticated, potaClient != nil {
                    Button {
                        Task { await refreshJobs() }
                    } label: {
                        if isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isLoading)
                }
            }
        }
        .sheet(item: $activationToUpload) { activation in
            UploadConfirmationSheet(
                activation: activation,
                parkName: parkName(for: activation.parkReference),
                onUpload: { await uploadActivation(activation) },
                onCancel: { activationToUpload = nil }
            )
        }
        .confirmationDialog(
            "Reject Upload",
            isPresented: Binding(
                get: { activationToReject != nil },
                set: {
                    if !$0 {
                        activationToReject = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Reject Upload", role: .destructive) {
                if let activation = activationToReject {
                    rejectActivation(activation)
                }
            }
            Button("Cancel", role: .cancel) {
                activationToReject = nil
            }
        } message: {
            if let activation = activationToReject {
                let parkDisplay =
                    if let name = parkName(for: activation.parkReference) {
                        "\(activation.parkReference) - \(name)"
                    } else {
                        activation.parkReference
                    }
                Text(rejectMessage(for: parkDisplay, pendingCount: activation.pendingCount))
            }
        }
        .onAppear {
            if isAuthenticated, potaClient != nil, jobs.isEmpty {
                Task { await refreshJobs() }
            }
            startMaintenanceTimer()
            Task {
                await loadCachedParkNames()
            }
        }
        .onDisappear {
            stopMaintenanceTimer()
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @AppStorage("debugMode") private var debugMode = false
    @AppStorage("bypassPOTAMaintenance") private var bypassMaintenance = false
    @Query(filter: #Predicate<QSO> { $0.parkReference != nil })
    private var allParkQSOs: [QSO]

    @State private var jobs: [POTAJob] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var activationToUpload: POTAActivation?
    @State private var activationToReject: POTAActivation?
    @State private var maintenanceTimeRemaining: String?
    @State private var maintenanceTimer: Timer?
    @State private var cachedParkNames: [String: String] = [:]

    private var isInMaintenance: Bool {
        if debugMode, bypassMaintenance {
            return false
        }
        return POTAClient.isInMaintenanceWindow()
    }

    private var isAuthenticated: Bool {
        potaAuth.isAuthenticated
    }

    private var activations: [POTAActivation] {
        POTAActivation.groupQSOs(allParkQSOs)
    }

    private var activationsByPark: [(park: String, activations: [POTAActivation])] {
        POTAActivation.groupByPark(activations)
    }

    /// Activations with pending uploads (not fully uploaded and not rejected), sorted by date descending
    private var pendingActivations: [POTAActivation] {
        activations
            .filter { $0.hasQSOsToUpload && !$0.isRejected }
            .sorted { $0.utcDate > $1.utcDate }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Activations", systemImage: "tree")
        } description: {
            Text("QSOs with park references will appear here grouped by activation.")
        }
    }

    @ViewBuilder
    private var maintenanceBanner: some View {
        HStack {
            Image(systemName: "wrench.and.screwdriver")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("POTA Maintenance Window")
                    .font(.subheadline)
                    .fontWeight(.medium)
                if let remaining = maintenanceTimeRemaining {
                    Text("Uploads disabled. Resumes in \(remaining)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Uploads temporarily disabled (2330-0400 UTC)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var activationsList: some View {
        List {
            if isInMaintenance {
                Section {
                    maintenanceBanner
                }
            }

            if let error = errorMessage {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                        Spacer()
                        Button("Retry") {
                            Task { await refreshJobs() }
                        }
                        .font(.caption)
                    }
                }
            }

            // Ready to Upload section - pending activations sorted by date
            if !pendingActivations.isEmpty {
                Section {
                    ForEach(pendingActivations) { activation in
                        ActivationRow(
                            activation: activation,
                            isUploadDisabled: isInMaintenance || potaClient == nil,
                            onUploadTapped: { activationToUpload = activation },
                            onRejectTapped: { activationToReject = activation },
                            showParkReference: true
                        )
                    }
                } header: {
                    Label("Ready to Upload", systemImage: "arrow.up.circle")
                }
            }

            // All activations grouped by park
            ForEach(activationsByPark, id: \.park) { parkGroup in
                Section {
                    ForEach(parkGroup.activations) { activation in
                        ActivationRow(
                            activation: activation,
                            isUploadDisabled: isInMaintenance || potaClient == nil,
                            onUploadTapped: { activationToUpload = activation },
                            onRejectTapped: { activationToReject = activation }
                        )
                    }
                } header: {
                    HStack {
                        Text(parkGroup.park)
                        if let name = parkName(for: parkGroup.park) {
                            Text("- \(name)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .refreshable {
            await refreshJobs()
        }
    }

    private func startMaintenanceTimer() {
        updateMaintenanceTime()
        maintenanceTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            updateMaintenanceTime()
        }
    }

    private func stopMaintenanceTimer() {
        maintenanceTimer?.invalidate()
        maintenanceTimer = nil
    }

    private func updateMaintenanceTime() {
        maintenanceTimeRemaining = POTAClient.formatMaintenanceTimeRemaining()
    }

    private func parkName(for reference: String) -> String? {
        // First try from fetched jobs (most accurate for user's parks)
        if let name = jobs.first(where: {
            $0.reference.uppercased() == reference.uppercased()
        })?.parkName {
            return name
        }
        // Fall back to cached park names
        return cachedParkNames[reference.uppercased()]
    }

    private func rejectMessage(for parkDisplay: String, pendingCount: Int) -> String {
        """
        Reject upload for \(parkDisplay)?

        This will hide \(pendingCount) QSO(s) from POTA uploads. \
        They will remain in your log but won't be prompted for upload again.
        """
    }
}

// MARK: - Actions

extension POTAActivationsContentView {
    func loadCachedParkNames() async {
        await POTAParksCache.shared.ensureLoaded()
        // Pre-load names for all parks in our activations
        var names: [String: String] = [:]
        for activation in activations {
            let ref = activation.parkReference.uppercased()
            if let name = await POTAParksCache.shared.name(for: ref) {
                names[ref] = name
            }
        }
        await MainActor.run {
            cachedParkNames = names
        }
    }

    func refreshJobs() async {
        guard isAuthenticated, let potaClient else {
            return
        }
        isLoading = true
        errorMessage = nil

        do {
            let fetchedJobs = try await potaClient.fetchJobs()
            await MainActor.run {
                jobs = fetchedJobs
            }
        } catch POTAError.notAuthenticated {
            await MainActor.run {
                errorMessage = "Session expired. Please re-authenticate in Settings."
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }

        await MainActor.run {
            isLoading = false
        }
    }

    func uploadActivation(_ activation: POTAActivation) async {
        activationToUpload = nil

        guard let potaClient else {
            await MainActor.run {
                errorMessage = "POTA client not available. Please sign in to POTA in Settings."
            }
            return
        }

        let pendingQSOs = activation.pendingQSOs()
        guard !pendingQSOs.isEmpty else {
            return
        }

        do {
            let result = try await potaClient.uploadActivationWithRecording(
                parkReference: activation.parkReference,
                qsos: pendingQSOs,
                modelContext: modelContext
            )

            if result.success {
                await MainActor.run {
                    for qso in pendingQSOs {
                        qso.markPresent(in: .pota, context: modelContext)
                    }
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = "Upload failed: \(error.localizedDescription)"
            }
        }
    }

    func rejectActivation(_ activation: POTAActivation) {
        let pendingQSOs = activation.pendingQSOs()
        for qso in pendingQSOs {
            qso.markUploadRejected(for: .pota, context: modelContext)
        }
        activationToReject = nil
    }
}

// Helper views are in POTAActivationsHelperViews.swift
