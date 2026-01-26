// POTA Activations view
//
// Displays activations grouped by park, with upload status per activation
// and ability to upload pending QSOs to POTA.

import SwiftData
import SwiftUI

// MARK: - POTAActivationsContentView

struct POTAActivationsContentView: View {
    // MARK: Internal

    let potaClient: POTAClient
    let potaAuth: POTAAuthService

    var body: some View {
        Group {
            if !isAuthenticated {
                notAuthenticatedView
            } else if activations.isEmpty {
                emptyStateView
            } else {
                activationsList
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if isAuthenticated {
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
        .onAppear {
            if isAuthenticated, jobs.isEmpty {
                Task { await refreshJobs() }
            }
            startMaintenanceTimer()
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
    @State private var maintenanceTimeRemaining: String?
    @State private var maintenanceTimer: Timer?

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

    @ViewBuilder
    private var notAuthenticatedView: some View {
        ContentUnavailableView {
            Label("Not Authenticated", systemImage: "person.crop.circle.badge.xmark")
        } description: {
            Text("Sign in to POTA in Settings to view and upload activations.")
        }
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

            ForEach(activationsByPark, id: \.park) { parkGroup in
                Section {
                    ForEach(parkGroup.activations) { activation in
                        ActivationRow(
                            activation: activation,
                            isUploadDisabled: isInMaintenance,
                            onUploadTapped: { activationToUpload = activation }
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
        jobs.first { $0.reference.uppercased() == reference.uppercased() }?.parkName
    }

    private func refreshJobs() async {
        guard isAuthenticated else {
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

    private func uploadActivation(_ activation: POTAActivation) async {
        activationToUpload = nil

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
}

// MARK: - ActivationRow

private struct ActivationRow: View {
    // MARK: Internal

    let activation: POTAActivation
    var isUploadDisabled: Bool = false
    let onUploadTapped: () -> Void

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(activation.qsos.sorted { $0.timestamp > $1.timestamp }) { qso in
                POTAQSORow(qso: qso)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(activation.displayDate)
                            .font(.headline)
                        Text(activation.callsign)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Image(systemName: activation.status.iconName)
                            .foregroundStyle(statusColor)
                        Text("\(activation.uploadedCount)/\(activation.qsoCount) QSOs uploaded")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if activation.hasQSOsToUpload {
                    Button("Upload") {
                        onUploadTapped()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isUploadDisabled)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Private

    @State private var isExpanded = false

    private var statusColor: Color {
        switch activation.status {
        case .uploaded: .green
        case .partial: .orange
        case .pending: .gray
        }
    }
}

// MARK: - POTAQSORow

private struct POTAQSORow: View {
    // MARK: Internal

    let qso: QSO

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(qso.callsign)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(timeString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Text(qso.band)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(4)
                Text(qso.mode)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(4)
            }

            if qso.isPresentInPOTA() {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Private

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: qso.timestamp) + " UTC"
    }
}

// MARK: - UploadConfirmationSheet

private struct UploadConfirmationSheet: View {
    // MARK: Internal

    let activation: POTAActivation
    let parkName: String?
    let onUpload: () async -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text(activation.parkReference)
                        .font(.title)
                        .fontWeight(.bold)
                    if let name = parkName {
                        Text(name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 12) {
                    DetailRow(label: "Date", value: activation.displayDate)
                    DetailRow(label: "Callsign", value: activation.callsign)
                    DetailRow(
                        label: "QSOs to Upload",
                        value: "\(activation.pendingCount) of \(activation.qsoCount)"
                    )
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)

                Spacer()

                if isUploading {
                    ProgressView("Uploading...")
                } else {
                    VStack(spacing: 12) {
                        Button {
                            isUploading = true
                            Task {
                                await onUpload()
                            }
                        } label: {
                            Text("Upload \(activation.pendingCount) QSOs")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Button("Cancel", role: .cancel) {
                            onCancel()
                        }
                    }
                }
            }
            .padding()
            .navigationTitle("Upload Activation")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    // MARK: Private

    @State private var isUploading = false
}

// MARK: - DetailRow

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}
