//
//  NetworkError.swift
//  OSRS Wiki
//
//  Standardized network error handling for consistent error messaging and recovery
//

import Foundation
import Network

/// Standardized network errors with user-friendly messages and recovery options
enum NetworkError: LocalizedError {
    case noConnection
    case connectionLost
    case timeout
    case serverError(Int)
    case pageNotFound(String?)
    case invalidResponse
    case invalidData
    case rateLimited
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
        case .noConnection:
            return "No internet connection available"
        case .connectionLost:
            return "Connection lost during request"
        case .timeout:
            return "Request timed out"
        case .serverError(let code):
            return "Server error (\(code))"
        case .pageNotFound(let title):
            if let title, !title.isEmpty {
                return "Page not found: \(title)"
            }
            return "Page not found"
        case .invalidResponse:
            return "Invalid server response"
        case .invalidData:
            return "Unable to process server data"
        case .rateLimited:
            return "Too many requests. Please try again later."
        case .unknown(let error):
            return error.localizedDescription
        }
    }
    
    /// User-friendly message for display in UI
    var userMessage: String {
        switch self {
        case .noConnection, .connectionLost:
            return "Please check your internet connection and try again."
        case .timeout:
            return "The request took too long. Please try again."
        case .serverError(_):
            return "The server is experiencing issues. Please try again later."
        case .pageNotFound(let title):
            if let title, !title.isEmpty {
                return "\"\(title)\" could not be found."
            }
            return "That page could not be found."
        case .invalidResponse, .invalidData:
            return "Something went wrong. Please try again."
        case .rateLimited:
            return "You're making requests too quickly. Please wait a moment and try again."
        case .unknown(_):
            return "An unexpected error occurred. Please try again."
        }
    }
    
    /// Whether this error suggests the user should retry
    var isRetryable: Bool {
        switch self {
        case .noConnection, .connectionLost, .timeout, .serverError(_), .unknown(_):
            return true
        case .pageNotFound, .invalidResponse, .invalidData, .rateLimited:
            return false
        }
    }
    
    /// Whether this error indicates an offline state
    var isOfflineError: Bool {
        switch self {
        case .noConnection, .connectionLost:
            return true
        default:
            return false
        }
    }
    
    /// Create NetworkError from URLError
    static func from(_ urlError: URLError) -> NetworkError {
        switch urlError.code {
        case .notConnectedToInternet, .dataNotAllowed, .networkConnectionLost:
            return .noConnection
        case .timedOut:
            return .timeout
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return .connectionLost
        default:
            return .unknown(urlError)
        }
    }
    
    /// Create NetworkError from HTTP response
    static func from(httpStatusCode: Int) -> NetworkError {
        switch httpStatusCode {
        case 429:
            return .rateLimited
        case 500...599:
            return .serverError(httpStatusCode)
        default:
            return .invalidResponse
        }
    }
}
