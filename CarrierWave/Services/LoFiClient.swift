// swiftlint:disable file_length type_body_length function_body_length
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

        // Log account details including cutoff date
        logRegistrationDetails(registration)

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

        NSLog("[LoFi] ========== STARTING SYNC ==========")
        NSLog("[LoFi] Callsign: %@", getCallsign() ?? "unknown")
        NSLog("[LoFi] Last Sync Millis: %lld", lastSyncMillis)
        if lastSyncMillis > 0 {
            let lastSyncDate = Date(timeIntervalSince1970: Double(lastSyncMillis) / 1_000.0)
            let formatter = ISO8601DateFormatter()
            NSLog("[LoFi] Last Sync Date: %@", formatter.string(from: lastSyncDate))
        }
        NSLog("[LoFi] Is Fresh Sync: %@", isFreshSync ? "true" : "false")

        // Re-register to get fresh account info (including cutoff date)
        do {
            _ = try await register()
        } catch {
            NSLog("[LoFi] Warning: Could not refresh registration: %@", error.localizedDescription)
        }

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

        // Log comprehensive summary
        logSyncSummary(operations: operations, qsos: allQsos)

        return allQsos
    }

    /// Fetch ALL QSOs from all operations (ignoring last sync timestamp, for force re-download)
    func fetchAllQsos() async throws -> [(LoFiQso, LoFiOperation)] {
        NSLog("[LoFi] ========== FORCE RE-DOWNLOAD ==========")
        NSLog("[LoFi] Fetching ALL QSOs (ignoring last sync timestamp)")

        // Re-register to get fresh account info (including cutoff date)
        do {
            _ = try await register()
        } catch {
            NSLog("[LoFi] Warning: Could not refresh registration: %@", error.localizedDescription)
        }

        // Fetch all operations (treat as fresh sync to get everything)
        let operations = try await fetchAllOperations(isFreshSync: true)

        // Fetch all QSOs starting from 0
        let (qsosByUUID, _) = try await fetchQsosForOperations(
            operations,
            lastSyncMillis: 0,
            isFreshSync: true
        )

        let allQsos = Array(qsosByUUID.values)

        // Log comprehensive summary
        logSyncSummary(operations: operations, qsos: allQsos)

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

    private func logRegistrationDetails(_ registration: LoFiRegistrationResponse) {
        NSLog("[LoFi] ========== REGISTRATION ==========")
        NSLog("[LoFi] Account UUID: %@", registration.account.uuid)
        NSLog("[LoFi] Account Call: %@", registration.account.call)
        NSLog("[LoFi] Account Name: %@", registration.account.name ?? "nil")
        NSLog("[LoFi] Account Email: %@", registration.account.email ?? "nil")

        if let cutoffDate = registration.account.cutoffDate {
            NSLog("[LoFi] ⚠️ CUTOFF DATE: %@", cutoffDate)
        } else {
            NSLog("[LoFi] Cutoff Date: nil (no restriction)")
        }

        if let cutoffMillis = registration.account.cutoffDateMillis {
            let date = Date(timeIntervalSince1970: Double(cutoffMillis) / 1_000.0)
            let formatter = ISO8601DateFormatter()
            NSLog(
                "[LoFi] ⚠️ CUTOFF DATE MILLIS: %lld (%@)", cutoffMillis, formatter.string(from: date)
            )
        } else {
            NSLog("[LoFi] Cutoff Date Millis: nil (no restriction)")
        }

        NSLog("[LoFi] Sync Batch Size: %d", registration.meta.flags.suggestedSyncBatchSize)
        NSLog("[LoFi] Sync Loop Delay: %d ms", registration.meta.flags.suggestedSyncLoopDelay)
        NSLog("[LoFi] Sync Check Period: %d ms", registration.meta.flags.suggestedSyncCheckPeriod)
    }

    private func logSyncSummary(operations: [LoFiOperation], qsos: [(LoFiQso, LoFiOperation)]) {
        NSLog("[LoFi] ========== SYNC SUMMARY ==========")
        NSLog("[LoFi] Total Operations: %d", operations.count)

        let expectedQsoCount = operations.reduce(0) { $0 + $1.qsoCount }
        NSLog("[LoFi] Expected QSOs (from operation.qsoCount): %d", expectedQsoCount)
        NSLog("[LoFi] Actual QSOs fetched: %d", qsos.count)

        if qsos.count != expectedQsoCount {
            NSLog(
                "[LoFi] ⚠️ QSO COUNT MISMATCH: expected %d, got %d (diff: %d)",
                expectedQsoCount, qsos.count, expectedQsoCount - qsos.count
            )
        }

        // Log date range of fetched QSOs
        if !qsos.isEmpty {
            let timestamps = qsos.map(\.0.startAtMillis)
            let minTimestamp = timestamps.min() ?? 0
            let maxTimestamp = timestamps.max() ?? 0
            let minDate = Date(timeIntervalSince1970: minTimestamp / 1_000.0)
            let maxDate = Date(timeIntervalSince1970: maxTimestamp / 1_000.0)
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short

            NSLog(
                "[LoFi] QSO Date Range: %@ to %@", formatter.string(from: minDate),
                formatter.string(from: maxDate)
            )
        }

        // Log operations with QSO count mismatches
        var mismatchCount = 0
        for op in operations {
            let opQsos = qsos.filter { $0.1.uuid == op.uuid }
            if opQsos.count != op.qsoCount {
                mismatchCount += 1
                if mismatchCount <= 10 {
                    NSLog(
                        "[LoFi] ⚠️ Operation %@ (%@): expected %d QSOs, got %d",
                        op.uuid, op.title ?? "untitled", op.qsoCount, opQsos.count
                    )
                }
            }
        }
        if mismatchCount > 10 {
            NSLog("[LoFi] ... and %d more operations with mismatches", mismatchCount - 10)
        }
        NSLog("[LoFi] ========== END SUMMARY ==========")
    }

    private func fetchAllOperations(isFreshSync: Bool) async throws -> [LoFiOperation] {
        var operationsByUUID: [String: LoFiOperation] = [:]

        NSLog("[LoFi] ========== FETCHING OPERATIONS ==========")
        NSLog(
            "[LoFi] isFreshSync: %@, otherClientsOnly: %@",
            isFreshSync ? "true" : "false", isFreshSync ? "false" : "true"
        )

        for deleted in [false, true] {
            var syncedSince: Int64 = 0
            var pageCount = 0

            NSLog("[LoFi] --- Fetching %@ operations ---", deleted ? "DELETED" : "ACTIVE")

            while true {
                pageCount += 1
                let response = try await fetchOperations(
                    syncedSinceMillis: syncedSince,
                    limit: 50,
                    otherClientsOnly: !isFreshSync,
                    deleted: deleted
                )

                NSLog(
                    "[LoFi] Page %d: got %d operations, totalRecords=%d, recordsLeft=%d",
                    pageCount, response.operations.count,
                    response.meta.operations.totalRecords,
                    response.meta.operations.recordsLeft
                )

                for operation in response.operations {
                    operationsByUUID[operation.uuid] = operation
                }

                if response.meta.operations.recordsLeft == 0 {
                    NSLog(
                        "[LoFi] No more records, finished fetching %@ operations",
                        deleted ? "deleted" : "active"
                    )
                    break
                }
                guard let next = response.meta.operations.nextSyncedAtMillis else {
                    NSLog(
                        "[LoFi] ⚠️ recordsLeft=%d but no nextSyncedAtMillis!",
                        response.meta.operations.recordsLeft
                    )
                    break
                }
                syncedSince = Int64(next)
            }
        }

        let operations = Array(operationsByUUID.values)
        let expectedQsos = operations.reduce(0) { $0 + $1.qsoCount }

        NSLog("[LoFi] ========== OPERATIONS SUMMARY ==========")
        NSLog("[LoFi] Total unique operations: %d", operations.count)
        NSLog("[LoFi] Expected total QSOs (sum of qsoCount): %d", expectedQsos)

        // Log date range of operations
        if !operations.isEmpty {
            let minMillis = operations.compactMap(\.startAtMillisMin).min() ?? 0
            let maxMillis = operations.compactMap(\.startAtMillisMax).max() ?? 0
            if minMillis > 0, maxMillis > 0 {
                let minDate = Date(timeIntervalSince1970: minMillis / 1_000.0)
                let maxDate = Date(timeIntervalSince1970: maxMillis / 1_000.0)
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                NSLog(
                    "[LoFi] Operations date range: %@ to %@",
                    formatter.string(from: minDate), formatter.string(from: maxDate)
                )
            }
        }

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
            var pageCount = 0

            while true {
                pageCount += 1
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
                    NSLog(
                        "[LoFi] ⚠️ Op %@: recordsLeft=%d but no nextSyncedAtMillis (deleted=%@)!",
                        operation.uuid, response.meta.qsos.recordsLeft, deleted ? "true" : "false"
                    )
                    break
                }
                qsoSyncedSince = Int64(next)
            }
        }

        if qsos.count != operation.qsoCount {
            // Log detailed mismatch info
            let opTitle = operation.title ?? "untitled"
            let potaRef = operation.potaRef?.reference ?? "none"

            // Calculate operation date range
            var dateInfo = "unknown dates"
            if let minMillis = operation.startAtMillisMin,
               let maxMillis = operation.startAtMillisMax
            {
                let minDate = Date(timeIntervalSince1970: minMillis / 1_000.0)
                let maxDate = Date(timeIntervalSince1970: maxMillis / 1_000.0)
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                dateInfo =
                    "\(formatter.string(from: minDate)) to \(formatter.string(from: maxDate))"
            }

            NSLog(
                "[LoFi] ⚠️ QSO MISMATCH: Op %@ (%@) POTA=%@ dates=%@ - expected %d, got %d (diff: %d)",
                operation.uuid, opTitle, potaRef, dateInfo,
                operation.qsoCount, qsos.count, operation.qsoCount - qsos.count
            )

            // If we got 0 QSOs for an operation that should have some, log extra warning
            if qsos.isEmpty, operation.qsoCount > 0 {
                NSLog(
                    "[LoFi] ⚠️⚠️ ZERO QSOs returned for operation with qsoCount=%d. "
                        + "This may indicate a cutoff_date restriction on the server.",
                    operation.qsoCount
                )
            }
        }
        return (qsos, maxSyncMillis)
    }
}

// Helper methods are in LoFiClient+Helpers.swift
