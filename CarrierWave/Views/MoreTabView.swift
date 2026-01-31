import SwiftUI

// MARK: - MoreTabView

/// A custom "More" tab that combines Map, Activity, and Settings
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
                Section {
                    NavigationLink {
                        QSOMapView()
                    } label: {
                        Label("Map", systemImage: "map")
                    }

                    NavigationLink {
                        ActivityView(tourState: tourState, isInNavigationContext: true)
                    } label: {
                        Label("Activity", systemImage: "person.2")
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
    }

    // MARK: Private

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
            SettingsMainView(
                potaAuth: potaAuthService,
                destination: $settingsDestination,
                tourState: tourState,
                isInNavigationContext: true
            )
        }
    }
}
