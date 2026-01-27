import Foundation
import MessageUI
import UIKit

// MARK: - BugCategory

enum BugCategory: String, CaseIterable {
    case syncIssue = "Sync Issue"
    case uiProblem = "UI Problem"
    case crash = "Crash"
    case other = "Other"
}

// MARK: - BugReportService

@MainActor
final class BugReportService {
    // MARK: Lifecycle

    init(
        qrzClient: QRZClient? = nil,
        lofiClient: LoFiClient? = nil,
        lotwClient: LoTWClient? = nil,
        hamrsClient: HAMRSClient? = nil,
        potaAuth: POTAAuthService? = nil,
        iCloudMonitor: ICloudMonitor? = nil
    ) {
        self.qrzClient = qrzClient
        self.lofiClient = lofiClient
        self.lotwClient = lotwClient
        self.hamrsClient = hamrsClient
        self.potaAuth = potaAuth
        self.iCloudMonitor = iCloudMonitor
    }

    // MARK: Internal

    // MARK: - Device Info

    struct DeviceInfo {
        let appVersion: String
        let buildNumber: String
        let iosVersion: String
        let deviceModel: String
        let debugMode: Bool
    }

    // MARK: - Service Status

    struct ServiceStatus {
        let qrzConfigured: Bool
        let potaConfigured: Bool
        let lofiConfigured: Bool
        let lotwConfigured: Bool
        let hamrsConfigured: Bool
        let iCloudStatus: String
    }

    static let recipientEmail = "jaysvana@gmail.com"

    static func canSendMail() -> Bool {
        MFMailComposeViewController.canSendMail()
    }

    func collectDeviceInfo(debugMode: Bool) -> DeviceInfo {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        let iosVersion = UIDevice.current.systemVersion
        let deviceModel = deviceModelName()

        return DeviceInfo(
            appVersion: appVersion,
            buildNumber: buildNumber,
            iosVersion: iosVersion,
            deviceModel: deviceModel,
            debugMode: debugMode
        )
    }

    func collectServiceStatus() -> ServiceStatus {
        let qrzConfigured = qrzClient?.hasApiKey() ?? false
        let potaConfigured = potaAuth?.isAuthenticated ?? false
        let lofiConfigured = lofiClient?.hasCredentials() ?? false
        let lotwConfigured = lotwClient?.hasCredentials() ?? false
        let hamrsConfigured = hamrsClient?.hasApiKey() ?? false
        let iCloudStatus = iCloudMonitor?.statusDescription ?? "Unknown"

        return ServiceStatus(
            qrzConfigured: qrzConfigured,
            potaConfigured: potaConfigured,
            lofiConfigured: lofiConfigured,
            lotwConfigured: lotwConfigured,
            hamrsConfigured: hamrsConfigured,
            iCloudStatus: iCloudStatus
        )
    }

    func collectSyncLogs() -> String {
        let entries = Array(SyncDebugLog.shared.logEntries.prefix(50))
        guard !entries.isEmpty else {
            return "No sync logs available"
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        return entries.map { entry in
            let timestamp = dateFormatter.string(from: entry.timestamp)
            let service = entry.service?.displayName ?? "General"
            return "[\(timestamp)] [\(entry.level.rawValue)] [\(service)] \(entry.message)"
        }.joined(separator: "\n")
    }

    func formatReport(
        category: BugCategory,
        description: String,
        deviceInfo: DeviceInfo,
        serviceStatus: ServiceStatus,
        syncLogs: String
    ) -> String {
        """
        BUG REPORT
        ==========

        Category: \(category.rawValue)

        Description:
        \(description)

        DEVICE INFO
        -----------
        App Version: \(deviceInfo.appVersion)
        Build Number: \(deviceInfo.buildNumber)
        iOS Version: \(deviceInfo.iosVersion)
        Device: \(deviceInfo.deviceModel)
        Debug Mode: \(deviceInfo.debugMode ? "Enabled" : "Disabled")

        SERVICE STATUS
        --------------
        QRZ: \(serviceStatus.qrzConfigured ? "Configured" : "Not configured")
        POTA: \(serviceStatus.potaConfigured ? "Configured" : "Not configured")
        LoFi: \(serviceStatus.lofiConfigured ? "Configured" : "Not configured")
        LoTW: \(serviceStatus.lotwConfigured ? "Configured" : "Not configured")
        HAMRS: \(serviceStatus.hamrsConfigured ? "Configured" : "Not configured")
        iCloud: \(serviceStatus.iCloudStatus)

        RECENT SYNC LOGS
        ----------------
        \(syncLogs)
        """
    }

    func emailSubject(category: BugCategory, version: String) -> String {
        "[Carrier Wave Bug] \(category.rawValue) - v\(version)"
    }

    // MARK: Private

    private let qrzClient: QRZClient?
    private let lofiClient: LoFiClient?
    private let lotwClient: LoTWClient?
    private let hamrsClient: HAMRSClient?
    private let potaAuth: POTAAuthService?
    private let iCloudMonitor: ICloudMonitor?

    private func deviceModelName() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let identifier = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "Unknown"
            }
        }
        return mapDeviceIdentifier(identifier)
    }

    private func mapDeviceIdentifier(_ identifier: String) -> String {
        // Common iPhone mappings
        let mappings: [String: String] = [
            // iPhone 15 series
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone15,4": "iPhone 15",
            "iPhone15,5": "iPhone 15 Plus",
            // iPhone 14 series
            "iPhone15,2": "iPhone 14 Pro",
            "iPhone15,3": "iPhone 14 Pro Max",
            "iPhone14,7": "iPhone 14",
            "iPhone14,8": "iPhone 14 Plus",
            // iPhone 13 series
            "iPhone14,2": "iPhone 13 Pro",
            "iPhone14,3": "iPhone 13 Pro Max",
            "iPhone14,4": "iPhone 13 mini",
            "iPhone14,5": "iPhone 13",
            // iPhone 12 series
            "iPhone13,1": "iPhone 12 mini",
            "iPhone13,2": "iPhone 12",
            "iPhone13,3": "iPhone 12 Pro",
            "iPhone13,4": "iPhone 12 Pro Max",
            // iPhone 11 series
            "iPhone12,1": "iPhone 11",
            "iPhone12,3": "iPhone 11 Pro",
            "iPhone12,5": "iPhone 11 Pro Max",
            // iPhone SE
            "iPhone14,6": "iPhone SE (3rd generation)",
            "iPhone12,8": "iPhone SE (2nd generation)",
            // iPad Pro
            "iPad13,4": "iPad Pro 11-inch (3rd generation)",
            "iPad13,5": "iPad Pro 11-inch (3rd generation)",
            "iPad13,6": "iPad Pro 11-inch (3rd generation)",
            "iPad13,7": "iPad Pro 11-inch (3rd generation)",
            "iPad13,8": "iPad Pro 12.9-inch (5th generation)",
            "iPad13,9": "iPad Pro 12.9-inch (5th generation)",
            "iPad13,10": "iPad Pro 12.9-inch (5th generation)",
            "iPad13,11": "iPad Pro 12.9-inch (5th generation)",
            // Simulator
            "x86_64": "Simulator",
            "arm64": "Simulator",
        ]

        return mappings[identifier] ?? identifier
    }
}
