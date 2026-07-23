import XCTest
import WebKit
@testable import osrswiki

// Helper delegate to wait for WebView navigation
class TestNavigationDelegate: NSObject, WKNavigationDelegate {
    let expectation: XCTestExpectation
    
    init(expectation: XCTestExpectation) {
        self.expectation = expectation
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        expectation.fulfill()
    }
}

class TableRenderingTests: XCTestCase {
    var webView: WKWebView!
    let loadTimeout: TimeInterval = 10.0
    
    override func setUp() {
        super.setUp()
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = true
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 375, height: 667), configuration: config)
    }
    
    override func tearDown() {
        webView = nil
        super.tearDown()
    }
    
    func testTableDoesNotUseDisplayBlock() async throws {
        let expectation = self.expectation(description: "WebView loaded")
        
        // Load test HTML with a wikitable
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <style>
                .wikitable {
                    font-size: 14px;
                    width: 100%;
                    table-layout: auto;
                }
                .collapsible-content {
                    overflow-x: auto;
                    -webkit-overflow-scrolling: touch;
                }
            </style>
        </head>
        <body>
            <table class="wikitable">
                <tr><th>Firelighters</th><th>Logs</th></tr>
                <tr><td>White firelighter</td><td>White logs</td></tr>
                <tr><td>Red firelighter</td><td>Red logs</td></tr>
            </table>
        </body>
        </html>
        """
        
        // Use navigation delegate to wait for load
        let delegate = TestNavigationDelegate(expectation: expectation)
        webView.navigationDelegate = delegate
        webView.loadHTMLString(html, baseURL: nil)
        
        await fulfillment(of: [expectation], timeout: loadTimeout)
        
        // Check computed styles
        let displayValue = try await webView.evaluateJavaScript("""
            window.getComputedStyle(document.querySelector('.wikitable')).display
        """) as? String
        
        // Table should NOT have display: block
        XCTAssertNotEqual(displayValue, "block", "Table should not use display: block")
        XCTAssertEqual(displayValue, "table", "Table should use display: table")
    }
    
    func testTableFillsWidth() async throws {
        let expectation = self.expectation(description: "WebView loaded")
        
        // Load test HTML with collapsible container
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <style>
                .collapsible-container {
                    width: 100%;
                }
                .collapsible-container .wikitable {
                    width: 100%;
                    table-layout: auto;
                }
            </style>
        </head>
        <body>
            <div class="collapsible-container" style="width: 375px;">
                <table class="wikitable">
                    <tr><th>Firelighters</th><th>Logs</th></tr>
                    <tr><td>White firelighter</td><td>White logs</td></tr>
                </table>
            </div>
        </body>
        </html>
        """
        
        let delegate = TestNavigationDelegate(expectation: expectation)
        webView.navigationDelegate = delegate
        webView.loadHTMLString(html, baseURL: nil)
        
        await fulfillment(of: [expectation], timeout: loadTimeout)
        
        // Check table width
        let result = try await webView.evaluateJavaScript("""
            (function() {
                const container = document.querySelector('.collapsible-container');
                const table = document.querySelector('.wikitable');
                return {
                    containerWidth: container.offsetWidth,
                    tableWidth: table.offsetWidth,
                    tableComputedWidth: window.getComputedStyle(table).width
                };
            })()
        """) as? [String: Any]
        
        let containerWidth = result?["containerWidth"] as? CGFloat ?? 0
        let tableWidth = result?["tableWidth"] as? CGFloat ?? 0
        
        // Table should fill container width
        XCTAssertEqual(tableWidth, containerWidth, accuracy: 1.0, 
                      "Table should fill container width")
    }
    
    func testNoWhiteSpaceNowrap() async throws {
        let expectation = self.expectation(description: "WebView loaded")
        
        // Load test HTML
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <style>
                .wikitable {
                    font-size: 14px;
                    width: 100%;
                    table-layout: auto;
                }
            </style>
        </head>
        <body>
            <table class="wikitable">
                <tr><td>This is a long text that should wrap normally</td></tr>
            </table>
        </body>
        </html>
        """
        
        let delegate = TestNavigationDelegate(expectation: expectation)
        webView.navigationDelegate = delegate
        webView.loadHTMLString(html, baseURL: nil)
        
        await fulfillment(of: [expectation], timeout: loadTimeout)
        
        // Check white-space property
        let whiteSpaceValue = try await webView.evaluateJavaScript("""
            window.getComputedStyle(document.querySelector('.wikitable')).whiteSpace
        """) as? String
        
        // Should not have nowrap
        XCTAssertNotEqual(whiteSpaceValue, "nowrap", 
                         "Table should not have white-space: nowrap")
    }
    
    func testCollapsibleContainerStyling() async throws {
        let expectation = self.expectation(description: "WebView loaded")
        
        // Test that table containers have proper styling - embed the CSS directly
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <style>
                .collapsible-container {
                    width: 100%;
                    background-color: transparent;
                    border-radius: 0;
                }
                .collapsible-container .wikitable {
                    width: 100%;
                    table-layout: auto;
                    margin: 0;
                }
                .collapsible-content {
                    padding: 0;
                }
            </style>
        </head>
        <body>
            <div class="collapsible-container">
                <div class="collapsible-header">
                    <div class="title-wrapper">Table</div>
                </div>
                <div class="collapsible-content">
                    <table class="wikitable">
                        <tr><th>Header</th></tr>
                        <tr><td>Content</td></tr>
                    </table>
                </div>
            </div>
        </body>
        </html>
        """
        
        let delegate = TestNavigationDelegate(expectation: expectation)
        webView.navigationDelegate = delegate
        webView.loadHTMLString(html, baseURL: nil)
        
        await fulfillment(of: [expectation], timeout: loadTimeout)
        
        // Check container styles
        let styles = try await webView.evaluateJavaScript("""
            (function() {
                const container = document.querySelector('.collapsible-container');
                const content = document.querySelector('.collapsible-content');
                const table = document.querySelector('.wikitable');
                const containerComputed = window.getComputedStyle(container);
                const contentComputed = window.getComputedStyle(content);
                const tableComputed = window.getComputedStyle(table);
                return {
                    containerWidth: container.offsetWidth,
                    tableWidth: table.offsetWidth,
                    contentPadding: contentComputed.padding,
                    tableMargin: tableComputed.margin,
                    backgroundColor: containerComputed.backgroundColor
                };
            })()
        """) as? [String: Any]
        
        // Verify styles are applied correctly
        XCTAssertNotNil(styles?["containerWidth"], "Container should have width")
        XCTAssertEqual(styles?["contentPadding"] as? String, "0px", "Content should have no padding for tables")
        XCTAssertEqual(styles?["tableMargin"] as? String, "0px", "Table should have no margin")
    }
}