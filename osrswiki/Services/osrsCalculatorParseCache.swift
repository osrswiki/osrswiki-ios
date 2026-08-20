import Foundation
import CryptoKit

enum osrsCalculatorParseCache {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("calculator_parse", isDirectory: true)
    }

    static func canonical(method: String, url: String, body: String) -> (method: String, url: String, body: String) {
        guard var components = URLComponents(string: url) else {
            return (method.uppercased(), url, body)
        }
        let path = "\(components.scheme ?? "https")://\(components.host ?? osrsWikiWebViewUrl.wikiHost)\(components.path)"
        var params: [String: String] = [:]
        components.queryItems?.forEach { item in
            params[item.name] = item.value ?? ""
        }
        if !body.isEmpty {
            for pair in body.split(separator: "&") {
                let pieces = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let key = decodeComponent(String(pieces[0]))
                let value = pieces.count > 1 ? decodeComponent(String(pieces[1])) : ""
                if !key.isEmpty {
                    params[key] = value
                }
            }
        }
        let canonicalBody = params.keys.sorted().map { key in
            "\(key)=\(params[key] ?? "")"
        }.joined(separator: "&")
        return (method.uppercased(), path, canonicalBody)
    }

    static func key(method: String, url: String, body: String) -> String {
        let canonicalRequest = canonical(method: method, url: url, body: body)
        let material = "\(canonicalRequest.method)\n\(canonicalRequest.url)\n\(canonicalRequest.body)"
        let digest = SHA256.hash(data: Data(material.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func read(method: String, url: String, body: String) -> Data? {
        let file = directory.appendingPathComponent(key(method: method, url: url, body: body) + ".bin")
        return try? Data(contentsOf: file)
    }

    static func write(method: String, url: String, body: String, data: Data) {
        let dir = directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(key(method: method, url: url, body: body) + ".bin")
        try? data.write(to: file, options: .atomic)
    }

    private static func decodeComponent(_ raw: String) -> String {
        raw.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? raw
    }
}
