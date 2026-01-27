import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - AppDelegate

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = ShakeDetectingSceneDelegate.self
        return config
    }
}

// MARK: - ShakeDetectingSceneDelegate

class ShakeDetectingSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else {
            return
        }
        window = ShakeDetectingWindow(windowScene: windowScene)
    }
}

// MARK: - CarrierWaveApp

@main
struct CarrierWaveApp: App {
    // MARK: Internal

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            QSO.self,
            ServicePresence.self,
            UploadDestination.self,
            POTAUploadAttempt.self,
            ActivationMetadata.self,
            ChallengeSource.self,
            ChallengeDefinition.self,
            ChallengeParticipation.self,
            LeaderboardCache.self,
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
            // If schema migration fails, log and crash
            // In production, you might want to handle this more gracefully
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    await POTAParksCache.shared.ensureLoaded()
                }
                .onOpenURL { url in
                    handleURL(url)
                }
        }
        .modelContainer(sharedModelContainer)
    }

    // MARK: Private

    private func handleURL(_ url: URL) {
        // Check if it's a challenge invite link
        if url.scheme == "carrierwave", url.host == "challenge" {
            handleChallengeURL(url)
            return
        }

        // Otherwise treat as ADIF file
        NotificationCenter.default.post(
            name: .didReceiveADIFFile,
            object: url
        )
    }

    private func handleChallengeURL(_ url: URL) {
        // Parse carrierwave://challenge/join?source=...&id=...&token=...
        guard url.path == "/join" else {
            return
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        var params: [String: String] = [:]
        for item in queryItems {
            if let value = item.value {
                params[item.name] = value
            }
        }

        guard let source = params["source"],
              let idString = params["id"],
              let challengeId = UUID(uuidString: idString)
        else {
            return
        }

        let token = params["token"]

        NotificationCenter.default.post(
            name: .didReceiveChallengeInvite,
            object: nil,
            userInfo: [
                "source": source,
                "challengeId": challengeId,
                "token": token as Any,
            ]
        )
    }
}

extension Notification.Name {
    static let didReceiveADIFFile = Notification.Name("didReceiveADIFFile")
    static let didReceiveChallengeInvite = Notification.Name("didReceiveChallengeInvite")
    static let didSyncQSOs = Notification.Name("didSyncQSOs")
}
