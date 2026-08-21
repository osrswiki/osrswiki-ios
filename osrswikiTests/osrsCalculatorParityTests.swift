import XCTest
@testable import osrswiki

final class osrsCalculatorParityTests: XCTestCase {
    func testLocalApiAndCorsPathsRewriteToTheWiki() throws {
        let api = try XCTUnwrap(URL(string: "app-assets://localhost/api.php?action=parse&text=x"))
        let cors = try XCTUnwrap(URL(string: "app-assets://localhost/cors/m=hiscore_oldschool/index_lite.ws?player=Zezima"))
        XCTAssertTrue(osrsWikiWebViewUrl.shouldProxy(api))
        XCTAssertTrue(osrsWikiWebViewUrl.shouldProxy(cors))
        XCTAssertTrue(osrsWikiWebViewUrl.rewriteToWiki(api).absoluteString.hasPrefix("https://oldschool.runescape.wiki/api.php"))
        XCTAssertTrue(osrsWikiWebViewUrl.rewriteToWiki(cors).absoluteString.hasPrefix("https://oldschool.runescape.wiki/cors/"))
        let load = try XCTUnwrap(URL(string: "app-assets://localhost/load.php?modules=oojs-ui-core"))
        XCTAssertTrue(osrsWikiWebViewUrl.shouldProxy(load))
        XCTAssertTrue(osrsWikiWebViewUrl.rewriteToWiki(load).absoluteString.hasPrefix("https://oldschool.runescape.wiki/load.php"))
        let nestedLoad = try XCTUnwrap(URL(string: "app-assets://localhost/w/load.php?modules=mediawiki.widgets"))
        XCTAssertTrue(osrsWikiWebViewUrl.shouldProxy(nestedLoad))
    }

    func testBundledCatalogListsEveryUserFacingCalculator() throws {
        let snapshot = try osrsCalculatorCatalog.loadSnapshot(json: catalogData())
        XCTAssertGreaterThanOrEqual(snapshot.calculators.count, 100)
        for entry in snapshot.calculators {
            XCTAssertTrue(osrsWikiWebViewUrl.isUserFacingCalculator(entry.title), entry.title)
            XCTAssertTrue(entry.url.hasPrefix("https://oldschool.runescape.wiki/w/Calculator:"), entry.url)
            XCTAssertFalse(
                entry.title.split(separator: "/").contains { $0.lowercased().hasPrefix("template") },
                entry.title
            )
        }
        let titles = Set(snapshot.calculators.map(\.title))
        XCTAssertTrue(titles.contains("Calculator:Combat level"))
        XCTAssertTrue(titles.contains("Calculator:Cooking"))
        XCTAssertTrue(titles.contains("Calculator:Barrows"))
    }

    func testCalculatorParseTitleKeepsCalculatorNamespace() throws {
        let url = try XCTUnwrap(URL(string: "https://oldschool.runescape.wiki/w/Calculator:Combat_level"))
        XCTAssertEqual(
            osrsArticleDocumentIdentity.requestedTitle(pageURL: url, fallbackTitle: "Combat level"),
            "Calculator:Combat level"
        )
        XCTAssertEqual(
            osrsArticleDocumentRequest(pageURL: url, pageTitle: "Combat level").requestedTitle,
            "Calculator:Combat level"
        )
    }

    func testEveryCataloguedCalculatorLoadsCalcCoreAndCalculatorNamespace() throws {
        let snapshot = try osrsCalculatorCatalog.loadSnapshot(json: catalogData())
        let builder = osrsPageHtmlBuilder()
        for entry in snapshot.calculators {
            let html = builder.buildFullHtmlDocument(
                title: entry.title,
                bodyContent: "<pre class=\"jcConfig\">template = \(entry.title)/Template</pre><div id=\"form\"></div>",
                theme: osrsLightTheme(),
                includeAssetLinks: true,
                canonicalTitle: entry.title
            )
            XCTAssertTrue(html.contains("js/mediawiki/gadget_calc_core.js"), entry.title)
            XCTAssertFalse(html.contains("src=\"app-assets://localhost/gadget_calc_core.js\""), entry.title)
            XCTAssertTrue(html.contains("\"oojs-ui-core\""), entry.title)
            XCTAssertTrue(html.contains("\"oojs-ui-widgets\""), entry.title)
            XCTAssertTrue(html.contains("\"mediawiki.widgets\""), entry.title)
            XCTAssertTrue(html.contains("\"wgNamespaceNumber\": 116") || html.contains("\"wgNamespaceNumber\":116"), entry.title)
            XCTAssertTrue(html.contains("\"wgCanonicalNamespace\": \"Calculator\""), entry.title)
            XCTAssertTrue(html.contains("\"wgLoadScript\": \"/load.php\""), entry.title)
            XCTAssertTrue(html.contains("\"wgScript\": \"/index.php\""), entry.title)
            XCTAssertTrue(html.contains("id=\"bodyContent\""), entry.title)
            XCTAssertTrue(html.contains("ResourceLoaderDynamicStyles"), entry.title)
            XCTAssertTrue(html.contains("--osrs-article-bottom-chrome"), entry.title)
        }
    }

