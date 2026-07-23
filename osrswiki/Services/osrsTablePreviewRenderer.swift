//
//  osrsTablePreviewRenderer.swift
//  OSRS Wiki
//
//  iOS equivalent to Android's TablePreviewRenderer
//  Generates table collapse previews using actual wiki content
//

import SwiftUI
import UIKit
import WebKit
import Combine

// MARK: - WebView Navigation Delegate for Proper Lifecycle Management
@MainActor
private final class TablePreviewContinuation {
    private var continuation: CheckedContinuation<UIImage, Never>?

    init(_ continuation: CheckedContinuation<UIImage, Never>) {
        self.continuation = continuation
    }

    var isPending: Bool {
        continuation != nil
    }

    func resume(with image: UIImage) {
        guard let continuation = continuation else { return }
        self.continuation = nil
        continuation.resume(returning: image)
    }
}

@MainActor
class TablePreviewWebViewDelegate: NSObject, WKNavigationDelegate {
    private var completion: ((UIImage) -> Void)?
    private let targetSize: CGSize
    private let collapsed: Bool
    private weak var renderer: osrsTablePreviewRenderer?
    private let delegateId = UUID().uuidString.prefix(8)
    private var startTime: Date = Date()

    // LOADING STATE COORDINATION: Track both WebView and ArticleViewModel loading completion
    private var webViewDidFinish = false
    private var articleViewModelReady = false
    private weak var currentWebView: WKWebView? // Store WebView reference for capture
    private weak var articleViewModel: ArticleViewModel? // Forward navigation events to maintain loading state

    init(targetSize: CGSize, collapsed: Bool, renderer: osrsTablePreviewRenderer?, articleViewModel: ArticleViewModel?, completion: @escaping (UIImage) -> Void) {
        self.targetSize = targetSize
        self.collapsed = collapsed
        self.renderer = renderer
        self.articleViewModel = articleViewModel
        self.completion = completion
        super.init()
        self.startTime = Date()
        print("🔗 TablePreviewDelegate-\(delegateId): Created for \(collapsed ? "collapsed" : "expanded") table")

    }

    // MARK: - ArticleViewModel Loading State Monitoring

    /// Set the ArticleViewModel reference for navigation event forwarding
    func setArticleViewModel(_ viewModel: ArticleViewModel) {
        self.articleViewModel = viewModel
        print("🔗 TablePreviewDelegate-\(delegateId): ArticleViewModel reference set for navigation forwarding")
    }

    /// Called by ArticleView when loading completes
    func onArticleViewModelLoadingComplete() {
        let elapsed = Date().timeIntervalSince(startTime)
        print("📊 TablePreviewDelegate-\(delegateId): ArticleViewModel loading completed via callback (+\(String(format: "%.2f", elapsed))s)")

        if !articleViewModelReady {
            articleViewModelReady = true
            checkBothCompletionStatesAndCapture()
        }
    }

    private func checkBothCompletionStatesAndCapture() {
        let elapsed = Date().timeIntervalSince(startTime)
        print("📊 TablePreviewDelegate-\(delegateId): Checking completion states - WebView: \(webViewDidFinish), ArticleViewModel: \(articleViewModelReady) (+\(String(format: "%.2f", elapsed))s)")

        // RESTORED: Pure callback-based coordination - wait for BOTH WebView AND ArticleViewModel
        if webViewDidFinish && articleViewModelReady {
            print("🎯 TablePreviewDelegate-\(delegateId): Both loading states complete - starting image capture!")
            startImageCaptureProcess()
        } else {
            print("⏳ TablePreviewDelegate-\(delegateId): Still waiting - WebView: \(webViewDidFinish), ArticleViewModel: \(articleViewModelReady)")
        }
    }

    private func startImageCaptureProcess() {
        // This replaces the old captureImageAndCleanup method
        guard let completion = completion else {
            print("❌ TablePreviewDelegate-\(delegateId): startImageCaptureProcess called but completion is nil")
            return
        }

        let elapsed = Date().timeIntervalSince(startTime)
        print("📊 TablePreviewDelegate-\(delegateId): 🎯 Starting image capture process (+\(String(format: "%.2f", elapsed))s)")

        // Ready to capture - both loading states are complete

        // MUCH SHORTER delay now that we know both systems are ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else {
                print("❌ TablePreviewDelegate-\(self?.delegateId ?? "unknown"): Self deallocated during capture delay")
                completion(UIImage())
                return
            }

            print("📊 TablePreviewDelegate-\(self.delegateId): 🔧 Forcing table state to \(self.collapsed ? "collapsed" : "expanded")")

