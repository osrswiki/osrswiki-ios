import Foundation
import SwiftUI

@MainActor
final class osrsNativeCalcSession: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case native
        case submitting
        case fallback
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var definition: osrsNativeCalcDefinitionModel?
    @Published var values: [String: String] = [:]
    @Published private(set) var introCopy: String = ""
    @Published private(set) var resultHTML: String = ""
    @Published private(set) var resultDocument: String = ""
    @Published private(set) var statusMessage: String = ""
    @Published private(set) var hiscoresError: String?
    @Published var fallbackReason: osrsNativeCalcFallbackReason?
    @Published var usesDarkTheme: Bool = false

    private var submitTask: Task<Void, Never>?
    private var pageTitle: String = ""

    static func calculatorTitle(pageTitle: String?, pageURL: URL) -> String {
        osrsArticleDocumentIdentity.requestedTitle(pageURL: pageURL, fallbackTitle: pageTitle)
    }

    static func shouldAttemptNativeChrome(title: String) -> Bool {
        osrsNativeCalcDefinition.spikeNativeTitles.contains(title)
    }

    func start(title: String, usesDarkTheme: Bool) {
        pageTitle = title
        self.usesDarkTheme = usesDarkTheme
        guard Self.shouldAttemptNativeChrome(title: title) else {
            fallbackReason = .unsupportedTitle
            phase = .fallback
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-osrsForceNativeCalcFallback") {
            fallbackReason = .missingConfig
            phase = .fallback
            return
        }
        phase = .loading
        statusMessage = "Loading calculator form…"
        Task { await loadDefinition() }
    }

    func setValue(_ name: String, _ value: String) {
        values[name] = value
        objectWillChange.send()
        scheduleSubmit()
    }

    func step(_ name: String, delta: Int) {
        let current = Int(values[name] ?? "") ?? 0
        let input = definition?.inputs.first { $0.name == name }
        var next = current + delta
        if let min = input?.minValue { next = max(min, next) }
        if let max = input?.maxValue { next = min(max, next) }
        setValue(name, String(next))
    }

    func visibleInputs() -> [osrsNativeCalcInput] {
        guard let definition else { return [] }
        return definition.inputs.filter { input in
            if input.type == .hidden || input.type == .fixed { return false }
            return isVisible(input.name)
        }
    }

    func isVisible(_ name: String) -> Bool {
        guard let definition else { return true }
        var visible = Set(definition.inputs.map(\.name))
        for input in definition.inputs where !input.toggles.isEmpty {
            let current = values[input.name] ?? input.defaultValue
            if let on = input.toggles[current] {
                on.forEach { visible.insert($0) }
                (input.toggleOff[current] ?? []).forEach { visible.remove($0) }
            } else {
                input.toggles.values.forEach { $0.forEach { visible.remove($0) } }
            }
        }
        return visible.contains(name)
    }

    func lookupHiscores() {
        guard let definition,
              let hs = definition.inputs.first(where: { $0.type == .hs }) else { return }
        let rawName = (values[hs.name] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawName.isEmpty else {
            hiscoresError = "Enter a player name to look up."
            return
        }
        hiscoresError = nil
        statusMessage = "Looking up hiscores…"
        Task {
            let player = rawName.replacingOccurrences(of: " ", with: "_")
            let result = await osrsCalculatorWikiClient.request(
                method: "GET",
                urlString: "/cors/m=hiscore_oldschool/index_lite.ws?player=\(player)",
                data: nil
            )
            guard (result["ok"] as? Bool) == true,
                  let body = result["body"] as? String,
                  !body.isEmpty else {
                hiscoresError = "Could not fetch hiscores for \(rawName)."
                statusMessage = ""
                return
            }
            applyHiscores(body, mapping: hs.range)
            statusMessage = ""
            scheduleSubmit()
        }
    }

    func submitNow() {
        submitTask?.cancel()
        Task { await submit() }
    }

    private func loadDefinition() async {
        let title = pageTitle
        let result = await osrsCalculatorWikiClient.request(
            method: "GET",
            urlString: "/api.php",
            data: [
                "action": "query",
                "prop": "revisions",
                "rvprop": "content|ids",
                "rvslots": "main",
                "titles": title,
                "format": "json"
            ]
        )
        guard (result["ok"] as? Bool) == true,
              let body = result["body"] as? String,
              let parsed = parseRevision(body, title: title),
              osrsNativeCalcDefinition.isNativeChromeEligible(parsed.definition) else {
            fallbackReason = osrsNativeCalcDefinition.fallbackReason(
                title: title,
                definition: nil
            ) ?? .missingConfig
            phase = .fallback
            return
        }
        definition = parsed.definition
        values = Dictionary(uniqueKeysWithValues: parsed.definition.inputs.map { ($0.name, $0.defaultValue) })
        introCopy = osrsNativeCalcDefinition.introCopy(from: parsed.wikitext)
        phase = .native
        statusMessage = ""
        await submit()
    }

    private func scheduleSubmit() {
        guard phase == .native || phase == .submitting else { return }
        submitTask?.cancel()
        submitTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await submit()
        }
    }

    private func submit() async {
        guard let definition,
              let wikitext = osrsNativeCalcDefinition.invokeWikitext(definition, values: values) else {
            fallbackReason = .missingConfig
            phase = .fallback
            return
        }
        if phase != .fallback {
            phase = .submitting
        }
        statusMessage = "Calculating…"
        let wikiTitle = osrsWikiWebViewUrl.mediaWikiPageConfig(
            canonicalTitle: pageTitle,
            displayTitle: pageTitle
        ).pageName
        let result = await osrsCalculatorWikiClient.request(
            method: "GET",
            urlString: "/api.php",
            data: [
                "action": "parse",
                "text": wikitext,
                "prop": "text",
                "title": wikiTitle,
                "disablelimitreport": "true",
                "contentmodel": "wikitext",
                "format": "json"
            ]
        )
        let html = parseHTML(from: result)
        if osrsNativeCalcDefinition.parseResultIsError(html) {
            fallbackReason = .parseError
            phase = .fallback
            statusMessage = ""
            return
        }
        resultHTML = html
        resultDocument = osrsNativeCalcDefinition.wrapResultHTML(html, dark: usesDarkTheme)
        phase = .native
        statusMessage = ""
    }

    private func applyHiscores(_ body: String, mapping: String) {
        let lines = body.split(whereSeparator: \.isNewline).map(String.init)
        for piece in mapping.split(separator: ";") {
            let parts = piece.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 3, let skill = Int(parts[1]), let field = Int(parts[2]) else { continue }
            guard skill >= 0, skill < lines.count else { continue }
            let cols = lines[skill].split(separator: ",").map(String.init)
            guard field >= 0, field < cols.count else { continue }
            values[parts[0]] = cols[field]
        }
    }

    private func parseRevision(_ body: String, title: String) -> (definition: osrsNativeCalcDefinitionModel, wikitext: String)? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let query = json["query"] as? [String: Any],
              let pages = query["pages"] as? [String: Any] else {
            return nil
        }
        for (_, raw) in pages {
            guard let page = raw as? [String: Any],
                  let revisions = page["revisions"] as? [[String: Any]],
                  let first = revisions.first else { continue }
            let wikitext: String
            if let slots = first["slots"] as? [String: Any],
               let main = slots["main"] as? [String: Any],
               let text = main["*"] as? String {
                wikitext = text
            } else if let text = first["*"] as? String {
                wikitext = text
            } else {
                continue
            }
            let pageId = page["pageid"] as? Int
            let revId = first["revid"] as? Int
            guard let definition = osrsNativeCalcDefinition.parse(
                wikitext,
                title: (page["title"] as? String) ?? title,
                pageId: pageId,
                revId: revId
            ) else { continue }
            return (definition, wikitext)
        }
        return nil
    }

    private func parseHTML(from result: [String: Any]) -> String {
        guard (result["ok"] as? Bool) == true,
              let body = result["body"] as? String,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let parse = json["parse"] as? [String: Any],
              let text = parse["text"] as? [String: Any],
              let html = text["*"] as? String else {
            return ""
        }
        return html
    }
}