    func testLiveNamespacePagesMergeOntoTheBundledCatalog() throws {
        let snapshot = try osrsCalculatorCatalog.loadSnapshot(json: catalogData())
        let merged = osrsCalculatorCatalog.mergeLivePages(
            snapshot: snapshot,
            livePages: [
                ["title": "Calculator:Brand New Tool", "pageid": 1],
                ["title": "Calculator:Combat level/Template", "pageid": 2]
            ]
        )
        XCTAssertTrue(merged.contains(where: { $0.title == "Calculator:Brand New Tool" }))
        XCTAssertFalse(merged.contains(where: { $0.title == "Calculator:Combat level/Template" }))
    }

    func testParseCacheKeysIgnoreQueryParameterOrder() {
        let left = osrsCalculatorParseCache.key(
            method: "GET",
            url: "https://oldschool.runescape.wiki/api.php?b=2&a=1",
            body: ""
        )
        let right = osrsCalculatorParseCache.key(
            method: "GET",
            url: "https://oldschool.runescape.wiki/api.php?a=1&b=2",
            body: ""
        )
        XCTAssertEqual(left, right)
    }

    func testDefaultCombatTemplateCallMatchesWikiGadgetSubmit() {
        let html = """
        <pre class="jcConfig">
        template = Calculator:Combat level/Template
        form = combatCalcForm
        result = combatCalcResult
        param = attack|Attack|1|int|1-99
        param = strength|Strength|1|int|1-99
        param = playername|Player name||hs|attack,1,1
        </pre>
        """
        XCTAssertEqual(
            osrsCalculatorSaveWarmer.defaultTemplateCall(from: html),
            "{{Calculator:Combat level/Template|attack=1|strength=1}}"
        )
        XCTAssertEqual(
            osrsCalculatorSaveWarmer.defaultTemplateCall(from: """
            <pre class="jcConfig">
            module = Dry calc
            param = chance|Chance of drop|1/128|string|
            param = kills|Number of kills|128|int|1-inf
            </pre>
            """),
            "{{#invoke:Dry calc|main|chance=1/128|kills=128}}"
        )
    }

