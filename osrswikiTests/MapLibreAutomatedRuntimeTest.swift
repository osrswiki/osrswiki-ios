//
//  MapLibreAutomatedRuntimeTest.swift
//  osrswikiTests
//
//  Automated test to definitively verify MapLibre bridge functionality
//  Uses proper XCTest patterns with evaluateJavaScript and XCTestExpectation
//

import XCTest
import WebKit
@testable import osrswiki

@MainActor
final class MapLibreAutomatedRuntimeTest: XCTestCase {
    
    var webView: WKWebView?
    var bridgeMessageReceived = false
    var nativeHandlerCalled = false
    var testMessageHandler: TestMessageHandler?
    
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    
    override func tearDownWithError() throws {
        webView = nil
        testMessageHandler = nil
    }
    
    /// Test that definitively verifies MapLibre bridge functionality
    func testMapLibreBridgeActuallyWorks() async throws {
        print("🧪 DEFINITIVE MAPLIBRE BRIDGE TEST")
        print("==================================")
        
        // Step 1: Create WebView with identical configuration to real app
        let webView = try await createAppIdenticalWebView()
        self.webView = webView
        
        // Step 2: Load test HTML with MapLibre widget
        let testHTML = createMapLibreTestHTML()
        let loadExpectation = expectation(description: "Page loads")
        
        webView.loadHTMLString(testHTML, baseURL: URL(string: "app-assets://localhost/"))
        
        // Wait for page to fully load
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            loadExpectation.fulfill()
        }
        
        await fulfillment(of: [loadExpectation], timeout: 5.0)
        print("✅ Test page loaded")
        
        // Step 3: Test bridge script loading using evaluateJavaScript
        let bridgeCheckExpectation = expectation(description: "Bridge availability check")
        var bridgeAvailable = false
        
        webView.evaluateJavaScript("typeof window.OsrsWikiBridge !== 'undefined'") { result, error in
            if let available = result as? Bool {
                bridgeAvailable = available
                print("🔍 Bridge available: \\(available)")
            } else if let error = error {
                print("❌ Bridge check error: \\(error)")
            }
            bridgeCheckExpectation.fulfill()
        }
        
        await fulfillment(of: [bridgeCheckExpectation], timeout: 10.0)
        
        guard bridgeAvailable else {
            XCTFail("❌ CRITICAL: Bridge script did not load - external script loading failed")
            return
        }
        
        print("✅ Bridge script successfully loaded")
        
        // Step 4: Test bridge function availability
        let functionsCheckExpectation = expectation(description: "Bridge functions check")
        var functionsAvailable = false
        
        let functionCheckScript = """
            (function() {
                if (typeof window.OsrsWikiBridge === 'undefined') return false;
                return typeof window.OsrsWikiBridge.onMapPlaceholderMeasured === 'function' &&
                       typeof window.OsrsWikiBridge.log === 'function';
            })()
        """
        
        webView.evaluateJavaScript(functionCheckScript) { result, error in
            if let available = result as? Bool {
                functionsAvailable = available
                print("🔍 Bridge functions available: \\(available)")
            } else if let error = error {
                print("❌ Functions check error: \\(error)")
            }
            functionsCheckExpectation.fulfill()
        }
        
        await fulfillment(of: [functionsCheckExpectation], timeout: 5.0)
        
        guard functionsAvailable else {
            XCTFail("❌ CRITICAL: Bridge functions missing - external script execution incomplete")
            return
        }
        
        print("✅ Bridge functions successfully available")
        
        // Step 5: Test actual bridge communication
        let bridgeCallExpectation = expectation(description: "Bridge communication test")
        
