import Combine
import WebKit
import XCTest
@testable import osrswiki

final class osrsNativeCalcDefinitionTests: XCTestCase {
    private let agilityConfig = """
    <pre class="jcConfig">
    template=Calculator:Skill calc/Template
    form=AgilityCalc
    result=AgilityResults
    name =
    param = name|Name||hs|XPInput,17,2;lvlInput,17,1
    param = currentToggle|Current: Level or Experience|Level|select|Level,Experience|Level=lvlInput;Experience=XPInput
    param = lvlInput|Current (per choice above)|1|int|1-126|
    param = XPInput|Current (per choice above)|1|int|1-200000000|
    param = goalToggle|Goal: Level or Experience?|Level|select|Level,Experience
    param = goal|Goal (per choice above)|0|int|0-200000000
    param = method|Method|All|select|All,Agility Course,Brimhaven Agility Arena,Rooftop Agility Course,Hallowed Sepulchre,Barbarian Fishing
    param = dataCriteria|Hide inaccessible methods|Show All|buttonselect|Show All,Hide,Greyed out
    param = leagueGroup|League multiplier?||toggleswitch|false|leagueMultiplier
    param = leagueMultiplier|League multiplier value?|5|int|5-32
    param = skill|Skill|Agility|hidden
    autosubmit = enabled
    </pre>
    """

    func testExtractIncludesHiddenSkillAndLiveLabels() throws {
        let definition = try XCTUnwrap(osrsNativeCalcDefinition.parse(agilityConfig, title: "Calculator:Agility"))
        XCTAssertEqual(definition.id, "Calculator:Agility")
        XCTAssertEqual(definition.invoke.kind, .template)
        XCTAssertEqual(definition.invoke.template, "Calculator:Skill calc/Template")
        XCTAssertEqual(definition.ui.formId, "AgilityCalc")
        XCTAssertEqual(definition.ui.resultId, "AgilityResults")
        XCTAssertEqual(definition.ui.autosubmit, "enabled")
        XCTAssertEqual(
            definition.inputs.map(\.name),
            [
                "name", "currentToggle", "lvlInput", "XPInput", "goalToggle",
                "goal", "method", "dataCriteria", "leagueGroup", "leagueMultiplier", "skill"
            ]
        )
        let skill = try XCTUnwrap(definition.inputs.first { $0.name == "skill" })
        XCTAssertEqual(skill.type, .hidden)
        XCTAssertEqual(skill.defaultValue, "Agility")
        let current = try XCTUnwrap(definition.inputs.first { $0.name == "currentToggle" })
        XCTAssertEqual(current.label, "Current: Level or Experience")
        XCTAssertEqual(current.options, ["Level", "Experience"])
        XCTAssertEqual(current.toggles["Level"], ["lvlInput"])
        XCTAssertEqual(current.toggles["Experience"], ["XPInput"])
        let method = try XCTUnwrap(definition.inputs.first { $0.name == "method" })
        XCTAssertTrue(method.options.contains("Hallowed Sepulchre"))
        let data = try XCTUnwrap(definition.inputs.first { $0.name == "dataCriteria" })
        XCTAssertEqual(data.type, .buttonSelect)
        XCTAssertEqual(data.label, "Hide inaccessible methods")
    }

    func testDefaultInvokeIncludesHiddenSkillAndOmitsDisabledFields() throws {
        let definition = try XCTUnwrap(osrsNativeCalcDefinition.parse(agilityConfig, title: "Calculator:Agility"))
        let wikitext = try XCTUnwrap(osrsNativeCalcDefinition.invokeWikitext(definition))
        XCTAssertTrue(wikitext.hasPrefix("{{Calculator:Skill calc/Template|"))
        XCTAssertTrue(wikitext.contains("|skill=Agility"))
        XCTAssertTrue(wikitext.contains("|currentToggle=Level"))
        XCTAssertTrue(wikitext.contains("|lvlInput=1"))
        XCTAssertFalse(wikitext.contains("|XPInput="))
        XCTAssertTrue(wikitext.contains("|goal=0"))
        XCTAssertTrue(wikitext.contains("|method=All"))
        XCTAssertTrue(wikitext.contains("|dataCriteria=Show All"))
        XCTAssertTrue(wikitext.contains("|leagueGroup=false"))
        XCTAssertFalse(wikitext.contains("|leagueMultiplier="))
        XCTAssertFalse(wikitext.contains("|name="))
        XCTAssertEqual(osrsCalculatorSaveWarmer.defaultTemplateCall(from: agilityConfig), wikitext)
    }

