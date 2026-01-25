import SwiftUI

// MARK: - LogsSegment

enum LogsSegment: String, CaseIterable {
    case qsos = "QSOs"
    case potaUploads = "POTA Uploads"
}

// MARK: - LogsContainerView

struct LogsContainerView: View {
    // MARK: Internal

    let potaClient: POTAClient?
    let potaAuth: POTAAuthService

    var body: some View {
        NavigationStack {
            selectedContent
                .navigationTitle("Logs")
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        segmentedPicker
                    }
                }
        }
    }

    // MARK: Private

    @State private var selectedSegment: LogsSegment = .qsos

    private var availableSegments: [LogsSegment] {
        if potaClient != nil {
            LogsSegment.allCases
        } else {
            [.qsos]
        }
    }

    @ViewBuilder
    private var segmentedPicker: some View {
        Picker("Log Type", selection: $selectedSegment) {
            ForEach(availableSegments, id: \.self) { segment in
                Text(segment.rawValue).tag(segment)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedSegment {
        case .qsos:
            LogsListContentView()
        case .potaUploads:
            if let potaClient {
                POTAUploadsContentView(potaClient: potaClient, potaAuth: potaAuth)
            }
        }
    }
}
