import Foundation

// MARK: - POTADownloadCheckpoint

/// Checkpoint for resumable POTA downloads
struct POTADownloadCheckpoint: Codable {
    let processedActivationKeys: Set<String>
    let lastBatchDate: Date
}

// MARK: - POTAClient Checkpoint Methods

extension POTAClient {
    func loadDownloadCheckpoint() -> POTADownloadCheckpoint? {
        guard let data = try? KeychainHelper.shared.read(for: KeychainHelper.Keys.potaDownloadProgress),
              let checkpoint = try? JSONDecoder().decode(POTADownloadCheckpoint.self, from: data)
        else {
            return nil
        }
        return checkpoint
    }

    func saveDownloadCheckpoint(_ checkpoint: POTADownloadCheckpoint) {
        guard let data = try? JSONEncoder().encode(checkpoint) else {
            return
        }
        try? KeychainHelper.shared.save(data, for: KeychainHelper.Keys.potaDownloadProgress)
    }

    func clearDownloadCheckpoint() {
        try? KeychainHelper.shared.delete(for: KeychainHelper.Keys.potaDownloadProgress)
    }

    // MARK: - Fetch All QSOs

    func fetchAllQSOs() async throws -> [POTAFetchedQSO] {
        let activations = try await fetchActivations()
        var allFetched: [POTAFetchedQSO] = []

        // Load checkpoint if exists
        let checkpoint = loadDownloadCheckpoint()
        var processedKeys = checkpoint?.processedActivationKeys ?? Set<String>()
        let batchSize = 25

        NSLog(
            "[POTA] Starting download: %d activations, %d already processed",
            activations.count, processedKeys.count
        )

        // Process in batches for checkpoint resilience
        let remainingActivations = activations.filter { activation in
            let key = "\(activation.reference)|\(activation.date)"
            return !processedKeys.contains(key)
        }

        for (batchIndex, batch) in remainingActivations.chunked(into: batchSize).enumerated() {
            NSLog("[POTA] Processing batch %d: %d activations", batchIndex + 1, batch.count)

            for activation in batch {
                let key = "\(activation.reference)|\(activation.date)"
                do {
                    let qsos = try await fetchAllActivationQSOs(
                        reference: activation.reference, date: activation.date
                    )
                    for qso in qsos {
                        if let fetched = convertToFetchedQSO(qso, activation: activation) {
                            allFetched.append(fetched)
                        }
                    }
                    processedKeys.insert(key)
                } catch {
                    NSLog(
                        "[POTA] WARNING: Failed to fetch %@ %@: %@",
                        activation.reference, activation.date, error.localizedDescription
                    )
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }

            saveDownloadCheckpoint(POTADownloadCheckpoint(
                processedActivationKeys: processedKeys,
                lastBatchDate: Date()
            ))
        }

        clearDownloadCheckpoint()
        NSLog("[POTA] Download complete: %d total QSOs fetched", allFetched.count)
        return allFetched
    }

    // MARK: - Job Status Methods

    func fetchJobs() async throws -> [POTAJob] {
        let debugLog = SyncDebugLog.shared
        let token = try await authService.ensureValidToken()

        guard let url = URL(string: "\(baseURL)/user/jobs") else {
            debugLog.error("Invalid URL for POTA jobs", service: .pota)
            throw POTAError.fetchFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "Authorization")

        debugLog.debug("GET /user/jobs", service: .pota)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            debugLog.error("Invalid response (not HTTP)", service: .pota)
            throw POTAError.fetchFailed("Invalid response")
        }

        debugLog.debug("Jobs response: \(httpResponse.statusCode)", service: .pota)

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw POTAError.notAuthenticated
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            debugLog.error(
                "Jobs fetch failed: \(httpResponse.statusCode) - \(body)", service: .pota
            )
            throw POTAError.fetchFailed("HTTP \(httpResponse.statusCode): \(body)")
        }

        let jobs = try JSONDecoder().decode([POTAJob].self, from: data)
        debugLog.info("Fetched \(jobs.count) POTA jobs", service: .pota)
        return jobs
    }
}

// MARK: - Array Chunking Extension

extension Array {
    /// Splits array into chunks of the specified size
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
