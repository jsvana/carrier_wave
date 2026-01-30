// User Profile Service
//
// Manages persistence and retrieval of the user's amateur radio profile.
// Profile data is stored in the keychain for security and persistence.

import Foundation

// MARK: - UserProfileService

/// Service for managing the user's profile
@MainActor
final class UserProfileService {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = UserProfileService()

    /// Get the user's profile
    func getProfile() -> UserProfile? {
        do {
            let data = try keychain.read(for: KeychainHelper.Keys.userProfile)
            return try JSONDecoder().decode(UserProfile.self, from: data)
        } catch {
            return nil
        }
    }

    /// Save the user's profile
    func saveProfile(_ profile: UserProfile) throws {
        let data = try JSONEncoder().encode(profile)
        try keychain.save(data, for: KeychainHelper.Keys.userProfile)

        // Keep CallsignAliasService in sync
        let aliasService = CallsignAliasService.shared
        if aliasService.getCurrentCallsign() != profile.callsign {
            try aliasService.saveCurrentCallsign(profile.callsign)
        }

        // Update AppStorage values for license class and grid
        if let licenseClass = profile.licenseClass {
            UserDefaults.standard.set(licenseClass.rawValue, forKey: "userLicenseClass")
        }
        if let grid = profile.grid {
            UserDefaults.standard.set(grid, forKey: "loggerDefaultGrid")
        }
        UserDefaults.standard.set(profile.callsign, forKey: "loggerDefaultCallsign")
    }

    /// Clear the user's profile
    func clearProfile() throws {
        try keychain.delete(for: KeychainHelper.Keys.userProfile)
    }

    /// Check if a profile exists
    func hasProfile() -> Bool {
        getProfile() != nil
    }

    /// Look up a callsign via HamDB and create a profile
    func lookupAndCreateProfile(callsign: String) async throws -> UserProfile? {
        let client = HamDBClient()
        guard let license = try await client.lookup(callsign: callsign) else {
            // Callsign not found in HamDB - create minimal profile
            return UserProfile(callsign: callsign)
        }

        return UserProfile.fromHamDB(license)
    }

    // MARK: Private

    private let keychain = KeychainHelper.shared
}
