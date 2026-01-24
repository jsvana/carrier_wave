import SwiftData
import SwiftUI

// MARK: - AppTab

enum AppTab: Hashable {
    case dashboard
    case logs
    case potaUploads
    case settings
}

// MARK: - ContentView

struct ContentView: View {
    // MARK: Internal

    var body: some View {
        TabView(selection: $selectedTab) {
            if let syncService {
                DashboardView(
                    iCloudMonitor: iCloudMonitor,
                    potaAuth: potaAuthService,
                    syncService: syncService,
                    selectedTab: $selectedTab
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

            LogsListView()
                .tabItem {
                    Label("QSOs", systemImage: "list.bullet")
                }
                .tag(AppTab.logs)

            if let potaClient {
                POTAUploadsView(potaClient: potaClient, potaAuth: potaAuthService)
                    .tabItem {
                        Label("POTA Uploads", systemImage: "arrow.up.doc")
                    }
                    .tag(AppTab.potaUploads)
            }

            SettingsMainView(potaAuth: potaAuthService)
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
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReceiveADIFFile)) { notification in
            if let url = notification.object as? URL {
                // Handle import - for now just print
                print("Received ADIF file: \(url.lastPathComponent)")
            }
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext
    @StateObject private var iCloudMonitor = ICloudMonitor()
    @StateObject private var potaAuthService = POTAAuthService()
    @State private var selectedTab: AppTab = .dashboard
    @State private var syncService: SyncService?
    @State private var potaClient: POTAClient?
}

#Preview {
    ContentView()
        .modelContainer(
            for: [QSO.self, ServicePresence.self, UploadDestination.self, POTAUploadAttempt.self],
            inMemory: true
        )
}