    func testExperienceToggleAndLeagueSwitchChangeSubmittedFields() throws {
        let definition = try XCTUnwrap(osrsNativeCalcDefinition.parse(agilityConfig, title: "Calculator:Agility"))
        let wikitext = try XCTUnwrap(
            osrsNativeCalcDefinition.invokeWikitext(
                definition,
                values: [
                    "currentToggle": "Experience",
                    "XPInput": "200",
                    "goalToggle": "Level",
                    "goal": "99",
                    "leagueGroup": "true",
                    "leagueMultiplier": "8"
                ]
            )
        )
        XCTAssertTrue(wikitext.contains("|currentToggle=Experience"))
        XCTAssertTrue(wikitext.contains("|XPInput=200"))
        XCTAssertFalse(wikitext.contains("|lvlInput="))
        XCTAssertTrue(wikitext.contains("|goal=99"))
        XCTAssertTrue(wikitext.contains("|leagueGroup=true"))
        XCTAssertTrue(wikitext.contains("|leagueMultiplier=8"))
        XCTAssertTrue(wikitext.contains("|skill=Agility"))
    }

    func testNativeChromeIsAgilityOnlyAndFallsBackOnUnknownTypes() {
        let agility = osrsNativeCalcDefinition.parse(agilityConfig, title: "Calculator:Agility")
        let cooking = osrsNativeCalcDefinition.parse(
            agilityConfig.replacingOccurrences(of: "Agility", with: "Cooking"),
            title: "Calculator:Cooking"
        )
        let unknown = osrsNativeCalcDefinition.parse(
            """
            <pre class="jcConfig">
            template = Calculator:Agility/Template
            param = voice|Voice of Seren|Amlodd|voiceofseren|
            param = skill|Skill|Agility|hidden
            </pre>
            """,
            title: "Calculator:Agility"
        )
        XCTAssertTrue(osrsNativeCalcDefinition.isNativeChromeEligible(agility))
        XCTAssertFalse(osrsNativeCalcDefinition.isNativeChromeEligible(cooking))
        XCTAssertFalse(osrsNativeCalcDefinition.isNativeChromeEligible(unknown))
        XCTAssertFalse(osrsNativeCalcDefinition.isNativeChromeEligible(nil))
        XCTAssertFalse(osrsNativeCalcDefinition.isNativeChromeEligible(
            osrsNativeCalcDefinition.parse("no config here")
        ))
    }

    func testParseResultDetectsScribuntoError() {
        XCTAssertTrue(osrsNativeCalcDefinition.parseResultIsError(
            "<div class=\"scribunto-error\">Lua error in Module:Skill_calc</div>"
        ))
        XCTAssertTrue(osrsNativeCalcDefinition.parseResultIsError(""))
        XCTAssertFalse(osrsNativeCalcDefinition.parseResultIsError(
            "<table class=\"wikitable\"><tr><td>Plank</td><td>1</td></tr></table>"
        ))
    }

    func testIntroCopyAndDarkResultWrapperAvoidBlackOnDark() {
        let copy = osrsNativeCalcDefinition.introCopy(from: """
        ===Assumptions===
        * The bonus experience gained at the Agility Pyramid is only calculated for the current level.
        ===Calculator===
        """)
        XCTAssertTrue(copy.contains("live wiki calculator"))
        XCTAssertTrue(copy.contains("Assumptions"))
        XCTAssertTrue(copy.contains("Agility Pyramid"))
        let dark = osrsNativeCalcDefinition.wrapResultHTML("<table><tr><td>Plank</td></tr></table>", dark: true)
        XCTAssertTrue(dark.contains("#28221d"))
        XCTAssertTrue(dark.contains("#f4eaea"))
        XCTAssertFalse(dark.contains("background: #000"))
        XCTAssertFalse(dark.contains("color: #000"))
    }

