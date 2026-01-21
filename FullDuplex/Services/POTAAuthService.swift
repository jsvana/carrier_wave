import Combine
import Foundation
import WebKit
import SwiftUI

enum POTAAuthError: Error, LocalizedError {
    case tokenExtractionFailed
    case authenticationCancelled
    case networkError(Error)
    case tokenExpired

    var errorDescription: String? {
        switch self {
        case .tokenExtractionFailed:
            return "Failed to extract authentication token from POTA"
        case .authenticationCancelled:
            return "Authentication was cancelled"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .tokenExpired:
            return "POTA token has expired, please re-authenticate"
        }
    }
}

struct POTAToken: Codable {
    let idToken: String
    let expiresAt: Date
    let callsign: String?

    var isExpired: Bool {
        Date() >= expiresAt
    }

    func isExpiringSoon(buffer: TimeInterval = 300) -> Bool {
        Date().addingTimeInterval(buffer) >= expiresAt
    }
}

@MainActor
class POTAAuthService: NSObject, ObservableObject {
    @Published var isAuthenticating = false
    @Published var currentToken: POTAToken?

    private let keychain = KeychainHelper.shared
    private var webView: WKWebView?
    private var authContinuation: CheckedContinuation<POTAToken, Error>?

    private let potaAppURL = "https://pota.app"

    // JavaScript to extract token from cookies/localStorage
    private let extractTokenJS = """
    (function() {
        // Check cookies first
        const cookies = document.cookie.split(';');
        for (const cookie of cookies) {
            const trimmed = cookie.trim();
            if (trimmed.includes('idToken=')) {
                const eqIdx = trimmed.indexOf('=');
                if (eqIdx > 0) {
                    const val = trimmed.substring(eqIdx + 1);
                    if (val && val.startsWith('eyJ')) {
                        return val;
                    }
                }
            }
        }

        // Try localStorage
        for (let i = 0; i < localStorage.length; i++) {
            const key = localStorage.key(i);
            if (key && key.includes('idToken')) {
                const val = localStorage.getItem(key);
                if (val && val.startsWith('eyJ')) {
                    return val;
                }
            }
        }

        // Check sessionStorage
        for (let i = 0; i < sessionStorage.length; i++) {
            const key = sessionStorage.key(i);
            if (key && key.includes('idToken')) {
                const val = sessionStorage.getItem(key);
                if (val && val.startsWith('eyJ')) {
                    return val;
                }
            }
        }

        // Try Amplify auth data
        for (let i = 0; i < localStorage.length; i++) {
            const key = localStorage.key(i);
            if (key && (key.includes('amplify') || key.includes('Cognito') || key.includes('auth'))) {
                try {
                    const val = localStorage.getItem(key);
                    const parsed = JSON.parse(val);
                    if (parsed && parsed.idToken) {
                        return parsed.idToken;
                    }
                    if (parsed && parsed.signInUserSession && parsed.signInUserSession.idToken) {
                        return parsed.signInUserSession.idToken.jwtToken;
                    }
                } catch (e) {}
            }
        }

        return null;
    })()
    """

    override init() {
        super.init()
        loadStoredToken()
    }

    func loadStoredToken() {
        do {
            let tokenData = try keychain.read(for: KeychainHelper.Keys.potaIdToken)
            let token = try JSONDecoder().decode(POTAToken.self, from: tokenData)
            if !token.isExpired {
                currentToken = token
            }
        } catch {
            // No stored token or expired
            currentToken = nil
        }
    }

    func authenticate() async throws -> POTAToken {
        // Check if we have a valid token
        if let token = currentToken, !token.isExpiringSoon() {
            return token
        }

        isAuthenticating = true
        defer { isAuthenticating = false }

        return try await withCheckedThrowingContinuation { continuation in
            self.authContinuation = continuation
            self.setupWebView()
        }
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent() // Don't persist between sessions

        webView = WKWebView(frame: .zero, configuration: config)
        webView?.navigationDelegate = self

        guard let url = URL(string: "\(potaAppURL)/#/login") else {
            authContinuation?.resume(throwing: POTAAuthError.tokenExtractionFailed)
            return
        }

        webView?.load(URLRequest(url: url))
    }

    func getWebView() -> WKWebView? {
        return webView
    }

    func cancelAuthentication() {
        authContinuation?.resume(throwing: POTAAuthError.authenticationCancelled)
        authContinuation = nil
        webView = nil
    }

    private func extractToken() async throws -> POTAToken {
        guard let webView = webView else {
            throw POTAAuthError.tokenExtractionFailed
        }

        // Try multiple times with delay
        for _ in 0..<5 {
            if let token = try await webView.evaluateJavaScript(extractTokenJS) as? String,
               !token.isEmpty {
                let potaToken = try decodeToken(token)
                try saveToken(potaToken)
                currentToken = potaToken
                return potaToken
            }
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        }

        throw POTAAuthError.tokenExtractionFailed
    }

    private func decodeToken(_ jwt: String) throws -> POTAToken {
        let parts = jwt.components(separatedBy: ".")
        guard parts.count >= 2 else {
            throw POTAAuthError.tokenExtractionFailed
        }

        var base64 = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Add padding if needed
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: base64),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw POTAAuthError.tokenExtractionFailed
        }

        let exp = claims["exp"] as? TimeInterval ?? (Date().timeIntervalSince1970 + 3600)
        let callsign = claims["pota:callsign"] as? String

        return POTAToken(
            idToken: jwt,
            expiresAt: Date(timeIntervalSince1970: exp),
            callsign: callsign
        )
    }

    private func saveToken(_ token: POTAToken) throws {
        let data = try JSONEncoder().encode(token)
        try keychain.save(data, for: KeychainHelper.Keys.potaIdToken)
    }

    func logout() {
        try? keychain.delete(for: KeychainHelper.Keys.potaIdToken)
        currentToken = nil
        webView = nil
    }

    func ensureValidToken() async throws -> String {
        if let token = currentToken, !token.isExpiringSoon() {
            return token.idToken
        }

        let newToken = try await authenticate()
        return newToken.idToken
    }
}

extension POTAAuthService: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            guard let url = webView.url?.absoluteString else { return }

            // Check if we've returned to POTA after Cognito auth
            if url.contains("pota.app") && !url.contains("cognito") && !url.contains("login") {
                do {
                    let token = try await extractToken()
                    authContinuation?.resume(returning: token)
                    authContinuation = nil
                    self.webView = nil
                } catch {
                    // Keep waiting, user might not be fully logged in yet
                }
            }
        }
    }
}
