// POTA WebView authentication module
//
// This module handles authentication with POTA using an in-app WebView
// to navigate the Cognito Hosted UI, then caches the resulting JWT tokens
// for subsequent direct API calls.

import Combine
import Foundation
import SwiftUI
import WebKit

// MARK: - String+JSEscape

extension String {
    /// Escapes special characters for safe embedding in JavaScript string literals
    var escapedForJS: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}

// MARK: - POTAAuthError

enum POTAAuthError: Error, LocalizedError {
    case tokenExtractionFailed
    case authenticationCancelled
    case networkError(Error)
    case tokenExpired
    case noStoredCredentials
    case cognitoRedirectTimeout
    case potaRedirectTimeout
    case formFieldsNotFound
    case loginFailed(String)

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
        case .noStoredCredentials:
            "No stored credentials found. Please enter your POTA login credentials in Settings."
        case .cognitoRedirectTimeout:
            "Timed out waiting for login page to load."
        case .potaRedirectTimeout:
            "Login may have failed. Please check your credentials."
        case .formFieldsNotFound:
            "Could not find login form fields. The login page may have changed."
        case let .loginFailed(message):
            "Login failed: \(message)"
        }
    }
}

// MARK: - POTAToken

struct POTAToken: Codable, @unchecked Sendable {
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

    static let potaAppURL = "https://pota.app"

    @Published var isAuthenticating = false
    @Published var currentToken: POTAToken?
    @Published private(set) var webView: WKWebView?

    var authContinuation: CheckedContinuation<POTAToken, Error>?

    /// Public accessor for the POTA app URL
    var potaAppURLString: String { Self.potaAppURL }

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
        // Clear token
        try? keychain.delete(for: KeychainHelper.Keys.potaIdToken)
        // Clear stored credentials
        try? keychain.delete(for: KeychainHelper.Keys.potaUsername)
        try? keychain.delete(for: KeychainHelper.Keys.potaPassword)

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

        // Try headless refresh if credentials are stored
        if hasStoredCredentials() {
            do {
                let newToken = try await authenticateWithStoredCredentials()
                return newToken.idToken
            } catch {
                // Fall through to manual authentication
            }
        }

        let newToken = try await authenticate()
        return newToken.idToken
    }

    // MARK: - Headless Authentication

    /// Check if stored credentials are available
    func hasStoredCredentials() -> Bool {
        (try? keychain.readString(for: KeychainHelper.Keys.potaUsername)) != nil
            && (try? keychain.readString(for: KeychainHelper.Keys.potaPassword)) != nil
    }

    /// Authenticates using stored credentials without user interaction
    func authenticateWithStoredCredentials() async throws -> POTAToken {
        guard let username = try? keychain.readString(for: KeychainHelper.Keys.potaUsername),
              let password = try? keychain.readString(for: KeychainHelper.Keys.potaPassword)
        else {
            throw POTAAuthError.noStoredCredentials
        }

        return try await performHeadlessLogin(username: username, password: password)
    }

    // MARK: - Token Management

    func decodeAndSaveToken(_ jwt: String) throws -> POTAToken {
        let token = try decodeToken(jwt)
        try saveToken(token)
        currentToken = token
        return token
    }

    func extractToken() async throws -> POTAToken {
        guard let webView else {
            throw POTAAuthError.tokenExtractionFailed
        }

        // Try multiple times with delay
        for _ in 0 ..< 5 {
            let result = try await webView.evaluateJavaScript(POTAAuthJavaScript.extractToken)
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

    // MARK: Private

    private let keychain = KeychainHelper.shared

    private func setupWebView() {
        // Create a fresh non-persistent data store and clear any residual data
        let dataStore = WKWebsiteDataStore.nonPersistent()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()

        // Clear the non-persistent store before use to ensure no residual state
        dataStore.removeData(ofTypes: dataTypes, modifiedSince: .distantPast) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                let config = WKWebViewConfiguration()
                config.websiteDataStore = dataStore

                webView = WKWebView(frame: .zero, configuration: config)
                webView?.navigationDelegate = self

                guard let url = URL(string: "\(Self.potaAppURL)/#/login") else {
                    authContinuation?.resume(throwing: POTAAuthError.tokenExtractionFailed)
                    return
                }

                webView?.load(URLRequest(url: url))
            }
        }
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

        let callsign = claims["pota:callsign"] as? String

        // Use 50 minutes from now as expiry (POTA tokens expire after ~1 hour,
        // but we use 50 minutes to ensure we refresh before actual expiry)
        let expiresAt = Date().addingTimeInterval(50 * 60)

        return POTAToken(
            idToken: jwt,
            expiresAt: expiresAt,
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
