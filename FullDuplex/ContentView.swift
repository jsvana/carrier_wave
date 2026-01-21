import SwiftUI
import SwiftData

struct ContentView: View {
    @StateObject private var iCloudMonitor = ICloudMonitor()

    var body: some View {
        TabView {
            DashboardView(iCloudMonitor: iCloudMonitor)
                .tabItem {
                    Label("Dashboard", systemImage: "square.grid.2x2")
                }

            LogsListView()
                .tabItem {
                    Label("Logs", systemImage: "list.bullet")
                }

            SettingsMainView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .onAppear {
            iCloudMonitor.startMonitoring()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [QSO.self, SyncRecord.self, UploadDestination.self], inMemory: true)
}
