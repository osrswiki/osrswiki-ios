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
        min(max(48 * toolbarScale(for: dynamicTypeSize), 48), 68)
    }

    static func requiresWebReflow(for dynamicTypeSize: DynamicTypeSize) -> Bool {
        dynamicTypeSize.isAccessibilitySize
    }
}

// MARK: - iOS Asset Handler (matches Android's appassets.androidplatform.net)
class IOSAssetHandler: NSObject, WKURLSchemeHandler {
    private let sourceArticleURL: URL

    init(sourceArticleURL: URL = URL(string: "https://oldschool.runescape.wiki/")!) {
        self.sourceArticleURL = sourceArticleURL
        super.init()
    }

    /// Historical HTML documents linked a few stylesheets from `styles/` after they
    /// moved under `web/`. Resolve those aliases before the bundle walk so a
    /// prepared article does not wait on 404 fallbacks.
    struct WikiMediaSchemePayload {
        let status: Int
        let headers: [String: String]
        let body: Data
    }

    /// WKWebView media requests Range. Serving 200 + full body for a custom-scheme
    /// audio URL can leave the infobox player on its loading spinner forever.
    /// Empty packaged bytes are a miss (nil), not a successful empty 200.
    static func wikiMediaSchemePayload(
        requestURL: URL,
        rangeHeader: String?,
        data: Data,
        contentType: String
    ) -> WikiMediaSchemePayload? {
        guard !data.isEmpty else { return nil }
        var headers: [String: String] = [
            "Content-Type": contentType,
            "Accept-Ranges": "bytes"
        ]
        let total = data.count
        guard let rangeHeader,
              let byteRange = parseByteRange(rangeHeader, totalLength: total) else {
            headers["Content-Length"] = "\(total)"
            return WikiMediaSchemePayload(status: 200, headers: headers, body: data)
        }
        let slice = data.subdata(in: byteRange.lowerBound..<byteRange.upperBound)
        let last = byteRange.upperBound - 1
        headers["Content-Range"] = "bytes \(byteRange.lowerBound)-\(last)/\(total)"
        headers["Content-Length"] = "\(slice.count)"
        return WikiMediaSchemePayload(status: 206, headers: headers, body: slice)
    }

    static func parseByteRange(_ header: String, totalLength: Int) -> Range<Int>? {
        let trimmed = header.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("bytes=") else { return nil }
        let spec = trimmed.dropFirst("bytes=".count)
        let parts = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard let startToken = parts.first else { return nil }
        let start = Int(startToken) ?? 0
        guard start >= 0, start < totalLength else { return nil }
        let end: Int
        if parts.count > 1, !parts[1].isEmpty, let parsedEnd = Int(parts[1]) {
            end = min(parsedEnd, totalLength - 1)
        } else {
            end = totalLength - 1
        }
        guard end >= start else { return nil }
        return start..<(end + 1)
    }

    static func canonicalAssetPath(_ path: String) -> String {
        switch path {
        case "styles/collapsible_tables.css":
            return "web/collapsible_tables.css"
        case "styles/infobox_switcher.css":
            return "web/switch_infobox_styles.css"
        case "gadget_calc_core.js":
            return "js/mediawiki/gadget_calc_core.js"
        case "osrs_calculator_runtime.js":
            return "web/osrs_calculator_runtime.js"
        case "osrs_native_calc_indoc.js":
            return "web/osrs_native_calc_indoc.js"
        default:
            return path
        }
    }
    
    // MARK: - Task State Management (Enhanced to prevent WebKit NSException crashes)
    
    // Task state tracking with generation counter to prevent race conditions
    private struct TaskInfo {
        let id: ObjectIdentifier
        let generation: Int
        let startTime: Date
    }
    
    private var activeTasks: [ObjectIdentifier: TaskInfo] = [:]
    private var transportHandles: [ObjectIdentifier: osrsAssetTransportCancellationHandle] = [:]
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

            if osrsWikiWebViewUrl.shouldProxy(url) {
                let wikiURL = osrsWikiWebViewUrl.rewriteToWiki(url)
                print("🌐 IOSAssetHandler: Proxying wiki calculator/API request: \(wikiURL.absoluteString)")
                if url.path.contains("/images/") {
                    NSLog(
                        "osrsImagesLookup: shouldProxy=1 request=%@ wiki=%@ method=%@ range=%@ mainThread=%d",
                        url.absoluteString,
                        wikiURL.absoluteString,
                        urlSchemeTask.request.httpMethod ?? "GET",
                        urlSchemeTask.request.value(forHTTPHeaderField: "Range") ?? "none",
                        Thread.isMainThread ? 1 : 0
                    )
                }
                self.fetchAndHandleExternalResource(
                    urlSchemeTask: urlSchemeTask,
                    originalURL: wikiURL.absoluteString,
                    shouldSave: false,
                    pageId: nil
                )
                return
            }

