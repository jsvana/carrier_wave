import SwiftUI

// MARK: - MoreTabView

/// A custom "More" tab that shows hidden tabs and Settings
/// in a single NavigationStack to avoid nested navigation issues.
struct MoreTabView: View {
    // MARK: Internal

    @ObservedObject var potaAuthService: POTAAuthService
    @Binding var settingsDestination: SettingsDestination?
    @Binding var navigationPath: NavigationPath

    let tourState: TourState
    let syncService: SyncService?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                // Show hidden configurable tabs
                if !hiddenTabs.isEmpty {
                    Section {
                        ForEach(hiddenTabs, id: \.self) { tab in
                            NavigationLink {
                                tabContent(for: tab)
                            } label: {
                                Label(tab.title, systemImage: tab.icon)
                            }
                        }
                    }
                }

                Section {
                    NavigationLink {
                        settingsContent
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }
                }
            }
            .navigationTitle("More")
        }
        .onReceive(NotificationCenter.default.publisher(for: .tabConfigurationChanged)) { _ in
            updateHiddenTabs()
        }
        .onAppear {
            updateHiddenTabs()
        }
    }

    // MARK: Private

    @State private var hiddenTabs: [AppTab] = []

    @ViewBuilder
    private var settingsContent: some View {
        if let syncService {
            SettingsMainView(
                potaAuth: potaAuthService,
                destination: $settingsDestination,
                tourState: tourState,
                isInNavigationContext: true
            )
            .environmentObject(syncService)
        } else {
            // SyncService not yet available - show loading state to prevent
            // crashes in child views that expect @EnvironmentObject<SyncService>
            ProgressView("Loading...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .map:
            QSOMapView()
        case .activity:
            ActivityView(tourState: tourState, isInNavigationContext: true)
        case .dashboard:
            // Dashboard needs sync service, show placeholder if not available
            if let syncService {
                DashboardView(
                    iCloudMonitor: ICloudMonitor(),
                    potaAuth: potaAuthService,
                    syncService: syncService,
                    selectedTab: .constant(.dashboard),
                    settingsDestination: $settingsDestination,
                    tourState: tourState
                )
            } else {
                Text("Dashboard unavailable")
            }
        case .logger:
            LoggerView(tourState: tourState, onSessionEnd: {})
        case .logs:
            LogsContainerView(
                potaClient: nil,
                potaAuth: potaAuthService,
                lofiClient: LoFiClient(),
                qrzClient: QRZClient(),
                hamrsClient: HAMRSClient(),
                lotwClient: LoTWClient(),
                tourState: tourState
            )
        case .cwDecoder:
            CWTranscriptionView(onLog: { _ in })
        case .more:
            EmptyView()
        }
    }

    private func updateHiddenTabs() {
        let hidden = TabConfiguration.hiddenTabs()
        let order = TabConfiguration.tabOrder()
        // Get configurable tabs that are hidden, in their configured order
        hiddenTabs = order.filter { tab in
            tab != .more && hidden.contains(tab)
        }
    }
}
