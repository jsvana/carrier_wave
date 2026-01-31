import SwiftData
import SwiftUI

// MARK: - AppTab

enum AppTab: Hashable, CaseIterable {
    case dashboard
    case logger
    case logs
    case cwDecoder
    case more

    // MARK: Internal

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .logger: "Logger"
        case .logs: "Logs"
        case .cwDecoder: "CW"
        case .more: "More"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .logger: "pencil.and.list.clipboard"
        case .logs: "list.bullet"
        case .cwDecoder: "waveform"
        case .more: "ellipsis"
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
            } else if tourState.shouldShowOnboarding() {
                showOnboarding = true
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
            // Navigate to More tab (Activity is now within More)
            selectedTab = .more
        }
        .fullScreenCover(isPresented: $showIntroTour) {
            IntroTourView(tourState: tourState)
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(tourState: tourState, potaAuth: potaAuthService)
        }
        .onChange(of: tourState.hasCompletedIntroTour) { _, completed in
            // Show onboarding after intro tour completes
            if completed, tourState.shouldShowOnboarding() {
                showOnboarding = true
            }
        }
        .onChange(of: selectedTab) { _, _ in
            // Reset navigation paths when switching tabs to avoid stale submenu state
            moreTabNavigationPath = NavigationPath()
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @StateObject private var iCloudMonitor = ICloudMonitor()
    @StateObject private var potaAuthService = POTAAuthService()
    @State private var selectedTab: AppTab? = .dashboard
    @State private var settingsDestination: SettingsDestination?
    @State private var syncService: SyncService?
    @State private var potaClient: POTAClient?
    @State private var showIntroTour = false
    @State private var showOnboarding = false
    @State private var moreTabNavigationPath = NavigationPath()

    private let lofiClient = LoFiClient()
    private let qrzClient = QRZClient()
    private let hamrsClient = HAMRSClient()
    private let lotwClient = LoTWClient()

    // MARK: - iPhone Navigation (TabView)

    private var selectedTabBinding: Binding<AppTab> {
        Binding(
            get: { selectedTab ?? .dashboard },
            set: { selectedTab = $0 }
        )
    }

    // MARK: - iPad Navigation (Sidebar)

    private var iPadNavigation: some View {
        NavigationSplitView {
            List(AppTab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.title, systemImage: tab.icon)
            }
            .navigationTitle("Carrier Wave")
        } detail: {
            selectedTabContent
        }
    }

    private var iPhoneNavigation: some View {
        TabView(selection: selectedTabBinding) {
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

    @ViewBuilder
    private var selectedTabContent: some View {
        if let tab = selectedTab {
            selectedTabContent(for: tab)
        } else {
            Text("Select a tab")
                .foregroundStyle(.secondary)
        }
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

        case .logger:
            LoggerView(onSessionEnd: {
                selectedTab = .logs
            })

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
            CWTranscriptionView(
                onLog: { callsign in
                    UIPasteboard.general.string = callsign
                    selectedTab = .logs
                }
            )

        case .more:
            MoreTabView(
                potaAuthService: potaAuthService,
                settingsDestination: $settingsDestination,
                navigationPath: $moreTabNavigationPath,
                tourState: tourState,
                syncService: syncService
            )
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
