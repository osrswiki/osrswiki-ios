//
//  osrsRandomPageRepository.swift
//  OSRS Wiki
//
//  Created on iOS development session for random page functionality
//

import Foundation

/**
 * Repository for fetching random pages from the OSRS Wiki.
 * iOS implementation matching Android's RandomPageRepository.kt functionality.
 */
class osrsRandomPageRepository {
    static let shared = osrsRandomPageRepository()
    
    private let randomURL = "https://oldschool.runescape.wiki/w/Special:RandomRootpage/main"
    
    private init() {}
    
    /**
     * Fetches a random page from the OSRS Wiki.
     * @return A Result containing the page title on success, or an error on failure.
     */
    func getRandomPage() async -> Result<String, Error> {
        do {
            // Create URLRequest for the random page endpoint
            guard let url = URL(string: randomURL) else {
                return .failure(NetworkError.invalidData)
            }
            
            // Create a custom URLRequest that follows redirects
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            
            // Use URLSession to follow redirects and get the final URL
            let (_, response) = try await URLSession.shared.data(for: request)
            
            // Get the final URL after redirects
            guard let httpResponse = response as? HTTPURLResponse,
                  let finalURL = httpResponse.url else {
                return .failure(NetworkError.invalidResponse)
            }
            
            let finalURLString = finalURL.absoluteString
            
            // Extract the page title from the final URL
            let pageTitle = extractPageTitle(from: finalURLString)
            
            if pageTitle.isEmpty {
                return .failure(NetworkError.invalidData)
            } else {
                return .success(pageTitle)
            }
        } catch let error as URLError {
            return .failure(NetworkError.from(error))
        } catch {
            return .failure(NetworkError.unknown(error))
        }
    }
    
    private func extractPageTitle(from url: String) -> String {
        // Extract the path segment after /w/
        let components = url.components(separatedBy: "/w/")
        guard components.count > 1 else { return "" }
        
        let wikiPath = components[1]
        
        // Skip Special: pages and other non-article pages
        if wikiPath.hasPrefix("Special:") ||
           wikiPath.hasPrefix("Category:") ||
           wikiPath.hasPrefix("File:") ||
           wikiPath.hasPrefix("Template:") {
            return ""
        }
        
        // Replace underscores with spaces and decode URL encoding
        let withSpaces = wikiPath.replacingOccurrences(of: "_", with: " ")
        
        // Decode URL encoding
        guard let decodedTitle = withSpaces.removingPercentEncoding else {
            return withSpaces
        }
        
        return decodedTitle
    }
}