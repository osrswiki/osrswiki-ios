import Foundation

enum UserFacingError {
    static func message(for error: Error, fallback: String = "Something went wrong. Please try again.") -> String {
        if let networkError = error as? NetworkError { return networkError.userMessage }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return "Please check your internet connection and try again."
            case .timedOut:
                return "That took too long. Please try again."
            default:
                break
            }
        }
        return fallback
    }
}
