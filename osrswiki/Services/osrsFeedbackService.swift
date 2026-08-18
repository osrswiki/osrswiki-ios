//
//  osrsFeedbackService.swift
//  OSRS Wiki
//
//  Created for iOS feedback parity implementation
//

import Foundation
import UIKit

/// Service for securely submitting feedback via Google Cloud Function.
/// This approach keeps the GitHub API token secure on the server side and routes
/// iOS feedback to the appropriate repository (osrswiki-ios).
class osrsFeedbackService {
    
    static let shared = osrsFeedbackService()
    
    private static let defaultCloudFunctionURL = URL(string: "https://us-central1-osrs-459713.cloudfunctions.net/createGithubIssue")!
    private let cloudFunctionURL: URL
    private let session: URLSession
    private let systemInfoProvider: () -> osrsFeedbackSystemInfo
    
    init(
        session: URLSession = .shared,
        cloudFunctionURL: URL = osrsFeedbackService.defaultCloudFunctionURL,
        systemInfoProvider: @escaping () -> osrsFeedbackSystemInfo = osrsFeedbackSystemInfo.current
    ) {
        self.session = session
        self.cloudFunctionURL = cloudFunctionURL
        self.systemInfoProvider = systemInfoProvider
    }
    
    /// Creates a bug report issue via secure Cloud Function
    func reportIssue(
        title: String,
        description: String,
        includeSystemInfo: Bool = true
    ) async -> Result<String, Error> {
        return await submitFeedback(
            title: title,
            description: description,
            label: "bug",
            includeSystemInfo: includeSystemInfo
        )
    }
    
    /// Creates a feature request issue via secure Cloud Function
    func requestFeature(
        title: String,
        description: String,
        includeSystemInfo: Bool = true
    ) async -> Result<String, Error> {
        return await submitFeedback(
            title: title,
            description: description,
            label: "enhancement",
            includeSystemInfo: includeSystemInfo
        )
    }
    
    /// Creates a general feedback issue via secure Cloud Function
    func submitGeneralFeedback(
        title: String,
        description: String,
        includeSystemInfo: Bool = true
    ) async -> Result<String, Error> {
        return await submitFeedback(
            title: title,
            description: description,
            label: "feedback",
            includeSystemInfo: includeSystemInfo
        )
    }
    
    func makeIssueRequest(
        title: String,
        description: String,
        label: String,
        includeSystemInfo: Bool
    ) throws -> osrsCloudFunctionIssueRequest {
        let body: String
        if includeSystemInfo {
            body = """
            \(description)
            
            ---
            **Device Information:**
            \(systemInfoProvider().formattedForFeedback)
            """
        } else {
            body = description
        }

        return osrsCloudFunctionIssueRequest(
            title: title,
            body: body,
            labels: [label],
            platform: "ios"
        )
    }

    private func submitFeedback(
        title: String,
        description: String,
        label: String,
        includeSystemInfo: Bool
    ) async -> Result<String, Error> {
        do {
            let requestBody = try makeIssueRequest(
                title: title,
                description: description,
                label: label,
                includeSystemInfo: includeSystemInfo
            )
            
            let jsonData = try JSONEncoder().encode(requestBody)

            var request = URLRequest(url: cloudFunctionURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("OSRSWikiApp-iOS/\(getAppVersion())", forHTTPHeaderField: "User-Agent")
            request.httpBody = jsonData
            
            print("osrsFeedbackService: Submitting feedback via Cloud Function for iOS")
            
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(osrsFeedbackError.invalidResponse)
            }
            
            switch httpResponse.statusCode {
            case 200:
                if let responseData = try? JSONDecoder().decode(osrsCloudFunctionResponse.self, from: data) {
                    print("osrsFeedbackService: Feedback submitted successfully: \(responseData.message)")
                    return .success("Your feedback has been submitted successfully!")
                } else {
                    return .success("Your feedback has been submitted successfully!")
                }
            case 400:
                return .failure(osrsFeedbackError.invalidRequest)
            case 500:
                return .failure(osrsFeedbackError.serverError)
            default:
                return .failure(osrsFeedbackError.httpError(httpResponse.statusCode))
            }
            
        } catch {
            print("osrsFeedbackService: Error submitting feedback - \(error)")
            
            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet:
                    return .failure(osrsFeedbackError.noInternetConnection)
                case .timedOut:
                    return .failure(osrsFeedbackError.timeout)
                default:
                    return .failure(osrsFeedbackError.networkError(urlError))
                }
            } else {
                return .failure(osrsFeedbackError.unexpectedError(error))
            }
        }
    }

    private func getAppVersion() -> String {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(appVersion).\(buildNumber)"
    }
}

// MARK: - Data Models

struct osrsFeedbackSystemInfo: Equatable {
    let appVersion: String
    let buildNumber: String
    let systemVersion: String
    let deviceModel: String
    let systemName: String

    static func current() -> osrsFeedbackSystemInfo {
        let device = UIDevice.current
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"

        return osrsFeedbackSystemInfo(
            appVersion: appVersion,
            buildNumber: buildNumber,
            systemVersion: device.systemVersion,
            deviceModel: device.model,
            systemName: device.systemName
        )
    }

    var formattedForFeedback: String {
        """
        - App Version: \(appVersion) (\(buildNumber))
        - iOS Version: \(systemVersion)
        - Device: \(deviceModel)
        - System Name: \(systemName)
        """
    }
}

struct osrsCloudFunctionIssueRequest: Codable {
    let title: String
    let body: String
    let labels: [String]?
    let platform: String
}

struct osrsCloudFunctionResponse: Codable {
    let message: String
}

// MARK: - Error Types

enum osrsFeedbackError: Error, LocalizedError {
    case invalidURL
    case invalidRequest
    case serverError
    case httpError(Int)
    case invalidResponse
    case noInternetConnection
    case timeout
    case networkError(URLError)
    case unexpectedError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Feedback could not be sent. Please try again."
        case .invalidRequest:
            return "Feedback could not be sent. Please check your input and try again."
        case .serverError:
            return "Server error. Please try again later."
        case .httpError(let code):
            _ = code
            return "Feedback could not be sent. Please try again."
        case .invalidResponse:
            return "Feedback could not be sent. Please try again."
        case .noInternetConnection:
            return "No internet connection. Please check your network."
        case .timeout:
            return "Request timed out. Please try again."
        case .networkError(let urlError):
            _ = urlError
            return "Feedback could not be sent. Please check your connection and try again."
        case .unexpectedError(let error):
            _ = error
            return "Feedback could not be sent. Please try again."
        }
    }
}