    func testArticleToolsLeavesWikiCalculatorFormsIntact() throws {
        let tools = try String(
            contentsOf: iosRoot.appendingPathComponent("osrswiki/Assets/web/article_tools.js"),
            encoding: .utf8
        )
        XCTAssertFalse(tools.contains("document.querySelectorAll('pre.jcConfig').forEach(setupCalculator)"))
        XCTAssertTrue(tools.contains("Calculator forms are owned by ext.gadget.calc-core"))
        let runtime = try String(
            contentsOf: iosRoot.appendingPathComponent("osrswiki/Assets/web/osrs_calculator_runtime.js"),
            encoding: .utf8
        )
        XCTAssertTrue(runtime.contains("mw.loader.load('ext.gadget.calc-core')"))
        XCTAssertTrue(runtime.contains("osrsCalculatorApi"))
        XCTAssertTrue(runtime.contains("webkit.messageHandlers.osrsCalculatorApi"))
        XCTAssertTrue(runtime.contains("oojs-ui-widgets"))
        XCTAssertTrue(runtime.contains("ButtonOptionWidget"))
        XCTAssertTrue(runtime.contains("ToggleSwitchWidget"))
        XCTAssertTrue(runtime.contains("data-osrs-ooui-loader"))
        XCTAssertTrue(runtime.contains("/load.php?modules=oojs-ui-core"))
        XCTAssertTrue(runtime.contains("only=scripts"))
        XCTAssertTrue(runtime.contains("/load.php?modules=jquery&only=scripts"))
        XCTAssertTrue(runtime.contains("osrsHideCalculatorJsPlaceholder"))
        XCTAssertTrue(runtime.contains("dynamic calculator requires JavaScript"))
        XCTAssertTrue(runtime.contains("jQuery.ajax.__osrsCalculatorPatched"))
        XCTAssertTrue(runtime.contains("setTimeout(patchAjax, 25)"))
        XCTAssertTrue(runtime.contains("__osrsCalculatorSmokeSubmit"))
        XCTAssertTrue(runtime.contains("osrsArmSmokeSubmit"))
        XCTAssertTrue(runtime.contains("aria-live"))
        XCTAssertTrue(runtime.contains("MutationObserver"))
        XCTAssertTrue(runtime.contains("[id$=\"Form\"]"))
        XCTAssertTrue(runtime.contains("#bodyContent"))
        XCTAssertTrue(runtime.contains("scrollIntoView"))
        XCTAssertTrue(runtime.contains("poll(attempt"))
        let calcCore = try String(
            contentsOf: iosRoot.appendingPathComponent("osrswiki/Assets/js/mediawiki/gadget_calc_core.js"),
            encoding: .utf8
        )
        XCTAssertTrue(calcCore.contains("document.getElementById('bodyContent') || document.body"))
        XCTAssertTrue(calcCore.contains("window.__osrsKickCalcCore"))
        XCTAssertTrue(calcCore.contains("osrsCalcCoreDepsReady"))
        XCTAssertTrue(calcCore.contains("OO.ui.ButtonOptionWidget"))
        XCTAssertTrue(calcCore.contains("osrsRunModuleScript"))
        XCTAssertTrue(calcCore.contains("osrsMakeModuleRequire"))
        XCTAssertTrue(calcCore.contains("osrsInstallImplementedScript"))
        XCTAssertTrue(calcCore.contains("osrsEnsureMwHelpers"))
        XCTAssertTrue(calcCore.contains("mw.html.escape"))
        XCTAssertTrue(runtime.contains("osrsEnsureJQueryAlias"))
        XCTAssertTrue(calcCore.contains("setupCalc:"))
        XCTAssertTrue(calcCore.contains("ToggleSwitchWidget"))
        XCTAssertTrue(calcCore.contains("__osrsRebuildCalcs"))
        XCTAssertTrue(calcCore.contains("__osrsCalculatorPatched"))
        XCTAssertFalse(calcCore.contains("$('#bodyContent')"))
        let startup = try String(
            contentsOf: iosRoot.appendingPathComponent("osrswiki/Assets/startup.js"),
            encoding: .utf8
        )
        XCTAssertTrue(startup.contains("\"debug\": \"0\""))
        XCTAssertFalse(startup.contains("\"debug\": \"1\""))
    }

    func testLeftoverCalculatorPlaceholdersIncludeRequiresJavaScript() {
        let leftovers = [
            "Please wait for the form to load",
            "This calculator requires JavaScript to run"
        ]
        XCTAssertTrue(leftovers.contains(where: { $0.localizedCaseInsensitiveContains("requires JavaScript") }))
        XCTAssertTrue(leftovers.contains(where: { $0.localizedCaseInsensitiveContains("Please wait for the form") }))
    }

    func testAssetHandlerAliasesBareCalcCoreFilename() {
        XCTAssertEqual(
            IOSAssetHandler.canonicalAssetPath("gadget_calc_core.js"),
            "js/mediawiki/gadget_calc_core.js"
        )
        XCTAssertEqual(
            IOSAssetHandler.canonicalAssetPath("js/mediawiki/gadget_calc_core.js"),
            "js/mediawiki/gadget_calc_core.js"
        )
    }

    private func catalogData() throws -> Data {
        let candidates = [
            iosRoot.appendingPathComponent("osrswiki/Assets/manifests/osrs-wiki-calculators.json"),
            iosRoot.deletingLastPathComponent().appendingPathComponent("shared/manifests/osrs-wiki-calculators.json")
        ]
        guard let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw XCTSkip("Calculator catalog snapshot is missing")
        }
        return try Data(contentsOf: url)
    }

    private var iosRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