    func testFallbackReasons() {
        XCTAssertEqual(
            osrsNativeCalcDefinition.fallbackReason(
                title: "Calculator:Agility",
                definition: nil
            ),
            .missingConfig
        )
        XCTAssertEqual(
            osrsNativeCalcDefinition.fallbackReason(
                title: "Calculator:Agility",
                definition: osrsNativeCalcDefinition.parse(
                    """
                    <pre class="jcConfig">
                    template = Calculator:Agility/Template
                    param = voice|Voice of Seren|Amlodd|voiceofseren|
                    </pre>
                    """,
                    title: "Calculator:Agility"
                )
            ),
            .unknownParamType
        )
        XCTAssertEqual(
            osrsNativeCalcDefinition.fallbackReason(html: "<p class=\"scribunto-error\">Lua error</p>"),
            .parseError
        )
    }

    func testCombatLevelExtractAndDefaultInvokeReuseTheKit() throws {
        let config = """
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
        """
        let definition = try XCTUnwrap(osrsNativeCalcDefinition.parse(config, title: "Calculator:Combat level"))
        XCTAssertTrue(osrsNativeCalcDefinition.isNativeChromeEligible(definition))
        XCTAssertEqual(osrsNativeCalcDefinition.chromeTitle(for: definition.id), "Combat level calculator")
        XCTAssertEqual(definition.invoke.template, "Calculator:Combat level/Template")
        XCTAssertEqual(definition.inputs.map(\.name), [
            "playername", "attack", "strength", "ranged", "magic", "defence", "hitpoints", "prayer"
        ])
        XCTAssertFalse(definition.inputs.contains { $0.type == .hidden })
        let hp = try XCTUnwrap(definition.inputs.first { $0.name == "hitpoints" })
        XCTAssertEqual(hp.defaultValue, "10")
        XCTAssertEqual(hp.minValue, 9)
        XCTAssertEqual(hp.maxValue, 99)
        let wikitext = try XCTUnwrap(osrsNativeCalcDefinition.invokeWikitext(definition))
        XCTAssertEqual(
            wikitext,
            "{{Calculator:Combat level/Template|attack=1|strength=1|ranged=1|magic=1|defence=1|hitpoints=10|prayer=1}}"
        )
        XCTAssertFalse(wikitext.contains("|skill="))
        let copy = osrsNativeCalcDefinition.introCopy(from: config, title: "Calculator:Combat level")
        XCTAssertTrue(copy.lowercased().contains("combat"))
        XCTAssertFalse(copy.contains("Agility"))
        XCTAssertFalse(osrsNativeCalcDefinition.parseResultIsError("<p>Your combat level is 3, balanced.</p>"))
    }

    func testHiscoresUnavailableMessageMatchesWikiGadget() {
        XCTAssertEqual(
            osrsNativeCalcDefinition.hiscoresUnavailableMessage(player: "zzzznotaplayer"),
            "The player \"zzzznotaplayer\" does not exist, is banned or unranked, or we couldn't fetch your hiscores. Please enter the data manually."
        )
        XCTAssertEqual(
            osrsNativeCalcDefinition.hiscoresUnavailableMessage(player: "  Lynx Titan  "),
            osrsNativeCalcDefinition.hiscoresUnavailableMessage(player: "Lynx Titan")
        )
    }

    func testNameFieldEditsDoNotAutosubmit() {
        XCTAssertFalse(osrsNativeCalcDefinition.shouldAutosubmitOnEdit(.hs))
        XCTAssertFalse(osrsNativeCalcDefinition.shouldAutosubmitOnEdit(.rsn))
        XCTAssertFalse(osrsNativeCalcDefinition.shouldAutosubmitOnEdit(.string))
        XCTAssertTrue(osrsNativeCalcDefinition.shouldAutosubmitOnEdit(.select))
        XCTAssertTrue(osrsNativeCalcDefinition.shouldAutosubmitOnEdit(.int))
        XCTAssertTrue(osrsNativeCalcDefinition.shouldAutosubmitOnEdit(.toggleSwitch))
    }

