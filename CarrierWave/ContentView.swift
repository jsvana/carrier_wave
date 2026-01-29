import SwiftData
import SwiftUI

// MARK: - AppTab

enum AppTab: Hashable, CaseIterable {
    case dashboard
    case logs
    case cwDecoder
    case map
    case activity
    case settings

    // MARK: Internal

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .logs: "Logs"
        case .cwDecoder: "CW"
        case .map: "Map"
        case .activity: "Activity"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .logs: "list.bullet"
        case .cwDecoder: "waveform"
        case .map: "map"
        case .activity: "person.2"
        case .settings: "gear"
        }
    }
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

    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                iPadNavigation
            } else {
                iPhoneNavigation
            }
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

    // MARK: - iPad Navigation (Sidebar)

    private var iPadNavigation: some View {
        NavigationSplitView {
            List {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Label(tab.title, systemImage: tab.icon)
                    }
                    .listRowBackground(selectedTab == tab ? Color.accentColor.opacity(0.2) : nil)
                }
            }
            .navigationTitle("Carrier Wave")
        } detail: {
            selectedTabContent
        }
    }

    // MARK: - iPhone Navigation (TabView)

    private var iPhoneNavigation: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                selectedTabContent(for: tab)
                    .tabItem {
                        Label(tab.title, systemImage: tab.icon)
                    }
                    .tag(tab)
            }
        }
    }

    // MARK: - Tab Content

    private var selectedTabContent: some View {
        selectedTabContent(for: selectedTab)
    }

    @ViewBuilder
    private func selectedTabContent(for tab: AppTab) -> some View {
        switch tab {
        case .dashboard:
            if let syncService {
                DashboardView(
                    iCloudMonitor: iCloudMonitor,
                    potaAuth: potaAuthService,
                    syncService: syncService,
                    selectedTab: $selectedTab,
                    settingsDestination: $settingsDestination,
                    tourState: tourState
                )
            } else {
                ProgressView()
            }

        case .logs:
            LogsContainerView(
                potaClient: potaClient,
                potaAuth: potaAuthService,
                lofiClient: lofiClient,
                qrzClient: qrzClient,
                hamrsClient: hamrsClient,
                lotwClient: lotwClient,
                tourState: tourState
            )

        case .cwDecoder:
            CWTranscriptionView()

        case .map:
            NavigationStack {
                QSOMapView()
            }

        case .activity:
            ActivityView(tourState: tourState)

        case .settings:
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
    }
}

#Preview {
    ContentView(tourState: TourState())
        .modelContainer(
            for: [QSO.self, ServicePresence.self, UploadDestination.self, POTAUploadAttempt.self],
            inMemory: true
        )
}