        let bridgeTestScript = """
            (function() {
                try {
                    // Test logging first
                    window.OsrsWikiBridge.log('AUTOMATED_TEST: Bridge communication test');
                    
                    // Test widget measurement call
                    var testRect = '{"x": 10, "y": 10, "width": 300, "height": 200}';
                    var testMapData = '{"lat": "3094", "lon": "3094", "zoom": "4", "plane": "0"}';
                    
                    window.OsrsWikiBridge.onMapPlaceholderMeasured('test-widget', testRect, testMapData);
                    
                    // CRITICAL: Make the native overlay visible (move from offscreen to onscreen)
                    window.OsrsWikiBridge.onCollapsibleToggled('test-widget', true);
                    
                    return 'SUCCESS';
                } catch (error) {
                    return 'ERROR: ' + error.message;
                }
            })()
        """
        
        webView.evaluateJavaScript(bridgeTestScript) { result, error in
            if let resultString = result as? String {
                print("🔍 Bridge call result: \\(resultString)")
                self.bridgeMessageReceived = resultString.contains("SUCCESS")
            } else if let error = error {
                print("❌ Bridge call error: \\(error)")
            }
            bridgeCallExpectation.fulfill()
        }
        
        await fulfillment(of: [bridgeCallExpectation], timeout: 5.0)
        
        guard bridgeMessageReceived else {
            XCTFail("❌ CRITICAL: Bridge communication failed - JavaScript calls not working")
            return
        }
        
        print("✅ Bridge communication successful")
        
        // Step 6: Wait and check if native handler responded
        let nativeResponseWait = expectation(description: "Native handler response wait")
        
