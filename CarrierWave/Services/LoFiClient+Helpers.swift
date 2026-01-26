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
    }
}
