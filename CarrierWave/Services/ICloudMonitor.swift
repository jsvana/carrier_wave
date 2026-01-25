import Combine
import Foundation
import UserNotifications

@MainActor
class ICloudMonitor: ObservableObject {
    // MARK: Lifecycle

    init() {
        setupNotifications()
    }

    // MARK: Internal

    @Published var pendingFiles: [URL] = []
    @Published var isMonitoring = false

    var iCloudContainerURL: URL? {
        fileManager.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents")
            .appendingPathComponent("Import")
    }

    func startMonitoring() {
        guard !isMonitoring else {
            return
        }
        guard iCloudContainerURL != nil else {
            print("iCloud not available")
            return
        }

        metadataQuery = NSMetadataQuery()
        metadataQuery?.predicate = NSPredicate(format: "%K LIKE[c] '*.adi' OR %K LIKE[c] '*.adif'",
                                               NSMetadataItemFSNameKey, NSMetadataItemFSNameKey)
        metadataQuery?.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryDidUpdate),
            name: .NSMetadataQueryDidUpdate,
            object: metadataQuery
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryDidFinishGathering),
            name: .NSMetadataQueryDidFinishGathering,
            object: metadataQuery
        )

        metadataQuery?.start()
        isMonitoring = true
    }

    func stopMonitoring() {
        metadataQuery?.stop()
        metadataQuery = nil
        isMonitoring = false
    }

    func markFileAsProcessed(_ url: URL) {
        pendingFiles.removeAll { $0 == url }

        // Optionally move to Processed folder
        guard let containerURL = iCloudContainerURL else {
            return
        }
        let processedURL = containerURL
            .deletingLastPathComponent()
            .appendingPathComponent("Processed")

        try? fileManager.createDirectory(at: processedURL, withIntermediateDirectories: true)

        let destination = processedURL.appendingPathComponent(url.lastPathComponent)
        try? fileManager.moveItem(at: url, to: destination)
    }

    func createImportFolderIfNeeded() {
        guard let url = iCloudContainerURL else {
            return
        }
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    // MARK: Private

    private var metadataQuery: NSMetadataQuery?
    private let fileManager = FileManager.default

    private func setupNotifications() {
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()

            if settings.authorizationStatus == .notDetermined {
                try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
        }
    }

    @objc private func queryDidFinishGathering(_ notification: Notification) {
        processQueryResults()
    }

    @objc private func queryDidUpdate(_ notification: Notification) {
        processQueryResults()
    }

    private func processQueryResults() {
        guard let query = metadataQuery else {
            return
        }

        query.disableUpdates()
        defer { query.enableUpdates() }

        var newFiles: [URL] = []

        for item in query.results {
            guard let metadataItem = item as? NSMetadataItem,
                  let url = metadataItem.value(forAttribute: NSMetadataItemURLKey) as? URL
            else {
                continue
            }

            // Check if file is downloaded
            let downloadStatus = metadataItem
                .value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String

            if downloadStatus == NSMetadataUbiquitousItemDownloadingStatusCurrent {
                // File is downloaded and ready
                if !pendingFiles.contains(url) {
                    newFiles.append(url)
                }
            } else if downloadStatus == NSMetadataUbiquitousItemDownloadingStatusNotDownloaded {
                // Trigger download
                try? fileManager.startDownloadingUbiquitousItem(at: url)
            }
        }

        if !newFiles.isEmpty {
            pendingFiles.append(contentsOf: newFiles)
            scheduleNotification(for: newFiles)
        }
    }

    private func scheduleNotification(for files: [URL]) {
        let content = UNMutableNotificationContent()

        if files.count == 1 {
            content.title = "New Log File"
            content.body = "Tap to import: \(files[0].lastPathComponent)"
        } else {
            content.title = "New Log Files"
            content.body = "\(files.count) ADIF files ready to import"
        }

        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request)
    }
}