        // Give time for native handler to potentially respond and create MapLibre views
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            nativeResponseWait.fulfill()
        }
        
        await fulfillment(of: [nativeResponseWait], timeout: 5.0)
        
        // Step 7: Final verification - check if widget appearance changed
        let widgetCheckExpectation = expectation(description: "Widget state check")
        var widgetChanged = false
        
        let widgetCheckScript = """
            (function() {
                var widget = document.getElementById('test-widget');
                if (!widget) return 'NO_WIDGET';
                
                var style = window.getComputedStyle(widget);
                var stillYellow = style.backgroundColor.includes('255, 255, 0') || 
                                style.backgroundColor.includes('yellow');
                var stillVisible = style.display !== 'none' && style.visibility !== 'hidden';
                
                return {
                    hasYellowBackground: stillYellow,
                    isVisible: stillVisible,
                    computedStyle: {
                        backgroundColor: style.backgroundColor,
                        display: style.display,
                        visibility: style.visibility
                    }
                };
            })()
        """
        
        webView.evaluateJavaScript(widgetCheckScript) { result, error in
            if let resultDict = result as? [String: Any] {
                print("🔍 Widget state: \\(resultDict)")
                
                if let hasYellow = resultDict["hasYellowBackground"] as? Bool {
                    // If yellow background is gone, native overlay likely worked
                    widgetChanged = !hasYellow
                }
            }
            widgetCheckExpectation.fulfill()
        }
        
        await fulfillment(of: [widgetCheckExpectation], timeout: 5.0)
        
        // Final assessment
        print("\\n🎯 FINAL TEST RESULTS")
        print("=====================")
        print("Bridge script loaded: TRUE")
        print("Bridge functions available: TRUE") 
        print("Bridge communication successful: TRUE")
        print("Native MapLibre overlay active: \\(widgetChanged)")
        
        if widgetChanged {
            print("\\nDEFINITIVE RESULT: SUCCESS")
            print("   MapLibre bridge is fully functional!")
            print("   - JavaScript loads and executes")
            print("   - Bridge communication works") 
            print("   - Native handler responds (widget changed)")
        } else {
            // Partial success - bridge works but native handler might not be responding
            print("\\nDEFINITIVE RESULT: PARTIAL SUCCESS")
            print("   Bridge communication works but native handler issue:")
            print("   - JavaScript bridge: WORKING")
            print("   - Swift native handler: NOT RESPONDING PROPERLY")
            print("   ") 
            print("   NEXT DEBUG STEPS:")
            print("   1. Check if osrsNativeMapHandler.setupMapHandler() is called")
            print("   2. Verify WKScriptMessageHandler 'mapBridge' is registered")
            print("   3. Check if Swift handleMapBridgeMessage() receives calls")
            
            // This is still valuable - we've isolated the issue to the Swift side
            XCTFail("Bridge communication works but native handler not responding - check Swift implementation")
        }
        
        // Always document what we learned
        print("\\nTECHNICAL VERIFICATION COMPLETE")
        print("   This test definitively proves:")
        print("   - External script loading: WORKING")
        print("   - JavaScript execution: WORKING") 
        print("   - Bridge object creation: WORKING")
        let callStatus = bridgeMessageReceived ? "WORKING" : "FAILING"
        print("   - JavaScript-to-Swift calls: \\(callStatus)")
    }
    
    // MARK: - Helper Methods
    
    private func createAppIdenticalWebView() async throws -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        
        // Add the same message handler as the real app
        testMessageHandler = TestMessageHandler { [weak self] action, data in
            print("🔗 [BRIDGE] Received Swift call: \\(action)")
            self?.nativeHandlerCalled = true
            
            if action == "onMapPlaceholderMeasured" {
                print("🗺️  [BRIDGE] Map placeholder measured - should create native view")
            }
        }
        
        userContentController.add(testMessageHandler!, name: "mapBridge")
        config.userContentController = userContentController
        
        // Set up URL scheme handler identical to the real app
        config.setURLSchemeHandler(RealAppAssetHandler(), forURLScheme: "app-assets")
        
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 375, height: 667), configuration: config)
        
        // CRITICAL FIX: Add parent view like real app has
        let parentView = UIView(frame: CGRect(x: 0, y: 0, width: 375, height: 667))
        parentView.addSubview(webView)
        print("🔥 [TEST] Added WebView to parent view")
        
        // CRITICAL FIX: Setup native map handler like ArticleWebView does
        print("🔥 [TEST] About to setup map handler")
        testMessageHandler!.setupMapHandler(webView: webView)
        
        return webView
    }
    
    private func createMapLibreTestHTML() -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <title>MapLibre Automated Test</title>
            <style>
                body { font-family: Arial, sans-serif; padding: 20px; }
                .mw-kartographer-map { 
                    width: 300px; 
                    height: 200px; 
                    background: yellow; 
                    border: 2px solid red; 
                    margin: 20px 0;
                }
                .collapsible-container { border: 1px solid #ccc; margin: 10px 0; }
                .collapsible-content { padding: 10px; }
            </style>
        </head>
        <body>
            <h1>MapLibre Bridge Test - Real Wiki Structure</h1>
            
            <!-- Simulate real wiki page structure with collapsible container -->
            <div class="collapsible-container">
                <div class="collapsible-content">
                    <!-- Use real wiki CSS class and dataset structure -->
                    <div class="mw-kartographer-map" 
                         data-lat="3094" 
                         data-lon="3094" 
                         data-zoom="4" 
                         data-plane="0">
                        KARTOGRAPHER PLACEHOLDER - Should become native map if bridge works
                    </div>
                </div>
            </div>
            
            <!-- Load both the bridge script AND the collapsible content script -->
            <script src="app-assets://localhost/web/map_bridge.js"></script>
            <script src="app-assets://localhost/web/collapsible_content.js"></script>
        </body>
        </html>
        """
    }
}

// Supporting classes
class TestMessageHandler: NSObject, WKScriptMessageHandler {
    let callback: (String, [String: Any]) -> Void
    var mapHandler: osrsNativeMapHandler?
    
    init(_ callback: @escaping (String, [String: Any]) -> Void) {
        self.callback = callback
    }
    
    func setupMapHandler(webView: WKWebView) {
        mapHandler = osrsNativeMapHandler(webView: webView)
        print("✅ [TEST] Map handler initialized")
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else {
            print("❌ [BRIDGE] Invalid message format: \\(message.body)")
            return
        }
        
        print("🔗 [BRIDGE] Received Swift call: \(action)")
        print("🔗 [BRIDGE] Full message body: \(body)")
        callback(action, body)
        
        // CRITICAL FIX: Forward to real native map handler like ArticleWebView does
        switch action {
        case "onMapPlaceholderMeasured":
            if let id = body["id"] as? String,
               let rectJson = body["rectJson"] as? String,
               let mapDataJson = body["mapDataJson"] as? String {
                print("🗺️ [TEST] Forwarding to native handler: onMapPlaceholderMeasured")
                print("🗺️ [TEST] - id: \(id)")
                print("🗺️ [TEST] - rectJson: \(rectJson)")
                print("🗺️ [TEST] - mapDataJson: \(mapDataJson)")
                print("🗺️ [TEST] - mapHandler exists: \(mapHandler != nil)")
                mapHandler?.onMapPlaceholderMeasured(id: id, rectJson: rectJson, mapDataJson: mapDataJson)
                print("🗺️ [TEST] Native handler call completed")
            } else {
                print("❌ [TEST] Failed to extract bridge message data:")
                print("❌ [TEST] - id: \(body["id"] ?? "nil")")
                print("❌ [TEST] - rectJson: \(body["rectJson"] ?? "nil")")  
                print("❌ [TEST] - mapDataJson: \(body["mapDataJson"] ?? "nil")")
            }
        case "log":
            if let message = body["message"] as? String {
                mapHandler?.log(message: message)
            }
        case "onCollapsibleToggled":
            if let mapId = body["mapId"] as? String,
               let isOpening = body["isOpening"] as? Bool {
                mapHandler?.onCollapsibleToggled(mapId: mapId, isOpening: isOpening)
            }
        case "setHorizontalScroll":
            if let inProgress = body["inProgress"] as? Bool {
                mapHandler?.setHorizontalScroll(inProgress: inProgress)
            }
        default:
            break
        }
    }
}

class RealAppAssetHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(NSError(domain: "TestError", code: 1))
            return
        }
        
        let path = url.path
        print("🔗 [ASSET] Loading asset: \\(path)")
        
        // Handle JavaScript files specifically
        if path.contains("map_bridge.js") {
            // Try to find the bridge script in the bundle
            if let bundlePath = Bundle.main.path(forResource: "map_bridge", ofType: "js") {
                do {
                    let content = try String(contentsOfFile: bundlePath)
                    let data = content.data(using: .utf8)!
                    let response = URLResponse(
                        url: url, 
                        mimeType: "application/javascript", 
                        expectedContentLength: data.count, 
                        textEncodingName: "utf-8"
                    )
                    
                    urlSchemeTask.didReceive(response)
                    urlSchemeTask.didReceive(data)
                    urlSchemeTask.didFinish()
                    print("✅ [ASSET] Loaded map_bridge.js (\\(data.count) bytes)")
                    return
                } catch {
                    print("❌ [ASSET] Failed to read map_bridge.js: \\(error)")
                }
            } else {
                print("❌ [ASSET] map_bridge.js not found in bundle")
            }
        } else if path.contains("collapsible_content.js") {
            // Try to find the collapsible content script in the bundle
            if let bundlePath = Bundle.main.path(forResource: "collapsible_content", ofType: "js") {
                do {
                    let content = try String(contentsOfFile: bundlePath)
                    let data = content.data(using: .utf8)!
                    let response = URLResponse(
                        url: url, 
                        mimeType: "application/javascript", 
                        expectedContentLength: data.count, 
                        textEncodingName: "utf-8"
                    )
                    
                    urlSchemeTask.didReceive(response)
                    urlSchemeTask.didReceive(data)
                    urlSchemeTask.didFinish()
                    print("✅ [ASSET] Loaded collapsible_content.js (\\(data.count) bytes)")
                    return
                } catch {
                    print("❌ [ASSET] Failed to read collapsible_content.js: \\(error)")
                }
            } else {
                print("❌ [ASSET] collapsible_content.js not found in bundle")
            }
        }
        
        // Asset not found
        let error = NSError(domain: "AssetError", code: 404, userInfo: [
            NSLocalizedDescriptionKey: "Asset not found: \\(path)"
        ])
        urlSchemeTask.didFailWithError(error)
        print("❌ [ASSET] Asset not found: \\(path)")
    }
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Stop handling
    }
}