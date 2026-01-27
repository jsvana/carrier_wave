import SwiftUI
import UIKit

// MARK: - ShakeDetector

/// A view modifier that detects device shake gestures
struct ShakeDetector: ViewModifier {
    let onShake: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
                onShake()
            }
    }
}

extension View {
    func onShake(perform action: @escaping () -> Void) -> some View {
        modifier(ShakeDetector(onShake: action))
    }
}

// MARK: - Notification.Name Extension

extension Notification.Name {
    static let deviceDidShake = Notification.Name("deviceDidShakeNotification")
}

// MARK: - ShakeDetectingWindow

/// Custom UIWindow subclass that detects shake gestures
/// Add this to your App's WindowGroup scene
class ShakeDetectingWindow: UIWindow {
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}
