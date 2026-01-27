import SwiftUI
import UIKit

// MARK: - Notification.Name Extension

extension Notification.Name {
    static let deviceDidShake = Notification.Name("deviceDidShakeNotification")
}

// MARK: - ShakeDetectingViewController

/// A view controller that detects shake gestures and posts a notification
final class ShakeDetectingViewController: UIViewController {
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}

// MARK: - ShakeDetectingView

/// A SwiftUI view that wraps a shake-detecting view controller
struct ShakeDetectingView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ShakeDetectingViewController {
        ShakeDetectingViewController()
    }

    func updateUIViewController(_ uiViewController: ShakeDetectingViewController, context: Context) {}
}

// MARK: - View Extension

extension View {
    /// Adds shake gesture detection to this view
    func onShake(perform action: @escaping () -> Void) -> some View {
        background(ShakeDetectingView())
            .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
                action()
            }
    }
}