            // Force table state - this should work immediately since page is ready
            if let webView = self.findWebViewInHierarchy() {
                self.renderer?.forceTableStateInWebView(webView: webView, collapsed: self.collapsed)

                // Very short delay after JavaScript execution
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    guard let self = self else {
                        print("❌ TablePreviewDelegate-\(self?.delegateId ?? "unknown"): Self deallocated during final capture delay")
                        completion(UIImage())
                        return
                    }

                    print("📊 TablePreviewDelegate-\(self.delegateId): 📸 Performing final image capture")
                    self.performFinalImageCapture(completion: completion)
                }
            } else {
                print("❌ TablePreviewDelegate-\(self.delegateId): Could not find WebView for table state forcing")
                completion(UIImage())
            }
        }
    }

    // Helper to find WebView in current context
    private func findWebViewInHierarchy() -> WKWebView? {
        return currentWebView
    }

    // UPDATED: Final image capture method (replaces old performImageCapture)
    private func performFinalImageCapture(completion: @escaping (UIImage) -> Void) {
        let elapsed = Date().timeIntervalSince(startTime)
        print("📊 TablePreviewDelegate-\(delegateId): 📸 performFinalImageCapture started (+\(String(format: "%.2f", elapsed))s)")

        guard let webView = currentWebView else {
            print("❌ TablePreviewDelegate-\(delegateId): No WebView reference available for capture")
            completion(UIImage())
            self.completion = nil
            return
        }

        // Find the hosting controller by traversing up the view hierarchy
        var hostingController: UIViewController? = nil
        var currentView: UIView? = webView
        var traversalSteps = 0

        // Traverse up to find any hosting controller
        while currentView != nil && traversalSteps < 20 { // Limit traversal to prevent infinite loops
            traversalSteps += 1

            // Check if current view's next responder is a hosting controller
            if let controller = currentView?.next as? UIViewController,
               String(describing: type(of: controller)).contains("UIHostingController") {
                hostingController = controller
                print("📊 TablePreviewDelegate-\(delegateId): Found hosting controller via next responder (step \(traversalSteps))")
                break
            }
            // Check parent view controller for hosting controller
            if let parentController = currentView?.parentViewController,
               String(describing: type(of: parentController)).contains("UIHostingController") {
                hostingController = parentController
                print("📊 TablePreviewDelegate-\(delegateId): Found hosting controller via parent controller (step \(traversalSteps))")
                break
            }
            currentView = currentView?.superview
        }

        guard let controller = hostingController else {
            print("❌ TablePreviewDelegate-\(delegateId): Could not find hosting controller after \(traversalSteps) traversal steps")
            completion(UIImage())
            self.completion = nil
            return
        }

        // Validate WebView dimensions
        let webViewSize = webView.frame.size
        print("📊 TablePreviewDelegate-\(delegateId): WebView size: \(webViewSize), controller view size: \(controller.view.frame.size)")

        if webViewSize.width <= 0 || webViewSize.height <= 0 {
            print("❌ TablePreviewDelegate-\(delegateId): WebView has zero dimensions - aborting capture")
            completion(UIImage())
            self.completion = nil
            return
        }

        // Force final layout
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        print("📊 TablePreviewDelegate-\(delegateId): Layout forced, ready to capture image")

        // Capture the image with WebView's actual size
        let safeAreaTop = controller.view.safeAreaInsets.top
        let actualContentHeight = max(webViewSize.height, targetSize.height - safeAreaTop)
        let actualContentSize = CGSize(width: max(webViewSize.width, targetSize.width), height: actualContentHeight)

        print("📊 TablePreviewDelegate-\(delegateId): Capturing image with size: \(actualContentSize) (target: \(targetSize), safeArea: \(safeAreaTop))")

        let renderer = UIGraphicsImageRenderer(size: actualContentSize)
        let image = renderer.image { context in
            // Clear background
            context.cgContext.clear(CGRect(origin: .zero, size: actualContentSize))
            context.cgContext.translateBy(x: 0, y: -safeAreaTop)

            // Render the controller's view
            controller.view.layer.render(in: context.cgContext)
        }

        // Validate captured image
        let finalElapsed = Date().timeIntervalSince(startTime)
        if image.size.width <= 0 || image.size.height <= 0 {
            print("❌ TablePreviewDelegate-\(delegateId): Captured image has zero dimensions (+\(String(format: "%.2f", finalElapsed))s total)")
            completion(UIImage())
        } else {
            print("✅ TablePreviewDelegate-\(delegateId): Image captured successfully - size: \(image.size) (+\(String(format: "%.2f", finalElapsed))s total)")
            completion(image)
        }

        // CRITICAL: Cancel asset handler tasks before WebView destruction to prevent crashes
        if let webView = currentWebView {
            // Get asset handler from WebView configuration and cancel all tasks
            if let assetHandler = webView.configuration.urlSchemeHandler(forURLScheme: "app-assets") as? IOSAssetHandler {
                let taskCount = assetHandler.activeTaskCount
                if taskCount > 0 {
                    print("🚨 TablePreviewDelegate-\(delegateId): Found \(taskCount) active asset handler tasks - synchronously cancelling before WebView destruction")
                    assetHandler.cancelAllActiveTasksAndWait()
                } else {
                    print("✅ TablePreviewDelegate-\(delegateId): No active asset handler tasks to cancel")
                }
            } else {
                print("⚠️ TablePreviewDelegate-\(delegateId): Could not find asset handler for cleanup")
            }

            // Clear WebView navigation delegate to prevent further callbacks
            webView.navigationDelegate = nil
            print("📊 TablePreviewDelegate-\(delegateId): WebView navigation delegate cleared")
        }

        // Clean up window safely
        if let window = controller.view.window {
            window.isHidden = true
            window.rootViewController = nil
            print("📊 TablePreviewDelegate-\(delegateId): Window cleaned up")
        } else {
            print("⚠️ TablePreviewDelegate-\(delegateId): No window to clean up")
        }

        self.completion = nil
        print("📊 TablePreviewDelegate-\(delegateId): 🧹 Delegate cleanup completed")
    }

    // MARK: - WKNavigationDelegate Methods with Enhanced Logging

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        let elapsed = Date().timeIntervalSince(startTime)
        print("📊 TablePreviewDelegate-\(delegateId): ⚡ didStartProvisionalNavigation called (+\(String(format: "%.2f", elapsed))s)")

        // Forward to ArticleViewModel to maintain loading state
        articleViewModel?.webView(webView, didStartProvisionalNavigation: navigation)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        let elapsed = Date().timeIntervalSince(startTime)
        print("📊 TablePreviewDelegate-\(delegateId): 📄 didCommit called (+\(String(format: "%.2f", elapsed))s)")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let elapsed = Date().timeIntervalSince(startTime)
        print("📊 TablePreviewDelegate-\(delegateId): ✅ didFinish called (+\(String(format: "%.2f", elapsed))s) - WebView finished loading")
        print("📊 TablePreviewDelegate-\(delegateId): WebView size: \(webView.frame.size), URL: \(webView.url?.absoluteString ?? "nil")")

        // Forward to ArticleViewModel to maintain loading state
        articleViewModel?.webView(webView, didFinish: navigation)

        // Verify completion callback is still available
        guard completion != nil else {
            print("❌ TablePreviewDelegate-\(delegateId): Completion callback is nil - delegate was already cleaned up!")
            return
        }

        // UPDATED: Mark WebView as complete and check both states
        webViewDidFinish = true
        currentWebView = webView // Store reference for later use
        print("✅ TablePreviewDelegate-\(delegateId): WebView loading completed!")
        checkBothCompletionStatesAndCapture()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let elapsed = Date().timeIntervalSince(startTime)
        print("❌ TablePreviewDelegate-\(delegateId): didFail called (+\(String(format: "%.2f", elapsed))s) - Error: \(error.localizedDescription)")

        // Forward to ArticleViewModel to maintain loading state
        articleViewModel?.webView(webView, didFail: navigation, withError: error)

        // Return empty image on failure and clean up
        if let completion = completion {
            print("📊 TablePreviewDelegate-\(delegateId): Returning empty image due to navigation failure")
            completion(UIImage())
            self.completion = nil
        } else {
            print("⚠️ TablePreviewDelegate-\(delegateId): Completion already nil during failure handling")
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let elapsed = Date().timeIntervalSince(startTime)
        print("❌ TablePreviewDelegate-\(delegateId): didFailProvisionalNavigation called (+\(String(format: "%.2f", elapsed))s) - Error: \(error.localizedDescription)")

        // Forward to ArticleViewModel to maintain loading state
        articleViewModel?.webView(webView, didFailProvisionalNavigation: navigation, withError: error)

        // Return empty image on failure and clean up
        if let completion = completion {
            print("📊 TablePreviewDelegate-\(delegateId): Returning empty image due to provisional navigation failure")
            completion(UIImage())
            self.completion = nil
        } else {
            print("⚠️ TablePreviewDelegate-\(delegateId): Completion already nil during provisional failure handling")
        }
    }

    // OLD METHOD REMOVED - replaced by startImageCaptureProcess() and performFinalImageCapture()

    private func performImageCapture(webView: WKWebView, completion: @escaping (UIImage) -> Void) {
        let elapsed = Date().timeIntervalSince(startTime)
        print("📊 TablePreviewDelegate-\(delegateId): 📸 performImageCapture started (+\(String(format: "%.2f", elapsed))s)")

        // Find the hosting controller by traversing up the view hierarchy
        var hostingController: UIViewController? = nil
        var currentView: UIView? = webView
        var traversalSteps = 0

        // Traverse up to find any hosting controller
        while currentView != nil && traversalSteps < 20 { // Limit traversal to prevent infinite loops
            traversalSteps += 1

            // Check if current view's next responder is a hosting controller
            if let controller = currentView?.next as? UIViewController,
               String(describing: type(of: controller)).contains("UIHostingController") {
                hostingController = controller
                print("📊 TablePreviewDelegate-\(delegateId): Found hosting controller via next responder (step \(traversalSteps))")
                break
            }
            // Check parent view controller for hosting controller
            if let parentController = currentView?.parentViewController,
               String(describing: type(of: parentController)).contains("UIHostingController") {
                hostingController = parentController
                print("📊 TablePreviewDelegate-\(delegateId): Found hosting controller via parent controller (step \(traversalSteps))")
                break
            }
            currentView = currentView?.superview
        }

        guard let controller = hostingController else {
            print("❌ TablePreviewDelegate-\(delegateId): Could not find hosting controller after \(traversalSteps) traversal steps")
            completion(UIImage())
            self.completion = nil
            return
        }

        // Validate WebView dimensions
        let webViewSize = webView.frame.size
        print("📊 TablePreviewDelegate-\(delegateId): WebView size: \(webViewSize), controller view size: \(controller.view.frame.size)")

        if webViewSize.width <= 0 || webViewSize.height <= 0 {
            print("❌ TablePreviewDelegate-\(delegateId): WebView has zero dimensions - aborting capture")
            completion(UIImage())
            self.completion = nil
            return
        }

        // Force final layout
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        print("📊 TablePreviewDelegate-\(delegateId): Layout forced, ready to capture image")

        // Capture the image with WebView's actual size
        let safeAreaTop = controller.view.safeAreaInsets.top
        let actualContentHeight = max(webViewSize.height, targetSize.height - safeAreaTop)
        let actualContentSize = CGSize(width: max(webViewSize.width, targetSize.width), height: actualContentHeight)

        print("📊 TablePreviewDelegate-\(delegateId): Capturing image with size: \(actualContentSize) (target: \(targetSize), safeArea: \(safeAreaTop))")

        let renderer = UIGraphicsImageRenderer(size: actualContentSize)
        let image = renderer.image { context in
            // Clear background
            context.cgContext.clear(CGRect(origin: .zero, size: actualContentSize))
            context.cgContext.translateBy(x: 0, y: -safeAreaTop)

            // Render the controller's view
            controller.view.layer.render(in: context.cgContext)
        }

        // Validate captured image
        let finalElapsed = Date().timeIntervalSince(startTime)
        if image.size.width <= 0 || image.size.height <= 0 {
            print("❌ TablePreviewDelegate-\(delegateId): Captured image has zero dimensions (+\(String(format: "%.2f", finalElapsed))s total)")
            completion(UIImage())
        } else {
            print("✅ TablePreviewDelegate-\(delegateId): Image captured successfully - size: \(image.size) (+\(String(format: "%.2f", finalElapsed))s total)")
            completion(image)
        }

        // CRITICAL: Cancel asset handler tasks before WebView destruction to prevent crashes
        if let webView = currentWebView {
            // Get asset handler from WebView configuration and cancel all tasks
            if let assetHandler = webView.configuration.urlSchemeHandler(forURLScheme: "app-assets") as? IOSAssetHandler {
                let taskCount = assetHandler.activeTaskCount
                if taskCount > 0 {
                    print("🚨 TablePreviewDelegate-\(delegateId): Found \(taskCount) active asset handler tasks - synchronously cancelling before WebView destruction")
                    assetHandler.cancelAllActiveTasksAndWait()
                } else {
                    print("✅ TablePreviewDelegate-\(delegateId): No active asset handler tasks to cancel")
                }
            } else {
                print("⚠️ TablePreviewDelegate-\(delegateId): Could not find asset handler for cleanup")
            }

            // Clear WebView navigation delegate to prevent further callbacks
            webView.navigationDelegate = nil
            print("📊 TablePreviewDelegate-\(delegateId): WebView navigation delegate cleared")
        }

        // Clean up window safely
        if let window = controller.view.window {
            window.isHidden = true
            window.rootViewController = nil
            print("📊 TablePreviewDelegate-\(delegateId): Window cleaned up")
        } else {
            print("⚠️ TablePreviewDelegate-\(delegateId): No window to clean up")
        }

        self.completion = nil
        print("📊 TablePreviewDelegate-\(delegateId): 🧹 Delegate cleanup completed")
    }
}

