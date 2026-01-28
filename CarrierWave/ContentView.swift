import SwiftData
import SwiftUI

// MARK: - AppTab

enum AppTab: Hashable {
    case dashboard
    case logs
    case map
    case activity
    case settings
}

// MARK: - SettingsDestination

enum SettingsDestination: Hashable {
    case qrz
    case pota
    case lofi
    case hamrs
    case lotw
    case icloud
}

// MARK: - ContentView

struct ContentView: View {
    // MARK: Internal

    let tourState: TourState

    var body: some View {
        TabView(selection: $selectedTab) {
            if let syncService {
                DashboardView(
                    iCloudMonitor: iCloudMonitor,
                    potaAuth: potaAuthService,
                    syncService: syncService,
                    selectedTab: $selectedTab,
                    settingsDestination: $settingsDestination,
                    tourState: tourState
                )
                .tabItem {
                    Label("Dashboard", systemImage: "square.grid.2x2")
                }
                .tag(AppTab.dashboard)
            } else {
                ProgressView()
                    .tabItem {
                        Label("Dashboard", systemImage: "square.grid.2x2")
                    }
                    .tag(AppTab.dashboard)
            }

            LogsContainerView(
                potaClient: potaClient,
                potaAuth: potaAuthService,
                lofiClient: lofiClient,
                qrzClient: qrzClient,
                hamrsClient: hamrsClient,
                lotwClient: lotwClient,
                tourState: tourState
            )
            .tabItem {
                Label("Logs", systemImage: "list.bullet")
            }
            .tag(AppTab.logs)

            NavigationStack {
                QSOMapView()
            }
            .tabItem {
                Label("Map", systemImage: "map")
            }
            .tag(AppTab.map)

            ChallengesView(tourState: tourState)
                .tabItem {
                    Label("Activity", systemImage: "person.2")
                }
                .tag(AppTab.activity)

            Group {
                if let syncService {
                    SettingsMainView(
                        potaAuth: potaAuthService,
                        destination: $settingsDestination,
                        tourState: tourState
                    )
                    .environmentObject(syncService)
                } else {
                    SettingsMainView(
                        potaAuth: potaAuthService,
                        destination: $settingsDestination,
                        tourState: tourState
                    )
                }
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(AppTab.settings)
        }
        .onAppear {
            iCloudMonitor.startMonitoring()
            if syncService == nil {
                syncService = SyncService(
                    modelContext: modelContext,
                    potaAuthService: potaAuthService
                )
            }
            if potaClient == nil {
                potaClient = POTAClient(authService: potaAuthService)
            }
            if tourState.shouldShowIntroTour() {
                showIntroTour = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReceiveADIFFile)) { notification in
            if let url = notification.object as? URL {
                // Handle import - for now just print
                print("Received ADIF file: \(url.lastPathComponent)")
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .didReceiveChallengeInvite)
        ) { notification in
            guard let userInfo = notification.userInfo,
                  userInfo["source"] is String,
                  userInfo["challengeId"] is UUID
            else {
                return
            }
            // Navigate to activity tab
            selectedTab = .activity
        }
        .fullScreenCover(isPresented: $showIntroTour) {
            IntroTourView(tourState: tourState)
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @StateObject private var iCloudMonitor = ICloudMonitor()
    @StateObject private var potaAuthService = POTAAuthService()
    @State private var selectedTab: AppTab = .dashboard
    @State private var settingsDestination: SettingsDestination?
    @State private var syncService: SyncService?
    @State private var potaClient: POTAClient?
    @State private var showIntroTour = false

    private let lofiClient = LoFiClient()
    private let qrzClient = QRZClient()
    private let hamrsClient = HAMRSClient()
    private let lotwClient = LoTWClient()
}

#Preview {
    ContentView(tourState: TourState())
        .modelContainer(
            for: [QSO.self, ServicePresence.self, UploadDestination.self, POTAUploadAttempt.self],
            inMemory: true
        )
}
