import Foundation

enum LoFiError: Error, LocalizedError {
    case notConfigured
    case notLinked
    case registrationFailed(String)
    case authenticationRequired
    case networkError(Error)
    case invalidResponse(String)
    case apiError(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "LoFi is not configured. Please set up your callsign."
        case .notLinked:
            return "Device not linked. Please check your email to confirm."
        case .registrationFailed(let msg):
            return "Registration failed: \(msg)"
        case .authenticationRequired:
            return "Authentication required. Please re-register."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse(let msg):
            return "Invalid response: \(msg)"
        case .apiError(let code, let msg):
            return "API error (\(code)): \(msg)"
        }
    }
}

actor LoFiClient {
    private let baseURL = "https://lofi.ham2k.net"
    private let clientName = "FullDuplex"
    private let appName = "FullDuplex"
    private let keychain = KeychainHelper.shared

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Configuration

    nonisolated var isConfigured: Bool {
        (try? keychain.readString(for: KeychainHelper.Keys.lofiClientKey)) != nil &&
        (try? keychain.readString(for: KeychainHelper.Keys.lofiCallsign)) != nil
    }

    nonisolated var isLinked: Bool {
        (try? keychain.readString(for: KeychainHelper.Keys.lofiDeviceLinked)) == "true"
    }

    nonisolated var hasToken: Bool {
        (try? keychain.readString(for: KeychainHelper.Keys.lofiAuthToken)) != nil
    }

    nonisolated func getCallsign() -> String? {
        try? keychain.readString(for: KeychainHelper.Keys.lofiCallsign)
    }

    nonisolated func getEmail() -> String? {
        try? keychain.readString(for: KeychainHelper.Keys.lofiEmail)
    }

    nonisolated func getLastSyncMillis() -> Int64 {
        guard let str = try? keychain.readString(for: KeychainHelper.Keys.lofiLastSyncMillis),
              let value = Int64(str) else {
            return 0
        }
        return value
    }

    // MARK: - Setup

    /// Configure LoFi with callsign and optional email
    /// Generates client key and secret automatically
    func configure(callsign: String, email: String?) throws {
        let clientKey = UUID().uuidString
        let clientSecret = generateClientSecret()

        try keychain.save(clientKey, for: KeychainHelper.Keys.lofiClientKey)
        try keychain.save(clientSecret, for: KeychainHelper.Keys.lofiClientSecret)
        try keychain.save(callsign.uppercased(), for: KeychainHelper.Keys.lofiCallsign)
        if let email = email {
            try keychain.save(email, for: KeychainHelper.Keys.lofiEmail)
        }
        try keychain.save("false", for: KeychainHelper.Keys.lofiDeviceLinked)
    }

    /// Register with LoFi and get bearer token
    func register() async throws -> LoFiRegistrationResponse {
        guard let clientKey = try? keychain.readString(for: KeychainHelper.Keys.lofiClientKey),
              let clientSecret = try? keychain.readString(for: KeychainHelper.Keys.lofiClientSecret),
              let callsign = try? keychain.readString(for: KeychainHelper.Keys.lofiCallsign) else {
            throw LoFiError.notConfigured
        }

        let request = LoFiRegistrationRequest(
            client: LoFiClientCredentials(key: clientKey, name: clientName, secret: clientSecret),
            account: LoFiAccountRequest(call: callsign),
            meta: LoFiMetaRequest(app: appName)
        )

        var urlRequest = URLRequest(url: URL(string: "\(baseURL)/v1/client")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LoFiError.invalidResponse("Not an HTTP response")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LoFiError.registrationFailed("\(httpResponse.statusCode) - \(body)")
        }

        let registration = try JSONDecoder().decode(LoFiRegistrationResponse.self, from: data)

        // Save the token
        try keychain.save(registration.token, for: KeychainHelper.Keys.lofiAuthToken)

        return registration
    }

    /// Link device via email confirmation
    func linkDevice(email: String) async throws {
        let token = try getToken()

        let request = LoFiLinkDeviceRequest(email: email)

        var urlRequest = URLRequest(url: URL(string: "\(baseURL)/v1/client/link")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LoFiError.invalidResponse("Not an HTTP response")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LoFiError.apiError(httpResponse.statusCode, body)
        }

        // Save the email for future reference
        try keychain.save(email, for: KeychainHelper.Keys.lofiEmail)
    }

    /// Mark device as linked (call after user confirms email)
    func markAsLinked() throws {
        try keychain.save("true", for: KeychainHelper.Keys.lofiDeviceLinked)
    }

    /// Refresh the bearer token
    func refreshToken() async throws -> String {
        let registration = try await register()
        return registration.token
    }

    // MARK: - Fetch Operations

    /// Fetch operations with pagination
    func fetchOperations(
        syncedSinceMillis: Int64 = 0,
        limit: Int = 50
    ) async throws -> LoFiOperationsResponse {
        let token = try getToken()

        var components = URLComponents(string: "\(baseURL)/v1/operations")!
        components.queryItems = [
            URLQueryItem(name: "synced_since_millis", value: String(syncedSinceMillis)),
            URLQueryItem(name: "other_clients_only", value: "true"),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return try await performRequest(urlRequest)
    }

    /// Fetch QSOs for a specific operation
    func fetchOperationQsos(
        operationUUID: String,
        syncedSinceMillis: Int64 = 0,
        limit: Int = 50
    ) async throws -> LoFiQsosResponse {
        let token = try getToken()

        var components = URLComponents(string: "\(baseURL)/v1/operations/\(operationUUID)/qsos")!
        components.queryItems = [
            URLQueryItem(name: "synced_since_millis", value: String(syncedSinceMillis)),
            URLQueryItem(name: "other_clients_only", value: "true"),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return try await performRequest(urlRequest)
    }

    /// Fetch all QSOs from all operations since last sync
    func fetchAllQsosSinceLastSync() async throws -> [(LoFiQso, LoFiOperation)] {
        var allQsos: [(LoFiQso, LoFiOperation)] = []
        let lastSyncMillis = getLastSyncMillis()
        var maxSyncMillis: Int64 = lastSyncMillis

        // First, fetch all operations
        var operations: [LoFiOperation] = []
        var syncedSince: Int64 = 0

        while true {
            let response = try await fetchOperations(syncedSinceMillis: syncedSince, limit: 50)
            operations.append(contentsOf: response.operations)

            if response.meta.operations.recordsLeft == 0 {
                break
            }

            // Use next_synced_at_millis for pagination
            if let next = response.meta.operations.nextSyncedAtMillis {
                syncedSince = Int64(next)
            } else {
                break
            }
        }

        // Now fetch QSOs for each operation
        for operation in operations {
            var qsoSyncedSince: Int64 = lastSyncMillis

            while true {
                let qsosResponse = try await fetchOperationQsos(
                    operationUUID: operation.uuid,
                    syncedSinceMillis: qsoSyncedSince,
                    limit: 50
                )

                for qso in qsosResponse.qsos {
                    allQsos.append((qso, operation))
                    if let syncedAt = qso.syncedAtMillis {
                        maxSyncMillis = max(maxSyncMillis, Int64(syncedAt))
                    }
                }

                if qsosResponse.meta.qsos.recordsLeft == 0 {
                    break
                }

                if let next = qsosResponse.meta.qsos.nextSyncedAtMillis {
                    qsoSyncedSince = Int64(next)
                } else {
                    break
                }
            }
        }

        // Update last sync timestamp
        if maxSyncMillis > lastSyncMillis {
            try? keychain.save(String(maxSyncMillis), for: KeychainHelper.Keys.lofiLastSyncMillis)
        }

        return allQsos
    }

    // MARK: - Clear

    /// Reset just the sync timestamp so QSOs can be re-downloaded
    func resetSyncTimestamp() {
        try? keychain.delete(for: KeychainHelper.Keys.lofiLastSyncMillis)
    }

    func clearCredentials() throws {
        try? keychain.delete(for: KeychainHelper.Keys.lofiAuthToken)
        try? keychain.delete(for: KeychainHelper.Keys.lofiClientKey)
        try? keychain.delete(for: KeychainHelper.Keys.lofiClientSecret)
        try? keychain.delete(for: KeychainHelper.Keys.lofiCallsign)
        try? keychain.delete(for: KeychainHelper.Keys.lofiEmail)
        try? keychain.delete(for: KeychainHelper.Keys.lofiDeviceLinked)
        try? keychain.delete(for: KeychainHelper.Keys.lofiLastSyncMillis)
    }

    // MARK: - Private

    private func getToken() throws -> String {
        guard let token = try? keychain.readString(for: KeychainHelper.Keys.lofiAuthToken) else {
            throw LoFiError.authenticationRequired
        }
        return token
    }

    private func generateClientSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LoFiError.invalidResponse("Not an HTTP response")
        }

        if httpResponse.statusCode == 401 {
            throw LoFiError.authenticationRequired
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LoFiError.apiError(httpResponse.statusCode, body)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw LoFiError.invalidResponse("JSON decode error: \(error)")
        }
    }
}