// MARK: - UIView Extension for Parent View Controller
extension UIView {
    var parentViewController: UIViewController? {
        var responder: UIResponder? = self
        while responder != nil {
            if let viewController = responder as? UIViewController {
                return viewController
            }
            responder = responder?.next
        }
        return nil
    }
}

/// Generates table collapse preview images by rendering actual wiki content
@MainActor
class osrsTablePreviewRenderer: ObservableObject {

    // Singleton instance for shared cache
    static let shared = osrsTablePreviewRenderer()

    // No fixed dimensions - return full device-sized renders

    // Cache for generated previews
    private var previewCache: [String: UIImage] = [:]

    // CONCURRENCY CONTROL: Prevent multiple WebView creations simultaneously
    private let webViewSemaphore = DispatchSemaphore(value: 1) // Only 1 concurrent WebView generation
    private var activeGenerations: Set<String> = []
    private let generationQueue = DispatchQueue(label: "TablePreviewRenderer.Generation", qos: .userInitiated)

    // Private initializer to ensure singleton usage
    private init() {}

    /// Generate preview showing expanded vs collapsed table states with retry mechanism and concurrency control
    func generateTablePreview(collapsed: Bool, theme: any osrsThemeProtocol) async -> UIImage {
        let cacheKey = "table-\(collapsed ? "collapsed" : "expanded")-\(theme.name)"

        print("📊 TablePreviewRenderer: Generating preview for \(collapsed ? "collapsed" : "expanded") table")

        // Check cache first
        if let cachedImage = previewCache[cacheKey] {
            print("📊 TablePreviewRenderer: Found cached image for \(cacheKey)")
            return cachedImage
        }

        // CONCURRENCY CONTROL: Prevent duplicate generations and limit concurrent WebViews
        if activeGenerations.contains(cacheKey) {
            print("⏳ TablePreviewRenderer: Generation already in progress for \(cacheKey) - waiting...")

            // Wait for active generation to complete
            var attempts = 0
            while activeGenerations.contains(cacheKey) && attempts < 30 { // 15 second timeout
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                attempts += 1

                // Check if cache was populated by the other generation
                if let cachedImage = previewCache[cacheKey] {
                    print("✅ TablePreviewRenderer: Found cached result from parallel generation for \(cacheKey)")
                    return cachedImage
                }
            }

            if attempts >= 30 {
                print("⚠️ TablePreviewRenderer: Timeout waiting for parallel generation - proceeding anyway")
            }
        }

        // Mark this generation as active
        activeGenerations.insert(cacheKey)
        defer {
            activeGenerations.remove(cacheKey)
        }

        // SEMAPHORE CONTROL: Wait for WebView generation slot
        return await withCheckedContinuation { continuation in
            generationQueue.async {
                self.webViewSemaphore.wait()

                Task { @MainActor in
                    defer {
                        self.webViewSemaphore.signal()
                    }

                    print("🔒 TablePreviewRenderer: Acquired WebView generation lock for \(cacheKey)")

                    // RETRY MECHANISM: Try up to 2 times with WebView rendering, then fallback
                    var previewImage: UIImage? = nil
                    let maxAttempts = 2

                    for attempt in 1...maxAttempts {
                        print("📊 TablePreviewRenderer: Attempt \(attempt)/\(maxAttempts) for \(collapsed ? "collapsed" : "expanded") table")

                        let attemptImage = await self.generateWebViewTablePreview(collapsed: collapsed, theme: theme)

                        // Check if we got a valid image (non-zero size)
                        if attemptImage.size.width > 0 && attemptImage.size.height > 0 {
                            print("✅ TablePreviewRenderer: Attempt \(attempt) succeeded - image size: \(attemptImage.size)")
                            previewImage = attemptImage
                            break
                        } else {
                            print("❌ TablePreviewRenderer: Attempt \(attempt) failed - got zero-size image")

                            if attempt < maxAttempts {
                                print("🔄 TablePreviewRenderer: Retrying in 1 second...")
                                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                            }
                        }
                    }

                    // GRACEFUL DEGRADATION: If WebView rendering failed, use fallback generation
                    let finalImage: UIImage
                    if let validImage = previewImage, validImage.size.width > 0 && validImage.size.height > 0 {
                        finalImage = validImage
                        print("✅ TablePreviewRenderer: Using WebView-generated image")
                    } else {
                        print("🚨 TablePreviewRenderer: WebView rendering failed after \(maxAttempts) attempts - using fallback")
                        finalImage = self.generateFallbackTableImage(collapsed: collapsed, theme: theme)
                        print("📊 TablePreviewRenderer: Fallback image size: \(finalImage.size)")
                    }

                    // Cache the result (even if it's a fallback)
                    self.previewCache[cacheKey] = finalImage

                    print("🔓 TablePreviewRenderer: Released WebView generation lock for \(cacheKey)")
                    continuation.resume(returning: finalImage)
                }
            }
        }
    }

