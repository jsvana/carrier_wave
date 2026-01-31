import Foundation
import SwiftData

// MARK: - CallsignLookupService

/// Service for looking up callsign information from multiple sources.
/// Uses a two-tier lookup strategy:
/// 1. Polo notes lists (local, fast, offline-capable)
/// 2. QRZ XML callbook API (remote, comprehensive)
actor CallsignLookupService {
    // MARK: Lifecycle

    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
    }

    // MARK: Internal

    // MARK: - Configuration

    /// Maximum entries to keep in cache
    let maxCacheSize = 100

    /// Debounce delay for lookups (seconds)
    let debounceDelay: TimeInterval = 0.5

    /// Maximum age for cached entries before refresh (seconds)
    let maxCacheAge: TimeInterval = 3_600

    // MARK: - Public API

    /// Look up a callsign, checking Polo notes first, then QRZ
    /// - Parameter callsign: The callsign to look up
    /// - Returns: CallsignInfo if found, nil otherwise
    func lookup(_ callsign: String) async -> CallsignInfo? {
        let normalizedCallsign = callsign.uppercased()

        // Check cache first
        if let cached = cache[normalizedCallsign], cached.age < maxCacheAge {
            return cached
        }

        // Check pending lookups
        if let pending = pendingLookups[normalizedCallsign] {
            return await pending.value
        }

        // Start new lookup
        let task = Task<CallsignInfo?, Never> {
            // Debounce
            try? await Task.sleep(nanoseconds: UInt64(debounceDelay * 1_000_000_000))

            // Tier 1: Polo notes (local)
            if let poloInfo = await lookupInPoloNotes(normalizedCallsign) {
                updateCache(poloInfo)
                return poloInfo
            }

            // Tier 2: QRZ XML API (remote)
            if let qrzInfo = await lookupInQRZ(normalizedCallsign) {
                updateCache(qrzInfo)
                return qrzInfo
            }

            return nil
        }

        pendingLookups[normalizedCallsign] = task
        let result = await task.value
        pendingLookups[normalizedCallsign] = nil

        return result
    }

    /// Get cached info for a callsign (synchronous, no network)
    /// - Parameter callsign: The callsign to look up
    /// - Returns: CallsignInfo if in cache, nil otherwise
    func cachedInfo(for callsign: String) -> CallsignInfo? {
        cache[callsign.uppercased()]
    }

    /// Preload Polo notes from all clubs
    func preloadPoloNotes() async {
        await loadPoloNotesFromClubs()
    }

    /// Clear all caches
    func clearCache() {
        cache.removeAll()
        poloNotesCache.removeAll()
        pendingLookups.removeAll()
    }

    // MARK: Private

    // MARK: - Private State

    /// Cache of recent lookups
    private var cache: [String: CallsignInfo] = [:]

    /// Order of cache entries for LRU eviction
    private var cacheOrder: [String] = []

    /// Pending lookup tasks (for deduplication)
    private var pendingLookups: [String: Task<CallsignInfo?, Never>] = [:]

    /// Merged Polo notes from all clubs
    private var poloNotesCache: [String: CallsignInfo] = [:]

    /// When Polo notes were last loaded
    private var poloNotesLoadedAt: Date?

    /// ModelContext for accessing Club data
    private let modelContext: ModelContext?

    // MARK: - Polo Notes Lookup

    private func lookupInPoloNotes(_ callsign: String) async -> CallsignInfo? {
        // Reload Polo notes if stale or empty
        if poloNotesCache.isEmpty || isPoloNotesCacheStale() {
            await loadPoloNotesFromClubs()
        }

        return poloNotesCache[callsign]
    }

    private func isPoloNotesCacheStale() -> Bool {
        guard let loadedAt = poloNotesLoadedAt else {
            return true
        }
        // Refresh every 5 minutes
        return Date().timeIntervalSince(loadedAt) > 300
    }

    private func loadPoloNotesFromClubs() async {
        // Fetch club URLs on main actor (SwiftData requirement)
        let urls = await fetchClubURLsOnMainActor()

        guard !urls.isEmpty else {
            return
        }

        // Load and merge all notes (can run on any thread)
        let merged = await PoloNotesParser.load(from: urls)
        poloNotesCache = merged
        poloNotesLoadedAt = Date()
    }

    @MainActor
    private func fetchClubURLsOnMainActor() -> [URL] {
        guard let context = modelContext else {
            return []
        }

        do {
            let descriptor = FetchDescriptor<Club>()
            let clubs = try context.fetch(descriptor)

            return clubs.compactMap { club -> URL? in
                guard !club.poloNotesListURL.isEmpty else {
                    return nil
                }
                return URL(string: club.poloNotesListURL)
            }
        } catch {
            print("[CallsignLookup] Failed to load clubs: \(error)")
            return []
        }
    }

    // MARK: - Cache Management

    private func updateCache(_ info: CallsignInfo) {
        let callsign = info.callsign

        // Update cache
        cache[callsign] = info

        // Update LRU order
        if let index = cacheOrder.firstIndex(of: callsign) {
            cacheOrder.remove(at: index)
        }
        cacheOrder.append(callsign)

        // Evict old entries if needed
        while cacheOrder.count > maxCacheSize {
            if let oldest = cacheOrder.first {
                cacheOrder.removeFirst()
                cache.removeValue(forKey: oldest)
            }
        }
    }
}

