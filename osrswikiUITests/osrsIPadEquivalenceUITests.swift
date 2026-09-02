import UIKit
import XCTest

/// iPad-regular-width article open must paint a real wiki body, not empty
/// parchment under article chrome. Same suite also covers Search / chrome /
/// Map / More / Donate on whatever idiom the destination is.
final class osrsIPadEquivalenceUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testHomeFeaturedOnThisDayAndPopularEachOpenPaintedArticle() throws {
        launchHome()
        XCTAssertTrue(element("home_screen").waitForExistence(timeout: 12), app.debugDescription)
        waitForHomeFeed()

        openHomeTarget(
            named: "featured card",
            target: app.descendants(matching: .any)["home_update_card"].firstMatch
        )
        assertPaintedArticle(named: "home featured card")
        navigateBackToHome()

        openHomeTarget(
            named: "On This Day row",
            target: app.descendants(matching: .any)["home_on_this_day_event"].firstMatch
        )
        assertPaintedArticle(named: "home On This Day")
        navigateBackToHome()

        openHomeTarget(
            named: "Popular Pages row",
            target: app.descendants(matching: .any)["home_popular_page"].firstMatch
        )
        assertPaintedArticle(named: "home Popular Pages")
    }

    func testSearchOpensPaintedArticle() throws {
        launchDirectArticle(title: "Varrock", path: "Varrock", startTab: "search")
        assertPaintedArticle(named: "search Varrock")
    }

    func testArticleChromeSaveFindAppearanceContentsAndBack() throws {
        launchDirectArticle(title: "Varrock", path: "Varrock")
        assertPaintedArticle(named: "chrome start")

        let save = app.buttons["article_save_button"]
        XCTAssertTrue(save.waitForExistence(timeout: 8), "Save must exist")
        XCTAssertTrue(save.isHittable, "Save must be hittable on this idiom")
        save.tap()

        let find = app.buttons["article_find_button"]
        XCTAssertTrue(find.waitForExistence(timeout: 6))
        find.tap()
        let findField = app.searchFields["find.searchField"]
        if findField.waitForExistence(timeout: 6) {
            let done = app.buttons["find.doneButton"].exists
                ? app.buttons["find.doneButton"]
                : app.buttons["Done"]
            if done.waitForExistence(timeout: 4) {
                done.tap()
            } else {
                app.buttons["article_back_button"].tap()
            }
        }

        XCTAssertTrue(app.webViews["article_web_view"].waitForExistence(timeout: 8))
        let appearance = app.buttons["article_appearance_button"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 6))
        appearance.tap()
        let appearanceDone = app.buttons["Done"].firstMatch
        if appearanceDone.waitForExistence(timeout: 6) {
            appearanceDone.tap()
        }

        let contents = app.buttons["article_contents_button"]
        XCTAssertTrue(contents.waitForExistence(timeout: 6))
        contents.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        if app.buttons["article_back_button"].isHittable {
            app.buttons["article_back_button"].tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
        }
        assertPaintedArticle(named: "after chrome")

        let back = app.buttons["article_back_button"]
        XCTAssertTrue(back.waitForExistence(timeout: 4))
        back.tap()
        XCTAssertTrue(
            element("home_screen").waitForExistence(timeout: 8) ||
                element("search_screen").waitForExistence(timeout: 2),
            "Back from article must return to a root tab\n\(app.debugDescription)"
        )
    }

    func testMapPanZoomStaysOnMapThenMoreDonateAreReachable() throws {
        launch(startTab: "map")
        XCTAssertTrue(element("map_screen").waitForExistence(timeout: 12), app.debugDescription)
        let map = element("map_screen")
        map.swipeLeft()
        map.swipeRight()
        map.pinch(withScale: 1.15, velocity: 1.0)
        XCTAssertFalse(app.webViews["article_web_view"].exists, "Map gestures must not open an article")

        tapTab("more_tab", fallbackLabel: "More")
        XCTAssertTrue(app.buttons["more_donate"].waitForExistence(timeout: 8), app.debugDescription)
        app.buttons["more_donate"].tap()
        XCTAssertTrue(element("donate_screen").waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertTrue(app.staticTexts["donate_header"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["donate_submit"].exists)
        XCTAssertFalse(app.webViews["article_web_view"].exists)
        attachScreenshot("donate-ui")
    }

    func testDirectArticleLaunchPaintsOnCurrentIdiom() throws {
        launchDirectArticle(title: "Varrock", path: "Varrock")
        assertPaintedArticle(named: "direct \(currentIdiomName())")
    }

    func testSavedSeededArticleOpensPainted() throws {
        launch(
            startTab: "saved",
            extra: [
                "-resetSavedPagesForUITests",
                "-seedSavedPagesForUITests",
                "-seedOfflineSavedPageForUITests"
            ]
        )
        let title = app.staticTexts["Varrock"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "Seeded saved Varrock missing\n\(app.debugDescription)")
        title.tap()
        assertPaintedArticle(named: "saved Varrock")
    }

    private func currentIdiomName() -> String {
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    }

    private func launchHome() {
        launch(startTab: "news")
    }

    private func launchDirectArticle(title: String, path: String, startTab: String = "news") {
        launch(
            startTab: startTab,
            extra: [
                "-startArticleTitle", title,
                "-startArticleURL", "https://oldschool.runescape.wiki/w/\(path)"
            ]
        )
    }

    private func launch(startTab: String, extra: [String] = []) {
        app.launchArguments = [
            "-screenshotMode",
            "-disableBackgroundPreloading",
            "-disableSearchAutofocusForUITests",
            "-allowProxyStartupDuringTests",
            "-startTab",
            startTab
        ] + extra
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 12))
    }

    private func waitForHomeFeed() {
        let card = app.descendants(matching: .any)["home_update_card"].firstMatch
        let popular = app.descendants(matching: .any)["home_popular_pages_section"].firstMatch
        XCTAssertTrue(
            card.waitForExistence(timeout: 25) || popular.waitForExistence(timeout: 5),
            "Home feed did not load\n\(app.debugDescription)"
        )
    }

    private func openHomeTarget(named: String, target: XCUIElement) {
        XCTAssertTrue(target.waitForExistence(timeout: 20), "\(named) missing\n\(app.debugDescription)")
        reveal(target)
        XCTAssertTrue(target.isHittable || target.exists, "\(named) not tappable")
        target.tap()
    }

    private func reveal(_ element: XCUIElement) {
        let feed = app.scrollViews["home_feed_scroll"].exists
            ? app.scrollViews["home_feed_scroll"]
            : app.scrollViews.firstMatch
        var attempts = 0
        while !element.isHittable, attempts < 8 {
            feed.swipeUp()
            attempts += 1
        }
    }

    private func navigateBackToHome() {
        let back = app.buttons["article_back_button"]
        XCTAssertTrue(back.waitForExistence(timeout: 8), "article back missing")
        back.tap()
        XCTAssertTrue(element("home_screen").waitForExistence(timeout: 10), app.debugDescription)
        waitForHomeFeed()
    }

    private func assertPaintedArticle(named moment: String) {
        let webView = app.webViews["article_web_view"]
        XCTAssertTrue(webView.waitForExistence(timeout: 30), "\(moment): article_web_view missing\n\(app.debugDescription)")
        XCTAssertGreaterThan(webView.frame.width, 80, "\(moment): width=\(webView.frame.width)")
        XCTAssertGreaterThan(webView.frame.height, 80, "\(moment): height=\(webView.frame.height)")
        XCTAssertFalse(app.staticTexts["Failed to Load Page"].exists, "\(moment): load failed")
        waitUntilArticlePainted(moment)
        attachScreenshot(moment)
    }

    private func waitUntilArticlePainted(_ moment: String) {
        let deadline = Date().addingTimeInterval(20)
        var lastRange = 0
        var lastFrame = CGRect.zero
        while Date() < deadline {
            let webView = app.webViews["article_web_view"]
            if webView.exists {
                lastFrame = webView.frame
                if webView.frame.width > 80, webView.frame.height > 80 {
                    let sample = paintSampleRect()
                    if sample.width > 40, sample.height > 40 {
                        lastRange = luminanceRange(croppedImage(app.screenshot().image, to: sample))
                        if lastRange > 16 {
                            return
                        }
                    }
                    if app.staticTexts["Varrock"].exists
                        || app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Old School")).firstMatch.exists {
                        return
                    }
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        }
        XCTFail("\(moment): article body is empty parchment (range=\(lastRange) frame=\(lastFrame))")
    }

    private func paintSampleRect() -> CGRect {
        let window = app.windows.firstMatch.frame
        var minY = window.minY + 90
        var maxY = window.maxY - 90
        let back = app.buttons["article_back_button"]
        if back.exists {
            minY = max(minY, back.frame.maxY + 8)
        }
        let bar = app.otherElements["article_bottom_bar"]
        if bar.exists {
            maxY = min(maxY, bar.frame.minY - 8)
        }
        let web = app.webViews["article_web_view"]
        if web.exists, web.frame.width > 40 {
            minY = max(minY, web.frame.minY + 12)
            maxY = min(maxY, web.frame.maxY - 12)
            return CGRect(
                x: web.frame.minX + 16,
                y: minY,
                width: max(web.frame.width - 32, 1),
                height: max(maxY - minY, 1)
            )
        }
        return CGRect(x: window.minX + 16, y: minY, width: max(window.width - 32, 1), height: max(maxY - minY, 1))
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

    private func tapTab(_ identifier: String, fallbackLabel: String) {
        // iPadOS 26 floating tab items nest Button-inside-Button with the same
        // identifier; tap the first match instead of the ambiguous query.
        let identified = app.buttons.matching(identifier: identifier).firstMatch
        if identified.waitForExistence(timeout: 4) {
            identified.tap()
            return
        }
        let labeled = app.buttons.matching(NSPredicate(format: "label == %@", fallbackLabel)).firstMatch
        XCTAssertTrue(labeled.waitForExistence(timeout: 6), "\(identifier) missing")
        labeled.tap()
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