    /// Generate table preview using ACTUAL ArticleView with real Varrock Wikipedia content
    private func generateWebViewTablePreview(collapsed: Bool, theme: any osrsThemeProtocol) async -> UIImage {
        // Create app state and theme manager for ArticleView environment
        let appState = AppState()
        let themeManager = osrsThemeManager()

        // CRITICAL FIX: Set the theme manager to match the preview theme to prevent contamination
        if theme.name.lowercased().contains("light") {
            themeManager.setTheme(.osrsLight)
        } else if theme.name.lowercased().contains("dark") {
            themeManager.setTheme(.osrsDark)
        }

        print("📊 TablePreviewRenderer: Set theme manager to \(themeManager.selectedTheme.rawValue) for \(theme.name) preview")

        // Use REAL ArticleView pointing to actual Varrock Wikipedia page
        let varrockUrl = URL(string: "https://oldschool.runescape.wiki/w/Varrock")!
        // Create a mock overlay manager for preview rendering
        let mockOverlayManager = GlobalOverlayManager()

        // Get device content size for delegate
        let deviceSize = await getDeviceContentSize()

        // Create table preview with delegate-based WebView lifecycle management
        return await withCheckedContinuation { continuation in
            let continuationBox = TablePreviewContinuation(continuation)

            // Create WebView delegate with completion callback
            let webViewDelegate = TablePreviewWebViewDelegate(
                targetSize: deviceSize,
                collapsed: collapsed,
                renderer: self,
                articleViewModel: nil  // Will be set via callback
            ) { image in
                continuationBox.resume(with: image)
            }

            let realArticleView = ArticleView(
                pageTitle: "Varrock",
                pageUrl: varrockUrl,
                collapseTablesEnabled: collapsed,
                excludeFromHistory: true,
                navigationDelegate: webViewDelegate,
                onLoadingComplete: { articleViewModel in
                    // This callback is called when ArticleViewModel.isLoading becomes false
                    print("📊 TablePreviewRenderer: ArticleView loading complete callback triggered with viewModel")
                    // Set the ArticleViewModel reference on the delegate for navigation forwarding
                    webViewDelegate.setArticleViewModel(articleViewModel)
                    webViewDelegate.onArticleViewModelLoadingComplete()
                },
                showProgressBar: false,  // Disable progress bar for clean preview capture
                managesMainTabBarVisibility: false
            )
            .environmentObject(appState)
            .environmentObject(themeManager)
            .environment(\.osrsTheme, theme)
            .overlayManager(mockOverlayManager) // Provide mock overlay manager

            // Render WebView with delegate already attached
            Task {
                let result = await renderWebViewWithDelegate(realArticleView, size: deviceSize, delegate: webViewDelegate)
                if !result {
                    // Fallback: return empty image if rendering fails
                    continuationBox.resume(with: UIImage())
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 14.0) {
                guard continuationBox.isPending else { return }

                print("⚠️ TablePreviewRenderer: Timed out waiting for table preview delegate - using fallback image")
                continuationBox.resume(with: self.generateFallbackTableImage(collapsed: collapsed, theme: theme))
            }
        }
    }

    /// Render WebView with delegate already attached - with robust fallback detection
    private func renderWebViewWithDelegate(_ view: some View, size: CGSize, delegate: TablePreviewWebViewDelegate) async -> Bool {
        return await withCheckedContinuation { continuation in
            var hasCompleted = false
            let renderId = UUID().uuidString.prefix(6)

            DispatchQueue.main.async {
                // Create hosting controller with view wrapped to ignore safe area
                let wrappedView = view
                    .ignoresSafeArea()
                    .frame(width: size.width, height: size.height)

                let controller = UIHostingController(rootView: wrappedView)
                controller.view.insetsLayoutMarginsFromSafeArea = false

                // Create a temporary window to provide proper view hierarchy
                let window = UIWindow(frame: CGRect(origin: .zero, size: size))
                window.rootViewController = controller
                window.isHidden = false

                // Set the controller's view frame
                controller.view.frame = CGRect(origin: .zero, size: size)
                controller.view.backgroundColor = UIColor.clear

                // Force layout cycle
                controller.view.setNeedsLayout()
                controller.view.layoutIfNeeded()

                print("📊 TablePreviewRenderer-\(renderId): WebView with delegate created, waiting for navigation completion...")

                // The delegate will handle the completion - just return success
                if !hasCompleted {
                    hasCompleted = true
                    continuation.resume(returning: true)
                }

                // Multi-level fallback timeout system
                // Level 1: Check for basic loading progress after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    if let webView = self.findWebView(in: controller.view) {
                        let isLoading = webView.isLoading
                        let progress = webView.estimatedProgress
                        let hasUrl = webView.url != nil

                        print("📊 TablePreviewRenderer-\(renderId): 🔍 3s check - Loading: \(isLoading), Progress: \(Int(progress * 100))%, URL: \(hasUrl)")

                        if !isLoading && progress > 0 && hasUrl {
                            print("📊 TablePreviewRenderer-\(renderId): ✅ WebView appears to be loaded but delegate didn't fire - this might be the issue")
                        }
                    } else {
                        print("❌ TablePreviewRenderer-\(renderId): WebView not found in hierarchy at 3s check")
                    }
                }

                // Level 2: Stronger intervention after 8 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
                    if let webView = self.findWebView(in: controller.view) {
                        let isLoading = webView.isLoading
                        let progress = webView.estimatedProgress
                        let hasUrl = webView.url != nil

                        print("📊 TablePreviewRenderer-\(renderId): ⚠️ 8s intervention - Loading: \(isLoading), Progress: \(Int(progress * 100))%, URL: \(hasUrl)")

                        // If WebView appears loaded but delegate never fired, attempt manual capture
                        if !isLoading && progress >= 0.9 && hasUrl {
                            print("📊 TablePreviewRenderer-\(renderId): 🚨 FALLBACK: WebView loaded but delegate failed - attempting manual navigation trigger")

                            // Try to manually trigger the delegate by calling a harmless JavaScript
                            webView.evaluateJavaScript("document.readyState") { result, error in
                                if let readyState = result as? String {
                                    print("📊 TablePreviewRenderer-\(renderId): Document ready state: \(readyState)")

                                    if readyState == "complete" {
                                        print("📊 TablePreviewRenderer-\(renderId): 🔧 MANUAL TRIGGER: Calling delegate didFinish manually")
                                        // The delegate should be the current navigation delegate
                                        if let currentDelegate = webView.navigationDelegate as? TablePreviewWebViewDelegate {
                                            currentDelegate.webView(webView, didFinish: nil)
                                        }
                                    }
                                } else {
                                    print("❌ TablePreviewRenderer-\(renderId): Could not determine document ready state: \(error?.localizedDescription ?? "unknown")")
                                }
                            }
                        }
                    }
                }

                // Level 3: Final timeout after 12 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 12.0) {
                    print("⚠️ TablePreviewRenderer-\(renderId): Final timeout reached after 12 seconds - outer preview continuation will fall back if still pending")
                }
            }
        }
    }

    /// Render real WebView with proper async waiting for page load (like Android approach)
    private func renderRealWebViewWithWait(_ view: some View, targetSize: CGSize, collapsed: Bool) async -> UIImage {
        // Get device screen bounds (like Android getAppContentBounds)
        let deviceSize = await getDeviceContentSize()

        print("📊 Rendering REAL WebView at device size: \(deviceSize), then scaling to: \(targetSize)")

        // First render at full device size with WebView load waiting
        let deviceImage = await renderRealWebViewToImageWithWait(view, size: deviceSize, collapsed: collapsed)

        // Then scale down to target preview size
        return scaleImageToTargetSize(deviceImage, targetSize: targetSize)
    }

    /// Render real WebView to image with proper callback-based page load waiting
    private func renderRealWebViewToImageWithWait(_ view: some View, size: CGSize, collapsed: Bool) async -> UIImage {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async { [weak self] in
                // Create hosting controller with view wrapped to ignore safe area
                let wrappedView = view
                    .ignoresSafeArea()
                    .frame(width: size.width, height: size.height)

                let controller = UIHostingController(rootView: wrappedView)
                controller.view.insetsLayoutMarginsFromSafeArea = false

                // Create a temporary window to provide proper view hierarchy
                let window = UIWindow(frame: CGRect(origin: .zero, size: size))
                window.rootViewController = controller
                window.isHidden = false

                // Set the controller's view frame
                controller.view.frame = CGRect(origin: .zero, size: size)
                controller.view.backgroundColor = UIColor.clear

                // Force layout cycle
                controller.view.setNeedsLayout()
                controller.view.layoutIfNeeded()

                // Create WebView delegate with completion callback
                let webViewDelegate = TablePreviewWebViewDelegate(
                    targetSize: size,
                    collapsed: collapsed,
                    renderer: self,
                    articleViewModel: nil  // Will be set via callback
                ) { image in
                    continuation.resume(returning: image)
                }

                // Find the WebView in the view hierarchy and set delegate
                self?.findAndSetWebViewDelegate(in: controller.view, delegate: webViewDelegate)

                print("📊 TablePreviewRenderer: WebView delegate set, waiting for navigation completion...")

                // Fallback timeout (much longer than the old 5 seconds)
                DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
                    // If we reach here, the delegate didn't fire - return empty image
                    print("⚠️ TablePreviewRenderer: Timeout reached, returning empty image")
                    continuation.resume(returning: UIImage())
                }
            }
        }
    }

    /// Recursively find WebView in view hierarchy and set navigation delegate
    private func findAndSetWebViewDelegate(in view: UIView, delegate: TablePreviewWebViewDelegate) {
        if let webView = view as? WKWebView {
            webView.navigationDelegate = delegate
            print("✅ TablePreviewRenderer: Found WebView and set navigation delegate")
            return
        }

        for subview in view.subviews {
            findAndSetWebViewDelegate(in: subview, delegate: delegate)
        }
    }

    // Removed renderViewAtDeviceSizeThenScale - no longer needed

    /// Get device content size (excluding system UI like Android)
    private func getDeviceContentSize() async -> CGSize {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                // Get main screen bounds
                let screen = UIScreen.main
                let fullSize = screen.bounds.size

                // Account for safe area (like Android system UI)
                let window = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first?.windows.first

                let safeAreaInsets = window?.safeAreaInsets ?? UIEdgeInsets.zero

                // Calculate content area (excluding system UI)
                let contentWidth = fullSize.width
                let contentHeight = fullSize.height - safeAreaInsets.top - safeAreaInsets.bottom

                let contentSize = CGSize(width: contentWidth, height: contentHeight)
                print("📊 Device content size: \(contentSize) (full: \(fullSize), insets: \(safeAreaInsets))")

                continuation.resume(returning: contentSize)
            }
        }
    }

    /// Scale image to target size maintaining aspect ratio
    private func scaleImageToTargetSize(_ sourceImage: UIImage, targetSize: CGSize) -> UIImage {
        let sourceSize = sourceImage.size

        // Scale to FILL the target size (use max to ensure no letterboxing)
        let scaleX = targetSize.width / sourceSize.width
        let scaleY = targetSize.height / sourceSize.height
        let scale = max(scaleX, scaleY) // Use max to fill completely

        let scaledWidth = sourceSize.width * scale
        let scaledHeight = sourceSize.height * scale

        print("📊 FILL scaling from \(sourceSize) to \(scaledWidth)x\(scaledHeight) (target: \(targetSize))")

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { context in
            // Center the scaled image and crop excess
            let x = (targetSize.width - scaledWidth) / 2
            let y = (targetSize.height - scaledHeight) / 2
            let drawRect = CGRect(x: x, y: y, width: scaledWidth, height: scaledHeight)

            // Set clipping to target size
            context.cgContext.clip(to: CGRect(origin: .zero, size: targetSize))

            // Draw the scaled image centered
            sourceImage.draw(in: drawRect)
        }
    }


    /// Render a SwiftUI view to UIImage with proper view hierarchy
    private func renderViewToImage(_ view: some View, size: CGSize) async -> UIImage {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                // Create hosting controller with view wrapped to ignore safe area
                let wrappedView = view
                    .ignoresSafeArea()
                    .frame(width: size.width, height: size.height)

                let controller = UIHostingController(rootView: wrappedView)
                controller.view.insetsLayoutMarginsFromSafeArea = false

                // Create a temporary window to provide proper view hierarchy
                let window = UIWindow(frame: CGRect(origin: .zero, size: size))
                window.rootViewController = controller
                window.isHidden = false

                // Set the controller's view frame
                controller.view.frame = CGRect(origin: .zero, size: size)
                controller.view.backgroundColor = UIColor.clear

                // Force layout cycle
                controller.view.setNeedsLayout()
                controller.view.layoutIfNeeded()

                // Wait for next run loop to ensure layout is complete
                DispatchQueue.main.async {
                    // Get the actual content area
                    let safeAreaTop = controller.view.safeAreaInsets.top
                    let contentHeight = size.height - safeAreaTop
                    let contentSize = CGSize(width: size.width, height: contentHeight)

                    // Render to image, cropping out the top safe area
                    let renderer = UIGraphicsImageRenderer(size: contentSize)
                    let image = renderer.image { context in
                        // Set clear background
                        context.cgContext.clear(CGRect(origin: .zero, size: contentSize))

                        // Translate to skip the safe area at top
                        context.cgContext.translateBy(x: 0, y: -safeAreaTop)

                        // Render the view
                        controller.view.layer.render(in: context.cgContext)
                    }

                    // Clean up
                    window.isHidden = true
                    window.rootViewController = nil

                    print("📊 Rendered table image size: \(image.size), cropped \(safeAreaTop)pt from top")
                    continuation.resume(returning: image)
                }
            }
        }
    }

    /// Generate fallback image when WebView rendering fails
    private func generateFallbackTableImage(collapsed: Bool, theme: any osrsThemeProtocol) -> UIImage {
        let size = CGSize(width: 300, height: 200) // Fallback size
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            // Fill background
            UIColor(theme.background).setFill()
            context.fill(CGRect(origin: .zero, size: size))

            // Draw simple text
            let text = collapsed ? "Collapsed" : "Expanded"
            let font = UIFont.systemFont(ofSize: 14, weight: .medium)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor(theme.onSurface)
            ]

            let textSize = text.size(withAttributes: attributes)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )

            text.draw(in: textRect, withAttributes: attributes)
        }
    }

    /// Force table state using JavaScript injection - WebView direct version with enhanced error handling
    func forceTableStateInWebView(webView: WKWebView, collapsed: Bool) {
        let collapsedState = collapsed ? "true" : "false"
        let stateDescription = collapsed ? "collapsed" : "expanded"

        // ENHANCED ERROR HANDLING: Wrap JavaScript in try-catch and return result
        let jsCode = """
            (function() {
                try {
                    console.log('TablePreviewRenderer: Forcing table state to \(stateDescription)');

                    // Verify document is ready
                    if (!document.body) {
                        console.log('TablePreviewRenderer: Document body not ready');
                        return { success: false, error: 'document_not_ready' };
                    }

                    // Set the global variable
                    window.OSRS_TABLE_COLLAPSED = \(collapsedState);

                    // Force all collapsible elements to the desired state
                    var collapsibleElements = document.querySelectorAll('.mw-collapsible');
                    console.log('TablePreviewRenderer: Found ' + collapsibleElements.length + ' collapsible elements');

                    var processed = 0;
                    collapsibleElements.forEach(function(element, index) {
                        try {
                            if (\(collapsedState)) {
                                // Collapse the element
                                if (!element.classList.contains('mw-collapsed')) {
                                    element.classList.add('mw-collapsed');
                                    processed++;
                                }
                            } else {
                                // Expand the element
                                if (element.classList.contains('mw-collapsed')) {
                                    element.classList.remove('mw-collapsed');
                                    processed++;
                                }
                            }
                        } catch (elementError) {
                            console.log('TablePreviewRenderer: Error processing element ' + index + ': ' + elementError.message);
                        }
                    });

                    console.log('TablePreviewRenderer: Table state forced to \(stateDescription), processed ' + processed + ' elements');
                    return { success: true, processed: processed, total: collapsibleElements.length };

                } catch (error) {
                    console.log('TablePreviewRenderer: JavaScript error: ' + error.message);
                    return { success: false, error: error.message };
                }
            })();
        """

        webView.evaluateJavaScript(jsCode) { result, error in
            if let error = error {
                print("❌ TablePreviewRenderer: JavaScript execution failed: \(error.localizedDescription)")

                // FALLBACK: Try simpler JavaScript approach
                let fallbackJs = "void(window.OSRS_TABLE_COLLAPSED = \(collapsedState));"
                webView.evaluateJavaScript(fallbackJs) { fallbackResult, fallbackError in
                    if let fallbackError = fallbackError {
                        print("❌ TablePreviewRenderer: Fallback JavaScript also failed: \(fallbackError.localizedDescription)")
                    } else {
                        print("✅ TablePreviewRenderer: Fallback set global variable successfully")
                    }
                }
            } else if let resultDict = result as? [String: Any] {
                if let success = resultDict["success"] as? Bool {
                    if success {
                        let processed = resultDict["processed"] as? Int ?? 0
                        let total = resultDict["total"] as? Int ?? 0
                        print("✅ TablePreviewRenderer: Table state set to \(stateDescription) - processed \(processed)/\(total) elements")
                    } else {
                        let errorMsg = resultDict["error"] as? String ?? "unknown"
                        print("❌ TablePreviewRenderer: JavaScript reported failure: \(errorMsg)")
                    }
                } else {
                    print("⚠️ TablePreviewRenderer: JavaScript returned unexpected result: \(resultDict)")
                }
            } else {
                print("✅ TablePreviewRenderer: JavaScript executed but returned unexpected type: \(type(of: result))")
            }
        }
    }

    /// Force table state in WebView by executing JavaScript directly
    private func forceTableStateInWebView(controller: UIHostingController<some View>, collapsed: Bool) {
        // Find the WKWebView in the view hierarchy
        if let webView = findWebView(in: controller.view) {
            let collapsedState = collapsed ? "true" : "false"
            let stateDescription = collapsed ? "collapsed" : "expanded"
            let jsCode = """
                console.log('TablePreviewRenderer: Forcing table state to \(stateDescription)');

                // Set the global variable
                window.OSRS_TABLE_COLLAPSED = \(collapsedState);

                // Debug: Check what tables are on the page
                var allTables = document.querySelectorAll('table');
                console.log('TablePreviewRenderer: Found ' + allTables.length + ' total tables');

                // Force all collapsible elements to the desired state
                var collapsibleElements = document.querySelectorAll('.mw-collapsible');
                console.log('TablePreviewRenderer: Found ' + collapsibleElements.length + ' collapsible elements');

                collapsibleElements.forEach(function(element, index) {
                    console.log('TablePreviewRenderer: Element ' + index + ' initial classes: ' + element.className);

                    if (\(collapsedState)) {
                        // Collapse the element
                        if (!element.classList.contains('mw-collapsed')) {
                            element.classList.add('mw-collapsed');
                            console.log('TablePreviewRenderer: Collapsed element ' + index + ' -> classes: ' + element.className);
                        }
                    } else {
                        // Expand the element
                        if (element.classList.contains('mw-collapsed')) {
                            element.classList.remove('mw-collapsed');
                            console.log('TablePreviewRenderer: Expanded element ' + index + ' -> classes: ' + element.className);
                        }
                    }
                });

                // Debug: Count visible table rows
                var visibleRows = document.querySelectorAll('table tr:not([style*="display: none"])');
                console.log('TablePreviewRenderer: Found ' + visibleRows.length + ' visible table rows after state change');

                // Force re-render by triggering a style recalculation
                document.body.style.display = 'none';
                document.body.offsetHeight; // Trigger reflow
                document.body.style.display = '';

                console.log('TablePreviewRenderer: Forced table state completed');
            """

            webView.evaluateJavaScript(jsCode) { result, error in
                if let error = error {
                    print("📊 TablePreviewRenderer: JavaScript execution error: \(error)")
                } else {
                    print("📊 TablePreviewRenderer: Successfully forced table state to \(stateDescription)")
                }
            }
        } else {
            print("📊 TablePreviewRenderer: Could not find WKWebView in view hierarchy")
        }
    }

    /// Recursively find WKWebView in view hierarchy
    private func findWebView(in view: UIView) -> WKWebView? {
        if let webView = view as? WKWebView {
            return webView
        }

        for subview in view.subviews {
            if let webView = findWebView(in: subview) {
                return webView
            }
        }

        return nil
    }

    /// Get cached table preview image without regenerating (for instant access)
    func getCachedTablePreview(collapsed: Bool, theme: any osrsThemeProtocol) -> UIImage? {
        let cacheKey = "table-\(collapsed ? "collapsed" : "expanded")-\(theme.name)"
        return previewCache[cacheKey]
    }

    /// Clear all cached previews
    func clearCache() {
        previewCache.removeAll()
    }
}


/// Extension to convert UIColor to hex string
private extension UIColor {
    func toHex() -> String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        let rgb = Int(red * 255) << 16 | Int(green * 255) << 8 | Int(blue * 255)
        return String(format: "#%06X", rgb)
    }
}



/// Extension to add name property to theme protocol
extension osrsThemeProtocol {
    var name: String {
        if self is osrsLightTheme {
            return "light"
        } else if self is osrsDarkTheme {
            return "dark"
        } else {
            return "unknown"
        }
    }
}