            if osrsArticleLinkRouter.isFloorNumberingSettingsURL(url) {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .showAppearanceSettings,
                        object: nil,
                        userInfo: ["highlightFloorNumbering": true]
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

            if let articleURL = osrsArticleLinkRouter.appArticleURL(for: url) {
                print("🔄 IOSAssetHandler: Intercepted app-assets article navigation: \(articleURL.absoluteString)")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .osrsInternalArticleLinkRequested,
                        object: nil,
                        userInfo: [
                            "url": articleURL,
                            "sourceArticleURL": self.sourceArticleURL
                        ]
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
        let rawPath = Self.canonicalAssetPath(
            url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        )
        
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
                if Self.shouldHandleExternalResource(assetPath: assetPath) {
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
        let transportHandle = transportHandles.removeValue(forKey: taskId)
        if let taskInfo = activeTasks[taskId] {
            activeTasks.removeValue(forKey: taskId)
            tasksLock.unlock()
            
            print("🛑 IOSAssetHandler: Task generation \(taskInfo.generation) stopped and removed")
        } else {
            tasksLock.unlock()
            print("⚠️ IOSAssetHandler: Task was already removed or never started")
        }
        
        completionSemaphore.signal()
        transportHandle?.cancel()
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
        transportHandles.removeValue(forKey: taskId)
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
        let transportHandles = Array(transportHandles.values)
        activeTasks.removeAll()
        self.transportHandles.removeAll()
        tasksLock.unlock()
        
        completionSemaphore.signal()
        transportHandles.forEach { $0.cancel() }
        
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
        let transportHandles = Array(transportHandles.values)
        activeTasks.removeAll()
        self.transportHandles.removeAll()
        tasksLock.unlock()
        
        completionSemaphore.signal()
        transportHandles.forEach { $0.cancel() }
        
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

    /// Bind the snapshot/browsing namespace used for cache-only and cache-first lookups.
    func setCacheLookupPageId(_ pageId: String?) {
        interceptorQueue.async {
            print("📦 IOSAssetHandler: Cache lookup pageId set to \(pageId ?? "nil")")
            self.currentSavePageId = pageId
            if pageId == nil {
                self.isInOfflineSaveMode = false
            }
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
    
    /// Get cached HTTP response (Android OfflineCacheInterceptor equivalent)
    private func getCachedHttpResponse(url: String, pageId: String?) -> (data: Data, response: HTTPURLResponse)? {
        print("🔍 IOSAssetHandler: Requesting cached response for URL: \(url), pageId: \(pageId ?? "nil")")
        let isImages = url.contains("/images/")
        if isImages {
            NSLog(
                "osrsImagesLookup: getCachedHttpResponse begin url=%@ pageId=%@ mainThread=%d",
                url,
                pageId ?? "nil",
                Thread.isMainThread ? 1 : 0
            )
        }
        
        // Use ProxyInterceptorService to access LocalHTTPServer cached responses
        if #available(iOS 17.0, *) {
            if let cachedResponse = ProxyInterceptorService.shared.getCachedAssetResponse(url: url, pageId: pageId) {
                print("✅ IOSAssetHandler: Retrieved cached response from LocalHTTPServer (\(cachedResponse.data.count) bytes)")
                if isImages {
                    NSLog(
                        "osrsImagesLookup: getCachedHttpResponse hit bytes=%d status=%d",
                        cachedResponse.data.count,
                        cachedResponse.response.statusCode
                    )
                }
                return cachedResponse
            } else {
                print("❌ IOSAssetHandler: No cached response found in LocalHTTPServer for: \(url)")
                if isImages {
                    NSLog("osrsImagesLookup: getCachedHttpResponse miss url=%@ pageId=%@", url, pageId ?? "nil")
                }
            }
        } else {
            print("⚠️ IOSAssetHandler: iOS 17+ required for proxy-based caching, falling back to legacy approach")
            if isImages {
                NSLog("osrsImagesLookup: getCachedHttpResponse skipped iOS<17")
            }
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
    static func shouldHandleExternalResource(assetPath: String) -> Bool {
        // Images and wiki-hosted audio (infobox transcodes live under images/)
        if assetPath.hasPrefix("images/") ||
           assetPath.contains(".png") || assetPath.contains(".jpg") ||
           assetPath.contains(".jpeg") || assetPath.contains(".gif") ||
           assetPath.contains(".svg") || assetPath.contains(".mp3") ||
           assetPath.contains(".ogg") || assetPath.contains(".oga") ||
           assetPath.contains(".m4a") {
            return true
        }
        
        // MediaWiki resources (load.php, api.php) and wiki CORS proxy (hiscores)
        if assetPath.hasSuffix(".php") ||
            assetPath.contains("load.php") ||
            assetPath.hasPrefix("cors/") ||
            assetPath.contains("/cors/") {
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
        let requestURL = urlSchemeTask.request.url
        let digest = LocalHTTPServer.cacheKeyForRequest(pageId: nil, method: "GET", url: originalURL)
        if assetPath.hasPrefix("images/") || originalURL.contains("/images/") {
            let encodedQuery = requestURL.flatMap {
                URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedQuery
            } ?? "nil"
            NSLog(
                "osrsImagesLookup: start request=%@ path=%@ encodedPath=%@ query=%@ encodedQuery=%@ wiki=%@ digest=%@ method=%@ range=%@ mainThread=%d",
                requestURL?.absoluteString ?? "nil",
                requestURL?.path ?? "nil",
                requestURL?.path(percentEncoded: true) ?? "nil",
                requestURL?.query ?? "nil",
                encodedQuery,
                originalURL,
                digest,
                urlSchemeTask.request.httpMethod ?? "GET",
                urlSchemeTask.request.value(forHTTPHeaderField: "Range") ?? "none",
                Thread.isMainThread ? 1 : 0
            )
        }
        
        // Check if we're in save mode and should cache this resource
        interceptorQueue.async {
            let shouldSave = self.isInOfflineSaveMode
            let localPageId = self.currentSavePageId
            var proxyPageId: String?
            if #available(iOS 17.0, *) {
                proxyPageId = ProxyInterceptorService.shared.getCurrentPageId()
            }

            var lookupPageIds: [String] = []
            if let localPageId, !lookupPageIds.contains(localPageId) {
                lookupPageIds.append(localPageId)
            }
            if let proxyPageId, !lookupPageIds.contains(proxyPageId) {
                lookupPageIds.append(proxyPageId)
            }
            let pageIdToUse = lookupPageIds.first
            if assetPath.hasPrefix("images/") || originalURL.contains("/images/") {
                NSLog(
                    "osrsImagesLookup: pageIds local=%@ proxy=%@ lookup=%@ saveMode=%d queueMainThread=%d",
                    localPageId ?? "nil",
                    proxyPageId ?? "nil",
                    lookupPageIds.isEmpty ? "nil" : lookupPageIds.joined(separator: ","),
                    shouldSave ? 1 : 0,
                    Thread.isMainThread ? 1 : 0
                )
            }
            if let pageIdToUse {
                print("🔍 [ENHANCED_DIAGNOSTICS] Using lookup pageId: \(pageIdToUse)")
            } else {
                print("🔍 [ENHANCED_DIAGNOSTICS] No explicit pageId; trying snapshot cache context")
            }

            let cachedResponse: (data: Data, response: HTTPURLResponse)?
            if lookupPageIds.isEmpty {
                cachedResponse = self.getCachedHttpResponse(url: originalURL, pageId: nil)
            } else {
                cachedResponse = lookupPageIds.lazy.compactMap {
                    self.getCachedHttpResponse(url: originalURL, pageId: $0)
                }.first
            }

            if let cachedResponse {
                print("✅ IOSAssetHandler: Serving \(originalURL) from cache (\(cachedResponse.data.count) bytes)")
                print("🔍 [ENHANCED_DIAGNOSTICS] Cache hit - Status: \(cachedResponse.response.statusCode)")

                let resourceType = self.determineResourceType(from: originalURL)
                if cachedResponse.response.statusCode != 200 {
                    print("⚠️ [ENHANCED_DIAGNOSTICS] Serving non-200 cached response: \(cachedResponse.response.statusCode)")
                    if let contentType = cachedResponse.response.value(forHTTPHeaderField: "Content-Type"),
                       contentType.contains("text/html") && (resourceType == "Image" || resourceType == "Font") {
                        print("🚨 [ENHANCED_DIAGNOSTICS] CACHE CORRUPTION: HTML cached as \(resourceType)!")
                    }
                }

                guard let scheme = self.osrsSchemeMatchedResponse(
                    for: urlSchemeTask,
                    upstream: cachedResponse.response,
                    data: cachedResponse.data
                ) else {
                    print("❌ IOSAssetHandler: Failed to wrap cached wiki response for \(originalURL)")
                    self.completeTask(
                        urlSchemeTask,
                        withError: NSError(
                            domain: "IOSAssetHandler",
                            code: cachedResponse.data.isEmpty ? 404 : 500,
                            userInfo: [NSLocalizedDescriptionKey: "Cached wiki media missing or unservable"]
                        )
                    )
                    return
                }
                self.completeTask(urlSchemeTask, withResponse: scheme.response, data: scheme.body)
                NSLog(
                    "osrsCalcProxy: status=%d bytes=%d request=%@ wiki=%@",
                    cachedResponse.response.statusCode,
                    cachedResponse.data.count,
                    urlSchemeTask.request.url?.absoluteString ?? "",
                    originalURL
                )
                return
            }

            print("❌ [ENHANCED_DIAGNOSTICS] Cache miss for: \(originalURL) (pageId: \(pageIdToUse ?? "nil"))")
            if assetPath.hasPrefix("images/") || originalURL.contains("/images/") {
                NSLog(
                    "osrsImagesLookup: handler cache miss wiki=%@ digest=%@ pageIds=%@",
                    originalURL,
                    digest,
                    lookupPageIds.isEmpty ? "nil" : lookupPageIds.joined(separator: ",")
                )
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
        launchTransport(for: urlSchemeTask) { [weak self] in
            guard let self = self else { return }
            
            do {
                let fetched = try await self.osrsFetchWikiResource(urlSchemeTask: urlSchemeTask, url: url, originalURL: originalURL)
                let data = fetched.data
                let response = fetched.response
                
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
                
                // NetworkManager/LocalHTTPServer owns page-scoped persistence and validates its
                // captured session token. A second handler-side write could outlive this WK task
                // and resurrect a namespace after the article disappears.
                print("🔍 [ENHANCED_DIAGNOSTICS] Persistence owned by request routing; handler direct write disabled (save=\(shouldSave), page=\(pageId ?? "none"))")

                guard let scheme = self.osrsSchemeMatchedResponse(
                    for: urlSchemeTask,
                    upstream: httpResponse,
                    data: data
                ) else {
                    print("❌ IOSAssetHandler: Failed to wrap wiki proxy response for \(originalURL)")
                    await MainActor.run {
                        self.completeTask(
                            urlSchemeTask,
                            withError: NSError(
                                domain: "IOSAssetHandler",
                                code: data.isEmpty ? 404 : 500,
                                userInfo: [NSLocalizedDescriptionKey: "Wiki media missing or unservable"]
                            )
                        )
                    }
                    return
                }
                
                // Serve to WebView
                await MainActor.run {
                    self.completeTask(urlSchemeTask, withResponse: scheme.response, data: scheme.body)
                    print("📱 IOSAssetHandler: Served external resource \(originalURL) (\(data.count) bytes)")
                    NSLog(
                        "osrsCalcProxy: status=%d bytes=%d request=%@ wiki=%@",
                        httpResponse.statusCode,
                        data.count,
                        urlSchemeTask.request.url?.absoluteString ?? "",
                        originalURL
                    )
                }
                
            } catch {
                print("❌ IOSAssetHandler: NetworkManager fetch failed for \(originalURL): \(error.localizedDescription)")
                await MainActor.run {
                    self.completeTask(urlSchemeTask, withError: error)
                }
            }
        }
    }

    private func osrsSchemeMatchedResponse(
        for urlSchemeTask: WKURLSchemeTask,
        upstream: HTTPURLResponse,
        data: Data
    ) -> (response: HTTPURLResponse, body: Data)? {
        guard let requestUrl = urlSchemeTask.request.url else {
            return nil
        }
        var contentType: String
        if let upstreamType = upstream.value(forHTTPHeaderField: "Content-Type"), !upstreamType.isEmpty {
            contentType = upstreamType
        } else if requestUrl.path.hasSuffix("/load.php") {
            contentType = "text/javascript; charset=utf-8"
        } else if requestUrl.path.hasSuffix("/api.php") {
            contentType = "application/json; charset=utf-8"
        } else {
            contentType = upstream.mimeType ?? "application/octet-stream"
        }
        let path = requestUrl.path.lowercased()
        let isAudio = contentType.lowercased().hasPrefix("audio/") ||
            path.contains(".mp3") || path.contains(".ogg") ||
            path.contains(".oga") || path.contains(".m4a")
        if isAudio {
            guard let payload = Self.wikiMediaSchemePayload(
                requestURL: requestUrl,
                rangeHeader: urlSchemeTask.request.value(forHTTPHeaderField: "Range"),
                data: data,
                contentType: contentType
            ),
            let response = HTTPURLResponse(
                url: requestUrl,
                statusCode: payload.status,
                httpVersion: "HTTP/1.1",
                headerFields: payload.headers
            ) else {
                return nil
            }
            return (response, payload.body)
        }
        var headers: [String: String] = ["Content-Type": contentType]
        headers["Content-Length"] = "\(data.count)"
        guard let response = HTTPURLResponse(
            url: requestUrl,
            statusCode: upstream.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) else {
            return nil
        }
        return (response, data)
    }
    
    private func osrsFetchWikiResource(
        urlSchemeTask: WKURLSchemeTask,
        url: URL,
        originalURL: String
    ) async throws -> (data: Data, response: URLResponse) {
        let method = (urlSchemeTask.request.httpMethod ?? "GET").uppercased()
        let requestBody = urlSchemeTask.request.httpBody
        let cacheBody = String(data: requestBody ?? Data(), encoding: .utf8) ?? ""
        let isCacheableCalculatorTraffic = originalURL.contains("/api.php")
            || originalURL.contains("/load.php")
        let isCalculatorTraffic = isCacheableCalculatorTraffic || originalURL.contains("/cors/")
        if isCacheableCalculatorTraffic,
           let cached = osrsCalculatorParseCache.read(method: method, url: originalURL, body: cacheBody),
           !cached.isEmpty,
           let cachedResponse = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": Self.osrsCalculatorCachedContentType(for: originalURL)]
           ) {
            let body = originalURL.contains("/load.php") ? osrsResourceLoaderScript.sanitize(cached) : cached
            return (body, cachedResponse)
        }
        if osrsTestEnvironment.forcesNetworkOfflineForUITests {
            if originalURL.contains("/images/") {
                NSLog("osrsImagesLookup: forcedOffline throw wiki=%@", originalURL)
            }
            throw Self.forcedOfflineError(for: originalURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("OSRSWiki-iOS-Calculator", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        if method == "POST" {
            request.httpBody = requestBody
            request.setValue(
                urlSchemeTask.request.value(forHTTPHeaderField: "Content-Type")
                    ?? "application/x-www-form-urlencoded; charset=UTF-8",
                forHTTPHeaderField: "Content-Type"
            )
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw NSError(
                domain: "osrsCalculatorProxy",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Calculator proxy HTTP \(http.statusCode)"]
            )
        }
        if isCacheableCalculatorTraffic, !data.isEmpty {
            let stored = originalURL.contains("/load.php") ? osrsResourceLoaderScript.sanitize(data) : data
            osrsCalculatorParseCache.write(method: method, url: originalURL, body: cacheBody, data: stored)
            return (stored, response)
        }
        if originalURL.contains("/load.php") {
            return (osrsResourceLoaderScript.sanitize(data), response)
        }
        return (data, response)
    }

    private static func osrsCalculatorCachedContentType(for url: String) -> String {
        if url.contains("/load.php") {
            return "text/javascript; charset=utf-8"
        }
        if url.contains("/api.php") {
            return "application/json; charset=utf-8"
        }
        return "text/plain; charset=utf-8"
    }

    /// Reconstruct original URL from asset path and request context
    static func reconstructOriginalURL(from assetPath: String, requestURL: URL?) -> String {
        if assetPath.contains("cdn.") {
            return "https://\(assetPath)"
        }

        let query = requestURL.flatMap { url -> String? in
            if let encoded = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery,
               !encoded.isEmpty {
                return encoded
            }
            return url.query
        }
        if let query, !query.isEmpty {
            return "https://oldschool.runescape.wiki/\(assetPath)?\(query)"
        }
        return "https://oldschool.runescape.wiki/\(assetPath)"
    }

    static func forcedOfflineError(for originalURL: String) -> NSError {
        if originalURL.contains("/images/") {
            return NSError(
                domain: "IOSAssetHandler",
                code: -1009,
                userInfo: [NSLocalizedDescriptionKey: "Forced offline: no cached wiki resource"]
            )
        }
        return NSError(
            domain: "osrsCalculatorProxy",
            code: -1009,
            userInfo: [NSLocalizedDescriptionKey: "Forced offline: no cached calculator resource"]
        )
    }

    private func reconstructOriginalURL(from assetPath: String, originalRequest: URLRequest) -> String {
        Self.reconstructOriginalURL(from: assetPath, requestURL: originalRequest.url)
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
        case "mp3": return "audio/mpeg"
        case "ogg", "oga": return "audio/ogg"
        case "m4a": return "audio/mp4"
        default: return "application/octet-stream"
        }
    }
    
    /// Enhanced diagnostics: Determine resource type for better logging
    private func determineResourceType(from url: String) -> String {
        if url.contains(".mp3") || url.contains(".ogg") || url.contains(".oga") || url.contains(".m4a") {
            return "Audio"
        } else if url.contains(".png") || url.contains(".jpg") || url.contains(".jpeg") || url.contains(".gif") || url.contains(".svg") {
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
        launchTransport(for: urlSchemeTask) { [weak self] in
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
        launchTransport(for: urlSchemeTask) { [weak self] in
            guard let self = self else { return }
            
            do {
                let fetched = try await self.osrsFetchWikiResource(urlSchemeTask: urlSchemeTask, url: url, originalURL: originalURL)
                let data = fetched.data
                let response = fetched.response
                
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

    private func launchTransport(
        for urlSchemeTask: WKURLSchemeTask,
        operation: @escaping @Sendable () async -> Void
    ) {
        let taskId = ObjectIdentifier(urlSchemeTask)
        let handle = osrsAssetTransportCancellationHandle()
        tasksLock.lock()
        guard activeTasks[taskId] != nil else {
            tasksLock.unlock()
            return
        }
        transportHandles[taskId] = handle
        tasksLock.unlock()

        let task = Task {
            guard !Task.isCancelled else { return }
            await operation()
            self.tasksLock.lock()
            if self.transportHandles[taskId] === handle {
                self.transportHandles.removeValue(forKey: taskId)
            }
            self.tasksLock.unlock()
        }
        handle.install(task)
    }
}

final class osrsAssetTransportCancellationHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var isCancelled = false

    func install(_ task: Task<Void, Never>) {
        lock.lock()
        if isCancelled {
            lock.unlock()
            task.cancel()
            return
        }
        self.task = task
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let task = self.task
        self.task = nil
        lock.unlock()
        task?.cancel()
    }
}

enum osrsArticleWebPanPolicy {
    static let backHorizontalThreshold: CGFloat = 36
    static let sidebarHorizontalThreshold: CGFloat = 100
    static let verticalThreshold: CGFloat = 32
    static let velocityThreshold: CGFloat = 100

    static func isPrimarilyHorizontal(velocity: CGPoint) -> Bool {
        abs(velocity.x) >= abs(velocity.y) * osrsInteractiveArticleSwipe.horizontalDominance &&
            abs(velocity.x) > 0
    }

    static func navigationDirection(
        translation: CGPoint,
        velocity: CGPoint
    ) -> HorizontalGestureDirection? {
        let dx = abs(translation.x)
        let dy = abs(translation.y)
        guard dx > dy,
              dy <= verticalThreshold,
              abs(velocity.x) > velocityThreshold else {
            return nil
        }
        if translation.x > 0, dx > backHorizontalThreshold {
            return .start
        }
        if translation.x < 0, dx > sidebarHorizontalThreshold {
            return .end
        }
        return nil
    }

    /// Convert a pan location sampled in WKScrollView (bounds origin = contentOffset)
    /// into the WKWebView visible-bounds point used by overlay hit-testing.
    static func webViewPoint(
        scrollViewLocation: CGPoint,
        contentOffset: CGPoint,
        zoomScale: CGFloat
    ) -> CGPoint {
        let scale = zoomScale > 0 ? zoomScale : 1
        return CGPoint(
            x: (scrollViewLocation.x - contentOffset.x) / scale,
            y: (scrollViewLocation.y - contentOffset.y) / scale
        )
    }

    /// CSS `elementFromPoint` / `classifyPoint` client coordinates for a point
    /// already in WKWebView visible-bounds space.
    static func javascriptClientPoint(
        webViewLocation: CGPoint,
        pageZoom: CGFloat
    ) -> CGPoint {
        let zoom = pageZoom > 0 ? pageZoom : 1
        return CGPoint(x: webViewLocation.x / zoom, y: webViewLocation.y / zoom)
    }
}

/// Whether article back / sidebar / TOC chrome may activate for a pan.
/// A horizontal scroller that owns the start point, an in-flight classifyPoint,
/// or a latched mid-horizontal-scroll / JS / native claim all veto chrome.
enum osrsArticleChromeArbitration {
    static func allowsChrome(
        isLocalOwnerAtStartPoint: Bool,
        classificationPending: Bool,
        shouldBlockGestures: Bool
    ) -> Bool {
        if classificationPending { return false }
        if isLocalOwnerAtStartPoint { return false }
        if shouldBlockGestures { return false }
        return true
    }
}

struct ArticleWebView: UIViewRepresentable {
    @ObservedObject var viewModel: ArticleViewModel
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var themeManager: osrsThemeManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    // Optional external navigation delegate for table preview generation
    let navigationDelegate: WKNavigationDelegate?
    let onBackGesture: (() -> Void)?
    let onSidebarGesture: (() -> Void)?
    let onSidebarProgress: ((CGFloat) -> Void)?
    let onSidebarSettle: ((CGFloat, CGFloat) -> Void)?
    let onBackProgress: ((CGFloat) -> Void)?
    let isContentsOpen: () -> Bool

    init(
        viewModel: ArticleViewModel,
        navigationDelegate: WKNavigationDelegate? = nil,
        onBackGesture: (() -> Void)? = nil,
        onSidebarGesture: (() -> Void)? = nil,
        onSidebarProgress: ((CGFloat) -> Void)? = nil,
        onSidebarSettle: ((CGFloat, CGFloat) -> Void)? = nil,
        onBackProgress: ((CGFloat) -> Void)? = nil,
        isContentsOpen: @escaping () -> Bool = { false }
    ) {
        self.viewModel = viewModel
        self.navigationDelegate = navigationDelegate
        self.onBackGesture = onBackGesture
        self.onSidebarGesture = onSidebarGesture
        self.onSidebarProgress = onSidebarProgress
        self.onSidebarSettle = onSidebarSettle
        self.onBackProgress = onBackProgress
        self.isContentsOpen = isContentsOpen
    }
    
    func makeUIView(context: Context) -> WKWebView {
        if !viewModel.needsContentProcessRecovery,
           let existing = viewModel.webView,
           existing.superview == nil,
           existing.url != nil,
           existing.url?.absoluteString != "about:blank" {
            return configureAdoptedWebView(existing, context: context)
        }
        let renderOptions = osrsArticleRenderOptions(
            usesDarkTheme: themeManager.currentTheme is osrsDarkTheme,
            collapseTablesEnabled: themeManager.collapseTables,
            wrapTableCellsEnabled: themeManager.wrapTableCells,
            articleTextScale: Double(themeManager.articleTextScale)
        )
        if !viewModel.needsContentProcessRecovery,
           let prepared = osrsPreparedArticleWebViewStore.shared.take(
            pageURL: viewModel.pageUrl,
            pageTitle: viewModel.pageTitle_,
            options: renderOptions
        ) {
            return configureAdoptedWebView(prepared, context: context)
        }

        let configuration = osrsPreparedArticleWebViewStore.makeConfiguration(
            sourceArticleURL: viewModel.pageUrl
        )
        configuration.processPool = osrsArticleWebKitRuntime.processPool
        configuration.websiteDataStore = .default()
        
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

        userContentController.addUserScript(
            WKUserScript(
                source: osrsWebViewThemePaint.documentStartPaintScript(theme: themeManager.currentTheme),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        
        // Register message handlers
        for handlerName in osrsWebKitSecurityPolicy.enabledHandlerNames {
            userContentController.add(context.coordinator, contentWorld: .page, name: handlerName)
        }
        
        configuration.userContentController = userContentController
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        print("✅ Reusing shared app-assets:// handler for article WebView")
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        // Theme-paint before any other WK configuration so the first compositor
        // frame is not system-white or light parchment under a dark article host.
        osrsWebViewThemePaint.apply(to: webView, theme: themeManager.currentTheme)
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
        // ArticleView owns the full-width back gesture. WebKit's edge-only navigation gesture
        // competes with local tables/maps and leaves the system transition outline half-open.
        webView.allowsBackForwardNavigationGestures = false
        osrsArticleRefreshSettlement.configure(webView.scrollView)
        if viewModel.needsContentProcessRecovery {
            osrsWebViewThemePaint.apply(to: webView, theme: themeManager.currentTheme)
        } else {
            osrsWebViewThemePaint.loadPlaceholderIfEmpty(in: webView, theme: themeManager.currentTheme)
        }
        webView.accessibilityIdentifier = "article_web_view"
        
        if #available(iOS 16.4, *) {
            webView.isInspectable = osrsWebKitSecurityPolicy.isWebViewInspectionEnabled
        }
        
        // UIKit owns this recognizer because SwiftUI gestures attached outside a WKWebView do
        // not reliably observe its touch stream. It recognizes simultaneously and never
        // cancels WebKit scrolling; DOM/native-map ownership still makes navigation fail closed.
        context.coordinator.installArticleNavigationGesture(on: webView)
        context.coordinator.installArticleRefreshControl(on: webView)
        context.coordinator.interactiveSwipe.chromeColor = UIColor(themeManager.currentTheme.background)
        
        // map_bridge.js is the single article bridge and the HTML loads the shared interceptor
        // once. Do not also install the legacy document-end interceptor here.
        
        // Enable find-in-page interaction (iOS 16+)
        if #available(iOS 16.0, *) {
            webView.isFindInteractionEnabled = true
        }
        
        // Connect webView to viewModel
        viewModel.setWebView(webView)
        applyDynamicTypeScale(to: webView, coordinator: context.coordinator)
        
        // Initialize map handler with the webView
        context.coordinator.setupMapHandler(webView: webView)
        context.coordinator.lastInjectedThemeIsDark = themeManager.currentTheme is osrsDarkTheme
        
        return webView
    }

    private func configureAdoptedWebView(_ webView: WKWebView, context: Context) -> WKWebView {
        let userContentController = webView.configuration.userContentController
        for handlerName in osrsWebKitSecurityPolicy.enabledHandlerNames {
            userContentController.removeScriptMessageHandler(forName: handlerName, contentWorld: .page)
            userContentController.add(context.coordinator, contentWorld: .page, name: handlerName)
        }
        let finalDelegate = navigationDelegate ?? viewModel
        webView.navigationDelegate = finalDelegate
        webView.allowsBackForwardNavigationGestures = false
        osrsArticleRefreshSettlement.configure(webView.scrollView)
        osrsWebViewThemePaint.apply(to: webView, theme: themeManager.currentTheme)
        webView.accessibilityIdentifier = "article_web_view"
        if #available(iOS 16.4, *) {
            webView.isInspectable = osrsWebKitSecurityPolicy.isWebViewInspectionEnabled
        }
        context.coordinator.installArticleNavigationGesture(on: webView)
        context.coordinator.installArticleRefreshControl(on: webView)
        context.coordinator.interactiveSwipe.chromeColor = UIColor(themeManager.currentTheme.background)
        if #available(iOS 16.0, *) {
            webView.isFindInteractionEnabled = true
        }
        viewModel.adoptPreRenderedWebView(webView)
        applyDynamicTypeScale(to: webView, coordinator: context.coordinator)
        context.coordinator.setupMapHandler(webView: webView)
        context.coordinator.lastInjectedThemeIsDark = themeManager.currentTheme is osrsDarkTheme
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        if viewModel.webView !== webView {
            viewModel.setWebView(webView)
        }
        applyDynamicTypeScale(to: webView, coordinator: context.coordinator)
        let isDark = themeManager.currentTheme is osrsDarkTheme
        context.coordinator.interactiveSwipe.chromeColor = UIColor(themeManager.currentTheme.background)
        if context.coordinator.lastInjectedThemeIsDark != isDark {
            context.coordinator.lastInjectedThemeIsDark = isDark
            viewModel.applyLiveTheme(themeManager.currentTheme, themeManager: themeManager)
        }
        let refreshing = viewModel.isRefreshing
        if !refreshing {
            if context.coordinator.wasArticleRefreshing {
                osrsArticleRefreshSettlement.settle(webView)
            } else {
                webView.scrollView.refreshControl?.endRefreshing()
            }
        }
        context.coordinator.wasArticleRefreshing = refreshing
        context.coordinator.maybeRunSyntheticSwipeFPSProbe(on: webView)
    }

    private func applyDynamicTypeScale(to webView: WKWebView, coordinator: Coordinator? = nil) {
        let scale = osrsArticleDynamicTypeScaling.scale(for: dynamicTypeSize)
        let requiresWebReflow = osrsArticleDynamicTypeScaling.requiresWebReflow(for: dynamicTypeSize)
        let pageZoom = requiresWebReflow ? 1.0 : scale
        if coordinator?.lastAppliedPageZoom != pageZoom {
            coordinator?.lastAppliedPageZoom = pageZoom
            webView.pageZoom = pageZoom
        }
        viewModel.setAccessibilityReflowEnabled(requiresWebReflow, textScale: requiresWebReflow ? scale : 1.0)
#if DEBUG
        let existing = (webView.accessibilityValue as? String) ?? ""
        let preservedTokens = existing
            .split(separator: ";")
            .map(String.init)
            .filter {
                $0.hasPrefix("native_article_maps=") ||
                    $0.hasPrefix("native_map_frame=") ||
                    $0.hasPrefix("swipe_fps_")
            }
        let probeTokens = (osrsInteractiveSwipeFrameProbe.accessibilityToken() ?? "")
            .split(separator: ";")
            .map(String.init)
        let keptWithoutProbe = preservedTokens.filter { !$0.hasPrefix("swipe_fps_") }
        webView.accessibilityValue = ([
            String(format: "article_dynamic_type_scale=%.2f", Double(scale)),
            String(format: "article_user_text_scale=%.2f", themeManager.articleTextScale),
            "article_collapse_tables=\(themeManager.collapseTables ? 1 : 0)",
            "article_wrap_table_cells=\(themeManager.wrapTableCells ? 1 : 0)",
            "article_swipe_right_back=\(themeManager.swipeRightToGoBackEnabled ? 1 : 0)",
            "article_swipe_left_contents=\(themeManager.swipeLeftToShowContentsEnabled ? 1 : 0)"
        ] + keptWithoutProbe + (probeTokens.isEmpty ? preservedTokens.filter { $0.hasPrefix("swipe_fps_") } : probeTokens))
            .joined(separator: ";")
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
                    line-height: 1.35;
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
    
    class Coordinator: NSObject, WKScriptMessageHandler, UIGestureRecognizerDelegate {
        var parent: ArticleWebView
        private var mapHandler: osrsNativeMapHandler?
        private weak var webView: WKWebView?
        private weak var articleNavigationRecognizer: UIPanGestureRecognizer?
        private var articleGestureGeneration: UInt64?
        private var articleGestureStartPoint: CGPoint?
        fileprivate let interactiveSwipe = osrsInteractiveArticleSwipe()
        private var restoredWebScrollEnabled: Bool?
        private var pendingBackCommitAuthorized: Bool?
        private var pendingBackCommitAnimationDone = false
        private var pendingBackCommitGeneration: UInt64?
        private var articleChromeBlockedForSequence = false
        private var articleChromeClassificationPending = false
        private var articleChromeStartIsLocalOwner = false
        private var articleChromePendingFinish: (generation: UInt64, translation: CGPoint, velocity: CGPoint)?
        fileprivate var lastAppliedPageZoom: CGFloat?
        fileprivate var wasArticleRefreshing = false
        fileprivate var lastInjectedThemeIsDark: Bool?
        private var didRunSyntheticSwipeFPSProbe = false
        private var syntheticSwipeDisplayLink: CADisplayLink?
        private var syntheticSwipeProgress: CGFloat = 0
        
        init(_ parent: ArticleWebView) {
            self.parent = parent
        }
        
        func setupMapHandler(webView: WKWebView) {
            self.webView = webView
            osrsArticleRefreshSettlement.configure(webView.scrollView)
            mapHandler = osrsNativeMapHandler(webView: webView)
            installCalculatorKeyboardRecovery(on: webView)
            print("✅ iOS ArticleWebView: Map handler initialized")
        }

        private var keyboardObservers: [NSObjectProtocol] = []

        func installCalculatorKeyboardRecovery(on webView: WKWebView) {
            osrsBlankViewFirstResponderDump.installPeriodicDumpIfRequested()
            removeCalculatorKeyboardObservers()
            let center = NotificationCenter.default
            let restore: (Notification) -> Void = { [weak self] _ in
                self?.restoreWebViewAfterCalculatorKeyboard()
            }
            keyboardObservers.append(center.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let viewModel = self?.parent.viewModel else { return }
                    if !viewModel.isArticleSoftwareKeyboardVisible {
                        viewModel.isArticleSoftwareKeyboardVisible = true
                        osrsSceneCompositor.beginLiveOverlaySession()
                    }
                    osrsBlankViewFirstResponderDump.capture(reason: "keyboardWillShow")
                }
            })
            keyboardObservers.append(center.addObserver(forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main) { _ in
                Task { @MainActor in
                    osrsBlankViewFirstResponderDump.capture(reason: "keyboardDidShow")
                }
            })
            keyboardObservers.append(center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main, using: restore))
            keyboardObservers.append(center.addObserver(forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let viewModel = self?.parent.viewModel else { return }
                    if viewModel.isArticleSoftwareKeyboardVisible {
                        viewModel.isArticleSoftwareKeyboardVisible = false
                        osrsSceneCompositor.endLiveOverlaySession()
                    }
                    self?.restoreWebViewAfterCalculatorKeyboard()
                    osrsBlankViewFirstResponderDump.capture(reason: "keyboardDidHide")
                }
            })
        }

        func restoreWebViewAfterCalculatorKeyboard() {
            guard let webView else { return }
            webView.isHidden = false
            webView.alpha = 1
            webView.scrollView.isHidden = false
            webView.scrollView.alpha = 1
            if parent.viewModel.shouldSkipDocumentWakeDuringFindOrKeyboard {
                return
            }
            osrsSceneCompositor.wakeLiveArticleWebView(webView)
            let scroll = webView.scrollView
            let inset = scroll.adjustedContentInset
            let maxY = max(0, scroll.contentSize.height - scroll.bounds.height + inset.bottom)
            let minY = -inset.top
            if scroll.contentOffset.y < minY - 1 || scroll.contentOffset.y > maxY + 1 {
                let y = min(max(scroll.contentOffset.y, minY), maxY)
                scroll.setContentOffset(CGPoint(x: 0, y: y), animated: false)
            }
            webView.evaluateJavaScript(
                "window.osrsEnsureCalculatorPageVisible && window.osrsEnsureCalculatorPageVisible();"
            )
        }

        func removeCalculatorKeyboardObservers() {
            keyboardObservers.forEach { NotificationCenter.default.removeObserver($0) }
            keyboardObservers.removeAll()
        }

        func installArticleNavigationGesture(on webView: WKWebView) {
            // Touches land on WKScrollView. A pan on WKWebView itself is often
            // starved by the scroll pan on iOS 26, which makes interactive chrome
            // wait (feels like a sub-120Hz hitch) and hides the gesture from XCTest.
            let host = webView.scrollView
            if articleNavigationRecognizer?.view === host {
                osrsInteractiveArticleSwipe.navigationController(from: webView)?
                    .interactivePopGestureRecognizer?.isEnabled = false
                return
            }
            if let previous = articleNavigationRecognizer {
                previous.view?.removeGestureRecognizer(previous)
            }
            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handleArticleNavigationPan(_:)))
            recognizer.delegate = self
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.maximumNumberOfTouches = 1
            webView.scrollView.addGestureRecognizer(recognizer)
            articleNavigationRecognizer = recognizer
            osrsInteractiveArticleSwipe.navigationController(from: webView)?
                .interactivePopGestureRecognizer?.isEnabled = false
        }

        func installArticleRefreshControl(on webView: WKWebView) {
            let refreshControl = webView.scrollView.refreshControl ?? UIRefreshControl()
            refreshControl.addTarget(self, action: #selector(handleArticlePullToRefresh), for: .valueChanged)
            webView.scrollView.refreshControl = refreshControl
        }

#if DEBUG
        func maybeRunSyntheticSwipeFPSProbe(on webView: WKWebView) {
            guard osrsInteractiveSwipeFrameProbe.isEnabled,
                  osrsInteractiveSwipeFrameProbe.isSyntheticPanEnabled,
                  !didRunSyntheticSwipeFPSProbe else { return }
            didRunSyntheticSwipeFPSProbe = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                self?.startSyntheticSwipeFPSProbe()
            }
        }

        private func startSyntheticSwipeFPSProbe() {
            guard let webView else { return }
            osrsInteractiveSwipeFrameProbe.beginSequence()
            publishSwipeFrameProbeToWebView()
            interactiveSwipe.begin(from: webView, contentsOpen: parent.isContentsOpen())
            syntheticSwipeProgress = 0
            let link = CADisplayLink(target: self, selector: #selector(handleSyntheticSwipeFPSProbeTick(_:)))
            link.add(to: .main, forMode: .common)
            syntheticSwipeDisplayLink = link
        }

        @objc private func handleSyntheticSwipeFPSProbeTick(_ link: CADisplayLink) {
            guard let webView else {
                stopSyntheticSwipeFPSProbe()
                return
            }
            osrsInteractiveSwipeFrameProbe.recordPanFrame()
            publishSwipeFrameProbeToWebView()
            syntheticSwipeProgress = min(1, syntheticSwipeProgress + 0.045)
            let width = max(webView.bounds.width, 1)
            let translation = CGPoint(x: syntheticSwipeProgress * width * 0.28, y: 0)
            interactiveSwipe.update(translation: translation, from: webView)
            if interactiveSwipe.isTracking {
                freezeWebScrollIfNeeded(webView)
                if interactiveSwipe.axis == .back {
                    parent.onBackProgress?(interactiveSwipe.backProgress)
                } else if interactiveSwipe.axis == .contents {
                    parent.onSidebarProgress?(interactiveSwipe.contentsProgress)
                }
            }
            if syntheticSwipeProgress >= 1 {
                stopSyntheticSwipeFPSProbe()
            }
        }

        private func stopSyntheticSwipeFPSProbe() {
            syntheticSwipeDisplayLink?.invalidate()
            syntheticSwipeDisplayLink = nil
            osrsInteractiveSwipeFrameProbe.finishSequence()
            publishSwipeFrameProbeToWebView()
            cancelInteractiveSwipe(restoreScroll: true)
        }
#else
        func maybeRunSyntheticSwipeFPSProbe(on webView: WKWebView) {}
#endif

        @objc private func handleArticlePullToRefresh() {
            parent.viewModel.refreshPage(theme: parent.themeManager.currentTheme)
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === articleNavigationRecognizer,
                  let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = pan.view else {
                return true
            }
            let velocity = pan.velocity(in: view)
            if osrsGestureState.shared.shouldBlockGestures {
                return false
            }
            if velocity == .zero {
                return true
            }
            guard osrsArticleWebPanPolicy.isPrimarilyHorizontal(velocity: velocity) else {
                return false
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            if isSystemScreenEdgePan(otherGestureRecognizer) {
                return false
            }
            return gestureRecognizer === articleNavigationRecognizer ||
                otherGestureRecognizer === articleNavigationRecognizer
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            gestureRecognizer === articleNavigationRecognizer && isSystemScreenEdgePan(otherGestureRecognizer)
        }

        private func isSystemScreenEdgePan(_ recognizer: UIGestureRecognizer) -> Bool {
            recognizer is UIScreenEdgePanGestureRecognizer ||
                String(describing: type(of: recognizer)).localizedCaseInsensitiveContains("ScreenEdge")
        }

        @objc private func handleArticleNavigationPan(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view else { return }
            switch recognizer.state {
            case .began:
                articleGestureGeneration = osrsGestureState.shared.beginArticleGesture()
                let scrollLocation = recognizer.location(in: view)
                if let webView {
                    articleGestureStartPoint = osrsArticleWebPanPolicy.webViewPoint(
                        scrollViewLocation: scrollLocation,
                        contentOffset: webView.scrollView.contentOffset,
                        zoomScale: webView.scrollView.zoomScale
                    )
                } else {
                    articleGestureStartPoint = scrollLocation
                }
                articleChromeBlockedForSequence = false
                articleChromeClassificationPending = true
                articleChromeStartIsLocalOwner = false
                articleChromePendingFinish = nil
                osrsInteractiveSwipeFrameProbe.beginSequence()
                publishSwipeFrameProbeToWebView()
                if osrsGestureState.shared.shouldBlockGestures {
                    articleChromeBlockedForSequence = true
                    articleChromeClassificationPending = false
                    return
                }
                if let webView, let startPoint = articleGestureStartPoint {
                    if mapHandler?.ownsArticleGesture(at: startPoint, in: webView) == true {
                        articleChromeBlockedForSequence = true
                        articleChromeClassificationPending = false
                        articleChromeStartIsLocalOwner = true
                    } else {
                        classifyArticleChromeStartPoint(
                            startPoint,
                            in: webView,
                            generation: articleGestureGeneration
                        )
                    }
                }
            case .changed:
                guard let webView else { return }
                if articleChromeBlockedForSequence || articleChromeClassificationPending {
                    return
                }
                osrsInteractiveSwipeFrameProbe.recordPanFrame()
                publishSwipeFrameProbeToWebView()
                if !osrsArticleChromeArbitration.allowsChrome(
                    isLocalOwnerAtStartPoint: articleChromeStartIsLocalOwner,
                    classificationPending: articleChromeClassificationPending,
                    shouldBlockGestures: osrsGestureState.shared.shouldBlockGestures
                ) {
                    // A late map overlay attaching during an already-committed chrome swipe
                    // must not abort it. A local table/chart that claims before chrome is
                    // locked still wins so the table can scroll.
                    let chromeLocked = interactiveSwipe.isTracking &&
                        max(interactiveSwipe.contentsProgress, interactiveSwipe.backProgress) > 0.25
                    if !chromeLocked {
                        cancelInteractiveSwipe(restoreScroll: true)
                        articleChromeBlockedForSequence = true
                        return
                    }
                }
                interactiveSwipe.update(
                    translation: recognizer.translation(in: view.window ?? view),
                    from: webView
                )
                if interactiveSwipe.isTracking {
                    freezeWebScrollIfNeeded(webView)
                    if interactiveSwipe.axis == .contents {
                        parent.onSidebarProgress?(interactiveSwipe.contentsProgress)
                    } else if interactiveSwipe.axis == .back {
                        parent.onBackProgress?(interactiveSwipe.backProgress)
                    }
                }
            case .ended:
                osrsInteractiveSwipeFrameProbe.finishSequence()
                publishSwipeFrameProbeToWebView()
                if articleChromeBlockedForSequence {
                    osrsGestureState.shared.cancelArticleGesture(generation: articleGestureGeneration)
                    cancelInteractiveSwipe(restoreScroll: true)
                    clearArticleGestureSequence()
                    return
                }
                guard let generation = articleGestureGeneration else {
                    osrsGestureState.shared.cancelArticleGesture()
                    cancelInteractiveSwipe(restoreScroll: true)
                    clearArticleGestureSequence()
                    return
                }
                let translation = recognizer.translation(in: view.window ?? view)
                let velocity = recognizer.velocity(in: view.window ?? view)
                if articleChromeClassificationPending {
                    // Fail closed until classifyPoint returns. An unowned result
                    // may still commit; a local horizontal owner never will.
                    articleChromePendingFinish = (
                        generation: generation,
                        translation: translation,
                        velocity: velocity
                    )
                    return
                }
                applyArticleChromeFinish(
                    generation: generation,
                    translation: translation,
                    velocity: velocity
                )
            case .cancelled, .failed:
                osrsInteractiveSwipeFrameProbe.finishSequence()
                publishSwipeFrameProbeToWebView()
                osrsGestureState.shared.cancelArticleGesture(generation: articleGestureGeneration)
                articleChromePendingFinish = nil
                clearArticleGestureSequence()
                cancelInteractiveSwipe(restoreScroll: true)
            default:
                break
            }
        }

        private func freezeWebScrollIfNeeded(_ webView: WKWebView) {
            guard restoredWebScrollEnabled == nil else { return }
            restoredWebScrollEnabled = webView.scrollView.isScrollEnabled
            webView.scrollView.isScrollEnabled = false
        }

        private func publishSwipeFrameProbeToWebView() {
            guard let token = osrsInteractiveSwipeFrameProbe.accessibilityToken(), let webView else { return }
#if DEBUG
            let kept = ((webView.accessibilityValue as? String) ?? "")
                .split(separator: ";")
                .map(String.init)
                .filter { !$0.hasPrefix("swipe_fps_") }
            webView.accessibilityValue = (kept + token.split(separator: ";").map(String.init))
                .joined(separator: ";")
#endif
        }

        private func restoreWebScroll() {
            if let restoredWebScrollEnabled, let webView {
                webView.scrollView.isScrollEnabled = restoredWebScrollEnabled
            }
            restoredWebScrollEnabled = nil
        }

        private func cancelInteractiveSwipe(restoreScroll: Bool) {
            resetPendingBackCommit()
            let restoreContents: CGFloat = interactiveSwipe.contentsOpenAtStart ? 1 : 0
            interactiveSwipe.cancel(animated: true)
            parent.onSidebarProgress?(restoreContents)
            parent.onBackProgress?(0)
            if restoreScroll {
                restoreWebScroll()
            }
        }

        private func restoreInteractiveOverlays() {
            parent.onSidebarProgress?(interactiveSwipe.contentsOpenAtStart ? 1.0 : 0.0)
            parent.onBackProgress?(0)
        }

        private func settleSidebar(to progress: CGFloat, velocity: CGFloat) {
            if let settle = parent.onSidebarSettle {
                settle(progress, velocity)
            } else {
                parent.onSidebarProgress?(progress)
                if progress >= 1 {
                    parent.onSidebarGesture?()
                }
            }
        }

        private func articleNavigationAction(for direction: HorizontalGestureDirection) -> () -> Void {
            { [weak self] in
                guard let self else { return }
                switch direction {
                case .start:
                    self.parent.onBackGesture?()
                case .end:
                    self.parent.onSidebarGesture?()
                }
            }
        }

        private func performArticleNavigationAfterOwnershipClassification(
            generation: UInt64,
            isLocalOwnerAtStartPoint: Bool,
            _ action: @escaping () -> Void
        ) {
            var authorized = false
            osrsGestureState.shared.performNavigationAfterPointClassification(
                generation: generation,
                isLocalOwnerAtStartPoint: isLocalOwnerAtStartPoint
            ) { [weak self] in
                authorized = true
                guard let self else { return }
                if self.pendingBackCommitGeneration == generation {
                    self.pendingBackCommitAuthorized = true
                    self.finishPendingBackCommitIfReady()
                    return
                }
                action()
                self.interactiveSwipe.cleanup(resetTransform: false)
            }
            if !authorized {
                if pendingBackCommitGeneration == generation {
                    return
                }
                interactiveSwipe.cancel(animated: true)
                restoreInteractiveOverlays()
            }
        }

        private func beginPendingBackCommit(generation: UInt64, velocity: CGPoint) {
            pendingBackCommitGeneration = generation
            pendingBackCommitAuthorized = true
            pendingBackCommitAnimationDone = true
            parent.onBackProgress?(1)
            interactiveSwipe.commitBackImmediately(velocity: velocity) { [weak self] in
                self?.parent.onBackGesture?()
            }
            osrsGestureState.shared.cancelArticleGesture(generation: generation)
            resetPendingBackCommit()
        }

        private func finishPendingBackCommitIfReady() {
            guard pendingBackCommitGeneration != nil,
                  pendingBackCommitAnimationDone,
                  pendingBackCommitAuthorized == true else { return }
            parent.onBackGesture?()
            resetPendingBackCommit()
        }

        private func resetPendingBackCommit() {
            pendingBackCommitGeneration = nil
            pendingBackCommitAuthorized = nil
            pendingBackCommitAnimationDone = false
        }

#if DEBUG
        func resolveArticleNavigationForTesting(
            direction: HorizontalGestureDirection,
            isLocalOwnerAtStartPoint: Bool
        ) {
            let generation = osrsGestureState.shared.beginArticleGesture()
            performArticleNavigationAfterOwnershipClassification(
                generation: generation,
                isLocalOwnerAtStartPoint: isLocalOwnerAtStartPoint,
                articleNavigationAction(for: direction)
            )
        }

        func allowsArticleChromeForTesting(
            isLocalOwnerAtStartPoint: Bool,
            classificationPending: Bool
        ) -> Bool {
            osrsArticleChromeArbitration.allowsChrome(
                isLocalOwnerAtStartPoint: isLocalOwnerAtStartPoint,
                classificationPending: classificationPending,
                shouldBlockGestures: osrsGestureState.shared.shouldBlockGestures
            )
        }
#endif

        private func clearArticleGestureSequence() {
            articleGestureGeneration = nil
            articleGestureStartPoint = nil
            articleChromeBlockedForSequence = false
            articleChromeClassificationPending = false
            articleChromeStartIsLocalOwner = false
            articleChromePendingFinish = nil
        }

        private func applyArticleChromeFinish(
            generation: UInt64,
            translation: CGPoint,
            velocity: CGPoint
        ) {
            defer { clearArticleGestureSequence() }
            if !osrsArticleChromeArbitration.allowsChrome(
                isLocalOwnerAtStartPoint: articleChromeStartIsLocalOwner,
                classificationPending: articleChromeClassificationPending,
                shouldBlockGestures: osrsGestureState.shared.shouldBlockGestures
            ) {
                osrsGestureState.shared.cancelArticleGesture(generation: generation)
                cancelInteractiveSwipe(restoreScroll: true)
                return
            }
            if let webView {
                if !interactiveSwipe.isTracking {
                    interactiveSwipe.begin(from: webView, contentsOpen: parent.isContentsOpen())
                }
                interactiveSwipe.update(translation: translation, from: webView)
            }
            let finish = interactiveSwipe.finish(translation: translation, velocity: velocity)
            restoreWebScroll()

            switch finish {
            case .cancel:
                if interactiveSwipe.lastAxis == .contents {
                    settleSidebar(
                        to: interactiveSwipe.contentsOpenAtStart ? 1 : 0,
                        velocity: velocity.x
                    )
                } else {
                    restoreInteractiveOverlays()
                }
                osrsGestureState.shared.cancelArticleGesture(generation: generation)
            case .commitBack:
                guard parent.onBackGesture != nil else {
                    interactiveSwipe.cancel(animated: true)
                    restoreInteractiveOverlays()
                    osrsGestureState.shared.cancelArticleGesture(generation: generation)
                    return
                }
                performArticleNavigationAfterOwnershipClassification(
                    generation: generation,
                    isLocalOwnerAtStartPoint: articleChromeStartIsLocalOwner
                ) { [weak self] in
                    self?.beginPendingBackCommit(generation: generation, velocity: velocity)
                }
            case .commitContents:
                guard parent.onSidebarGesture != nil || parent.onSidebarSettle != nil else {
                    restoreInteractiveOverlays()
                    osrsGestureState.shared.cancelArticleGesture(generation: generation)
                    return
                }
                performArticleNavigationAfterOwnershipClassification(
                    generation: generation,
                    isLocalOwnerAtStartPoint: articleChromeStartIsLocalOwner
                ) { [weak self] in
                    guard let self else { return }
                    self.settleSidebar(to: 1, velocity: velocity.x)
                    self.interactiveSwipe.cleanup(resetTransform: false)
                }
            case .commitContentsDismiss:
                settleSidebar(to: 0, velocity: velocity.x)
                osrsGestureState.shared.cancelArticleGesture(generation: generation)
            }
        }

        private func classifyArticleChromeStartPoint(
            _ point: CGPoint,
            in webView: WKWebView,
            generation: UInt64?
        ) {
            let client = osrsArticleWebPanPolicy.javascriptClientPoint(
                webViewLocation: point,
                pageZoom: webView.pageZoom
            )
            let x = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), client.x)
            let y = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), client.y)
            let script = "window.OSRSArticleGestureOwnership && window.OSRSArticleGestureOwnership.classifyPoint(\(x), \(y))"
            webView.evaluateJavaScript(script) { [weak self] result, error in
                DispatchQueue.main.async {
                    guard let self,
                          self.articleGestureGeneration == generation,
                          self.articleChromeClassificationPending else { return }
                    let isLocalOwner: Bool
                    if error == nil,
                       let classification = result as? [String: Any],
                       let classified = classification["isLocalOwner"] as? Bool {
                        isLocalOwner = classified
                    } else {
                        // Missing or unreadable classifyPoint must not authorize chrome.
                        isLocalOwner = true
                    }
                    self.articleChromeStartIsLocalOwner = isLocalOwner
                    self.articleChromeClassificationPending = false
                    if isLocalOwner {
                        let hadPendingFinish = self.articleChromePendingFinish != nil
                        self.articleChromeBlockedForSequence = true
                        self.articleChromePendingFinish = nil
                        self.cancelInteractiveSwipe(restoreScroll: true)
                        if let generation {
                            osrsGestureState.shared.cancelArticleGesture(generation: generation)
                        }
                        if hadPendingFinish {
                            self.clearArticleGestureSequence()
                        }
                        return
                    }
                    if let pending = self.articleChromePendingFinish,
                       pending.generation == generation {
                        self.articleChromePendingFinish = nil
                        self.applyArticleChromeFinish(
                            generation: pending.generation,
                            translation: pending.translation,
                            velocity: pending.velocity
                        )
                        return
                    }
                    if !self.interactiveSwipe.isTracking {
                        self.interactiveSwipe.begin(from: webView, contentsOpen: self.parent.isContentsOpen())
                    }
                    if let recognizer = self.articleNavigationRecognizer {
                        self.interactiveSwipe.update(
                            translation: recognizer.translation(in: recognizer.view?.window ?? recognizer.view ?? webView),
                            from: webView
                        )
                    }
                }
            }
        }

        private func classifyArticleGestureStartPoint(
            _ point: CGPoint,
            in webView: WKWebView,
            generation: UInt64,
            action: @escaping () -> Void
        ) {
            let client = osrsArticleWebPanPolicy.javascriptClientPoint(
                webViewLocation: point,
                pageZoom: webView.pageZoom
            )
            let x = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), client.x)
            let y = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), client.y)
            let script = "window.OSRSArticleGestureOwnership && window.OSRSArticleGestureOwnership.classifyPoint(\(x), \(y))"
            webView.evaluateJavaScript(script) { result, error in
                DispatchQueue.main.async {
                    guard error == nil,
                          let classification = result as? [String: Any],
                          let isLocalOwner = classification["isLocalOwner"] as? Bool else {
                        if self.pendingBackCommitGeneration == generation {
                            // The user already completed the back swipe. A missing
                            // ownership bridge must not snap the article back.
                            self.pendingBackCommitAuthorized = true
                            self.finishPendingBackCommitIfReady()
                            return
                        }
                        // The ownership bridge is not ready yet (page still loading).
                        // Keep article chrome gestures usable the same way Android does.
                        self.performArticleNavigationAfterOwnershipClassification(
                            generation: generation,
                            isLocalOwnerAtStartPoint: false,
                            action
                        )
                        return
                    }
#if DEBUG
                    let owner = classification["ownerId"] as? String ?? "unknown"
                    let target = classification["targetTag"] as? String ?? "unknown"
                    print("[ArticleWebGesture] generation=\(generation) start=(\(x),\(y)) owner=\(owner) target=\(target) local=\(isLocalOwner)")
#endif
                    self.performArticleNavigationAfterOwnershipClassification(
                        generation: generation,
                        isLocalOwnerAtStartPoint: isLocalOwner,
                        action
                    )
                }
            }
        }
        
        func cleanup() {
            print("🧹 ArticleWebView.Coordinator: Starting cleanup")
            removeCalculatorKeyboardObservers()

            osrsGestureState.shared.cancelArticleGesture(generation: articleGestureGeneration)
            articleGestureGeneration = nil
            articleGestureStartPoint = nil
            syntheticSwipeDisplayLink?.invalidate()
            syntheticSwipeDisplayLink = nil
            interactiveSwipe.cleanup(resetTransform: true)
            restoreWebScroll()
            if let recognizer = articleNavigationRecognizer {
                recognizer.view?.removeGestureRecognizer(recognizer)
            }
            articleNavigationRecognizer = nil
            
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
                NSLog(
                    "osrsCalcApi: rejected name=%@ main=%@ proto=%@ host=%@",
                    message.name,
                    String(message.frameInfo.isMainFrame),
                    message.frameInfo.securityOrigin.protocol,
                    message.frameInfo.securityOrigin.host
                )
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
            case "osrsYouTube":
                if let videoId = body["videoId"] as? String {
                    parent.viewModel.playYouTubeVideo(id: videoId)
                }
            case "osrsCalculatorApi":
                handleCalculatorApiMessage(body)
            case "osrsLiveAssetWarm":
                if body["pause"] as? Bool == true {
                    osrsBackgroundWorkGate.shared.noteUserInteraction()
                    parent.viewModel.noteBackgroundWorkUserInteraction()
                }
                if let urls = body["urls"] as? [String] {
                    parent.viewModel.promoteLiveArticleAssets(urls)
                }
            case "osrsFirstViewComplete":
                parent.viewModel.markFirstViewComplete()
                if let generation = firstViewGeneration(from: body) {
                    parent.viewModel.completeLoadingWithBodyReveal(loadGeneration: generation)
                } else {
                    parent.viewModel.completeLoadingWithBodyReveal()
                }
            case "osrsFirstViewportSettled":
                // Stopwatch-only; body reveal stays on FirstViewPainted / osrsFirstViewComplete.
                parent.viewModel.markFirstViewportSettled(loadGeneration: firstViewGeneration(from: body))
            case "safariDebugger":
                handleSafariDebuggerMessage(body)
            default:
                break
            }
        }

