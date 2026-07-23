import XCTest
import WebKit
@testable import osrswiki

class MapLibreBridgeQuantitativeTest: XCTestCase {
    var webView: WKWebView!
    var bridgeMessageCount = 0
    var receivedMessages: [String: Any] = [:]
    var testExpectation: XCTestExpectation?
    
    override func setUp() {
        super.setUp()
        bridgeMessageCount = 0
        receivedMessages.removeAll()
    }
    
    override func tearDown() {
        webView?.removeFromSuperview()
        webView = nil
        super.tearDown()
    }
    
    func testMapLibreBridgeInitialization() throws {
        testExpectation = expectation(description: "MapLibre bridge should initialize and be callable")
        
        // Create the same WebView configuration as ArticleWebView
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        
        // Register message handler to capture bridge messages
        userContentController.add(self, name: "mapBridge")
        config.userContentController = userContentController
        
        // Set up asset handler (same as ArticleWebView)
        let assetHandler = IOSAssetHandler()
        config.setURLSchemeHandler(assetHandler, forURLScheme: "app-assets")
        
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 375, height: 667), configuration: config)
        
        // Load HTML that includes the map_bridge.js file
        let testHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>MapLibre Bridge Test</title>
        </head>
        <body>
            <div id="test-output"></div>
            <script src="app-assets://localhost/web/map_bridge.js"></script>
            <script>
                // Test script to verify bridge functionality
                window.addEventListener('load', function() {
                    const output = document.getElementById('test-output');
                    let testResults = [];
                    
                    // Test 1: Check if OsrsWikiBridge exists
                    if (typeof window.OsrsWikiBridge !== 'undefined') {
                        testResults.push('PASS: OsrsWikiBridge object exists');
                    } else {
                        testResults.push('FAIL: OsrsWikiBridge object missing');
                        output.innerHTML = testResults.join('<br>');
                        return;
                    }
                    
                    // Test 2: Check if required methods exist
                    const requiredMethods = ['onMapPlaceholderMeasured', 'onCollapsibleToggled', 'setHorizontalScroll', 'log'];
                    let allMethodsExist = true;
                    
                    requiredMethods.forEach(method => {
                        if (typeof window.OsrsWikiBridge[method] === 'function') {
                            testResults.push('PASS: Method ' + method + ' exists');
                        } else {
                            testResults.push('FAIL: Method ' + method + ' missing');
                            allMethodsExist = false;
                        }
                    });
                    
                    if (!allMethodsExist) {
                        output.innerHTML = testResults.join('<br>');
                        return;
                    }
                    
                    // Test 3: Test bridge communication
                    try {
                        window.OsrsWikiBridge.log('BRIDGE_TEST_MESSAGE');
                        testResults.push('PASS: Bridge communication attempted');
                    } catch (error) {
                        testResults.push('FAIL: Bridge communication failed - ' + error.message);
                    }
                    
                    // Test 4: Test complex method call
                    try {
                        window.OsrsWikiBridge.onMapPlaceholderMeasured(
                            'test-map-id', 
                            '{"x": 10, "y": 20, "width": 300, "height": 200}',
                            '{"latitude": 45.0, "longitude": -122.0, "zoom": 10}'
                        );
                        testResults.push('PASS: Complex method call attempted');
                    } catch (error) {
                        testResults.push('FAIL: Complex method call failed - ' + error.message);
                    }
                    
                    output.innerHTML = testResults.join('<br>');
                });
            </script>
        </body>
        </html>
        """
        
        webView.loadHTMLString(testHTML, baseURL: URL(string: "app-assets://localhost/"))
        
        // Wait for the test to complete
        wait(for: [testExpectation!], timeout: 10.0)
        
        // Verify we received bridge messages
        XCTAssertGreaterThan(bridgeMessageCount, 0, "Should have received at least one bridge message")
        XCTAssertTrue(receivedMessages.keys.contains("log"), "Should have received log message")
        XCTAssertTrue(receivedMessages.keys.contains("onMapPlaceholderMeasured"), "Should have received map placeholder message")
    }
    
    func testAssetLoading() throws {
        testExpectation = expectation(description: "map_bridge.js should load successfully")
        
        let config = WKWebViewConfiguration()
        let assetHandler = IOSAssetHandler()
        config.setURLSchemeHandler(assetHandler, forURLScheme: "app-assets")
        
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 375, height: 667), configuration: config)
        
        let testHTML = """
        <!DOCTYPE html>
        <html>
        <head><title>Asset Loading Test</title></head>
        <body>
            <div id="status">Loading...</div>
            <script>
                // Test if we can load the bridge file
                const script = document.createElement('script');
                script.src = 'app-assets://localhost/web/map_bridge.js';
                script.onload = function() {
                    document.getElementById('status').textContent = 'ASSET_LOADED';
                };
                script.onerror = function() {
                    document.getElementById('status').textContent = 'ASSET_FAILED';
                };
                document.head.appendChild(script);
            </script>
        </body>
        </html>
        """
        
        webView.loadHTMLString(testHTML, baseURL: URL(string: "app-assets://localhost/"))
        
        // Check result after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.webView.evaluateJavaScript("document.getElementById('status').textContent") { result, error in
                if let status = result as? String {
                    XCTAssertEqual(status, "ASSET_LOADED", "map_bridge.js should load successfully")
                } else {
                    XCTFail("Could not determine asset loading status")
                }
                self.testExpectation?.fulfill()
            }
        }
        
        wait(for: [testExpectation!], timeout: 10.0)
    }
    
    func testNativeMapHandlerInitialization() throws {
        // Test that we can create the native map handler
        let testWebView = WKWebView(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        let mapHandler = osrsNativeMapHandler(webView: testWebView)
        
        XCTAssertNotNil(mapHandler, "Native map handler should initialize")
        
        // Test that handler responds to method calls without crashing
        XCTAssertNoThrow(mapHandler.log(message: "Test message"))
        XCTAssertNoThrow(mapHandler.setHorizontalScroll(inProgress: true))
    }
    
    func testEndToEndMapLibrePipeline() throws {
        testExpectation = expectation(description: "Complete MapLibre pipeline should work")
        
        // Create ArticleWebView configuration
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        
        // Set up all handlers like ArticleWebView does
        userContentController.add(self, name: "mapBridge")
        config.userContentController = userContentController
        
        let assetHandler = IOSAssetHandler()
        config.setURLSchemeHandler(assetHandler, forURLScheme: "app-assets")
        
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 375, height: 667), configuration: config)
        
        // Initialize map handler like ArticleWebView does
        let mapHandler = osrsNativeMapHandler(webView: webView)
        
        // Load test page that simulates real MapLibre widget
        let testHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <title>End-to-End MapLibre Test</title>
        </head>
        <body>
            <div class="maplibre-widget" id="test-map" data-map='{"latitude": 45.0, "longitude": -122.0, "zoom": 10}'>
                Map placeholder
            </div>
            
            <script src="app-assets://localhost/web/map_bridge.js"></script>
            <script>
                window.addEventListener('load', function() {
                    // Simulate what the real MapLibre initialization would do
                    setTimeout(function() {
                        if (window.OsrsWikiBridge && window.OsrsWikiBridge.onMapPlaceholderMeasured) {
                            const mapElement = document.getElementById('test-map');
                            const rect = mapElement.getBoundingClientRect();
                            const rectJson = JSON.stringify({
                                x: rect.x,
                                y: rect.y,
                                width: rect.width,
                                height: rect.height
                            });
                            const mapData = mapElement.getAttribute('data-map');
                            
                            // This should trigger the native map handler
                            window.OsrsWikiBridge.onMapPlaceholderMeasured('test-map', rectJson, mapData);
                            window.OsrsWikiBridge.log('END_TO_END_TEST_COMPLETE');
                        }
                    }, 2000);
                });
            </script>
        </body>
        </html>
        """
        
        webView.loadHTMLString(testHTML, baseURL: URL(string: "app-assets://localhost/"))
        
        wait(for: [testExpectation!], timeout: 15.0)
        
        // Verify the complete pipeline worked
        XCTAssertGreaterThan(bridgeMessageCount, 1, "Should have received multiple bridge messages")
        XCTAssertTrue(receivedMessages.keys.contains("onMapPlaceholderMeasured"), "Should have processed map placeholder measurement")
        XCTAssertTrue(receivedMessages.keys.contains("log"), "Should have received completion log")
    }
}

// MARK: - WKScriptMessageHandler
extension MapLibreBridgeQuantitativeTest: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "mapBridge",
              let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }
        
        bridgeMessageCount += 1
        receivedMessages[action] = body
        
        print("✅ Received bridge message: \(action)")
        
        // Fulfill expectation after receiving messages
        if bridgeMessageCount >= 2 || action == "log" {
            testExpectation?.fulfill()
        }
    }
}