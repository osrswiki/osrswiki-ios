//
//  ArticleWebView.swift
//  OSRS Wiki
//
//  Created on iOS webviewer implementation session
//

import SwiftUI
import WebKit
import UniformTypeIdentifiers
import CryptoKit

enum osrsArticleDynamicTypeScaling {
    static func scale(for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        switch dynamicTypeSize {
        case .xSmall:
            return 0.88
        case .small:
            return 0.94
        case .medium, .large:
            return 1.0
        case .xLarge:
            return 1.08
        case .xxLarge:
            return 1.16
        case .xxxLarge:
            return 1.24
        case .accessibility1:
            return 1.38
        case .accessibility2:
            return 1.52
        case .accessibility3:
            return 1.68
        case .accessibility4:
            return 1.84
        case .accessibility5:
            return 2.0
        @unknown default:
            return 1.0
        }
    }

    static func toolbarScale(for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        min(scale(for: dynamicTypeSize), 1.45)
    }

    static func toolbarHeight(for dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        min(max(49 * toolbarScale(for: dynamicTypeSize), 49), 72)
    }

    static func requiresWebReflow(for dynamicTypeSize: DynamicTypeSize) -> Bool {
        dynamicTypeSize.isAccessibilitySize
    }
}

// MARK: - iOS Asset Handler (matches Android's appassets.androidplatform.net)
class IOSAssetHandler: NSObject, WKURLSchemeHandler {
    
    // MARK: - Task State Management (Enhanced to prevent WebKit NSException crashes)
    
    // Task state tracking with generation counter to prevent race conditions
    private struct TaskInfo {
        let id: ObjectIdentifier
        let generation: Int
        let startTime: Date
    }
    
    private var activeTasks: [ObjectIdentifier: TaskInfo] = [:]
    private var globalGeneration = 0
    private let taskQueue = DispatchQueue(label: "IOSAssetHandler.TaskQueue", qos: .userInitiated)
    private let tasksLock = NSLock() // Thread safety for task tracking
    
    // Synchronization for critical WebKit calls
    private let completionSemaphore = DispatchSemaphore(value: 1)
    
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        taskQueue.async {
            // DEFENSIVE: Verify task is not nil and URL scheme handler is still active
            guard let urlString = urlSchemeTask.request.url?.absoluteString, !urlString.isEmpty else {
                print("❌ IOSAssetHandler: EDGE CASE PREVENTED: Empty or nil URL in request")
                return
            }
            
            // Add task to active set with generation tracking
            let taskId = ObjectIdentifier(urlSchemeTask)
            self.tasksLock.lock()
            
            // DEFENSIVE: Check if task was already added (shouldn't happen but prevent duplicates)
            if self.activeTasks.keys.contains(taskId) {
                self.tasksLock.unlock()
                print("⚠️ IOSAssetHandler: EDGE CASE PREVENTED: Task already exists in active set")
                return
            }
            
            // Create task info with unique generation counter
            self.globalGeneration += 1
            let taskInfo = TaskInfo(id: taskId, generation: self.globalGeneration, startTime: Date())
            self.activeTasks[taskId] = taskInfo
            
            let currentGeneration = taskInfo.generation
            self.tasksLock.unlock()
            
            print("🆔 IOSAssetHandler: Task started with generation \(currentGeneration)")
            
            print("🚨 IOSAssetHandler: CALLED! URL: \(urlSchemeTask.request.url?.absoluteString ?? "nil")")
            
            guard let url = urlSchemeTask.request.url else {
                print("❌ IOSAssetHandler: No URL in request")
                self.completeTask(urlSchemeTask, withError: NSError(domain: "IOSAssetHandler", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing URL in request"]))
                return
            }
            
            // Get the registered scheme from UserDefaults
            let expectedScheme = UserDefaults.standard.string(forKey: "WKURLSchemeHandler_Scheme") ?? "app-assets"
            
            // DEFENSIVE: Validate scheme with multiple fallback checks
            let urlScheme = url.scheme?.lowercased() ?? ""
            let expectedSchemeLower = expectedScheme.lowercased()
            
            guard !urlScheme.isEmpty && (urlScheme == expectedSchemeLower || urlScheme == "app-assets") else {
                print("❌ IOSAssetHandler: Invalid scheme: '\(url.scheme ?? "nil")' (expected: '\(expectedScheme)' or 'app-assets')")
                self.completeTask(urlSchemeTask, withError: NSError(domain: "IOSAssetHandler", code: 404, userInfo: [NSLocalizedDescriptionKey: "Invalid URL scheme: \(url.scheme ?? "nil")"]))
                return
            }

            if let articleURL = osrsArticleLinkRouter.appArticleURL(for: url) {
                print("🔄 IOSAssetHandler: Intercepted app-assets article navigation: \(articleURL.absoluteString)")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .osrsInternalArticleLinkRequested,
                        object: nil,
                        userInfo: ["url": articleURL]
                    )
                }
                self.completeTask(
                    urlSchemeTask,
                    withError: NSError(
                        domain: NSURLErrorDomain,
                        code: NSURLErrorCancelled,
                        userInfo: [NSURLErrorFailingURLErrorKey: url]
                    )
                )
                return
            }
        
        // Extract asset path (e.g., app-assets://localhost/styles/themes.css -> styles/themes.css)
        let rawPath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        // DEFENSIVE: Validate asset path for security and sanity
        guard !rawPath.isEmpty else {
            print("❌ IOSAssetHandler: EDGE CASE PREVENTED: Empty asset path")
            self.completeTask(urlSchemeTask, withError: NSError(domain: "IOSAssetHandler", code: 400, userInfo: [NSLocalizedDescriptionKey: "Empty asset path"]))
            return
        }
        
        // DEFENSIVE: Prevent directory traversal attacks
        let assetPath = rawPath.replacingOccurrences(of: "../", with: "").replacingOccurrences(of: "..\\", with: "")
        
        // DEFENSIVE: Validate path length (prevent extremely long paths)
        guard assetPath.count < 500 else {
            print("❌ IOSAssetHandler: EDGE CASE PREVENTED: Asset path too long (\(assetPath.count) chars)")
            self.completeTask(urlSchemeTask, withError: NSError(domain: "IOSAssetHandler", code: 400, userInfo: [NSLocalizedDescriptionKey: "Asset path too long"]))
            return
        }
        
        print("📁 IOSAssetHandler: Extracted asset path: '\(assetPath)'")
        
            // NEW: Check if this is a saved page request - but now use web archives instead
            if url.host == "saved-pages" {
                print("📖 IOSAssetHandler: Web archive request detected: \(assetPath)")
                self.handleWebArchiveRequest(urlSchemeTask: urlSchemeTask, url: url, assetPath: assetPath)
                return
            }
        
            // PRIORITY FIX: Try bundle detection FIRST before external resource logic
            // This restores main branch behavior where fonts are served from bundle, not external server
            
        
        // Debug: Show bundle structure for asset resolution debugging
        let bundleMainPath = Bundle.main.bundlePath
        print("📦 Bundle path: \(bundleMainPath)")
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: bundleMainPath) {
            print("📦 Bundle root contents: \(contents.prefix(10))")
        }
        
        // Check if Assets directory exists in bundle
        let assetsDir = bundleMainPath + "/Assets"
        if FileManager.default.fileExists(atPath: assetsDir) {
            print("📦 Assets directory exists: \(assetsDir)")
            if let assetContents = try? FileManager.default.contentsOfDirectory(atPath: assetsDir) {
                print("📦 Assets/ contents: \(assetContents.prefix(10))")
                
                // Check web/ subdirectory specifically
                let webDir = assetsDir + "/web"
                if FileManager.default.fileExists(atPath: webDir) {
                    if let webContents = try? FileManager.default.contentsOfDirectory(atPath: webDir) {
                        print("📦 Assets/web/ contents: \(webContents.prefix(10))")
                    }
                } else {
                    print("📦 Assets/web/ does NOT exist in bundle")
                }
            }
        } else {
            print("📦 Assets directory does NOT exist in bundle")
        }
        
        // Try multiple path patterns to find the asset
        var bundlePath: String?
        var attemptedPaths: [String] = []
        
