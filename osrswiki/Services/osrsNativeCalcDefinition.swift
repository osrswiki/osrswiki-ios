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
    static let spikeNativeTitles: Set<String> = [
        "Calculator:Agility",
        "Calculator:Combat level"
    ]
    static let kitTypes: Set<osrsNativeCalcParamType> = [
        .string, .int, .number, .select, .buttonSelect, .check,
        .toggleSwitch, .toggleButton, .hs, .rsn, .hidden, .fixed, .semiHidden
    ]

    static func parse(_ text: String, title: String? = nil, pageId: Int? = nil, revId: Int? = nil) -> osrsNativeCalcDefinitionModel? {
        guard let config = firstConfig(in: text) else { return nil }
        var ui = osrsNativeCalcUI(name: "Calculator", formId: "", resultId: "", autosubmit: "off")
        var invokeKind: osrsNativeCalcInvoke.Kind?
        var template: String?
        var module: String?
        var moduleFunc: String?
        var inputs: [osrsNativeCalcInput] = []
        var unknownTypes: [String] = []
        for rawLine in config.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard let (key, value) = splitConfigLine(line) else { continue }
            if key != "param" {
                switch key {
                case "form": ui.formId = value
                case "result": ui.resultId = value
                case "name": if !value.isEmpty { ui.name = value }
                case "autosubmit": ui.autosubmit = value.isEmpty ? "off" : value
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
            let type = osrsNativeCalcParamType(rawValue: rawType) ?? .unknown
            if type == .unknown, !rawType.isEmpty {
                unknownTypes.append(rawType)
            }
            let toggleDefault: String
            if !defaultValue.isEmpty {
                toggleDefault = defaultValue
            } else if type == .toggleSwitch || type == .toggleButton || type == .check {
                toggleDefault = "true"
            } else {
                toggleDefault = name
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
                    maxValue: intBounds.max
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
        guard spikeNativeTitles.contains(definition.id) else { return false }
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
            if input.type == .unknown { continue }
            let always = input.type == .hidden || input.type == .fixed
            if !always && !visible.contains(input.name) { continue }
            var value = merged[input.name] ?? ""
            if (input.type == .hs || input.type == .rsn) && value.isEmpty { continue }
            if input.type == .toggleSwitch {
                value = boolToken(value)
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

    static func fallbackReason(
        title: String? = nil,
        definition: osrsNativeCalcDefinitionModel? = nil,
        html: String? = nil
    ) -> osrsNativeCalcFallbackReason? {
        if let html, parseResultIsError(html) {
            return .parseError
        }
        if let title, !spikeNativeTitles.contains(title) {
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
        guard type == .select || type == .buttonSelect || type == .check, !range.isEmpty else {
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
        return visible
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
