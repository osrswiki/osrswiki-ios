import XCTest
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

    func testPrimaryInfoboxAndFirstContentTableStartExpanded() async throws {
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
        XCTAssertTrue((state["firstInfoboxHeader"] as? String ?? "").contains("Dragon scimitar"))
        XCTAssertEqual(state["firstTableCollapsed"] as? Bool, false)
        XCTAssertTrue((state["firstTableHeader"] as? String ?? "").contains("Level / New abilities"))
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
        XCTAssertTrue((state["header"] as? String ?? "").contains("Details"))
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
        XCTAssertTrue((state["watchdogHeader"] as? String ?? "").contains("Importable Watchdog config"))
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

        XCTAssertTrue((state["headerText"] as? String ?? "").contains("Doom of Mokhaiotl"))
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

        XCTAssertTrue((state["headerText"] as? String ?? "").contains("Ankou"))
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
        XCTAssertTrue((state["unlockHeader"] as? String ?? "").contains("Crafting level up table"))
        XCTAssertEqual(state["summaryCollapsed"] as? Bool, false)
        XCTAssertTrue((state["summaryHeader"] as? String ?? "").contains("Crafting"))
        XCTAssertEqual(state["expandedWikitablesBeforeSummary"] as? Int, 0)
    }

    func testStandaloneLevelUpTableKeepsPrimaryTableExpanded() async throws {
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

        XCTAssertEqual(state["collapsed"] as? Bool, false)
        XCTAssertTrue((state["header"] as? String ?? "").contains("Construction level up table"))
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

    func testAccessibilityReflowScalesTextInsideCollapsibleContent() async throws {
        let collapsibleContent = try readAsset("Assets/web/collapsible_content.js")
        let fixesCss = try readAsset("Assets/styles/fixes.css")
        let html = """
        <!doctype html>
        <html class="osrs-accessibility-reflow" style="--osrs-article-text-scale: 1.6;">
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
                contentFontSize: parseFloat(getComputedStyle(cell.closest('.collapsible-content')).fontSize)
            };
        })()
        """)

        let bodyFontSize = state["bodyFontSize"] as? Double ?? 0
        XCTAssertGreaterThan(bodyFontSize, 24)
        XCTAssertEqual(state["contentFontSize"] as? Double ?? 0, bodyFontSize, accuracy: 0.5)
        XCTAssertEqual(state["cellFontSize"] as? Double ?? 0, bodyFontSize, accuracy: 0.5)
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
