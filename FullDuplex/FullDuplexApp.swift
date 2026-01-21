import SwiftUI
import SwiftData
import UniformTypeIdentifiers

@main
struct FullDuplexApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            QSO.self,
            SyncRecord.self,
            UploadDestination.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    handleADIFFile(url)
                }
        }
        .modelContainer(sharedModelContainer)
    }

    private func handleADIFFile(_ url: URL) {
        NotificationCenter.default.post(
            name: .didReceiveADIFFile,
            object: url
        )
    }
}

extension Notification.Name {
    static let didReceiveADIFFile = Notification.Name("didReceiveADIFFile")
}
