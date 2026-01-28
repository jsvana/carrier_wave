import Foundation

// MARK: - ChallengesClient Clubs Extension

extension ChallengesClient {
    // MARK: - Club Endpoints

    /// Get list of clubs the user belongs to
    func getMyClubs(sourceURL: String, authToken: String) async throws -> [ClubDTO] {
        guard let url = URL(string: sourceURL + "/v1/clubs") else {
            throw ChallengesError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await performClubRequest(request)
        try validateClubResponse(response, data: data)

        let apiResponse = try JSONDecoder.challengesDecoder.decode(
            APIResponse<[ClubDTO]>.self,
            from: data
        )
        return apiResponse.data
    }

    /// Get detailed information about a specific club
    func getClubDetails(
        clubId: UUID,
        sourceURL: String,
        authToken: String,
        includeMembers: Bool = true
    ) async throws -> ClubDetailDTO {
        guard var components = URLComponents(string: sourceURL + "/v1/clubs/\(clubId.uuidString)") else {
            throw ChallengesError.invalidServerURL
        }

        components.queryItems = [URLQueryItem(name: "includeMembers", value: String(includeMembers))]

        guard let url = components.url else {
            throw ChallengesError.invalidServerURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await performClubRequest(request)
        try validateClubResponse(response, data: data)

        let apiResponse = try JSONDecoder.challengesDecoder.decode(
            APIResponse<ClubDetailDTO>.self,
            from: data
        )
        return apiResponse.data
    }

    // MARK: - Private Helpers

    private func performClubRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw ChallengesError.networkError(error)
        }
    }

    private func validateClubResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChallengesError.invalidResponse("Not an HTTP response")
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            if let errorResponse = try? JSONDecoder.challengesDecoder.decode(
                APIErrorResponse.self,
                from: data
            ) {
                throw ChallengesError.from(
                    apiCode: errorResponse.error.code,
                    message: errorResponse.error.message
                )
            }

            let message = String(data: data, encoding: .utf8)
            throw ChallengesError.serverError(httpResponse.statusCode, message)
        }
    }
}

// MARK: - ClubDTO

struct ClubDTO: Codable {
    var id: UUID
    var name: String
    var description: String?
    var memberCount: Int
    var poloNotesListId: String?
}

// MARK: - ClubDetailDTO

struct ClubDetailDTO: Codable {
    var id: UUID
    var name: String
    var description: String?
    var poloNotesListURL: String?
    var memberCount: Int
    var lastSyncedAt: Date?
    var members: [ClubMemberDTO]?
}

// MARK: - ClubMemberDTO

struct ClubMemberDTO: Codable {
    var callsign: String
    var userId: String?
    var isCarrierWaveUser: Bool
}
