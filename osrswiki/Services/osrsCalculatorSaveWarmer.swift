import Foundation

enum osrsCalculatorSaveWarmer {
    static func defaultTemplateCall(from html: String) -> String? {
        guard let config = firstConfig(in: html) else { return nil }
        let paramsRegex = try? NSRegularExpression(
            pattern: #"(?i)\bparam\s*=\s*([^|\n]+)\|([^|\n]*)\|([^|\n]*)\|([^|\n]*)"#
        )
        var wikitext: String
        if let module = firstMatch(
            #"(?i)\bmodule\s*=\s*(.+?)(?=\s+(?:form|result|param|name|autosubmit|modulefunc|template)\b|$)"#,
            in: config
        ) {
            let funcName = firstMatch(#"(?i)\bmodulefunc\s*=\s*(\S+)"#, in: config) ?? "main"
            wikitext = "{{#invoke:\(module.trimmingCharacters(in: .whitespacesAndNewlines))|\(funcName.trimmingCharacters(in: .whitespacesAndNewlines))"
        } else if let template = firstMatch(
            #"(?i)\btemplate\s*=\s*(.+?)(?=\s+(?:form|result|param|name|autosubmit|module|modulefunc)\b|$)"#,
            in: config
        ) {
            wikitext = "{{\(template.trimmingCharacters(in: .whitespacesAndNewlines))"
        } else {
            return nil
        }
        let range = NSRange(config.startIndex..<config.endIndex, in: config)
        paramsRegex?.enumerateMatches(in: config, range: range) { match, _, _ in
            guard let match,
                  let nameRange = Range(match.range(at: 1), in: config),
                  let initialRange = Range(match.range(at: 3), in: config),
                  let typeRange = Range(match.range(at: 4), in: config) else {
                return
            }
            let name = String(config[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let initial = String(config[initialRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let type = String(config[typeRange]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if name.isEmpty || type == "hidden" || type == "hs" || type == "rsn" {
                return
            }
            wikitext += "|\(name)=\(initial)"
        }
        wikitext += "}}"
        return wikitext
    }

    static func warmDefaultParse(from html: String, pageTitle: String? = nil) async {
        guard let wikitext = defaultTemplateCall(from: html) else {
            return
        }
        let wikiTitle = osrsWikiWebViewUrl.mediaWikiPageConfig(
            canonicalTitle: pageTitle ?? "Calculator",
            displayTitle: pageTitle ?? "Calculator"
        ).pageName
        let result = await osrsCalculatorWikiClient.request(
            method: "GET",
            urlString: "/api.php",
            data: [
                "action": "parse",
                "text": wikitext,
                "prop": "text|limitreportdata",
                "title": wikiTitle,
                "disablelimitreport": "true",
                "contentmodel": "wikitext",
                "format": "json"
            ]
        )
        if let error = result["error"] as? String {
            print("osrsCalculatorSaveWarmer: failed to warm default parse: \(error)")
        }
    }

    private static func firstConfig(in html: String) -> String? {
        if let pre = firstMatch(#"(?is)<pre[^>]*class="[^"]*jcConfig[^"]*"[^>]*>(.*?)</pre>"#, in: html) {
            return pre
        }
        guard let regex = try? NSRegularExpression(
            pattern: #"(?is)(?:^|\n)\s*(?:template|module)\s*=.+?(?=\n\s*(?:\{\||----|<pre|$))"#
        ) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let matched = Range(match.range, in: html) else {
            return nil
        }
        return String(html[matched])
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let captured = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captured])
    }
}
