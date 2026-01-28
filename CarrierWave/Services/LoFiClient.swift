import Foundation

// MARK: - LoFiError

enum LoFiError: Error, LocalizedError {
    case notConfigured
    case notLinked
    case registrationFailed(String)
    case authenticationRequired
    case networkError(Error)
    case invalidResponse(String)
    case apiError(Int, String)

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "LoFi is not configured. Please set up your callsign."
        case .notLinked:
            "Device not linked. Please check your email to confirm."
        case let .registrationFailed(msg):
            "Registration failed: \(msg)"
        case .authenticationRequired:
            "Authentication required. Please re-register."
        case let .networkError(error):
            "Network error: \(error.localizedDescription)"
        case let .invalidResponse(msg):
            "Invalid response: \(msg)"
        case let .apiError(code, msg):
            "API error (\(code)): \(msg)"
        }
    }
}

// MARK: - LoFiClient

@MainActor
final class LoFiClient {
    // MARK: Lifecycle

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    // MARK: Internal

    // MARK: Internal (for extension access)

    let baseURL = "https://lofi.ham2k.net"
    let clientName = "CarrierWave"
    let appName = "CarrierWave"
    let keychain = KeychainHelper.shared
    let session: URLSession

    // MARK: - Configuration

    var isConfigured: Bool {
        (try? keychain.readString(for: KeychainHelper.Keys.lofiClientKey)) != nil
            && (try? keychain.readString(for: KeychainHelper.Keys.lofiCallsign)) != nil
    }

    var isLinked: Bool {
        (try? keychain.readString(for: KeychainHelper.Keys.lofiDeviceLinked)) == "true"
    }

    var hasToken: Bool {
        (try? keychain.readString(for: KeychainHelper.Keys.lofiAuthToken)) != nil
    }

    func hasCredentials() -> Bool {
        isConfigured && isLinked
    }

    func getCallsign() -> String? {
        try? keychain.readString(for: KeychainHelper.Keys.lofiCallsign)
    }

    func getEmail() -> String? {
        try? keychain.readString(for: KeychainHelper.Keys.lofiEmail)
    }

    func getLastSyncMillis() -> Int64 {
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
        if let email {
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
        let lastSyncMillis = getLastSyncMillis()
        let isFreshSync = lastSyncMillis == 0

        NSLog(
            "[LoFi] fetchAllQsosSinceLastSync: callsign=%@, lastSyncMillis=%lld, isFreshSync=%@",
            getCallsign() ?? "unknown", lastSyncMillis, isFreshSync ? "true" : "false"
        )

        // Fetch all operations (both active and deleted)
        let operations = try await fetchAllOperations(isFreshSync: isFreshSync)

        // Fetch QSOs for each operation
        let (qsosByUUID, maxSyncMillis) = try await fetchQsosForOperations(
            operations,
            lastSyncMillis: lastSyncMillis,
            isFreshSync: isFreshSync
        )

        // Update last sync timestamp
        if maxSyncMillis > lastSyncMillis {
            try? keychain.save(String(maxSyncMillis), for: KeychainHelper.Keys.lofiLastSyncMillis)
        }

        let allQsos = Array(qsosByUUID.values)
        NSLog("[LoFi] Total unique QSOs fetched: %d", allQsos.count)
        return allQsos
    }

    /// Fetch ALL QSOs from all operations (ignoring last sync timestamp, for force re-download)
    func fetchAllQsos() async throws -> [(LoFiQso, LoFiOperation)] {
        NSLog("[LoFi] fetchAllQsos: fetching all QSOs (force re-download)")

        // Fetch all operations (treat as fresh sync to get everything)
        let operations = try await fetchAllOperations(isFreshSync: true)

        // Fetch all QSOs starting from 0
        let (qsosByUUID, _) = try await fetchQsosForOperations(
            operations,
            lastSyncMillis: 0,
            isFreshSync: true
        )

        let allQsos = Array(qsosByUUID.values)
        NSLog("[LoFi] fetchAllQsos: Total QSOs fetched: %d", allQsos.count)
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

    // MARK: Private

    private func fetchAllOperations(isFreshSync: Bool) async throws -> [LoFiOperation] {
        var operationsByUUID: [String: LoFiOperation] = [:]

        for deleted in [false, true] {
            var syncedSince: Int64 = 0
            while true {
                let response = try await fetchOperations(
                    syncedSinceMillis: syncedSince,
                    limit: 50,
                    otherClientsOnly: !isFreshSync,
                    deleted: deleted
                )

                for operation in response.operations {
                    operationsByUUID[operation.uuid] = operation
                }

                if response.meta.operations.recordsLeft == 0 {
                    break
                }
                guard let next = response.meta.operations.nextSyncedAtMillis else {
                    break
                }
                syncedSince = Int64(next)
            }
        }

        let operations = Array(operationsByUUID.values)
        NSLog(
            "[LoFi] Total unique operations: %d, expected QSOs: %d",
            operations.count, operations.reduce(0) { $0 + $1.qsoCount }
        )
        return operations
    }

    private func fetchQsosForOperations(
        _ operations: [LoFiOperation],
        lastSyncMillis: Int64,
        isFreshSync: Bool
    ) async throws -> ([String: (LoFiQso, LoFiOperation)], Int64) {
        var qsosByUUID: [String: (LoFiQso, LoFiOperation)] = [:]
        var maxSyncMillis = lastSyncMillis
        let qsoSyncStart: Int64 = isFreshSync ? 0 : lastSyncMillis

        for operation in operations {
            let (opQsos, opMaxSync) = try await fetchQsosForOperation(
                operation,
                syncStart: qsoSyncStart,
                isFreshSync: isFreshSync
            )
            for (qso, op) in opQsos where qsosByUUID[qso.uuid] == nil {
                qsosByUUID[qso.uuid] = (qso, op)
            }
            maxSyncMillis = max(maxSyncMillis, opMaxSync)
        }

        return (qsosByUUID, maxSyncMillis)
    }

    private func fetchQsosForOperation(
        _ operation: LoFiOperation,
        syncStart: Int64,
        isFreshSync: Bool
    ) async throws -> ([(LoFiQso, LoFiOperation)], Int64) {
        var qsos: [(LoFiQso, LoFiOperation)] = []
        var maxSyncMillis: Int64 = 0

        for deleted in [false, true] {
            var qsoSyncedSince = syncStart
            while true {
                let response = try await fetchOperationQsos(
                    operationUUID: operation.uuid,
                    syncedSinceMillis: qsoSyncedSince,
                    limit: 50,
                    otherClientsOnly: !isFreshSync,
                    deleted: deleted
                )

                for qso in response.qsos {
                    qsos.append((qso, operation))
                    if let syncedAt = qso.syncedAtMillis {
                        maxSyncMillis = max(maxSyncMillis, Int64(syncedAt))
                    }
                }

                if response.meta.qsos.recordsLeft == 0 {
                    break
                }
                guard let next = response.meta.qsos.nextSyncedAtMillis else {
                    break
                }
                qsoSyncedSince = Int64(next)
            }
        }

        if qsos.count != operation.qsoCount {
            NSLog(
                "[LoFi] WARNING: Operation %@ QSO count mismatch - expected %d, got %d. "
                    + "If you see 0 QSOs, download access may need to be enabled by Ham2K staff.",
                operation.uuid, operation.qsoCount, qsos.count
            )
        }
        return (qsos, maxSyncMillis)
    }
}

// Helper methods are in LoFiClient+Helpers.swift
