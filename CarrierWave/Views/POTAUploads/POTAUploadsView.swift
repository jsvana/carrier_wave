// POTA Uploads tab main view
//
// Displays unified timeline of local upload attempts and remote POTA job
// status, with refresh capability and authentication state handling.

import SwiftData
import SwiftUI

// MARK: - POTAUploadsContentView

/// Content-only view for embedding in LogsContainerView
struct POTAUploadsContentView: View {
    // MARK: Internal

    let potaClient: POTAClient
    let potaAuth: POTAAuthService

    var body: some View {
        Group {
            if !isAuthenticated {
                notAuthenticatedView
            } else if entries.isEmpty, !isLoading {
                emptyStateView
            } else {
                timelineList
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if isAuthenticated {
                    Button {
                        Task { await fetchJobs() }
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
        .onAppear {
            if isAuthenticated, jobs.isEmpty {
                Task { await fetchJobs() }
            }
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \POTAUploadAttempt.timestamp, order: .reverse) private var attempts:
        [POTAUploadAttempt]

    @State private var jobs: [POTAJob] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastFetchTime: Date?

    private var entries: [POTALogEntry] {
        POTALogEntry.merge(attempts: Array(attempts), jobs: jobs)
    }

    private var isAuthenticated: Bool {
        potaAuth.isAuthenticated
    }

    @ViewBuilder
    private var notAuthenticatedView: some View {
        ContentUnavailableView {
            Label("Not Authenticated", systemImage: "person.crop.circle.badge.xmark")
        } description: {
            Text("Sign in to POTA in Settings to view upload history and job status.")
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Upload History", systemImage: "doc.badge.arrow.up")
        } description: {
            Text("Upload QSOs to POTA to see them here. Jobs from POTA will appear after refresh.")
        } actions: {
            Button("Refresh") {
                Task { await fetchJobs() }
            }
        }
    }

    @ViewBuilder
    private var timelineList: some View {
        List {
            if let error = errorMessage {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                        Spacer()
                        Button("Retry") {
                            Task { await fetchJobs() }
                        }
                        .font(.caption)
                    }
                }
            }

            if let lastFetch = lastFetchTime {
                Section {
                    HStack {
                        Text("Last refreshed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(lastFetch, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                ForEach(entries) { entry in
                    POTALogEntryRow(entry: entry)
                }
            } header: {
                HStack {
                    Text("Upload Timeline")
                    Spacer()
                    Text("\(entries.count) entries")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .refreshable {
            await fetchJobs()
        }
    }

    private func fetchJobs() async {
        guard isAuthenticated else {
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let fetchedJobs = try await potaClient.fetchJobs()
            await MainActor.run {
                jobs = fetchedJobs
                lastFetchTime = Date()
                correlateJobsWithAttempts()
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

    private func correlateJobsWithAttempts() {
        for attempt in attempts where attempt.correlatedJobId == nil {
            if let matchingJob = jobs.first(where: { job in
                job.reference.uppercased() == attempt.parkReference.uppercased()
                    && abs(job.submitted.timeIntervalSince(attempt.timestamp)) < 300
            }) {
                attempt.correlatedJobId = matchingJob.jobId
            }
        }
    }
}
