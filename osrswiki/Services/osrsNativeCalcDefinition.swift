import Foundation

enum osrsNativeCalcParamType: String, Equatable {
    case string
    case int
    case number
    case select
    case buttonSelect = "buttonselect"
    case check
    case toggleSwitch = "toggleswitch"
    case toggleButton = "togglebutton"
    case toggleButtonGroup = "togglebuttongroup"
    case combobox
    case group
    case hs
    case rsn
    case hidden
    case fixed
    case semiHidden = "semihidden"
    case unknown
}

enum osrsNativeCalcFallbackReason: String, Equatable {
    case missingConfig
    case unknownParamType
    case parseError
    case unsupportedTitle
}

struct osrsNativeCalcInvoke: Equatable {
    enum Kind: String {
        case template
        case module
    }

    var kind: Kind
    var template: String?
    var module: String?
    var moduleFunc: String?
}

struct osrsNativeCalcUI: Equatable {
    var name: String
    var formId: String
    var resultId: String
    var autosubmit: String
}

struct osrsNativeCalcInput: Equatable {
    var name: String
    var label: String
    var defaultValue: String
    var type: osrsNativeCalcParamType
    var range: String
    var options: [String]
    var toggles: [String: [String]]
    var toggleOff: [String: [String]]
    var minValue: Int?
    var maxValue: Int?
    var help: String = ""
}

struct osrsNativeCalcDefinitionModel: Equatable {
    var schemaVersion: Int
    var id: String
    var pageId: Int?
    var revId: Int?
    var wikiOrigin: String
    var family: String
    var ui: osrsNativeCalcUI
    var invoke: osrsNativeCalcInvoke
    var inputs: [osrsNativeCalcInput]
    var unknownTypes: [String]
}

enum osrsNativeCalcDefinition {
    static let kitTypes: Set<osrsNativeCalcParamType> = [
        .string, .int, .number, .select, .buttonSelect, .check,
        .toggleSwitch, .toggleButton, .toggleButtonGroup, .combobox, .group,
        .hs, .rsn, .hidden, .fixed, .semiHidden
    ]

    static func normalizeAutosubmit(_ raw: String?) -> String {
        let value = (raw ?? "off").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.isEmpty || value == "off" || value == "disabled" || value == "false" {
            return "off"
        }
        if value == "enabled" || value == "on" || value == "true" {
            return "on"
        }
        return "on"
    }