    func testApplyHiscoresMapsAgilityLevelAndXp() {
        var lines = Array(repeating: "-1,-1,-1", count: 24)
        lines[17] = "100,60,273742"
        let body = lines.joined(separator: "\n")
        let applied = osrsNativeCalcDefinition.applyHiscores(
            body: body,
            mapping: "XPInput,17,2;lvlInput,17,1"
        )
        XCTAssertEqual(applied?["lvlInput"], "60")
        XCTAssertEqual(applied?["XPInput"], "273742")
    }

    func testApplyHiscoresRejectsMissingPlayerPayloads() {
        XCTAssertNil(osrsNativeCalcDefinition.applyHiscores(body: "", mapping: "lvlInput,17,1"))
        XCTAssertNil(osrsNativeCalcDefinition.applyHiscores(body: "404", mapping: "lvlInput,17,1"))
        XCTAssertNil(osrsNativeCalcDefinition.applyHiscores(
            body: "<html>not found</html>",
            mapping: "lvlInput,17,1"
        ))
        let lookup = osrsNativeCalcDefinition.interpretHiscoresLookup(
            ok: false,
            body: "",
            player: "zzzznotaplayer",
            mapping: "XPInput,17,2;lvlInput,17,1"
        )
        guard case .failed(let message) = lookup else {
            return XCTFail("expected failed lookup")
        }
        XCTAssertTrue(message.contains("zzzznotaplayer"))
        XCTAssertTrue(message.contains("does not exist"))
    }

    func testParseFailureStaysAsNativeBannerCopy() {
        let message = osrsNativeCalcDefinition.parseFailureMessage(
            "<p class=\"scribunto-error\">Lua error in Module:Skill_calc</p>"
        )
        XCTAssertFalse(message.isEmpty)
        XCTAssertFalse(message.lowercased().contains("scribunto"))
    }

