//
//  UITabBar+FastRestore.swift
//  osrswiki
//
//  Created for immediate tab bar restoration UX optimization
//

import UIKit

private enum osrsTabBarFillCache {
    static var opaqueFill: UIColor?
}

extension UIApplication {
    /// iOS 26 Liquid Glass TabView keeps the system tab bar composited even
    /// when `.toolbarVisibility(.hidden)` is set. Hide the 62pt capsule by
    /// alpha so the layer stays warm, but never alpha-hide the full-screen
    /// bar samplers (`_UITabBarContainerView`, `_UIFloatingBarContainerView`):
    /// those layers paint tab/article content. Send them behind the content
    /// instead so a stale resume snapshot cannot cover the article.
    static func setFloatingTabBarHidden(_ hidden: Bool) {
        let apply = {
            for bar in floatingTabBarViews() {
                bar.alpha = hidden ? 0 : 1
                bar.isUserInteractionEnabled = !hidden
                // Keep the view in the hierarchy. `isHidden` rematerializes the
                // glass capsule and is what made the home bar pop in late.
                if hidden == false {
                    bar.isHidden = false
                    bar.transform = .identity
                }
            }
            sendFloatingTabBarCoversBehindContent(hidden)
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }

    static func refreshFloatingTabBarMaterial(opaqueFill: UIColor? = nil, replaceFill: Bool = false) {
        DispatchQueue.main.async {
            if replaceFill {
                osrsTabBarFillCache.opaqueFill = opaqueFill
            }
            applyStableTabBarAppearance(opaqueFill: osrsTabBarFillCache.opaqueFill)
            for bar in floatingTabBarViews() {
                bar.setNeedsLayout()
                bar.layoutIfNeeded()
                // Force the glass to resample the current tab's contents.
                // Leaving Map otherwise keeps the last map sample until a scroll.
                let current = bar.alpha
                bar.alpha = max(0.001, current * 0.997)
                DispatchQueue.main.async {
                    bar.alpha = current
                }
            }
        }
    }

    static func applyStableTabBarAppearance(opaqueFill: UIColor? = nil) {
        // Pin scroll-edge and standard appearances to the same material so
        // iOS 26 cannot rematerialize from clear → frosted when the sampled
        // background crosses a luminance threshold (the map-tab snap).
        // Never use an opaque non-translucent bar: that insets TabView
        // content and leaves a white hole above the floating capsule.
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = nil
        appearance.backgroundColor = opaqueFill
        appearance.shadowColor = .clear
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        for bar in floatingTabBars() {
            bar.standardAppearance = appearance
            bar.scrollEdgeAppearance = appearance
            bar.isTranslucent = true
        }
    }

    static func restoreTabBarImmediately() {
        DispatchQueue.main.async {
            setFloatingTabBarHidden(false)
            if let tabBarController = findTabBarController(in: keyWindow()?.rootViewController) {
                tabBarController.tabBar.isHidden = false
                tabBarController.tabBar.alpha = 1.0
                UIView.animate(withDuration: 0.15, delay: 0, options: [.allowUserInteraction], animations: {
                    tabBarController.tabBar.transform = .identity
                }, completion: nil)
            }
        }
    }

    private static func contentWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { isAppLikeWindow($0) && $0.rootViewController != nil }
    }

    private static func keyWindow() -> UIWindow? {
        contentWindow() ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }

    private static func floatingTabBars() -> [UITabBar] {
        floatingTabBarViews().compactMap { $0 as? UITabBar }
    }

