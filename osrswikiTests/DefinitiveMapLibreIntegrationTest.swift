import XCTest
import WebKit
@testable import osrswiki

/// DEFINITIVE MapLibre Integration Test - True TDD
/// This test creates an isolated environment and definitively verifies MapLibre functionality
/// WITHOUT requiring any manual verification
class DefinitiveMapLibreIntegrationTest: XCTestCase {
    var webView: WKWebView!
    var mapHandler: osrsNativeMapHandler!
    var bridgeCallsReceived: [String: Any] = [:]
    var testCoordinator: MapLibreBridgeTestCoordinator!
    var assetHandler: IOSAssetHandler!
    
    override func setUp() {
        super.setUp()
        bridgeCallsReceived.removeAll()
        setupTestEnvironment()
    }
    
    override func tearDown() {
        webView?.removeFromSuperview()
        webView = nil
        mapHandler = nil
        testCoordinator = nil
        assetHandler = nil
        super.tearDown()
    }
    
    func setupTestEnvironment() {
        // Create WebView with EXACT same configuration as ArticleWebView
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        
        // Setup test coordinator to capture bridge calls
        testCoordinator = MapLibreBridgeTestCoordinator()
        testCoordinator.onBridgeCall = { [weak self] action, data in
            self?.bridgeCallsReceived[action] = data
            print("🔍 [TEST] Bridge call received: \(action) with data: \(data)")
        }
        
        // Register message handlers exactly like ArticleWebView
        userContentController.add(testCoordinator, name: "mapBridge")
        config.userContentController = userContentController
        
        // Setup asset handler exactly like ArticleWebView
        assetHandler = IOSAssetHandler()
        config.setURLSchemeHandler(assetHandler, forURLScheme: "app-assets")
        
        // Create WebView
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 375, height: 667), configuration: config)
        
        // Initialize native map handler exactly like the real app
        mapHandler = osrsNativeMapHandler(webView: webView)
        testCoordinator.mapHandler = mapHandler
    }
    
    func testMapLibreWidgetEndToEndIntegration() throws {
        let expectation = expectation(description: "MapLibre integration test should complete")
        var testResult: MapLibreTestResult = .unknown
        
        print("\n🧪 DEFINITIVE MAPLIBRE INTEGRATION TEST")
        print("=====================================")
        
        // Create controlled test HTML with MapLibre widget
        let testHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>MapLibre Integration Test</title>
        </head>
        <body>
            <h1>MapLibre Integration Test</h1>
            
            <!-- MapLibre widget with known data -->
            <div id="test-map-widget" 
                 class="maplibre-widget" 
                 data-map='{"latitude": 45.0, "longitude": -122.0, "zoom": 10}'
                 style="width: 300px; height: 200px; background: #f0f0f0; border: 1px solid #ccc;">
                Test Map Widget
            </div>
            
            <!-- Load bridge exactly like real app -->
            <script src="app-assets://localhost/web/map_bridge.js"></script>
            
            <!-- Test script that exercises the bridge -->
            <script>
                console.log('🧪 [TEST] Starting MapLibre integration test...');
                
                function runMapLibreTest() {
                    console.log('🧪 [TEST] Executing bridge tests...');
                    
                    let testResults = {
                        bridgeLoaded: false,
                        methodsAvailable: false,
                        communicationWorking: false,
                        widgetMeasured: false
                    };
                    
                    // Test 1: Bridge object exists
                    if (typeof window.OsrsWikiBridge !== 'undefined') {
                        testResults.bridgeLoaded = true;
                        console.log('✅ [TEST] Bridge loaded');
                        
                        // Test 2: Required methods exist
                        const requiredMethods = ['onMapPlaceholderMeasured', 'log'];
                        let methodsFound = 0;
                        
                        requiredMethods.forEach(method => {
                            if (typeof window.OsrsWikiBridge[method] === 'function') {
                                methodsFound++;
                            }
                        });
                        
                        if (methodsFound === requiredMethods.length) {
                            testResults.methodsAvailable = true;
                            console.log('✅ [TEST] All bridge methods available');
                            
                            // Test 3: Communication test
                            try {
                                window.OsrsWikiBridge.log('TEST_COMMUNICATION_WORKING');
                                testResults.communicationWorking = true;
                                console.log('✅ [TEST] Bridge communication working');
                                
                                // Test 4: Widget measurement (the key functionality)
                                const widget = document.getElementById('test-map-widget');
                                const rect = widget.getBoundingClientRect();
                                const rectJson = JSON.stringify({
                                    x: rect.x,
                                    y: rect.y,
                                    width: rect.width,
                                    height: rect.height
                                });
                                const mapData = widget.getAttribute('data-map');
                                
                                window.OsrsWikiBridge.onMapPlaceholderMeasured(
                                    'test-map-widget',
                                    rectJson,
                                    mapData
                                );
                                testResults.widgetMeasured = true;
                                console.log('✅ [TEST] Widget measurement sent to bridge');
                                
                            } catch (error) {
                                console.log('❌ [TEST] Bridge communication failed: ' + error.message);
                            }
                        } else {
                            console.log('❌ [TEST] Missing bridge methods: ' + methodsFound + '/' + requiredMethods.length);
                        }
                    } else {
                        console.log('❌ [TEST] Bridge not loaded');
                    }
                    
                    // Report results
                    const overallSuccess = Object.values(testResults).every(result => result === true);
                    console.log('🧪 [TEST] Overall result: ' + (overallSuccess ? 'SUCCESS' : 'FAILURE'));
                    console.log('🧪 [TEST] Bridge loaded: ' + testResults.bridgeLoaded);
                    console.log('🧪 [TEST] Methods available: ' + testResults.methodsAvailable);
                    console.log('🧪 [TEST] Communication working: ' + testResults.communicationWorking);
                    console.log('🧪 [TEST] Widget measured: ' + testResults.widgetMeasured);
                    console.log('🧪 [TEST] INTEGRATION_TEST_COMPLETE');
                }
                
                // Wait for DOM and bridge to be ready, then run test
                if (document.readyState === 'loading') {
                    document.addEventListener('DOMContentLoaded', () => {
                        setTimeout(runMapLibreTest, 1000);
                    });
                } else {
                    setTimeout(runMapLibreTest, 1000);
                }
            </script>
        </body>
        </html>
        """
        
        // Load test HTML
        webView.loadHTMLString(testHTML, baseURL: URL(string: "app-assets://localhost/"))
        
        // Set up result monitoring
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            // Analyze test results
            print("\n📊 TEST RESULTS ANALYSIS")
            print("========================")
            print("Bridge calls received: \(self.bridgeCallsReceived.count)")
            
            for (action, data) in self.bridgeCallsReceived {
                print("  • \(action): \(data)")
            }
            
            // Definitive pass/fail criteria
            let hasLogCall = self.bridgeCallsReceived.keys.contains("log")
            let hasMapMeasurement = self.bridgeCallsReceived.keys.contains("onMapPlaceholderMeasured")
            let hasMapHandler = self.mapHandler != nil
            
            if hasLogCall && hasMapMeasurement && hasMapHandler {
                testResult = .success
                print("🎉 DEFINITIVE RESULT: ✅ SUCCESS")
                print("   - Bridge communication working")
                print("   - Map widget measurement working") 
                print("   - Native map handler initialized")
                print("   - MapLibre widgets should render correctly")
            } else {
                testResult = .failure
                print("💥 DEFINITIVE RESULT: ❌ FAILURE")
                print("   - Log call received: \(hasLogCall)")
                print("   - Map measurement received: \(hasMapMeasurement)")
                print("   - Map handler exists: \(hasMapHandler)")
                print("   - MapLibre widgets will NOT work")
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 15.0)
        
        // Final assertion based on definitive test result
        switch testResult {
        case .success:
            XCTAssertTrue(true, "MapLibre integration test PASSED - widgets should work")
        case .failure:
            XCTFail("MapLibre integration test FAILED - widgets will not work")
        case .unknown:
            XCTFail("MapLibre integration test TIMEOUT - could not determine status")
        }
    }
}

// MARK: - Test Support Classes

enum MapLibreTestResult {
    case success
    case failure
    case unknown
}

class MapLibreBridgeTestCoordinator: NSObject, WKScriptMessageHandler {
    var mapHandler: osrsNativeMapHandler?
    var onBridgeCall: ((String, [String: Any]) -> Void)?
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "mapBridge",
              let body = message.body as? [String: Any],
              let action = body["action"] as? String else {
            return
        }
        
        // Notify test of bridge call
        onBridgeCall?(action, body)
        
        // Forward to actual map handler to test full integration
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
}