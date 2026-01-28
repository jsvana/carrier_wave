import Foundation

// MARK: - MiniTourContent

enum MiniTourContent {
    static let potaActivations: [TourPage] = [
        TourPage(
            icon: "tree",
            title: "Your POTA Activations",
            body: """
            QSOs with a park reference are grouped here by park and date. \
            Each group is an activation you can upload to POTA.
            """
        ),
        TourPage(
            icon: "arrow.up.doc",
            title: "Uploading to POTA",
            body: """
            Tap an activation to review its QSOs, then upload. You need 10+ QSOs \
            for activation credit, but you can upload smaller logs to credit your hunters.
            """
        ),
    ]

    static let potaAccountSetup: [TourPage] = [
        TourPage(
            icon: "person.2.badge.gearshape",
            title: "POTA Accounts Explained",
            body: "POTA has two account systems that can be confusing."
        ),
        TourPage(
            icon: "server.rack",
            title: "External Logins (Google, Apple, etc.)",
            body: """
            If you registered years ago, you may have an external login (Google, Apple, etc.). \
            This is separate from your pota.app account.
            """
        ),
        TourPage(
            icon: "envelope.badge.person.crop",
            title: "Creating a pota.app Account",
            body: """
            Go to pota.app, create an account with email/password, then link your \
            existing service login in your profile settings. Carrier Wave uses \
            your pota.app credentials.
            """
        ),
    ]

    static let challenges: [TourPage] = [
        TourPage(
            icon: "person.2",
            title: "Activity & Social",
            body: """
            This is your social hub. Join challenges to track progress toward awards, \
            compete on leaderboards, and connect with the ham radio community.
            """
        ),
        TourPage(
            icon: "flag.2.crossed",
            title: "Challenges",
            body: """
            Browse and join challenges, then watch your progress as you make QSOs. \
            Compete with others on leaderboards and earn recognition for your achievements.
            """
        ),
        TourPage(
            icon: "person.badge.plus",
            title: "Friends & Clubs",
            body: """
            Add friends to see their activity, or join clubs to connect with groups. \
            Use the toolbar buttons to manage your connections. More social features coming soon!
            """
        ),
    ]

    static let statsDrilldown: [TourPage] = [
        TourPage(
            icon: "chart.bar.xaxis",
            title: "Explore Your Stats",
            body: """
            Tap any statistic to see the breakdown. Expand individual items to view \
            the QSOs that count toward that total.
            """
        ),
    ]

    static let lofiSetup: [TourPage] = [
        TourPage(
            icon: "icloud.and.arrow.down",
            title: "Ham2K LoFi",
            body: """
            LoFi syncs your logs from the Ham2K Portable Logger (PoLo) app. \
            It's download-only - Carrier Wave imports your PoLo operations.
            """
        ),
        TourPage(
            icon: "link.badge.plus",
            title: "Device Linking",
            body: """
            Enter the email address associated with your PoLo account. \
            You'll receive a verification code to link this device.
            """
        ),
    ]

    static func pages(for id: TourState.MiniTourID) -> [TourPage] {
        switch id {
        case .potaActivations: potaActivations
        case .potaAccountSetup: potaAccountSetup
        case .challenges: challenges
        case .statsDrilldown: statsDrilldown
        case .lofiSetup: lofiSetup
        }
    }
}
