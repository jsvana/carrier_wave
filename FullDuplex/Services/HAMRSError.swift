import Foundation

enum HAMRSError: Error, LocalizedError {
    case notConfigured
    case invalidApiKey
    case subscriptionInactive
    case networkError(Error)
    case invalidResponse(String)
    case decodingError(Error)
    case invalidCouchDBURL

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "HAMRS is not configured. Please enter your API key."
        case .invalidApiKey:
            return "Invalid API key. Check your HAMRS Pro settings at hamrs.app"
        case .subscriptionInactive:
            return "HAMRS Pro subscription is inactive. Visit hamrs.app to resubscribe."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse(let msg):
            return "Invalid response: \(msg)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .invalidCouchDBURL:
            return "Invalid CouchDB URL received from HAMRS"
        }
    }
}