        print("🟡 [ASSET_HANDLER] Request for: \(assetPath)")
        
        // Pattern 1: Try direct path in Assets/ directory structure (our organized shared assets)
        let assetsPath = "Assets/\(assetPath)"
        if let path = Bundle.main.path(forResource: assetsPath, ofType: nil) {
            bundlePath = path
            print("🟢 [ASSET_HANDLER] Found via Assets/ structure: \(assetsPath)")
        } else {
            attemptedPaths.append("Bundle.main.path(forResource: '\(assetsPath)', ofType: nil)")
            print("🔍 [ASSET_HANDLER] Pattern 1 failed for: \(assetsPath)")
            
            // Additional debugging: Try different approaches for JS files specifically
            if assetPath == "web/map_bridge.js" {
                print("🔍 [DEBUG] Special debugging for map_bridge.js:")
                
                // Try various permutations
                let variations = [
                    "Assets/web/map_bridge.js",
                    "web/map_bridge",
                    "Assets/web/map_bridge", 
                    "map_bridge.js",
                    "map_bridge"
                ]
                
                for variation in variations {
                    if let path = Bundle.main.path(forResource: variation, ofType: nil) {
                        print("🔍 [DEBUG] Found \(variation) -> \(path)")
                    } else if let path = Bundle.main.path(forResource: variation, ofType: "js") {
                        print("🔍 [DEBUG] Found \(variation).js -> \(path)")
                    } else {
                        print("🔍 [DEBUG] NOT found: \(variation) (neither .js nor no extension)")
                    }
                }
            }
        }
        
        // Pattern 2: Try with extension separation in Assets/ directory
        if bundlePath == nil {
            let filename = assetPath.components(separatedBy: "/").last ?? assetPath
            let pathComponents = filename.split(separator: ".")
            if pathComponents.count >= 2,
               let lastComponent = pathComponents.last {
                let nameWithoutExtension = String(pathComponents.dropLast().joined(separator: "."))
                let fileExtension = String(lastComponent)
                let assetsFilePath = "Assets/\(assetPath.replacingOccurrences(of: filename, with: ""))\(nameWithoutExtension)"
                
                if let path = Bundle.main.path(forResource: assetsFilePath, ofType: fileExtension) {
                    bundlePath = path
                    print("🟢 [ASSET_HANDLER] Found via Assets/ + extension: \(assetsFilePath).\(fileExtension)")
                } else {
                    attemptedPaths.append("Bundle.main.path(forResource: '\(assetsFilePath)', ofType: '\(fileExtension)')")
                    print("🔍 [ASSET_HANDLER] Pattern 2 failed for: \(assetsFilePath).\(fileExtension)")
                }
            }
        }
        
        // Pattern 3: Special handling for fonts in Font/ subdirectory (legacy fonts)
        if bundlePath == nil && assetPath.hasPrefix("fonts/") {
            let fontFileName = assetPath.replacingOccurrences(of: "fonts/", with: "")
            if let path = Bundle.main.path(forResource: fontFileName, ofType: nil, inDirectory: "Font") {
                bundlePath = path
                print("✅ IOSAssetHandler: Found font in Font/ subdirectory: \(fontFileName)")
            } else {
                attemptedPaths.append("Bundle.main.path(forResource: '\(fontFileName)', ofType: nil, inDirectory: 'Font')")
            }
        }
        
        // Pattern 4: Fallback to flat bundle structure (iOS flattens some assets to bundle root)
        if bundlePath == nil {
            let flatFileName = assetPath.components(separatedBy: "/").last ?? assetPath
            if let path = Bundle.main.path(forResource: flatFileName, ofType: nil) {
                bundlePath = path
                print("🟢 [ASSET_HANDLER] Found via flat bundle: \(flatFileName)")
            } else {
                attemptedPaths.append("Bundle.main.path(forResource: '\(flatFileName)', ofType: nil)")
            }
        }
        
        // Pattern 5: Try parsing file extension from flat filename
        if bundlePath == nil {
            let flatFileName = assetPath.components(separatedBy: "/").last ?? assetPath
            let pathComponents = flatFileName.split(separator: ".")
            if pathComponents.count >= 2,
               let lastComponent = pathComponents.last {
                let nameWithoutExtension = String(pathComponents.dropLast().joined(separator: "."))
                let fileExtension = String(lastComponent)
                
                if let path = Bundle.main.path(forResource: nameWithoutExtension, ofType: fileExtension) {
                    bundlePath = path
                    print("✅ IOSAssetHandler: Found via flat + extension parsing: \(nameWithoutExtension).\(fileExtension)")
                } else {
                    attemptedPaths.append("Bundle.main.path(forResource: '\(nameWithoutExtension)', ofType: '\(fileExtension)')")
                }
            }
        }
        
            guard let finalBundlePath = bundlePath else {
                print("🔴 [ASSET_HANDLER] Asset not found in bundle: \(assetPath)")
                print("🔴 [ASSET_HANDLER] Attempted bundle paths: \(attemptedPaths)")
                
                // FALLBACK: If not found in bundle, try external resource handling (offline architecture)
                if self.shouldHandleExternalResource(assetPath: assetPath) {
                    print("🌐 [ASSET_HANDLER] Falling back to external resource handling for: \(assetPath)")
                    self.handleExternalResourceRequest(urlSchemeTask: urlSchemeTask, assetPath: assetPath)
                    return
                }
                
                // Final failure: not in bundle and not an external resource
                print("❌ [ASSET_HANDLER] Asset cannot be resolved: \(assetPath)")
                self.completeTask(urlSchemeTask, withError: NSError(domain: "IOSAssetHandler", code: 404, 
                                                      userInfo: [NSLocalizedDescriptionKey: "Asset not found: \(assetPath). Attempted: \(attemptedPaths.joined(separator: ", "))"]))
                return
            }
            
            // DEFENSIVE: Verify file exists and is readable
            guard FileManager.default.fileExists(atPath: finalBundlePath) else {
                print("❌ IOSAssetHandler: EDGE CASE PREVENTED: File path exists but file is missing: \(finalBundlePath)")
                self.completeTask(urlSchemeTask, withError: NSError(domain: "IOSAssetHandler", code: 404, 
                                                      userInfo: [NSLocalizedDescriptionKey: "File missing at path: \(finalBundlePath)"]))
                return
            }
            
            // DEFENSIVE: Load file data with error handling
            guard let data = FileManager.default.contents(atPath: finalBundlePath), !data.isEmpty else {
                print("❌ IOSAssetHandler: EDGE CASE PREVENTED: File exists but no data or empty: \(finalBundlePath)")
                self.completeTask(urlSchemeTask, withError: NSError(domain: "IOSAssetHandler", code: 500, 
                                                      userInfo: [NSLocalizedDescriptionKey: "Unable to read file data from: \(finalBundlePath)"]))
                return
            }
        
        print("🟢 [ASSET_HANDLER] Found asset at: \(finalBundlePath)")
        
        // DEFENSIVE: Determine MIME type with fallbacks
        let fileExtension = (assetPath as NSString).pathExtension.lowercased()
        let mimeType: String
        
        switch fileExtension {
        case "css":
            mimeType = "text/css"
        case "js":
            mimeType = "application/javascript"
        case "ttf":
            mimeType = "font/ttf"
        case "woff", "woff2":
            mimeType = "font/woff"
        case "png":
            mimeType = "image/png"
        case "jpg", "jpeg":
            mimeType = "image/jpeg"
        case "svg":
            mimeType = "image/svg+xml"
        case "html", "htm":
            mimeType = "text/html"
        case "json":
            mimeType = "application/json"
        case "txt":
            mimeType = "text/plain"
        default:
            mimeType = "application/octet-stream"
            print("⚠️ IOSAssetHandler: Unknown file extension '\(fileExtension)' for \(assetPath), using fallback MIME type")
        }
        
