import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case dashboard
    case logs
    case settings
}

struct ContentView: View {
    @StateObject private var iCloudMonitor = ICloudMonitor()
    @State private var selectedTab: AppTab = .dashboard

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(iCloudMonitor: iCloudMonitor, selectedTab: $selectedTab)
                .tabItem {
                    Label("Dashboard", systemImage: "square.grid.2x2")
                }
                .tag(AppTab.dashboard)

            LogsListView()
                .tabItem {
                    Label("Logs", systemImage: "list.bullet")
                }
                .tag(AppTab.logs)

            SettingsMainView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(AppTab.settings)
        }
        .onAppear {
            iCloudMonitor.startMonitoring()
        }
        .onReceive(NotificationCenter.default.publisher(for: .didReceiveADIFFile)) { notification in
            if let url = notification.object as? URL {
                // Handle import - for now just print
                print("Received ADIF file: \(url.lastPathComponent)")
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [QSO.self, SyncRecord.self, UploadDestination.self], inMemory: true)
}
