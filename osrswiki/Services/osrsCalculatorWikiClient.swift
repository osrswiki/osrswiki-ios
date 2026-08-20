import Foundation

enum osrsCalculatorWikiClient {
    static func request(method: String, urlString: String, data: Any?) async -> [String: Any] {
        let rewritten = absoluteWikiURL(from: urlString)
        let encoded = encode(data)
        var requestURL = rewritten
        var cacheBody = encoded.bodyText
        if method.uppercased() == "GET" {
            requestURL = appendQuery(rewritten, encoded.params)
            cacheBody = ""
        }
        let cacheable = requestURL.contains("/api.php") || requestURL.contains("/load.php")
        if cacheable,
           let cached = osrsCalculatorParseCache.read(method: method, url: requestURL, body: cacheBody),
           !cached.isEmpty,
           let body = String(data: cached, encoding: .utf8) {
            return ["ok": true, "body": body, "cached": true]
        }
        if osrsTestEnvironment.forcesNetworkOfflineForUITests {
            return ["ok": false, "error": "Forced offline: no cached calculator parse"]
        }
        do {
            var request = URLRequest(url: URL(string: requestURL) ?? URL(string: osrsWikiWebViewUrl.wikiOrigin)!)
            request.httpMethod = method.uppercased()
            request.setValue("OSRSWiki-iOS-Calculator", forHTTPHeaderField: "User-Agent")
            request.setValue("*/*", forHTTPHeaderField: "Accept")
            if method.uppercased() == "POST" {
                request.httpBody = encoded.bodyData
                request.setValue(
                    encoded.contentType,
                    forHTTPHeaderField: "Content-Type"
                )
            }
            let (responseData, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                return [
                    "ok": false,
                    "error": "http-\(http.statusCode)",
                    "body": String(data: responseData, encoding: .utf8) ?? ""
                ]
            }
            if requestURL.contains("/cors/"), responseData.isEmpty {
                return ["ok": false, "error": "empty-hiscores-response"]
            }
            if cacheable, !responseData.isEmpty {
                osrsCalculatorParseCache.write(method: method, url: requestURL, body: cacheBody, data: responseData)
            }
            return [
                "ok": true,
                "body": String(data: responseData, encoding: .utf8) ?? "",
                "cached": false
            ]
        } catch {
            return [
                "ok": false,
                "error": error.localizedDescription
            ]
        }
    }

    private static func absoluteWikiURL(from raw: String) -> String {
        if raw.hasPrefix("https://") || raw.hasPrefix("http://") || raw.hasPrefix("app-assets://") {
            if let url = URL(string: raw) {
                return osrsWikiWebViewUrl.rewriteToWiki(url).absoluteString
            }
        }
        if raw.hasPrefix("/") {
            return osrsWikiWebViewUrl.wikiOrigin + raw
        }
        return osrsWikiWebViewUrl.wikiOrigin + "/" + raw
    }

    private static func appendQuery(_ url: String, _ params: [String: String]) -> String {
        guard var components = URLComponents(string: url) else { return url }
        var items = components.queryItems ?? []
        params.keys.sorted().forEach { key in
            items.append(URLQueryItem(name: key, value: params[key]))
        }
        components.queryItems = items.isEmpty ? nil : items
        return components.url?.absoluteString ?? url
    }

    private struct EncodedBody {
        let params: [String: String]
        let bodyText: String
        let bodyData: Data
        let contentType: String
    }

    private static func encode(_ data: Any?) -> EncodedBody {
        var params: [String: String] = [:]
        if let dictionary = data as? [String: Any] {
            dictionary.forEach { key, value in
                params[key] = String(describing: value)
            }
        } else if let dictionary = data as? NSDictionary {
            dictionary.forEach { key, value in
                if let key = key as? String {
                    params[key] = String(describing: value)
                }
            }
        } else if let text = data as? String, !text.isEmpty {
            for pair in text.split(separator: "&") {
                let pieces = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                if !pieces.isEmpty {
                    params[String(pieces[0])] = pieces.count > 1 ? String(pieces[1]) : ""
                }
            }
        }
        let bodyText = params.keys.sorted().map { key in
            let value = params[key] ?? ""
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
        return EncodedBody(
            params: params,
            bodyText: bodyText,
            bodyData: Data(bodyText.utf8),
            contentType: "application/x-www-form-urlencoded; charset=UTF-8"
        )
    }
}