        // DEFENSIVE: Create HTTP response with error handling
        let headerFields: [String: String] = [
            "Content-Type": mimeType,
            "Content-Length": "\(data.count)",
            "Cache-Control": "public, max-age=3600", // 1 hour cache for performance
            "X-Asset-Source": "iOS Bundle" // Debug info
        ]
        
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headerFields) else {
            print("❌ IOSAssetHandler: EDGE CASE PREVENTED: Failed to create HTTP response for \(assetPath)")
            self.completeTask(urlSchemeTask, withError: NSError(domain: "IOSAssetHandler", code: 500, userInfo: [NSLocalizedDescriptionKey: "HTTP response creation failed for: \(assetPath)"]))
            return
        }
            
            self.completeTask(urlSchemeTask, withResponse: response, data: data)
            print("📱 iOS Asset Handler: Served \(assetPath) (\(data.count) bytes)")
        }
    }
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // CRITICAL: Use synchronous execution to prevent race conditions
        let taskId = ObjectIdentifier(urlSchemeTask)
        
        // Acquire completion semaphore to prevent concurrent WebKit calls
        completionSemaphore.wait()
        
        tasksLock.lock()
        if let taskInfo = activeTasks[taskId] {
            activeTasks.removeValue(forKey: taskId)
            tasksLock.unlock()
            
            print("🛑 IOSAssetHandler: Task generation \(taskInfo.generation) stopped and removed")
        } else {
            tasksLock.unlock()
            print("⚠️ IOSAssetHandler: Task was already removed or never started")
        }
        
        completionSemaphore.signal()
    }
    
    
    private func completeTask(_ urlSchemeTask: WKURLSchemeTask, withResponse response: HTTPURLResponse, data: Data) {
        taskQueue.async {
            self.performAtomicTaskCompletion(urlSchemeTask) { taskInfo in
                // This closure runs ONLY if the task is verified as still active
                print("✅ IOSAssetHandler: Completing task generation \(taskInfo.generation)")
                
                // Call WebKit methods in the safe zone - no exceptions possible here
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
                
                print("✅ IOSAssetHandler: Task generation \(taskInfo.generation) completed successfully")
            }
        }
    }
    
    private func completeTask(_ urlSchemeTask: WKURLSchemeTask, withError error: Error) {
        taskQueue.async {
            self.performAtomicTaskCompletion(urlSchemeTask) { taskInfo in
                // This closure runs ONLY if the task is verified as still active
                print("❌ IOSAssetHandler: Failing task generation \(taskInfo.generation) with error: \(error.localizedDescription)")
                
                // Call WebKit methods in the safe zone - no exceptions possible here
                urlSchemeTask.didFailWithError(error)
                
                print("❌ IOSAssetHandler: Task generation \(taskInfo.generation) failed successfully")
            }
        }
    }
    
    /// CRITICAL: Atomic task completion that prevents WebKit NSException crashes
    /// This method ensures WebKit methods are never called on stopped tasks
    private func performAtomicTaskCompletion(_ urlSchemeTask: WKURLSchemeTask, completion: (TaskInfo) -> Void) {
        let taskId = ObjectIdentifier(urlSchemeTask)
        
        // STEP 1: Acquire semaphore to prevent concurrent stop() calls
        completionSemaphore.wait()
        
        // STEP 2: Check if task is still active under lock
        tasksLock.lock()
        guard let taskInfo = activeTasks[taskId] else {
            // Task was stopped - release lock and semaphore, abort safely
            tasksLock.unlock()
            completionSemaphore.signal()
            print("⚠️ IOSAssetHandler: RACE PREVENTED: Task generation unknown was already stopped")
            return
        }
        
        // STEP 3: Task is verified active - remove it and execute WebKit calls
        activeTasks.removeValue(forKey: taskId)
        let capturedTaskInfo = taskInfo
        tasksLock.unlock()
        
        // STEP 4: Execute WebKit methods (guaranteed safe - task cannot be stopped now)
        completion(capturedTaskInfo)
        
        // STEP 5: Release semaphore to allow other operations
        completionSemaphore.signal()
    }
    
    // MARK: - WebView Cleanup Methods (Fix for task lifecycle crashes)
    
    /// Cancel all active tasks when WebView is being destroyed
    /// This prevents "This task has already been stopped" crashes during WebView destruction
    func cancelAllActiveTasks() {
        // CRITICAL: Use semaphore to ensure atomic cleanup
        completionSemaphore.wait()
        
        tasksLock.lock()
        let taskCount = activeTasks.count
        let cancelledGenerations = activeTasks.values.map { $0.generation }
        activeTasks.removeAll()
        tasksLock.unlock()
        
        completionSemaphore.signal()
        
        print("🧹 IOSAssetHandler: Cancelled \(taskCount) active tasks (generations: \(cancelledGenerations)) during WebView cleanup")
    }
    
    /// Synchronously cancel all active tasks and wait for completion
    /// This ensures all asset handler operations are finished before WebView destruction
    func cancelAllActiveTasksAndWait() {
        print("🔄 IOSAssetHandler: Starting synchronous task cancellation...")
        
        // CRITICAL: Use completion semaphore for atomic operation
        completionSemaphore.wait()
        
        tasksLock.lock()
        let taskCount = activeTasks.count
        let cancelledGenerations = activeTasks.values.map { $0.generation }
        activeTasks.removeAll()
        tasksLock.unlock()
        
        completionSemaphore.signal()
        
        print("✅ IOSAssetHandler: Synchronously cancelled \(taskCount) tasks (generations: \(cancelledGenerations))")
    }
    
    /// Get count of currently active tasks for monitoring
    var activeTaskCount: Int {
        tasksLock.lock()
        let count = activeTasks.count
        tasksLock.unlock()
        return count
    }
    
    // MARK: - HTTP Interceptor for Offline Caching (Android-style)
    
    /// HTTP Interceptor Storage - matches Android's OfflineCacheInterceptor approach
    private var isInOfflineSaveMode: Bool = false
    private var currentSavePageId: String?
    private let interceptorQueue = DispatchQueue(label: "IOSAssetHandler.HTTPInterceptor", qos: .userInitiated)
    
    /// Enable save mode for offline caching (like Android's X-Offline-Save header)
    func enableOfflineSaveMode(pageId: String) {
        interceptorQueue.async {
            print("🔄 IOSAssetHandler: Enabling offline save mode for page: \(pageId)")
            self.isInOfflineSaveMode = true
            self.currentSavePageId = pageId
        }
    }
    
    /// Disable save mode and return to normal operation
    func disableOfflineSaveMode() {
        interceptorQueue.async {
            print("✅ IOSAssetHandler: Disabling offline save mode")
            self.isInOfflineSaveMode = false
            self.currentSavePageId = nil
        }
    }
    
    /// Save HTTP response to offline cache (Android OfflineCacheInterceptor equivalent)
    private func saveHttpResponse(url: String, response: HTTPURLResponse, data: Data, pageId: String) {
        interceptorQueue.async {
            // CRITICAL FIX: Save to LocalHTTPServer cache for proper offline access
            // This ensures images are found during offline page loading
            if #available(iOS 17.0, *) {
                // Use ProxyInterceptorService to save to LocalHTTPServer cache
                Task { @MainActor in
                    ProxyInterceptorService.shared.cacheResponseForAsset(
                        pageId: pageId,
                        url: url,
                        data: data,
                        response: response
                    )
                    print("✅ IOSAssetHandler: Saved HTTP response to LocalHTTPServer cache for \(url) (\(data.count) bytes)")
                }
            } else {
                // Fallback to OfflineContentService for older iOS versions
                guard let offlineService = try? OfflineContentService.shared else {
                    print("❌ IOSAssetHandler: Cannot save response - OfflineContentService unavailable")
                    return
                }
                
                do {
                    // Create hash of URL for filename (like Android's hashUrl method)
                    let urlHash = self.hashUrl(url)
                    let filename = "\(urlHash).cached"
                    
                    // Save response metadata (headers, status code)
                    let metadata = [
                        "url": url,
                        "status": response.statusCode,
                        "headers": response.allHeaderFields,
                        "mimeType": response.mimeType ?? "application/octet-stream"
                    ] as [String: Any]
                    
                    try offlineService.saveHttpResponse(
                        pageId: pageId,
                        url: url,
                        filename: filename,
                        data: data,
                        metadata: metadata
                    )
                    
                    print("✅ IOSAssetHandler: Saved HTTP response for \(url) (\(data.count) bytes)")
                    
                } catch {
                    print("❌ IOSAssetHandler: Failed to save HTTP response for \(url): \(error)")
                }
            }
        }
    }
    
    /// Get cached HTTP response (Android OfflineCacheInterceptor equivalent)
    private func getCachedHttpResponse(url: String, pageId: String) -> (data: Data, response: HTTPURLResponse)? {
        print("🔍 IOSAssetHandler: Requesting cached response for URL: \(url), pageId: \(pageId)")
        
        // Use ProxyInterceptorService to access LocalHTTPServer cached responses
        if #available(iOS 17.0, *) {
            if let cachedResponse = ProxyInterceptorService.shared.getCachedAssetResponse(url: url, pageId: pageId) {
                print("✅ IOSAssetHandler: Retrieved cached response from LocalHTTPServer (\(cachedResponse.data.count) bytes)")
                return cachedResponse
            } else {
                print("❌ IOSAssetHandler: No cached response found in LocalHTTPServer for: \(url)")
            }
        } else {
            print("⚠️ IOSAssetHandler: iOS 17+ required for proxy-based caching, falling back to legacy approach")
            // Legacy fallback for iOS <17 could use OfflineContentService if needed
        }
        
        return nil
    }
    
    /// Hash URL for consistent filename generation
    private func hashUrl(_ url: String) -> String {
        guard let data = url.data(using: .utf8) else { return url }
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Determine if this is an external resource that should be cached (Android-style detection)
    private func shouldHandleExternalResource(assetPath: String) -> Bool {
        // Images
        if assetPath.hasPrefix("images/") || 
           assetPath.contains(".png") || assetPath.contains(".jpg") || 
           assetPath.contains(".jpeg") || assetPath.contains(".gif") || 
           assetPath.contains(".svg") {
            return true
        }
        
        // MediaWiki resources (load.php, etc.)
        if assetPath.hasSuffix(".php") || assetPath.contains("load.php") {
            return true
        }
        
        // Font files
        if assetPath.contains(".woff") || assetPath.contains(".woff2") || 
           assetPath.contains(".ttf") || assetPath.contains(".otf") {
            return true
        }
        
        // External JavaScript/CSS
        if assetPath.contains("cdn.") || assetPath.contains("pageos.js") {
            return true
        }
        
        return false
    }
    
    /// Handle external resource with HTTP interceptor pattern (Android OfflineCacheInterceptor equivalent)
    private func handleExternalResourceRequest(urlSchemeTask: WKURLSchemeTask, assetPath: String) {
        let originalURL = reconstructOriginalURL(from: assetPath, originalRequest: urlSchemeTask.request)
        
        // Check if we're in save mode and should cache this resource
        interceptorQueue.async {
            let shouldSave = self.isInOfflineSaveMode
            let pageId = self.currentSavePageId
            
            // Get pageId from local context or ProxyInterceptorService
            let pageIdToUse: String?
            if let localPageId = pageId {
                pageIdToUse = localPageId
                print("🔍 [ENHANCED_DIAGNOSTICS] Using local pageId: \(localPageId)")
            } else if #available(iOS 17.0, *) {
                pageIdToUse = ProxyInterceptorService.shared.getCurrentPageId()
                if let proxyPageId = pageIdToUse {
                    print("🔍 [ENHANCED_DIAGNOSTICS] Retrieved pageId from ProxyInterceptorService: \(proxyPageId)")
                } else {
                    print("🔍 [ENHANCED_DIAGNOSTICS] No pageId available from ProxyInterceptorService")
                }
            } else {
                pageIdToUse = nil
                print("🔍 [ENHANCED_DIAGNOSTICS] iOS 17+ required for ProxyInterceptorService pageId lookup")
            }
            
            // Always try to serve from cache first if we have a pageId
            if let pageId = pageIdToUse {
                print("🔍 [ENHANCED_DIAGNOSTICS] Checking cache for: \(originalURL) with pageId: \(pageId)")
                if let cachedResponse = self.getCachedHttpResponse(url: originalURL, pageId: pageId) {
                    print("✅ IOSAssetHandler: Serving \(originalURL) from cache (\(cachedResponse.data.count) bytes)")
                    print("🔍 [ENHANCED_DIAGNOSTICS] Cache hit - Status: \(cachedResponse.response.statusCode)")
                    
                    // Check for potential cache corruption issues
                    let resourceType = self.determineResourceType(from: originalURL)
                    if cachedResponse.response.statusCode != 200 {
                        print("⚠️ [ENHANCED_DIAGNOSTICS] Serving non-200 cached response: \(cachedResponse.response.statusCode)")
                        if let contentType = cachedResponse.response.value(forHTTPHeaderField: "Content-Type"),
                           contentType.contains("text/html") && (resourceType == "Image" || resourceType == "Font") {
                            print("🚨 [ENHANCED_DIAGNOSTICS] CACHE CORRUPTION: HTML cached as \(resourceType)!")
                        }
                    }
                    
                    self.completeTask(urlSchemeTask, withResponse: cachedResponse.response, data: cachedResponse.data)
                    return
                } else {
                    print("❌ [ENHANCED_DIAGNOSTICS] Cache miss for: \(originalURL) (pageId: \(pageId))")
                }
            } else {
                print("🔍 [ENHANCED_DIAGNOSTICS] No pageId available for caching check")
            }
            
            // Fetch from network (either for saving or because not cached)
            self.fetchAndHandleExternalResource(
                urlSchemeTask: urlSchemeTask,
                originalURL: originalURL,
                shouldSave: shouldSave,
                pageId: pageIdToUse
            )
        }
    }
    
    /// Fetch external resource from network and optionally save (Android-style)
    private func fetchAndHandleExternalResource(urlSchemeTask: WKURLSchemeTask, originalURL: String, shouldSave: Bool, pageId: String?) {
        guard let url = URL(string: originalURL) else {
            print("❌ IOSAssetHandler: Invalid external URL: \(originalURL)")
            completeTask(urlSchemeTask, withError: NSError(domain: "IOSAssetHandler", code: 400, userInfo: nil))
            return
        }
        
        print("🌐 IOSAssetHandler: Fetching external resource through proxy system: \(originalURL)")
        
        // Enhanced diagnostics for image loading issues
        let resourceType = determineResourceType(from: originalURL)
        print("🔍 [ENHANCED_DIAGNOSTICS] Resource type: \(resourceType)")
        print("🔍 [ENHANCED_DIAGNOSTICS] Should save: \(shouldSave)")
        print("🔍 [ENHANCED_DIAGNOSTICS] Page ID: \(pageId ?? "none")")
        print("🔍 [ENHANCED_DIAGNOSTICS] URL breakdown:")
        print("   - Host: \(url.host ?? "none")")
        print("   - Path: \(url.path)")
        print("   - Query: \(url.query ?? "none")")
        print("   - Fragment: \(url.fragment ?? "none")")
        
        // Use NetworkManager instead of URLSession.shared to route through proxy system
        Task { [weak self] in
            guard let self = self else { return }
            
            do {
                let (data, response) = try await NetworkManager.shared.performDataRequest(url: url, retryCount: 2)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("❌ IOSAssetHandler: Invalid response type for \(originalURL)")
                    await MainActor.run {
                        self.completeTask(urlSchemeTask, withError: NSError(domain: "IOSAssetHandler", code: 500, userInfo: nil))
                    }
                    return
                }
                
                print("✅ IOSAssetHandler: Successfully fetched external resource through proxy: \(originalURL) (\(data.count) bytes)")
                
                // Enhanced diagnostics for HTTP response
                print("🔍 [ENHANCED_DIAGNOSTICS] HTTP Response Details:")
                print("   - Status Code: \(httpResponse.statusCode)")
                print("   - Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown")")
                print("   - Content-Length: \(httpResponse.value(forHTTPHeaderField: "Content-Length") ?? "unknown")")
                print("   - Data Size: \(data.count) bytes")
                
                // Check for potential issues
                if httpResponse.statusCode != 200 {
                    print("⚠️ [ENHANCED_DIAGNOSTICS] Non-200 status code detected: \(httpResponse.statusCode)")
                    if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"), 
                       contentType.contains("text/html") && resourceType == "Image" {
                        print("🚨 [ENHANCED_DIAGNOSTICS] WARNING: HTML content returned for image request - likely 404 error page!")
                    }
                }
                
                // Save to cache if in save mode (Android-style)
                if shouldSave, let pageId = pageId {
                    print("💾 [ENHANCED_DIAGNOSTICS] Saving to cache: \(resourceType) for pageId \(pageId)")
                    self.saveHttpResponse(url: originalURL, response: httpResponse, data: data, pageId: pageId)
                } else {
                    print("🔍 [ENHANCED_DIAGNOSTICS] NOT saving to cache - shouldSave: \(shouldSave), pageId: \(pageId ?? "none")")
                }
                
                // Serve to WebView
                await MainActor.run {
                    self.completeTask(urlSchemeTask, withResponse: httpResponse, data: data)
                    print("📱 IOSAssetHandler: Served external resource \(originalURL) (\(data.count) bytes)")
                }
                
            } catch {
                print("❌ IOSAssetHandler: NetworkManager fetch failed for \(originalURL): \(error.localizedDescription)")
                await MainActor.run {
                    self.completeTask(urlSchemeTask, withError: error)
                }
            }
        }
    }
    
    /// Reconstruct original URL from asset path and request context
    private func reconstructOriginalURL(from assetPath: String, originalRequest: URLRequest) -> String {
        // If this is a query-based URL, preserve query parameters
        if let originalURL = originalRequest.url?.absoluteString,
           originalURL.contains("?") {
            return "https://oldschool.runescape.wiki/\(assetPath)?\(originalRequest.url?.query ?? "")"
        }
        
        // Handle external domains
        if assetPath.contains("cdn.") {
            return "https://\(assetPath)"
        }
        
        // Default: wiki resource
        return "https://oldschool.runescape.wiki/\(assetPath)"
    }
    
    // MARK: - Web Archive Request Handler
    
    private func handleWebArchiveRequest(urlSchemeTask: WKURLSchemeTask, url: URL, assetPath: String) {
        // For web archives, we don't serve individual resources through the scheme handler
        // Instead, web archives are loaded via loadFileURL in the WebView itself
        // This handler just provides a fallback error for any unexpected requests
        print("⚠️ IOSAssetHandler: Unexpected web archive scheme request: \(assetPath)")
        print("⚠️ IOSAssetHandler: Web archives should be loaded via loadFileURL, not scheme handlers")
        
        completeTask(urlSchemeTask, withError: NSError(
            domain: "IOSAssetHandler", 
            code: 501, 
            userInfo: [NSLocalizedDescriptionKey: "Web archive content should be loaded via loadFileURL"]
        ))
    }
    
    private func mimeTypeForExtension(_ extension: String) -> String {
        switch `extension`.lowercased() {
        case "css": return "text/css"
        case "js": return "application/javascript"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "svg": return "image/svg+xml"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        case "json": return "application/json"
        default: return "application/octet-stream"
        }
    }
    
    /// Enhanced diagnostics: Determine resource type for better logging
    private func determineResourceType(from url: String) -> String {
        if url.contains(".png") || url.contains(".jpg") || url.contains(".jpeg") || url.contains(".gif") || url.contains(".svg") {
            return "Image"
        } else if url.contains(".ttf") || url.contains(".woff") || url.contains(".otf") {
            return "Font"
        } else if url.contains(".css") {
            return "CSS"
        } else if url.contains(".js") {
            return "JavaScript"
        } else if url.contains("load.php") || url.hasSuffix(".php") {
            return "MediaWiki Resource"
        } else if url.contains("cdn.") {
            return "External CDN Resource"
        } else {
            return "Unknown Resource"
        }
    }
    
    // MARK: - Image Proxying Methods
    
    private func handleImageProxy(urlSchemeTask: WKURLSchemeTask, assetPath: String) {
        // Convert custom scheme image request to original wiki URL
        let originalImageURL = "https://oldschool.runescape.wiki/\(assetPath)"
        
        guard let url = URL(string: originalImageURL) else {
            print("❌ IOSAssetHandler: Invalid image URL: \(originalImageURL)")
            self.completeTask(urlSchemeTask, withError: NSError(domain: "IOSAssetHandler", code: 400, userInfo: nil))
            return
        }
        
        print("🌐 IOSAssetHandler: Proxying image through proxy system: \(originalImageURL)")
        
        // Use NetworkManager instead of URLSession.shared to route through proxy system
        Task { [weak self] in
            guard let self = self else { return }
            
            do {
                let (data, response) = try await NetworkManager.shared.performDataRequest(url: url, retryCount: 2)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("❌ IOSAssetHandler: Invalid response type for image: \(originalImageURL)")
                    await MainActor.run {
                        self.completeTask(urlSchemeTask, withError: NSError(domain: "IOSAssetHandler", code: 500, userInfo: nil))
                    }
                    return
                }
                
                print("✅ IOSAssetHandler: Image fetched successfully through proxy (\(data.count) bytes)")
                
                // Determine MIME type based on file extension
                let mimeType: String
                if assetPath.contains(".png") {
                    mimeType = "image/png"
                } else if assetPath.contains(".jpg") || assetPath.contains(".jpeg") {
                    mimeType = "image/jpeg"  
                } else if assetPath.contains(".gif") {
                    mimeType = "image/gif"
                } else if assetPath.contains(".svg") {
                    mimeType = "image/svg+xml"
                } else {
                    mimeType = httpResponse.mimeType ?? "image/png"
                }
                
                // Create response with proper headers
                guard let requestUrl = urlSchemeTask.request.url,
                      let customResponse = HTTPURLResponse(
                    url: requestUrl,
                    statusCode: httpResponse.statusCode,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Type": mimeType,
                        "Content-Length": "\(data.count)",
                        "Cache-Control": "max-age=3600"
                    ]
                ) else {
                    print("❌ Failed to create HTTP response for image proxy")
                    await MainActor.run {
                        self.completeTask(urlSchemeTask, withError: NSError(domain: "ImageProxy", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create HTTP response"]))
                    }
                    return
                }
                
                await MainActor.run {
                    self.completeTask(urlSchemeTask, withResponse: customResponse, data: data)
                    print("📱 iOS Image Proxy: Served \(assetPath) (\(data.count) bytes)")
                }
                
            } catch {
                print("❌ IOSAssetHandler: Image NetworkManager fetch failed for \(originalImageURL): \(error.localizedDescription)")
                await MainActor.run {
                    self.completeTask(urlSchemeTask, withError: error)
                }
            }
        }
    }
    
    private func handleMediaWikiProxy(urlSchemeTask: WKURLSchemeTask, assetPath: String) {
        // Convert custom scheme MediaWiki request to original wiki URL
        let originalURL: String
        if let queryString = urlSchemeTask.request.url?.query {
            originalURL = "https://oldschool.runescape.wiki/\(assetPath)?\(queryString)"
        } else {
            originalURL = "https://oldschool.runescape.wiki/\(assetPath)"
        }
        
        guard let url = URL(string: originalURL) else {
            print("❌ IOSAssetHandler: Invalid MediaWiki URL: \(originalURL)")
            self.completeTask(urlSchemeTask, withError: NSError(domain: "IOSAssetHandler", code: 400, userInfo: nil))
            return
        }
        
        print("🌐 IOSAssetHandler: Proxying MediaWiki resource through proxy system: \(originalURL)")
        
        // Use NetworkManager instead of URLSession.shared to route through proxy system
        Task { [weak self] in
            guard let self = self else { return }
            
            do {
                let (data, response) = try await NetworkManager.shared.performDataRequest(url: url, retryCount: 2)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("❌ IOSAssetHandler: Invalid response type for MediaWiki resource: \(originalURL)")
                    await MainActor.run {
                        self.completeTask(urlSchemeTask, withError: NSError(domain: "IOSAssetHandler", code: 500, userInfo: nil))
                    }
                    return
                }
                
                print("✅ IOSAssetHandler: MediaWiki resource fetched successfully through proxy (\(data.count) bytes)")
                
                // Use original response MIME type or default to JavaScript
                let mimeType = httpResponse.mimeType ?? "application/javascript"
                
                // Create response with proper headers
                guard let requestUrl = urlSchemeTask.request.url,
                      let customResponse = HTTPURLResponse(
                    url: requestUrl,
                    statusCode: httpResponse.statusCode,
                    httpVersion: "HTTP/1.1", 
                    headerFields: [
                        "Content-Type": mimeType,
                        "Content-Length": "\(data.count)",
                        "Cache-Control": "max-age=3600"
                    ]
                ) else {
                    print("❌ Failed to create HTTP response for MediaWiki proxy")
                    await MainActor.run {
                        self.completeTask(urlSchemeTask, withError: NSError(domain: "IOSAssetHandler", code: 500, userInfo: nil))
                    }
                    return
                }
                
                await MainActor.run {
                    self.completeTask(urlSchemeTask, withResponse: customResponse, data: data)
                    print("📱 iOS MediaWiki Proxy: Served \(assetPath) (\(data.count) bytes)")
                }
                
            } catch {
                print("❌ IOSAssetHandler: MediaWiki NetworkManager fetch failed for \(originalURL): \(error.localizedDescription)")
                await MainActor.run {
                    self.completeTask(urlSchemeTask, withError: error)
                }
            }
        }
    }
}

