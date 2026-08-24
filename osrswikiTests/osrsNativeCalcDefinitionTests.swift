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
}
