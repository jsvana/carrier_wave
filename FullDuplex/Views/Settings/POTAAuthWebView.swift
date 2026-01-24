// POTA authentication WebView UI components
//
// SwiftUI wrapper for WKWebView used in POTA Cognito login flow.

import SwiftUI
import WebKit

// MARK: - POTAAuthWebView

struct POTAAuthWebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // No updates needed
    }
}

// MARK: - POTALoginSheet

struct POTALoginSheet: View {
    // MARK: Internal

    @ObservedObject var authService: POTAAuthService

    var body: some View {
        NavigationStack {
            Group {
                if let webView = authService.getWebView() {
                    POTAAuthWebView(webView: webView)
                } else {
                    ProgressView("Loading...")
                }
            }
            .navigationTitle("POTA Login")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        authService.cancelAuthentication()
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
}
