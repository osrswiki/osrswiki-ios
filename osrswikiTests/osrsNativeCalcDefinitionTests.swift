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
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let articleView = try String(
            contentsOf: root.appendingPathComponent("osrswiki/Views/ArticleView.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(articleView.contains("osrsNativeCalcSession"))
        XCTAssertFalse(articleView.contains("osrsNativeCalcSlotOverlay"))
        XCTAssertFalse(articleView.contains("osrsNativeCalcView"))
        let runtime = try String(
            contentsOf: root.appendingPathComponent("osrswiki/Assets/web/osrs_calculator_runtime.js"),
            encoding: .utf8
        )
        XCTAssertTrue(runtime.contains("osrsInstallNativeCalcSlot"))
        XCTAssertTrue(runtime.contains("osrsBootIndocCalc"))
        XCTAssertTrue(runtime.contains("osrs-native-calc-slot"))
        XCTAssertTrue(runtime.contains("osrsNativeCalcSetResult"))
        XCTAssertTrue(runtime.contains("osrsWrapCollapsible"))
        XCTAssertTrue(runtime.contains("osrsWrapWikitablesInRoot"))
        let collapsible = try String(
            contentsOf: root.appendingPathComponent("osrswiki/Assets/web/collapsible_content.js"),
            encoding: .utf8
        )
        XCTAssertTrue(collapsible.contains("window.osrsWrapCollapsible"))
        XCTAssertTrue(collapsible.contains("kind === 'calculator'"))
        XCTAssertTrue(collapsible.contains("allowInsideCalculator"))
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
        let indoc = try String(
            contentsOf: root.appendingPathComponent("osrswiki/Assets/web/osrs_native_calc_indoc.js"),
            encoding: .utf8
        )
        XCTAssertTrue(indoc.contains("osrs-indoc-calc-form"))
        XCTAssertTrue(indoc.contains("Calculator:Agility"))
        XCTAssertTrue(indoc.contains("Calculator:Combat level"))
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
        XCTAssertTrue(runtime.contains("collapsible-calculator"))
        XCTAssertTrue(runtime.contains("osrsWrapNativeCalcCalculatorBox"))
        XCTAssertTrue(runtime.contains("osrsNativeCalcSetCollapsed"))
        XCTAssertTrue(runtime.contains("osrsNotifyNativeCalcCollapsed"))
        XCTAssertTrue(runtime.contains("osrsWrapCollapsible"))

        let collapsible = try String(
            contentsOf: root.appendingPathComponent("osrswiki/Assets/web/collapsible_content.js"),
            encoding: .utf8
        )
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
        _ = try await webView.evaluateJavaScript("window.OSRS_TABLE_COLLAPSED = false;")
        _ = try await webView.evaluateJavaScript(collapsible)
        _ = try await webView.evaluateJavaScript(runtime)
        _ = try await webView.evaluateJavaScript("window.OSRSInitializeCollapsibleContent && window.OSRSInitializeCollapsibleContent();")

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
          var box = slot && slot.closest && slot.closest('.collapsible-calculator');
          var body = box && box.querySelector('.osrs-disclosure-body');
          var bodyCs = body ? window.getComputedStyle(body) : null;
          window.osrsNativeCalcSetCollapsed && window.osrsNativeCalcSetCollapsed(true);
          var collapsedHeight = slot ? slot.getBoundingClientRect().height : -1;
          window.osrsNativeCalcSetCollapsed && window.osrsNativeCalcSetCollapsed(false);
          return {
            heading: (document.querySelector('h2') || {}).textContent || '',
            leftover: vis('.leftover-gadget-name'),
            panel: vis('.osrs-calculator-panel'),
            late: vis('.leftover-late'),
            jcTable: vis('.jcTable'),
            gadget: visibleGadgetChrome(),
            slotExists: !!slot,
            slotBorder: slotCs ? slotCs.borderTopWidth : '',
            result: vis('#AgilityResults'),
            category: box ? (box.getAttribute('data-osrs-disclosure-kind') || '') : '',
            boxClass: box ? String(box.className || '') : '',
            overflowX: bodyCs ? bodyCs.overflowX : '',
            collapsedHidesSlot: collapsedHeight <= 1,
            isCollapsedFn: window.osrsNativeCalcIsCollapsed ? window.osrsNativeCalcIsCollapsed() : null
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
        XCTAssertEqual(payload["category"] as? String, "calculator")
        XCTAssertTrue(((payload["boxClass"] as? String) ?? "").contains("collapsible-calculator"))
        XCTAssertEqual(payload["overflowX"] as? String, "visible")
        XCTAssertEqual(payload["collapsedHidesSlot"] as? Bool, true)
        XCTAssertEqual(payload["isCollapsedFn"] as? Bool, false)
        window.isHidden = true
    }

    @MainActor
    func testAgilitySelectLabelsRenderFromJcConfig() throws {
        let definition = try XCTUnwrap(osrsNativeCalcDefinition.parse(agilityConfig, title: "Calculator:Agility"))
        let labels = definition.inputs.filter { $0.type == .select }.map(\.label)
        XCTAssertEqual(
            labels,
            [
                "Current: Level or Experience",
                "Goal: Level or Experience?",
                "Method"
            ]
        )
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let indoc = try String(
            contentsOf: root.appendingPathComponent("osrswiki/Assets/web/osrs_native_calc_indoc.js"),
            encoding: .utf8
        )
        XCTAssertTrue(indoc.contains("osrs-indoc-calc-form"))
        XCTAssertTrue(indoc.contains("aria-label"))
        let runtime = try String(
            contentsOf: root.appendingPathComponent("osrswiki/Assets/web/osrs_calculator_runtime.js"),
            encoding: .utf8
        )
        XCTAssertTrue(runtime.contains("showChoicePicker"))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("osrswiki/Views/osrsNativeCalcView.swift").path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("osrswiki/Views/osrsNativeCalcSlotOverlay.swift").path
            )
        )
    }

    func testIndocEnterKeyHintIsGoOnHiscoresAndDoneOnOtherFields() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let indoc = try String(
            contentsOf: root.appendingPathComponent("osrswiki/Assets/web/osrs_native_calc_indoc.js"),
            encoding: .utf8
        )
        XCTAssertTrue(indoc.contains("input.type === 'hs' ? 'go' : 'done'"))
        XCTAssertTrue(indoc.contains("enterkeyhint=\"done\""))
        XCTAssertTrue(indoc.contains("data-osrs-indoc-type"))
        let runtime = try String(
            contentsOf: root.appendingPathComponent("osrswiki/Assets/web/osrs_calculator_runtime.js"),
            encoding: .utf8
        )
        let bind = runtime.components(separatedBy: "function bind() {").dropFirst().first ?? ""
        let keydown = bind.components(separatedBy: "form.addEventListener('click'").first ?? ""
        XCTAssertTrue(keydown.contains("isIndocEnterKey"))
        XCTAssertTrue(keydown.contains("keydown"))
        XCTAssertTrue(keydown.contains("fieldTypeFor(target.name) === 'hs'"))
        XCTAssertTrue(keydown.contains("lookupHiscores()"))
        XCTAssertTrue(keydown.contains("dismissIndocKeyboard"))
        XCTAssertTrue(keydown.contains("preventDefault"))
        XCTAssertTrue(keydown.contains("isIndocTextOrNumberField"))
        XCTAssertFalse(keydown.contains("data-osrs-indoc-step"))
        XCTAssertTrue(runtime.contains("existingHint !== 'go' && existingHint !== 'search'"))
    }

    @MainActor
    func testCalculatorCollapsibleMatchesArticleDisclosureChromeAndToggle() async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let collapsible = try String(
            contentsOf: root.appendingPathComponent("osrswiki/Assets/web/collapsible_content.js"),
            encoding: .utf8
        )
        let runtime = try String(
            contentsOf: root.appendingPathComponent("osrswiki/Assets/web/osrs_calculator_runtime.js"),
            encoding: .utf8
        )
        XCTAssertTrue(collapsible.contains("window.osrsWrapCollapsible"))
        XCTAssertTrue(runtime.contains("osrsWrapCollapsible"))

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let window = UIWindow(frame: webView.bounds)
        window.addSubview(webView)
        window.makeKeyAndVisible()
        try await loadHTML(disclosureFixtureHTML(), in: webView)
        _ = try await webView.evaluateJavaScript("window.OSRS_TABLE_COLLAPSED = false;")
        _ = try await webView.evaluateJavaScript(collapsible)
        _ = try await webView.evaluateJavaScript(runtime)
        _ = try await webView.evaluateJavaScript("window.OSRSInitializeCollapsibleContent && window.OSRSInitializeCollapsibleContent();")

        let probe = """
        (function () {
          function boxInfo(sel) {
            var box = document.querySelector(sel);
            if (!box) return null;
            var header = box.querySelector(':scope > .collapsible-header');
            var label = header && header.querySelector('.collapsible-label');
            var state = header && header.querySelector('.collapsible-state');
            var body = box.querySelector(':scope > .collapsible-content > .osrs-disclosure-body');
            var content = box.querySelector(':scope > .collapsible-content');
            var br = box.getBoundingClientRect();
            var bodyCs = body ? window.getComputedStyle(body) : null;
            return {
              classes: String(box.className || ''),
              kind: box.getAttribute('data-osrs-disclosure-kind') || '',
              hasHeader: !!(header && header.classList.contains('collapsible-header')),
              hasLabel: !!(label && label.classList.contains('collapsible-label')),
              hasState: !!(state && state.classList.contains('collapsible-state')),
              hasBody: !!(body && body.classList.contains('osrs-disclosure-body')),
              label: label ? String(label.textContent || '') : '',
              state: state ? String(state.textContent || '') : '',
              left: br.left,
              width: br.width,
              inset: bodyCs ? bodyCs.marginLeft : '',
              contentHeight: content ? content.getBoundingClientRect().height : -1,
              collapsed: box.classList.contains('collapsed'),
              viewport: document.documentElement.clientWidth || window.innerWidth || 0
            };
          }
          window.osrsInstallNativeCalcSlot({
            formId: 'AgilityCalc',
            resultId: 'AgilityResults',
            height: 220
          });
          var article = boxInfo('.collapsible-wikitable');
          var calc = boxInfo('.collapsible-calculator');
          var header = document.querySelector('.collapsible-calculator > .collapsible-header');
          if (header) header.click();
          var afterCollapse = boxInfo('.collapsible-calculator');
          if (header) header.click();
          var afterExpand = boxInfo('.collapsible-calculator');
          var slot = document.getElementById('osrs-native-calc-slot');
          var expandedBox = document.querySelector('.collapsible-calculator');
          return {
            article: article,
            calc: calc,
            afterCollapse: afterCollapse,
            afterExpand: afterExpand,
            slotVisibleAfterExpand: !!(
              slot &&
              expandedBox &&
              expandedBox.contains(slot) &&
              !expandedBox.classList.contains('collapsed')
            ),
            wrapFn: typeof window.osrsWrapCollapsible,
            toggleFn: typeof window.osrsToggleCollapsible
          };
        })()
        """
        let raw = try await webView.evaluateJavaScript(probe)
        let payload = try XCTUnwrap(raw as? [String: Any])
        writeScratchJSON(payload, name: "calc-collapsible-probe.json")
        XCTAssertEqual(payload["wrapFn"] as? String, "function")
        let article = try XCTUnwrap(payload["article"] as? [String: Any])
        let calc = try XCTUnwrap(payload["calc"] as? [String: Any])
        XCTAssertEqual(article["hasHeader"] as? Bool, true)
        XCTAssertEqual(article["hasLabel"] as? Bool, true)
        XCTAssertEqual(article["hasState"] as? Bool, true)
        XCTAssertEqual(article["hasBody"] as? Bool, true)
        XCTAssertEqual(calc["hasHeader"] as? Bool, true)
        XCTAssertEqual(calc["hasLabel"] as? Bool, true)
        XCTAssertEqual(calc["hasState"] as? Bool, true)
        XCTAssertEqual(calc["hasBody"] as? Bool, true)
        XCTAssertEqual(calc["kind"] as? String, "calculator")
        XCTAssertEqual(calc["label"] as? String, "Calculator")
        XCTAssertTrue(((calc["classes"] as? String) ?? "").contains("collapsible-container"))
        XCTAssertTrue(((calc["classes"] as? String) ?? "").contains("collapsible-calculator"))
        let articleWidth = (article["width"] as? NSNumber)?.doubleValue ?? -1
        let calcWidth = (calc["width"] as? NSNumber)?.doubleValue ?? -1
        let articleLeft = (article["left"] as? NSNumber)?.doubleValue ?? -1
        let calcLeft = (calc["left"] as? NSNumber)?.doubleValue ?? -1
        let viewport = (calc["viewport"] as? NSNumber)?.doubleValue ?? 390
        XCTAssertGreaterThan(articleWidth, 0)
        XCTAssertEqual(articleWidth, calcWidth, accuracy: 2)
        XCTAssertEqual(articleLeft, calcLeft, accuracy: 2)
        XCTAssertLessThan(calcWidth, viewport - 8, "calc box must use article inset, not full-bleed")
        XCTAssertEqual(article["inset"] as? String, calc["inset"] as? String)
        let afterCollapse = try XCTUnwrap(payload["afterCollapse"] as? [String: Any])
        XCTAssertEqual(afterCollapse["collapsed"] as? Bool, true)
        let collapsedHeight = (afterCollapse["contentHeight"] as? NSNumber)?.doubleValue ?? 99
        XCTAssertLessThanOrEqual(collapsedHeight, 1)
        XCTAssertEqual(afterCollapse["state"] as? String, "Tap to expand")
        let afterExpand = try XCTUnwrap(payload["afterExpand"] as? [String: Any])
        XCTAssertEqual(afterExpand["collapsed"] as? Bool, false)
        let expandedHeight = (afterExpand["contentHeight"] as? NSNumber)?.doubleValue ?? 0
        XCTAssertGreaterThan(expandedHeight, 0)
        XCTAssertEqual(payload["slotVisibleAfterExpand"] as? Bool, true)
        window.isHidden = true
    }

    @MainActor
    func testContentColumnWidthIgnoresNestedCollapsibleInsideCalculatorBox() async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let runtime = try String(
            contentsOf: root.appendingPathComponent("osrswiki/Assets/web/osrs_calculator_runtime.js"),
            encoding: .utf8
        )
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 420, height: 844))
        let window = UIWindow(frame: webView.bounds)
        window.addSubview(webView)
        window.makeKeyAndVisible()
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          html, body { margin: 0; }
          .mw-parser-output { width: 420px; padding: 16px; box-sizing: border-box; }
          .collapsible-calculator { padding: 25px; box-sizing: border-box; }
          .collapsible-wikitable { width: 100%; height: 24px; box-sizing: border-box; background: #ccc; }
        </style>
        </head>
        <body>
          <div class="mw-parser-output">
            <p>Notes</p>
            <div id="box" class="collapsible-container collapsible-calculator">
              <div id="nested" class="collapsible-container collapsible-wikitable primary-collapsible"></div>
            </div>
          </div>
        </body>
        </html>
        """
        try await loadHTML(html, in: webView)
        _ = try await webView.evaluateJavaScript(runtime)
        let probe = """
        (function () {
          var box = document.getElementById('box');
          var nested = document.getElementById('nested');
          var widths = [];
          for (var i = 0; i < 9; i++) {
            widths.push(window.osrsNativeCalcContentColumnWidth(box));
            window.osrsNativeCalcApplyContentColumnWidth(box);
          }
          var output = document.querySelector('.mw-parser-output');
          var cs = window.getComputedStyle(output);
          var parserInner = (output.clientWidth || 0)
            - (parseFloat(cs.paddingLeft) || 0)
            - (parseFloat(cs.paddingRight) || 0);
          return {
            nestedInside: !!(box && box.contains(nested)),
            widths: widths,
            parserInner: Math.round(parserInner)
          };
        })()
        """
        let raw = try await webView.evaluateJavaScript(probe)
        let payload = try XCTUnwrap(raw as? [String: Any])
        XCTAssertEqual(payload["nestedInside"] as? Bool, true)
        let widths = try XCTUnwrap(payload["widths"] as? [NSNumber]).map { $0.doubleValue }
        XCTAssertEqual(widths.count, 9)
        let unique = Set(widths.map { Int($0.rounded()) })
        XCTAssertEqual(
            unique.count,
            1,
            "cold-cache nested wikitable must not staircase the column: \(widths)"
        )
        let parserInner = (payload["parserInner"] as? NSNumber)?.doubleValue ?? -1
        XCTAssertEqual(widths[0], parserInner, accuracy: 2)
        XCTAssertGreaterThan(parserInner, 300)
        window.isHidden = true
    }

    @MainActor
    func testCalculatorCollapsibleUsesContentColumnWidthOnFirstPaintBelowFold() async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let collapsible = try String(
            contentsOf: root.appendingPathComponent("osrswiki/Assets/web/collapsible_content.js"),
            encoding: .utf8
        )
        let runtime = try String(
            contentsOf: root.appendingPathComponent("osrswiki/Assets/web/osrs_calculator_runtime.js"),
            encoding: .utf8
        )
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let window = UIWindow(frame: webView.bounds)
        window.addSubview(webView)
        window.makeKeyAndVisible()
        try await loadHTML(belowFoldDisclosureFixtureHTML(), in: webView)
        _ = try await webView.evaluateJavaScript("window.OSRS_TABLE_COLLAPSED = false;")
        _ = try await webView.evaluateJavaScript(collapsible)
        _ = try await webView.evaluateJavaScript(runtime)
        _ = try await webView.evaluateJavaScript("window.OSRSInitializeCollapsibleContent && window.OSRSInitializeCollapsibleContent();")

        let probe = """
        (function () {
          function boxInfo(sel) {
            var box = document.querySelector(sel);
            if (!box) return null;
            var br = box.getBoundingClientRect();
            var slot = document.getElementById('osrs-native-calc-slot');
            var slotBr = slot ? slot.getBoundingClientRect() : null;
            return {
              left: br.left,
              width: br.width,
              top: br.top,
              documentTop: br.top + (window.scrollY || document.documentElement.scrollTop || 0),
              collapsed: box.classList.contains('collapsed'),
              slotWidth: slotBr ? slotBr.width : 0,
              slotLeft: slotBr ? slotBr.left : 0
            };
          }
          window.scrollTo(0, 0);
          window.osrsInstallNativeCalcSlot({
            formId: 'AgilityCalc',
            resultId: 'AgilityResults',
            height: 220
          });
          var viewport = document.documentElement.clientWidth || window.innerWidth || 0;
          var viewportHeight = window.innerHeight || 844;
          var atRest = {
            scrollY: window.scrollY || document.documentElement.scrollTop || 0,
            article: boxInfo('.collapsible-wikitable'),
            calc: boxInfo('.collapsible-calculator'),
            viewport: viewport,
            viewportHeight: viewportHeight
          };
          var calcEl = document.querySelector('.collapsible-calculator');
          if (calcEl && calcEl.scrollIntoView) {
            calcEl.scrollIntoView({ block: 'start', inline: 'nearest' });
          }
          var afterScroll = {
            scrollY: window.scrollY || document.documentElement.scrollTop || 0,
            article: boxInfo('.collapsible-wikitable'),
            calc: boxInfo('.collapsible-calculator'),
            viewport: viewport
          };
          return { atRest: atRest, afterScroll: afterScroll };
        })()
        """
        let raw = try await webView.evaluateJavaScript(probe)
        let payload = try XCTUnwrap(raw as? [String: Any])
        writeScratchJSON(payload, name: "calc-first-paint-width.json")
        let atRest = try XCTUnwrap(payload["atRest"] as? [String: Any])
        let afterScroll = try XCTUnwrap(payload["afterScroll"] as? [String: Any])
        let restScroll = (atRest["scrollY"] as? NSNumber)?.doubleValue ?? -1
        XCTAssertEqual(restScroll, 0, accuracy: 1, "first paint must be measured at scrollY=0")
        let article = try XCTUnwrap(atRest["article"] as? [String: Any])
        let calc = try XCTUnwrap(atRest["calc"] as? [String: Any])
        let articleWidth = (article["width"] as? NSNumber)?.doubleValue ?? -1
        let calcWidth = (calc["width"] as? NSNumber)?.doubleValue ?? -1
        let articleLeft = (article["left"] as? NSNumber)?.doubleValue ?? -1
        let calcLeft = (calc["left"] as? NSNumber)?.doubleValue ?? -1
        let viewport = (atRest["viewport"] as? NSNumber)?.doubleValue ?? 390
        let viewportHeight = (atRest["viewportHeight"] as? NSNumber)?.doubleValue ?? 844
        let calcDocumentTop = (calc["documentTop"] as? NSNumber)?.doubleValue ?? 0
        XCTAssertGreaterThan(articleWidth, 200, "article collapsible must occupy the content column")
        XCTAssertGreaterThan(calcDocumentTop, viewportHeight, "calc must start below the first viewport")
        XCTAssertEqual(articleWidth, calcWidth, accuracy: 4)
        XCTAssertEqual(articleLeft, calcLeft, accuracy: 4)
        XCTAssertLessThan(calcWidth, viewport - 8, "calc box must use article inset, not full-bleed")
        XCTAssertGreaterThan(calcWidth, viewport * 0.7, "calc box must not be a leftover much smaller than the column")
        let afterCalc = try XCTUnwrap(afterScroll["calc"] as? [String: Any])
        let afterWidth = (afterCalc["width"] as? NSNumber)?.doubleValue ?? -1
        XCTAssertEqual(calcWidth, afterWidth, accuracy: 4, "width must not jump after intersection/scroll")
        XCTAssertTrue(runtime.contains("osrsNativeCalcContentColumnWidth"))
        XCTAssertTrue(runtime.contains("osrsNativeCalcApplyContentColumnWidth"))
        XCTAssertTrue(
            runtime.contains("box.contains"),
            "column measure must skip nested collapsibles inside the calculator box"
        )
        window.isHidden = true
    }

    @MainActor
    func testSetResultWrapsTablesAsArticleCollapsiblesInsideCalcBox() async throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let collapsible = try String(
            contentsOf: root.appendingPathComponent("osrswiki/Assets/web/collapsible_content.js"),
            encoding: .utf8
        )
        let runtime = try String(
            contentsOf: root.appendingPathComponent("osrswiki/Assets/web/osrs_calculator_runtime.js"),
            encoding: .utf8
        )
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let window = UIWindow(frame: webView.bounds)
        window.addSubview(webView)
        window.makeKeyAndVisible()
        try await loadHTML(disclosureFixtureHTML(), in: webView)
        _ = try await webView.evaluateJavaScript("window.OSRS_TABLE_COLLAPSED = false;")
        _ = try await webView.evaluateJavaScript(collapsible)
        _ = try await webView.evaluateJavaScript(runtime)
        _ = try await webView.evaluateJavaScript("window.OSRSInitializeCollapsibleContent && window.OSRSInitializeCollapsibleContent();")

        let probe = """
        (function () {
          window.osrsInstallNativeCalcSlot({
            formId: 'AgilityCalc',
            resultId: 'AgilityResults',
            height: 180
          });
          window.osrsNativeCalcSetResult('AgilityResults',
            '<table class="wikitable"><caption>Methods</caption><tr><td>Plank</td></tr></table>' +
            '<table class="wikitable"><caption>Rates</caption><tr><td>Low wall</td></tr></table>'
          );
          var calc = document.querySelector('.collapsible-calculator');
          var body = calc && calc.querySelector(':scope > .collapsible-content > .osrs-disclosure-body');
          var result = document.getElementById('AgilityResults');
          var nested = result ? Array.prototype.map.call(
            result.querySelectorAll(':scope > .collapsible-container'),
            function (box) {
              return {
                kind: box.getAttribute('data-osrs-disclosure-kind') || '',
                classes: String(box.className || ''),
                hasHeader: !!box.querySelector(':scope > .collapsible-header'),
                hasBody: !!box.querySelector('.osrs-disclosure-body'),
                tableKind: box.classList.contains('collapsible-wikitable')
              };
            }
          ) : [];
          var nestedHeader = result && result.querySelector('.collapsible-container > .collapsible-header');
          var parentBefore = calc && calc.classList.contains('collapsed');
          if (nestedHeader) nestedHeader.click();
          var parentAfterNested = calc && calc.classList.contains('collapsed');
          if (nestedHeader) nestedHeader.click();
          return {
            resultInBody: !!(body && result && body.contains(result)),
            nestedCount: nested.length,
            nested: nested,
            parentCollapsedBefore: parentBefore,
            parentCollapsedAfterNestedToggle: parentAfterNested,
            parentStillPresent: !!document.querySelector('.collapsible-calculator')
          };
        })()
        """
        let raw = try await webView.evaluateJavaScript(probe)
        let payload = try XCTUnwrap(raw as? [String: Any])
        writeScratchJSON(payload, name: "calc-result-tables.json")
        XCTAssertEqual(payload["resultInBody"] as? Bool, true)
        XCTAssertEqual((payload["nestedCount"] as? NSNumber)?.intValue, 2)
        let nested = try XCTUnwrap(payload["nested"] as? [[String: Any]])
        XCTAssertEqual(nested.count, 2)
        for box in nested {
            XCTAssertEqual(box["hasHeader"] as? Bool, true)
            XCTAssertEqual(box["hasBody"] as? Bool, true)
            XCTAssertEqual(box["tableKind"] as? Bool, true)
            XCTAssertTrue(((box["classes"] as? String) ?? "").contains("collapsible-container"))
        }
        XCTAssertEqual(payload["parentCollapsedBefore"] as? Bool, false)
        XCTAssertEqual(payload["parentCollapsedAfterNestedToggle"] as? Bool, false)
        XCTAssertEqual(payload["parentStillPresent"] as? Bool, true)
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

    private func writeScratchJSON(_ payload: Any, name: String) {
        let scratch = ProcessInfo.processInfo.environment["OSRS_SCRATCH"]
            ?? "/var/folders/vt/gqrlflhj10b1g04_6pcq_q3r0000gn/T/grok-goal-b3bd04458c83/implementer"
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys]
              ) else { return }
        try? data.write(to: URL(fileURLWithPath: scratch).appendingPathComponent(name))
    }

    private func disclosureFixtureHTML() -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          :root { --osrs-disclosure-content-inline-inset: 12px; --osrs-disclosure-chrome-bg: #d8ccb4; }
          body { margin: 0; background: #e2dbc8; }
          .mw-parser-output { padding: 12px; }
          .collapsible-container { background-color: var(--osrs-disclosure-chrome-bg); box-sizing: border-box; }
          .collapsible-header { display: flex; padding: 12px; }
          .collapsible-label { font-weight: 600; }
          .collapsible-state { margin-left: 8px; }
          .collapsible-container.collapsed > .collapsible-content {
            height: 0; max-height: 0; min-height: 0; overflow: hidden; padding: 0; margin: 0;
          }
          .collapsible-container:not(.collapsed) > .collapsible-content > .osrs-disclosure-body {
            margin-inline: var(--osrs-disclosure-content-inline-inset);
            overflow-x: auto;
          }
          table.wikitable { width: 100%; border: 1px solid #94866d; }
        </style>
        </head>
        <body>
          <div class="mw-parser-output">
            <table class="wikitable">
              <caption>Drops</caption>
              <tr><th>Item</th><td>Coins</td></tr>
            </table>
            <h2>Calculator</h2>
            <pre class="jcConfig">form=AgilityCalc result=AgilityResults</pre>
            <div class="osrs-calculator-layout">
              <div class="osrs-calculator-panel">
                <fieldset class="jcTable oo-ui-fieldsetLayout" id="jsForm-AgilityCalc"></fieldset>
              </div>
              <div id="AgilityResults" class="osrs-calculator-result"></div>
            </div>
          </div>
        </body>
        </html>
        """
    }

    private func belowFoldDisclosureFixtureHTML() -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          :root { --osrs-disclosure-content-inline-inset: 12px; --osrs-disclosure-chrome-bg: #d8ccb4; }
          body { margin: 0; background: #e2dbc8; }
          .mw-parser-output { padding: 12px; box-sizing: border-box; }
          .collapsible-container { background-color: var(--osrs-disclosure-chrome-bg); box-sizing: border-box; }
          .collapsible-header { display: flex; padding: 12px; }
          .collapsible-label { font-weight: 600; }
          .collapsible-state { margin-left: 8px; }
          .collapsible-container.collapsed > .collapsible-content {
            height: 0; max-height: 0; min-height: 0; overflow: hidden; padding: 0; margin: 0;
          }
          .collapsible-container:not(.collapsed) > .collapsible-content > .osrs-disclosure-body {
            margin-inline: var(--osrs-disclosure-content-inline-inset);
            overflow-x: auto;
          }
          table.wikitable { width: 100%; border: 1px solid #94866d; }
          .below-fold-spacer { height: 1400px; }
          .osrs-calculator-layout {
            display: block;
            width: 96px;
            max-width: 96px;
          }
          .leftover-gadget {
            width: 96px;
            height: 32px;
            background: #d8ccb4;
          }
        </style>
        </head>
        <body>
          <div class="mw-parser-output">
            <table class="wikitable">
              <caption>Drops</caption>
              <tr><th>Item</th><td>Coins</td></tr>
            </table>
            <div class="below-fold-spacer"></div>
            <h2>Calculator</h2>
            <pre class="jcConfig">form=AgilityCalc result=AgilityResults</pre>
            <div class="osrs-calculator-layout">
              <div class="leftover-gadget osrs-calculator-panel">gadget leftover</div>
              <div class="osrs-calculator-panel">
                <fieldset class="jcTable oo-ui-fieldsetLayout" id="jsForm-AgilityCalc"></fieldset>
              </div>
              <div id="AgilityResults" class="osrs-calculator-result"></div>
            </div>
          </div>
        </body>
        </html>
        """
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
