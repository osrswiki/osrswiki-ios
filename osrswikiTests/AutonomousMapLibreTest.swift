import XCTest
import WebKit
@testable import osrswiki

class AutonomousMapLibreTest: XCTestCase {
    var webView: WKWebView!
    var bridgeMessages: [String: Any] = [:]
    var consoleMessages: [String] = []
    var testCoordinator: TestCoordinator!
    
    override func setUp() {
        super.setUp()
        bridgeMessages.removeAll()
        consoleMessages.removeAll()
    }
    
    override func tearDown() {
        webView?.removeFromSuperview()
        webView = nil
        testCoordinator = nil
        super.tearDown()
    }
    
    func testMapLibreEndToEndAutonomous() throws {
        let expectation = expectation(description: "Autonomous MapLibre test should complete")
        
        // Create WebView configuration exactly like ArticleWebView
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        
        // Create test coordinator that intercepts bridge messages
        testCoordinator = TestCoordinator()
        testCoordinator.bridgeMessageHandler = { [weak self] action, data in
            self?.bridgeMessages[action] = data
        }
        testCoordinator.consoleMessageHandler = { [weak self] message in
            self?.consoleMessages.append(message)
        }
        
        // Register all handlers like ArticleWebView
        userContentController.add(testCoordinator, name: "mapBridge")
        userContentController.add(testCoordinator, name: "testConsole")
        
        // Add console capture script
        let consoleScript = WKUserScript(
            source: """
            (function() {
                const originalLog = console.log;
                const originalError = console.error;
                
                console.log = function(...args) {
                    window.webkit.messageHandlers.testConsole.postMessage({
                        type: 'log',
                        message: args.join(' ')
                    });
                    originalLog.apply(console, args);
                };
                
                console.error = function(...args) {
                    window.webkit.messageHandlers.testConsole.postMessage({
                        type: 'error',
                        message: args.join(' ')
                    });
                    originalError.apply(console, args);
                };
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        userContentController.addUserScript(consoleScript)
        
        config.userContentController = userContentController
        
        // Set up WKURLSchemeHandler exactly like ArticleWebView
        let assetHandler = IOSAssetHandler()
        config.setURLSchemeHandler(assetHandler, forURLScheme: "app-assets")
        
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 375, height: 667), configuration: config)
        
        // Initialize native map handler
        let mapHandler = osrsNativeMapHandler(webView: webView)
        testCoordinator.mapHandler = mapHandler
        
        // Create test HTML that loads and tests the bridge
        let testHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <title>Autonomous MapLibre Test</title>
        </head>
        <body>
            <h1>MapLibre Test</h1>
            <div id="map-widget" class="maplibre-widget" data-map='{"lat": 45.0, "lng": -122.0, "zoom": 10}' 
                 style="width: 300px; height: 200px; background: #ccc;">Map Widget</div>
            
            <script src="app-assets://localhost/web/map_bridge.js"></script>
            <script>
                console.log('🤖 AUTONOMOUS_TEST: Starting...');
                
                function runAutonomousTest() {
                    console.log('🤖 AUTONOMOUS_TEST: Running tests...');
                    let results = {
                        bridgeExists: false,
                        methodsExist: false,
                        webkitAvailable: false,
                        messageHandlerAvailable: false,
                        communicationWorks: false
                    };
                    
                    // Test 1: Bridge object exists
                    if (typeof window.OsrsWikiBridge !== 'undefined') {
                        results.bridgeExists = true;
                        console.log('🤖 AUTONOMOUS_TEST: Bridge object exists ✅');
                    } else {
                        console.log('🤖 AUTONOMOUS_TEST: Bridge object missing ❌');
                        return reportResults(results);
                    }
                    
                    // Test 2: Required methods exist
                    const requiredMethods = ['onMapPlaceholderMeasured', 'onCollapsibleToggled', 'setHorizontalScroll', 'log'];
                    let methodsFound = 0;
                    
                    requiredMethods.forEach(method => {
                        if (typeof window.OsrsWikiBridge[method] === 'function') {
                            methodsFound++;
                        }
                    });
                    
                    if (methodsFound === requiredMethods.length) {
                        results.methodsExist = true;
                        console.log('🤖 AUTONOMOUS_TEST: All methods exist ✅');
                    } else {
                        console.log('🤖 AUTONOMOUS_TEST: Methods missing ❌ Found: ' + methodsFound + '/' + requiredMethods.length);
                    }
                    
                    // Test 3: WebKit availability
                    if (window.webkit && window.webkit.messageHandlers) {
                        results.webkitAvailable = true;
                        console.log('🤖 AUTONOMOUS_TEST: WebKit available ✅');
                        
                        if (window.webkit.messageHandlers.mapBridge) {
                            results.messageHandlerAvailable = true;
                            console.log('🤖 AUTONOMOUS_TEST: MapBridge handler available ✅');
                        } else {
                            console.log('🤖 AUTONOMOUS_TEST: MapBridge handler missing ❌');
                            console.log('🤖 AUTONOMOUS_TEST: Available handlers: ' + Object.keys(window.webkit.messageHandlers).join(', '));
                        }
                    } else {
                        console.log('🤖 AUTONOMOUS_TEST: WebKit not available ❌');
                    }
                    
                    // Test 4: Communication test
                    if (results.bridgeExists && results.messageHandlerAvailable) {
                        try {
                            window.OsrsWikiBridge.log('AUTONOMOUS_TEST_LOG_MESSAGE');
                            console.log('🤖 AUTONOMOUS_TEST: Log communication attempted ✅');
                            
                            // Test map placeholder measurement
                            const widget = document.getElementById('map-widget');
                            const rect = widget.getBoundingClientRect();
                            const rectJson = JSON.stringify({
                                x: rect.x,
                                y: rect.y, 
                                width: rect.width,
                                height: rect.height
                            });
                            const mapData = widget.getAttribute('data-map');
                            
                            window.OsrsWikiBridge.onMapPlaceholderMeasured('test-widget', rectJson, mapData);
                            console.log('🤖 AUTONOMOUS_TEST: Map measurement communication attempted ✅');
                            
                            results.communicationWorks = true;
                        } catch (error) {
                            console.log('🤖 AUTONOMOUS_TEST: Communication failed ❌ ' + error.message);
                        }
                    }
                    
                    reportResults(results);
                }
                
                function reportResults(results) {
                    console.log('🤖 AUTONOMOUS_TEST: Final Results:');
                    console.log('🤖 AUTONOMOUS_TEST: Bridge Exists: ' + results.bridgeExists);
                    console.log('🤖 AUTONOMOUS_TEST: Methods Exist: ' + results.methodsExist);
                    console.log('🤖 AUTONOMOUS_TEST: WebKit Available: ' + results.webkitAvailable);
                    console.log('🤖 AUTONOMOUS_TEST: Message Handler Available: ' + results.messageHandlerAvailable);
                    console.log('🤖 AUTONOMOUS_TEST: Communication Works: ' + results.communicationWorks);
                    
                    const allPassed = Object.values(results).every(r => r === true);
                    console.log('🤖 AUTONOMOUS_TEST: OVERALL: ' + (allPassed ? 'PASS' : 'FAIL'));
                    console.log('🤖 AUTONOMOUS_TEST: COMPLETE');
                }
                
                // Run test after slight delay to ensure everything is loaded
                if (document.readyState === 'loading') {
                    document.addEventListener('DOMContentLoaded', () => setTimeout(runAutonomousTest, 1000));
                } else {
                    setTimeout(runAutonomousTest, 1000);
                }
            </script>
        </body>
        </html>
        """
        
        // Load the test page
        webView.loadHTMLString(testHTML, baseURL: URL(string: "app-assets://localhost/"))
        
        // Wait for test completion
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 15.0)
        
        // Analyze results
        print("\n" + String(repeating: "=", count: 50))
        print("AUTONOMOUS MAPLIBRE TEST RESULTS")
        print(String(repeating: "=", count: 50))
        print("Console messages received: \(consoleMessages.count)")
        print("Bridge messages received: \(bridgeMessages.count)")
        print("")
        
        // Parse console messages for test results
        let testMessages = consoleMessages.filter { $0.contains("🤖 AUTONOMOUS_TEST:") }
        
        print("Test Messages:")
        for (i, message) in testMessages.enumerated() {
            print("[\(i+1)] \(message)")
        }
        print("")
        
        print("Bridge Messages:")
        for (action, data) in bridgeMessages {
            print("Action: \(action), Data: \(data)")
        }
        print(String(repeating: "=", count: 50))
        
        // Make assertions based on autonomous test results
        XCTAssertTrue(consoleMessages.contains { $0.contains("AUTONOMOUS_TEST: Starting") }, 
                     "Test should have started")
        
        XCTAssertTrue(consoleMessages.contains { $0.contains("AUTONOMOUS_TEST: COMPLETE") },
                     "Test should have completed")
        
        let overallResult = consoleMessages.first { $0.contains("AUTONOMOUS_TEST: OVERALL:") }
        XCTAssertNotNil(overallResult, "Should have overall result")
        
        if let result = overallResult {
            XCTAssertTrue(result.contains("PASS"), "Overall test should pass. Result: \(result)")
        }
        
        XCTAssertGreaterThan(bridgeMessages.count, 0, "Should have received bridge messages")
    }
}

// MARK: - Test Coordinator
class TestCoordinator: NSObject, WKScriptMessageHandler {
    var mapHandler: osrsNativeMapHandler?
    var bridgeMessageHandler: ((String, [String: Any]) -> Void)?
    var consoleMessageHandler: ((String) -> Void)?
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "mapBridge":
            if let body = message.body as? [String: Any],
               let action = body["action"] as? String {
                bridgeMessageHandler?(action, body)
                
                // Forward to actual map handler
                switch action {
                case "onMapPlaceholderMeasured":
                    if let id = body["id"] as? String,
                       let rectJson = body["rectJson"] as? String,
                       let mapDataJson = body["mapDataJson"] as? String {
                        mapHandler?.onMapPlaceholderMeasured(id: id, rectJson: rectJson, mapDataJson: mapDataJson)
                    }
                case "log":
                    if let logMessage = body["message"] as? String {
                        mapHandler?.log(message: logMessage)
                    }
                default:
                    break
                }
            }
            
        case "testConsole":
            if let body = message.body as? [String: Any],
               let messageText = body["message"] as? String {
                consoleMessageHandler?(messageText)
            }
            
        default:
            break
        }
    }
}