        private func handleCalculatorApiMessage(_ body: [String: Any]) {
            // Check for choice picker action
            if let action = body["action"] as? String, action == "showChoicePicker" {
                handleCalculatorChoicePickerMessage(body)
                return
            }
            
            // Original calculator API request handler
            let requestId = body["id"] as? String ?? ""
            let method = body["method"] as? String ?? "GET"
            let urlString = body["url"] as? String ?? ""
            NSLog("osrsCalcApi: id=%@ method=%@ url=%@", requestId, method, urlString)
            Task {
                let result = await osrsCalculatorWikiClient.request(
                    method: method,
                    urlString: urlString,
                    data: body["data"]
                )
                await MainActor.run {
                    self.completeCalculatorApi(id: requestId, result: result)
                }
            }
        }

        private func handleCalculatorChoicePickerMessage(_ body: [String: Any]) {
            let rawLabel = (body["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let label = rawLabel.isEmpty ? "Choose option" : rawLabel
            let callbackId = body["callbackId"] as? String ?? ""
            let currentValue = Self.osrsStringValue(body["currentValue"]) ?? ""
            let options = Self.osrsCalculatorPickerOptions(from: body["options"])

            guard !options.isEmpty else {
                NSLog("osrsCalcApi: Invalid choice picker request")
                completeChoicePicker(callbackId: callbackId, selected: false, value: nil)
                return
            }

            NSLog("osrsCalcApi: showChoicePicker label=%@ options=%d currentValue=%@", label, options.count, currentValue)

            DispatchQueue.main.async { [weak self] in
                self?.showIOSChoicePicker(
                    label: label,
                    options: options,
                    currentValue: currentValue,
                    callbackId: callbackId
                )
            }
        }

        static func osrsCalculatorPickerOptions(from raw: Any?) -> [(label: String, value: String)] {
            guard let items = raw as? [Any] else { return [] }
            return items.compactMap { item in
                if let dict = item as? [String: Any] {
                    let label = osrsStringValue(dict["label"]) ?? osrsStringValue(dict["value"])
                    let value = osrsStringValue(dict["value"]) ?? label
                    guard let label, let value, !label.isEmpty else { return nil }
                    return (label, value)
                }
                if let dict = item as? [String: String] {
                    let label = dict["label"] ?? dict["value"]
                    let value = dict["value"] ?? label
                    guard let label, let value, !label.isEmpty else { return nil }
                    return (label, value)
                }
                if let label = osrsStringValue(item), !label.isEmpty {
                    return (label, label)
                }
                return nil
            }
        }

        static func osrsStringValue(_ raw: Any?) -> String? {
            if let value = raw as? String { return value }
            if let value = raw as? NSNumber { return value.stringValue }
            if let value = raw as? NSString { return value as String }
            return nil
        }

        private func showIOSChoicePicker(label: String, options: [(label: String, value: String)], currentValue: String, callbackId: String) {
            guard let webView else {
                completeChoicePicker(callbackId: callbackId, selected: false, value: nil)
                return
            }

            let picker = osrsCalculatorChoicePickerController(
                titleText: label,
                options: options,
                currentValue: currentValue
            ) { [weak self] selected, value in
                self?.completeChoicePicker(callbackId: callbackId, selected: selected, value: value)
            }

            let nav = UINavigationController(rootViewController: picker)
            nav.modalPresentationStyle = .pageSheet
            if let sheet = nav.sheetPresentationController {
                sheet.detents = options.count > 8 ? [.medium(), .large()] : [.medium()]
                sheet.prefersGrabberVisible = true
                sheet.preferredCornerRadius = 16
            }

            guard let presentingVC = webView.osrsPresentingViewController() else {
                NSLog("osrsCalcApi: Could not find view controller to present picker")
                completeChoicePicker(callbackId: callbackId, selected: false, value: nil)
                return
            }
            if presentingVC.presentedViewController != nil {
                presentingVC.dismiss(animated: false) {
                    presentingVC.present(nav, animated: true)
                }
            } else {
                presentingVC.present(nav, animated: true)
            }
        }

        private func completeChoicePicker(callbackId: String, selected: Bool, value: String?) {
            guard !callbackId.isEmpty, let webView else { return }
            
            let response: [String: Any] = [
                "selected": selected,
                "value": value ?? ""
            ]
            
            guard let data = try? JSONSerialization.data(withJSONObject: response),
                  let json = String(data: data, encoding: .utf8) else {
                NSLog("osrsCalcApi: Failed to serialize picker response")
                return
            }
            
            let js = "if (window['\(callbackId)']) { window['\(callbackId)'](\(json)); }"
            webView.evaluateJavaScript(js) { _, error in
                if let error = error {
                    NSLog("osrsCalcApi: Failed to call picker callback: %@", error.localizedDescription)
                }
            }
        }

        private func completeCalculatorApi(id: String, result: [String: Any]) {
            guard let webView else { return }
            let envelope: [String: Any] = ["id": id, "result": result]
            guard let data = try? JSONSerialization.data(withJSONObject: envelope),
                  let json = String(data: data, encoding: .utf8) else {
                return
            }
            let ok = result["ok"] as? Bool ?? false
            let cached = result["cached"] as? Bool ?? false
            let body = result["body"] as? String ?? ""
            NSLog("osrsCalcApi: complete id=%@ ok=%@ cached=%@ bytes=%d", id, String(ok), String(cached), body.count)
            webView.evaluateJavaScript("window.osrsCalculatorApiComplete(\(json));", completionHandler: nil)
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
                
                // Stopwatch-only settled signal — must never reveal the body.
                if message.hasPrefix("Event: FirstViewportSettled") {
                    let loadGeneration = Self.loadGeneration(from: message)
                    DispatchQueue.main.async {
                        self.parent.viewModel.markFirstViewportSettled(loadGeneration: loadGeneration)
                    }
                // Handle first-viewport paint (primary reveal) and late styling-complete fallback
                } else if message.hasPrefix("Event: FirstViewPainted") || message.hasPrefix("Event: StylingScriptsComplete") {
                    let loadGeneration = Self.loadGeneration(from: message)
                    // ANDROID PARITY: first-viewport paint unlocks reveal; styling-complete is a late fallback
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
                        if let loadGeneration {
                            self.parent.viewModel.completeLoadingWithBodyReveal(loadGeneration: loadGeneration)
                        } else {
                            self.parent.viewModel.completeLoadingWithBodyReveal()
                        }
                    }
                } else {
                    print("📊 [\(timeString)] 📝 OTHER JS EVENT: \(message)")
                }
            }
        }

