//
//  osrsThemePreviewRenderer.swift
//  OSRS Wiki
//
//  iOS equivalent to Android's ThemePreviewRenderer
//  Generates visual theme previews by rendering actual app interface screenshots
//

import SwiftUI
import UIKit
import Combine

/// Generates theme preview images by rendering actual app interfaces with different themes applied
@MainActor
class osrsThemePreviewRenderer: ObservableObject {
    
    // Singleton instance for shared cache
    static let shared = osrsThemePreviewRenderer()
    
    // No fixed dimensions - we'll return the full device-sized render
    // and let the UI handle scaling/cropping as needed
    
    // Cache for generated previews
    private var previewCache: [String: UIImage] = [:]
    
    // Private initializer to ensure singleton usage
    private init() {}
    
    /// Generate preview image for a specific theme
    func generatePreview(for theme: osrsThemeSelection, colorScheme: ColorScheme? = nil) async -> UIImage {
        let colorSchemeKey = colorScheme == .light ? "light" : colorScheme == .dark ? "dark" : "auto"
        let cacheKey = "\(theme.rawValue)-\(colorSchemeKey)"
        
        print("🖼️ ThemePreviewRenderer: Generating preview for \(theme.rawValue)")
        
        // Check cache first
        if let cachedImage = previewCache[cacheKey] {
            print("⚡ ThemePreviewRenderer: CACHE HIT for \(cacheKey) - returning cached image instantly")
            return cachedImage
        }
        
        print("🔄 ThemePreviewRenderer: CACHE MISS for \(cacheKey) - generating new preview (this will be slow)")
        
        // Generate new preview
        let previewImage: UIImage
        
        switch theme {
        case .automatic:
            print("🖼️ ThemePreviewRenderer: Generating split preview for automatic theme")
            previewImage = await generateSplitPreview()
        case .osrsLight:
            print("🖼️ ThemePreviewRenderer: Generating light theme preview")
            previewImage = await generateSingleThemePreview(theme: theme, forceColorScheme: .light)
        case .osrsDark:
            print("🖼️ ThemePreviewRenderer: Generating dark theme preview")
            previewImage = await generateSingleThemePreview(theme: theme, forceColorScheme: .dark)
        }
        
        print("🖼️ ThemePreviewRenderer: Generated image size: \(previewImage.size)")
        
        // Cache the result for future instant access
        previewCache[cacheKey] = previewImage
        print("💾 ThemePreviewRenderer: CACHED image for \(cacheKey) - future loads will be instant")
        return previewImage
    }
    
    /// Generate split preview showing light theme on left, dark theme on right (for "Follow system")
    private func generateSplitPreview() async -> UIImage {
        // CRITICAL FIX: Use cached generatePreview instead of bypassing cache with direct generateSingleThemePreview calls
        let lightPreview = await generatePreview(for: .osrsLight)
        let darkPreview = await generatePreview(for: .osrsDark)
        
        // CRITICAL FIX: Use actual preview size (excludes safe area) instead of full device size
        // Individual previews are already cropped to content area, so combined image should match
        let targetSize = lightPreview.size
        return combineImagesLeftRight(leftImage: lightPreview, rightImage: darkPreview, targetSize: targetSize)
    }
    
    /// Generate single theme preview using ACTUAL app interface with pre-loaded content (like Android)
    private func generateSingleThemePreview(theme: osrsThemeSelection, forceColorScheme: ColorScheme) async -> UIImage {
        let resolvedTheme = theme.theme(for: forceColorScheme)
        
        print("🖼️ ThemePreviewRenderer: Loading real content for \(theme.rawValue) theme...")
        
        print("🖼️ ThemePreviewRenderer: Pre-loading data then rendering NewsView")
        
        // Create real app state and theme manager
        let appState = AppState()
        let themeManager = osrsThemeManager()
        themeManager.setTheme(theme)
        
        // Pre-load NewsViewModel data BEFORE creating the view to avoid timing issues
        let newsViewModel = NewsViewModel()
        await newsViewModel.loadNews()
        
        print("🖼️ ThemePreviewRenderer: Data loaded, wikiFeed: \(newsViewModel.wikiFeed != nil ? "✅" : "❌"), updates count: \(newsViewModel.wikiFeed?.recentUpdates.count ?? 0)")
        
        // Extract wikiFeed data to avoid @Published timing issues in UIHostingController
        guard let wikiFeed = newsViewModel.wikiFeed else {
            print("🖼️ ThemePreviewRenderer: No wikiFeed data, using fallback")
            return await generateFallbackPreview(theme: resolvedTheme)
        }
        
        print("🖼️ ThemePreviewRenderer: Pre-loading images for theme preview...")
        
        // Pre-load all images for reliable theme preview rendering (solves AsyncImage issues)
        let imageCache = osrsImageCache.shared
        await imageCache.preloadImages(from: wikiFeed.recentUpdates)
        
        print("🖼️ ThemePreviewRenderer: Creating StaticNewsView with pre-loaded images")
        
        // Create StaticNewsView with direct data (no ObservableObject dependencies)
        let staticNewsView = StaticNewsView(wikiFeed: wikiFeed)
            .environmentObject(appState)
            .environmentObject(themeManager)
            .environment(\.osrsTheme, resolvedTheme)
            .environment(\.colorScheme, forceColorScheme)
            .environment(\.osrsPreviewMode, true)
        
        // Render at device size WITHOUT scaling down - return full resolution
        let deviceSize = await getDeviceContentSize()
        return await renderViewWithImageWait(staticNewsView, size: deviceSize)
    }
    
