import MessageUI
import PhotosUI
import SwiftUI
import UIKit

struct BugReportView: View {
    // MARK: Lifecycle

    init(potaAuth: POTAAuthService, iCloudMonitor: ICloudMonitor) {
        self.potaAuth = potaAuth
        self.iCloudMonitor = iCloudMonitor
    }

    // MARK: Internal

    var body: some View {
        NavigationStack {
            Form {
                categorySection
                descriptionSection
                screenshotSection
                infoSection
                if debugMode {
                    logsSection
                }
            }
            .navigationTitle("Report a Bug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { sendReport() }
                        .disabled(isSending)
                }
            }
            .sheet(isPresented: $showingMailComposer) {
                MailComposeView(
                    recipients: [BugReportService.recipientEmail],
                    subject: emailSubject,
                    body: emailBody,
                    attachmentData: screenshotData,
                    attachmentMimeType: screenshotData != nil ? "image/jpeg" : nil,
                    attachmentFileName: screenshotData != nil ? "screenshot.jpg" : nil,
                    onDismiss: handleMailResult
                )
            }
            .alert("Report Copied", isPresented: $showingCopiedAlert) {
                Button("OK") { dismiss() }
            } message: {
                Text("Report copied to clipboard. Please email it to \(BugReportService.recipientEmail)")
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss

    @AppStorage("debugMode") private var debugMode = false

    @State private var selectedCategory: BugCategory = .other
    @State private var descriptionText = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var screenshotData: Data?
    @State private var screenshotImage: UIImage?
    @State private var showingMailComposer = false
    @State private var showingCopiedAlert = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isSending = false
    @State private var showingLogs = false

    private let potaAuth: POTAAuthService
    private let iCloudMonitor: ICloudMonitor

    private var service: BugReportService {
        BugReportService(potaAuth: potaAuth, iCloudMonitor: iCloudMonitor)
    }

    private var deviceInfo: BugReportService.DeviceInfo {
        service.collectDeviceInfo(debugMode: debugMode)
    }

    private var serviceStatus: BugReportService.ServiceStatus {
        service.collectServiceStatus()
    }

    private var syncLogs: String {
        service.collectSyncLogs()
    }

    private var emailSubject: String {
        service.emailSubject(category: selectedCategory, version: deviceInfo.appVersion)
    }

    private var emailBody: String {
        service.formatReport(
            category: selectedCategory,
            description: descriptionText,
            deviceInfo: deviceInfo,
            serviceStatus: serviceStatus,
            syncLogs: syncLogs
        )
    }

    private var categorySection: some View {
        Section {
            Picker("Category", selection: $selectedCategory) {
                ForEach(BugCategory.allCases, id: \.self) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var descriptionSection: some View {
        Section {
            TextField("Describe what happened...", text: $descriptionText, axis: .vertical)
                .lineLimit(5 ... 10)
        } header: {
            Text("Description")
        }
    }

    private var screenshotSection: some View {
        Section {
            if let image = screenshotImage {
                HStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 100)
                        .cornerRadius(8)

                    Spacer()

                    Button(role: .destructive) {
                        screenshotData = nil
                        screenshotImage = nil
                        selectedPhoto = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Attach Screenshot", systemImage: "photo")
                }
            }
        } header: {
            Text("Screenshot (Optional)")
        }
        .onChange(of: selectedPhoto) { _, newValue in
            Task {
                if let data = try? await newValue?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data)
                {
                    screenshotImage = image
                    screenshotData = image.jpegData(compressionQuality: 0.7)
                }
            }
        }
    }

    private var infoSection: some View {
        Section {
            DisclosureGroup("Report includes...") {
                LabeledContent("Version", value: "\(deviceInfo.appVersion) (\(deviceInfo.buildNumber))")
                LabeledContent("iOS", value: deviceInfo.iosVersion)
                LabeledContent("Device", value: deviceInfo.deviceModel)
                LabeledContent("QRZ", value: serviceStatus.qrzConfigured ? "Configured" : "Not configured")
                LabeledContent("POTA", value: serviceStatus.potaConfigured ? "Configured" : "Not configured")
                LabeledContent("LoFi", value: serviceStatus.lofiConfigured ? "Configured" : "Not configured")
                LabeledContent("LoTW", value: serviceStatus.lotwConfigured ? "Configured" : "Not configured")
                LabeledContent("HAMRS", value: serviceStatus.hamrsConfigured ? "Configured" : "Not configured")
                LabeledContent("iCloud", value: serviceStatus.iCloudStatus)
            }
        } footer: {
            Text("Report includes recent sync activity which may contain callsigns.")
        }
    }

    private var logsSection: some View {
        Section {
            DisclosureGroup("Sync Debug Logs", isExpanded: $showingLogs) {
                Text(syncLogs)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sendReport() {
        isSending = true
        defer { isSending = false }

        // If we have a screenshot, prefer MFMailComposeViewController (supports attachments)
        // Otherwise prefer mailto: (works with Gmail, Outlook, etc.)
        if screenshotData != nil, BugReportService.canSendMail() {
            showingMailComposer = true
            return
        }

        // Try mailto: URL (works with any mail app, but no attachment support)
        if let mailtoURL = createMailtoURL(), UIApplication.shared.canOpenURL(mailtoURL) {
            UIApplication.shared.open(mailtoURL)
            dismiss()
            return
        }

        // Fallback to MFMailComposeViewController even without screenshot
        if BugReportService.canSendMail() {
            showingMailComposer = true
            return
        }

        // Last resort: copy to clipboard
        UIPasteboard.general.string = emailBody
        showingCopiedAlert = true
    }

    private func createMailtoURL() -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = BugReportService.recipientEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: emailSubject),
            URLQueryItem(name: "body", value: emailBody),
        ]
        return components.url
    }

    private func handleMailResult(_ result: MFMailComposeResult) {
        showingMailComposer = false
        switch result {
        case .sent:
            dismiss()
        case .failed:
            // Try clipboard fallback on failure
            UIPasteboard.general.string = emailBody
            showingCopiedAlert = true
        case .cancelled,
             .saved:
            break
        @unknown default:
            break
        }
    }
}