    static func countJcConfigs(in html: String?) -> Int {
        guard let html, !html.isEmpty else { return 0 }
        guard let regex = try? NSRegularExpression(pattern: #"(?i)<(?:pre|div)[^>]*class="[^"]*jcConfig[^"]*""#) else {
            return 0
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.numberOfMatches(in: html, options: [], range: range)
    }

    static func parse(_ text: String, title: String? = nil, pageId: Int? = nil, revId: Int? = nil) -> osrsNativeCalcDefinitionModel? {
        guard let config = firstConfig(in: text) else { return nil }
        var ui = osrsNativeCalcUI(name: "Calculator", formId: "", resultId: "", autosubmit: "off")
        var invokeKind: osrsNativeCalcInvoke.Kind?
        var template: String?
        var module: String?
        var moduleFunc: String?
        var inputs: [osrsNativeCalcInput] = []
        var unknownTypes: [String] = []
        for rawLine in configLines(config) {
            let line = rawLine
            guard let (key, value) = splitConfigLine(line) else { continue }
            if key != "param" {
                switch key {
                case "form": ui.formId = value
                case "result": ui.resultId = value
                case "name": if !value.isEmpty { ui.name = value }
                case "autosubmit": ui.autosubmit = normalizeAutosubmit(value)
                case "template":
                    invokeKind = .template
                    template = value
                case "module":
                    invokeKind = .module
                    module = value
                case "modulefunc":
                    moduleFunc = value.isEmpty ? "main" : value
                default:
                    break
                }
                continue
            }
            var fields = value.split(separator: "|", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            while fields.count < 6 { fields.append("") }
            let name = fields[0]
            guard !name.isEmpty else { continue }
            let label = fields[1].isEmpty ? name : fields[1]
            var defaultValue = fields[2]
            let rawType = fields[3].lowercased()
            let range = fields[4]
            let rawToggles = fields[5]
            let help = parseHelp(fields)
            let type = osrsNativeCalcParamType(rawValue: rawType) ?? .unknown
            if type == .unknown, !rawType.isEmpty {
                unknownTypes.append(rawType)
            }
            let toggleDefault: String
            if type == .toggleSwitch || type == .toggleButton || type == .check {
                toggleDefault = "true"
            } else {
                toggleDefault = defaultValue.isEmpty ? name : defaultValue
            }
            if type == .toggleSwitch, defaultValue.isEmpty {
                defaultValue = "false"
            }
            let parsedToggles = parseToggles(rawToggles, defaultKey: toggleDefault)
            let intBounds = intRange(range, type: type)
            inputs.append(
                osrsNativeCalcInput(
                    name: name,
                    label: label,
                    defaultValue: defaultValue,
                    type: type,
                    range: range,
                    options: options(for: type, range: range),
                    toggles: parsedToggles.on,
                    toggleOff: parsedToggles.off,
                    minValue: intBounds.min,
                    maxValue: intBounds.max,
                    help: help
                )
            )
        }
        guard let kind = invokeKind else { return nil }
        if kind == .module, (moduleFunc == nil || moduleFunc?.isEmpty == true) {
            moduleFunc = "main"
        }
        let calcId = title ?? ui.name
        let family = (template ?? "").hasPrefix("Calculator:Skill calc/") ? "skill-calc-shared-template" : "jcconfig"
        return osrsNativeCalcDefinitionModel(
            schemaVersion: 1,
            id: calcId,
            pageId: pageId,
            revId: revId,
            wikiOrigin: osrsWikiWebViewUrl.wikiOrigin,
            family: family,
            ui: ui,
            invoke: osrsNativeCalcInvoke(kind: kind, template: template, module: module, moduleFunc: moduleFunc),
            inputs: inputs,
            unknownTypes: unknownTypes
        )
    }

    static func isNativeChromeEligible(_ definition: osrsNativeCalcDefinitionModel?) -> Bool {
        guard let definition else { return false }
        switch definition.invoke.kind {
        case .template:
            if (definition.invoke.template ?? "").isEmpty { return false }
        case .module:
            if (definition.invoke.module ?? "").isEmpty { return false }
        }
        if !definition.unknownTypes.isEmpty { return false }
        if definition.inputs.isEmpty { return false }
        return definition.inputs.allSatisfy { kitTypes.contains($0.type) }
    }

    static func isPageNativeChromeEligible(_ html: String?, title: String? = nil) -> Bool {
        guard let html, countJcConfigs(in: html) == 1 else { return false }
        return isNativeChromeEligible(parse(html, title: title))
    }

    static func invokeWikitext(
        _ definition: osrsNativeCalcDefinitionModel?,
        values: [String: String] = [:]
    ) -> String? {
        guard let definition else { return nil }
        var parts: [String]
        switch definition.invoke.kind {
        case .module:
            let module = (definition.invoke.module ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let funcName = (definition.invoke.moduleFunc ?? "main").trimmingCharacters(in: .whitespacesAndNewlines)
            if module.isEmpty { return nil }
            parts = ["{{#invoke:\(module)|\(funcName.isEmpty ? "main" : funcName)"]
        case .template:
            let template = (definition.invoke.template ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if template.isEmpty { return nil }
            parts = ["{{\(template)"]
        }
        var merged: [String: String] = [:]
        for input in definition.inputs {
            merged[input.name] = input.defaultValue
        }
        for (key, value) in values {
            merged[key] = value
        }
        let visible = visibleInputNames(definition, values: merged)
        for input in definition.inputs {
            if input.type == .unknown || input.type == .group { continue }
            let always = input.type == .hidden || input.type == .fixed
            if !always && !visible.contains(input.name) { continue }
            var value = merged[input.name] ?? ""
            if (input.type == .hs || input.type == .rsn) && value.isEmpty { continue }
            if input.type == .toggleSwitch {
                value = boolToken(value)
            }
            if input.type == .check {
                value = checkToken(input, on: checkIsOn(input, value))
            }
            if input.type == .toggleButtonGroup {
                value = csvTokens(value).joined(separator: ",")
            }
            parts.append("|\(input.name)=\(value)")
        }
        parts.append("}}")
        return parts.joined()
    }

    static func chromeTitle(for calcId: String) -> String {
        var rest = calcId
        if rest.hasPrefix("Calculator:") {
            rest = String(rest.dropFirst("Calculator:".count))
        }
        rest = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        if rest.isEmpty { rest = "Calculator" }
        if rest.lowercased().hasSuffix("calculator") {
            return rest
        }
        return "\(rest) calculator"
    }

    static func parseResultIsError(_ html: String?) -> Bool {
        let body = html ?? ""
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        let lowered = body.lowercased()
        return lowered.contains("scribunto-error") || lowered.contains("lua error")
    }

    static func hiscoresUnavailableMessage(player: String) -> String {
        let name = player.trimmingCharacters(in: .whitespacesAndNewlines)
        return "The player \"\(name)\" does not exist, is banned or unranked, or we couldn't fetch your hiscores. Please enter the data manually."
    }

    static func parseFailureMessage(_ html: String?) -> String {
        let body = (html ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = body.range(of: "Lua error[^<]*", options: [.regularExpression, .caseInsensitive]) {
            let extracted = String(body[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !extracted.isEmpty { return extracted }
        }
        return "The wiki could not calculate a result. Please check your inputs and try again."
    }

    static func shouldAutosubmitOnEdit(_ type: osrsNativeCalcParamType) -> Bool {
        switch type {
        case .hs, .rsn, .string, .group:
            return false
        default:
            return true
        }
    }

    static func jsonEscape(_ value: String) -> String {
        let data = (try? JSONSerialization.data(
            withJSONObject: value,
            options: [.fragmentsAllowed]
        )) ?? Data("\"\"".utf8)
        return String(data: data, encoding: .utf8) ?? "\"\""
    }

    static func installSlotJavaScript(formId: String, resultId: String, height: Int) -> String {
        let payload: [String: Any] = [
            "formId": formId,
            "resultId": resultId,
            "height": max(1, height)
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [])) ?? Data("{}".utf8)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return "window.osrsInstallNativeCalcSlot && window.osrsInstallNativeCalcSlot(\(json))"
    }

    static func setSlotHeightJavaScript(_ height: Int) -> String {
        "window.osrsNativeCalcSetSlotHeight && window.osrsNativeCalcSetSlotHeight(\(max(1, height)))"
    }

    static func setResultJavaScript(resultId: String, html: String) -> String {
        "window.osrsNativeCalcSetResult && window.osrsNativeCalcSetResult(\(jsonEscape(resultId)), \(jsonEscape(html)))"
    }

    static func uninstallSlotJavaScript() -> String {
        "window.osrsUninstallNativeCalcSlot && window.osrsUninstallNativeCalcSlot()"
    }

    enum HiscoresLookup: Equatable {
        case applied([String: String])
        case failed(String)
    }

    static func interpretHiscoresLookup(
        ok: Bool,
        body: String,
        player: String,
        mapping: String
    ) -> HiscoresLookup {
        guard ok, let applied = applyHiscores(body: body, mapping: mapping), !applied.isEmpty else {
            return .failed(hiscoresUnavailableMessage(player: player))
        }
        return .applied(applied)
    }

    static func applyHiscores(body: String, mapping: String) -> [String: String]? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lowered = trimmed.lowercased()
        if lowered.contains("<html") || lowered.contains("<!doctype") { return nil }
        let lines = trimmed.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.count > 1 else { return nil }
        var updates: [String: String] = [:]
        for piece in mapping.split(separator: ";") {
            let parts = piece.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 3, let skill = Int(parts[1]), let field = Int(parts[2]) else { continue }
            guard skill >= 0, skill < lines.count else { continue }
            let cols = lines[skill].split(separator: ",").map(String.init)
            guard field >= 0, field < cols.count else { continue }
            let value = cols[field].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            updates[parts[0]] = value
        }
        return updates.isEmpty ? nil : updates
    }

    static func fallbackReason(
        title: String? = nil,
        definition: osrsNativeCalcDefinitionModel? = nil,
        html: String? = nil
    ) -> osrsNativeCalcFallbackReason? {
        if let html, parseResultIsError(html) {
            return .parseError
        }
        if let html, countJcConfigs(in: html) > 1 {
            return .unsupportedTitle
        }
        guard let definition else { return .missingConfig }
        if !definition.unknownTypes.isEmpty {
            return .unknownParamType
        }
        if !isNativeChromeEligible(definition) {
            return .unsupportedTitle
        }
        return nil
    }

    static func firstConfig(in html: String) -> String? {
        if let match = firstTaggedConfig(in: html) {
            return match
        }
        guard let regex = try? NSRegularExpression(
            pattern: #"(?is)(?:^|\n)\s*(?:template|module)\s*=.+?(?=\n\s*(?:\{\||----|<pre|<div|$))"#
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

    private static func firstTaggedConfig(in html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?is)<(pre|div)[^>]*class="[^"]*jcConfig[^"]*"[^>]*>(.*?)</\1>"#
        ) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              match.numberOfRanges > 2,
              let tagRange = Range(match.range(at: 1), in: html),
              let innerRange = Range(match.range(at: 2), in: html) else {
            return nil
        }
        let tag = String(html[tagRange]).lowercased()
        let inner = String(html[innerRange])
        if tag == "pre" {
            return decodeEntities(inner)
        }
        return unwrapDivConfig(inner)
    }

    private static let configKeyBreak = try! NSRegularExpression(
        pattern: #"\s+(?=(?:param|form|result|template|modulefunc|module|name|autosubmit|suggestns)\s*=)"#,
        options: [.caseInsensitive]
    )

    private static func configLines(_ config: String) -> [String] {
        var text = config
            .replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"</p>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<p\b[^>]*>"#, with: "", options: [.regularExpression, .caseInsensitive])
        text = decodeEntities(text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression))
        let ns = text as NSString
        text = configKeyBreak.stringByReplacingMatches(
            in: text,
            options: [],
            range: NSRange(location: 0, length: ns.length),
            withTemplate: "\n"
        )
        return text.split(whereSeparator: \.isNewline).map(String.init)
    }

    private static func splitConfigLine(_ line: String) -> (String, String)? {
        let stripped = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty, !stripped.hasPrefix("#"), let eq = stripped.firstIndex(of: "=") else {
            return nil
        }
        let key = String(stripped[..<eq]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let value = String(stripped[stripped.index(after: eq)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (key, value)
    }

    private static func parseToggles(_ raw: String, defaultKey: String) -> (on: [String: [String]], off: [String: [String]]) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ([:], [:]) }
        var on: [String: [String]] = [:]
        var allKeys: [String] = []
        var allVals: [String] = []
        for piece in trimmed.split(separator: ";") {
            let item = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !item.isEmpty else { continue }
            let keys: [String]
            let vals: [String]
            if let eq = item.firstIndex(of: "=") {
                keys = String(item[..<eq]).split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                vals = String(item[item.index(after: eq)...]).split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            } else {
                keys = [defaultKey]
                vals = item.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            }
            for key in keys {
                on[key] = vals
                allKeys.append(key)
            }
            allVals.append(contentsOf: vals)
        }
        let uniqueVals = Array(NSOrderedSet(array: allVals)) as? [String] ?? Array(Set(allVals))
        var off: [String: [String]] = [:]
        for key in NSOrderedSet(array: allKeys).array as? [String] ?? allKeys {
            let shown = on[key] ?? []
            off[key] = uniqueVals.filter { !shown.contains($0) }
        }
        return (on, off)
    }

    private static func options(for type: osrsNativeCalcParamType, range: String) -> [String] {
        guard type == .select || type == .buttonSelect || type == .check ||
            type == .combobox || type == .toggleButtonGroup, !range.isEmpty else {
            return []
        }
        return range.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private static func intRange(_ range: String, type: osrsNativeCalcParamType) -> (min: Int?, max: Int?) {
        guard type == .int || type == .number, let dash = range.firstIndex(of: "-") else {
            return (nil, nil)
        }
        let left = String(range[..<dash]).trimmingCharacters(in: .whitespacesAndNewlines)
        let right = String(range[range.index(after: dash)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (Int(left), Int(right))
    }

    private static func visibleInputNames(
        _ definition: osrsNativeCalcDefinitionModel,
        values: [String: String]
    ) -> Set<String> {
        var visible = Set(definition.inputs.map(\.name))
        for input in definition.inputs {
            guard !input.toggles.isEmpty else { continue }
            let current = values[input.name] ?? input.defaultValue
            if let on = input.toggles[current] {
                on.forEach { visible.insert($0) }
                (input.toggleOff[current] ?? []).forEach { visible.remove($0) }
            } else {
                for names in input.toggles.values {
                    names.forEach { visible.remove($0) }
                }
            }
        }
        for input in definition.inputs where input.type == .group {
            guard !visible.contains(input.name) else { continue }
            groupMembers(input).forEach { visible.remove($0) }
        }
        return visible
    }

    private static func groupMembers(_ input: osrsNativeCalcInput) -> [String] {
        input.range.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private static func csvTokens(_ value: String) -> [String] {
        value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private static func parseHelp(_ fields: [String]) -> String {
        guard fields.count >= 7 else { return "" }
        var raw = fields.dropFirst(6).joined(separator: "|").trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return "" }
        if raw.lowercased().hasPrefix("inline=") {
            raw = String(raw.dropFirst(7))
        }
        return stripTags(raw)
    }

    private static func decodeEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func stripTags(_ text: String) -> String {
        decodeEntities(text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func unwrapDivConfig(_ inner: String) -> String {
        let pattern = #"^\s*<([a-z][a-z0-9]*)\b[^>]*>(.*)</\1>\s*$"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
           let match = regex.firstMatch(in: inner, options: [], range: NSRange(inner.startIndex..<inner.endIndex, in: inner)),
           match.numberOfRanges > 2,
           let captured = Range(match.range(at: 2), in: inner) {
            return String(inner[captured])
        }
        return inner
    }

    private static func checkIsOn(_ input: osrsNativeCalcInput, _ value: String) -> Bool {
        if input.options.count >= 2 {
            return value == input.options[0]
        }
        return boolToken(value) == "true"
    }

    private static func checkToken(_ input: osrsNativeCalcInput, on: Bool) -> String {
        if input.options.count >= 2 {
            return on ? input.options[0] : input.options[1]
        }
        return on ? "true" : "false"
    }

    private static func boolToken(_ value: String) -> String {
        switch value.lowercased() {
        case "1", "true", "yes", "on": return "true"
        default: return "false"
        }
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captured])
    }
}