    /// Generate fallback preview when content loading fails
    private func generateFallbackPreview(theme: any osrsThemeProtocol) async -> UIImage {
        let size = await getDeviceContentSize()
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            // Fill background
            UIColor(theme.background).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            
            // Draw simple preview indicator
            let text = "Preview"
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
    
    // Removed scaling methods - we now return full device-sized images
    
    /// Render view to image with proper async image loading waiting
    private func renderViewWithImageWait(_ view: some View, size: CGSize) async -> UIImage {
        return await withCheckedContinuation { continuation in
            // Use async task instead of nested DispatchQueue delays
            Task { @MainActor in
                // Check for cancellation
                guard !Task.isCancelled else {
                    continuation.resume(returning: UIImage())
                    return
                }
                
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
                
                // Use proper async/await instead of DispatchQueue.main.asyncAfter
                do {
                    try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    
                    guard !Task.isCancelled else {
                        continuation.resume(returning: UIImage())
                        return
                    }
                    // Force ScrollView to scroll to top for proper alignment
                    self.forceScrollToTop(in: controller.view)
                    
                    // Additional layout after image loading and scroll positioning
                    controller.view.setNeedsLayout()
                    controller.view.layoutIfNeeded()
                    
                    // Get the actual content area (excluding any remaining safe area)
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
                    
                    print("🖼️ Rendered image (no safe area): size \(image.size), cropped \(safeAreaTop)pt from top")
                    continuation.resume(returning: image)
                } catch {
                    // Task was cancelled or error occurred
                    continuation.resume(returning: UIImage())
                }
            }
        }
    }
    
    /// Force all ScrollViews to scroll to top for proper alignment
    private func forceScrollToTop(in view: UIView) {
        // Find all UIScrollViews in the view hierarchy
        let scrollViews = findAllScrollViews(in: view)
        
        for scrollView in scrollViews {
            print("🖼️ Found ScrollView, forcing to top: current offset \(scrollView.contentOffset)")
            
            // Scroll to the very top
            scrollView.contentOffset = CGPoint(x: 0, y: -scrollView.adjustedContentInset.top)
            scrollView.setNeedsLayout()
            scrollView.layoutIfNeeded()
            
            print("🖼️ ScrollView forced to top: new offset \(scrollView.contentOffset)")
        }
    }
    
    /// Recursively find all UIScrollViews in view hierarchy
    private func findAllScrollViews(in view: UIView) -> [UIScrollView] {
        var scrollViews: [UIScrollView] = []
        
        if let scrollView = view as? UIScrollView {
            scrollViews.append(scrollView)
        }
        
        for subview in view.subviews {
            scrollViews.append(contentsOf: findAllScrollViews(in: subview))
        }
        
        return scrollViews
    }
    
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
                print("🖼️ Device content size: \(contentSize) (full: \(fullSize), insets: \(safeAreaInsets))")
                
                continuation.resume(returning: contentSize)
            }
        }
    }
    
    // Removed scaleImageToTargetSize - no longer needed
    
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
                    
                    print("🖼️ Rendered image size: \(image.size), cropped \(safeAreaTop)pt from top")
                    continuation.resume(returning: image)
                }
            }
        }
    }
    
    /// Combine two images side by side with divider
    private func combineImagesLeftRight(leftImage: UIImage, rightImage: UIImage, targetSize: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        
        return renderer.image { context in
            let halfWidth = targetSize.width / 2
            
            // Draw LEFT HALF of light theme image
            let leftRect = CGRect(x: 0, y: 0, width: halfWidth, height: targetSize.height)
            context.cgContext.saveGState()
            context.cgContext.clip(to: leftRect)
            leftImage.draw(in: CGRect(x: 0, y: 0, width: leftImage.size.width, height: leftImage.size.height))
            context.cgContext.restoreGState()
            
            // Draw RIGHT HALF of dark theme image
            // We want to show the right half of the dark image in the right half of the canvas
            let rightRect = CGRect(x: halfWidth, y: 0, width: halfWidth, height: targetSize.height)
            context.cgContext.saveGState()
            context.cgContext.clip(to: rightRect)
            // To show the right half of the dark image:
            // - The image needs to be positioned so its center aligns with halfWidth
            // - This means drawing it at x = halfWidth - (rightImage.size.width / 2)
            let darkImageHalfWidth = rightImage.size.width / 2
            rightImage.draw(in: CGRect(x: halfWidth - darkImageHalfWidth, y: 0, width: rightImage.size.width, height: rightImage.size.height))
            context.cgContext.restoreGState()
            
            // Draw divider line
            context.cgContext.setStrokeColor(UIColor.systemGray.cgColor)
            context.cgContext.setLineWidth(1.0)
            context.cgContext.move(to: CGPoint(x: halfWidth, y: 0))
            context.cgContext.addLine(to: CGPoint(x: halfWidth, y: targetSize.height))
            context.cgContext.strokePath()
        }
    }
    
    // Removed scaleImagePreservingAspectRatio - no longer needed
    
    
    /// Clear all cached previews
    /// Get cached preview image without regenerating (for instant access)
    func getCachedPreview(for theme: osrsThemeSelection, colorScheme: ColorScheme? = nil) -> UIImage? {
        let colorSchemeKey = colorScheme == .light ? "light" : colorScheme == .dark ? "dark" : "auto"
        let cacheKey = "\(theme.rawValue)-\(colorSchemeKey)"
        return previewCache[cacheKey]
    }
    
    func clearCache() {
        previewCache.removeAll()
    }
}

