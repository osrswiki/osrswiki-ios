import Foundation

enum osrsSrcsetParser {
    struct Candidate {
        let url: String
        let descriptor: String
    }

    static func urls(from srcset: String) -> [String] {
        parse(srcset).map(\.url)
    }

    /// One density URL for a slot. Does not return both a 1x (140px) and 2x (280px) candidate.
    static func choose(
        src: String?,
        srcset: String?,
        widthPx: Int? = nil,
        devicePixelRatio: CGFloat = 2
    ) -> String? {
        let trimmedSrc = src?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let srcURL: String? = {
            if trimmedSrc.isEmpty || trimmedSrc.lowercased().hasPrefix("data:") { return nil }
            return trimmedSrc
        }()
        var candidates: [String: Candidate] = [:]
        if let srcURL {
            candidates[srcURL] = Candidate(url: srcURL, descriptor: "1x")
        }
        for candidate in parse(srcset ?? "") {
            if candidate.url.isEmpty || candidate.url.lowercased().hasPrefix("data:") {
                continue
            }
            candidates[candidate.url] = candidate
        }
        let list = Array(candidates.values)
        if list.isEmpty { return nil }
        if list.count == 1 { return list[0].url }
        let dpr = max(devicePixelRatio, 1)
        let xCandidates: [(Candidate, CGFloat)] = list.compactMap { candidate in
            guard let density = xDensity(candidate) else { return nil }
            return (candidate, density)
        }
        if !xCandidates.isEmpty {
            let meeting = xCandidates.filter { $0.1 >= dpr }
            let pick = meeting.min(by: { $0.1 < $1.1 }) ?? xCandidates.max(by: { $0.1 < $1.1 })
            return pick?.0.url
        }
        let wCandidates: [(Candidate, CGFloat)] = list.compactMap { candidate in
            guard let width = wDescriptor(candidate) else { return nil }
            return (candidate, width)
        }
        if !wCandidates.isEmpty, let layoutWidth = widthPx, layoutWidth > 0 {
            let needed = CGFloat(layoutWidth) * dpr
            let meeting = wCandidates.filter { $0.1 >= needed }
            let pick = meeting.min(by: { $0.1 < $1.1 }) ?? wCandidates.max(by: { $0.1 < $1.1 })
            return pick?.0.url
        }
        return list.last?.url
    }

    private static func parse(_ srcset: String) -> [Candidate] {
        var candidates: [Candidate] = []
        var index = srcset.startIndex
        while index < srcset.endIndex {
            while index < srcset.endIndex, srcset[index].isWhitespace || srcset[index] == "," {
                index = srcset.index(after: index)
            }
            if index >= srcset.endIndex { break }
            let quoted = srcset[index] == "'" || srcset[index] == "\""
            let quote = quoted ? srcset[index] : nil
            if quoted { index = srcset.index(after: index) }
            let urlStart = index
            let isData = srcset[index...].lowercased().hasPrefix("data:")
            while index < srcset.endIndex {
                let character = srcset[index]
                if (quote != nil && character == quote) ||
                    (quote == nil && character.isWhitespace) ||
                    (quote == nil && !isData && character == ",") {
                    break
                }
                index = srcset.index(after: index)
            }
            let url = String(srcset[urlStart..<index]).trimmingCharacters(in: .whitespaces)
            if quote != nil, index < srcset.endIndex, srcset[index] == quote {
                index = srcset.index(after: index)
            }
            while index < srcset.endIndex, srcset[index].isWhitespace {
                index = srcset.index(after: index)
            }
            let descriptorStart = index
            while index < srcset.endIndex, srcset[index] != "," {
                index = srcset.index(after: index)
            }
            let descriptor = String(srcset[descriptorStart..<index]).trimmingCharacters(in: .whitespaces)
            if index < srcset.endIndex, srcset[index] == "," {
                index = srcset.index(after: index)
            }
            if !url.isEmpty {
                candidates.append(Candidate(url: url, descriptor: descriptor))
            }
        }
        return candidates
    }

    private static func xDensity(_ candidate: Candidate) -> CGFloat? {
        let descriptor = candidate.descriptor.trimmingCharacters(in: .whitespaces)
        if descriptor.isEmpty { return 1 }
        return numericPrefix(descriptor, suffix: "x")
    }

    private static func wDescriptor(_ candidate: Candidate) -> CGFloat? {
        let descriptor = candidate.descriptor.trimmingCharacters(in: .whitespaces)
        return numericPrefix(descriptor, suffix: "w")
    }

    private static func numericPrefix(_ descriptor: String, suffix: Character) -> CGFloat? {
        guard descriptor.lowercased().hasSuffix(String(suffix)),
              !descriptor.isEmpty else { return nil }
        let end = descriptor.index(before: descriptor.endIndex)
        guard let value = Double(String(descriptor[..<end])) else { return nil }
        return CGFloat(value)
    }
}
