//
//  SearchFocusLatencyTest.swift
//  osrswikiUITests
//
//  Tests for search bar focus and keyboard appearance latency
//

import XCTest

class SearchFocusLatencyTest: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // Test search focus from Home/News tab
    func testSearchFocusFromHomeTab() {
        // Start on Home tab - News is the default tab
        let homeTab = app.tabBars.buttons.element(boundBy: 0) // First tab is News/Home
        if homeTab.exists && homeTab.isHittable {
            homeTab.tap()
        }
        
        // Wait for home view to load - search bar is a button with the placeholder text
        let searchBar = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Search'")).firstMatch
        XCTAssertTrue(searchBar.waitForExistence(timeout: 3), "Search bar should exist on home page")
        
        // Measure time from tap to keyboard appearance
        let startTime = Date()
        
        // Tap search bar
        searchBar.tap()
        
        // Wait for keyboard to appear
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 1), "Keyboard should appear quickly")
        
        let endTime = Date()
        let elapsedTime = endTime.timeIntervalSince(startTime)
        
        // Verify keyboard appeared quickly (should be under 0.5 seconds)
        XCTAssertLessThan(elapsedTime, 0.5, "Keyboard should appear within 500ms, took \(elapsedTime)s")
        
        // Verify search field is focused
        let searchField = app.textFields.firstMatch
        XCTAssertTrue(searchField.exists, "Search text field should exist")
        XCTAssertEqual(searchField.value as? String, "", "Search field should be empty initially")
    }
    
    // Test search focus from History tab
    func testSearchFocusFromHistoryTab() {
        // Navigate to History tab - it's the second tab (index 1)
        let historyTab = app.tabBars.buttons.element(boundBy: 1)
        XCTAssertTrue(historyTab.waitForExistence(timeout: 2), "History tab should exist")
        if historyTab.isHittable {
            historyTab.tap()
        }
        
        // Wait for history view to load
        let searchBar = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Search'")).firstMatch
        XCTAssertTrue(searchBar.waitForExistence(timeout: 2), "Search bar should exist on history page")
        
        // Measure time from tap to keyboard appearance
        let startTime = Date()
        
        // Tap search bar
        searchBar.tap()
        
        // Wait for keyboard to appear
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 1), "Keyboard should appear quickly")
        
        let endTime = Date()
        let elapsedTime = endTime.timeIntervalSince(startTime)
        
        // Verify keyboard appeared quickly
        XCTAssertLessThan(elapsedTime, 0.5, "Keyboard should appear within 500ms, took \(elapsedTime)s")
    }
    
    // Test direct Search tab focus
    func testSearchTabDirectFocus() {
        // Navigate directly to Search tab - it's the third tab (index 2)
        let searchTab = app.tabBars.buttons.element(boundBy: 2)
        XCTAssertTrue(searchTab.waitForExistence(timeout: 2), "Search tab should exist")
        
        let startTime = Date()
        searchTab.tap()
        
        // Wait for keyboard to appear automatically
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 1), "Keyboard should appear automatically on Search tab")
        
        let endTime = Date()
        let elapsedTime = endTime.timeIntervalSince(startTime)
        
        // Verify keyboard appeared very quickly (should be immediate)
        XCTAssertLessThan(elapsedTime, 0.3, "Keyboard should appear within 300ms on direct tab switch, took \(elapsedTime)s")
        
        // Verify search field is focused
        let searchField = app.textFields.firstMatch
        XCTAssertTrue(searchField.exists, "Search text field should exist and be focused")
    }
    
    // Test keyboard dismissal and re-focus
    func testKeyboardDismissalAndRefocus() {
        // Navigate to Search tab - third tab (index 2)
        let searchTab = app.tabBars.buttons.element(boundBy: 2)
        if searchTab.exists && searchTab.isHittable {
            searchTab.tap()
        }
        
        // Wait for initial keyboard
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 1), "Keyboard should appear initially")
        
        // Type something
        let searchField = app.textFields.firstMatch
        searchField.typeText("test search")
        
        // Dismiss keyboard by tapping elsewhere
        app.tap()
        
        // Verify keyboard dismissed
        XCTAssertFalse(keyboard.exists, "Keyboard should be dismissed")
        
        // Measure re-focus time
        let startTime = Date()
        
        // Tap search field again
        searchField.tap()
        
        // Wait for keyboard to reappear
        XCTAssertTrue(keyboard.waitForExistence(timeout: 0.5), "Keyboard should reappear quickly")
        
        let endTime = Date()
        let elapsedTime = endTime.timeIntervalSince(startTime)
        
        // Verify keyboard reappeared quickly
        XCTAssertLessThan(elapsedTime, 0.3, "Keyboard should reappear within 300ms, took \(elapsedTime)s")
    }
    
    // Test search with actual query
    func testSearchWithQuery() {
        // Navigate to Search tab - third tab (index 2)
        let searchTab = app.tabBars.buttons.element(boundBy: 2)
        if searchTab.exists && searchTab.isHittable {
            searchTab.tap()
        }
        
        // Wait for keyboard
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 1), "Keyboard should appear")
        
        // Type search query
        let searchField = app.textFields.firstMatch
        searchField.typeText("Grand Exchange")
        
        // Submit search by pressing return key
        app.keyboards.buttons["search"].tap()
        
        // Wait for search results
        let firstResult = app.cells.firstMatch
        XCTAssertTrue(firstResult.waitForExistence(timeout: 5), "Search results should appear")
        
        // Verify keyboard stays visible during search
        XCTAssertTrue(keyboard.exists, "Keyboard should remain visible during search")
    }
    
    // Performance test for repeated focus
    func testRepeatedSearchFocusPerformance() {
        measure {
            // Navigate to Home tab - first tab (index 0)
            let homeTab = app.tabBars.buttons.element(boundBy: 0)
            if homeTab.exists && homeTab.isHittable {
                homeTab.tap()
            }
            
            // Tap search bar
            let searchBar = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Search'")).firstMatch
            _ = searchBar.waitForExistence(timeout: 1)
            if searchBar.isHittable {
                searchBar.tap()
            }
            
            // Wait for keyboard
            let keyboard = app.keyboards.firstMatch
            _ = keyboard.waitForExistence(timeout: 1)
            
            // Dismiss by going back
            app.navigationBars.buttons.firstMatch.tap()
            
            // Wait for keyboard to disappear
            _ = keyboard.waitForNonExistence(timeout: 1)
        }
    }
    
    // Helper to wait for element to not exist
    private func waitForNonExistence(of element: XCUIElement, timeout: TimeInterval = 1) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}

// Extension to help with keyboard detection
extension XCUIElement {
    func waitForNonExistence(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}