    @MainActor
    func testNativeCalcKeepsArticleWebViewAsPageShell() throws {
        XCTAssertFalse(osrsNativeCalcSession.hidesArticleShell(phase: .idle))
        XCTAssertFalse(osrsNativeCalcSession.hidesArticleShell(phase: .loading))
        XCTAssertFalse(osrsNativeCalcSession.hidesArticleShell(phase: .native))
        XCTAssertFalse(osrsNativeCalcSession.hidesArticleShell(phase: .submitting))
        XCTAssertFalse(osrsNativeCalcSession.hidesArticleShell(phase: .fallback))
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let articleView = try String(
            contentsOf: root.appendingPathComponent("osrswiki/Views/ArticleView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(articleView.contains("osrsNativeCalcSession.hidesArticleShell"))
        XCTAssertFalse(articleView.contains(".opacity(showNative ? 0 : 1)"))
        XCTAssertTrue(articleView.contains("osrsNativeCalcSlotOverlay"))
        let view = try String(
            contentsOf: root.appendingPathComponent("osrswiki/Views/osrsNativeCalcView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(view.contains("Picker(input.label"))
        XCTAssertFalse(view.contains("Menu {"))
        XCTAssertTrue(view.contains("osrsNativeCalcDraftField"))
        XCTAssertTrue(view.contains("native-calc-error"))
        XCTAssertFalse(view.contains("listStyle(.insetGrouped)"))
        XCTAssertFalse(view.contains("osrsNativeCalcResultWebView"))
        let runtime = try String(
            contentsOf: root.appendingPathComponent("osrswiki/Assets/web/osrs_calculator_runtime.js"),
            encoding: .utf8
        )
        XCTAssertTrue(runtime.contains("osrsInstallNativeCalcSlot"))
        XCTAssertTrue(runtime.contains("osrs-native-calc-slot"))
        XCTAssertTrue(runtime.contains("osrsNativeCalcSetResult"))
        let script = osrsNativeCalcDefinition.installSlotJavaScript(
            formId: "AgilityCalc",
            resultId: "AgilityResults",
            height: 420
        )
        XCTAssertTrue(script.contains("osrsInstallNativeCalcSlot"))
        XCTAssertTrue(script.contains("AgilityCalc"))
        XCTAssertTrue(script.contains("AgilityResults"))
        let escaped = osrsNativeCalcDefinition.jsonEscape("<td>Plank</td>")
        XCTAssertTrue(escaped.contains("Plank"))
        let resultScript = osrsNativeCalcDefinition.setResultJavaScript(
            resultId: "AgilityResults",
            html: "<table><tr><td>Plank</td></tr></table>"
        )
        XCTAssertTrue(resultScript.contains("osrsNativeCalcSetResult"))
        XCTAssertTrue(resultScript.contains("Plank"))
    }

    @MainActor
    func testNameFieldEditsDoNotPublishOrClearArticleDocuments() throws {
        let session = osrsNativeCalcSession()
        let definition = try XCTUnwrap(osrsNativeCalcDefinition.parse(agilityConfig, title: "Calculator:Agility"))
        session.seedNativeStateForTesting(
            definition: definition,
            values: Dictionary(uniqueKeysWithValues: definition.inputs.map { ($0.name, $0.defaultValue) }),
            resultDocument: "<html>Plank</html>",
            resultHTML: "<td>Plank</td>"
        )
        var publishes = 0
        let cancellable = session.objectWillChange.sink { _ in publishes += 1 }
        session.setValue("name", "osa", submit: false)
        session.setValue("name", "osamo", submit: false)
        XCTAssertEqual(publishes, 0)
        XCTAssertEqual(session.phase, .native)
        XCTAssertEqual(session.resultDocument, "<html>Plank</html>")
        XCTAssertEqual(session.resultHTML, "<td>Plank</td>")
        XCTAssertEqual(session.values["name"], "osamo")
        session.applyLookupResult(
            ok: false,
            body: "",
            player: "osamosis",
            mapping: "XPInput,17,2;lvlInput,17,1"
        )
        XCTAssertEqual(session.phase, .native)
        XCTAssertEqual(session.resultDocument, "<html>Plank</html>")
        XCTAssertEqual(
            session.hiscoresError,
            osrsNativeCalcDefinition.hiscoresUnavailableMessage(player: "osamosis")
        )
        cancellable.cancel()
    }

    @MainActor
    func testInstallSlotHidesLeftoverGadgetChromeBetweenHeadingAndName() async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let runtime = try String(
            contentsOf: root.appendingPathComponent("osrswiki/Assets/web/osrs_calculator_runtime.js"),
            encoding: .utf8
        )
        XCTAssertTrue(runtime.contains("osrs-native-calc-slot-active"))
        XCTAssertTrue(runtime.contains("osrs-native-calc-slot-style"))
        XCTAssertTrue(runtime.contains(".osrs-calculator-panel"))
        XCTAssertTrue(runtime.contains(".oo-ui-textInputWidget"))

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          body { margin: 0; background: #e2dbc8; }
          h2 { margin: 12px 0; }
          .osrs-calculator-panel {
            border: 1px solid #94866d;
            background: #d8ccb4;
            padding: 8px;
            min-height: 40px;
            border-radius: 6px;
          }
          .oo-ui-textInputWidget, input.oo-ui-inputWidget-input {
            display: block;
            width: 100%;
            height: 36px;
            border: 1px solid #94866d;
            background: #e9e3d6;
            border-radius: 6px;
          }
        </style>
        </head>
        <body>
          <div class="mw-parser-output">
            <h2>Calculator</h2>
            <pre class="jcConfig">form=AgilityCalc</pre>
            <div class="osrs-calculator-layout">
              <div class="osrs-calculator-panel">
                <fieldset class="jcTable oo-ui-fieldsetLayout" id="jsForm-AgilityCalc">
                  <div class="jsCalc-field">
                    <div class="oo-ui-textInputWidget leftover-gadget-name">
                      <input class="oo-ui-inputWidget-input" type="text">
                    </div>
                  </div>
                </fieldset>
              </div>
              <div id="AgilityResults" class="osrs-calculator-result"></div>
            </div>
          </div>
        </body>
        </html>
        """

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let window = UIWindow(frame: webView.bounds)
        window.addSubview(webView)
        window.makeKeyAndVisible()
        try await loadHTML(html, in: webView)
        _ = try await webView.evaluateJavaScript(runtime)

        let probe = """
        (function () {
          function vis(sel) {
            var n = document.querySelector(sel);
            if (!n) return { exists: false, visible: false, height: 0, display: '' };
            var cs = window.getComputedStyle(n);
            var r = n.getBoundingClientRect();
            return {
              exists: true,
              visible: cs.display !== 'none' && cs.visibility !== 'hidden' && r.height > 2 && r.width > 2,
              height: r.height,
              display: cs.display,
              border: cs.borderTopWidth
            };
          }
          function visibleGadgetChrome() {
            var slot = document.getElementById('osrs-native-calc-slot');
            var found = [];
            document.querySelectorAll(
              '.osrs-calculator-panel, .jcTable, .jcSubmit, .oo-ui-fieldsetLayout, .oo-ui-textInputWidget, .jsCalc-field, pre.jcConfig, input, select, button'
            ).forEach(function (n) {
              if (!n || n.id === 'osrs-native-calc-slot') return;
              if (slot && (n === slot || (slot.contains && slot.contains(n)))) return;
              if (n.id === 'AgilityResults' || (n.classList && n.classList.contains('osrs-calculator-result'))) return;
              var cs = window.getComputedStyle(n);
              var r = n.getBoundingClientRect();
              if (cs.display === 'none' || cs.visibility === 'hidden') return;
              if (r.height <= 2 || r.width <= 2) return;
              found.push({ tag: n.tagName, id: n.id || '', cls: String(n.className || ''), height: r.height });
            });
            return found;
          }
          window.osrsInstallNativeCalcSlot({
            formId: 'AgilityCalc',
            resultId: 'AgilityResults',
            height: 420
          });
          var layout = document.querySelector('.osrs-calculator-layout');
          var late = document.createElement('div');
          late.className = 'oo-ui-textInputWidget leftover-late';
          late.innerHTML = '<input class="oo-ui-inputWidget-input" type="text">';
          layout.insertBefore(late, layout.firstChild);
          var slot = document.getElementById('osrs-native-calc-slot');
          var slotCs = slot ? window.getComputedStyle(slot) : null;
          return {
            heading: (document.querySelector('h2') || {}).textContent || '',
            leftover: vis('.leftover-gadget-name'),
            panel: vis('.osrs-calculator-panel'),
            late: vis('.leftover-late'),
            jcTable: vis('.jcTable'),
            gadget: visibleGadgetChrome(),
            slotExists: !!slot,
            slotBorder: slotCs ? slotCs.borderTopWidth : '',
            result: vis('#AgilityResults')
          };
        })()
        """

        let raw = try await webView.evaluateJavaScript(probe)
        let payload = try XCTUnwrap(raw as? [String: Any])
        XCTAssertEqual(payload["heading"] as? String, "Calculator")
        XCTAssertEqual(payload["slotExists"] as? Bool, true)
        let leftover = try XCTUnwrap(payload["leftover"] as? [String: Any])
        XCTAssertEqual(leftover["visible"] as? Bool, false, "gadget Name field must not remain between heading and native form")
        let panel = try XCTUnwrap(payload["panel"] as? [String: Any])
        XCTAssertEqual(panel["visible"] as? Bool, false, "empty calculator panel must not paint leftover chrome")
        let late = try XCTUnwrap(payload["late"] as? [String: Any])
        XCTAssertEqual(late["visible"] as? Bool, false, "late gadget paint must stay hidden")
        let jcTable = try XCTUnwrap(payload["jcTable"] as? [String: Any])
        XCTAssertEqual(jcTable["visible"] as? Bool, false)
        let gadget = try XCTUnwrap(payload["gadget"] as? [Any])
        XCTAssertTrue(gadget.isEmpty, "leftover gadget chrome still visible: \(gadget)")
        XCTAssertEqual(payload["slotBorder"] as? String, "0px")
        let result = try XCTUnwrap(payload["result"] as? [String: Any])
        XCTAssertEqual(result["exists"] as? Bool, true)
        window.isHidden = true
    }

    @MainActor
    private func loadHTML(_ html: String, in webView: WKWebView) async throws {
        let ready = expectation(description: "html")
        let delegate = osrsNativeCalcHTMLDelegate(expectation: ready)
        webView.navigationDelegate = delegate
        webView.loadHTMLString(html, baseURL: nil)
        await fulfillment(of: [ready], timeout: 5)
    }
}

private final class osrsNativeCalcHTMLDelegate: NSObject, WKNavigationDelegate {
    let expectation: XCTestExpectation
    init(expectation: XCTestExpectation) {
        self.expectation = expectation
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        expectation.fulfill()
    }
}
