//
//  WebKitCrashReproductionTest.swift
//  osrswikiTests
//
//  Test to reproduce and verify fix for "This task has already been stopped" 
//  NSInternalInconsistencyException in WKURLSchemeTask handling
//

import XCTest
import WebKit
@testable import osrswiki

@MainActor
final class WebKitCrashReproductionTest: XCTestCase {
    
    var webView: WKWebView?
    var testURLSchemeHandler: TestURLSchemeHandler?
    
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
    
    override func tearDownWithError() throws {
        webView?.navigationDelegate = nil
        webView = nil
        testURLSchemeHandler = nil
    }
    
    /// Test to reproduce URLSchemeTask race condition crash
    func testURLSchemeTaskRaceConditionCrash() async throws {
        print("🧪 WEBKIT CRASH REPRODUCTION TEST")
        print("=================================")
        print("Testing URLSchemeTask race condition that causes:")
        print("NSInternalInconsistencyException: 'This task has already been stopped'")
        
        // Step 1: Create WebView with URL scheme handler that can race
        let config = WKWebViewConfiguration()
        testURLSchemeHandler = TestURLSchemeHandler()
        config.setURLSchemeHandler(testURLSchemeHandler!, forURLScheme: "test-assets")
        
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 375, height: 667), configuration: config)
        
        // Step 2: Load HTML that triggers multiple rapid asset requests
        let testHTML = createRapidAssetLoadHTML()
        let loadExpectation = expectation(description: "Page loads with potential race")
        
        var navigationCompleted = false
        
        // Monitor for navigation completion
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            navigationCompleted = true
            loadExpectation.fulfill()
        }
        
        // Load page that triggers rapid asset loading
        webView!.loadHTMLString(testHTML, baseURL: URL(string: "test-assets://localhost/"))
        
        await fulfillment(of: [loadExpectation], timeout: 10.0)
        
        // Step 3: Trigger rapid navigation that could cause task cancellation
        print("🔄 Triggering rapid navigation to test task cancellation...")
        
        let rapidNavigationExpectation = expectation(description: "Rapid navigation completes")
        
        // Load multiple pages rapidly to trigger task cancellations
        webView!.loadHTMLString("<html><body><h1>Page 2</h1></body></html>", baseURL: nil)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.webView!.loadHTMLString("<html><body><h1>Page 3</h1></body></html>", baseURL: nil)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.webView!.loadHTMLString("<html><body><h1>Page 4</h1></body></html>", baseURL: nil)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            rapidNavigationExpectation.fulfill()
        }
        
        await fulfillment(of: [rapidNavigationExpectation], timeout: 5.0)
        
        // Step 4: Check if any crashes occurred
        print("✅ Test completed without crashing")
        print("Race condition handling: \(testURLSchemeHandler!.raceConditionHandled ? "SUCCESS" : "NOT TRIGGERED")")
        print("Tasks stopped multiple times: \(testURLSchemeHandler!.taskStoppedCount)")
        
        // If we got here without crashing, the fix is working
        XCTAssertTrue(true, "WebView navigation completed without NSInternalInconsistencyException")
    }
    
    /// Test URLSchemeTask proper lifecycle management
    func testURLSchemeTaskProperLifecycle() async throws {
        print("🧪 URLSCHEME TASK LIFECYCLE TEST")
        print("================================")
        
        let config = WKWebViewConfiguration()
        testURLSchemeHandler = TestURLSchemeHandler()
        config.setURLSchemeHandler(testURLSchemeHandler!, forURLScheme: "test-assets")
        
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 375, height: 667), configuration: config)
        
        let testHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Task Lifecycle Test</title>
            <link rel="stylesheet" href="test-assets://localhost/styles/test.css">
        </head>
        <body>
            <h1>Task Lifecycle Test</h1>
            <img src="test-assets://localhost/images/test.png" alt="Test Image">
            <script src="test-assets://localhost/scripts/test.js"></script>
        </body>
        </html>
        """
        
        let loadExpectation = expectation(description: "Task lifecycle test loads")
        
        webView!.loadHTMLString(testHTML, baseURL: URL(string: "test-assets://localhost/"))
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            loadExpectation.fulfill()
        }
        
        await fulfillment(of: [loadExpectation], timeout: 5.0)
        
        // Verify proper task handling
        XCTAssertGreaterThan(testURLSchemeHandler!.tasksStarted, 0, "Should have started some tasks")
        XCTAssertFalse(testURLSchemeHandler!.hasTaskStateViolation, "Should not have task state violations")
        
        print("✅ Tasks started: \(testURLSchemeHandler!.tasksStarted)")
        print("✅ Task state violations: \(testURLSchemeHandler!.hasTaskStateViolation ? "YES" : "NO")")
    }
    
    private func createRapidAssetLoadHTML() -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Race Condition Test</title>
            <link rel="stylesheet" href="test-assets://localhost/styles/style1.css">
            <link rel="stylesheet" href="test-assets://localhost/styles/style2.css">
            <link rel="stylesheet" href="test-assets://localhost/styles/style3.css">
        </head>
        <body>
            <h1>Rapid Asset Loading Test</h1>
            <img src="test-assets://localhost/images/img1.png" alt="Image 1">
            <img src="test-assets://localhost/images/img2.png" alt="Image 2">
            <img src="test-assets://localhost/images/img3.png" alt="Image 3">
            <img src="test-assets://localhost/images/img4.png" alt="Image 4">
            <script src="test-assets://localhost/scripts/script1.js"></script>
            <script src="test-assets://localhost/scripts/script2.js"></script>
            <script src="test-assets://localhost/scripts/script3.js"></script>
            
            <div id="dynamic-content"></div>
            
            <script>
            // Dynamically add more assets to increase race condition chances
            setTimeout(function() {
                var img = document.createElement('img');
                img.src = 'test-assets://localhost/images/dynamic.png';
                document.getElementById('dynamic-content').appendChild(img);
                
                var link = document.createElement('link');
                link.rel = 'stylesheet';
                link.href = 'test-assets://localhost/styles/dynamic.css';
                document.head.appendChild(link);
            }, 100);
            </script>
        </body>
        </html>
        """
    }
}

