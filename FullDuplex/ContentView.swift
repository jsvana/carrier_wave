import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        Text("Full Duplex")
            .font(.largeTitle)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [QSO.self, SyncRecord.self, UploadDestination.self], inMemory: true)
}