extension osrsNativeCalcDefinition {
    static func introCopy(from wikitext: String) -> String {
        var lines: [String] = [
            "Enter your current Agility level or XP and a goal. Methods come from the live wiki calculator, not formulas shipped in the app."
        ]
        if let range = wikitext.range(of: "===Assumptions===") {
            let rest = wikitext[range.upperBound...]
            let end = rest.range(of: "===")?.lowerBound ?? rest.endIndex
            let block = rest[..<end]
            let bullets = block.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.hasPrefix("*") }
                .map { "• " + $0.dropFirst().trimmingCharacters(in: .whitespaces) }
            if !bullets.isEmpty {
                lines.append("")
                lines.append("Assumptions")
                lines.append(contentsOf: bullets)
            }
        }
        return lines.joined(separator: "\n")
    }

    static func wrapResultHTML(_ html: String, dark: Bool) -> String {
        let bg = dark ? "#28221d" : "#f4e0c8"
        let fg = dark ? "#f4eaea" : "#3A2E1C"
        let border = dark ? "#D2B48C" : "#4C3D2A"
        let link = dark ? "#b79d7e" : "#744e2f"
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>
        html, body { background: \(bg); color: \(fg); margin: 0; padding: 8px; font-family: -apple-system, BlinkMacSystemFont, "Alegreya", serif; }
        table { width: 100%; border-collapse: collapse; color: \(fg); background: transparent; }
        th, td { border: 1px solid \(border); padding: 6px; color: \(fg); vertical-align: middle; }
        th { text-align: left; }
        a { color: \(link); }
        img { max-height: 28px; width: auto; }
        .scribunto-error { color: #B00020; }
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """
    }
}