// MARK: - QRZ XML API

extension CallsignLookupService {
    /// QRZ XML callbook API base URL
    private static let qrzXMLURL = "https://xmldata.qrz.com/xml/current/"

    /// Look up a callsign in QRZ XML callbook
    /// Uses the logbook API key which also works for XML callbook lookups
    private func lookupInQRZ(_ callsign: String) async -> CallsignInfo? {
        // Get API key from keychain
        guard let apiKey = try? KeychainHelper.shared.readString(for: KeychainHelper.Keys.qrzApiKey)
        else {
            return nil
        }

        // First, get a session key using the API key
        guard let sessionKey = await getQRZSessionKey(apiKey: apiKey) else {
            return nil
        }

        // Then look up the callsign
        return await performQRZLookup(callsign: callsign, sessionKey: sessionKey)
    }

    /// Get a QRZ session key using the API key
    private func getQRZSessionKey(apiKey: String) async -> String? {
        guard var urlComponents = URLComponents(string: Self.qrzXMLURL) else {
            return nil
        }

        // QRZ XML API accepts logbook API key with "apikey:" prefix
        urlComponents.queryItems = [
            URLQueryItem(name: "username", value: apiKey),
            URLQueryItem(name: "password", value: "apikey"),
        ]

        guard let url = urlComponents.url else {
            return nil
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("CarrierWave/1.0", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 5

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200
            else {
                return nil
            }

            guard let xmlString = String(data: data, encoding: .utf8) else {
                return nil
            }

            // Parse session key from XML response
            // Format: <Key>SESSION_KEY</Key>
            return parseXMLValue(from: xmlString, tag: "Key")
        } catch {
            return nil
        }
    }

    /// Perform the actual callsign lookup with a session key
    private func performQRZLookup(callsign: String, sessionKey: String) async -> CallsignInfo? {
        guard var urlComponents = URLComponents(string: Self.qrzXMLURL) else {
            return nil
        }

        urlComponents.queryItems = [
            URLQueryItem(name: "s", value: sessionKey),
            URLQueryItem(name: "callsign", value: callsign),
        ]

        guard let url = urlComponents.url else {
            return nil
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("CarrierWave/1.0", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 5

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200
            else {
                return nil
            }

            guard let xmlString = String(data: data, encoding: .utf8) else {
                return nil
            }

            // Check for error
            if xmlString.contains("<Error>") {
                return nil
            }

            // Parse callsign info from XML
            let name = combineNames(
                first: parseXMLValue(from: xmlString, tag: "fname"),
                last: parseXMLValue(from: xmlString, tag: "name")
            )
            let grid = parseXMLValue(from: xmlString, tag: "grid")
            let qth = parseXMLValue(from: xmlString, tag: "addr2") // City
            let state = parseXMLValue(from: xmlString, tag: "state")
            let country = parseXMLValue(from: xmlString, tag: "country")
            let licenseClass = parseXMLValue(from: xmlString, tag: "class")

            // Only return if we got at least some useful info
            guard name != nil || grid != nil || qth != nil else {
                return nil
            }

            return CallsignInfo(
                callsign: callsign,
                name: name,
                qth: qth,
                state: state,
                country: country,
                grid: grid,
                licenseClass: licenseClass,
                source: .qrz
            )
        } catch {
            return nil
        }
    }

    /// Parse a value from XML by tag name
    private func parseXMLValue(from xml: String, tag: String) -> String? {
        let openTag = "<\(tag)>"
        let closeTag = "</\(tag)>"

        guard let startRange = xml.range(of: openTag),
              let endRange = xml.range(of: closeTag, range: startRange.upperBound ..< xml.endIndex)
        else {
            return nil
        }

        let value = String(xml[startRange.upperBound ..< endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return value.isEmpty ? nil : value
    }

    /// Combine first and last name
    private func combineNames(first: String?, last: String?) -> String? {
        if let first, let last {
            "\(first) \(last)"
        } else if let first {
            first
        } else if let last {
            last
        } else {
            nil
        }
    }
}