        private static func loadGeneration(from message: String) -> Int? {
            let prefixes = [
                "Event: FirstViewPainted:",
                "Event: StylingScriptsComplete:",
                "Event: FirstViewportSettled:"
            ]
            for prefix in prefixes {
                guard message.hasPrefix(prefix) else { continue }
                return Int(message.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return nil
        }

        private func firstViewGeneration(from body: [String: Any]) -> Int? {
            if let generation = body["generation"] as? Int {
                return generation
            }
            if let generation = body["generation"] as? NSNumber {
                return generation.intValue
            }
            return nil
        }

        private func handleLinkMessage(_ body: [String: Any]) {
            guard let action = body["action"] as? String,
                  action == "navigate",
                  let urlString = body["url"] as? String,
                  let url = URL(string: urlString) else { return }
            guard let articleURL = osrsArticleLinkRouter.appArticleURL(for: url) else { return }

            webView?.stopLoading()

            DispatchQueue.main.async {
                self.parent.appState.routeInternalArticleLink(
                    articleURL,
                    sourceArticleURL: self.parent.viewModel.pageUrl
                )
            }
        }
        
        private func jsFlag(_ value: Any?) -> Bool? {
            if let flag = value as? Bool {
                return flag
            }
            if let number = value as? NSNumber {
                return number.boolValue
            }
            if let string = value as? String {
                switch string.lowercased() {
                case "true", "1", "yes":
                    return true
                case "false", "0", "no":
                    return false
                default:
                    return nil
                }
            }
            return nil
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
                   let isOpening = jsFlag(body["isOpening"]) {
                    mapHandler?.onCollapsibleToggled(mapId: mapId, isOpening: isOpening)
                }

            case "onMapViewportVisibilityChanged":
                if let mapId = body["mapId"] as? String,
                   let isVisible = jsFlag(body["isVisible"]) {
                    mapHandler?.onMapViewportVisibilityChanged(mapId: mapId, isVisible: isVisible)
                }
                
            case "setHorizontalScroll":
                if let inProgress = body["inProgress"] as? Bool {
                    mapHandler?.setHorizontalScroll(inProgress: inProgress)
                }

            case "setHorizontalScrollGesture":
                if let phase = body["phase"] as? String,
                   let gestureId = body["gestureId"] as? String {
                    let ownerId = body["ownerId"] as? String ?? "article-navigation"
                    let isLocalOwner: Bool
                    if let explicit = body["isLocalOwner"] as? Bool {
                        isLocalOwner = explicit
                    } else {
                        let inProgress = phase == "begin" || phase == "change"
                        isLocalOwner = inProgress && ownerId != "article-navigation"
                    }
                    mapHandler?.setHorizontalScrollGesture(
                        phase: phase,
                        gestureId: gestureId,
                        ownerId: ownerId,
                        isLocalOwner: isLocalOwner
                    )
                }
                
            case "log":
                if let message = body["message"] as? String {
                    mapHandler?.log(message: message)
                }

            case "openFloorNumberingSettings":
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .showAppearanceSettings,
                        object: nil,
                        userInfo: ["highlightFloorNumbering": true]
                    )
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

private final class osrsCalculatorChoicePickerController: UITableViewController {
    private let options: [(label: String, value: String)]
    private let currentValue: String
    private let onComplete: (Bool, String?) -> Void
    private var didComplete = false

    init(
        titleText: String,
        options: [(label: String, value: String)],
        currentValue: String,
        onComplete: @escaping (Bool, String?) -> Void
    ) {
        self.options = options
        self.currentValue = currentValue
        self.onComplete = onComplete
        super.init(style: .insetGrouped)
        title = titleText
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "option")
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        options.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "option", for: indexPath)
        let option = options[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = option.label
        cell.contentConfiguration = content
        cell.accessoryType = (option.value == currentValue || option.label == currentValue) ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        finish(selected: true, value: options[indexPath.row].value)
    }

    @objc private func cancelTapped() {
        finish(selected: false, value: nil)
    }

    private func finish(selected: Bool, value: String?) {
        guard !didComplete else { return }
        didComplete = true
        dismiss(animated: true) { [onComplete] in
            onComplete(selected, value)
        }
    }
}

private extension UIView {
    func osrsNearestViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let viewController = current as? UIViewController {
                return viewController
            }
            responder = current.next
        }
        return window?.rootViewController
    }

    func osrsPresentingViewController() -> UIViewController? {
        func topMost(from root: UIViewController?) -> UIViewController? {
            var current = root
            while let presented = current?.presentedViewController {
                current = presented
            }
            if let nav = current as? UINavigationController {
                return nav.visibleViewController ?? nav
            }
            if let tabs = current as? UITabBarController {
                return topMost(from: tabs.selectedViewController) ?? tabs
            }
            return current
        }

        if let nearest = osrsNearestViewController(), nearest.view.window != nil {
            return topMost(from: nearest) ?? nearest
        }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            let windows = scene.windows.filter { $0.isKeyWindow || $0.isHidden == false }
            for window in windows {
                if let top = topMost(from: window.rootViewController), top.view.window != nil {
                    return top
                }
            }
        }
        return window?.rootViewController
    }
}

#Preview {
    ArticleWebView(viewModel: ArticleViewModel(pageUrl: URL(string: "about:blank")!))
        .environmentObject(AppState())
        .environmentObject(osrsThemeManager.preview)
}
