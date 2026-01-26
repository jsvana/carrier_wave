// POTA Parks Cache
//
// Downloads and caches park reference data from pota.app for
// displaying human-readable park names throughout the app.

import Foundation

// MARK: - POTAParksCacheMetadata

struct POTAParksCacheMetadata: Codable, Sendable {
    let downloadedAt: Date
    let recordCount: Int

    static func load(from url: URL) -> POTAParksCacheMetadata? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(POTAParksCacheMetadata.self, from: data)
    }

    func save(to url: URL) {
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: url)
        }
    }
}

// MARK: - POTAParksCacheStatus

enum POTAParksCacheStatus: Sendable {
    case notLoaded
    case loading
    case loaded(parkCount: Int, downloadedAt: Date?)
    case downloading
    case failed(String)
}

// MARK: - POTAParksCache

actor POTAParksCache {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = POTAParksCache()

    /// Current status of the cache (for UI display)
    private(set) var status: POTAParksCacheStatus = .notLoaded

    /// Number of parks in cache (for display/debugging)
    var parkCount: Int {
        parks.count
    }

    /// Get park name for a reference (e.g., "K-1234" -> "Yellowstone National Park")
    /// Returns nil if park not found or cache not loaded
    func name(for reference: String) -> String? {
        parks[reference.uppercased()]
    }

    /// Ensure cache is loaded, downloading if necessary
    func ensureLoaded() async {
        guard !isLoaded else {
            return
        }

        status = .loading

        // Try to load from disk first
        if loadFromDisk() {
            isLoaded = true
            status = .loaded(parkCount: parks.count, downloadedAt: loadMetadata()?.downloadedAt)
            // Check if refresh needed in background
            Task {
                await refreshIfNeeded()
            }
            return
        }

        // No cache on disk, download
        do {
            status = .downloading
            try await downloadAndCache()
            isLoaded = true
            status = .loaded(parkCount: parks.count, downloadedAt: loadMetadata()?.downloadedAt)
        } catch {
            print("POTAParksCache: Failed to download parks: \(error)")
            status = .failed(error.localizedDescription)
            isLoaded = true // Mark loaded to avoid repeated attempts
        }
    }

    /// Check if cache is stale and refresh if needed (non-blocking)
    func refreshIfNeeded() async {
        guard let metadata = loadMetadata() else {
            // No metadata, need to download
            status = .downloading
            do {
                try await downloadAndCache()
                status = .loaded(parkCount: parks.count, downloadedAt: loadMetadata()?.downloadedAt)
            } catch {
                status = .failed(error.localizedDescription)
            }
            return
        }

        let twoWeeksAgo = Date().addingTimeInterval(-14 * 24 * 60 * 60)
        if metadata.downloadedAt < twoWeeksAgo {
            status = .downloading
            do {
                try await downloadAndCache()
                status = .loaded(parkCount: parks.count, downloadedAt: loadMetadata()?.downloadedAt)
            } catch {
                // Keep old data, just update status to show we tried
                status = .loaded(parkCount: parks.count, downloadedAt: metadata.downloadedAt)
            }
        }
    }

    /// Force refresh the cache, throwing on failure
    func forceRefresh() async throws {
        status = .downloading
        do {
            try await downloadAndCache()
            status = .loaded(parkCount: parks.count, downloadedAt: loadMetadata()?.downloadedAt)
        } catch {
            status = .failed(error.localizedDescription)
            throw error
        }
    }

    /// Last download date (for display/debugging)
    func lastDownloadDate() -> Date? {
        loadMetadata()?.downloadedAt
    }

    /// Get current status snapshot for UI
    func getStatus() -> POTAParksCacheStatus {
        status
    }

    // MARK: Private

    private static let csvURL = URL(string: "https://pota.app/all_parks_ext.csv")!
    private static let cacheFileName = "pota_parks.csv"
    private static let metadataFileName = "pota_parks_metadata.json"

    private var parks: [String: String] = [:] // reference -> name
    private var isLoaded = false

    private var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    private var cacheFileURL: URL {
        cacheDirectory.appendingPathComponent(Self.cacheFileName)
    }

    private var metadataFileURL: URL {
        cacheDirectory.appendingPathComponent(Self.metadataFileName)
    }

    private func loadFromDisk() -> Bool {
        guard FileManager.default.fileExists(atPath: cacheFileURL.path) else {
            return false
        }

        do {
            let csvData = try String(contentsOf: cacheFileURL, encoding: .utf8)
            parks = parseCSV(csvData)
            return !parks.isEmpty
        } catch {
            print("POTAParksCache: Failed to load from disk: \(error)")
            return false
        }
    }

    private func loadMetadata() -> POTAParksCacheMetadata? {
        POTAParksCacheMetadata.load(from: metadataFileURL)
    }

    private func saveMetadata(recordCount: Int) {
        let metadata = POTAParksCacheMetadata(
            downloadedAt: Date(),
            recordCount: recordCount
        )
        metadata.save(to: metadataFileURL)
    }

    private func downloadAndCache() async throws {
        let (data, response) = try await URLSession.shared.data(from: Self.csvURL)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            throw URLError(.badServerResponse)
        }

        guard let csvString = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }

        // Parse and store in memory
        let parsed = parseCSV(csvString)
        parks = parsed

        // Save to disk
        try csvString.write(to: cacheFileURL, atomically: true, encoding: .utf8)
        saveMetadata(recordCount: parsed.count)

        print("POTAParksCache: Downloaded \(parsed.count) parks")
    }

    private func parseCSV(_ csv: String) -> [String: String] {
        var result: [String: String] = [:]
        let lines = csv.components(separatedBy: .newlines)

        // Skip header row
        for line in lines.dropFirst() {
            guard !line.isEmpty else {
                continue
            }

            let fields = parseCSVLine(line)
            guard fields.count >= 2 else {
                continue
            }

            let reference = fields[0].uppercased()
            let name = fields[1]

            guard !reference.isEmpty, !name.isEmpty else {
                continue
            }
            result[reference] = name
        }

        return result
    }

    /// Parse a CSV line handling quoted fields
    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == ",", !inQuotes {
                fields.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current.trimmingCharacters(in: .whitespaces))

        return fields
    }
}