    private static func appContentWindows() -> [UIWindow] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter(isAppLikeWindow)
    }

    private static func floatingTabBarViews() -> [UIView] {
        var bars: [UIView] = []
        func visit(_ view: UIView) {
            let name = NSStringFromClass(type(of: view))
            if view is UITabBar ||
                (name.localizedCaseInsensitiveContains("TabBar") &&
                 !name.contains("Container") &&
                 view.bounds.height > 20 && view.bounds.height < 140 &&
                 view.bounds.width > 160) {
                bars.append(view)
            }
            view.subviews.forEach(visit)
        }
        appContentWindows().forEach { visit($0) }
        return bars
    }

    private static func floatingTabBarCoverViews() -> [UIView] {
        var covers: [UIView] = []
        func visit(_ view: UIView) {
            let name = NSStringFromClass(type(of: view))
            if name.contains("_UITabBarContainerView") ||
                name.contains("_UITabBarContainerWrapperView") ||
                name.contains("_UIFloatingBarContainerView") ||
                name.contains("FloatingBarContainer") {
                covers.append(view)
            }
            view.subviews.forEach(visit)
        }
        appContentWindows().forEach { visit($0) }
        return covers
    }

    /// The iOS 26 tab container is a later sibling of tab content and a
    /// full-screen sampling layer. After a scene resume it can freeze as an
    /// opaque theme fill over the still-alive article tree. Keep it in the
    /// hierarchy at alpha 1 so Liquid Glass can resample, but park it behind
    /// the content while an article owns the chrome.
    private static func sendFloatingTabBarCoversBehindContent(_ behind: Bool) {
        var parents: Set<ObjectIdentifier> = []
        for cover in floatingTabBarCoverViews() {
            cover.isUserInteractionEnabled = !behind
            cover.layer.zPosition = behind ? -1 : 0
            // `_UITabBarContainerView` is a full-screen sampler whose frame
            // originates above the 83pt wrapper. Without clipping, that
            // overflow paints a frozen theme fill over the article after resume.
            cover.clipsToBounds = behind
            cover.layer.masksToBounds = behind
            let name = NSStringFromClass(type(of: cover))
            let isFullScreenSampler = name.contains("_UIFloatingBarContainerView")
                || name.contains("FloatingBarHostingView")
            if isFullScreenSampler {
                // Full-screen Liquid Glass samplers paint a frozen theme fill
                // over the article after resume even at z=-1. Hide them while
                // an article owns the chrome; restore on the tab root.
                cover.alpha = behind ? 0 : 1
                cover.isHidden = behind
            }
            if behind {
                cover.layer.contents = nil
                cover.setNeedsLayout()
                cover.layer.setNeedsDisplay()
            }
            if let parent = cover.superview {
                parents.insert(ObjectIdentifier(parent))
                for sibling in parent.subviews {
                    let name = NSStringFromClass(type(of: sibling))
                    let isCover = name.contains("_UITabBarContainerView")
                        || name.contains("_UITabBarContainerWrapperView")
                        || name.contains("_UIFloatingBarContainerView")
                        || name.contains("FloatingBarContainer")
                    if isCover { continue }
                    sibling.layer.zPosition = behind ? 1 : 0
                }
            }
        }
        print("🪟 tabBar covers=\(floatingTabBarCoverViews().count) behind=\(behind) parents=\(parents.count)")
        let coverDump = floatingTabBarCoverViews().map { view in
            let name = NSStringFromClass(type(of: view))
            return "COVER \(name) alpha=\(String(format: "%.2f", view.alpha)) hidden=\(view.isHidden) z=\(Int(view.layer.zPosition)) frame=\(Int(view.frame.minX)),\(Int(view.frame.minY)) \(Int(view.frame.width))x\(Int(view.frame.height))"
        }.joined(separator: "\n")
        if let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("osrs-scene-dump.txt") {
            let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            try? (existing + "\n" + coverDump + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private static func isAppLikeWindow(_ window: UIWindow) -> Bool {
        let name = NSStringFromClass(type(of: window))
        return !name.contains("TextEffects") && !name.contains("Keyboard")
    }
    
    private static func findTabBarController(in viewController: UIViewController?) -> UITabBarController? {
        if let tabBarController = viewController as? UITabBarController {
            return tabBarController
        }
        
        if let presentedViewController = viewController?.presentedViewController {
            if let result = findTabBarController(in: presentedViewController) {
                return result
            }
        }
        
        for child in viewController?.children ?? [] {
            if let result = findTabBarController(in: child) {
                return result
            }
        }
        
        return nil
    }
}