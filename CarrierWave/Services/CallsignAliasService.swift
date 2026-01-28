import Foundation

// MARK: - CallsignAliasService

/// Service to manage the user's current callsign and previous callsigns (aliases).
/// Used to properly match QSOs across services when the user has changed callsigns over time.
actor CallsignAliasService {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = CallsignAliasService()

    /// Get the user's current callsign
    func getCurrentCallsign() -> String? {
        do {
            return try keychain.readString(for: KeychainHelper.Keys.currentCallsign)
        } catch {
            return nil
        }
    }

    /// Save the user's current callsign
    func saveCurrentCallsign(_ callsign: String) throws {
        let normalized = callsign.uppercased().trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else {
            throw CallsignAliasError.invalidCallsign
        }
        try keychain.save(normalized, for: KeychainHelper.Keys.currentCallsign)
    }

    /// Clear the current callsign
    func clearCurrentCallsign() throws {
        try keychain.delete(for: KeychainHelper.Keys.currentCallsign)
    }

    /// Get the list of previous callsigns
    func getPreviousCallsigns() -> [String] {
        do {
            let data = try keychain.read(for: KeychainHelper.Keys.previousCallsigns)
            let callsigns = try JSONDecoder().decode([String].self, from: data)
            return callsigns
        } catch {
            return []
        }
    }

    /// Save the list of previous callsigns
    func savePreviousCallsigns(_ callsigns: [String]) throws {
        let normalized = callsigns
            .map { $0.uppercased().trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let data = try JSONEncoder().encode(normalized)
        try keychain.save(data, for: KeychainHelper.Keys.previousCallsigns)
    }

    /// Add a previous callsign to the list
    func addPreviousCallsign(_ callsign: String) throws {
        let normalized = callsign.uppercased().trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else {
            throw CallsignAliasError.invalidCallsign
        }

        var existing = getPreviousCallsigns()
        if !existing.contains(normalized) {
            existing.append(normalized)
            try savePreviousCallsigns(existing)
        }
    }

    /// Remove a previous callsign from the list
    func removePreviousCallsign(_ callsign: String) throws {
        let normalized = callsign.uppercased().trimmingCharacters(in: .whitespaces)
        var existing = getPreviousCallsigns()
        existing.removeAll { $0 == normalized }
        try savePreviousCallsigns(existing)
    }

    /// Get all user callsigns (current + previous), uppercased
    func getAllUserCallsigns() -> Set<String> {
        var callsigns = Set<String>()
        if let current = getCurrentCallsign() {
            callsigns.insert(current)
        }
        for previous in getPreviousCallsigns() {
            callsigns.insert(previous)
        }
        return callsigns
    }

    /// Check if a given callsign belongs to the user
    func isUserCallsign(_ callsign: String) -> Bool {
        let normalized = callsign.uppercased().trimmingCharacters(in: .whitespaces)
        return getAllUserCallsigns().contains(normalized)
    }

    /// Find callsigns in the given set that are not configured as user callsigns
    func getUnconfiguredCallsigns(from allCallsigns: Set<String>) -> Set<String> {
        let userCallsigns = getAllUserCallsigns()
        return allCallsigns.filter { !userCallsigns.contains($0.uppercased()) }
    }

    // MARK: Private

    private let keychain = KeychainHelper.shared
}

// MARK: - CallsignAliasError

enum CallsignAliasError: LocalizedError {
    case invalidCallsign

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .invalidCallsign:
            "Invalid callsign"
        }
    }
}
