import SwiftData
import SwiftUI

// MARK: - DashboardView

struct DashboardView: View {
    @Environment(\.modelContext) var modelContext
    @Query var qsos: [QSO]
    @Query var allPresence: [ServicePresence]

    @ObservedObject var iCloudMonitor: ICloudMonitor
    @ObservedObject var potaAuth: POTAAuthService
    @ObservedObject var syncService: SyncService
    @Binding var selectedTab: AppTab
    @Binding var settingsDestination: SettingsDestination?
    let tourState: TourState

    @AppStorage("debugMode") var debugMode = false
    @AppStorage("bypassPOTAMaintenance") var bypassPOTAMaintenance = false

    var importService: ImportService {
        ImportService(modelContext: modelContext)
    }

    let lofiClient = LoFiClient()
    let qrzClient = QRZClient()
    let hamrsClient = HAMRSClient()
    let lotwClient = LoTWClient()

    /// Statistics
    var stats: QSOStatistics {
        QSOStatistics(qsos: qsos)
    }

    /// Derived counts from ServicePresence
    func uploadedCount(for service: ServiceType) -> Int {
        allPresence.filter { $0.serviceType == service && $0.isPresent }.count
    }

    func pendingCount(for service: ServiceType) -> Int {
        allPresence.filter { $0.serviceType == service && $0.needsUpload }.count
    }

    // Sync state
    @State var isSyncing = false
    @State var syncingService: ServiceType?
    @State var lastSyncDate: Date?
    @State var lofiSyncResult: String?

    // QRZ state
    @State var qrzCallsign: String?
    @State var qrzIsConfigured: Bool = false
    @State var qrzSyncResult: String?

    /// POTA state
    @State var potaSyncResult: String?

    /// HAMRS state
    @State var hamrsSyncResult: String?

    /// LoTW state
    @State var lotwSyncResult: String?

    // Service configuration state (refreshed on appear)
    @State var lofiIsConfigured: Bool = false
    @State var lofiIsLinked: Bool = false
    @State var lofiCallsign: String?
    @State var hamrsIsConfigured: Bool = false
    @State var lotwIsConfigured: Bool = false

    /// Service detail sheet state
    @State var selectedService: ServiceIdentifier?

    /// Callsign alias detection state
    @State var unconfiguredCallsigns: Set<String> = []
    @State var showingCallsignAliasAlert = false
    let aliasService = CallsignAliasService.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    activityCard
                    summaryCard
                    servicesList
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .onAppear {
                loadQRZConfig()
                refreshServiceStatus()
            }
            .task {
                await checkForUnconfiguredCallsigns()
            }
            .callsignAliasDetectionAlert(
                unconfiguredCallsigns: $unconfiguredCallsigns,
                showingAlert: $showingCallsignAliasAlert,
                onAccept: { await addUnconfiguredCallsignsAsAliases() },
                onOpenSettings: {
                    selectedTab = .settings
                    settingsDestination = nil
                }
            )
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    toolbarButtons
                }
            }
            .sheet(item: $selectedService) { service in
                serviceDetailSheet(for: service)
            }
        }
    }

    // MARK: - Toolbar

    private var toolbarButtons: some View {
        HStack(spacing: 12) {
            if debugMode {
                Button {
                    Task { await performDownloadOnly() }
                } label: {
                    if isSyncing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.down.circle")
                    }
                }
                .disabled(isSyncing)
                .accessibilityLabel("Download only")
            }

            Button {
                Task { await performFullSync() }
            } label: {
                if isSyncing {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
            }
            .disabled(isSyncing)
            .accessibilityLabel("Sync all services")
        }
    }

    // MARK: - Activity Card

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Activity")
                    .font(.headline)
                Spacer()
                Text("\(stats.totalQSOs) QSOs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ActivityGrid(activityData: stats.activityByDate)
                .frame(height: 115)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Statistics")
                    .font(.headline)
                Spacer()
                if let lastSync = lastSyncDate {
                    Text("Synced \(lastSync, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            statsGrid
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var statsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 12
        ) {
            Button {
                selectedTab = .logs
            } label: {
                StatBox(
                    title: "QSOs",
                    value: "\(stats.totalQSOs)",
                    icon: "antenna.radiowaves.left.and.right"
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                StatDetailView(category: .qsls, items: stats.items(for: .qsls), tourState: tourState)
            } label: {
                StatBox(title: "QSLs", value: "\(stats.confirmedQSLs)", icon: "checkmark.seal")
            }
            .buttonStyle(.plain)

            if lotwIsConfigured {
                NavigationLink {
                    StatDetailView(category: .entities, items: stats.items(for: .entities), tourState: tourState)
                } label: {
                    StatBox(title: "DXCC Entities", value: "\(stats.uniqueEntities)", icon: "globe")
                }
                .buttonStyle(.plain)
            } else {
                StatBox(title: "DXCC Entities", value: "--", icon: "globe")
                    .opacity(0.5)
            }

            NavigationLink {
                StatDetailView(category: .grids, items: stats.items(for: .grids), tourState: tourState)
            } label: {
                StatBox(title: "Grids", value: "\(stats.uniqueGrids)", icon: "square.grid.3x3")
            }
            .buttonStyle(.plain)

            NavigationLink {
                StatDetailView(category: .bands, items: stats.items(for: .bands), tourState: tourState)
            } label: {
                StatBox(title: "Bands", value: "\(stats.uniqueBands)", icon: "waveform")
            }
            .buttonStyle(.plain)

            NavigationLink {
                StatDetailView(category: .parks, items: stats.items(for: .parks), tourState: tourState)
            } label: {
                ActivationsStatBox(successful: stats.successfulActivations)
            }
            .buttonStyle(.plain)
        }
    }
}

// Services list and detail sheets are in DashboardView+Services.swift
// Action methods are in DashboardView+Actions.swift
// Helper views are in DashboardHelperViews.swift