struct ArticleWebView: UIViewRepresentable {
    @ObservedObject var viewModel: ArticleViewModel
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var themeManager: osrsThemeManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    // Optional external navigation delegate for table preview generation
    let navigationDelegate: WKNavigationDelegate?
    
    init(viewModel: ArticleViewModel, navigationDelegate: WKNavigationDelegate? = nil) {
        self.viewModel = viewModel
        self.navigationDelegate = navigationDelegate
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        
        // Configure user content controller for JavaScript bridge
        let userContentController = WKUserContentController()
        
        // Add clipboard bridge script
        let clipboardScript = WKUserScript(
            source: createClipboardBridgeScript(),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: osrsWebKitSecurityPolicy.isUserScriptMainFrameOnly(name: "clipboardBridge")
        )
        userContentController.addUserScript(clipboardScript)
        
        // Add render timeline logging script
        let renderTimelineScript = WKUserScript(
            source: createRenderTimelineScript(),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: osrsWebKitSecurityPolicy.isUserScriptMainFrameOnly(name: "renderTimeline")
        )
        userContentController.addUserScript(renderTimelineScript)

        // Capture article link clicks before WebKit mutates the source WebView.
        let internalLinkRoutingScript = WKUserScript(
            source: createInternalLinkRoutingScript(),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: osrsWebKitSecurityPolicy.isUserScriptMainFrameOnly(name: "internalLinkRouting")
        )
        userContentController.addUserScript(internalLinkRoutingScript)
        
        // Add mobile optimization script
        let mobileOptimizationScript = WKUserScript(
            source: createMobileOptimizationScript(),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: osrsWebKitSecurityPolicy.isUserScriptMainFrameOnly(name: "mobileOptimization")
        )
        userContentController.addUserScript(mobileOptimizationScript)
        
        // Note: MapLibre bridge loaded via external JS file (Option B) for cross-platform compatibility
        
        if osrsWebKitSecurityPolicy.isDiagnosticModeEnabled {
            let debuggingScript = WKUserScript(
                source: createSafariComparisonScript(),
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            userContentController.addUserScript(debuggingScript)
        }
        
        // Register message handlers
        for handlerName in osrsWebKitSecurityPolicy.enabledHandlerNames {
            userContentController.add(context.coordinator, contentWorld: .page, name: handlerName)
        }
        
        configuration.userContentController = userContentController
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        
        // Register custom scheme handler for app assets (fonts, CSS, icons)
        let assetHandler = IOSAssetHandler()
        let customScheme = "app-assets"
        configuration.setURLSchemeHandler(assetHandler, forURLScheme: customScheme)
        UserDefaults.standard.set(customScheme, forKey: "WKURLSchemeHandler_Scheme")
        print("✅ Registered \(customScheme):// handler for app assets")
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        // Use external navigation delegate if provided, otherwise use viewModel
        // Set navigation delegate with proper logging to verify delegate assignment
        let finalDelegate = navigationDelegate ?? viewModel
        webView.navigationDelegate = finalDelegate
        
        if let customDelegate = navigationDelegate {
            let delegateType = String(describing: type(of: customDelegate))
            print("🔗 ArticleWebView: Using custom navigation delegate: \(delegateType)")
        } else {
            print("🔗 ArticleWebView: Using default viewModel as navigation delegate")
        }
        
        // Verify delegate was set correctly
        if webView.navigationDelegate != nil {
            let actualDelegate = String(describing: type(of: webView.navigationDelegate!))
            print("✅ ArticleWebView: Navigation delegate successfully set to: \(actualDelegate)")
        } else {
            print("❌ ArticleWebView: Navigation delegate is nil after assignment!")
        }
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.bounces = true
        webView.scrollView.contentInset.bottom = 64
        webView.scrollView.verticalScrollIndicatorInsets.bottom = 64
        webView.isOpaque = false
        webView.backgroundColor = UIColor.clear
        webView.accessibilityIdentifier = "article_web_view"
        
        if #available(iOS 16.4, *) {
            webView.isInspectable = osrsWebKitSecurityPolicy.isWebViewInspectionEnabled
        }
        
        // Set up gesture recognizers for iOS-specific interactions
        setupGestureRecognizers(webView: webView)
        
        // Configure WebView for horizontal gesture support
        osrsWebViewBridge.configureWebView(webView)
        
        // Enable find-in-page interaction (iOS 16+)
        if #available(iOS 16.0, *) {
            webView.isFindInteractionEnabled = true
        }
        
