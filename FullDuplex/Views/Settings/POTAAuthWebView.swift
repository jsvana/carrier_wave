// POTA authentication WebView UI components
//
// SwiftUI wrapper for WKWebView used in POTA Cognito login flow.

import SwiftUI
import WebKit

struct POTAAuthWebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // No updates needed
    }
}

struct POTALoginSheet: View {
    @ObservedObject var authService: POTAAuthService
    @Environment(\.dismiss) private var dismiss

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
}
