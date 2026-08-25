import UIKit
import XCTest

/// Article Find, Agility Name, and article→search must not collapse to a
/// uniform unresponsive fill. One suite so all three entries run together.
final class osrsArticleFirstResponderBlankUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testArticleSearchKeyboardKeepsPaintedHittableChrome() throws {
        launchArticle(title: "Varrock", path: "Varrock")
        XCTAssertTrue(identifiedArticleWebView().waitForExistence(timeout: 25), app.debugDescription)
        waitUntilSurfacePainted("loaded article")

        let launcher = app.buttons["article_search_launcher"]
        XCTAssertTrue(launcher.waitForExistence(timeout: 10), "Article search launcher missing")
        launcher.tap()

        let input = app.textFields["search_input"]
        XCTAssertTrue(input.waitForExistence(timeout: 8), "article→search must show search_input\n\(app.debugDescription)")
        let back = app.buttons["search_back_button"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), "article→search must keep search_back_button")
        if !input.isHittable {
            input.tap()
        }
        try requireSoftwareKeyboard("article→search")
        XCTAssertTrue(app.textFields["search_input"].isHittable, "search_input must stay hittable with keyboard up")
        XCTAssertTrue(app.buttons["search_back_button"].isHittable, "search_back_button must stay hittable with keyboard up")
        waitUntilSurfacePainted("article→search keyboard")
        saveScratchScreenshot("search-keyboard.png")
        attachScreenshot("search-keyboard")
    }

    func testArticleFindKeepsPaintedIdentifiedWebView() throws {
        launchArticle(title: "Varrock", path: "Varrock")
        XCTAssertTrue(identifiedArticleWebView().waitForExistence(timeout: 25), app.debugDescription)
        assertIdentifiedArticleWebViewUsable("loaded")
        waitUntilSurfacePainted("loaded before Find")

        let findButton = waitForArticleFindButton()
        findButton.tap()
        let field = app.searchFields["find.searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 8), "Find search field missing")
        try requireSoftwareKeyboard("Find")
        assertIdentifiedArticleWebViewUsable("after Find tap")
        waitUntilSurfacePainted("Find present")
        saveScratchScreenshot("find.png")
        attachScreenshot("find")
    }

    func testAgilityNameKeyboardKeepsPaintedArticle() throws {
        launchArticle(title: "Calculator:Agility", path: "Calculator:Agility")
        XCTAssertTrue(
            identifiedArticleWebView().waitForExistence(timeout: 35) ||
                app.webViews.firstMatch.waitForExistence(timeout: 2),
            app.debugDescription
        )
        let namedById = app.textFields["native-calc-field-name"].firstMatch
        let namedByPlaceholder = app.textFields["Name"].firstMatch
        let nameField = namedById.exists ? namedById : namedByPlaceholder
        var appeared = namedById.waitForExistence(timeout: 35) || namedByPlaceholder.waitForExistence(timeout: 2)
        if !appeared {
            let webView = identifiedArticleWebView().exists ? identifiedArticleWebView() : app.webViews.firstMatch
            for _ in 0..<10 {
                webView.swipeUp()
                if nameField.waitForExistence(timeout: 2) {
                    appeared = true
                    break
                }
            }
        }
        XCTAssertTrue(appeared, "Native Name field missing on Calculator:Agility. \(app.debugDescription)")
        let webView = identifiedArticleWebView().exists ? identifiedArticleWebView() : app.webViews.firstMatch
        for _ in 0..<8 where !nameField.isHittable {
            webView.swipeUp()
        }
        tapNameFieldWithoutOpeningSearch(nameField)
        if app.textFields["search_input"].waitForExistence(timeout: 1) {
            app.buttons["search_back_button"].tap()
            XCTAssertTrue(identifiedArticleWebView().waitForExistence(timeout: 8), "Back from accidental search must restore Agility")
            for _ in 0..<8 where !nameField.isHittable {
                webView.swipeUp()
            }
            tapNameFieldWithoutOpeningSearch(nameField)
        }
        try requireSoftwareKeyboard("Agility Name")
        XCTAssertFalse(
            app.textFields["search_input"].exists && app.buttons["search_back_button"].exists,
            "Tapping Name must stay on Calculator:Agility, not article→search"
        )
        let nameStillPresent = app.textFields["native-calc-field-name"].firstMatch.exists
            || app.textFields["Name"].firstMatch.exists
            || app.webViews.textFields["Name"].firstMatch.exists
            || app.buttons["native-calc-lookup"].firstMatch.exists
            || app.buttons["Lookup"].firstMatch.exists
            || app.staticTexts["Calculator"].firstMatch.exists
        XCTAssertTrue(
            nameStillPresent,
            "Agility Name chrome vanished after keyboard. \(app.debugDescription)"
        )
        XCTAssertTrue(
            identifiedArticleWebView().exists || app.webViews.firstMatch.exists,
            "Article web view vanished while Name keyboard is up"
        )
        waitUntilSurfacePainted("Agility Name keyboard")
        saveScratchScreenshot("agility-name.png")
        attachScreenshot("agility-name")
    }

    private func launchArticle(title: String, path: String) {
        app.launchArguments = [
            "-osrsUITestHarness",
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-resetReaderPreferencesForUITests",
            "-allowProxyStartupDuringTests",
            "-startTab", "search",
            "-startArticleTitle", title,
            "-startArticleURL", "https://oldschool.runescape.wiki/w/\(path)"
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
    }

    private func tapNameFieldWithoutOpeningSearch(_ nameField: XCUIElement) {
        if nameField.exists {
            nameField.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    private func requireSoftwareKeyboard(_ moment: String) throws {
        let keyboard = app.keyboards.firstMatch
        if keyboard.waitForExistence(timeout: 8) {
            return
        }
        throw XCTSkip("\(moment): software keyboard did not appear. Connect Hardware Keyboard must be off.")
    }

    private func identifiedArticleWebView() -> XCUIElement {
        app.webViews["article_web_view"]
    }

    private func waitForArticleFindButton() -> XCUIElement {
        let identified = app.buttons["article_find_button"]
        if identified.waitForExistence(timeout: 4) {
            return identified
        }
        let labeled = app.buttons.matching(NSPredicate(format: "label == %@", "Find"))
        XCTAssertTrue(labeled.firstMatch.waitForExistence(timeout: 8), "Bottom-bar Find must appear")
        let matches = labeled.allElementsBoundByIndex
        return matches.max(by: { $0.frame.minY < $1.frame.minY }) ?? labeled.firstMatch
    }

    private func assertIdentifiedArticleWebViewUsable(_ moment: String) {
        let webView = identifiedArticleWebView()
        XCTAssertTrue(webView.exists, "\(moment): article_web_view missing")
        XCTAssertGreaterThan(webView.frame.width, 1, "\(moment): width=\(webView.frame.width)")
        XCTAssertGreaterThan(webView.frame.height, 1, "\(moment): height=\(webView.frame.height)")
    }

    private func waitUntilSurfacePainted(_ moment: String) {
        let deadline = Date().addingTimeInterval(12)
        var lastRange = 0
        var lastSample = CGRect.zero
        while Date() < deadline {
            let sample = paintSampleRect()
            lastSample = sample
            if sample.width > 40, sample.height > 40 {
                lastRange = luminanceRange(croppedImage(app.screenshot().image, to: sample))
                if lastRange > 16 {
                    return
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTFail("\(moment): surface is uniform fill (luminance range=\(lastRange) sample=\(lastSample))")
    }

    private func paintSampleRect() -> CGRect {
        let window = app.windows.firstMatch.frame
        var minY = window.minY + 80
        var maxY = window.maxY - 24
        let back = app.buttons["article_back_button"].exists
            ? app.buttons["article_back_button"]
            : app.buttons["search_back_button"]
        if back.exists {
            minY = max(minY, back.frame.maxY + 8)
        }
        if app.keyboards.firstMatch.exists {
            maxY = min(maxY, app.keyboards.firstMatch.frame.minY - 8)
        }
        let findField = app.searchFields["find.searchField"]
        if findField.exists {
            maxY = min(maxY, findField.frame.minY - 8)
        }
        let web = identifiedArticleWebView()
        let minX: CGFloat
        let width: CGFloat
        if web.exists, web.frame.width > 40 {
            minX = web.frame.minX + 12
            width = max(web.frame.width - 24, 1)
            minY = max(minY, web.frame.minY + 8)
            maxY = min(maxY, web.frame.maxY - 8)
        } else {
            minX = window.minX + 16
            width = max(window.width - 32, 1)
        }
        return CGRect(x: minX, y: minY, width: width, height: max(maxY - minY, 1))
    }

    private func croppedImage(_ image: UIImage, to rect: CGRect) -> UIImage {
        let scale = image.scale
        let pixel = CGRect(
            x: rect.minX * scale,
            y: rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        ).integral
        guard let cg = image.cgImage, let cropped = cg.cropping(to: pixel) else {
            return image
        }
        return UIImage(cgImage: cropped, scale: scale, orientation: image.imageOrientation)
    }

    private func luminanceRange(_ image: UIImage) -> Int {
        let sample = CGSize(width: 16, height: 16)
        UIGraphicsBeginImageContextWithOptions(sample, true, 1)
        defer { UIGraphicsEndImageContext() }
        image.draw(in: CGRect(origin: .zero, size: sample))
        guard let tiny = UIGraphicsGetImageFromCurrentImageContext()?.cgImage,
              let data = tiny.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return 0
        }
        let count = tiny.width * tiny.height
        guard count > 0 else { return 0 }
        var minLuminance = 255
        var maxLuminance = 0
        for index in 0..<count {
            let offset = index * 4
            let luminance = (Int(bytes[offset]) + Int(bytes[offset + 1]) + Int(bytes[offset + 2])) / 3
            minLuminance = min(minLuminance, luminance)
            maxLuminance = max(maxLuminance, luminance)
        }
        return maxLuminance - minLuminance
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func saveScratchScreenshot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["OSRS_BLANK_EVIDENCE_DIR"], !dir.isEmpty else {
            return
        }
        let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
        try? app.screenshot().image.pngData()?.write(to: url)
    }
}
