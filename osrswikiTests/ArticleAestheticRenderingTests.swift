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
    private var hostWindow: UIWindow?

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
        webView.removeFromSuperview()
        hostWindow?.isHidden = true
        hostWindow = nil
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
        XCTAssertTrue(collapsible.contains("osrsUsesAndroidDisclosureChrome"))
        XCTAssertTrue(collapsible.contains("android-article-aesthetics"))
        XCTAssertTrue(collapsible.contains("Tap to collapse"))
        XCTAssertTrue(collapsible.contains("Tap to expand"))
        XCTAssertTrue(collapsible.contains("collapsible-state"))
        XCTAssertTrue(collapsible.contains("scheduleCollapseAndMapWork"))
        XCTAssertTrue(collapsible.contains("osrs-first-view-complete"))
        XCTAssertTrue(collapsible.contains("startCollapseAndMapWork"))
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
        XCTAssertTrue(fixes.contains("min-width: max-content !important;"))
        XCTAssertTrue(fixes.contains("max-width: max-content !important;"))
        XCTAssertTrue(fixes.contains("hyphens: none !important;"))
        XCTAssertTrue(fixes.contains(".collapsible-primary-infobox table.infobox th:not(.infobox-header) {"))
        XCTAssertFalse(
            fixes.contains("table.infobox th:not(.infobox-header):not([colspan])"),
            "Location labels are th[colspan=2]; excluding colspan from nowrap wraps Inhabitants."
        )
        XCTAssertFalse(
            fixes.contains(".collapsible-primary-infobox th,\n.collapsible-primary-infobox td {"),
            "Blanket white-space:normal on every primary-infobox th wraps location labels such as Inhabitants."
        )
        XCTAssertFalse(
            fixes.contains("max(8em, min-content)"),
            "An 8em min-content floor stretches compact infoboxes; WebKit also ignores min-content on table cells."
        )
        XCTAssertTrue(fixes.contains("table:not(.infobox):not(.infobox-bonuses)"))
        XCTAssertTrue(fixes.contains("Generic load-time minmax"))
        XCTAssertFalse(fixes.contains(".osrs-local-scroll-surface > table.infobox-bonuses:not(.main-infobox)"))
        let tableNormalize = try readAsset("Assets/web/table_column_normalize.js")
        XCTAssertTrue(tableNormalize.contains("lockInfoboxValueCellFloors"))
        XCTAssertTrue(tableNormalize.contains("probeInfoboxValueIntrinsicWidth"))
        XCTAssertTrue(tableNormalize.contains("osrsValueFloor"))
        try assertDateCellsAndImageRowsStayContained(fixes: fixes)
    }

    func testSharedArticleCssContainsDateCellsAndKeepsImageRowsInViewport() throws {
        let fixes = try readAsset("Assets/styles/fixes.css")
        let polish = try readAsset("Assets/web/mobile_article_polish.js")
        let imageCap = try readAsset("Assets/web/image_area_cap.js")
        let aesthetics = try readAsset("Assets/styles/ios-article-aesthetics.css")
        try assertDateCellsAndImageRowsStayContained(fixes: fixes)
        XCTAssertTrue(polish.contains("markImageRowTables"))
        XCTAssertTrue(polish.contains("osrs-image-row-table"))
        XCTAssertTrue(imageCap.contains("if (targetWidth > viewportWidth && dims.width > 0)"))
        XCTAssertTrue(aesthetics.contains("table.osrs-map-table:not(.osrs-image-row-table)"))
        XCTAssertTrue(fixes.contains("table.infobox-bonuses"))
        XCTAssertTrue(fixes.contains(".wikitable img"))
        XCTAssertTrue(fixes.contains("width: 22px"))
        XCTAssertFalse(
            fixes.contains("table.infobox-bonuses :is(th, td) {\n    min-width: max-content"),
            "Generic wikitable nowrap/max-content must not dump leftover width onto bonuses."
        )
    }

    private func assertDateCellsAndImageRowsStayContained(fixes: String) throws {
        XCTAssertTrue(fixes.contains("OSRS_DATE_CELL_CONTAINMENT"))
        XCTAssertTrue(fixes.contains("OSRS_IMAGE_ROW_IN_VIEWPORT"))
        XCTAssertTrue(fixes.contains("osrs-image-row-table"))
        XCTAssertTrue(fixes.contains("min-width: max-content"))
        XCTAssertTrue(
            fixes.contains(
                "table.wikitable:not(.infobox):not(.infobox-bonuses):not(.navbox):not(.osrs-map-table) :is(th, td)[style*=\"max-width\"]"
            )
        )
        XCTAssertTrue(fixes.contains("table.osrs-map-table:not(.osrs-image-row-table)"))
    }

    func testJcConfigCombatCalculatorLeavesWikiFormForCalcCore() async throws {
        let articleTools = try readAsset("Assets/web/article_tools.js")
        let runtime = try readAsset("Assets/web/osrs_calculator_runtime.js")
        let html = """
        <!doctype html>
        <html>
        <body>
        <pre class="jcConfig">
        template = Calculator:Combat level/Template
        form = combatCalcForm
        result = combatCalcResult
        param = attack|Attack|1|int|1-99
        param = strength|Strength|1|int|1-99
        autosubmit = enabled
        </pre>
        <div id="combatCalcForm">Please wait for the form to load. If it does not load, try refreshing the page.</div>
        <div id="combatCalcResult"></div>
        <script>\(runtime)</script>
        <script>\(articleTools)</script>
        </body>
        </html>
        """

        try await load(html)
        let result = try await evaluate("""
        (() => {
            const form = document.getElementById('combatCalcForm');
            const layout = document.querySelector('.osrs-calculator-layout');
            const result = document.getElementById('combatCalcResult');
            return {
                hasPlaceholder: (form?.innerText || '').includes('Please wait for the form to load'),
                hijacked: !!document.querySelector('[data-osrs-calculator-param]'),
                hasLayout: !!layout,
                resultInsideLayout: !!(layout && result && layout.contains(result))
            };
        })()
        """)

        XCTAssertEqual(result["hasPlaceholder"] as? Bool, true)
        XCTAssertEqual(result["hijacked"] as? Bool, false)
        XCTAssertEqual(result["hasLayout"] as? Bool, true)
        XCTAssertEqual(result["resultInsideLayout"] as? Bool, true)
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
        let runtime = try readAsset("Assets/web/osrs_calculator_runtime.js")
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
        <table class="calculator-host" width="800" style="width:800px"><tbody><tr><td><div id="combatCalcForm">Please wait for the form to load.</div><div id="combatCalcResult"></div></td></tr></tbody></table>
        <script>\(runtime)</script>
        </body>
        </html>
        """

        try await load(html)
        let phoneState = try await evaluate("""
        (() => {
            const layout = document.querySelector('.osrs-calculator-layout');
            const templates = document.querySelector('.osrs-calculator-templates');
            const panel = document.querySelector('.osrs-calculator-panel');
            const templateRect = templates.getBoundingClientRect();
            const panelRect = panel.getBoundingClientRect();
            return {
                hasLayout: !!layout,
                templateFloat: getComputedStyle(templates).float,
                templateBeforePanel: templateRect.bottom <= panelRect.top,
                columns: getComputedStyle(layout).gridTemplateColumns,
                placeholderKept: (document.getElementById('combatCalcForm')?.innerText || '').includes('Please wait for the form to load'),
                panelWidth: panelRect.width,
                viewportWidth: document.documentElement.clientWidth
            };
        })()
        """)

        XCTAssertEqual(phoneState["hasLayout"] as? Bool, true)
        XCTAssertEqual(phoneState["templateFloat"] as? String, "none")
        XCTAssertEqual(phoneState["templateBeforePanel"] as? Bool, true)
        XCTAssertEqual((phoneState["columns"] as? String ?? "").split(separator: " ").count, 1)
        XCTAssertEqual(phoneState["placeholderKept"] as? Bool, true)
        XCTAssertLessThanOrEqual(
            phoneState["panelWidth"] as? Double ?? 999,
            (phoneState["viewportWidth"] as? Double ?? 0) + 1,
            "Calculator host table must shrink to the viewport, not keep a desktop width: \(phoneState)"
        )

        webView.frame = CGRect(x: 0, y: 0, width: 768, height: 1024)
        let tabletState = try await evaluate("""
        (() => ({
            columns: getComputedStyle(document.querySelector('.osrs-calculator-layout')).gridTemplateColumns,
            templateWidth: document.querySelector('.osrs-calculator-templates')?.getBoundingClientRect().width || 0,
            viewportWidth: document.documentElement.clientWidth
        }))()
        """)
        XCTAssertEqual((tabletState["columns"] as? String ?? "").split(separator: " ").count, 1)
        XCTAssertGreaterThan(tabletState["templateWidth"] as? Double ?? 0, (tabletState["viewportWidth"] as? Double ?? 768) * 0.7)
    }

    func testCalculatorOOUIChromeUsesArticleParchmentTokensAgainstLateWikiStyles() async throws {
        let themesCss = try readAsset("Assets/styles/themes.css")
        let gadgetCss = try readAsset("Assets/styles/gadget_calc.css")
        let fixesCss = try readAsset("Assets/styles/fixes.css")
        let hotSwap = try String(
            contentsOf: iosRoot.appendingPathComponent("osrswikiUITests/AppearanceThemeHotSwapUITests.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(themesCss.contains("--ooui-normal: #f8f9fa"))
        XCTAssertFalse(themesCss.contains("--ooui-progressive: #0645ad"))
        XCTAssertFalse(themesCss.contains("--ooui-input: #fff"))
        XCTAssertTrue(themesCss.contains("--osrsw-brown: #605443"))
        XCTAssertTrue(themesCss.contains("--background-color-base: var(--body-main)"))
        XCTAssertTrue(fixesCss.contains(".osrs-calculator-panel h2"))
        XCTAssertTrue(fixesCss.contains(".osrs-calculator-panel .oo-ui-fieldsetLayout-header"))
        XCTAssertTrue(
            fixesCss.contains("font-family: 'Alegreya', 'Palatino', 'Georgia', serif !important"),
            "Calculator headings (h2 and FieldsetLayout) must use article serif chrome"
        )
        XCTAssertTrue(fixesCss.contains("Calculator infobox language"))
        XCTAssertTrue(fixesCss.contains("jsCalc-field-check"))
        XCTAssertTrue(
            fixesCss.contains("grid-template-columns: minmax(6em, 38%) minmax(0, 1fr)"),
            "Calculator fields must use an infobox-like label|control grid"
        )
        XCTAssertTrue(fixesCss.contains("osrs-calculator-templates > tbody"))
        XCTAssertTrue(fixesCss.contains("oo-ui-numberInputWidget-buttoned"))
        XCTAssertTrue(fixesCss.contains("oo-ui-numberInputWidget-field"))
        XCTAssertTrue(fixesCss.contains("grid-row: 1"))
        XCTAssertTrue(fixesCss.contains("table.osrs-calculator-panel"))
        XCTAssertTrue(
            fixesCss.contains("96px) + 12px"),
            "Calculator layout must add tab-bar clearance on top of baked article chrome"
        )
        XCTAssertTrue(hotSwap.contains("app.staticTexts[\"Light\"]"))
        XCTAssertTrue(hotSwap.contains("hasDarkInk(lightThemePixels)"))
        XCTAssertFalse(
            hotSwap.contains(".id(themeManager.selectedTheme)"),
            "Appearance hot-swap must stay a live restyle, not a view identity reset"
        )

        attachWebViewToWindow()
        let html = """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
        \(themesCss)
        .oo-ui-fieldLayout.oo-ui-labelElement.oo-ui-fieldLayout-align-right > .oo-ui-fieldLayout-body {
            display: flex;
        }
        .oo-ui-fieldLayout.oo-ui-labelElement.oo-ui-fieldLayout-align-right > .oo-ui-fieldLayout-body > .oo-ui-fieldLayout-field {
            width: 60%;
            flex-shrink: 0;
        }
        .oo-ui-fieldLayout.oo-ui-labelElement.oo-ui-fieldLayout-align-right > .oo-ui-fieldLayout-body > .oo-ui-fieldLayout-header {
            flex-grow: 1;
            text-align: right;
        }
        .oo-ui-buttonElement > .oo-ui-buttonElement-button {
            background-color: #f8f9fa;
            border: 1px solid #a2a9b1;
            color: #222;
            padding-top: 2.14285714em;
        }
        .oo-ui-buttonElement-framed.oo-ui-widget-enabled.oo-ui-flaggedElement-primary.oo-ui-flaggedElement-progressive > .oo-ui-buttonElement-button {
            background-color: #36c;
            border-color: #36c;
            color: #fff;
        }
        .oo-ui-textInputWidget .oo-ui-inputWidget-input {
            background-color: #fff;
            border: 1px solid #a2a9b1;
            color: #000;
        }
        .oo-ui-checkboxInputWidget [type='checkbox'] + span {
            background-color: var(--background-color-base, #fff);
            border: 1px solid #a2a9b1;
        }
        .oo-ui-numberInputWidget-field {
            display: table;
            table-layout: fixed;
            width: 100%;
        }
        .oo-ui-numberInputWidget-buttoned .oo-ui-buttonWidget,
        .oo-ui-numberInputWidget-buttoned .oo-ui-inputWidget-input {
            display: table-cell;
            height: 100%;
        }
        \(gadgetCss)
        \(fixesCss)
        </style>
        </head>
        <body>
        <div class="osrs-calculator-layout">
          <table class="archivelist osrs-calculator-templates">
            <tbody>
              <tr><td><img class="mw-file-element" width="120" height="120" alt=""></td></tr>
              <tr><th>Templates used</th></tr>
              <tr><td><a href="/w/Calculator:Barrows/Template">Calculator:Barrows/Template</a></td></tr>
            </tbody>
          </table>
          <div class="osrs-calculator-panel">
            <h2>Calculator</h2>
            <div class="oo-ui-widget oo-ui-labelElement oo-ui-fieldsetLayout jcTable">
              <div class="oo-ui-fieldsetLayout-header">
                <span class="oo-ui-labelElement-label">Calculator</span>
              </div>
            </div>
            <div class="oo-ui-fieldLayout oo-ui-labelElement oo-ui-fieldLayout-align-right jsCalc-field jsCalc-field-check">
              <div class="oo-ui-fieldLayout-body">
                <span class="oo-ui-fieldLayout-header">
                  <label class="oo-ui-labelElement-label">Ahrim?</label>
                </span>
                <div class="oo-ui-fieldLayout-field">
                  <span class="oo-ui-checkboxInputWidget oo-ui-widget oo-ui-widget-enabled">
                    <input type="checkbox" checked>
                    <span class="osrs-calc-check-box"></span>
                  </span>
                </div>
              </div>
            </div>
            <div class="oo-ui-fieldLayout oo-ui-labelElement oo-ui-fieldLayout-align-right jsCalc-field jsCalc-field-check osrs-calc-check-field-first">
              <div class="oo-ui-fieldLayout-body">
                <div class="oo-ui-fieldLayout-field">
                  <span class="oo-ui-checkboxInputWidget oo-ui-widget oo-ui-widget-enabled">
                    <input type="checkbox" checked>
                    <span class="osrs-calc-check-box osrs-calc-dharok-box"></span>
                  </span>
                </div>
                <span class="oo-ui-fieldLayout-header">
                  <label class="oo-ui-labelElement-label">Dharok?</label>
                </span>
              </div>
            </div>
            <div class="oo-ui-fieldLayout oo-ui-labelElement oo-ui-fieldLayout-align-right jsCalc-field jsCalc-field-int">
              <div class="oo-ui-fieldLayout-body">
                <span class="oo-ui-fieldLayout-header">
                  <label class="oo-ui-labelElement-label">Attack</label>
                </span>
                <div class="oo-ui-fieldLayout-field">
                  <div class="oo-ui-widget oo-ui-widget-enabled oo-ui-inputWidget oo-ui-textInputWidget oo-ui-textInputWidget-type-number oo-ui-numberInputWidget oo-ui-numberInputWidget-buttoned">
                    <span class="oo-ui-iconElement-icon oo-ui-iconElement-noIcon"></span>
                    <span class="oo-ui-indicatorElement-indicator oo-ui-indicatorElement-noIndicator"></span>
                    <div class="oo-ui-numberInputWidget-field">
                      <span class="oo-ui-numberInputWidget-minusButton oo-ui-widget oo-ui-widget-enabled oo-ui-buttonElement oo-ui-buttonElement-framed oo-ui-iconElement oo-ui-buttonWidget">
                        <a class="oo-ui-buttonElement-button osrs-calc-minus" role="button">−</a>
                      </span>
                      <input class="oo-ui-inputWidget-input" value="1">
                      <span class="oo-ui-numberInputWidget-plusButton oo-ui-widget oo-ui-widget-enabled oo-ui-buttonElement oo-ui-buttonElement-framed oo-ui-iconElement oo-ui-buttonWidget">
                        <a class="oo-ui-buttonElement-button osrs-calc-plus" role="button">+</a>
                      </span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
            <span class="oo-ui-buttonElement oo-ui-buttonElement-framed oo-ui-widget oo-ui-widget-enabled oo-ui-labelElement">
              <a class="oo-ui-buttonElement-button">Lookup</a>
            </span>
            <span class="oo-ui-buttonElement oo-ui-buttonElement-framed oo-ui-widget oo-ui-widget-enabled oo-ui-flaggedElement-primary oo-ui-flaggedElement-progressive jcSubmit">
              <a class="oo-ui-buttonElement-button">Submit</a>
            </span>
            <div class="oo-ui-textInputWidget oo-ui-widget oo-ui-widget-enabled">
              <input class="oo-ui-inputWidget-input" value="99">
            </div>
          </div>
        </div>
        </body>
        </html>
        """

        try await load(html)
        let state = try await evaluate("""
        (() => {
            const heading = document.querySelector('.osrs-calculator-panel .oo-ui-fieldsetLayout-header .oo-ui-labelElement-label')
                || document.querySelector('.osrs-calculator-panel h2');
            const templates = document.querySelector('.osrs-calculator-templates');
            const label = document.querySelector('.jsCalc-field-check .oo-ui-labelElement-label');
            const attack = document.querySelector('.jsCalc-field-int .oo-ui-labelElement-label');
            const lookup = document.querySelector('.oo-ui-labelElement > .oo-ui-buttonElement-button');
            const submit = document.querySelector('.jcSubmit .oo-ui-buttonElement-button');
            const input = document.querySelector('.oo-ui-textInputWidget .oo-ui-inputWidget-input');
            const check = document.querySelector('.osrs-calc-check-box');
            const minus = document.querySelector('.osrs-calc-minus');
            const plus = document.querySelector('.osrs-calc-plus');
            const checkRect = check.getBoundingClientRect();
            const labelRect = label.getBoundingClientRect();
            const fieldRect = document.querySelector('.jsCalc-field-check .oo-ui-fieldLayout-field').getBoundingClientRect();
            const attackRect = attack.getBoundingClientRect();
            const intFieldRect = document.querySelector('.jsCalc-field-int .oo-ui-fieldLayout-field').getBoundingClientRect();
            const minusRect = minus.getBoundingClientRect();
            const plusRect = plus.getBoundingClientRect();
            const dharokLabel = document.querySelector('.osrs-calc-check-field-first .oo-ui-labelElement-label');
            const dharokBox = document.querySelector('.osrs-calc-dharok-box');
            const dharokLabelRect = dharokLabel.getBoundingClientRect();
            const dharokBoxRect = dharokBox.getBoundingClientRect();
            const rgb = (el, prop) => getComputedStyle(el)[prop];
            const channels = (value) => {
                const m = String(value).match(/rgba?\\((\\d+),\\s*(\\d+),\\s*(\\d+)/);
                return m ? [Number(m[1]), Number(m[2]), Number(m[3])] : [0, 0, 0];
            };
            const nearWhite = (value) => {
                const [r, g, b] = channels(value);
                return r > 245 && g > 245 && b > 245;
            };
            const wikiBlue = (value) => {
                const [r, g, b] = channels(value);
                return b > 150 && b > r + 40;
            };
            return {
                headingFont: getComputedStyle(heading).fontFamily,
                headingIsGenericSans: String(getComputedStyle(heading).fontFamily).trim().toLowerCase() === 'sans-serif',
                headingHasAlegreya: String(getComputedStyle(heading).fontFamily).includes('Alegreya'),
                templatesHeight: templates.getBoundingClientRect().height,
                labelText: label.textContent,
                labelVisible: labelRect.width > 20 && labelRect.height > 8 && getComputedStyle(label).color !== 'rgba(0, 0, 0, 0)',
                labelNotClippedRight: labelRect.left < document.documentElement.clientWidth - 8,
                labelThenControl: labelRect.right <= Math.min(fieldRect.left, checkRect.left) + 8,
                checkboxLabelSameRow: (checkRect.bottom > labelRect.top + 2) && (labelRect.bottom > checkRect.top + 2),
                dharokThenControl: dharokLabelRect.right <= dharokBoxRect.left + 8,
                dharokSameRow: (dharokBoxRect.bottom > dharokLabelRect.top + 2) && (dharokLabelRect.bottom > dharokBoxRect.top + 2),
                attackThenStepper: attackRect.right <= intFieldRect.left + 8,
                attackStepperSameRow: Math.abs(attackRect.top - intFieldRect.top) < 24,
                minusPlusSameRow: Math.abs(minusRect.top - plusRect.top) < 8,
                plusAfterMinus: plusRect.left >= minusRect.right - 2,
                lookupBg: rgb(lookup, 'backgroundColor'),
                submitBg: rgb(submit, 'backgroundColor'),
                inputBg: rgb(input, 'backgroundColor'),
                checkBg: rgb(check, 'backgroundColor'),
                lookupNearWhite: nearWhite(rgb(lookup, 'backgroundColor')),
                inputNearWhite: nearWhite(rgb(input, 'backgroundColor')),
                checkNearWhite: nearWhite(rgb(check, 'backgroundColor')),
                submitWikiBlue: wikiBlue(rgb(submit, 'backgroundColor')),
                lookupPaddingTop: parseFloat(getComputedStyle(lookup).paddingTop)
            };
        })()
        """)

        XCTAssertEqual(state["headingIsGenericSans"] as? Bool, false, "Heading font was \(state["headingFont"] ?? "")")
        XCTAssertEqual(state["headingHasAlegreya"] as? Bool, true, "Heading font was \(state["headingFont"] ?? "")")
        XCTAssertLessThan(state["templatesHeight"] as? Double ?? 999, 72, "Templates used kept a large empty tan region: \(state)")
        XCTAssertEqual(state["labelText"] as? String, "Ahrim?")
        XCTAssertEqual(state["labelVisible"] as? Bool, true, "\(state)")
        XCTAssertEqual(state["labelNotClippedRight"] as? Bool, true, "\(state)")
        XCTAssertEqual(state["labelThenControl"] as? Bool, true, "Infobox language is label|control, not control then label: \(state)")
        XCTAssertEqual(state["checkboxLabelSameRow"] as? Bool, true, "Checkbox/label stacked vertically: \(state)")
        XCTAssertEqual(state["dharokThenControl"] as? Bool, true, "Field-first OOUI DOM must still render label|control: \(state)")
        XCTAssertEqual(state["dharokSameRow"] as? Bool, true, "Field-first OOUI DOM stacked the Dharok row: \(state)")
        XCTAssertEqual(state["attackThenStepper"] as? Bool, true, "Attack label must sit in the grid beside the stepper: \(state)")
        XCTAssertEqual(state["attackStepperSameRow"] as? Bool, true, "\(state)")
        XCTAssertEqual(state["minusPlusSameRow"] as? Bool, true, "Integer steppers must keep minus and plus on one row: \(state)")
        XCTAssertEqual(state["plusAfterMinus"] as? Bool, true, "\(state)")
        XCTAssertEqual(state["lookupNearWhite"] as? Bool, false, "Lookup stayed Wikipedia white: \(state["lookupBg"] ?? "")")
        XCTAssertEqual(state["inputNearWhite"] as? Bool, false, "Input stayed Wikipedia white: \(state["inputBg"] ?? "")")
        XCTAssertEqual(state["checkNearWhite"] as? Bool, false, "Checkbox stayed Wikipedia white: \(state["checkBg"] ?? "")")
        XCTAssertEqual(state["submitWikiBlue"] as? Bool, false, "Submit stayed Wikipedia blue: \(state["submitBg"] ?? "")")
        XCTAssertLessThan(state["lookupPaddingTop"] as? Double ?? 99, 20, "OOUI icon padding-top leaked onto calculator buttons")
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

    func testInArticleTocShrinkWrapsWhileProseBannersStayFullWidthThemedAndUnscrolled() async throws {
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

        XCTAssertEqual(state["tocDisplay"] as? String, "table")
        XCTAssertEqual(state["tocClear"] as? String, "both")
        XCTAssertLessThan(
            state["tocWidth"] as? Double ?? 999,
            (state["viewportWidth"] as? Double ?? 0) * 0.7,
            "In-article Contents must shrink-wrap instead of spanning the viewport"
        )
        XCTAssertEqual(state["messageboxSurface"] as? Bool, false)
        XCTAssertFalse((state["messageboxParent"] as? String ?? "").contains("osrs-article-scroll-region"))
        XCTAssertLessThanOrEqual(
            (state["messageboxScrollWidth"] as? Double ?? 99) - (state["messageboxClientWidth"] as? Double ?? 0),
            2
        )
        XCTAssertEqual(state["captionColor"] as? String, "rgb(17, 34, 51)")
        XCTAssertEqual(state["mapCaptionColor"] as? String, "rgb(17, 34, 51)")
    }

    func testWikiQuoteBoxesWrapInsideContentWidthInLightAndDark() async throws {
        let polish = try readAsset("Assets/web/mobile_article_polish.js")
        let interceptor = try readAsset("Assets/web/horizontal_scroll_interceptor.js")
        let themes = try readAsset("Assets/styles/themes.css")
        let base = try readAsset("Assets/styles/base.css")
        let components = try readAsset("Assets/styles/components.css")
        let fixes = try readAsset("Assets/styles/fixes.css")
        let quoteText = """
        The 60kB limit was still in place when I wrote "Sea Shanty 2", so it was a simple tune like all those early tracks — again, I was going for catchy. It came very quickly to me once I was in the shanty-writing groove. It has remained in the game for well over a decade, and has always enjoyed a degree of notoriety because it's a cheesy earworm. Since Old School RuneScape launched in 2013, we came to realise that the fanbase had re-embraced the track, and it has become a meme. There are plenty of silly videos featuring it, Rick-Rolling, etc. Although it makes me cringe a little, I don't mind it being a humorous song as it has charm. One of my ambitions in life is to write a novelty track and retire from the proceeds. "Sea Shanty 2" might be my best effort yet, but sadly I'm not close to retiring...
        """
        let html = """
        <!doctype html>
        <html class="theme-osrs-light">
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        html, body { margin: 0; width: 375px; }
        \(themes)
        \(base)
        \(components)
        \(fixes)
        </style>
        </head>
        <body class="theme-osrs-light">
          <div class="mw-parser-output">
            <p id="lead-para">Ian Taylor later commented on its fame:</p>
            <table id="sea-shanty-quote" align="center" style="border-collapse:collapse; border-style:none; background-color:transparent;">
              <tbody><tr>
                <td class="quotation-mark" style="width:20px; vertical-align:top; font-size:40px; font-family:serif; font-weight:bold; text-align:left; padding:10px 10px;">“</td>
                <td id="quote-text" style="vertical-align:center; padding:4px 10px;">\(quoteText)</td>
                <td class="quotation-mark" style="width:20px; vertical-align:bottom; font-size:40px; font-family:serif; font-weight:bold; text-align:right; padding:10px 10px;">”</td>
              </tr>
              <tr>
                <td id="quote-spacer">&nbsp;</td>
                <td id="quote-cite" style="vertical-align:top"><div style="line-height:1em;text-align: right"><cite style="font-style:normal;">— Ian Taylor</cite></div></td>
              </tr></tbody>
            </table>
            <div id="toc" class="toc"><div class="toctitle"><h2>Contents</h2></div><ul><li>Versions</li></ul></div>
            <p id="jagex-lead">Mark Gerhard later commented:</p>
            <table id="jagex-quote" align="center" style="border-collapse:collapse; border-style:none; background-color:transparent;">
              <tbody><tr>
                <td class="quotation-mark" style="width:20px; vertical-align:top; font-size:40px; font-family:serif; font-weight:bold; text-align:left; padding:10px 10px;">“</td>
                <td id="jagex-quote-text" style="vertical-align:center; padding:4px 10px;">Sadly the game was not as complete as we wanted and we spent the first few months trying to "fix" the game where we could. About a month or so ago we took the decision to stop trying to "fix it" as we still wouldn't have the game we wanted and the game certainly did not meet all the objectives and specifications established in the original game design document and therefore it would be better to go back to the founding principles and build the game we always wanted.</td>
                <td class="quotation-mark" style="width:20px; vertical-align:bottom; font-size:40px; font-family:serif; font-weight:bold; text-align:right; padding:10px 10px;">”</td>
              </tr>
              <tr>
                <td>&nbsp;</td>
                <td style="vertical-align:top"><div style="line-height:1em;text-align: right"><cite style="font-style:normal;">— Mark Gerhard, 25 October 2009</cite></div></td>
              </tr></tbody>
            </table>
            <blockquote id="quote-block">\(quoteText)</blockquote>
            <pre id="code-sample"><code>UNBROKEN_TOKEN_THAT_SHOULD_STILL_BE_ALLOWED_TO_OVERFLOW_HORIZONTALLY_WHEN_IT_CANNOT_WRAP_BECAUSE_IT_HAS_NO_SPACES_OR_BREAKS_0123456789_ABCDEFGHIJKLMNOPQRSTUVWXYZ</code></pre>
          </div>
          <script>\(polish)</script>
          <script>\(interceptor)</script>
        </body>
        </html>
        """

        try await load(html)
        let state = try await evaluate("""
        (() => {
            function lineBoxHeight(el) {
                const cs = getComputedStyle(el);
                const parsed = parseFloat(cs.lineHeight);
                if (cs.lineHeight !== 'normal' && Number.isFinite(parsed)) return parsed;
                return parseFloat(cs.fontSize) * 1.2;
            }
            function lineBoxes(el) {
                const range = document.createRange();
                range.selectNodeContents(el);
                const unique = [];
                for (const r of range.getClientRects()) {
                    const prev = unique.find((item) => Math.abs(item.top - r.top) < 0.5);
                    if (prev) {
                        prev.width = Math.max(prev.width, r.width);
                        continue;
                    }
                    unique.push({ top: r.top, width: r.width, height: r.height });
                }
                return unique;
            }
            function measureQuote(tableId, textId) {
                const table = document.getElementById(tableId);
                const cell = document.getElementById(textId);
                const marks = [...table.querySelectorAll('td.quotation-mark')];
                const lines = lineBoxes(cell);
                return {
                    tableWidth: table.getBoundingClientRect().width,
                    tableDelta: table.scrollWidth - table.clientWidth,
                    tableSurface: !!(table.closest('.osrs-local-scroll-surface') ||
                        (table.parentElement && /osrs-local-scroll-surface|osrs-article-scroll-region/.test(table.parentElement.className || ''))),
                    cellWidth: cell.getBoundingClientRect().width,
                    cellHeight: cell.getBoundingClientRect().height,
                    cellLine: lineBoxHeight(cell),
                    cellWhiteSpace: getComputedStyle(cell).whiteSpace,
                    cellMaxLineWidth: lines.reduce((m, l) => Math.max(m, l.width), 0),
                    maxMarkWidth: marks.reduce((m, el) => Math.max(m, el.getBoundingClientRect().width), 0)
                };
            }
            function measure(theme) {
                document.documentElement.className = theme;
                document.body.className = theme;
                if (typeof window.OSRSApplyArticlePolish === 'function') {
                    window.OSRSApplyArticlePolish();
                }
                const block = document.getElementById('quote-block');
                const pre = document.getElementById('code-sample');
                const para = document.getElementById('lead-para');
                const sea = measureQuote('sea-shanty-quote', 'quote-text');
                const jagex = measureQuote('jagex-quote', 'jagex-quote-text');
                const viewport = document.documentElement.clientWidth;
                return {
                    viewportWidth: viewport,
                    paraWidth: para.getBoundingClientRect().width,
                    tableWidth: sea.tableWidth,
                    tableDelta: sea.tableDelta,
                    tableSurface: sea.tableSurface,
                    cellWidth: sea.cellWidth,
                    cellWhiteSpace: sea.cellWhiteSpace,
                    cellHeight: sea.cellHeight,
                    cellLine: sea.cellLine,
                    cellMaxLineWidth: sea.cellMaxLineWidth,
                    maxMarkWidth: sea.maxMarkWidth,
                    jagexCellWidth: jagex.cellWidth,
                    jagexCellHeight: jagex.cellHeight,
                    jagexCellLine: jagex.cellLine,
                    jagexCellWhiteSpace: jagex.cellWhiteSpace,
                    jagexMaxLineWidth: jagex.cellMaxLineWidth,
                    jagexMaxMarkWidth: jagex.maxMarkWidth,
                    jagexTableDelta: jagex.tableDelta,
                    blockWidth: block.getBoundingClientRect().width,
                    blockScrollWidth: block.scrollWidth,
                    blockClientWidth: block.clientWidth,
                    blockWhiteSpace: getComputedStyle(block).whiteSpace,
                    blockOverflowX: getComputedStyle(block).overflowX,
                    blockHeight: block.getBoundingClientRect().height,
                    blockLine: lineBoxHeight(block),
                    blockSurface: !!block.closest('.osrs-local-scroll-surface'),
                    preOverflowX: getComputedStyle(pre).overflowX,
                    rootScrollWidth: document.documentElement.scrollWidth
                };
            }
            const light = measure('theme-osrs-light');
            const dark = measure('theme-osrs-dark');
            return {
                lightViewport: light.viewportWidth,
                lightParaWidth: light.paraWidth,
                lightTableWidth: light.tableWidth,
                lightTableDelta: light.tableDelta,
                lightTableSurface: light.tableSurface,
                lightCellWidth: light.cellWidth,
                lightCellWhiteSpace: light.cellWhiteSpace,
                lightCellHeight: light.cellHeight,
                lightCellLine: light.cellLine,
                lightCellMaxLineWidth: light.cellMaxLineWidth,
                lightMaxMarkWidth: light.maxMarkWidth,
                lightJagexCellWidth: light.jagexCellWidth,
                lightJagexCellHeight: light.jagexCellHeight,
                lightJagexCellLine: light.jagexCellLine,
                lightJagexCellWhiteSpace: light.jagexCellWhiteSpace,
                lightJagexMaxLineWidth: light.jagexMaxLineWidth,
                lightJagexMaxMarkWidth: light.jagexMaxMarkWidth,
                lightJagexTableDelta: light.jagexTableDelta,
                lightBlockWidth: light.blockWidth,
                lightBlockDelta: light.blockScrollWidth - light.blockClientWidth,
                lightBlockWhiteSpace: light.blockWhiteSpace,
                lightBlockHeight: light.blockHeight,
                lightBlockLine: light.blockLine,
                lightBlockSurface: light.blockSurface,
                lightPreOverflowX: light.preOverflowX,
                lightRootScrollWidth: light.rootScrollWidth,
                darkViewport: dark.viewportWidth,
                darkParaWidth: dark.paraWidth,
                darkTableWidth: dark.tableWidth,
                darkTableDelta: dark.tableDelta,
                darkTableSurface: dark.tableSurface,
                darkCellWidth: dark.cellWidth,
                darkCellWhiteSpace: dark.cellWhiteSpace,
                darkCellHeight: dark.cellHeight,
                darkCellLine: dark.cellLine,
                darkCellMaxLineWidth: dark.cellMaxLineWidth,
                darkMaxMarkWidth: dark.maxMarkWidth,
                darkJagexCellWidth: dark.jagexCellWidth,
                darkJagexCellHeight: dark.jagexCellHeight,
                darkJagexCellLine: dark.jagexCellLine,
                darkJagexCellWhiteSpace: dark.jagexCellWhiteSpace,
                darkJagexMaxLineWidth: dark.jagexMaxLineWidth,
                darkJagexMaxMarkWidth: dark.jagexMaxMarkWidth,
                darkJagexTableDelta: dark.jagexTableDelta,
                darkBlockWidth: dark.blockWidth,
                darkBlockDelta: dark.blockScrollWidth - dark.blockClientWidth,
                darkBlockWhiteSpace: dark.blockWhiteSpace,
                darkBlockHeight: dark.blockHeight,
                darkBlockLine: dark.blockLine,
                darkBlockSurface: dark.blockSurface,
                darkPreOverflowX: dark.preOverflowX,
                darkRootScrollWidth: dark.rootScrollWidth
            };
        })()
        """)

        for prefix in ["light", "dark"] {
            let viewport = number(state, "\(prefix)Viewport")
            let paraWidth = number(state, "\(prefix)ParaWidth")
            XCTAssertGreaterThan(viewport, 0, "\(prefix) viewport")
            XCTAssertGreaterThan(paraWidth, 0, "\(prefix) sibling paragraph")
            XCTAssertLessThanOrEqual(
                number(state, "\(prefix)TableWidth"),
                viewport + 8,
                "\(prefix) Cquote2 table must stay inside the phone content width"
            )
            XCTAssertLessThanOrEqual(
                number(state, "\(prefix)TableDelta"),
                2,
                "\(prefix) Cquote2 table must wrap instead of scrolling horizontally"
            )
            XCTAssertEqual(state["\(prefix)TableSurface"] as? Bool, false, "\(prefix) Cquote2 must not become a local scroll surface")
            XCTAssertNotEqual(state["\(prefix)CellWhiteSpace"] as? String, "nowrap", "\(prefix) quote text cell must wrap")
            XCTAssertGreaterThan(
                number(state, "\(prefix)CellWidth"),
                paraWidth * 0.65,
                "\(prefix) Sea shanty 2 quote body must use paragraph-width, not a 1-2 letter rail"
            )
            XCTAssertGreaterThan(
                number(state, "\(prefix)CellMaxLineWidth"),
                paraWidth * 0.5,
                "\(prefix) Sea shanty 2 quote lines must be paragraph-width"
            )
            XCTAssertLessThan(
                number(state, "\(prefix)MaxMarkWidth"),
                viewport * 0.28,
                "\(prefix) quotation-mark columns must stay glyph-sized"
            )
            XCTAssertGreaterThan(
                number(state, "\(prefix)CellHeight"),
                number(state, "\(prefix)CellLine") * 1.5,
                "\(prefix) Cquote2 text must wrap onto more than one line at 375px"
            )
            XCTAssertGreaterThan(
                number(state, "\(prefix)JagexCellWidth"),
                paraWidth * 0.65,
                "\(prefix) Jagex quote body must use paragraph-width, not a 1-2 letter rail"
            )
            XCTAssertGreaterThan(
                number(state, "\(prefix)JagexMaxLineWidth"),
                paraWidth * 0.5,
                "\(prefix) Jagex quote lines must be paragraph-width"
            )
            XCTAssertNotEqual(state["\(prefix)JagexCellWhiteSpace"] as? String, "nowrap")
            XCTAssertGreaterThan(
                number(state, "\(prefix)JagexCellHeight"),
                number(state, "\(prefix)JagexCellLine") * 1.5
            )
            XCTAssertLessThanOrEqual(number(state, "\(prefix)JagexTableDelta"), 2)
            XCTAssertLessThanOrEqual(
                number(state, "\(prefix)BlockWidth"),
                viewport + 8,
                "\(prefix) blockquote must stay inside the phone content width"
            )
            XCTAssertGreaterThan(
                number(state, "\(prefix)BlockWidth"),
                paraWidth * 0.85,
                "\(prefix) blockquote must stay near paragraph width"
            )
            XCTAssertLessThanOrEqual(
                number(state, "\(prefix)BlockDelta"),
                2,
                "\(prefix) blockquote must wrap instead of scrolling horizontally"
            )
            XCTAssertNotEqual(state["\(prefix)BlockWhiteSpace"] as? String, "nowrap", "\(prefix) blockquote must wrap")
            XCTAssertEqual(state["\(prefix)BlockSurface"] as? Bool, false)
            XCTAssertGreaterThan(
                number(state, "\(prefix)BlockHeight"),
                number(state, "\(prefix)BlockLine") * 1.5,
                "\(prefix) blockquote text must wrap onto more than one line at 375px"
            )
            let preOverflow = state["\(prefix)PreOverflowX"] as? String ?? ""
            XCTAssertTrue(
                preOverflow == "auto" || preOverflow == "scroll",
                "\(prefix) pre/code must keep overflow-x for unbroken tokens, got \(preOverflow)"
            )
        }
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
        XCTAssertEqual(state["primaryOverflow"] as? String, "auto")
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

    func testStandaloneWideWikitableClassifyPointOwnsInteriorNotArticleEdge() async throws {
        let polish = try readAsset("Assets/web/mobile_article_polish.js")
        let horizontalScroll = try readAsset("Assets/web/horizontal_scroll_interceptor.js")
        let html = """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            body { margin: 0; }
            .mw-parser-output { width: 320px; }
            table.wikitable { min-width: 720px; border-collapse: collapse; }
            table.wikitable td { white-space: nowrap; padding: 8px; }
          </style>
        </head>
        <body>
          <div class="mw-parser-output">
            <table id="wideDrops" class="wikitable item-drops">
              <tbody><tr>
                <td id="wideCell">Long drop table cell that overflows the article column</td>
                <td>More overflowing columns of item quantities and rarity</td>
                <td>Still more columns so scrollWidth exceeds clientWidth</td>
              </tr></tbody>
            </table>
            <p id="ordinaryArticleText">Ordinary article navigation content.</p>
          </div>
          <script>\(polish)</script>
          <script>\(horizontalScroll)</script>
        </body>
        </html>
        """

        try await load(html)
        let state = try await evaluate("""
        (() => {
          if (window.OSRSApplyArticlePolish) { window.OSRSApplyArticlePolish(); }
          window.OSRSArticleMetrics.refreshHorizontalScrollAffordances();
          const cell = document.getElementById('wideCell');
          const ordinary = document.getElementById('ordinaryArticleText');
          const classify = (element, xRatio) => {
            const rect = element.getBoundingClientRect();
            return window.OSRSArticleGestureOwnership.classifyPoint(
              rect.left + Math.max(8, rect.width * xRatio),
              rect.top + Math.min(12, rect.height / 2)
            );
          };
          const interior = classify(cell, 0.35);
          const ordinaryOwnership = classify(ordinary, 0.5);
          const surfaces = Array.from(document.querySelectorAll('.osrs-local-scroll-surface, .osrs-article-scroll-region, table.wikitable'));
          const overflow = Math.max(0, ...surfaces.map(s => s.scrollWidth - s.clientWidth));
          return {
            overflow,
            interiorLocal: interior.isLocalOwner,
            ordinaryLocal: ordinaryOwnership.isLocalOwner
          };
        })()
        """)

        XCTAssertGreaterThan(state["overflow"] as? Double ?? 0, 20)
        XCTAssertEqual(state["interiorLocal"] as? Bool, true)
        XCTAssertEqual(state["ordinaryLocal"] as? Bool, false)
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

        XCTAssertEqual(firstMeasurementState["label"] as? String, "Map table")
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
        XCTAssertTrue(chart.contains("type: 'line'"))
        XCTAssertTrue(chart.contains("type: 'linear'"))
        XCTAssertTrue(chart.contains("role', 'application'"))
        XCTAssertTrue(chart.contains("ResizeObserver"))
        XCTAssertTrue(chart.contains("resolveChart"))
        XCTAssertTrue(chart.contains("AbortController"))
        XCTAssertTrue(chart.contains("Chart.js never became available"))
        XCTAssertTrue(chart.contains("Price history unavailable"))
        XCTAssertTrue(chart.contains("osrsChartPendingAt"))
        XCTAssertTrue(chart.contains("pageshow"))
        XCTAssertFalse(chart.contains("resolveHighcharts"))
        XCTAssertFalse(chart.contains("Highcharts.stockChart"))
        XCTAssertTrue(switcher.contains("data-default-version"))
        XCTAssertTrue(switcher.contains("preloader.decode()"))
        XCTAssertTrue(switcher.contains("updateExistingImage"))
        XCTAssertTrue(switcher.contains("lockSwitcherMinBlockSize"))
        XCTAssertTrue(switcher.contains("applySwitcherLayoutLock"))
        XCTAssertTrue(switcher.contains("scheduleSwitcherLayoutLock"))
        XCTAssertTrue(switcher.contains("stabilizeSwitcherScrollPin"))
        XCTAssertTrue(switcher.contains("captureSwitcherScrollPin"))
        XCTAssertTrue(switcher.contains("bindSwitcherViewportPin"))
        XCTAssertTrue(switcher.contains("osrsSwitcherScrollingElement"))
        XCTAssertTrue(switcher.contains("watchSwitcherHostSize"))
        XCTAssertTrue(switcher.contains("th.scrollWidth"))
        XCTAssertTrue(switcher.contains("setProperty('table-layout'"))
        XCTAssertFalse(switcher.contains("'width:max-content'"))
        XCTAssertFalse(switcher.contains("container.classList.contains('infobox-bonuses')"))
        XCTAssertFalse(switcher.contains("\n            stabilizeInfoboxWidth(mainInfobox"))
        XCTAssertTrue(fonts.contains("font-display: optional"))
        XCTAssertFalse(articleViewModel.contains("pageHeader.style.fontFamily"))
        XCTAssertTrue(htmlBuilder.contains("osrs-article-first-paint"))
        XCTAssertTrue(htmlBuilder.contains("background-color: #28221d"))
        XCTAssertTrue(htmlBuilder.contains("--body-main: #28221d"))
        XCTAssertTrue(htmlBuilder.contains("table.infobox-bonuses"))
        XCTAssertFalse(htmlBuilder.contains("min-width: min(18.75rem, 100%)"))
        XCTAssertTrue(htmlBuilder.contains("alegreya_bold.ttf"))
        XCTAssertTrue(htmlBuilder.contains("--osrs-article-safe-area-top"))
        XCTAssertTrue(htmlBuilder.contains("padding-top: calc(var(--osrs-article-safe-area-top) + var(--osrs-article-chrome-clearance))"))
        XCTAssertFalse(htmlBuilder.contains("env(safe-area-inset-top"))
        let iosAesthetics = try readAsset("Assets/styles/ios-article-aesthetics.css")
        XCTAssertTrue(iosAesthetics.contains("var(--osrs-article-safe-area-top, 0px)"))
        XCTAssertFalse(iosAesthetics.contains("env(safe-area-inset-top"))
    }

    func testGEChartScriptsLoadBeforeMediaWikiStartup() throws {
        let html = osrsPageHtmlBuilder().buildFullHtmlDocument(
            title: "Abyssal whip",
            bodyContent: """
            <div class="GEChartBox">
              <div class="GEdataprices" data-itemid="4151"></div>
              <div class="GEdatachart smallChart">Loading...</div>
            </div>
            """,
            theme: osrsLightTheme(),
            includeAssetLinks: true
        )
        let chartRange = try XCTUnwrap(html.range(of: "web/chart.umd.min.js"))
        let initRange = try XCTUnwrap(html.range(of: "web/ge_charts_init.js"))
        let startupRange = try XCTUnwrap(html.range(of: "startup.js"))
        XCTAssertLessThan(chartRange.lowerBound, startupRange.lowerBound)
        XCTAssertLessThan(initRange.lowerBound, startupRange.lowerBound)
        XCTAssertTrue(html.contains("osrsInstallFetchText"))
        XCTAssertTrue(html.contains("fetchText"))
    }

    func testGEChartFirstOpenReplacesLoadingPlaceholder() async throws {
        attachWebViewToWindow()
        let shippedChart = iosRoot.appendingPathComponent("osrswiki/Assets/web/chart.umd.min.js")
        let shippedInit = iosRoot.appendingPathComponent("osrswiki/Assets/web/ge_charts_init.js")
        XCTAssertTrue(FileManager.default.fileExists(atPath: shippedChart.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: shippedInit.path))

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ge-chart-first-open-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.copyItem(at: shippedChart, to: tmp.appendingPathComponent("chart.umd.min.js"))
        try FileManager.default.copyItem(at: shippedInit, to: tmp.appendingPathComponent("ge_charts_init.js"))

        let html = """
        <!DOCTYPE html>
        <html>
        <head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"></head>
        <body>
          <div class="GEChartBox">
            <div class="GEdataprices" data-itemid="4151"></div>
            <div class="GEdatachart smallChart">Loading...</div>
          </div>
          <script>
            window.OsrsWikiBridge = {
              fetchText: function(url) {
                return JSON.stringify({
                  data: [
                    { timestamp: 1700000000, avgHighPrice: 100000, avgLowPrice: 90000 },
                    { timestamp: 1700086400, avgHighPrice: 120000, avgLowPrice: 110000 },
                    { timestamp: 1700172800, avgHighPrice: 115000, avgLowPrice: 105000 }
                  ]
                });
              }
            };
          </script>
          <script src="chart.umd.min.js"></script>
          <script src="ge_charts_init.js"></script>
        </body>
        </html>
        """
        let index = tmp.appendingPathComponent("index.html")
        try html.write(to: index, atomically: true, encoding: .utf8)

        func probe() async throws -> [String: Any] {
            try await evaluate("""
            (() => {
                const el = document.querySelector('.GEdatachart');
                if (!el) return { text: '', canvas: false, role: '', chart: false };
                const text = String(el.innerText || el.textContent || '').replace(/\\s+/g, ' ').trim();
                return {
                    text: text.slice(0, 80),
                    canvas: !!el.querySelector('canvas'),
                    role: el.getAttribute('role') || '',
                    chart: !!(el.__osrsChart),
                    typeofChart: typeof window.Chart
                };
            })()
            """)
        }

        func waitSettled() async throws -> [String: Any] {
            var last: [String: Any] = [:]
            for _ in 0..<50 {
                last = try await probe()
                let canvas = boolValue(last["canvas"])
                let text = last["text"] as? String ?? ""
                if canvas || text.localizedCaseInsensitiveContains("unavailable") {
                    return last
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            return last
        }

        func assertNotStuck(_ state: [String: Any], label: String) {
            let text = state["text"] as? String ?? ""
            let canvas = boolValue(state["canvas"])
            XCTAssertFalse(
                text.localizedCaseInsensitiveContains("Loading"),
                "\(label) still shows Loading...: \(state)"
            )
            XCTAssertTrue(
                canvas || text.localizedCaseInsensitiveContains("unavailable"),
                "\(label) expected canvas or empty/error, got \(state)"
            )
        }

        try await loadFile(index, allowingReadAccessTo: tmp)
        let firstOpen = try await waitSettled()
        assertNotStuck(firstOpen, label: "first open")

        try await loadFile(index, allowingReadAccessTo: tmp)
        let refresh = try await waitSettled()
        assertNotStuck(refresh, label: "refresh analogue")
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
            return { height: box.getBoundingClientRect().height, widthPx: box.getBoundingClientRect().width, ready: box.dataset.osrsSwitcherReady || '' };
        })()
        """)
        _ = try await evaluate("(() => { performSwitch('2'); return { ok: true }; })()")
        let after = try await evaluate("""
        (() => {
            const box = document.querySelector('.infobox-switch');
            const selected = document.querySelector('.button-selected');
            return {
                height: box.getBoundingClientRect().height,
                widthPx: box.getBoundingClientRect().width,
                selected: (selected && selected.textContent) || '',
                width: box.style.width,
                minHeight: box.style.minHeight
            };
        })()
        """)
        XCTAssertEqual(before["ready"] as? String, "true")
        XCTAssertEqual(after["selected"] as? String, "B")
        XCTAssertFalse((after["width"] as? String ?? "").isEmpty)
        // Image state B is taller; width is locked so the column does not reflow.
        XCTAssertEqual(before["widthPx"] as? Double ?? 0, after["widthPx"] as? Double ?? -1, accuracy: 2.0)
    }

    func testMidPageSwitcherKeepsViewportPinWhenTopInfoboxHeightChanges() async throws {
        attachWebViewToWindow()
        let bootstrap = try readAsset("Assets/web/infobox_switcher_bootstrap.js")
        let switcher = try readAsset("Assets/web/switch_infobox.js")
        let html = """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        body { margin: 0; width: 375px; }
        table.infobox { width: 100%; border-collapse: collapse; }
        .tall { height: 220px; background: #c00; }
        .short { height: 48px; background: #0c0; }
        </style>
        </head>
        <body>
        <table class="infobox infobox-switch" data-resource-class=".infobox-resources-Item">
            <caption>
                <div class="infobox-buttons" data-default-version="1">
                    <span data-switch-index="1" class="button">Short</span>
                    <span data-switch-index="2" class="button">Tall</span>
                </div>
            </caption>
            <tbody>
                <tr><td data-attr-param="block"><div class="short"></div></td></tr>
            </tbody>
        </table>
        <div class="infobox-resources-Item infobox-switch-resources">
            <div data-attr-param="block">
                <span data-attr-index="1"><div class="short"></div></span>
                <span data-attr-index="2"><div class="tall"></div></span>
            </div>
        </div>
        <p>Combat stats filler so the mid-page control sits below the infobox.</p>
        <div style="height: 360px"></div>
        <div class="infobox-buttons" id="mid-page-switcher">
            <span data-switch-index="1" class="button">Short</span>
            <span data-switch-index="2" class="button" id="mid-tall">Tall</span>
        </div>
        <div style="height: 2000px">scrollable tail</div>
        <script>\(bootstrap)</script>
        <script>\(switcher)</script>
        <script>initializeInfoboxSwitcher();</script>
        </body>
        </html>
        """
        try await load(html)
        try await Task.sleep(nanoseconds: 250_000_000)
        _ = try await evaluate("""
        (() => {
            const pin = document.getElementById('mid-page-switcher');
            pin.scrollIntoView();
            return { ok: true };
        })()
        """)
        let before = try await evaluate("""
        (() => {
            const pin = document.getElementById('mid-page-switcher');
            const scroller = document.scrollingElement || document.documentElement;
            return {
                top: pin.getBoundingClientRect().top,
                scrollTop: scroller.scrollTop
            };
        })()
        """)
        _ = try await evaluate("""
        (() => {
            performSwitch('2', document.getElementById('mid-tall'));
            return { ok: true };
        })()
        """)
        try await Task.sleep(nanoseconds: 200_000_000)
        let after = try await evaluate("""
        (() => {
            const pin = document.getElementById('mid-page-switcher');
            const scroller = document.scrollingElement || document.documentElement;
            return {
                top: pin.getBoundingClientRect().top,
                scrollTop: scroller.scrollTop
            };
        })()
        """)
        XCTAssertEqual(
            before["top"] as? Double ?? 0,
            after["top"] as? Double ?? -1,
            accuracy: 2.0,
            "Switcher pin jumped from \(before) to \(after)"
        )
    }

    func testMidPageSelectSwitcherKeepsViewportPinWhenTopInfoboxHeightChanges() async throws {
        attachWebViewToWindow()
        let bootstrap = try readAsset("Assets/web/infobox_switcher_bootstrap.js")
        let switcher = try readAsset("Assets/web/switch_infobox.js")
        let html = """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        body { margin: 0; width: 375px; }
        table.infobox { width: 100%; border-collapse: collapse; }
        .tall { height: 220px; background: #c00; }
        .short { height: 48px; background: #0c0; }
        </style>
        </head>
        <body>
        <table class="infobox infobox-switch" data-resource-class=".infobox-resources-Item">
            <caption>
                <div class="infobox-buttons" data-default-version="1">
                    <span data-switch-index="1" class="button">Short</span>
                    <span data-switch-index="2" class="button">Tall</span>
                </div>
            </caption>
            <tbody>
                <tr><td data-attr-param="block"><div class="short"></div></td></tr>
            </tbody>
        </table>
        <div class="infobox-resources-Item infobox-switch-resources">
            <div data-attr-param="block">
                <span data-attr-index="1"><div class="short"></div></span>
                <span data-attr-index="2"><div class="tall"></div></span>
            </div>
        </div>
        <p>Bonuses filler so the mid-page control sits below the infobox.</p>
        <div style="height: 360px"></div>
        <div class="infobox-buttons" id="mid-page-switcher">
            <select id="mid-select">
                <option data-switch-index="1" value="1" selected>Short</option>
                <option data-switch-index="2" value="2">Tall</option>
            </select>
        </div>
        <div style="height: 2000px">scrollable tail</div>
        <script>\(bootstrap)</script>
        <script>\(switcher)</script>
        <script>initializeInfoboxSwitcher();</script>
        </body>
        </html>
        """
        try await load(html)
        try await Task.sleep(nanoseconds: 250_000_000)
        _ = try await evaluate("""
        (() => {
            document.getElementById('mid-page-switcher').scrollIntoView();
            return { ok: true };
        })()
        """)
        let before = try await evaluate("""
        (() => {
            const pin = document.getElementById('mid-page-switcher');
            return { top: pin.getBoundingClientRect().top };
        })()
        """)
        _ = try await evaluate("""
        (() => {
            const select = document.getElementById('mid-select');
            select.value = '2';
            select.dispatchEvent(new Event('change', { bubbles: true }));
            performSwitch('2', select);
            return { ok: true };
        })()
        """)
        try await Task.sleep(nanoseconds: 200_000_000)
        let after = try await evaluate("""
        (() => {
            const pin = document.getElementById('mid-page-switcher');
            return { top: pin.getBoundingClientRect().top };
        })()
        """)
        XCTAssertEqual(
            before["top"] as? Double ?? 0,
            after["top"] as? Double ?? -1,
            accuracy: 2.0,
            "Select switcher pin jumped from \(before) to \(after)"
        )
    }

    func testInfoboxAndBonusesRowHeightsStayStableAcrossScroll() async throws {
        attachWebViewToWindow()
        try await load(gloryMidPageSwitcherFixtureHTML())
        try await Task.sleep(nanoseconds: 250_000_000)
        let before = try await evaluate(gloryLayoutProbeScript(tag: "before-scroll"))
        XCTAssertEqual(before["ready"] as? String, "true")
        XCTAssertGreaterThan(number(before, "gloryHeight"), 40)
        XCTAssertGreaterThan(number(before, "bonusesHeight"), 20)
        _ = try await evaluate("""
        (() => {
            const scroller = document.scrollingElement || document.documentElement;
            const max = Math.max(0, (scroller.scrollHeight || 0) - (window.innerHeight || 812));
            const steps = [0.15, 0.35, 0.6, 0.9, 1];
            steps.forEach((frac) => { scroller.scrollTop = max * frac; });
            scroller.scrollTop = 0;
            return { ok: true, max: max };
        })()
        """)
        try await Task.sleep(nanoseconds: 150_000_000)
        let after = try await evaluate(gloryLayoutProbeScript(tag: "after-scroll"))
        XCTAssertEqual(
            number(before, "gloryHeight"),
            number(after, "gloryHeight"),
            accuracy: 1.0,
            "Infobox height ratcheted across scroll: \(before) -> \(after)"
        )
        XCTAssertEqual(
            number(before, "bonusesHeight"),
            number(after, "bonusesHeight"),
            accuracy: 1.0,
            "Equipment-stats height ratcheted across scroll: \(before) -> \(after)"
        )
        XCTAssertEqual(
            number(before, "gloryRow0"),
            number(after, "gloryRow0"),
            accuracy: 1.0,
            "Infobox row height ratcheted across scroll: \(before) -> \(after)"
        )
        XCTAssertEqual(
            number(before, "bonusesRow0"),
            number(after, "bonusesRow0"),
            accuracy: 1.0,
            "Bonuses row height ratcheted across scroll: \(before) -> \(after)"
        )
        XCTAssertEqual(number(after, "gloryMinHeight"), 0, accuracy: 0.5)
        XCTAssertEqual(number(after, "bonusesMinHeight"), 0, accuracy: 0.5)
    }

    func testFirstSwitchToUnactivatedStateLeavesSettledViewportUnmoved() async throws {
        attachWebViewToWindow()
        try await load(gloryMidPageSwitcherFixtureHTML())
        try await Task.sleep(nanoseconds: 250_000_000)
        _ = try await evaluate("""
        (() => {
            document.getElementById('mid-page-switcher').scrollIntoView();
            return { ok: true };
        })()
        """)
        let before = try await evaluate("""
        (() => {
            const pin = document.getElementById('mid-page-switcher');
            const scroller = document.scrollingElement || document.documentElement;
            const selected = document.querySelector('#mid-page-switcher .button-selected');
            return {
                top: pin.getBoundingClientRect().top,
                scrollTop: scroller.scrollTop,
                selected: (selected && selected.getAttribute('data-switch-index')) || '',
                activated: document.documentElement.dataset.osrsFlashStudyActivated || ''
            };
        })()
        """)
        XCTAssertEqual(before["selected"] as? String, "0")
        _ = try await evaluate("""
        (() => {
            performSwitch('1', document.getElementById('mid-charged'));
            return { ok: true };
        })()
        """)
        try await Task.sleep(nanoseconds: 250_000_000)
        let after = try await evaluate("""
        (() => {
            const pin = document.getElementById('mid-page-switcher');
            const scroller = document.scrollingElement || document.documentElement;
            const selected = document.querySelector('#mid-page-switcher .button-selected');
            const gloryName = (document.querySelector('#glory [data-attr-param="name"]') || {}).textContent || '';
            return {
                top: pin.getBoundingClientRect().top,
                scrollTop: scroller.scrollTop,
                selected: (selected && selected.getAttribute('data-switch-index')) || '',
                gloryName: gloryName.trim()
            };
        })()
        """)
        XCTAssertEqual(after["selected"] as? String, "1")
        XCTAssertEqual(after["gloryName"] as? String, "Amulet of glory (6)")
        XCTAssertEqual(
            number(before, "top"),
            number(after, "top"),
            accuracy: 2.0,
            "Settled first-switch pin/viewport top jumped from \(before) to \(after)"
        )
        // scrollTop is allowed to change: a taller top infobox must be
        // compensated so the mid-page pin stays put. A lasting viewport
        // jump is pin.getBoundingClientRect().top, not scroller.scrollTop.
        XCTAssertGreaterThan(number(after, "scrollTop"), 0)
    }

    func testOriginalMidPageSwitcherFlashStudyCapturesFramesAndLogs() async throws {
        attachWebViewToWindow()
        try await load(gloryMidPageSwitcherFixtureHTML(includeLazy: true))
        try await Task.sleep(nanoseconds: 250_000_000)
        let beforeImage = try await snapshot()
        add(XCTAttachment(image: beforeImage))
        _ = try await evaluate("""
        (() => {
            const pin = document.getElementById('mid-page-switcher');
            pin.scrollIntoView();
            \(gloryFlashStudyProbeSource())
            window.__osrsFlashStudy.snapshot('before');
            return { ok: true };
        })()
        """)
        _ = try await evaluate("""
        (() => {
            const charged = document.getElementById('mid-charged');
            window.__osrsFlashStudy.snapshot('pre-click');
            charged.click();
            window.__osrsFlashStudy.snapshot('sync-after-click');
            let frames = 0;
            const onFrame = () => {
                window.__osrsFlashStudy.snapshot('raf-' + frames);
                frames += 1;
                if (frames < 8) {
                    requestAnimationFrame(onFrame);
                    return;
                }
                window.__osrsFlashStudy.done = true;
            };
            requestAnimationFrame(onFrame);
            return { ok: true };
        })()
        """)
        var payload: [String: Any] = [:]
        for _ in 0..<50 {
            let probe = try await evaluate("""
            (() => {
                const state = window.__osrsFlashStudy || { done: false, samples: [] };
                return {
                    done: !!state.done,
                    json: JSON.stringify({ samples: state.samples || [] })
                };
            })()
            """)
            if boolValue(probe["done"]), let json = probe["json"] as? String,
               let data = json.data(using: .utf8),
               let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                payload = parsed
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let afterImage = try await snapshot()
        add(XCTAttachment(image: afterImage))
        let samples = payload["samples"] as? [[String: Any]] ?? []
        XCTAssertGreaterThanOrEqual(samples.count, 6, "Flash study needs before/during/after samples, got \(samples)")
        let json = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        let jsonText = String(data: json, encoding: .utf8) ?? "{}"
        let attachment = XCTAttachment(string: jsonText)
        attachment.name = "original-midpage-flash-study.json"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("OSRS_FLASH_STUDY_JSON_BEGIN")
        print(jsonText)
        print("OSRS_FLASH_STUDY_JSON_END")

        let tags = samples.map { $0["tag"] as? String ?? "" }
        XCTAssertTrue(tags.contains("before"))
        XCTAssertTrue(tags.contains { $0.hasPrefix("performSwitch") })
        XCTAssertTrue(tags.contains { $0.hasPrefix("restoreSwitcherScrollPin") })
        XCTAssertTrue(tags.contains { $0.hasPrefix("raf-") })

        let before = samples.first { ($0["tag"] as? String) == "before" } ?? samples[0]
        let lastRaf = samples.last { ($0["tag"] as? String)?.hasPrefix("raf-") == true } ?? samples.last!
        XCTAssertEqual(
            number(before, "pinTop"),
            number(lastRaf, "pinTop"),
            accuracy: 2.0,
            "Settled pin moved after original first-switch: before=\(before) last=\(lastRaf)"
        )

        let pinDeltas = samples.map { abs(number($0, "pinTop") - number(before, "pinTop")) }
        let srcs = samples.map { $0["imgSrc"] as? String ?? "" }
        let heights = samples.map { number($0, "gloryHeight") }
        let deferredHits = samples.filter { ($0["tag"] as? String)?.contains("restoreDeferredImage") == true }
        let pinRestores = samples.filter { ($0["tag"] as? String)?.hasPrefix("restoreSwitcherScrollPin") == true }
        let pinJumpedDuring = pinDeltas.contains { $0 > 2.0 }
        let srcChanged = Set(srcs.filter { !$0.isEmpty }).count > 1
        let heightChanged = (heights.max() ?? 0) - (heights.min() ?? 0) > 2.0
        XCTAssertFalse(
            deferredHits.isEmpty && !srcChanged && !pinJumpedDuring && !heightChanged,
            "Flash study recorded no src/layout/scroll change; samples=\(tags)"
        )
        _ = pinRestores
    }

    func testDarkFirstPaintUsesLiteralThemeBackgroundBeforeSharedCss() async throws {
        let firstPaint = osrsPageHtmlBuilder.articleFirstPaintStyle(
            chromeClearancePx: 0,
            safeAreaTopPx: 0,
            safeAreaBottomPx: 0
        )
        let html = """
        <!doctype html>
        <html class="theme-osrs-dark">
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        \(firstPaint)
        </head>
        <body class="theme-osrs-dark"></body>
        </html>
        """
        try await load(html)
        let colors = try await evaluate("""
        (() => {
            const html = getComputedStyle(document.documentElement);
            const body = getComputedStyle(document.body);
            return {
                htmlBg: html.backgroundColor,
                bodyBg: body.backgroundColor,
                htmlColor: html.color
            };
        })()
        """)
        XCTAssertTrue((colors["htmlBg"] as? String ?? "").contains("40, 34, 29"))
        XCTAssertTrue((colors["bodyBg"] as? String ?? "").contains("40, 34, 29"))
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

    func testExpandedDisclosureHeaderToContentGapsMatchAcrossKinds() async throws {
        let fixesCss = try readAsset("Assets/styles/fixes.css")
        let tablesCss = try readAsset("Assets/web/collapsible_tables.css")
        let collapsible = try readAsset("Assets/web/collapsible_content.js")
        XCTAssertTrue(collapsible.contains("osrsMeasureDisclosureHeaderGaps"))
        XCTAssertTrue(fixesCss.contains("--osrs-disclosure-control-padding-block: 12px;"))
        XCTAssertTrue(fixesCss.contains("html.osrs-table-cells-wrap"))
        XCTAssertTrue(fixesCss.contains(".osrs-toc-layout-table"))
        XCTAssertTrue(fixesCss.contains("#toctemplate"))
        XCTAssertTrue(fixesCss.contains("osrs-toc-layout-host"))
        XCTAssertTrue(fixesCss.contains(".collapsible-label"))
        XCTAssertTrue(collapsible.contains(".archivelist, .osrs-toc-layout-table"))

        func disclosure(
            kind: String,
            extraClass: String,
            label: String,
            body: String
        ) -> String {
            """
            <div class="collapsible-container \(extraClass)" data-osrs-disclosure-kind="\(kind)">
                <div class="collapsible-header">
                    <div class="title-wrapper">
                        <span class="collapsible-label">\(label)</span>
                        <span class="collapsible-state">Tap to collapse</span>
                    </div>
                    <div class="icon"></div>
                </div>
                <div class="collapsible-content">
                    <div class="osrs-disclosure-body">\(body)</div>
                </div>
            </div>
            """
        }

        let html = """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
        html { font-size: 16px; }
        body { margin: 16px; font-family: -apple-system, sans-serif; }
        \(fixesCss)
        \(tablesCss)
        table.infobox { margin: 1em 0 !important; }
        </style>
        </head>
        <body>
        \(disclosure(
            kind: "infobox",
            extraClass: "collapsible-infobox collapsible-primary-infobox",
            label: "Infobox",
            body: "<br><table class=\"infobox\"><tr><td>Varrock</td></tr></table>"
        ))
        \(disclosure(
            kind: "wikitable",
            extraClass: "collapsible-wikitable",
            label: "Table",
            body: "<table class=\"wikitable\"><tr><th>A</th><td>One</td></tr></table>"
        ))
        \(disclosure(
            kind: "section",
            extraClass: "",
            label: "Section",
            body: "<p>First section paragraph.</p>"
        ))
        <script>\(collapsible)</script>
        </body>
        </html>
        """
        try await load(html)
        try await Task.sleep(nanoseconds: 250_000_000)
        let state = try await evaluate("""
        (() => {
            const result = window.osrsMeasureDisclosureHeaderGaps();
            const heights = result.measurements.map((item) => item.headerHeightPx);
            const gaps = result.measurements.map((item) => item.gapPx);
            const spread = result.summary.reduce((max, item) => Math.max(max, item.spreadPx), 0);
            const kinds = result.summary.map((item) => item.kind).sort();
            return {
                count: result.measurements.length,
                minHeader: Math.min.apply(null, heights),
                maxHeader: Math.max.apply(null, heights),
                minGap: Math.min.apply(null, gaps),
                maxGap: Math.max.apply(null, gaps),
                kindSpread: spread,
                kinds: kinds.join(',')
            };
        })()
        """)

        XCTAssertEqual(number(state, "count"), 3, accuracy: 0.1)
        XCTAssertGreaterThanOrEqual(number(state, "minHeader"), 30)
        XCTAssertEqual(
            number(state, "maxGap"),
            number(state, "minGap"),
            accuracy: 2.0,
            "Expanded header-text to first-content gap must be consistent across disclosure kinds"
        )
        XCTAssertLessThanOrEqual(number(state, "kindSpread"), 2.0)
        XCTAssertEqual(state["kinds"] as? String, "infobox,section,wikitable")
    }

    func testDisclosureHeaderMatchesCloseHeightAndKeepsLabelOnTheStartEdge() async throws {
        let fixesCss = try readAsset("Assets/styles/fixes.css")
        let tablesCss = try readAsset("Assets/web/collapsible_tables.css")
        let html = """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
        html, body { margin: 0; font: 16px/1.3 -apple-system, sans-serif; }
        table.wikitable { text-align: center; width: 100%; }
        \(fixesCss)
        \(tablesCss)
        </style>
        </head>
        <body>
        <table class="wikitable">
          <tr>
            <td>
              <div class="collapsible-container collapsible-wikitable">
                <div class="collapsible-header">
                  <div class="title-wrapper">
                    <span class="collapsible-label">Table</span>
                    <span class="collapsible-state">Tap to collapse</span>
                  </div>
                  <div class="icon"></div>
                </div>
                <div class="collapsible-content">
                  <div class="osrs-disclosure-body"><p>Loot</p></div>
                </div>
                <div class="collapsible-close-button">
                  <div class="title-wrapper"><span class="collapsible-label">Close</span></div>
                </div>
              </div>
            </td>
          </tr>
        </table>
        <p>Inline <math class="mwe-math-element mwe-math-element-inline"><mrow><mi>E</mi></mrow></math> math.</p>
        <table>
          <tr>
            <td><table class="infobox"><tr><td>Agility</td></tr></table></td>
            <td><div id="toc" class="toc"><ul><li>Contents</li></ul></div></td>
          </tr>
        </table>
        <div id="toctemplate" style="clear:left; float:right; margin:0 0 1.5em 1.5em; width:auto;" class="nomobile">
          <div class="toc"><ul><li>Skills</li></ul></div>
        </div>
        <p class="skills-prose">Skills section text that must keep the full line measure.</p>
        <table class="archivelist"><tr><td>Templates used</td></tr></table>
        <script>
        \(try readAsset("Assets/web/mobile_article_polish.js"))
        </script>
        </body>
        </html>
        """
        try await load(html)
        try await Task.sleep(nanoseconds: 150_000_000)
        let state = try await evaluate("""
        (() => {
            const header = document.querySelector('.collapsible-header');
            const close = document.querySelector('.collapsible-close-button');
            const label = document.querySelector('.collapsible-header .collapsible-label');
            const math = document.querySelector('p > .mwe-math-element');
            const paragraph = math && math.closest('p');
            const tocTable = document.querySelector('.osrs-toc-layout-table');
            const tocHost = document.querySelector('#toctemplate');
            const archive = document.querySelector('table.archivelist');
            const headerRect = header.getBoundingClientRect();
            const closeRect = close.getBoundingClientRect();
            const labelRect = label.getBoundingClientRect();
            const mathRect = math ? math.getBoundingClientRect() : null;
            const paragraphRect = paragraph ? paragraph.getBoundingClientRect() : null;
            const headerStyle = getComputedStyle(header);
            const tocHostRect = tocHost ? tocHost.getBoundingClientRect() : null;
            const archiveRect = archive ? archive.getBoundingClientRect() : null;
            return {
                headerHeight: headerRect.height,
                closeHeight: closeRect.height,
                labelLeft: labelRect.left,
                headerContentLeft: headerRect.left + parseFloat(headerStyle.paddingLeft),
                headerTextAlign: getComputedStyle(label).textAlign,
                mathDisplay: math ? getComputedStyle(math).display : '',
                mathWidth: mathRect ? mathRect.width : 0,
                paragraphWidth: paragraphRect ? paragraphRect.width : 0,
                tocMarked: !!tocTable,
                tocDisplay: tocTable ? getComputedStyle(tocTable).display : '',
                tocHostClass: tocHost ? tocHost.className : '',
                tocHostFloat: tocHost ? getComputedStyle(tocHost).float : '',
                tocHostWidth: tocHostRect ? tocHostRect.width : 0,
                archiveFloat: archive ? getComputedStyle(archive).float : '',
                archiveWidth: archiveRect ? archiveRect.width : 0,
                viewportWidth: document.documentElement.clientWidth
            };
        })()
        """)
        XCTAssertEqual(number(state, "headerHeight"), number(state, "closeHeight"), accuracy: 2.0)
        XCTAssertEqual(
            number(state, "labelLeft"),
            number(state, "headerContentLeft"),
            accuracy: 2.0,
            "Collapsible header text must sit on the start edge, not centered in leftover space"
        )
        let align = state["headerTextAlign"] as? String ?? ""
        XCTAssertTrue(align == "start" || align == "left", "label text-align was \(align)")
        XCTAssertTrue((state["mathDisplay"] as? String ?? "").contains("inline"))
        XCTAssertLessThan(
            number(state, "mathWidth"),
            number(state, "paragraphWidth") * 0.5,
            "Inline math must shrink-wrap instead of stretching to the paragraph width"
        )
        XCTAssertEqual(state["tocMarked"] as? Bool, true)
        XCTAssertEqual(state["tocDisplay"] as? String, "block")
        XCTAssertTrue((state["tocHostClass"] as? String ?? "").contains("osrs-toc-layout-host"))
        XCTAssertEqual(state["tocHostFloat"] as? String, "none")
        XCTAssertLessThan(
            number(state, "tocHostWidth"),
            number(state, "viewportWidth") * 0.7,
            "Floated Contents hosts must shrink-wrap instead of using the full article width"
        )
        XCTAssertEqual(state["archiveFloat"] as? String, "none")
        XCTAssertGreaterThan(
            number(state, "archiveWidth"),
            number(state, "viewportWidth") * 0.85,
            "Template-used banners must use the full article width"
        )
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

    func testInfoboxSwitcherKeepsLabelColumnAndWidthAcrossStates() async throws {
        let switcher = try readAsset("Assets/web/switch_infobox.js")
        let html = """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        body { margin: 0; font: 16px/1.3 -apple-system, sans-serif; }
        .article { width: 280px; }
        table.infobox, .infobox-switch {
            border-collapse: collapse;
            width: max-content !important;
            max-width: 100% !important;
            table-layout: auto !important;
        }
        table.infobox th, table.infobox td {
            padding: 0.24em 0.42em;
            border: 1px solid #333;
        }
        .infobox-header { text-align: center; }
        .infobox-buttons { display: flex; gap: 4px; }
        .infobox-buttons .button { padding: 2px 6px; cursor: pointer; }
        .infobox-resources-test { display: none; }
        </style>
        </head>
        <body>
        <script>window.mw = { hook: function() { return { add: function(fn) { fn(); } }; } };</script>
        <div class="article">
        <table class="infobox infobox-switch" data-resource-class=".infobox-resources-test">
            <tr><th colspan="2" class="infobox-header" data-attr-param="name">Amulet of glory(4)</th></tr>
            <tr><th>Equipable</th><td data-attr-param="equipable">Yes</td></tr>
            <tr><th>Tradeable</th><td data-attr-param="tradeable">Yes</td></tr>
            <tr><th>Destroyed</th><td data-attr-param="destroyed">Drop</td></tr>
            <tr><td colspan="2">
                <div class="infobox-buttons" data-default-version="0">
                    <span class="button button-selected" data-switch-index="0">4</span>
                    <span class="button" data-switch-index="1">3</span>
                    <span class="button" data-switch-index="2">Uncharged</span>
                </div>
            </td></tr>
        </table>
        </div>
        <div class="infobox-resources-test">
            <div data-attr-param="name">
                <div data-attr-index="0">Amulet of glory(4)</div>
                <div data-attr-index="1">Amulet of glory(3)</div>
                <div data-attr-index="2">Amulet of glory</div>
            </div>
            <div data-attr-param="equipable">
                <div data-attr-index="0">Yes</div>
                <div data-attr-index="1">Yes</div>
                <div data-attr-index="2">Yes</div>
            </div>
            <div data-attr-param="tradeable">
                <div data-attr-index="0">Yes</div>
                <div data-attr-index="1">Yes, plus a much longer value that used to steal the label column WWWWWWWWWWWWWWWWWWWWWWWWW</div>
                <div data-attr-index="2">Yes</div>
            </div>
            <div data-attr-param="destroyed">
                <div data-attr-index="0">Drop</div>
                <div data-attr-index="1">Drop</div>
                <div data-attr-index="2">Drop</div>
            </div>
        </div>
        <script>\(switcher)</script>
        </body>
        </html>
        """

        try await load(html)
        try await Task.sleep(nanoseconds: 250_000_000)
        func metrics() async throws -> [String: Any] {
            try await evaluate("""
            (() => {
                const box = document.querySelector('.infobox-switch');
                const label = Array.from(box.querySelectorAll('th')).find((th) => th.textContent.trim() === 'Equipable');
                const boxRect = box.getBoundingClientRect();
                const labelRect = label.getBoundingClientRect();
                return {
                    width: boxRect.width,
                    height: boxRect.height,
                    labelWidth: labelRect.width,
                    labelHeight: labelRect.height
                };
            })()
            """)
        }

        let baseline = try await metrics()
        _ = try await evaluate("""
        (() => { performSwitch('1'); return { ok: 1 }; })()
        """)
        let wideState = try await metrics()
        _ = try await evaluate("""
        (() => { performSwitch('2'); return { ok: 1 }; })()
        """)
        let uncharged = try await metrics()

        XCTAssertGreaterThan(number(baseline, "width"), 80)
        XCTAssertEqual(number(wideState, "width"), number(baseline, "width"), accuracy: 1.0)
        XCTAssertEqual(number(uncharged, "width"), number(baseline, "width"), accuracy: 1.0)
        XCTAssertEqual(number(wideState, "labelWidth"), number(baseline, "labelWidth"), accuracy: 1.0)
        XCTAssertEqual(number(uncharged, "labelWidth"), number(baseline, "labelWidth"), accuracy: 1.0)
        XCTAssertEqual(number(wideState, "labelHeight"), number(baseline, "labelHeight"), accuracy: 1.0)
        XCTAssertEqual(number(uncharged, "labelHeight"), number(baseline, "labelHeight"), accuracy: 1.0)
    }

    func testGloryBonusesTableStaysViewportFitInsideScrollSurface() async throws {
        let fixes = try readAsset("Assets/styles/fixes.css")
        let firstPaint = osrsPageHtmlBuilder.articleFirstPaintStyle(
            chromeClearancePx: 0,
            safeAreaTopPx: 0,
            safeAreaBottomPx: 0
        )
        attachWebViewToWindow()
        let html = """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        \(firstPaint)
        <style>\(fixes)</style>
        </head>
        <body style="margin:0">
          <div class="collapsible-content osrs-local-scroll-surface" id="surface" style="width:375px">
            <table id="bonuses" class="infobox infobox-bonuses">
              <tbody>
                <tr>
                  <th class="infobox-header" colspan="5">Combat bonuses</th>
                </tr>
                <tr>
                  <td class="infobox-nested">+10</td>
                  <td class="infobox-nested">+10</td>
                  <td class="infobox-nested">+10</td>
                  <td class="infobox-nested">+10</td>
                  <td class="infobox-nested">+10</td>
                </tr>
              </tbody>
            </table>
            <table id="item" class="infobox">
              <tbody>
                <tr><th>Released</th><td>27 February 2002</td></tr>
                <tr><th>Members</th><td>Yes</td></tr>
              </tbody>
            </table>
          </div>
        </body>
        </html>
        """
        try await load(html)
        let state = try await evaluate("""
        (() => {
          const bonuses = document.getElementById('bonuses');
          const item = document.getElementById('item');
          const bonusesStyle = getComputedStyle(bonuses);
          const itemStyle = getComputedStyle(item);
          return {
            bonusesLayout: bonusesStyle.tableLayout,
            bonusesWidth: bonuses.getBoundingClientRect().width,
            bonusesMaxWidth: bonusesStyle.maxWidth,
            itemWidth: item.getBoundingClientRect().width,
            itemMaxWidth: itemStyle.maxWidth,
            viewport: document.documentElement.clientWidth
          };
        })()
        """)
        XCTAssertEqual(state["bonusesLayout"] as? String, "fixed")
        XCTAssertLessThanOrEqual(state["bonusesWidth"] as? Double ?? 999, (state["viewport"] as? Double ?? 0) + 1)
        XCTAssertLessThanOrEqual(state["itemWidth"] as? Double ?? 999, (state["viewport"] as? Double ?? 0) + 1)
        XCTAssertNotEqual(state["bonusesMaxWidth"] as? String, "none")
    }

    func testInfoboxValueCellsKeepMeasuredFloorAfterLateFixedLayout() async throws {
        let fixes = try readAsset("Assets/styles/fixes.css")
        let iosAesthetics = try readAsset("Assets/styles/ios-article-aesthetics.css")
        let normalize = try readAsset("Assets/web/table_column_normalize.js")
        XCTAssertFalse(fixes.contains("max(8em, min-content)"))
        attachWebViewToWindow()
        let html = """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        body { margin: 0; font: 16px/1.3 -apple-system, sans-serif; }
        .article { width: 375px; max-width: 375px; overflow: hidden; }
        \(fixes)
        \(iosAesthetics)
        </style>
        </head>
        <body>
        <div class="article">
          <div class="collapsible-primary-infobox">
            <div class="collapsible-content">
              <table class="main-infobox infobox infobox-switch">
                <tbody>
                  <tr><th colspan="2" class="infobox-header">Abyssal whip</th></tr>
                  <tr><td colspan="2" class="infobox-image"><img width="120" height="120" src="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw=="></td></tr>
                  <tr><th>Released</th><td id="released">26 January 2005</td></tr>
                  <tr><th>Members</th><td id="members">Yes</td></tr>
                  <tr><th>Tradeable</th><td id="tradeable">Yes</td></tr>
                  <tr><th>Examine</th><td id="examine">A weapon from the abyss.</td></tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>
        <script>\(normalize)</script>
        </body>
        </html>
        """

        try await load(html)
        try await Task.sleep(nanoseconds: 250_000_000)
        _ = try await evaluate("""
        (() => {
            if (typeof window.__osrsLockInfoboxValueFloors === 'function') {
                window.__osrsLockInfoboxValueFloors();
            }
            return { ok: 1 };
        })()
        """)
        let before = try await evaluate("""
        (() => {
            const box = document.querySelector('table.infobox');
            const released = document.getElementById('released');
            const examine = document.getElementById('examine');
            return {
                boxWidth: box.getBoundingClientRect().width,
                releasedWidth: released.getBoundingClientRect().width,
                examineWidth: examine.getBoundingClientRect().width,
                floor: released.dataset.osrsValueFloor || ''
            };
        })()
        """)
        XCTAssertGreaterThan(number(before, "releasedWidth"), 24)
        XCTAssertGreaterThan(number(before, "examineWidth"), 24)
        XCTAssertLessThan(
            number(before, "boxWidth"),
            390,
            "Value-cell floors must not stretch a compact infobox past the phone column"
        )

        _ = try await evaluate("""
        (() => {
            const box = document.querySelector('table.infobox');
            const width = box.getBoundingClientRect().width;
            box.style.setProperty('table-layout', 'fixed', 'important');
            box.style.setProperty('width', width + 'px', 'important');
            if (typeof window.__osrsLockInfoboxValueFloors === 'function') {
                window.__osrsLockInfoboxValueFloors();
            }
            return { ok: 1 };
        })()
        """)
        try await Task.sleep(nanoseconds: 50_000_000)
        let after = try await evaluate("""
        (() => {
            const box = document.querySelector('table.infobox');
            const released = document.getElementById('released');
            const examine = document.getElementById('examine');
            return {
                boxWidth: box.getBoundingClientRect().width,
                releasedWidth: released.getBoundingClientRect().width,
                examineWidth: examine.getBoundingClientRect().width
            };
        })()
        """)
        XCTAssertGreaterThan(number(after, "releasedWidth"), 24)
        XCTAssertGreaterThan(number(after, "examineWidth"), 24)
        XCTAssertEqual(number(after, "boxWidth"), number(before, "boxWidth"), accuracy: 8.0)
    }

    private func gloryMidPageSwitcherFixtureHTML(includeLazy: Bool = false) throws -> String {
        let bootstrap = try readAsset("Assets/web/infobox_switcher_bootstrap.js")
        let switcher = try readAsset("Assets/web/switch_infobox.js")
        let lazy = includeLazy ? (try readAsset("Assets/web/article_image_lazy.js")) : ""
        let short = "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='40' height='48'><rect width='40' height='48' fill='%23c00'/></svg>"
        let tall = "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='80' height='280'><rect width='80' height='280' fill='%23006'/></svg>"
        let deferredImg = includeLazy
            ? "<img width=\"80\" height=\"280\" class=\"mw-file-element osrs-deferred-offscreen-image\" src=\"data:image/gif;base64,R0lGODlhAQABAAAAACwAAAAAAQABAAA=\" data-osrs-deferred-src=\"\(tall)\">"
            : "<img width=\"80\" height=\"280\" class=\"mw-file-element\" src=\"\(tall)\">"
        return """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        html, body { margin: 0; width: 375px; max-width: 375px; }
        table.infobox, table.infobox-bonuses { width: 375px; max-width: 375px; border-collapse: collapse; box-sizing: border-box; }
        table.infobox-bonuses th, table.infobox-bonuses td { min-width: 28px; padding: 4px; }
        </style>
        </head>
        <body>
        <table class="infobox infobox-switch" id="glory" data-resource-class=".infobox-resources-glory">
            <caption>
                <div class="infobox-buttons" data-default-version="0">
                    <span data-switch-index="0" class="button">Uncharged</span>
                    <span data-switch-index="1" class="button">6</span>
                </div>
            </caption>
            <tbody>
                <tr><th class="infobox-header" data-attr-param="name">Amulet of glory</th></tr>
                <tr><td data-attr-param="image"><img width="40" height="48" class="mw-file-element" src="\(short)"></td></tr>
            </tbody>
        </table>
        <div class="infobox-resources-glory infobox-switch-resources">
            <div data-attr-param="name">
                <span data-attr-index="0">Amulet of glory</span>
                <span data-attr-index="1">Amulet of glory (6)</span>
            </div>
            <div data-attr-param="image">
                <span data-attr-index="0"><img width="40" height="48" class="mw-file-element" src="\(short)"></span>
                <span data-attr-index="1">\(deferredImg)</span>
            </div>
        </div>
        <p>Combat stats filler so Equipment bonuses sits below the first screen.</p>
        <div style="height: 420px"></div>
        <table class="infobox infobox-switch infobox-bonuses" id="combatStats" data-resource-class=".infobox-resources-bonuses">
            <caption>
                <div class="infobox-buttons" id="mid-page-switcher" data-default-version="0">
                    <span data-switch-index="0" class="button">Uncharged</span>
                    <span data-switch-index="1" class="button" id="mid-charged">6</span>
                </div>
            </caption>
            <tbody>
                <tr>
                    <th class="infobox-subheader">Attack bonuses</th>
                    <th class="infobox-bonuses-image">Stab</th>
                    <th class="infobox-bonuses-image">Slash</th>
                    <th class="infobox-bonuses-image">Crush</th>
                </tr>
                <tr>
                    <td>Attack</td>
                    <td data-attr-param="stab">+0</td>
                    <td>+0</td>
                    <td>+0</td>
                </tr>
            </tbody>
        </table>
        <div class="infobox-resources-bonuses infobox-switch-resources">
            <div data-attr-param="stab">
                <span data-attr-index="0">+0</span>
                <span data-attr-index="1">+0</span>
            </div>
        </div>
        <div style="height: 2000px">scrollable tail</div>
        <script>\(lazy)</script>
        <script>\(bootstrap)</script>
        <script>\(switcher)</script>
        <script>initializeInfoboxSwitcher();</script>
        </body>
        </html>
        """
    }

    private func gloryLayoutProbeScript(tag: String) -> String {
        """
        (() => {
            const glory = document.getElementById('glory');
            const bonuses = document.getElementById('combatStats');
            const gloryRow = glory && glory.querySelector('tbody tr');
            const bonusesRow = bonuses && bonuses.querySelector('tbody tr');
            const gloryMin = glory ? parseFloat(getComputedStyle(glory).minHeight) || 0 : -1;
            const bonusesMin = bonuses ? parseFloat(getComputedStyle(bonuses).minHeight) || 0 : -1;
            return {
                tag: '\(tag)',
                ready: (glory && glory.dataset.osrsSwitcherReady) || '',
                gloryHeight: glory ? glory.getBoundingClientRect().height : -1,
                bonusesHeight: bonuses ? bonuses.getBoundingClientRect().height : -1,
                gloryRow0: gloryRow ? gloryRow.getBoundingClientRect().height : -1,
                bonusesRow0: bonusesRow ? bonusesRow.getBoundingClientRect().height : -1,
                gloryMinHeight: gloryMin,
                bonusesMinHeight: bonusesMin
            };
        })()
        """
    }

    private func gloryFlashStudyProbeSource() -> String {
        """
            (function () {
                const samples = [];
                const t0 = performance.now();
                const now = () => Math.round((performance.now() - t0) * 100) / 100;
                const snapshot = (tag, extra) => {
                    const pin = document.getElementById('mid-page-switcher');
                    const glory = document.getElementById('glory');
                    const bonuses = document.getElementById('combatStats');
                    const scroller = document.scrollingElement || document.documentElement;
                    const img = glory && glory.querySelector('img');
                    const rec = Object.assign({
                        tag: tag,
                        t: now(),
                        pinTop: pin ? Math.round(pin.getBoundingClientRect().top * 100) / 100 : null,
                        gloryTop: glory ? Math.round(glory.getBoundingClientRect().top * 100) / 100 : null,
                        gloryHeight: glory ? Math.round(glory.getBoundingClientRect().height * 100) / 100 : null,
                        bonusesTop: bonuses ? Math.round(bonuses.getBoundingClientRect().top * 100) / 100 : null,
                        bonusesHeight: bonuses ? Math.round(bonuses.getBoundingClientRect().height * 100) / 100 : null,
                        scrollTop: scroller ? Math.round((scroller.scrollTop || 0) * 100) / 100 : null,
                        scrollY: Math.round((window.scrollY || 0) * 100) / 100,
                        imgSrc: img ? (img.currentSrc || img.getAttribute('src') || '') : '',
                        imgComplete: !!(img && img.complete),
                        imgNatural: img ? img.naturalHeight : 0,
                        deferred: img ? (img.getAttribute('data-osrs-deferred-src') || '') : '',
                        firstView: !!window.__osrsFirstViewPainted
                    }, extra || {});
                    samples.push(rec);
                    return rec;
                };
                const wrap = (name) => {
                    const orig = window[name];
                    if (typeof orig !== 'function') return;
                    window[name] = function () {
                        snapshot(name + ':enter');
                        const result = orig.apply(this, arguments);
                        snapshot(name + ':exit');
                        return result;
                    };
                };
                wrap('performSwitch');
                wrap('restoreSwitcherScrollPin');
                wrap('stabilizeSwitcherScrollPin');
                wrap('restoreDeferredImage');
                wrap('updateExistingImage');
                wrap('populatePlaceholders');
                wrap('lockSwitcherMinBlockSize');
                wrap('applySwitcherLayoutLock');
                if (typeof window.osrsRestoreDeferredImage === 'function') {
                    const origLazy = window.osrsRestoreDeferredImage;
                    window.osrsRestoreDeferredImage = function (image) {
                        snapshot('osrsRestoreDeferredImage:enter', {
                            deferred: image && image.getAttribute && (image.getAttribute('data-osrs-deferred-src') || '')
                        });
                        const result = origLazy.apply(this, arguments);
                        snapshot('osrsRestoreDeferredImage:exit');
                        return result;
                    };
                }
                window.__osrsFlashStudy = { samples: samples, snapshot: snapshot, done: false };
            })();
        """
    }

    private func attachWebViewToWindow() {
        let host = UIViewController()
        host.view.frame = CGRect(x: 0, y: 0, width: 375, height: 812)
        webView.frame = host.view.bounds
        host.view.addSubview(webView)
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 375, height: 812)
        } else {
            window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 812))
        }
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        webView.layoutIfNeeded()
        hostWindow = window
    }

    private func load(_ html: String) async throws {
        let didFinish = expectation(description: "WebView loaded")
        let delegate = ArticleAestheticNavigationDelegate(didFinish: didFinish)
        navigationDelegate = delegate
        webView.navigationDelegate = delegate
        webView.loadHTMLString(html, baseURL: URL(string: "https://oldschool.runescape.wiki/"))
        await fulfillment(of: [didFinish], timeout: 10.0)
    }

    private func loadFile(_ url: URL, allowingReadAccessTo readAccessURL: URL) async throws {
        let didFinish = expectation(description: "WebView file loaded")
        let delegate = ArticleAestheticNavigationDelegate(didFinish: didFinish)
        navigationDelegate = delegate
        webView.navigationDelegate = delegate
        webView.loadFileURL(url, allowingReadAccessTo: readAccessURL)
        await fulfillment(of: [didFinish], timeout: 10.0)
    }

    private func boolValue(_ value: Any?) -> Bool {
        if let flag = value as? Bool { return flag }
        if let number = value as? NSNumber { return number.boolValue }
        return false
    }

    private func number(_ state: [String: Any], _ key: String) -> Double {
        if let value = state[key] as? NSNumber {
            return value.doubleValue
        }
        if let value = state[key] as? Double {
            return value
        }
        return 0
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
