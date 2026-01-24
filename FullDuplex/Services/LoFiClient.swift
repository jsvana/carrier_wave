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
        (try? keychain.readString(for: KeychainHelper.Keys.lofiClientKey)) != nil
            && (try? keychain.readString(for: KeychainHelper.Keys.lofiCallsign)) != nil
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
            let value = Int64(str)
        else {
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
            let callsign = try? keychain.readString(for: KeychainHelper.Keys.lofiCallsign)
        else {
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
    /// - Parameter otherClientsOnly: When true, excludes operations uploaded by this client.
    ///   Should be false for fresh sync to get ALL operations.
    /// - Parameter deleted: When true, fetches only deleted operations. When nil/false, fetches only active.
    ///   Note: The server checks `if params[:deleted]` so passing "false" is treated as truthy.
    ///   Only pass this parameter when true, omit it entirely for active operations.
    func fetchOperations(
        syncedSinceMillis: Int64 = 0,
        limit: Int = 50,
        otherClientsOnly: Bool = true,
        deleted: Bool = false
    ) async throws -> LoFiOperationsResponse {
        let token = try getToken()

        var components = URLComponents(string: "\(baseURL)/v1/operations")!
        components.queryItems = [
            URLQueryItem(name: "synced_since_millis", value: String(syncedSinceMillis)),
            URLQueryItem(name: "other_clients_only", value: String(otherClientsOnly)),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        // Only include deleted param when true - server treats any value as truthy
        if deleted {
            components.queryItems?.append(URLQueryItem(name: "deleted", value: "true"))
        }

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return try await performRequest(urlRequest)
    }

    /// Fetch QSOs for a specific operation
    /// - Parameter otherClientsOnly: When true, excludes QSOs uploaded by this client.
    ///   Should be false for fresh sync to get ALL QSOs.
    /// - Parameter deleted: When true, fetches deleted QSOs. When nil/false, fetches active QSOs.
    ///   Note: The server checks `if params[:deleted]` so passing "false" is treated as truthy.
    ///   Only pass this parameter when true, omit it entirely for active QSOs.
    func fetchOperationQsos(
        operationUUID: String,
        syncedSinceMillis: Int64 = 0,
        limit: Int = 50,
        otherClientsOnly: Bool = true,
        deleted: Bool = false
    ) async throws -> LoFiQsosResponse {
        let token = try getToken()

        var components = URLComponents(string: "\(baseURL)/v1/operations/\(operationUUID)/qsos")!
        components.queryItems = [
            URLQueryItem(name: "synced_since_millis", value: String(syncedSinceMillis)),
            URLQueryItem(name: "other_clients_only", value: String(otherClientsOnly)),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        // Only include deleted param when true - server treats any value as truthy
        if deleted {
            components.queryItems?.append(URLQueryItem(name: "deleted", value: "true"))
        }

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return try await performRequest(urlRequest)
    }

    /// Fetch all QSOs from all operations since last sync
    func fetchAllQsosSinceLastSync() async throws -> [(LoFiQso, LoFiOperation)] {
        var allQsos: [(LoFiQso, LoFiOperation)] = []
        let lastSyncMillis = getLastSyncMillis()
        var maxSyncMillis: Int64 = lastSyncMillis

        // For fresh sync (lastSyncMillis == 0), fetch ALL QSOs including our own.
        // For incremental sync, only fetch QSOs from other clients to avoid duplicates.
        let isFreshSync = lastSyncMillis == 0
        let callsign = getCallsign() ?? "unknown"
        NSLog(
            "[LoFi] fetchAllQsosSinceLastSync: callsign=%@, lastSyncMillis=%lld, isFreshSync=%@, otherClientsOnly=%@",
            callsign, lastSyncMillis, isFreshSync ? "true" : "false",
            !isFreshSync ? "true" : "false")

        // Fetch all operations (both active and deleted, deduplicated by UUID)
        var operationsByUUID: [String: LoFiOperation] = [:]

        // Helper to fetch operations with given deleted flag
        func fetchOperationsWithDeleted(_ deleted: Bool) async throws {
            var syncedSince: Int64 = 0
            while true {
                let response = try await fetchOperations(
                    syncedSinceMillis: syncedSince,
                    limit: 50,
                    otherClientsOnly: !isFreshSync,
                    deleted: deleted
                )
                NSLog(
                    "[LoFi] Fetched %d operations (deleted=%@, total unique so far: %d), recordsLeft=%d",
                    response.operations.count, deleted ? "true" : "false",
                    operationsByUUID.count
                        + response.operations.filter { operationsByUUID[$0.uuid] == nil }.count,
                    response.meta.operations.recordsLeft)

                for op in response.operations {
                    operationsByUUID[op.uuid] = op
                }

                if response.meta.operations.recordsLeft == 0 {
                    break
                }

                if let next = response.meta.operations.nextSyncedAtMillis {
                    syncedSince = Int64(next)
                } else {
                    break
                }
            }
        }

        try await fetchOperationsWithDeleted(false)
        try await fetchOperationsWithDeleted(true)

        let operations = Array(operationsByUUID.values)
        let expectedTotal = operations.reduce(0) { $0 + $1.qsoCount }
        NSLog(
            "[LoFi] Total unique operations fetched: %d, expected QSOs: %d",
            operations.count,
            expectedTotal)

        // Fetch QSOs for each operation (both active and deleted, deduplicated by UUID)
        var qsosByUUID: [String: (LoFiQso, LoFiOperation)] = [:]

        // For fresh sync, always start from 0 to get all QSOs
        let qsoSyncStart: Int64 = isFreshSync ? 0 : lastSyncMillis

        for operation in operations {
            var operationQsoCount = 0

            // Helper to fetch QSOs with given deleted flag
            func fetchQsosWithDeleted(_ deleted: Bool) async throws {
                var qsoSyncedSince: Int64 = qsoSyncStart
                while true {
                    let qsosResponse = try await fetchOperationQsos(
                        operationUUID: operation.uuid,
                        syncedSinceMillis: qsoSyncedSince,
                        limit: 50,
                        otherClientsOnly: !isFreshSync,
                        deleted: deleted
                    )

                    for qso in qsosResponse.qsos {
                        if qsosByUUID[qso.uuid] == nil {
                            qsosByUUID[qso.uuid] = (qso, operation)
                            operationQsoCount += 1
                            if let syncedAt = qso.syncedAtMillis {
                                maxSyncMillis = max(maxSyncMillis, Int64(syncedAt))
                            }
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

            try await fetchQsosWithDeleted(false)
            try await fetchQsosWithDeleted(true)

            // Log if we got fewer QSOs than expected for this operation
            if operationQsoCount != operation.qsoCount {
                NSLog(
                    "[LoFi] Operation %@ (%@): expected %d QSOs, got %d",
                    operation.uuid, operation.title ?? "untitled",
                    operation.qsoCount, operationQsoCount)
            }
        }

        allQsos = Array(qsosByUUID.values)
        NSLog("[LoFi] Total unique QSOs fetched: %d", allQsos.count)

        // Update last sync timestamp
        if maxSyncMillis > lastSyncMillis {
            try? keychain.save(String(maxSyncMillis), for: KeychainHelper.Keys.lofiLastSyncMillis)
        }

        return allQsos
    }

    // MARK: - Clear

    /// Reset just the sync timestamp so QSOs can be re-downloaded
    func resetSyncTimestamp() {
        let before = getLastSyncMillis()
        try? keychain.delete(for: KeychainHelper.Keys.lofiLastSyncMillis)
        let after = getLastSyncMillis()
        NSLog("[LoFi] resetSyncTimestamp: before=%lld, after=%lld", before, after)
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

        // Log response details
        NSLog("[LoFi] ========== RESPONSE ==========")
        NSLog("[LoFi] Status: %d", httpResponse.statusCode)
        NSLog("[LoFi] Response Headers:")
        for (key, value) in httpResponse.allHeaderFields {
            NSLog("[LoFi]   %@: %@", String(describing: key), String(describing: value))
        }

        // Log response body (truncate if very long)
        if let bodyStr = String(data: data, encoding: .utf8) {
            if bodyStr.count > 2000 {
                NSLog("[LoFi] Body (truncated): %@...", String(bodyStr.prefix(2000)))
            } else {
                NSLog("[LoFi] Body: %@", bodyStr)
            }
        }

        if httpResponse.statusCode == 401 {
            throw LoFiError.authenticationRequired
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LoFiError.apiError(httpResponse.statusCode, body)
        }

        do {
            let decoded = try JSONDecoder().decode(T.self, from: data)

            // Log counts for known response types
            if let opsResponse = decoded as? LoFiOperationsResponse {
                NSLog("[LoFi] ========== COUNTS ==========")
                NSLog("[LoFi] Operations returned: %d", opsResponse.operations.count)
                NSLog("[LoFi] Records left: %d", opsResponse.meta.operations.recordsLeft)
                if let next = opsResponse.meta.operations.nextSyncedAtMillis {
                    NSLog("[LoFi] Next synced at millis: %d", next)
                }
            } else if let qsosResponse = decoded as? LoFiQsosResponse {
                NSLog("[LoFi] ========== COUNTS ==========")
                NSLog("[LoFi] QSOs returned: %d", qsosResponse.qsos.count)
                NSLog("[LoFi] Records left: %d", qsosResponse.meta.qsos.recordsLeft)
                if let next = qsosResponse.meta.qsos.nextSyncedAtMillis {
                    NSLog("[LoFi] Next synced at millis: %d", next)
                }
            }

            return decoded
        } catch {
            throw LoFiError.invalidResponse("JSON decode error: \(error)")
        }
    }
}
