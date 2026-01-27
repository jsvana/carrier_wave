import SwiftUI
import UIKit

// MARK: - Notification.Name Extension

extension Notification.Name {
    static let deviceDidShake = Notification.Name("deviceDidShakeNotification")
}

// MARK: - ShakeDetector

/// Sets up shake detection at the application level by swizzling UIWindow
enum ShakeDetector {
    // MARK: Internal

    static func setUp() {
        guard !isSetUp else {
            return
        }
        isSetUp = true

        // Swizzle UIWindow's motionEnded to detect shake gestures
        let originalSelector = #selector(UIWindow.motionEnded(_:with:))
        let swizzledSelector = #selector(UIWindow.swizzled_motionEnded(_:with:))

        guard let originalMethod = class_getInstanceMethod(UIWindow.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(UIWindow.self, swizzledSelector)
        else {
            return
        }

        method_exchangeImplementations(originalMethod, swizzledMethod)
    }

    // MARK: Private

    private static var isSetUp = false
}

// MARK: - UIWindow Swizzle

extension UIWindow {
    @objc func swizzled_motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        // Call original implementation
        swizzled_motionEnded(motion, with: event)

        // Post notification on shake
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
    }
}

// MARK: - View Extension

extension View {
    /// Adds shake gesture detection to this view
    func onShake(perform action: @escaping () -> Void) -> some View {
        onAppear {
            ShakeDetector.setUp()
        }
        .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
            action()
        }
    }
}
