import Foundation

enum ChallengesError: Error, LocalizedError {
    case notAuthenticated
    case invalidServerURL
    case networkError(Error)
    case invalidResponse(String)
    case serverError(Int, String?)
    case challengeNotFound
    case alreadyJoined
    case notParticipating
    case inviteExpired
    case inviteFull
    case invalidInviteToken

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "Not authenticated with challenge server"
        case .invalidServerURL:
            "Invalid challenge server URL"
        case let .networkError(error):
            "Network error: \(error.localizedDescription)"
        case let .invalidResponse(details):
            "Invalid response from server: \(details)"
        case let .serverError(code, message):
            if let message {
                "Server error (\(code)): \(message)"
            } else {
                "Server error: \(code)"
            }
        case .challengeNotFound:
            "Challenge not found"
        case .alreadyJoined:
            "Already participating in this challenge"
        case .notParticipating:
            "Not participating in this challenge"
        case .inviteExpired:
            "This invite link has expired"
        case .inviteFull:
            "This challenge has reached its participant limit"
        case .invalidInviteToken:
            "Invalid invite token"
        }
    }
}
