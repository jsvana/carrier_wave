import MessageUI
import SwiftUI

struct MailComposeView: UIViewControllerRepresentable {
    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        // MARK: Lifecycle

        init(onDismiss: @escaping (MFMailComposeResult) -> Void) {
            self.onDismiss = onDismiss
        }

        // MARK: Internal

        let onDismiss: (MFMailComposeResult) -> Void

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            controller.dismiss(animated: true) {
                self.onDismiss(result)
            }
        }
    }

    let recipients: [String]
    let subject: String
    let body: String
    let attachmentData: Data?
    let attachmentMimeType: String?
    let attachmentFileName: String?
    var onDismiss: (MFMailComposeResult) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = context.coordinator
        composer.setToRecipients(recipients)
        composer.setSubject(subject)
        composer.setMessageBody(body, isHTML: false)

        if let data = attachmentData,
           let mimeType = attachmentMimeType,
           let fileName = attachmentFileName
        {
            composer.addAttachmentData(data, mimeType: mimeType, fileName: fileName)
        }

        return composer
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }
}
