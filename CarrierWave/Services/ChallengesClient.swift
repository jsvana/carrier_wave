import Foundation

// MARK: - ChallengesClient

actor ChallengesClient {
    // MARK: Lifecycle

    init(baseURL: String = "https://challenges.carrierwave.app/api") {
        self.baseURL = baseURL
    }

    // MARK: Internal

    nonisolated let keychain = KeychainHelper.shared

    // MARK: - Authentication

    func saveAuthToken(_ token: String) throws {
        try keychain.save(token, for: KeychainHelper.Keys.challengesAuthToken)
    }

    func getAuthToken() throws -> String {
        try keychain.readString(for: KeychainHelper.Keys.challengesAuthToken)
    }

    func hasAuthToken() -> Bool {
        do {
            _ = try keychain.readString(for: KeychainHelper.Keys.challengesAuthToken)
            return true
        } catch {
            return false
        }
    }

    func clearAuthToken() {
        try? keychain.delete(for: KeychainHelper.Keys.challengesAuthToken)
    }

    func saveCallsign(_ callsign: String) throws {
        try keychain.save(callsign, for: KeychainHelper.Keys.challengesCallsign)
    }

    func getCallsign() -> String? {
        try? keychain.readString(for: KeychainHelper.Keys.challengesCallsign)
    }

    func logout() {
        clearAuthToken()
        try? keychain.delete(for: KeychainHelper.Keys.challengesCallsign)
    }

    // MARK: - Challenge Sources

    /// Fetch challenges from a source URL
    func fetchChallenges(from sourceURL: String) async throws -> [ChallengeDefinitionDTO] {
        let url = try buildURL(sourceURL, path: "/challenges")
        let request = try buildRequest(url: url, method: "GET")

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)

        let listResponse = try JSONDecoder.challengesDecoder.decode(
            ChallengeListResponse.self,
            from: data
        )
        return listResponse.challenges
    }

    /// Fetch a single challenge definition
    func fetchChallenge(id: UUID, from sourceURL: String) async throws -> ChallengeDefinitionDTO {
        let url = try buildURL(sourceURL, path: "/challenges/\(id.uuidString)")
        let request = try buildRequest(url: url, method: "GET")

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)

        return try JSONDecoder.challengesDecoder.decode(
            ChallengeDefinitionDTO.self,
            from: data
        )
    }

    // MARK: - Participation

    /// Join a challenge
    func joinChallenge(
        id: UUID,
        sourceURL: String,
        token: String? = nil
    ) async throws -> JoinChallengeResponse {
        let authToken = try getAuthToken()
        guard let callsign = getCallsign() else {
            throw ChallengesError.notAuthenticated
        }

        let url = try buildURL(sourceURL, path: "/challenges/\(id.uuidString)/join")
        var request = try buildRequest(url: url, method: "POST", authToken: authToken)

        let joinRequest = JoinChallengeRequest(callsign: callsign, token: token)
        request.httpBody = try JSONEncoder().encode(joinRequest)

        let (data, response) = try await performRequest(request)

        // Handle specific error cases
        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200,
                 201:
                break
            case 404:
                throw ChallengesError.challengeNotFound
            case 409:
                throw ChallengesError.alreadyJoined
            case 410:
                throw ChallengesError.inviteExpired
            case 429:
                throw ChallengesError.inviteFull
            default:
                try validateResponse(response, data: data)
            }
        }

        return try JSONDecoder.challengesDecoder.decode(
            JoinChallengeResponse.self,
            from: data
        )
    }

    /// Leave a challenge
    func leaveChallenge(id: UUID, sourceURL: String) async throws {
        let authToken = try getAuthToken()

        let url = try buildURL(sourceURL, path: "/challenges/\(id.uuidString)/leave")
        let request = try buildRequest(url: url, method: "POST", authToken: authToken)

        let (data, response) = try await performRequest(request)

        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200,
                 204:
                return
            case 404:
                throw ChallengesError.notParticipating
            default:
                try validateResponse(response, data: data)
            }
        }
    }

    /// Report progress to server
    func reportProgress(
        participationId: UUID,
        progress: ChallengeProgress,
        sourceURL: String,
        challengeId: UUID
    ) async throws -> ProgressReportResponse {
        let authToken = try getAuthToken()

        let url = try buildURL(sourceURL, path: "/challenges/\(challengeId.uuidString)/progress")
        var request = try buildRequest(url: url, method: "POST", authToken: authToken)

        let reportRequest = ProgressReportRequest(
            participationId: participationId,
            progress: progress
        )
        request.httpBody = try JSONEncoder().encode(reportRequest)

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)

        return try JSONDecoder.challengesDecoder.decode(
            ProgressReportResponse.self,
            from: data
        )
    }

    // MARK: - Leaderboards

    /// Fetch leaderboard for a challenge
    func fetchLeaderboard(
        challengeId: UUID,
        sourceURL: String
    ) async throws -> LeaderboardResponse {
        let url = try buildURL(sourceURL, path: "/challenges/\(challengeId.uuidString)/leaderboard")
        let request = try buildRequest(url: url, method: "GET")

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)

        return try JSONDecoder.challengesDecoder.decode(
            LeaderboardResponse.self,
            from: data
        )
    }

    // MARK: - Invite Links

    /// Validate an invite token
    func validateInvite(token: String, sourceURL: String) async throws -> ChallengeDefinitionDTO {
        let url = try buildURL(sourceURL, path: "/invites/\(token)")
        let request = try buildRequest(url: url, method: "GET")

        let (data, response) = try await performRequest(request)

        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200:
                break
            case 404:
                throw ChallengesError.invalidInviteToken
            case 410:
                throw ChallengesError.inviteExpired
            default:
                try validateResponse(response, data: data)
            }
        }

        return try JSONDecoder.challengesDecoder.decode(
            ChallengeDefinitionDTO.self,
            from: data
        )
    }

    // MARK: Private

    private let baseURL: String
    private let userAgent = "CarrierWave/1.0"

    // MARK: - Request Building

    private func buildURL(_ base: String, path: String) throws -> URL {
        guard let url = URL(string: base + path) else {
            throw ChallengesError.invalidServerURL
        }
        return url
    }

    private func buildRequest(
        url: URL,
        method: String,
        authToken: String? = nil
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let authToken {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw ChallengesError.networkError(error)
        }
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChallengesError.invalidResponse("Not an HTTP response")
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)
            throw ChallengesError.serverError(httpResponse.statusCode, message)
        }
    }
}

// MARK: - JSON Decoder Extension

extension JSONDecoder {
    static let challengesDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

// MARK: - Keychain Keys Extension

extension KeychainHelper.Keys {
    static let challengesAuthToken = "challenges.auth.token"
    static let challengesCallsign = "challenges.callsign"
}
