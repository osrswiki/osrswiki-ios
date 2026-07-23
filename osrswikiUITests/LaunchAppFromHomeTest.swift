import XCTest

final class LaunchAppFromHomeTest: XCTestCase {
    
    func testLaunchAppFromHome() throws {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.activate()
        
        // Wait for springboard to load
        sleep(2)
        
        // Find and tap the OSRS Wiki app icon
        let osrsWikiIcon = springboard.icons["OSRS Wiki"]
        if osrsWikiIcon.exists {
            osrsWikiIcon.tap()
            print("Successfully tapped OSRS Wiki icon")
        } else {
            // Try alternative approach
            let osrsIcon = springboard.icons.containing(NSPredicate(format: "label CONTAINS 'OSRS'")).firstMatch
            if osrsIcon.exists {
                osrsIcon.tap()
                print("Successfully tapped OSRS icon")
            }
        }
        
        // Wait for app to launch
        sleep(5)
    }
}