        // Connect webView to viewModel
        viewModel.setWebView(webView)
        applyDynamicTypeScale(to: webView)
        
        // Initialize map handler with the webView
        context.coordinator.setupMapHandler(webView: webView)
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        applyDynamicTypeScale(to: webView)
        // Apply modern OSRS theme changes
        viewModel.injectThemeColors(themeManager)
    }

    private func applyDynamicTypeScale(to webView: WKWebView) {
        let scale = osrsArticleDynamicTypeScaling.scale(for: dynamicTypeSize)
        let requiresWebReflow = osrsArticleDynamicTypeScaling.requiresWebReflow(for: dynamicTypeSize)
        webView.pageZoom = requiresWebReflow ? 1.0 : scale
        viewModel.setAccessibilityReflowEnabled(requiresWebReflow, textScale: requiresWebReflow ? scale : 1.0)
#if DEBUG
        webView.accessibilityValue = String(format: "article_dynamic_type_scale=%.2f", Double(scale))
#endif
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        print("🧹 ArticleWebView: Dismantling WebView")
        
        // Critical: Clean up all message handlers and resources
        coordinator.cleanup()
        
        // Stop any ongoing navigation
        uiView.stopLoading()
        
        // Additional WebView cleanup
        uiView.scrollView.delegate = nil
        uiView.navigationDelegate = nil
        uiView.uiDelegate = nil
        
        print("✅ ArticleWebView: WebView dismantled successfully")
    }
    
    private func setupGestureRecognizers(webView: WKWebView) {
        // Add any iOS-specific gesture handling here
        // For example, double-tap to zoom, long press for context menu, etc.
    }
    
    private func createClipboardBridgeScript() -> String {
        return """
        (function() {
            // Create clipboard bridge similar to Android implementation
            window.ClipboardBridge = {
                writeText: function(text) {
                    window.webkit.messageHandlers.clipboardBridge.postMessage({
                        action: 'writeText',
                        text: text
                    });
                    return true;
                },
                
                readText: function() {
                    window.webkit.messageHandlers.clipboardBridge.postMessage({
                        action: 'readText'
                    });
                    return '';
                }
            };
            
            // Override navigator.clipboard for iframe compatibility
            if (navigator.clipboard) {
                const originalWriteText = navigator.clipboard.writeText;
                navigator.clipboard.writeText = function(text) {
                    return window.ClipboardBridge.writeText(text);
                };
            }
        })();
        """
    }
    
    private func createRenderTimelineScript() -> String {
        return """
        (function() {
            window.RenderTimeline = {
                log: function(message) {
                    window.webkit.messageHandlers.renderTimeline.postMessage({
                        message: message,
                        timestamp: Date.now()
                    });
                }
            };
            
            // Log key render events
            document.addEventListener('DOMContentLoaded', function() {
                window.RenderTimeline.log('Event: DOMContentLoaded');
            });
            
            window.addEventListener('load', function() {
                window.RenderTimeline.log('Event: WindowLoad');
            });
        })();
        """
    }

    private func createInternalLinkRoutingScript() -> String {
        return """
        (function() {
            function routeInternalArticleLink(event) {
                const rawTarget = event.target;
                const target = rawTarget && rawTarget.nodeType === 3 ? rawTarget.parentElement : rawTarget;
                if (!target || typeof target.closest !== 'function') {
                    return;
                }

                const link = target.closest('a');
                if (!link) {
                    return;
                }

                const routedHref = link.getAttribute('data-osrs-article-href') || link.href;
                if (!routedHref) {
                    return;
                }

                let url;
                try {
                    url = new URL(routedHref, document.baseURI);
                } catch (_) {
                    return;
                }

                const pageName = url.pathname.substring('/w/'.length).toLowerCase();
                const isArticlePath = url.pathname.startsWith('/w/') &&
                    pageName.length > 0 &&
                    !pageName.startsWith('file:') &&
                    !pageName.startsWith('media:') &&
                    !pageName.startsWith('special:');

                if ((url.hostname === 'oldschool.runescape.wiki' ||
                     url.hostname === 'runescape.wiki' ||
                     (url.protocol === 'app-assets:' && url.hostname === 'localhost')) &&
                    isArticlePath) {
                    event.preventDefault();
                    event.stopPropagation();
                    event.stopImmediatePropagation();

                    window.webkit.messageHandlers.linkHandler.postMessage({
                        action: 'navigate',
                        url: url.href,
                        title: link.textContent || link.title || ''
                    });
                }
            }

            document.addEventListener('click', routeInternalArticleLink, true);
        })();
        """
    }
    
    private func createMobileOptimizationScript() -> String {
        return """
        (function() {
            // Mobile-specific optimizations
            
            // Prevent text selection on buttons and interactive elements
            const style = document.createElement('style');
            style.textContent = `
                button, .button, [role="button"], input[type="button"], input[type="submit"] {
                    -webkit-user-select: none;
                    user-select: none;
                    -webkit-touch-callout: none;
                }
                
                img {
                    -webkit-touch-callout: none;
                    -webkit-user-select: none;
                    user-select: none;
                }
                
                /* Improve touch targets */
                a, button, .button, [role="button"] {
                    min-height: 44px;
                    min-width: 44px;
                }
                
                /* Optimize tables for mobile */
                .wikitable {
                    font-size: 14px;
                    width: 100%;
                    table-layout: auto;
                }
                
                /* Handle horizontal overflow at container level */
                .collapsible-content {
                    overflow-x: auto;
                    -webkit-overflow-scrolling: touch;
                }
                
                /* Improve readability */
                .mw-parser-output {
                    line-height: 1.6;
                    font-size: 16px;
                }
            `;
            document.head.appendChild(style);
            
        })();
        """
    }
    
    // Note: MapLibre bridge now loaded exclusively via external JS file (Option B)
    // This eliminates redundancy and provides cleaner cross-platform compatibility
    
    private func createSafariComparisonScript() -> String {
        return """
        (function() {
            // Safari vs WKWebView debugging script
            window.SafariDebugger = {
                analyzeEnvironment: function() {
                    const results = {
                        userAgent: navigator.userAgent,
                        viewport: {
                            innerWidth: window.innerWidth,
                            innerHeight: window.innerHeight,
                            devicePixelRatio: window.devicePixelRatio,
                            screen: { 
                                width: screen.width, 
                                height: screen.height,
                                availWidth: screen.availWidth,
                                availHeight: screen.availHeight
                            }
                        },
                        mediaQueries: {
                            mobile: window.matchMedia('(max-width: 768px)').matches,
                            tablet: window.matchMedia('(min-width: 769px) and (max-width: 1024px)').matches,
                            desktop: window.matchMedia('(min-width: 1025px)').matches,
                            retina: window.matchMedia('(-webkit-min-device-pixel-ratio: 2)').matches
                        },
                        fonts: {
                            defaultFamily: getComputedStyle(document.body).fontFamily,
                            defaultSize: getComputedStyle(document.body).fontSize
                        },
                        tables: this.analyzeTableRendering()
                    };
                    
                    window.webkit.messageHandlers.safariDebugger.postMessage({
                        type: 'environmentAnalysis',
                        data: results
                    });
                },
                
                analyzeTableRendering: function() {
                    const tables = document.querySelectorAll('table.wikitable');
                    const tableAnalysis = [];
                    
                    tables.forEach((table, index) => {
                        if (index < 3) { // Analyze first 3 tables
                            const tableStyles = window.getComputedStyle(table);
                            const cells = table.querySelectorAll('td');
                            const cellAnalysis = [];
                            
                            cells.forEach((cell, cellIndex) => {
                                if (cellIndex < 10) { // First 10 cells
                                    const cellStyles = window.getComputedStyle(cell);
                                    const rect = cell.getBoundingClientRect();
                                    const text = cell.textContent;
                                    
                                    // Test if text would wrap
                                    const testSpan = document.createElement('span');
                                    testSpan.style.cssText = 'position: absolute; visibility: hidden; white-space: nowrap; font-family: inherit; font-size: inherit;';
                                    testSpan.textContent = text;
                                    document.body.appendChild(testSpan);
                                    const singleLineWidth = testSpan.getBoundingClientRect().width;
                                    document.body.removeChild(testSpan);
                                    
                                    cellAnalysis.push({
                                        cellIndex: cellIndex,
                                        text: text.substring(0, 50),
                                        textLength: text.length,
                                        cellWidth: rect.width,
                                        cellHeight: rect.height,
                                        singleLineWidth: singleLineWidth,
                                        isWrapping: singleLineWidth > rect.width && text.length > 10,
                                        styles: {
                                            width: cellStyles.width,
                                            maxWidth: cellStyles.maxWidth,
                                            minWidth: cellStyles.minWidth,
                                            wordWrap: cellStyles.wordWrap,
                                            overflowWrap: cellStyles.overflowWrap,
                                            wordBreak: cellStyles.wordBreak,
                                            whiteSpace: cellStyles.whiteSpace,
                                            textSizeAdjust: cellStyles.webkitTextSizeAdjust || cellStyles.textSizeAdjust,
                                            display: cellStyles.display,
                                            fontSize: cellStyles.fontSize,
                                            fontFamily: cellStyles.fontFamily
                                        }
                                    });
                                }
                            });
                            
                            tableAnalysis.push({
                                tableIndex: index,
                                cellsAnalyzed: cellAnalysis.length,
                                wrappingCells: cellAnalysis.filter(c => c.isWrapping).length,
                                tableStyles: {
                                    width: tableStyles.width,
                                    tableLayout: tableStyles.tableLayout,
                                    borderCollapse: tableStyles.borderCollapse,
                                    wordWrap: tableStyles.wordWrap,
                                    overflowWrap: tableStyles.overflowWrap
                                },
                                cells: cellAnalysis
                            });
                        }
                    });
                    
                    return {
                        tablesFound: tables.length,
                        tablesAnalyzed: tableAnalysis.length,
                        totalWrappingCells: tableAnalysis.reduce((sum, table) => sum + table.wrappingCells, 0),
                        analysis: tableAnalysis
                    };
                }
            };
            
            // Run analysis after page load
            if (document.readyState === 'complete') {
                setTimeout(() => window.SafariDebugger.analyzeEnvironment(), 1000);
            } else {
                window.addEventListener('load', () => {
                    setTimeout(() => window.SafariDebugger.analyzeEnvironment(), 1000);
                });
            }
        })();
        """
    }
    
    class Coordinator: NSObject, WKScriptMessageHandler {
        let parent: ArticleWebView
        private var mapHandler: osrsNativeMapHandler?
        private weak var webView: WKWebView?
        
        init(_ parent: ArticleWebView) {
            self.parent = parent
        }
        
        func setupMapHandler(webView: WKWebView) {
            self.webView = webView
            mapHandler = osrsNativeMapHandler(webView: webView)
            print("✅ iOS ArticleWebView: Map handler initialized")
        }
        
        func cleanup() {
            print("🧹 ArticleWebView.Coordinator: Starting cleanup")
            
            // Clean up map handler resources
            mapHandler?.cleanup()
            mapHandler = nil
            
            // Remove all script message handlers to prevent memory leaks
            if let webView = webView {
                let userContentController = webView.configuration.userContentController
                
                for handlerName in osrsWebKitSecurityPolicy.enabledHandlerNames {
                    userContentController.removeScriptMessageHandler(forName: handlerName, contentWorld: .page)
                }
                
                // Remove all user scripts to free memory
                userContentController.removeAllUserScripts()
                
                print("✅ ArticleWebView.Coordinator: Removed all script message handlers and user scripts")
            }
            
            // Clear weak reference
            webView = nil
            
            print("✅ ArticleWebView.Coordinator: Cleanup completed")
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            guard osrsWebKitSecurityPolicy.canAcceptScriptMessage(name: message.name, frameInfo: message.frameInfo) else {
#if DEBUG
                print("⚠️ ArticleWebView.Coordinator: Rejected script message '\(message.name)' from untrusted frame or origin")
#endif
                return
            }
            
            switch message.name {
            case "clipboardBridge":
                handleClipboardMessage(body)
            case "renderTimeline":
                handleRenderTimelineMessage(body)
            case "linkHandler":
                handleLinkMessage(body)
            case "mapBridge":
                handleMapBridgeMessage(body)
            case "safariDebugger":
                handleSafariDebuggerMessage(body)
            default:
                break
            }
        }
        
        private func handleClipboardMessage(_ body: [String: Any]) {
            guard let action = body["action"] as? String else { return }
            
            switch action {
            case "writeText":
                if let text = body["text"] as? String {
                    UIPasteboard.general.string = text
                    print("Clipboard: Successfully copied text via iOS bridge")
                }
            case "readText":
                let text = UIPasteboard.general.string ?? ""
                // Note: Reading clipboard on iOS requires returning the value differently
                // This would need to be implemented with a callback mechanism
                print("Clipboard: Read text request (iOS has limitations)")
            default:
                break
            }
        }
        
        private func handleRenderTimelineMessage(_ body: [String: Any]) {
            if let message = body["message"] as? String,
               let timestamp = body["timestamp"] as? Double {
                let timeString = DateFormatter.timeFormatter.string(from: Date())
                print("📊 [\(timeString)] 🎯 RenderTimeline: \(message)")
                
                // Handle specific render events
                if message.hasPrefix("Event: StylingScriptsComplete") {
                    let loadGeneration = Self.loadGeneration(from: message)
                    // ANDROID PARITY: JavaScript is ready - now wait for body reveal completion
                    DispatchQueue.main.async {
                        // TIMING MEASUREMENT: Record JavaScript completion time
                        let jsCompletionTime = Date()
                        let jsCompletionTimeString = DateFormatter.timeFormatter.string(from: jsCompletionTime)
                        
                        if let progressTime = self.parent.viewModel.progressCompletionTime {
                            let delay = jsCompletionTime.timeIntervalSince(progressTime)
                            self.parent.viewModel.lastMeasuredDelay = delay
                            print("📊 [\(jsCompletionTimeString)] 🟢 JAVASCRIPT COMPLETE: WebKit-to-JS delay: \(String(format: "%.3f", delay))s")
                        }
                        
                        // Trigger body reveal and complete progress when it's done
                        self.parent.viewModel.completeLoadingWithBodyReveal(loadGeneration: loadGeneration)
                    }
                } else {
                    print("📊 [\(timeString)] 📝 OTHER JS EVENT: \(message)")
                }
            }
        }

        private static func loadGeneration(from message: String) -> Int? {
            let prefix = "Event: StylingScriptsComplete:"
            guard message.hasPrefix(prefix) else {
                return nil
            }
            return Int(message.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines))
        }

        private func handleLinkMessage(_ body: [String: Any]) {
            guard let action = body["action"] as? String,
                  action == "navigate",
                  let urlString = body["url"] as? String,
                  let url = URL(string: urlString) else { return }
            guard let articleURL = osrsArticleLinkRouter.appArticleURL(for: url) else { return }

            webView?.stopLoading()

            DispatchQueue.main.async {
                self.parent.appState.routeInternalArticleLink(articleURL)
            }
        }
        
        private func handleMapBridgeMessage(_ body: [String: Any]) {
            guard let action = body["action"] as? String else { 
                print("🔴 MapBridge: Received message with no action: \(body)")
                return 
            }
            
            print("🟢 MapBridge: Received action '\(action)' with data: \(body)")
            
            switch action {
            case "onMapPlaceholderMeasured":
                if let id = body["id"] as? String,
                   let rectJson = body["rectJson"] as? String,
                   let mapDataJson = body["mapDataJson"] as? String {
                    mapHandler?.onMapPlaceholderMeasured(id: id, rectJson: rectJson, mapDataJson: mapDataJson)
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
                
            case "log":
                if let message = body["message"] as? String {
                    mapHandler?.log(message: message)
                }
                
            default:
                print("❌ iOS ArticleWebView: Unknown map bridge action: \(action)")
            }
        }
        
        private func handleSafariDebuggerMessage(_ body: [String: Any]) {
            guard osrsWebKitSecurityPolicy.isDiagnosticModeEnabled else { return }
            guard let type = body["type"] as? String,
                  let data = body["data"] as? [String: Any] else { return }
            
            switch type {
            case "environmentAnalysis":
                print("🔍 Safari Debugger: Environment Analysis Results")
                print("=" + String(repeating: "=", count: 50))
                
                if let userAgent = data["userAgent"] as? String {
                    print("📱 User Agent: \(userAgent)")
                }
                
                if let viewport = data["viewport"] as? [String: Any] {
                    print("📐 Viewport: \(viewport)")
                }
                
                if let mediaQueries = data["mediaQueries"] as? [String: Any] {
                    print("📺 Media Queries: \(mediaQueries)")
                }
                
                if let fonts = data["fonts"] as? [String: Any] {
                    print("🔤 Fonts: \(fonts)")
                }
                
                if let tables = data["tables"] as? [String: Any] {
                    print("📊 Tables Analysis:")
                    if let tablesFound = tables["tablesFound"] as? Int,
                       let totalWrappingCells = tables["totalWrappingCells"] as? Int {
                        print("  - Tables found: \(tablesFound)")
                        print("  - Total wrapping cells: \(totalWrappingCells)")
                    }
                    
                    if let analysis = tables["analysis"] as? [[String: Any]] {
                        for (index, tableData) in analysis.enumerated() {
                            if let wrappingCells = tableData["wrappingCells"] as? Int,
                               let cellsAnalyzed = tableData["cellsAnalyzed"] as? Int {
                                print("  - Table \(index): \(wrappingCells)/\(cellsAnalyzed) cells wrapping")
                            }
                        }
                    }
                }
                
                print("=" + String(repeating: "=", count: 50))
                
                // Save the results to a file for comparison with Safari web results
                DispatchQueue.global(qos: .background).async {
                    do {
                        let jsonData = try JSONSerialization.data(withJSONObject: data, options: .prettyPrinted)
                        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                        let fileURL = documentsPath.appendingPathComponent("wkwebview-analysis.json")
                        try jsonData.write(to: fileURL)
                        print("💾 WKWebView analysis saved to: \(fileURL.path)")
                    } catch {
                        print("❌ Failed to save WKWebView analysis: \(error)")
                    }
                }
                
            default:
                print("🔍 Safari Debugger: Unknown message type: \(type)")
            }
        }
    }
}

#Preview {
    ArticleWebView(viewModel: ArticleViewModel(pageUrl: URL(string: "about:blank")!))
        .environmentObject(AppState())
        .environmentObject(osrsThemeManager.preview)
}
