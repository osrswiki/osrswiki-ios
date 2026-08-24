import Foundation

enum osrsCalculatorSaveWarmer {
    static func defaultTemplateCall(from html: String) -> String? {
        let definition = osrsNativeCalcDefinition.parse(html)
        return osrsNativeCalcDefinition.invokeWikitext(definition)
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
}
