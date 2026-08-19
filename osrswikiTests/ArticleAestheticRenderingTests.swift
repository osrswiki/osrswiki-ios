import XCTest
import UIKit
import WebKit
@testable import osrswiki

private final class ArticleAestheticNavigationDelegate: NSObject, WKNavigationDelegate {
    let didFinish: XCTestExpectation

    init(didFinish: XCTestExpectation) {
        self.didFinish = didFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        didFinish.fulfill()
    }
}

@MainActor
final class ArticleAestheticRenderingTests: XCTestCase {
    private var webView: WKWebView!
    private var navigationDelegate: ArticleAestheticNavigationDelegate?

    override func setUp() {
        super.setUp()
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptEnabled = true
        webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 375, height: 812),
            configuration: configuration
        )
    }

    override func tearDown() {
        navigationDelegate = nil
        webView = nil
        super.tearDown()
    }

    func testFloorNumberFixesKeepOneDialectAndInfoboxesPaintImmediately() throws {
        let fixes = try readAsset("Assets/styles/fixes.css")
        let other = try readAsset("Assets/styles/modules/other.css")
        let tables = try readAsset("Assets/web/collapsible_tables.css")
        let collapsible = try readAsset("Assets/web/collapsible_content.js")

        XCTAssertTrue(fixes.contains(".floornumber-help"))
        XCTAssertTrue(fixes.contains(".floornumber-us"))
        XCTAssertTrue(fixes.contains("display: none !important"))
        XCTAssertTrue(fixes.contains("cursor: pointer"))
        XCTAssertFalse(fixes.contains(".mw-halign-left > figcaption"))
        XCTAssertTrue(fixes.contains("ul.gallery"))
        let inlineRule = other.substring(
            from: other.range(of: "#toc li a span.toctext span span:nth-child(2)")!.lowerBound
        )
        let ruleBody = String(inlineRule.prefix(while: { $0 != "}" }))
        XCTAssertTrue(ruleBody.contains("display: none"))
        XCTAssertFalse(ruleBody.contains("display: inline"))
        XCTAssertFalse(tables.contains("body:not(.js-transforms-complete) .infobox"))
        XCTAssertTrue(tables.contains(".mw-parser-output > table.infobox"))
        XCTAssertTrue(collapsible.contains("authoredMapId"))
        XCTAssertTrue(collapsible.contains("Tap to collapse"))
        XCTAssertTrue(collapsible.contains("Tap to expand"))
        XCTAssertTrue(collapsible.contains("collapsible-state"))
        XCTAssertTrue(fixes.contains("mask-image:"))
        XCTAssertTrue(fixes.contains("text-overflow: ellipsis"))
        XCTAssertTrue(tables.contains("mask-image:"))
        let afterTransforms = String(collapsible[collapsible.range(of: "js-transforms-complete")!.upperBound...])
        let stylingCompleteRange = try XCTUnwrap(afterTransforms.range(of: "Event: StylingScriptsComplete"))
        let mapMeasureRange = try XCTUnwrap(afterTransforms.range(of: "measureAndPreloadMaps();"))
        XCTAssertLessThan(
            stylingCompleteRange.lowerBound,
            mapMeasureRange.lowerBound,
            "Map measurement must not block the first-paint styling-complete event."
        )
        let components = try readAsset("Assets/styles/components.css")
        let infoboxRule = String(components.substring(
            from: components.range(of: ".infobox {")!.upperBound
        ).prefix(while: { $0 != "}" }))
        XCTAssertTrue(infoboxRule.contains("float: none"))
        XCTAssertFalse(infoboxRule.contains("float: right"))
    }

    func testJcConfigCombatCalculatorRendersUsableControls() async throws {
        let articleTools = try readAsset("Assets/web/article_tools.js")
        let html = """
        <!doctype html>
        <html>
        <body>
        <pre class="jcConfig">
        template = Calculator:Combat level/Template
        form = combatCalcForm
        result = combatCalcResult
        param  = playername|Player name||hs|attack,1,1;strength,3,1;ranged,5,1;magic,7,1;defence,2,1;hitpoints,4,1;prayer,6,1
        param = attack|Attack|1|int|1-99
        param = strength|Strength|1|int|1-99
        param = ranged|Ranged|1|int|1-99
        param = magic|Magic|1|int|1-99
        param = defence|Defence|1|int|1-99
        param = hitpoints|Hitpoints|10|int|9-99
        param = prayer|Prayer|1|int|1-99
        autosubmit = enabled
        </pre>
        <div id="combatCalcForm">Please wait for the form to load. If it does not load, try refreshing the page.</div>
        <div id="combatCalcResult"></div>
        <script>\(articleTools)</script>
        </body>
        </html>
        """

        try await load(html)
        let result = try await evaluate("""
        (() => {
            const form = document.getElementById('combatCalcForm');
            return {
                hasPlaceholder: document.body.innerText.includes('Please wait for the form to load'),
                hasAttackInput: !!document.querySelector('[data-osrs-calculator-param="attack"] input'),
                incrementButtons: document.querySelectorAll('[data-osrs-calculator-action="increment"]').length,
                resultText: document.getElementById('combatCalcResult')?.innerText || ''
            };
        })()
        """)

        XCTAssertEqual(result["hasPlaceholder"] as? Bool, false)
        XCTAssertEqual(result["hasAttackInput"] as? Bool, true)
        XCTAssertGreaterThanOrEqual(result["incrementButtons"] as? Int ?? 0, 7)
        XCTAssertTrue((result["resultText"] as? String ?? "").contains("Combat level"))
    }

    func testMoneyMakingGuideRateControlUpdatesVisibleValues() async throws {
        let articleTools = try readAsset("Assets/web/article_tools.js")
        let html = """
        <!doctype html>
        <html>
        <body>
        <table class="wikitable mmg-table mmg-isperkill" data-default-kph="308" data-default-kph-name="Catches per hour">
            <caption>Fishing raw dark crabs</caption>
            <tbody>
                <tr><th>Results</th></tr>
                <tr>
                    <td>
                        <span class="mmg-itemline mmg-input mmg-varieswithkph">
                            <span class="mmg-quantity" data-mmg-qty="1">308</span> x bait
                            (<span class="mmg-cost" data-mmg-cost-pk="6"><span class="coins">1,848</span></span>)
                        </span>
                    </td>
                    <td>
                        <span class="mmg-varieswithkph" data-mmg-cost-pk="963" data-mmg-cost-ph="0">
                            <span class="coins">296,604</span>
                        </span>
                    </td>
                </tr>
            </tbody>
        </table>
        <script>\(articleTools)</script>
        </body>
        </html>
        """

        try await load(html)
        let initial = try await evaluate("""
        (() => ({
            hasControl: !!document.querySelector('.osrs-mmg-rate-control'),
            controlBeforeTable: document.querySelector('.mmg-table')?.previousElementSibling?.classList.contains('osrs-mmg-rate-control') || false,
            inputValue: document.querySelector('.osrs-mmg-rate-control input')?.value || ''
        }))()
        """)

        XCTAssertEqual(initial["hasControl"] as? Bool, true)
        XCTAssertEqual(initial["controlBeforeTable"] as? Bool, true)
        XCTAssertEqual(initial["inputValue"] as? String, "308")

        let updated = try await evaluate("""
        (() => {
            const input = document.querySelector('.osrs-mmg-rate-control input');
            input.value = '400';
            input.dispatchEvent(new Event('input', { bubbles: true }));
            return {
                quantity: document.querySelector('.mmg-quantity')?.textContent || '',
                profit: document.querySelector('.mmg-varieswithkph > .coins')?.textContent || ''
            };
        })()
        """)

        XCTAssertEqual(updated["quantity"] as? String, "400")
        XCTAssertEqual(updated["profit"] as? String, "385,200")
    }

    func testCalculatorTemplatesAndControlsUseResponsiveThemedLayout() async throws {
        let articleTools = try readAsset("Assets/web/article_tools.js")
        let fixesCss = try readAsset("Assets/styles/fixes.css")
        let html = """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
        :root {
            --text-color: #f4eaea;
            --wikitable-bg: #3e362f;
            --wikitable-border: #736559;
            --ooui-normal: #312a25;
            --ooui-normal-border: #736559;
            --ooui-normal--hover: #3e362f;
            --ooui-text: #f4eaea;
            --ooui-input: #1f1a16;
            --ooui-input-border: #736559;
            --ooui-progressive: #4d9bff;
            --ooui-progressive--hover: #6babff;
            --body-light: #3e362f;
            --body-border: #736559;
        }
        .archivelist {
            float: right;
            width: 120px;
        }
        \(fixesCss)
        </style>
        </head>
        <body>
        <table class="archivelist"><tbody><tr><th>Templates used</th></tr><tr><td>Calculator:Combat level/Template</td></tr></tbody></table>
        <pre class="jcConfig">
        template = Calculator:Combat level/Template
        form = combatCalcForm
        result = combatCalcResult
        param = attack|Attack|1|int|1-99
        param = strength|Strength|1|int|1-99
        param = hitpoints|Hitpoints|10|int|9-99
        </pre>
        <table class="calculator-host"><tbody><tr><td><div id="combatCalcForm">Please wait for the form to load.</div><div id="combatCalcResult"></div></td></tr></tbody></table>
        <script>\(articleTools)</script>
        </body>
        </html>
        """

        try await load(html)
        let phoneState = try await evaluate("""
        (() => {
            const layout = document.querySelector('.osrs-calculator-layout');
            const templates = document.querySelector('.osrs-calculator-templates');
            const panel = document.querySelector('.osrs-calculator-panel');
            const stepButton = document.querySelector('.osrs-stepper button');
            const input = document.querySelector('.osrs-stepper input');
            const buttonStyle = getComputedStyle(stepButton);
            const inputStyle = getComputedStyle(input);
            const templateRect = templates.getBoundingClientRect();
            const panelRect = panel.getBoundingClientRect();
            return {
                hasLayout: !!layout,
                templateFloat: getComputedStyle(templates).float,
                templateBeforePanel: templateRect.bottom <= panelRect.top,
                columns: getComputedStyle(layout).gridTemplateColumns,
                buttonFontSize: parseFloat(buttonStyle.fontSize),
                buttonBackground: buttonStyle.backgroundColor,
                buttonBorder: buttonStyle.borderTopColor,
                inputBackground: inputStyle.backgroundColor
            };
        })()
        """)

        XCTAssertEqual(phoneState["hasLayout"] as? Bool, true)
        XCTAssertEqual(phoneState["templateFloat"] as? String, "none")
        XCTAssertEqual(phoneState["templateBeforePanel"] as? Bool, true)
        XCTAssertEqual((phoneState["columns"] as? String ?? "").split(separator: " ").count, 1)
        XCTAssertGreaterThanOrEqual(phoneState["buttonFontSize"] as? Double ?? 0, 18)
        XCTAssertNotEqual(phoneState["buttonBackground"] as? String, "rgba(0, 0, 0, 0)")
        XCTAssertNotEqual(phoneState["buttonBorder"] as? String, "rgba(0, 0, 0, 0)")
        XCTAssertNotEqual(phoneState["inputBackground"] as? String, "rgba(0, 0, 0, 0)")

        webView.frame = CGRect(x: 0, y: 0, width: 768, height: 1024)
        let tabletState = try await evaluate("""
        (() => ({
            columns: getComputedStyle(document.querySelector('.osrs-calculator-layout')).gridTemplateColumns
        }))()
        """)
        XCTAssertGreaterThanOrEqual((tabletState["columns"] as? String ?? "").split(separator: " ").count, 2)
    }

    func testMoneyMakingControlUsesInlineThemedIconControls() async throws {
        let articleTools = try readAsset("Assets/web/article_tools.js")
        let fixesCss = try readAsset("Assets/styles/fixes.css")
        let html = """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
        :root {
            --text-color: #f4eaea;
            --wikitable-bg: #3e362f;
            --wikitable-border: #736559;
            --ooui-normal: #312a25;
            --ooui-normal-border: #736559;
            --ooui-text: #f4eaea;
            --ooui-input: #1f1a16;
            --ooui-input-border: #736559;
        }
        \(fixesCss)
        </style>
        </head>
        <body>
        <table class="wikitable mmg-table mmg-isperkill" data-default-kph="308" data-default-kph-name="Catches per hour">
            <caption>Fishing raw dark crabs</caption>
            <tbody>
                <tr><th>Results</th></tr>
                <tr><td><span class="mmg-varieswithkph" data-mmg-cost-pk="963"><span class="coins">296,604</span></span></td></tr>
            </tbody>
        </table>
        <script>\(articleTools)</script>
        </body>
        </html>
        """

        try await load(html)
        let state = try await evaluate("""
        (() => {
            const control = document.querySelector('.osrs-mmg-rate-control');
            const info = control.querySelector('.osrs-mmg-info');
            const input = control.querySelector('input');
            const decrement = control.querySelector('[data-osrs-mmg-action="decrement"]');
            const increment = control.querySelector('[data-osrs-mmg-action="increment"]');
            const reset = control.querySelector('[data-osrs-mmg-action="reset"]');
            const infoRect = info.getBoundingClientRect();
            const inputRect = input.getBoundingClientRect();
            const decRect = decrement.getBoundingClientRect();
            const resetRect = reset.getBoundingClientRect();
            const resetStyle = getComputedStyle(reset);
            return {
                infoBeforeInput: info.compareDocumentPosition(input) & Node.DOCUMENT_POSITION_FOLLOWING ? true : false,
                resetHasSvg: !!reset.querySelector('svg'),
                resetLabel: reset.getAttribute('aria-label') || '',
                inputAndButtonsSameRow: Math.abs(inputRect.top - decRect.top) < 4 && Math.abs(inputRect.top - resetRect.top) < 4,
                infoLeftOfInput: infoRect.right <= inputRect.left,
                resetText: reset.textContent.trim(),
                resetBackground: resetStyle.backgroundColor,
                resetBorder: resetStyle.borderTopColor,
                incrementFontSize: parseFloat(getComputedStyle(increment).fontSize)
            };
        })()
        """)

        XCTAssertEqual(state["infoBeforeInput"] as? Bool, true)
        XCTAssertEqual(state["infoLeftOfInput"] as? Bool, true)
        XCTAssertEqual(state["inputAndButtonsSameRow"] as? Bool, true)
        XCTAssertEqual(state["resetHasSvg"] as? Bool, true)
        XCTAssertTrue((state["resetLabel"] as? String ?? "").contains("Reset Catches per hour"))
        XCTAssertEqual(state["resetText"] as? String, "")
        XCTAssertNotEqual(state["resetBackground"] as? String, "rgba(0, 0, 0, 0)")
        XCTAssertNotEqual(state["resetBorder"] as? String, "rgba(0, 0, 0, 0)")
        XCTAssertGreaterThanOrEqual(state["incrementFontSize"] as? Double ?? 0, 18)
    }

    func testPrimaryInfoboxStaysExpandedAndContentTablesHonorCollapsePreference() async throws {
        let collapsibleContent = try readAsset("Assets/web/collapsible_content.js")
        let html = """
        <!doctype html>
        <html>
        <body>
        <script>window.OSRS_TABLE_COLLAPSED = true;</script>
        <table class="infobox"><caption>Dragon scimitar</caption><tbody><tr><th>Released</th><td>29 March 2005</td></tr></tbody></table>
        <p>Lead paragraph.</p>
        <table class="wikitable"><tbody><tr><th>Level</th><th>New abilities</th></tr><tr><td>1</td><td>Build a chair</td></tr></tbody></table>
        <table class="wikitable"><caption>Secondary table</caption><tbody><tr><td>Later detail</td></tr></tbody></table>
        <table class="navbox"><tbody><tr><th>Navigation</th></tr><tr><td>Links</td></tr></tbody></table>
        <script>\(collapsibleContent)</script>
        </body>
        </html>
        """

        try await load(html)
        let state = try await evaluate("""
        (() => {
            const containers = Array.from(document.querySelectorAll('.collapsible-container'));
            return {
                firstInfoboxCollapsed: containers[0]?.classList.contains('collapsed') || false,
                firstInfoboxHeader: containers[0]?.querySelector('.title-wrapper')?.innerText || '',
                firstTableCollapsed: containers[1]?.classList.contains('collapsed') || false,
                firstTableHeader: containers[1]?.querySelector('.title-wrapper')?.innerText || '',
                secondTableCollapsed: containers[2]?.classList.contains('collapsed') || false,
                navCollapsed: containers[3]?.classList.contains('collapsed') || false
            };
        })()
        """)

        XCTAssertEqual(state["firstInfoboxCollapsed"] as? Bool, false)
        XCTAssertTrue((state["firstInfoboxHeader"] as? String ?? "").contains("Infobox"))
        XCTAssertTrue((state["firstInfoboxHeader"] as? String ?? "").contains("Tap to collapse"))
        XCTAssertFalse((state["firstInfoboxHeader"] as? String ?? "").contains("Dragon scimitar"))
        XCTAssertEqual(state["firstTableCollapsed"] as? Bool, true)
        XCTAssertTrue((state["firstTableHeader"] as? String ?? "").contains("Table"))
        XCTAssertTrue((state["firstTableHeader"] as? String ?? "").contains("Tap to expand"))
        XCTAssertFalse((state["firstTableHeader"] as? String ?? "").contains("Level / New abilities"))
        XCTAssertEqual(state["secondTableCollapsed"] as? Bool, true)
        XCTAssertEqual(state["navCollapsed"] as? Bool, true)
    }

    func testQuestDetailsTableTransformsIntoCollapsedOverviewBox() async throws {
        let collapsibleContent = try readAsset("Assets/web/collapsible_content.js")
        let html = """
        <!doctype html>
        <html>
        <body>
        <script>window.OSRS_TABLE_COLLAPSED = true;</script>
        <h2>Details</h2>
        <table class="questdetails" cellspacing="3">
            <tbody>
                <tr><th class="questdetails-header">Start point</th><td class="questdetails-info">Talk to Sarius Guile in the Icyene Graveyard.</td></tr>
                <tr><th class="questdetails-header">Official difficulty</th><td class="questdetails-info">Grandmaster</td></tr>
                <tr><th class="questdetails-header">Official length</th><td class="questdetails-info">Very Long</td></tr>
                <tr><th class="questdetails-header">Requirements</th><td class="questdetails-info">Several skill and quest requirements.</td></tr>
            </tbody>
        </table>
        <script>\(collapsibleContent)</script>
        </body>
        </html>
        """

        try await load(html)
        let state = try await evaluate("""
        (() => {
            const table = document.querySelector('table.questdetails');
            const container = table.closest('.collapsible-container');
            return {
                containerCount: document.querySelectorAll('.collapsible-container').length,
                tableInsideContainer: !!container,
                collapsed: container?.classList.contains('collapsed') || false,
                header: container?.querySelector('.title-wrapper')?.innerText || '',
                outsideQuestdetails: Array.from(document.querySelectorAll('table.questdetails')).filter(table => !table.closest('.collapsible-container')).length
            };
        })()
        """)

        XCTAssertEqual(state["containerCount"] as? Int, 1)
        XCTAssertEqual(state["tableInsideContainer"] as? Bool, true)
        XCTAssertEqual(state["collapsed"] as? Bool, true)
        XCTAssertTrue((state["header"] as? String ?? "").contains("Quest details"))
        XCTAssertEqual(state["outsideQuestdetails"] as? Int, 0)
    }

    func testExplicitMwCollapsibleTableTransformsWithoutDoubleWrapping() async throws {
        let collapsibleContent = try readAsset("Assets/web/collapsible_content.js")
        let html = """
        <!doctype html>
        <html>
        <body>
        <script>window.OSRS_TABLE_COLLAPSED = true;</script>
        <h2>Level 20-99: Stealing from Port Roberts stalls</h2>
        <table class="mw-collapsible mw-collapsed">
            <tbody>
                <tr><th align="left">Importable Watchdog config</th></tr>
                <tr><td><pre>{"type":"AlertGroup","alerts":[{"type":"XPDropAlert"}]}</pre></td></tr>
            </tbody>
        </table>
        <div class="collapsible-container collapsed">
            <div class="collapsible-content">
                <table class="mw-collapsible mw-collapsed" id="alreadyWrapped">
                    <tbody><tr><th>Already wrapped</th></tr><tr><td>Leave this table in its existing container.</td></tr></tbody>
                </table>
            </div>
        </div>
        <script>\(collapsibleContent)</script>
        </body>
        </html>
        """

        try await load(html)
        let state = try await evaluate("""
        (() => {
            const explicitTables = Array.from(document.querySelectorAll('table.mw-collapsible'));
            const watchdog = explicitTables.find(table => table.id !== 'alreadyWrapped');
            const watchdogContainer = watchdog.closest('.collapsible-container');
            const alreadyWrapped = document.getElementById('alreadyWrapped');
            return {
                containerCount: document.querySelectorAll('.collapsible-container').length,
                watchdogInsideContainer: !!watchdogContainer,
                watchdogCollapsed: watchdogContainer?.classList.contains('collapsed') || false,
                watchdogHeader: watchdogContainer?.querySelector('.title-wrapper')?.innerText || '',
                alreadyWrappedDepth: alreadyWrapped ? Array.from(document.querySelectorAll('.collapsible-container')).filter(container => container.contains(alreadyWrapped)).length : 0,
                outsideExplicitTables: explicitTables.filter(table => !table.closest('.collapsible-container')).length
            };
        })()
        """)

        XCTAssertEqual(state["containerCount"] as? Int, 2)
        XCTAssertEqual(state["watchdogInsideContainer"] as? Bool, true)
        XCTAssertEqual(state["watchdogCollapsed"] as? Bool, true)
        XCTAssertTrue((state["watchdogHeader"] as? String ?? "").contains("Table"))
        XCTAssertFalse((state["watchdogHeader"] as? String ?? "").contains("Importable Watchdog config"))
        XCTAssertEqual(state["alreadyWrappedDepth"] as? Int, 1)
        XCTAssertEqual(state["outsideExplicitTables"] as? Int, 0)
    }

    func testSwitchInfoboxCaptionUsesSemanticHeaderInsteadOfVariantButtons() async throws {
        let collapsibleContent = try readAsset("Assets/web/collapsible_content.js")
        let html = """
        <!doctype html>
        <html>
        <body>
        <script>window.OSRS_TABLE_COLLAPSED = true;</script>
        <table class="infobox infobox-switch infobox-monster" data-resource-class=".infobox-resources-Infobox_Monster">
            <caption class="infobox-switch-buttons-caption">
                <div class="infobox-buttons infobox-buttons-select">
                    <span data-switch-index="1" class="button">Delve 1</span>
                    <span data-switch-index="2" class="button">Delve 2</span>
                    <span data-switch-index="9" class="button">Deep Delve</span>
                </div>
            </caption>
            <tbody>
                <tr><th colspan="24" class="infobox-header" data-attr-param="name">Doom of Mokhaiotl</th></tr>
                <tr><td data-attr-param="image">Monster image</td></tr>
            </tbody>
        </table>
        <div class="infobox-switch-resources">
            <div data-attr-param="name">
                <span data-attr-index="1">Delve 1 Doom</span>
                <span data-attr-index="9">Deep Delve Doom</span>
            </div>
        </div>
        <script>\(collapsibleContent)</script>
        </body>
        </html>
        """

        try await load(html)
        let state = try await evaluate("""
        (() => {
            const headerText = document.querySelector('.collapsible-container .title-wrapper')?.innerText || '';
            return {
                headerText,
                containsVariantButtons: /Delve 1|Delve 2|Deep Delve/.test(headerText),
                containsResourceBank: /Deep Delve Doom/.test(headerText)
            };
        })()
        """)

        XCTAssertTrue((state["headerText"] as? String ?? "").contains("Infobox"))
        XCTAssertFalse((state["headerText"] as? String ?? "").contains("Doom of Mokhaiotl"))
        XCTAssertEqual(state["containsVariantButtons"] as? Bool, false)
        XCTAssertEqual(state["containsResourceBank"] as? Bool, false)
    }

    func testLegacySwitchInfoboxHeaderIgnoresTriggersAndInactiveItems() async throws {
        let collapsibleContent = try readAsset("Assets/web/collapsible_content.js")
        let html = """
        <!doctype html>
        <html>
        <body>
        <script>window.OSRS_TABLE_COLLAPSED = true;</script>
        <div class="switch-infobox">
            <div class="switch-infobox-triggers">
                <span class="trigger button" data-id="1">Normal</span>
                <span class="trigger button" data-id="2">Level 82</span>
                <span class="trigger button" data-id="3">Catacombs</span>
            </div>
            <table class="infobox">
                <caption>
                    <span class="button">Level 75</span>
                    <span class="button">Level 82</span>
                    <span class="button">Level 86</span>
                    <span class="button">Level 95</span>
                    <span class="button">Level 98</span>
                </caption>
                <tbody>
                    <tr><th class="infobox-header">Ankou</th></tr>
                    <tr class="item showing"><td>Active combat level</td></tr>
                    <tr class="item"><td>Inactive Catacombs drops</td></tr>
                </tbody>
            </table>
        </div>
        <script>\(collapsibleContent)</script>
        </body>
        </html>
        """

        try await load(html)
        let state = try await evaluate("""
        (() => {
            const headerText = document.querySelector('.collapsible-container .title-wrapper')?.innerText || '';
            return {
                headerText,
                containsTriggers: /Normal|Level 75|Level 82|Catacombs/.test(headerText),
                containsInactiveContent: /Inactive Catacombs drops/.test(headerText)
            };
        })()
        """)

        XCTAssertTrue((state["headerText"] as? String ?? "").contains("Infobox"))
        XCTAssertFalse((state["headerText"] as? String ?? "").contains("Ankou"))
        XCTAssertEqual(state["containsTriggers"] as? Bool, false)
        XCTAssertEqual(state["containsInactiveContent"] as? Bool, false)
    }

    func testSkillLandingPageCollapsesNoisyFirstUnlockTableBeforeSummary() async throws {
        let collapsibleContent = try readAsset("Assets/web/collapsible_content.js")
        let html = """
        <!doctype html>
        <html>
        <body>
        <script>window.OSRS_TABLE_COLLAPSED = true;</script>
        <h1>Crafting</h1>
        <p>Crafting is a skill that allows players to create useful items.</p>
        <table class="wikitable">
            <caption>Crafting level up table</caption>
            <tbody>
                <tr><th>Level</th><th>Unlocks</th></tr>
                <tr><td>1</td><td><img src="/images/Clay_icon.png" width="48" height="48" class="mw-file-element"> Pottery</td></tr>
                <tr><td>2</td><td>Leather gloves</td></tr>
            </tbody>
        </table>
        <table class="infobox infobox-skill">
            <caption>Crafting</caption>
            <tbody><tr><th>Members only?</th><td>No</td></tr></tbody>
        </table>
        <script>\(collapsibleContent)</script>
        </body>
        </html>
        """

        try await load(html)
        let state = try await evaluate("""
        (() => {
            const containers = Array.from(document.querySelectorAll('.collapsible-container'));
            const unlockTable = containers.find(container => container.querySelector('table.wikitable'));
            const skillSummary = containers.find(container => container.querySelector('table.skill-info, table.infobox-skill'));
            return {
                unlockCollapsed: unlockTable?.classList.contains('collapsed') || false,
                unlockHeader: unlockTable?.querySelector('.title-wrapper')?.innerText || '',
                summaryCollapsed: skillSummary ? skillSummary.classList.contains('collapsed') : true,
                summaryHeader: skillSummary?.querySelector('.title-wrapper')?.innerText || '',
                expandedWikitablesBeforeSummary: Array.from(document.querySelectorAll('.collapsible-container:not(.collapsed)')).filter(container => container.querySelector('table.wikitable') && !!skillSummary && container.compareDocumentPosition(skillSummary) & Node.DOCUMENT_POSITION_FOLLOWING).length
            };
        })()
        """)

        XCTAssertEqual(state["unlockCollapsed"] as? Bool, true)
        XCTAssertTrue((state["unlockHeader"] as? String ?? "").contains("Table"))
        XCTAssertFalse((state["unlockHeader"] as? String ?? "").contains("Crafting level up table"))
        XCTAssertEqual(state["summaryCollapsed"] as? Bool, false)
        XCTAssertTrue((state["summaryHeader"] as? String ?? "").contains("Infobox"))
        XCTAssertFalse((state["summaryHeader"] as? String ?? "").contains("Crafting"))
        XCTAssertEqual(state["expandedWikitablesBeforeSummary"] as? Int, 0)
    }

    func testStandaloneLevelUpTableHonorsCollapsePreference() async throws {
        let collapsibleContent = try readAsset("Assets/web/collapsible_content.js")
        let html = """
        <!doctype html>
        <html>
        <body>
        <script>window.OSRS_TABLE_COLLAPSED = true;</script>
        <h1>Construction/Level up table</h1>
        <table class="wikitable">
            <caption>Construction level up table</caption>
            <tbody>
                <tr><th>Level</th><th>Unlocks</th></tr>
                <tr><td>1</td><td>Crude wooden chair</td></tr>
                <tr><td>2</td><td>Decorative rock</td></tr>
            </tbody>
        </table>
        <script>\(collapsibleContent)</script>
        </body>
        </html>
        """

        try await load(html)
        let state = try await evaluate("""
        (() => {
            const primaryTable = document.querySelector('.collapsible-container');
            return {
                collapsed: primaryTable?.classList.contains('collapsed') || false,
                header: primaryTable?.querySelector('.title-wrapper')?.innerText || ''
            };
        })()
        """)

        XCTAssertEqual(state["collapsed"] as? Bool, true)
        XCTAssertTrue((state["header"] as? String ?? "").contains("Table"))
        XCTAssertFalse((state["header"] as? String ?? "").contains("Construction level up table"))
    }

    func testBroadWikitableSpritesStayCompactWhileTableCanScrollHorizontally() async throws {
        let fixesCss = try readAsset("Assets/styles/fixes.css")
        let collapsibleTablesCss = try readAsset("Assets/web/collapsible_tables.css")
        let html = """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
        :root {
            --text-color: #241c12;
            --wikitable-bg: #ded2b8;
            --wikitable-border: #9d8c70;
            --wikitable-header-bg: #b8a17c;
            --wikitable-color: #241c12;
            --colorsurfacevariant: #ded2b8;
            --coloronsurfacevariant: #241c12;
        }
        body { margin: 16px; }
        .wikitable { border-collapse: collapse; min-width: 720px; }
        .wikitable td, .wikitable th { border: 1px solid var(--wikitable-border); padding: 4px 8px; }
        \(fixesCss)
        \(collapsibleTablesCss)
        </style>
        </head>
        <body>
        <div class="collapsible-container collapsible-wikitable primary-collapsible">
            <div class="collapsible-content">
                <table class="wikitable">
                    <tbody>
                        <tr><th>Level</th><th>Unlock</th><th>Notes</th><th>More</th></tr>
                        <tr>
                            <td>1</td>
                            <td><a href="/w/Clay"><img id="plainSprite" src="/images/Clay_icon.png" width="96" height="96" class="mw-file-element"></a> Clay</td>
                            <td><span class="plinkp-template"><span class="mw-default-size"><img id="templateSprite" src="/images/Pot_icon.png" width="48" height="48" class="mw-file-element"></span></span> Pottery</td>
                            <td>Wide explanatory cell that keeps the table wider than the viewport.</td>
                        </tr>
                    </tbody>
                </table>
            </div>
        </div>
        </body>
        </html>
        """

        try await load(html)
        let state = try await evaluate("""
        (() => {
            const container = document.querySelector('.collapsible-container');
            const content = document.querySelector('.collapsible-content');
            const plain = document.getElementById('plainSprite');
            const template = document.getElementById('templateSprite');
            return {
                containerWidth: container.getBoundingClientRect().width,
                viewportWidth: document.documentElement.clientWidth,
                contentScrollWidth: content.scrollWidth,
                contentClientWidth: content.clientWidth,
                plainWidth: plain.getBoundingClientRect().width,
                plainHeight: plain.getBoundingClientRect().height,
                plainDisplay: getComputedStyle(plain).display,
                templateWidth: template.getBoundingClientRect().width,
                templateHeight: template.getBoundingClientRect().height
            };
        })()
        """)

        XCTAssertLessThanOrEqual(state["containerWidth"] as? Double ?? 999, (state["viewportWidth"] as? Double ?? 0) + 1)
        XCTAssertGreaterThan(state["contentScrollWidth"] as? Double ?? 0, state["contentClientWidth"] as? Double ?? 0)
        XCTAssertEqual(state["plainDisplay"] as? String, "inline-block")
        XCTAssertLessThanOrEqual(state["plainWidth"] as? Double ?? 999, 30)
        XCTAssertLessThanOrEqual(state["plainHeight"] as? Double ?? 999, 30)
        XCTAssertLessThanOrEqual(state["templateWidth"] as? Double ?? 999, 30)
        XCTAssertLessThanOrEqual(state["templateHeight"] as? Double ?? 999, 30)
    }

    func testSkillInfoCellSpritesDoNotBecomeFullWidthScenicImages() async throws {
        let fixesCss = try readAsset("Assets/styles/fixes.css")
        let html = """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
        body { margin: 16px; }
        .infobox-skill {
            border-collapse: collapse;
            table-layout: fixed;
            width: 340px;
        }
        .infobox-skill td {
            border: 1px solid #9d8c70;
            width: 50%;
        }
        \(fixesCss)
        </style>
        </head>
        <body>
        <table class="infobox infobox-skill">
            <tbody>
                <tr><th colspan="2">Crafting</th></tr>
                <tr>
                    <td class="infobox-full-width-content"><span class="mw-default-size" typeof="mw:File"><a class="mw-file-description" href="/w/Needle"><img id="needle" src="/images/Needle.png" width="96" height="96"></a></span></td>
                    <td class="infobox-full-width-content"><span class="mw-default-size" typeof="mw:File"><a class="mw-file-description" href="/w/Thread"><img id="thread" src="/images/Thread.png" width="96" height="96" class="mw-file-element"></a></span></td>
                </tr>
            </tbody>
        </table>
        </body>
        </html>
        """

        try await load(html)
        let state = try await evaluate("""
        (() => {
            const needle = document.getElementById('needle');
            const style = getComputedStyle(needle);
            return {
                width: needle.getBoundingClientRect().width,
                height: needle.getBoundingClientRect().height,
                display: style.display,
                marginTop: parseFloat(style.marginTop)
            };
        })()
        """)

        XCTAssertEqual(state["display"] as? String, "inline-block")
        XCTAssertLessThanOrEqual(state["width"] as? Double ?? 999, 64)
        XCTAssertLessThanOrEqual(state["height"] as? Double ?? 999, 64)
        XCTAssertEqual(state["marginTop"] as? Double ?? -1, 0, accuracy: 0.5)
    }

    func testTrailblazerNarrowTablesAndTemplateIconsKeepIntrinsicSizing() async throws {
        let collapsibleContent = try readAsset("Assets/web/collapsible_content.js")
        let fixesCss = try readAsset("Assets/styles/fixes.css")
        let html = """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
        :root {
            --text-color: #f4eaea;
            --wikitable-bg: #3e362f;
            --wikitable-border: #736559;
            --body-light: #3e362f;
            --body-border: #736559;
        }
        .wikitable {
            border-collapse: collapse;
        }
        .wikitable td,
        .wikitable th {
            padding: 4px 8px;
        }
        \(fixesCss)
        </style>
        </head>
        <body>
        <script>window.OSRS_TABLE_COLLAPSED = true;</script>
        <table class="wikitable" style="float:right; clear:right; text-align:center; margin-left:1em;">
            <tbody>
                <tr><th scope="row" colspan="3">Trailblazer Reloaded</th></tr>
                <tr>
                    <td><span class="plinkp-template"><span class="mw-default-size" typeof="mw:File"><a href="/w/Trailblazer_Reloaded_League/Guide/Quests"><img src="/images/Quest_point_icon.png" width="21" height="21" class="mw-file-element"></a></span></span></td>
                    <td><span class="plinkp-template"><span class="mw-default-size" typeof="mw:File"><a href="/w/Trailblazer_Reloaded_League/Tasks"><img src="/images/Trailblazer_Reloaded_League_icon.png" width="22" height="22" class="mw-file-element"></a></span></span></td>
                    <td><span class="plinkp-template"><span class="mw-default-size" typeof="mw:File"><a href="/w/Trailblazer_Reloaded_League/Relics"><img id="unknownRelic" src="/images/Trailblazer_Reloaded_League_-_%3F_Relic.png" width="30" height="30" class="mw-file-element"></a></span></span></td>
                </tr>
            </tbody>
        </table>
        <p>Tasks per region are as follows:</p>
        <table class="wikitable sortable tbrl-tasks"><tbody><tr><th>Area</th><th>Task</th><th>Comp%</th><th>Difficulty</th><th>Points</th></tr><tr><td>General</td><td>Open the Leagues Menu</td><td>99%</td><td>Easy</td><td>10</td></tr></tbody></table>
        <script>\(collapsibleContent)</script>
        </body>
        </html>
        """

        try await load(html)
        let state = try await evaluate("""
        (() => {
            const containers = Array.from(document.querySelectorAll('.collapsible-container'));
            const narrow = containers[0];
            const wide = containers[1];
            const narrowRect = narrow.getBoundingClientRect();
            const wideRect = wide.getBoundingClientRect();
            const image = document.getElementById('unknownRelic');
            const imageRect = image.getBoundingClientRect();
            return {
                narrowHasIntrinsicClass: narrow.classList.contains('collapsible-intrinsic-table'),
                wideHasIntrinsicClass: wide.classList.contains('collapsible-intrinsic-table'),
                narrowWidth: narrowRect.width,
                wideWidth: wideRect.width,
                viewportWidth: document.documentElement.clientWidth,
                imageWidth: imageRect.width,
                imageHeight: imageRect.height,
                imageDisplay: getComputedStyle(image).display,
                imageMarginTop: parseFloat(getComputedStyle(image).marginTop)
            };
        })()
        """)

        XCTAssertEqual(state["narrowHasIntrinsicClass"] as? Bool, true)
        XCTAssertEqual(state["wideHasIntrinsicClass"] as? Bool, false)
        XCTAssertLessThan(state["narrowWidth"] as? Double ?? 0, (state["viewportWidth"] as? Double ?? 0) * 0.8)
        XCTAssertGreaterThan((state["wideWidth"] as? Double ?? 0), (state["narrowWidth"] as? Double ?? 0))
        XCTAssertEqual(state["imageDisplay"] as? String, "inline-block")
        XCTAssertEqual(state["imageWidth"] as? Double ?? 0, 30, accuracy: 1)
        XCTAssertEqual(state["imageHeight"] as? Double ?? 0, 30, accuracy: 1)
        XCTAssertEqual(state["imageMarginTop"] as? Double ?? -1, 0, accuracy: 0.5)
    }

    func testAccessibilityReflowCssContainsFloatsAndMessageBoxes() async throws {
        let baseCss = try readAsset("Assets/styles/base.css")
        let layoutCss = try readAsset("Assets/styles/layout.css")
        let fixesCss = try readAsset("Assets/styles/fixes.css")
        let html = """
        <!doctype html>
        <html class="osrs-accessibility-reflow" style="--osrs-article-text-scale: 1.5;">
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>\(baseCss)\n\(layoutCss)\n\(fixesCss)</style>
        </head>
        <body class="osrs-accessibility-reflow">
        <figure class="mw-halign-left" style="width: 360px;"><img alt="" src="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==" style="width: 360px; height: 80px;"></figure>
        <p id="lead">The dragon scimitar is the strongest scimitar available in Old School RuneScape.</p>
        <table class="messagebox"><tbody><tr><td class="messagebox-image">!</td><td>Risk warning text that should stay inside the viewport.</td></tr></tbody></table>
        </body>
        </html>
        """

        try await load(html)
        let state = try await evaluate("""
        (() => {
            const figure = document.querySelector('figure');
            const messagebox = document.querySelector('.messagebox');
            return {
                figureFloat: getComputedStyle(figure).float,
                figureWidth: figure.getBoundingClientRect().width,
                viewportWidth: document.documentElement.clientWidth,
                scrollWidth: document.documentElement.scrollWidth,
                messageboxDisplay: getComputedStyle(messagebox).display,
                bodyFontSize: parseFloat(getComputedStyle(document.body).fontSize)
            };
        })()
        """)

        XCTAssertEqual(state["figureFloat"] as? String, "none")
        XCTAssertLessThanOrEqual(state["scrollWidth"] as? Double ?? 1, state["viewportWidth"] as? Double ?? 0)
        XCTAssertEqual(state["messageboxDisplay"] as? String, "block")
        XCTAssertGreaterThan(state["bodyFontSize"] as? Double ?? 0, 20)
    }

    func testInArticleTocCaptionsAndProseBannersStayFullWidthThemedAndUnscrolled() async throws {
        let polish = try readAsset("Assets/web/mobile_article_polish.js")
        let interceptor = try readAsset("Assets/web/horizontal_scroll_interceptor.js")
        let fixes = try readAsset("Assets/styles/fixes.css")
        let pixel = "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw=="
        let html = """
        <!doctype html>
        <html style="--text-color:#112233;">
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        html, body { margin: 0; width: 375px; }
        \(fixes)
        </style>
        </head>
        <body>
          <figure class="mw-halign-left" style="float:left;width:150px;height:180px;margin:0;">
            <img class="mw-file-element" width="150" height="180" src="\(pixel)">
          </figure>
          <p>Short lead that wraps beside the vignette.</p>
          <div id="toc" class="toc"><div class="toctitle"><h2>Contents</h2></div><ul><li>Details</li></ul></div>
          <table class="messagebox" role="presentation">
            <tbody><tr>
              <td class="messagebox-image">!</td>
              <td>
                <span class="messagebox-title"><b>This quest has a quick guide.</b></span>
                <div class="messagebox-text">It briefly summarises the steps needed to complete the quest.</div>
              </td>
            </tr></tbody>
          </table>
          <figure><img src="\(pixel)" width="80" height="80"><figcaption id="plainCaption">A themed figure caption.</figcaption></figure>
          <div class="thumbinner"><div class="thumbcaption" id="mapCaption">Slepe, showing locations of the church</div></div>
          <script>\(polish)</script>
          <script>\(interceptor)</script>
        </body>
        </html>
        """

        try await load(html)
        let state = try await evaluate("""
        (() => {
            window.OSRSApplyArticlePolish();
            const toc = document.querySelector('#toc');
            const box = document.querySelector('table.messagebox');
            const caption = document.getElementById('plainCaption');
            const mapCaption = document.getElementById('mapCaption');
            const tocCs = getComputedStyle(toc);
            return {
                tocDisplay: tocCs.display,
                tocClear: tocCs.clear,
                tocWidth: toc.getBoundingClientRect().width,
                viewportWidth: document.documentElement.clientWidth,
                messageboxParent: box.parentElement && box.parentElement.className,
                messageboxScrollWidth: box.scrollWidth,
                messageboxClientWidth: box.clientWidth,
                messageboxSurface: !!box.closest('.osrs-local-scroll-surface'),
                captionColor: getComputedStyle(caption).color,
                mapCaptionColor: getComputedStyle(mapCaption).color
            };
        })()
        """)

        XCTAssertEqual(state["tocDisplay"] as? String, "block")
        XCTAssertEqual(state["tocClear"] as? String, "both")
        XCTAssertGreaterThanOrEqual(state["tocWidth"] as? Double ?? 0, (state["viewportWidth"] as? Double ?? 0) - 8)
        XCTAssertEqual(state["messageboxSurface"] as? Bool, false)
        XCTAssertFalse((state["messageboxParent"] as? String ?? "").contains("osrs-article-scroll-region"))
        XCTAssertLessThanOrEqual(
            (state["messageboxScrollWidth"] as? Double ?? 99) - (state["messageboxClientWidth"] as? Double ?? 0),
            2
        )
        XCTAssertEqual(state["captionColor"] as? String, "rgb(17, 34, 51)")
        XCTAssertEqual(state["mapCaptionColor"] as? String, "rgb(17, 34, 51)")
    }

    func testMobileArticlePolishUsesSemanticTableRolesWithoutVisualScrollCues() async throws {
        let polish = try readAsset("Assets/web/mobile_article_polish.js")
        let horizontalScroll = try readAsset("Assets/web/horizontal_scroll_interceptor.js")
        let fixes = try readAsset("Assets/styles/fixes.css")
        let switchInfoboxStyles = try readAsset("Assets/web/switch_infobox_styles.css")
        let pixel = "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw=="
        // Intrinsic 32x32 bitmap: width:auto + height:auto use the image size, not the HTML attributes.
        let bitmap32 = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAAKklEQVR42mMwnplGU8QwasGoBaMWjFowasGoBaMWjFowasGoBaMWjFowasGoBaMWDBULAHLzyD25ip3jAAAAAElFTkSuQmCC"
        let html = """
        <!doctype html>
        <html>
        <head><meta name="viewport" content="width=device-width, initial-scale=1"><style>\(switchInfoboxStyles)\n\(fixes)</style></head>
        <body>
          <p id="transport">Walk <span style="padding:25.6px"><span><img id="inline" class="mw-file-element" width="32" height="32" src="\(bitmap32)"></span></span> north.</p>
          <table class="infobox"><tbody><tr><td class="infobox-image"><img id="portrait" class="mw-file-element" width="130" height="367" src="\(pixel)"></td></tr></tbody></table>
          <figure id="vignette" class="mw-halign-left"><img class="mw-file-element" width="140" height="251" src="\(pixel)"></figure>
          <div class="collapsible-content" id="collapse"><table class="wikitable" style="min-width:720px"><tbody><tr><td>Combat stats</td></tr></tbody></table></div>
          <div class="collapsible-primary-infobox"><div id="primary" class="collapsible-content"><table id="switch" class="main-infobox infobox infobox-switch" style="min-width:620px;float:right"><caption>Item states</caption><tbody><tr><td>Responsive switch infobox content that wraps</td></tr><tr><td><div id="stateControls" class="infobox-buttons"><span id="stateOne" class="button">State A</span><span id="stateTwo" class="button">State B</span></div></td></tr></tbody></table></div></div>
          <table id="bonuses" class="infobox infobox-switch infobox-bonuses" style="min-width:720px;float:right"><caption>Combat stats</caption><tbody><tr><td>Wide bonuses</td></tr></tbody></table>
          <div class="recipe-table" id="recipe"><table class="wikitable"><tbody><tr><td>Requirements</td></tr></tbody></table></div>
          <div class="collapsible-container"><div id="mapContent" class="collapsible-content"><table id="mapTable" class="wikitable"><tbody><tr><th>Destination</th><th>Map</th></tr><tr><td>Edgeville</td><td><span class="mw-kartographer-map" style="display:block;width:200px;height:200px"></span></td></tr></tbody></table></div></div>
          <script>\(polish)</script>
          <script>\(horizontalScroll)</script>
        </body>
        </html>
        """

        try await load(html)
        let state = try await evaluate("""
        (() => {
          window.OSRSApplyArticlePolish();
          window.OSRSArticleMetrics.refreshHorizontalScrollAffordances();
          const inline = document.getElementById('inline');
          const portrait = document.getElementById('portrait');
          const collapse = document.getElementById('collapse');
          const recipe = document.getElementById('recipe');
          const switchTable = document.getElementById('switch');
          const primary = document.getElementById('primary');
          const stateControls = document.getElementById('stateControls');
          const stateOne = document.getElementById('stateOne');
          const stateTwo = document.getElementById('stateTwo');
          const bonusesSurface = document.getElementById('bonuses').parentElement;
          const bonusesMaxScroll = bonusesSurface.scrollWidth - bonusesSurface.clientWidth;
          bonusesSurface.scrollLeft = bonusesMaxScroll / 2;
          bonusesSurface.dispatchEvent(new Event('scroll'));
          const mapTable = document.getElementById('mapTable');
          const mapContent = document.getElementById('mapContent');
          return {
            inlineClass: inline.classList.contains('osrs-inline-icon'),
            inlineDisplay: getComputedStyle(inline).display,
            inlineWidth: inline.getBoundingClientRect().width,
            notePaddingLeft: parseFloat(getComputedStyle(inline.closest('[style]')).paddingLeft),
            portraitClass: portrait.classList.contains('osrs-balanced-portrait'),
            portraitWidth: portrait.getBoundingClientRect().width,
            portraitHeight: portrait.getBoundingClientRect().height,
            vignetteClass: document.getElementById('vignette').classList.contains('osrs-balanced-vignette'),
            vignetteWidth: document.getElementById('vignette').getBoundingClientRect().width,
            vignetteHeight: document.getElementById('vignette').getBoundingClientRect().height,
            scrollClass: collapse.classList.contains('osrs-article-scroll-region'),
            scrollOverflow: getComputedStyle(collapse).overflowX,
            scrollAffordance: collapse.classList.contains('osrs-scroll-affordance'),
            scrollCanRight: collapse.classList.contains('osrs-scroll-can-right'),
            scrollMetricsCount: window.OSRSArticleMetrics.collect().tableAffordanceCanRightCount,
            cueCount: document.querySelectorAll('.osrs-scroll-cue-layer').length,
            primaryScrollable: primary.classList.contains('osrs-local-scroll-surface') || primary.classList.contains('osrs-article-scroll-region'),
            primaryOverflow: getComputedStyle(primary).overflowX,
            switchFloat: getComputedStyle(switchTable).float,
            switchWidth: switchTable.getBoundingClientRect().width,
            primaryWidth: primary.clientWidth,
            stateControlGap: stateTwo.getBoundingClientRect().left - stateOne.getBoundingClientRect().right,
            stateControlCssGap: parseFloat(getComputedStyle(stateControls).columnGap),
            stateControlMargin: parseFloat(getComputedStyle(stateOne).marginLeft),
            stateControlPadding: parseFloat(getComputedStyle(stateOne).paddingLeft),
            bonusesWrapped: document.getElementById('bonuses').parentElement.classList.contains('osrs-article-scroll-region'),
            bonusesFloat: getComputedStyle(document.getElementById('bonuses')).float,
            bonusesOverflow: bonusesMaxScroll,
            bonusesWidth: bonusesSurface.getBoundingClientRect().width,
            recipeClass: recipe.classList.contains('osrs-intrinsic-table'),
            recipeWidth: recipe.getBoundingClientRect().width,
            mapClass: mapTable.classList.contains('osrs-map-table'),
            mapScrollable: mapContent.classList.contains('osrs-local-scroll-surface') || mapContent.classList.contains('osrs-article-scroll-region'),
            mapWidth: mapTable.getBoundingClientRect().width,
            documentOverflow: document.documentElement.scrollWidth - document.documentElement.clientWidth
          };
        })()
        """)

        XCTAssertEqual(state["inlineClass"] as? Bool, true)
        let inlineDisplay = state["inlineDisplay"] as? String
        XCTAssertTrue(
            inlineDisplay == "inline" || inlineDisplay == "inline-block",
            "prose icons must stay in the line box, not become block; got \(inlineDisplay ?? "nil")"
        )
        XCTAssertGreaterThanOrEqual(state["inlineWidth"] as? Double ?? 0, 28)
        XCTAssertLessThanOrEqual(state["inlineWidth"] as? Double ?? 100, 48)
        XCTAssertEqual(state["notePaddingLeft"] as? Double ?? -1, 0, accuracy: 0.5)
        XCTAssertEqual(state["portraitClass"] as? Bool, true)
        XCTAssertLessThanOrEqual(state["portraitWidth"] as? Double ?? 999, 220)
        XCTAssertLessThanOrEqual(state["portraitHeight"] as? Double ?? 999, 280)
        XCTAssertEqual(state["vignetteClass"] as? Bool, true)
        XCTAssertLessThanOrEqual(state["vignetteWidth"] as? Double ?? 999, 112.5)
        XCTAssertLessThanOrEqual(state["vignetteHeight"] as? Double ?? 999, 196.5)
        XCTAssertEqual(state["scrollClass"] as? Bool, true)
        XCTAssertEqual(state["scrollOverflow"] as? String, "auto")
        XCTAssertEqual(state["scrollAffordance"] as? Bool, true)
        XCTAssertEqual(state["scrollCanRight"] as? Bool, true)
        XCTAssertGreaterThanOrEqual(state["scrollMetricsCount"] as? Int ?? 0, 1)
        XCTAssertEqual(state["cueCount"] as? Int, 0)
        XCTAssertEqual(state["primaryScrollable"] as? Bool, false)
        XCTAssertEqual(state["primaryOverflow"] as? String, "hidden")
        XCTAssertEqual(state["switchFloat"] as? String, "none")
        XCTAssertLessThanOrEqual(state["switchWidth"] as? Double ?? 999, (state["primaryWidth"] as? Double ?? 0) + 0.5)
        XCTAssertGreaterThan(state["stateControlGap"] as? Double ?? 0, 0)
        XCTAssertLessThanOrEqual(state["stateControlGap"] as? Double ?? 999, 4.1)
        XCTAssertLessThanOrEqual(state["stateControlCssGap"] as? Double ?? 999, 4.1)
        XCTAssertEqual(state["stateControlMargin"] as? Double ?? -1, 0, accuracy: 0.1)
        XCTAssertLessThanOrEqual(state["stateControlPadding"] as? Double ?? 999, 8.1)
        XCTAssertEqual(state["bonusesWrapped"] as? Bool, true)
        XCTAssertEqual(state["bonusesFloat"] as? String, "none")
        XCTAssertGreaterThan(state["bonusesOverflow"] as? Double ?? 0, 20)
        XCTAssertLessThan(state["bonusesWidth"] as? Double ?? 999, 550)
        XCTAssertEqual(state["recipeClass"] as? Bool, true)
        XCTAssertLessThan(state["recipeWidth"] as? Double ?? 999, 360)
        XCTAssertEqual(state["mapClass"] as? Bool, true)
        XCTAssertEqual(state["mapScrollable"] as? Bool, false)
        XCTAssertLessThanOrEqual(state["mapWidth"] as? Double ?? 999, 360.5)
        XCTAssertLessThanOrEqual(state["documentOverflow"] as? Double ?? 1, 0.5)
    }

    func testIconPlusAuthoredProseKeepsWrappedLineBoxes() async throws {
        let polish = try readAsset("Assets/web/mobile_article_polish.js")
        let fixes = try readAsset("Assets/styles/fixes.css")
        let iosAesthetics = try readAsset("Assets/styles/ios-article-aesthetics.css")
        XCTAssertTrue(polish.contains("osrsWrapperIsIconChrome"))
        XCTAssertTrue(polish.contains("osrs-inline-icon-prose"))
        XCTAssertTrue(fixes.contains(".osrs-inline-icon-prose"))
        XCTAssertTrue(iosAesthetics.contains(".osrs-inline-icon-prose"))
        XCTAssertFalse(polish.contains("[style*=\"padding\"]"))

        let bitmap = "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw=="
        webView.frame = CGRect(x: 0, y: 0, width: 320, height: 812)
        let html = """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            body { margin: 8px; font: 16px/1.5 -apple-system, sans-serif; width: 180px; }
            \(fixes)
            \(iosAesthetics)
          </style>
        </head>
        <body>
          <div class="mw-parser-output mw-body-content">
            <p id="lore">
              <span id="group" style="padding:25.6px; text-align:center; font-size:10pt;">
                <span typeof="mw:File"><span>
                  <img class="mw-file-element" width="18" height="17" src="\(bitmap)">
                </span></span>
                <i id="sentence">The following lore is sourced from the Varrock Museum</i>.
              </span>
            </p>
            <p id="follow">169 years ago, the lost art of Runecraft was rediscovered.</p>
          </div>
          <script>\(polish)</script>
        </body>
        </html>
        """

        try await load(html)
        let state = try await evaluate("""
        (() => {
          window.OSRSApplyArticlePolish();
          const lore = document.getElementById('lore');
          const group = document.getElementById('group');
          const sentence = document.getElementById('sentence');
          const loreStyle = getComputedStyle(lore);
          const groupStyle = getComputedStyle(group);
          const sentenceStyle = getComputedStyle(sentence);
          const loreRect = lore.getBoundingClientRect();
          const followRect = document.getElementById('follow').getBoundingClientRect();
          const sentenceLineHeight = parseFloat(sentenceStyle.lineHeight) || parseFloat(sentenceStyle.fontSize) * 1.2;
          const sentenceRects = Array.from(sentence.getClientRects());
          return {
            groupIsWrapper: group.classList.contains('osrs-inline-icon-wrapper'),
            groupIsProse: group.classList.contains('osrs-inline-icon-prose'),
            paragraphClass: lore.classList.contains('osrs-inline-lore-paragraph'),
            groupDisplay: groupStyle.display,
            groupOverflow: groupStyle.overflow,
            groupLineHeight: groupStyle.lineHeight,
            sentenceLineHeight,
            sentenceRectCount: sentenceRects.length,
            sentenceHeight: sentence.getBoundingClientRect().height,
            sentenceScrollHeight: sentence.scrollHeight,
            loreHeight: loreRect.height,
            loreOverflow: loreStyle.overflow,
            gapToFollow: followRect.top - loreRect.bottom,
            innerWrapper: !!group.querySelector('.osrs-inline-icon-wrapper')
          };
        })()
        """)

        XCTAssertEqual(state["groupIsWrapper"] as? Bool, false)
        XCTAssertEqual(state["groupIsProse"] as? Bool, true)
        XCTAssertEqual(state["paragraphClass"] as? Bool, true)
        XCTAssertEqual(state["groupDisplay"] as? String, "block")
        XCTAssertEqual(state["groupOverflow"] as? String, "visible")
        XCTAssertNotEqual(state["groupLineHeight"] as? String, "0px")
        XCTAssertGreaterThanOrEqual(state["sentenceRectCount"] as? Int ?? 0, 2)
        XCTAssertGreaterThan(state["loreHeight"] as? Double ?? 0, (state["sentenceLineHeight"] as? Double ?? 0) * 1.6)
        XCTAssertGreaterThanOrEqual(state["gapToFollow"] as? Double ?? -99, -1)
        XCTAssertEqual(state["innerWrapper"] as? Bool, true)
    }

    func testWideDisclosureOwnsHorizontalGesturesAcrossHeaderAndContent() async throws {
        let polish = try readAsset("Assets/web/mobile_article_polish.js")
        let horizontalScroll = try readAsset("Assets/web/horizontal_scroll_interceptor.js")
        let fixes = try readAsset("Assets/styles/fixes.css")
        let html = """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>\(fixes)</style>
        </head>
        <body>
          <div class="collapsible-container" style="width:320px">
            <div id="combatHeader" class="collapsible-header">
              <span class="collapsible-label">Combat stats</span>
            </div>
            <div id="combatContent" class="collapsible-content" style="width:320px">
              <table id="combatTable" class="wikitable infobox-bonuses" style="min-width:720px">
                <tbody><tr><td>Attack bonus</td><td>Defence bonus</td><td>Other bonuses</td></tr></tbody>
              </table>
            </div>
          </div>
          <p id="ordinaryArticleText">Ordinary article navigation content.</p>
          <script>\(polish)</script>
          <script>\(horizontalScroll)</script>
        </body>
        </html>
        """

        try await load(html)
        let state = try await evaluate("""
        (() => {
          window.OSRSApplyArticlePolish();
          window.OSRSArticleMetrics.refreshHorizontalScrollAffordances();
          const surface = document.getElementById('combatContent');
          const header = document.getElementById('combatHeader');
          const tableCell = document.querySelector('#combatTable td');
          const ordinary = document.getElementById('ordinaryArticleText');
          const classify = (element) => {
            const rect = element.getBoundingClientRect();
            return window.OSRSArticleGestureOwnership.classifyPoint(
              rect.left + Math.min(24, rect.width / 2),
              rect.top + Math.min(10, rect.height / 2)
            );
          };
          return {
            isLocalSurface: surface.classList.contains('osrs-local-scroll-surface'),
            overflow: surface.scrollWidth - surface.clientWidth,
            label: surface.getAttribute('aria-label') || '',
            headerOwnership: classify(header),
            contentOwnership: classify(tableCell),
            ordinaryOwnership: classify(ordinary),
            cueCount: document.querySelectorAll('.osrs-scroll-cue-layer').length
          };
        })()
        """)

        XCTAssertEqual(state["isLocalSurface"] as? Bool, true)
        XCTAssertGreaterThan(state["overflow"] as? Double ?? 0, 20)
        XCTAssertEqual(state["label"] as? String, "Scrollable Combat stats table")
        let headerOwnership = state["headerOwnership"] as? [String: Any]
        let contentOwnership = state["contentOwnership"] as? [String: Any]
        let ordinaryOwnership = state["ordinaryOwnership"] as? [String: Any]
        XCTAssertEqual(headerOwnership?["isLocalOwner"] as? Bool, true)
        XCTAssertEqual(headerOwnership?["ownerId"] as? String, "Scrollable Combat stats table")
        XCTAssertEqual(contentOwnership?["isLocalOwner"] as? Bool, true)
        XCTAssertEqual(ordinaryOwnership?["isLocalOwner"] as? Bool, false)
        XCTAssertEqual(state["cueCount"] as? Int, 0)
    }

    func testRecipeTablesBecomeOrderedAccessibleSemanticDisclosures() async throws {
        let collapsibleContent = try readAsset("Assets/web/collapsible_content.js")
        let fixes = try readAsset("Assets/styles/fixes.css")
        let collapsibleTables = try readAsset("Assets/web/collapsible_tables.css")
        let html = """
        <!doctype html>
        <html>
        <head><meta name="viewport" content="width=device-width, initial-scale=1"><style>\(fixes)\n\(collapsibleTables)</style></head>
        <body>
          <script>window.OSRS_TABLE_COLLAPSED = false;</script>
          <div class="recipe-table" id="creationRecipe">
            <table class="wikitable"><caption>Materials</caption><tbody><tr><th>Item</th><th>Quantity</th></tr><tr><td>Metal bar</td><td>1</td></tr></tbody></table>
            <table class="wikitable"><tbody><tr><th>Skill</th><th>Level required</th></tr><tr><td>Crafting</td><td>80</td></tr></tbody></table>
            <table class="wikitable"><caption>By-products</caption><tbody><tr><th>Result</th><th>Chance</th></tr><tr><td>Dust</td><td>1/10</td></tr></tbody></table>
            <table class="wikitable"><tbody><tr><th>Method</th><th>Notes</th></tr><tr><td>Alternative</td><td>Optional</td></tr></tbody></table>
            <table class="wikitable"><tbody><tr><th>Ingredients</th><th>Quantity</th></tr><tr><td>Gem</td><td>1</td></tr></tbody></table>
          </div>
          <div class="recipe-table" id="negativeRecipe">
            <table role="presentation"><tbody><tr><td>Layout shell</td></tr></tbody></table>
            <table class="navbox"><tbody><tr><td>Navigation</td></tr></tbody></table>
            <aside><table class="wikitable"><caption>Nested reference</caption><tbody><tr><td>Not a direct child</td></tr></tbody></table></aside>
          </div>
          <script>\(collapsibleContent)</script>
        </body>
        </html>
        """

        try await load(html)
        let state = try await evaluate("""
        (() => {
          const recipe = document.getElementById('creationRecipe');
          const containers = Array.from(recipe.querySelectorAll(':scope > .collapsible-recipe-table'));
          const captions = Array.from(recipe.querySelectorAll(':scope > .collapsible-recipe-table caption'));
          const beforeSecondPass = document.querySelectorAll('.collapsible-recipe-table').length;
          window.OSRSInitializeCollapsibleContent();
          return {
            containerCount: document.querySelectorAll('.collapsible-recipe-table').length,
            tableCount: recipe.querySelectorAll('table.wikitable').length,
            beforeSecondPass,
            labels: containers.map(container => container.querySelector('.collapsible-label')?.textContent || ''),
            roles: containers.map(container => container.dataset.osrsTableRole || ''),
            captionsRepresented: captions.every(caption => caption.hidden && caption.dataset.osrsCaptionHiddenByDisclosure === 'true'),
            accessibilityContracts: containers.every(container => {
              const header = container.querySelector(':scope > .collapsible-header');
              const content = container.querySelector(':scope > .collapsible-content');
              return header?.getAttribute('role') === 'button' &&
                header?.getAttribute('tabindex') === '0' &&
                header?.getAttribute('aria-controls') === content?.id &&
                content?.getAttribute('aria-labelledby') === header?.id;
            }),
            duplicateVisibleLabels: containers.filter(container => {
              const label = (container.querySelector('.collapsible-label')?.textContent || '')
                .replace(/\\s+\\(\\d+\\)$/, '').trim().toLowerCase();
              return Array.from(container.querySelectorAll('caption, th')).some(element =>
                !element.hidden && element.textContent.trim().toLowerCase() === label
              );
            }).length,
            wrapperInsideDisclosure: !!recipe.parentElement.closest('.collapsible-container'),
            negativeRecipeControls: document.getElementById('negativeRecipe').querySelectorAll('.collapsible-recipe-table').length,
            containerWidths: containers.map(container => container.getBoundingClientRect().width),
            viewportWidth: document.documentElement.clientWidth,
            footerDisplays: containers.map(container => getComputedStyle(container.querySelector('.collapsible-close-footer')).display)
          };
        })()
        """)

        XCTAssertEqual(state["containerCount"] as? Int, 5)
        XCTAssertEqual(state["tableCount"] as? Int, 5)
        XCTAssertEqual(state["beforeSecondPass"] as? Int, 5)
        XCTAssertEqual(
            state["labels"] as? [String],
            ["Materials", "Requirements", "By-products", "Method / Notes", "Materials (2)"]
        )
        XCTAssertEqual(
            state["roles"] as? [String],
            ["recipe-materials", "recipe-requirements", "recipe-other", "recipe-other", "recipe-materials"]
        )
        XCTAssertEqual(state["captionsRepresented"] as? Bool, true)
        XCTAssertEqual(state["accessibilityContracts"] as? Bool, true)
        XCTAssertEqual(state["duplicateVisibleLabels"] as? Int, 0)
        XCTAssertEqual(state["wrapperInsideDisclosure"] as? Bool, false)
        XCTAssertEqual(state["negativeRecipeControls"] as? Int, 0)
        XCTAssertTrue((state["containerWidths"] as? [Double] ?? []).allSatisfy {
            $0 < (state["viewportWidth"] as? Double ?? 0)
        })
        XCTAssertEqual(state["footerDisplays"] as? [String], Array(repeating: "block", count: 5))
    }

    func testTeleportationOptionsKeepsFourMapsInOneContainedDisclosureAcrossCollapseCycles() async throws {
        let collapsibleContent = try readAsset("Assets/web/collapsible_content.js")
        let fixes = try readAsset("Assets/styles/fixes.css")
        let mapRows = (1...4).map { index in
            "<tr><td>Destination \(index)</td><td><span class=\"mw-kartographer-map\" data-lat=\"320\(index)\" data-lon=\"321\(index)\" data-zoom=\"5\" data-plane=\"0\" style=\"display:block;width:200px;height:80px\"></span></td></tr>"
        }.joined()
        let html = """
        <!doctype html>
        <html>
        <head><meta name="viewport" content="width=device-width, initial-scale=1"><style>\(fixes)</style></head>
        <body>
          <script>
            window.OSRS_TABLE_COLLAPSED = true;
            window.__mapMeasurements = [];
            window.__mapToggles = [];
            window.OsrsWikiBridge = {
              onMapPlaceholderMeasured(id, rectJson, mapDataJson) { window.__mapMeasurements.push({ id, rectJson, mapDataJson }); },
              onCollapsibleToggled(id, isOpening) { window.__mapToggles.push({ id, isOpening }); }
            };
          </script>
          <table class="wikitable"><caption>Earlier table</caption><tbody><tr><td>Earlier content</td></tr></tbody></table>
          <h2>Teleportation options</h2>
          <table id="teleports" class="wikitable"><tbody><tr><th>Destination</th><th>Map</th></tr>\(mapRows)</tbody></table>
          <script>\(collapsibleContent)</script>
        </body>
        </html>
        """

        try await load(html)
        let initialAndRapidClose = try await evaluate("""
        (() => {
          const table = document.getElementById('teleports');
          const container = table.closest('.collapsible-container');
          const header = container.querySelector('.collapsible-header');
          const ids = Array.from(table.querySelectorAll('.mw-kartographer-map')).map(map => map.id);
          const measurementsBeforeOpen = window.__mapMeasurements.length;
          header.click();
          const firstOpenToggleCount = window.__mapToggles.filter(toggle => toggle.isOpening === true).length;
          header.click();
          return {
            ids,
            uniqueIds: new Set(ids.filter(Boolean)).size,
            measurementsBeforeOpen,
            firstOpenToggleCount,
            closeToggleCount: window.__mapToggles.filter(toggle => toggle.isOpening === false).length,
            terminalCollapsed: container.classList.contains('collapsed')
          };
        })()
        """)
        XCTAssertEqual(initialAndRapidClose["uniqueIds"] as? Int, 4)
        XCTAssertEqual(initialAndRapidClose["measurementsBeforeOpen"] as? Int, 0)
        XCTAssertEqual(initialAndRapidClose["firstOpenToggleCount"] as? Int, 4)
        XCTAssertEqual(initialAndRapidClose["closeToggleCount"] as? Int, 4)
        XCTAssertEqual(initialAndRapidClose["terminalCollapsed"] as? Bool, true)
        try await Task.sleep(nanoseconds: 300_000_000)

        let afterRapidClose = try await evaluate("""
        (() => ({
          measurementCount: window.__mapMeasurements.length,
          collapsed: document.getElementById('teleports').closest('.collapsible-container').classList.contains('collapsed')
        }))()
        """)
        XCTAssertEqual(afterRapidClose["measurementCount"] as? Int, 0)
        XCTAssertEqual(afterRapidClose["collapsed"] as? Bool, true)

        _ = try await evaluate("""
        (() => {
          const container = document.getElementById('teleports').closest('.collapsible-container');
          container.querySelector('.collapsible-header').click();
          return true;
        })()
        """)
        try await Task.sleep(nanoseconds: 300_000_000)

        let firstMeasurementState = try await evaluate("""
        (() => {
          const table = document.getElementById('teleports');
          const container = table.closest('.collapsible-container');
          const ids = Array.from(table.querySelectorAll('.mw-kartographer-map')).map(map => map.id);
          return {
            label: container.querySelector('.collapsible-label')?.textContent || '',
            mapCount: ids.length,
            uniqueIds: new Set(ids.filter(Boolean)).size,
            measuredIds: Array.from(new Set(window.__mapMeasurements.map(item => item.id))).sort(),
            measurementCount: window.__mapMeasurements.length,
            closeToggleCount: window.__mapToggles.filter(toggle => toggle.isOpening === false).length,
            openToggleCount: window.__mapToggles.filter(toggle => toggle.isOpening === true).length,
            tableWidth: table.getBoundingClientRect().width,
            destWidth: table.querySelector('td')?.getBoundingClientRect().width || 0,
            mapWidth: table.querySelector('td:has(.mw-kartographer-map)')?.getBoundingClientRect().width || 0,
            viewportWidth: document.documentElement.clientWidth,
            zeroSizedMapCount: Array.from(table.querySelectorAll('.mw-kartographer-map')).filter(map => {
              const rect = map.getBoundingClientRect();
              return rect.width <= 0 || rect.height <= 0;
            }).length,
            contentHeight: container.querySelector('.collapsible-content').getBoundingClientRect().height,
            bridgeAvailable: !!window.OsrsWikiBridge,
            measureFunctionAvailable: typeof window.measureAndPreloadMaps === 'function',
            locallyScrollable: container.querySelector('.collapsible-content').classList.contains('osrs-local-scroll-surface'),
            expanded: !container.classList.contains('collapsed')
          };
        })()
        """)

        XCTAssertEqual(firstMeasurementState["label"] as? String, "Teleportation options")
        XCTAssertEqual(firstMeasurementState["mapCount"] as? Int, 4)
        XCTAssertEqual(firstMeasurementState["uniqueIds"] as? Int, 4)
        XCTAssertEqual(firstMeasurementState["zeroSizedMapCount"] as? Int, 0, "\(firstMeasurementState)")
        XCTAssertEqual((firstMeasurementState["measuredIds"] as? [String])?.count, 4, "\(firstMeasurementState)")
        XCTAssertGreaterThanOrEqual(firstMeasurementState["measurementCount"] as? Int ?? 0, 4, "\(firstMeasurementState)")
        XCTAssertEqual(firstMeasurementState["closeToggleCount"] as? Int, 4)
        XCTAssertEqual(firstMeasurementState["openToggleCount"] as? Int, 8)
        XCTAssertLessThanOrEqual(firstMeasurementState["tableWidth"] as? Double ?? 999, firstMeasurementState["viewportWidth"] as? Double ?? 0)
        XCTAssertGreaterThan(firstMeasurementState["mapWidth"] as? Double ?? 0, firstMeasurementState["destWidth"] as? Double ?? 999)
        XCTAssertGreaterThan(
            (firstMeasurementState["mapWidth"] as? Double ?? 0) /
                max(firstMeasurementState["tableWidth"] as? Double ?? 1, 1),
            0.4
        )
        XCTAssertEqual(firstMeasurementState["locallyScrollable"] as? Bool, false)
        XCTAssertEqual(firstMeasurementState["expanded"] as? Bool, true)

        let measurementCountBeforeRemeasure = firstMeasurementState["measurementCount"] as? Int ?? 0
        _ = try await evaluate("window.scheduleMapRemeasure(); true")
        try await Task.sleep(nanoseconds: 300_000_000)
        let remeasurement = try await evaluate("""
        (() => {
          const perId = {};
          window.__mapMeasurements.forEach(item => { perId[item.id] = (perId[item.id] || 0) + 1; });
          return { count: window.__mapMeasurements.length, perId };
        })()
        """)
        XCTAssertGreaterThanOrEqual(remeasurement["count"] as? Int ?? 0, measurementCountBeforeRemeasure + 4)
        let rawPerId = remeasurement["perId"] as? [String: Any] ?? [:]
        let perId = rawPerId.compactMapValues { value -> Int? in
            if let integer = value as? Int { return integer }
            if let number = value as? NSNumber { return number.intValue }
            return nil
        }
        XCTAssertEqual(perId.count, 4)
        XCTAssertTrue(perId.values.allSatisfy { $0 >= 2 })
    }

    func testMapTablesGiveKartographerColumnsLeftoverWidthForTwoAndThreeColumnShapes() async throws {
        let collapsibleContent = try readAsset("Assets/web/collapsible_content.js")
        let polish = try readAsset("Assets/web/mobile_article_polish.js")
        let fixes = try readAsset("Assets/styles/fixes.css")
        let html = """
        <!doctype html>
        <html>
        <head><meta name="viewport" content="width=device-width, initial-scale=1"><style>\(fixes)</style></head>
        <body>
          <script>window.OSRS_TABLE_COLLAPSED = false;</script>
          <h2>Two column maps</h2>
          <table id="twoCol" class="wikitable">
            <tbody>
              <tr><th>Destination</th><th>Map</th></tr>
              <tr><td>Edgeville</td><td><span class="mw-kartographer-map" data-width="300" data-height="300" style="display:block;width:200px;height:200px"></span></td></tr>
            </tbody>
          </table>
          <h2>Three column maps</h2>
          <table id="threeCol" class="wikitable">
            <tbody>
              <tr><th>Destination</th><th>Requirements</th><th>Map</th></tr>
              <tr>
                <td>Edgeville</td>
                <td>None</td>
                <td><span class="mw-kartographer-map" data-width="300" data-height="300" style="display:block;width:200px;height:200px"></span></td>
              </tr>
            </tbody>
          </table>
          <script>\(collapsibleContent)</script>
          <script>\(polish)</script>
        </body>
        </html>
        """

        try await load(html)
        _ = try await evaluate("window.OSRSApplyArticlePolish && window.OSRSApplyArticlePolish(); true")
        let state = try await evaluate("""
        (() => {
          const measure = (id) => {
            const table = document.getElementById(id);
            const mapCell = table.querySelector('td:has(.mw-kartographer-map)');
            const otherWidths = Array.from(table.querySelectorAll('tbody tr:last-child > :is(th, td)'))
              .filter((cell) => cell !== mapCell)
              .map((cell) => cell.getBoundingClientRect().width);
            return {
              tableWidth: table.getBoundingClientRect().width,
              mapWidth: mapCell.getBoundingClientRect().width,
              otherMax: Math.max(0, ...otherWidths),
              mapClass: table.classList.contains('osrs-map-table'),
              layout: getComputedStyle(table).tableLayout,
              width: getComputedStyle(table).width
            };
          };
          return {
            viewportWidth: document.documentElement.clientWidth,
            two: measure('twoCol'),
            three: measure('threeCol')
          };
        })()
        """)

        func assertMapColumn(_ key: String) throws {
            let table = try XCTUnwrap(state[key] as? [String: Any])
            XCTAssertEqual(table["mapClass"] as? Bool, true, key)
            let mapWidth = table["mapWidth"] as? Double ?? 0
            let otherMax = table["otherMax"] as? Double ?? 999
            let tableWidth = table["tableWidth"] as? Double ?? 1
            XCTAssertGreaterThan(mapWidth, otherMax, "\(key) \(table)")
            XCTAssertGreaterThan(mapWidth / max(tableWidth, 1), 0.4, "\(key) \(table)")
            XCTAssertLessThanOrEqual(tableWidth, (state["viewportWidth"] as? Double ?? 0) + 1, key)
        }
        try assertMapColumn("two")
        try assertMapColumn("three")
    }

    func testHorizontalContentGestureOwnershipUsesSequenceLatchWithoutNativeWebKitBackGesture() throws {
        let interceptor = try readAsset("Assets/web/horizontal_scroll_interceptor.js")
        let articleWebView = try readSource("Views/ArticleWebView.swift")
        let articleView = try readSource("Views/ArticleView.swift")
        let articleViewModel = try readSource("ViewModels/ArticleViewModel.swift")
        let gestureModifier = try readSource("Views/Components/osrsHorizontalGestureModifier.swift")
        let mapBridge = try readAsset("Assets/web/map_bridge.js")

        XCTAssertTrue(interceptor.contains("setHorizontalScrollGesture"))
        XCTAssertTrue(interceptor.contains("activeGestureId"))
        XCTAssertTrue(interceptor.contains("notifyGesturePhase('begin'"))
        XCTAssertTrue(interceptor.contains("resetScrollState()"))
        XCTAssertTrue(interceptor.contains("canConsumeHorizontalDelta"))
        XCTAssertTrue(interceptor.contains("horizontalEdgeCapacity"))
        XCTAssertTrue(interceptor.contains("sequenceAxisLock"))
        XCTAssertTrue(interceptor.contains("const edgeSlop = 8"))
        XCTAssertTrue(interceptor.contains("isProseBannerTable"))
        XCTAssertFalse(interceptor.contains("if (!consume && isHorizontallyScrollable)"))
        XCTAssertTrue(interceptor.contains("overflowingHorizontalOwner"))
        XCTAssertTrue(interceptor.contains("'article-navigation'"))
        XCTAssertTrue(interceptor.contains("article-touch-"))
        XCTAssertTrue(interceptor.contains("isHorizontallyScrollable"))
        XCTAssertFalse(interceptor.contains("createElement('span')"))
        XCTAssertTrue(mapBridge.contains("isLocalOwner: !!isLocalOwner"))
        XCTAssertTrue(articleWebView.contains("allowsBackForwardNavigationGestures = false"))
        XCTAssertTrue(articleWebView.contains("case \"setHorizontalScrollGesture\""))
        XCTAssertTrue(articleWebView.contains("installArticleNavigationGesture(on: webView)"))
        XCTAssertTrue(articleWebView.contains("recognizer.cancelsTouchesInView = false"))
        XCTAssertTrue(articleWebView.contains("shouldRecognizeSimultaneouslyWith"))
        XCTAssertTrue(gestureModifier.contains("activeJavaScriptGestureId"))
        XCTAssertTrue(gestureModifier.contains("JavaScriptGestureSequence"))
        XCTAssertTrue(gestureModifier.contains("performNavigationAfterClassification"))
        XCTAssertFalse(gestureModifier.contains("navigationArbitrationDelay"))
        XCTAssertTrue(gestureModifier.contains("guard isEnabled && !gestureState.shouldBlockGestures"))
        XCTAssertFalse(gestureModifier.contains("gestureState.resetState()"))
        XCTAssertEqual(articleViewModel.components(separatedBy: "\"map_bridge.js\"").count - 1, 1)
        XCTAssertEqual(articleViewModel.components(separatedBy: "\"web/map_bridge.js\"").count - 1, 1)
        XCTAssertFalse(articleViewModel.contains("table_wrapper.js"))
    }

    func testInfoboxChromeKeepsHairlineBorderWithoutInlineOutlineOverride() throws {
        let articleViewModel = try readSource("ViewModels/ArticleViewModel.swift")
        let iosAesthetics = try readAsset("Assets/styles/ios-article-aesthetics.css")
        XCTAssertFalse(articleViewModel.contains("infobox.style.border"))
        XCTAssertFalse(articleViewModel.contains("2px solid var(--coloroutline)"))
        XCTAssertFalse(articleViewModel.contains("applyFinalStylingFixes"))
        XCTAssertTrue(iosAesthetics.contains("border: 1px solid var(--wikitable-border) !important"))
        XCTAssertTrue(iosAesthetics.contains("display: inline-flex !important"))
        XCTAssertTrue(iosAesthetics.contains("align-items: center !important"))
        XCTAssertTrue(iosAesthetics.contains(":is(p, li, dd, figcaption) img.mw-file-element"))
        XCTAssertFalse(iosAesthetics.contains("vertical-align: -0.2em !important"))
        XCTAssertFalse(
            iosAesthetics.contains("height: 1em !important"),
            "Do not shrink iOS prose icons to 1em to fake alignment; keep Android 2em density."
        )
        XCTAssertFalse(iosAesthetics.contains("max-height: 1em !important"))
        XCTAssertFalse(iosAesthetics.contains("max-width: 1.25em !important"))
        XCTAssertTrue(iosAesthetics.contains(".osrs-inline-icon-prose"))
        XCTAssertTrue(iosAesthetics.contains("overflow: hidden !important"))
        XCTAssertTrue(iosAesthetics.contains("scroll-padding-top:"))
        XCTAssertTrue(iosAesthetics.contains("line-height: 0 !important"))
        XCTAssertTrue(iosAesthetics.contains("max-height: 2em !important"))
        XCTAssertTrue(iosAesthetics.contains("vertical-align: middle !important"))
        XCTAssertFalse(iosAesthetics.contains("vertical-align: text-bottom !important"))
    }

    func testInteractivePriceChartAndHiddenStatePrewarmContracts() throws {
        let chart = try readAsset("Assets/web/ge_charts_init.js")
        let switcher = try readAsset("Assets/web/switch_infobox.js")
        let fonts = try readAsset("Assets/styles/fonts.css")
        let articleViewModel = try readSource("ViewModels/ArticleViewModel.swift")
        let htmlBuilder = try readSource("Services/osrsPageHtmlBuilder.swift")

        XCTAssertTrue(chart.contains("overflow:hidden !important"))
        XCTAssertTrue(chart.contains("zoomType: 'x'"))
        XCTAssertTrue(chart.contains("pinchType: 'x'"))
        XCTAssertTrue(chart.contains("panning: { enabled: true, type: 'x' }"))
        XCTAssertTrue(chart.contains("followTouchMove: true"))
        XCTAssertTrue(chart.contains("ResizeObserver"))
        XCTAssertTrue(chart.contains("resolveHighcharts"))
        XCTAssertTrue(chart.contains("AbortController"))
        XCTAssertTrue(chart.contains("Highcharts never became available"))
        XCTAssertTrue(switcher.contains("data-default-version"))
        XCTAssertTrue(switcher.contains("preloader.decode()"))
        XCTAssertTrue(switcher.contains("updateExistingImage"))
        XCTAssertTrue(switcher.contains("lockSwitcherMinBlockSize"))
        XCTAssertFalse(switcher.contains("container.classList.contains('infobox-bonuses')"))
        XCTAssertFalse(switcher.contains("\n            stabilizeInfoboxWidth(mainInfobox"))
        XCTAssertTrue(fonts.contains("font-display: optional"))
        XCTAssertFalse(articleViewModel.contains("pageHeader.style.fontFamily"))
        XCTAssertTrue(htmlBuilder.contains("osrs-article-first-paint"))
        XCTAssertTrue(htmlBuilder.contains("alegreya_bold.ttf"))
        XCTAssertTrue(htmlBuilder.contains("--osrs-article-safe-area-top"))
        XCTAssertTrue(htmlBuilder.contains("padding-top: calc(var(--osrs-article-safe-area-top) + var(--osrs-article-chrome-clearance))"))
        XCTAssertFalse(htmlBuilder.contains("env(safe-area-inset-top"))
        let iosAesthetics = try readAsset("Assets/styles/ios-article-aesthetics.css")
        XCTAssertTrue(iosAesthetics.contains("var(--osrs-article-safe-area-top, 0px)"))
        XCTAssertFalse(iosAesthetics.contains("env(safe-area-inset-top"))
    }

    func testFirstPaintReservesPageTitleAndChromeClearance() async throws {
        let firstPaint = osrsPageHtmlBuilder.articleFirstPaintStyle(
            chromeClearancePx: 64,
            safeAreaTopPx: 59,
            safeAreaBottomPx: 34
        )
        let html = """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        \(firstPaint)
        </head>
        <body style="margin:0">
        <h1 class="page-header">Varrock</h1>
        <p id="lead">Capital of Misthalin.</p>
        </body>
        </html>
        """
        try await load(html)
        let before = try await evaluate("""
        (() => {
            const lead = document.getElementById('lead');
            const html = document.documentElement;
            return {
                top: lead.getBoundingClientRect().top,
                paddingTop: getComputedStyle(html).paddingTop
            };
        })()
        """)
        _ = try await evaluate("""
        (() => {
            const style = document.createElement('style');
            style.textContent = 'html { padding-top: calc(var(--osrs-article-safe-area-top, 0px) + var(--osrs-article-chrome-clearance, 56px)) !important; }';
            document.head.appendChild(style);
            document.body.offsetHeight;
            return { ok: true };
        })()
        """)
        let after = try await evaluate("""
        (() => {
            const lead = document.getElementById('lead');
            return { top: lead.getBoundingClientRect().top };
        })()
        """)
        XCTAssertEqual(before["paddingTop"] as? String, "123px")
        XCTAssertEqual(before["top"] as? Double ?? 0, after["top"] as? Double ?? -1, accuracy: 1.0)
        XCTAssertGreaterThan(before["top"] as? Double ?? 0, 120)
    }

    func testInfoboxStateSwitchKeepsBoxHeightStable() async throws {
        let bootstrap = try readAsset("Assets/web/infobox_switcher_bootstrap.js")
        let switcher = try readAsset("Assets/web/switch_infobox.js")
        let tiny = "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='18' height='29'><rect width='18' height='29' fill='%23c00'/></svg>"
        let large = "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='80' height='120'><rect width='80' height='120' fill='%2300c'/></svg>"
        let html = """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        body { margin: 16px; width: 343px; }
        table.infobox { width: 100%; border-collapse: collapse; }
        table.infobox img { max-width: 100%; height: auto; }
        </style>
        </head>
        <body>
        <table class="infobox infobox-switch" data-resource-class=".infobox-resources-Item">
            <caption>
                <div class="infobox-buttons" data-default-version="1">
                    <span data-switch-index="1" class="button">A</span>
                    <span data-switch-index="2" class="button">B</span>
                </div>
            </caption>
            <tbody>
                <tr><th class="infobox-header" data-attr-param="name">Short name</th></tr>
                <tr><td data-attr-param="image"><img width="18" height="29" class="mw-file-element" src="\(tiny)"></td></tr>
            </tbody>
        </table>
        <div class="infobox-resources-Item infobox-switch-resources">
            <div data-attr-param="name">
                <span data-attr-index="1">Short name</span>
                <span data-attr-index="2">A substantially longer infobox title that wraps on a phone-width column</span>
            </div>
            <div data-attr-param="image">
                <span data-attr-index="1"><img width="18" height="29" class="mw-file-element" src="\(tiny)"></span>
                <span data-attr-index="2"><img width="80" height="120" class="mw-file-element" src="\(large)"></span>
            </div>
        </div>
        <script>\(bootstrap)</script>
        <script>\(switcher)</script>
        <script>initializeInfoboxSwitcher();</script>
        </body>
        </html>
        """
        try await load(html)
        try await Task.sleep(nanoseconds: 250_000_000)
        let before = try await evaluate("""
        (() => {
            const box = document.querySelector('.infobox-switch');
            return { height: box.getBoundingClientRect().height, ready: box.dataset.osrsSwitcherReady || '' };
        })()
        """)
        _ = try await evaluate("(() => { performSwitch('2'); return { ok: true }; })()")
        let after = try await evaluate("""
        (() => {
            const box = document.querySelector('.infobox-switch');
            const selected = document.querySelector('.button-selected');
            return {
                height: box.getBoundingClientRect().height,
                selected: (selected && selected.textContent) || '',
                minHeight: box.style.minHeight
            };
        })()
        """)
        XCTAssertEqual(before["ready"] as? String, "true")
        XCTAssertEqual(after["selected"] as? String, "B")
        XCTAssertFalse((after["minHeight"] as? String ?? "").isEmpty)
        XCTAssertEqual(before["height"] as? Double ?? 0, after["height"] as? Double ?? -1, accuracy: 2.0)
    }

    func testBuilderAppliesUserArticleTextScaleExactlyOnce() async throws {
        let fixesCss = try readAsset("Assets/styles/fixes.css")
        var html = osrsPageHtmlBuilder().buildFullHtmlDocument(
            title: "Text scale fixture",
            bodyContent: "<main><p id=\"scaledText\">Readable article text</p></main>",
            theme: osrsLightTheme(),
            collapseTablesEnabled: true,
            includeAssetLinks: false,
            articleTextScale: 1.40
        )
        let preferenceStart = try XCTUnwrap(html.range(of: "<style id=\"osrs-article-reader-preferences\">"))
        let preferenceEnd = try XCTUnwrap(html.range(of: "</style>", range: preferenceStart.upperBound..<html.endIndex))
        let preferenceBlock = String(html[preferenceStart.lowerBound..<preferenceEnd.upperBound])

        XCTAssertTrue(preferenceBlock.contains("--osrs-article-user-text-scale: 1.400"))
        XCTAssertFalse(
            preferenceBlock.contains("font-size"),
            "The builder owns only the user-scale variable; shared article CSS owns the single font-size application"
        )

        html = html.replacingOccurrences(
            of: "</head>",
            with: "<style>html { font-size: 16px; }\n\(fixesCss)</style></head>"
        )
        try await load(html)
        let state = try await evaluate("""
        (() => ({
            rootFontSize: parseFloat(getComputedStyle(document.documentElement).fontSize),
            bodyFontSize: parseFloat(getComputedStyle(document.body).fontSize),
            textFontSize: parseFloat(getComputedStyle(document.getElementById('scaledText')).fontSize)
        }))()
        """)

        XCTAssertEqual(state["rootFontSize"] as? Double ?? 0, 16.0, accuracy: 0.1)
        XCTAssertEqual(state["bodyFontSize"] as? Double ?? 0, 22.4, accuracy: 0.2)
        XCTAssertEqual(state["textFontSize"] as? Double ?? 0, 22.4, accuracy: 0.2)
    }

    func testAccessibilityReflowScalesTextInsideCollapsibleContent() async throws {
        let collapsibleContent = try readAsset("Assets/web/collapsible_content.js")
        let fixesCss = try readAsset("Assets/styles/fixes.css")
        let html = """
        <!doctype html>
        <html class="osrs-accessibility-reflow" style="--osrs-article-text-scale: 1.5; --osrs-article-user-text-scale: 1.15;">
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
        :root {
            --text-color: #241c12;
            --wikitable-bg: #ded2b8;
            --wikitable-border: #9d8c70;
        }
        body { font-size: 16px; }
        \(fixesCss)
        </style>
        </head>
        <body class="osrs-accessibility-reflow">
        <script>window.OSRS_TABLE_COLLAPSED = false;</script>
        <figure id="vignette" class="mw-halign-right osrs-balanced-vignette" style="width: 360px;">
            <img alt="" width="140" height="251" src="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==">
        </figure>
        <table class="wikitable">
            <tbody>
                <tr><th>Dragon scimitar</th></tr>
                <tr><td id="scaledCell" style="font-size:85%;">Special attack text should scale with Dynamic Type.</td></tr>
            </tbody>
        </table>
        <script>\(collapsibleContent)</script>
        </body>
        </html>
        """

        try await load(html)
        let state = try await evaluate("""
        (() => {
            const bodyFontSize = parseFloat(getComputedStyle(document.body).fontSize);
            const cell = document.getElementById('scaledCell');
            return {
                bodyFontSize,
                cellFontSize: parseFloat(getComputedStyle(cell).fontSize),
                contentFontSize: parseFloat(getComputedStyle(cell.closest('.collapsible-content')).fontSize),
                vignetteWidth: document.getElementById('vignette').getBoundingClientRect().width,
                vignetteFloat: getComputedStyle(document.getElementById('vignette')).float
            };
        })()
        """)

        let bodyFontSize = state["bodyFontSize"] as? Double ?? 0
        XCTAssertEqual(bodyFontSize, 27.6, accuracy: 0.1)
        XCTAssertEqual(state["contentFontSize"] as? Double ?? 0, bodyFontSize, accuracy: 0.5)
        XCTAssertEqual(state["cellFontSize"] as? Double ?? 0, bodyFontSize, accuracy: 0.5)
        XCTAssertLessThanOrEqual(state["vignetteWidth"] as? Double ?? 999, 112.5)
        XCTAssertEqual(state["vignetteFloat"] as? String, "none")
    }

    func testArticleWebViewTogglesAccessibilityReflowClass() throws {
        let webViewSource = try readSource("Views/ArticleWebView.swift")
        let viewModelSource = try readSource("ViewModels/ArticleViewModel.swift")

        XCTAssertTrue(webViewSource.contains("isAccessibilitySize"))
        XCTAssertTrue(webViewSource.contains("requiresWebReflow ? 1.0 : scale"))
        XCTAssertTrue(webViewSource.contains("setAccessibilityReflowEnabled"))
        XCTAssertTrue(viewModelSource.contains("osrs-accessibility-reflow"))
        XCTAssertTrue(viewModelSource.contains("--osrs-article-text-scale"))
        XCTAssertTrue(viewModelSource.contains("classList.toggle"))
    }

    func testArticleChromeUsesCompactAccessibilityLabels() throws {
        let searchBarSource = try readSource("Views/Components/osrsArticleSearchBar.swift")
        let bottomBarSource = try readSource("Views/Components/osrsArticleBottomBar.swift")

        XCTAssertTrue(searchBarSource.contains("compactSearchTitle"))
        XCTAssertTrue(searchBarSource.contains("dynamicTypeSize.isAccessibilitySize ? \"Search\" : \"Search OSRS Wiki\""))
        XCTAssertTrue(searchBarSource.contains("accessibilityLabel(\"Search OSRS Wiki\")"))
        XCTAssertTrue(bottomBarSource.contains("compactText"))
        XCTAssertTrue(bottomBarSource.contains("case \"Appearance\": return \"Text\""))
    }

    private func load(_ html: String) async throws {
        let didFinish = expectation(description: "WebView loaded")
        let delegate = ArticleAestheticNavigationDelegate(didFinish: didFinish)
        navigationDelegate = delegate
        webView.navigationDelegate = delegate
        webView.loadHTMLString(html, baseURL: URL(string: "https://oldschool.runescape.wiki/"))
        await fulfillment(of: [didFinish], timeout: 10.0)
    }

    private func evaluate(_ script: String) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let dictionary = result as? [String: Any] {
                    continuation.resume(returning: dictionary)
                } else {
                    continuation.resume(returning: [:])
                }
            }
        }
    }

    private func snapshot() async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            webView.takeSnapshot(with: nil) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: NSError(domain: "ArticleAestheticRenderingTests", code: 1))
                }
            }
        }
    }

    private func imageChannelDifferenceCount(_ lhs: UIImage, _ rhs: UIImage) -> Int {
        guard
            let lhsData = lhs.cgImage?.dataProvider?.data as Data?,
            let rhsData = rhs.cgImage?.dataProvider?.data as Data?,
            lhsData.count == rhsData.count
        else {
            return 0
        }
        return zip(lhsData, rhsData).reduce(into: 0) { count, bytes in
            if abs(Int(bytes.0) - Int(bytes.1)) > 4 {
                count += 1
            }
        }
    }

    private func readAsset(_ relativePath: String) throws -> String {
        try String(contentsOf: iosRoot.appendingPathComponent("osrswiki").appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func readSource(_ relativePath: String) throws -> String {
        try String(contentsOf: iosRoot.appendingPathComponent("osrswiki").appendingPathComponent(relativePath), encoding: .utf8)
    }

    private var iosRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
