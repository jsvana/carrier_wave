// swiftlint:disable function_body_length
import Foundation

// MARK: - LoFiClient Private Helpers

@MainActor
extension LoFiClient {
    func getToken() throws -> String {
        guard let token = try? keychain.readString(for: KeychainHelper.Keys.lofiAuthToken) else {
            throw LoFiError.authenticationRequired
        }
        return token
    }

    func generateClientSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LoFiError.invalidResponse("Not an HTTP response")
        }

        logResponseDetails(httpResponse, data: data)

        if httpResponse.statusCode == 401 {
            throw LoFiError.authenticationRequired
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LoFiError.apiError(httpResponse.statusCode, body)
        }

        do {
            let decoded = try JSONDecoder().decode(T.self, from: data)
            logResponseCounts(decoded)
            return decoded
        } catch {
            throw LoFiError.invalidResponse("JSON decode error: \(error)")
        }
    }

    private func logResponseDetails(_ response: HTTPURLResponse, data: Data) {
        NSLog("[LoFi] ========== RESPONSE ==========")
        NSLog("[LoFi] Status: %d", response.statusCode)
        NSLog("[LoFi] Response Headers:")
        for (key, value) in response.allHeaderFields {
            NSLog("[LoFi]   %@: %@", String(describing: key), String(describing: value))
        }

        if let bodyStr = String(data: data, encoding: .utf8) {
            if bodyStr.count > 2_000 {
                NSLog("[LoFi] Body (truncated): %@...", String(bodyStr.prefix(2_000)))
            } else {
                NSLog("[LoFi] Body: %@", bodyStr)
            }
        }
    }

    private func logResponseCounts(_ decoded: some Any) {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        if let opsResponse = decoded as? LoFiOperationsResponse {
            let meta = opsResponse.meta.operations
            NSLog("[LoFi] ========== OPERATIONS RESPONSE ==========")
            NSLog("[LoFi] Operations in page: %d", opsResponse.operations.count)
            NSLog("[LoFi] Total records: %d", meta.totalRecords)
            NSLog("[LoFi] Records left: %d", meta.recordsLeft)
            NSLog("[LoFi] Limit: %d", meta.limit)

            if let syncedUntil = meta.syncedUntilMillis {
                let date = Date(timeIntervalSince1970: syncedUntil / 1_000.0)
                NSLog(
                    "[LoFi] Synced until: %@ (millis: %.0f)", formatter.string(from: date),
                    syncedUntil
                )
            }
            if let syncedSince = meta.syncedSinceMillis {
                let date = Date(timeIntervalSince1970: syncedSince / 1_000.0)
                NSLog(
                    "[LoFi] Synced since: %@ (millis: %.0f)", formatter.string(from: date),
                    syncedSince
                )
            }
            if let next = meta.nextSyncedAtMillis {
                let date = Date(timeIntervalSince1970: next / 1_000.0)
                NSLog(
                    "[LoFi] Next synced at: %@ (millis: %.0f)", formatter.string(from: date), next
                )
            }
            if let otherClientsOnly = meta.otherClientsOnly {
                NSLog("[LoFi] Other clients only: %@", otherClientsOnly ? "true" : "false")
            }
        } else if let qsosResponse = decoded as? LoFiQsosResponse {
            let meta = qsosResponse.meta.qsos
            NSLog("[LoFi] ========== QSOS RESPONSE ==========")
            NSLog("[LoFi] QSOs in page: %d", qsosResponse.qsos.count)
            NSLog("[LoFi] Total records: %d", meta.totalRecords)
            NSLog("[LoFi] Records left: %d", meta.recordsLeft)
            NSLog("[LoFi] Limit: %d", meta.limit)

            if let syncedUntil = meta.syncedUntilMillis {
                let date = Date(timeIntervalSince1970: syncedUntil / 1_000.0)
                NSLog(
                    "[LoFi] Synced until: %@ (millis: %.0f)", formatter.string(from: date),
                    syncedUntil
                )
            }
            if let syncedSince = meta.syncedSinceMillis {
                let date = Date(timeIntervalSince1970: syncedSince / 1_000.0)
                NSLog(
                    "[LoFi] Synced since: %@ (millis: %.0f)", formatter.string(from: date),
                    syncedSince
                )
            }
            if let next = meta.nextSyncedAtMillis {
                let date = Date(timeIntervalSince1970: next / 1_000.0)
                NSLog(
                    "[LoFi] Next synced at: %@ (millis: %.0f)", formatter.string(from: date), next
                )
            }
            if let otherClientsOnly = meta.otherClientsOnly {
                NSLog("[LoFi] Other clients only: %@", otherClientsOnly ? "true" : "false")
            }
        }
    }
}