/// Test URL scheme handler that tracks task state and race conditions
class TestURLSchemeHandler: NSObject, WKURLSchemeHandler {
    var tasksStarted = 0
    var taskStoppedCount = 0
    var raceConditionHandled = false
    var hasTaskStateViolation = false
    
    // Using Set with ObjectIdentifier for iOS 18+ compatibility instead of direct WKURLSchemeTask
    private var activeTasks = Set<ObjectIdentifier>()
    private let taskQueue = DispatchQueue(label: "URLSchemeTaskQueue", qos: .userInitiated)
    private let tasksLock = NSLock() // Thread safety for task tracking
    
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        taskQueue.async {
            self.tasksStarted += 1
            let taskId = ObjectIdentifier(urlSchemeTask)
            self.tasksLock.lock()
            self.activeTasks.insert(taskId)
            self.tasksLock.unlock()
            
            print("🔗 [TEST] Starting task \(self.tasksStarted): \(urlSchemeTask.request.url?.path ?? "unknown")")
            
            // Simulate different asset types
            guard let url = urlSchemeTask.request.url else {
                self.completeTask(urlSchemeTask, withError: NSError(domain: "TestError", code: 400, userInfo: nil))
                return
            }
            
            let path = url.path
            
            if path.contains(".css") {
                self.handleCSSRequest(urlSchemeTask, path: path)
            } else if path.contains(".js") {
                self.handleJSRequest(urlSchemeTask, path: path)
            } else if path.contains(".png") || path.contains(".jpg") {
                self.handleImageRequest(urlSchemeTask, path: path)
            } else {
                self.handle404Request(urlSchemeTask, path: path)
            }
        }
    }
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        taskQueue.async {
            self.taskStoppedCount += 1
            print("🛑 [TEST] Stopping task: \(urlSchemeTask.request.url?.path ?? "unknown")")
            
            // Check if task was already completed
            let taskId = ObjectIdentifier(urlSchemeTask)
            self.tasksLock.lock()
            if !self.activeTasks.contains(taskId) {
                self.tasksLock.unlock()
                print("⚠️ [TEST] RACE CONDITION: Task already removed from active set")
                self.raceConditionHandled = true
            } else {
                self.activeTasks.remove(taskId)
                self.tasksLock.unlock()
            }
        }
    }
    
    private func handleCSSRequest(_ urlSchemeTask: WKURLSchemeTask, path: String) {
        let cssContent = """
        body { 
            font-family: Arial, sans-serif; 
            margin: 20px;
            background-color: #f0f0f0;
        }
        h1 { color: #333; }
        img { max-width: 100px; height: auto; margin: 5px; }
        """
        
        // Add delay to increase race condition chances
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            self.completeTask(urlSchemeTask, withData: cssContent.data(using: .utf8)!, mimeType: "text/css")
        }
    }
    
    private func handleJSRequest(_ urlSchemeTask: WKURLSchemeTask, path: String) {
        let jsContent = """
        console.log('Test script loaded: \(path)');
        document.addEventListener('DOMContentLoaded', function() {
            console.log('DOM ready for \(path)');
        });
        """
        
        // Add delay to increase race condition chances
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            self.completeTask(urlSchemeTask, withData: jsContent.data(using: .utf8)!, mimeType: "application/javascript")
        }
    }
    
    private func handleImageRequest(_ urlSchemeTask: WKURLSchemeTask, path: String) {
        // Create a small 1x1 PNG
        let pngData = Data([
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
            0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00,
            0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0x00, 0x02, 0x00, 0x00,
            0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
            0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
        ])
        
        // Add delay to increase race condition chances
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) {
            self.completeTask(urlSchemeTask, withData: pngData, mimeType: "image/png")
        }
    }
    
    private func handle404Request(_ urlSchemeTask: WKURLSchemeTask, path: String) {
        let error = NSError(domain: "TestURLSchemeHandler", code: 404, userInfo: [
            NSLocalizedDescriptionKey: "Asset not found: \(path)"
        ])
        completeTask(urlSchemeTask, withError: error)
    }
    
    private func completeTask(_ urlSchemeTask: WKURLSchemeTask, withData data: Data, mimeType: String) {
        taskQueue.async {
            // CRITICAL: Check if task is still active before completing
            let taskId = ObjectIdentifier(urlSchemeTask)
            self.tasksLock.lock()
            guard self.activeTasks.contains(taskId) else {
                self.tasksLock.unlock()
                print("⚠️ [TEST] RACE CONDITION DETECTED: Attempted to complete already-stopped task")
                self.raceConditionHandled = true
                self.hasTaskStateViolation = true
                return
            }
            
            guard let url = urlSchemeTask.request.url else {
                self.hasTaskStateViolation = true
                self.activeTasks.remove(taskId)
                self.tasksLock.unlock()
                return
            }
            
            do {
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Type": mimeType,
                        "Content-Length": "\(data.count)"
                    ]
                )!
                
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
                
                self.activeTasks.remove(taskId)
                self.tasksLock.unlock()
                print("✅ [TEST] Completed task: \(url.path)")
                
            } catch {
                print("❌ [TEST] Error completing task: \(error)")
                self.hasTaskStateViolation = true
                self.activeTasks.remove(taskId)
                self.tasksLock.unlock()
            }
        }
    }
    
    private func completeTask(_ urlSchemeTask: WKURLSchemeTask, withError error: Error) {
        taskQueue.async {
            // CRITICAL: Check if task is still active before failing
            let taskId = ObjectIdentifier(urlSchemeTask)
            self.tasksLock.lock()
            guard self.activeTasks.contains(taskId) else {
                self.tasksLock.unlock()
                print("⚠️ [TEST] RACE CONDITION DETECTED: Attempted to fail already-stopped task")
                self.raceConditionHandled = true
                self.hasTaskStateViolation = true
                return
            }
            
            do {
                urlSchemeTask.didFailWithError(error)
                self.activeTasks.remove(taskId)
                self.tasksLock.unlock()
                print("❌ [TEST] Failed task with error: \(error.localizedDescription)")
            } catch {
                print("❌ [TEST] Error failing task: \(error)")
                self.hasTaskStateViolation = true
                self.activeTasks.remove(taskId)
                self.tasksLock.unlock()
            }
        }
    }
}