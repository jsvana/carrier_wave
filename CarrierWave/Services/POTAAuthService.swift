// POTA WebView authentication module
//
// This module handles authentication with POTA using an in-app WebView
// to navigate the Cognito Hosted UI, then caches the resulting JWT tokens
// for subsequent direct API calls.

import Combine
import Foundation
import SwiftUI
import WebKit

// MARK: - POTAAuthError

enum POTAAuthError: Error, LocalizedError {
    case tokenExtractionFailed
    case authenticationCancelled
    case networkError(Error)
    case tokenExpired

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .tokenExtractionFailed:
            "Failed to extract authentication token from POTA"
        case .authenticationCancelled:
            "Authentication was cancelled"
        case let .networkError(error):
            "Network error: \(error.localizedDescription)"
        case .tokenExpired:
            "POTA token has expired, please re-authenticate"
        }
    }
}

// MARK: - POTAToken

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

// MARK: - POTAAuthService

@MainActor
class POTAAuthService: NSObject, ObservableObject {
    // MARK: Lifecycle

    override init() {
        super.init()
        loadStoredToken()
    }

    // MARK: Internal

    @Published var isAuthenticating = false
    @Published var currentToken: POTAToken?
    @Published private(set) var webView: WKWebView?

    /// Check if we have a valid (non-expired) POTA authentication token
    var isAuthenticated: Bool {
        guard let token = currentToken else {
            return false
        }
        return !token.isExpired
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

    func cancelAuthentication() {
        authContinuation?.resume(throwing: POTAAuthError.authenticationCancelled)
        authContinuation = nil
        webView = nil
    }

    func logout() {
        try? keychain.delete(for: KeychainHelper.Keys.potaIdToken)
        currentToken = nil
        webView = nil

        // Clear Cognito-related data from default data store to prevent session conflicts
        let dataStore = WKWebsiteDataStore.default()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        dataStore.fetchDataRecords(ofTypes: dataTypes) { records in
            let cognitoRecords = records.filter {
                $0.displayName.contains("pota") || $0.displayName.contains("cognito")
                    || $0.displayName.contains("amazoncognito")
            }
            if !cognitoRecords.isEmpty {
                dataStore.removeData(ofTypes: dataTypes, for: cognitoRecords) {}
            }
        }
    }

    func ensureValidToken() async throws -> String {
        if let token = currentToken, !token.isExpiringSoon() {
            return token.idToken
        }

        let newToken = try await authenticate()
        return newToken.idToken
    }

    // MARK: Private

    private let keychain = KeychainHelper.shared
    private var authContinuation: CheckedContinuation<POTAToken, Error>?

    private let potaAppURL = "https://pota.app"

    /// JavaScript to extract token from cookies/localStorage
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

    private func setupWebView() {
        // Create a fresh non-persistent data store and clear any residual data
        // This ensures each login attempt starts with a completely clean state
        let dataStore = WKWebsiteDataStore.nonPersistent()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()

        // Clear the non-persistent store before use to ensure no residual state
        dataStore.removeData(ofTypes: dataTypes, modifiedSince: .distantPast) { [weak self] in
            // Dispatch back to main actor since completion handler runs on background thread
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                let config = WKWebViewConfiguration()
                config.websiteDataStore = dataStore

                webView = WKWebView(frame: .zero, configuration: config)
                webView?.navigationDelegate = self

                guard let url = URL(string: "\(potaAppURL)/#/login") else {
                    authContinuation?.resume(throwing: POTAAuthError.tokenExtractionFailed)
                    return
                }

                webView?.load(URLRequest(url: url))
            }
        }
    }

    private func extractToken() async throws -> POTAToken {
        guard let webView else {
            throw POTAAuthError.tokenExtractionFailed
        }

        // Try multiple times with delay
        for _ in 0 ..< 5 {
            let result = try await webView.evaluateJavaScript(extractTokenJS)
            if let token = result as? String, !token.isEmpty {
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
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw POTAAuthError.tokenExtractionFailed
        }

        let exp = claims["exp"] as? TimeInterval ?? (Date().timeIntervalSince1970 + 3_600)
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
}

// MARK: WKNavigationDelegate

extension POTAAuthService: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            guard let url = webView.url?.absoluteString else {
                return
            }

            // Check if we've returned to POTA after Cognito auth
            if url.contains("pota.app"), !url.contains("cognito"), !url.contains("login") {
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
