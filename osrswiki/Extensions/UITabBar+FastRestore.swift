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
    /// when `.toolbarVisibility(.hidden)` is set. Hide it by alpha so the
    /// layer stays warm for an instant restore, but cannot show through the
    /// article glass overlay.
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

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first
    }

    private static func floatingTabBars() -> [UITabBar] {
        floatingTabBarViews().compactMap { $0 as? UITabBar }
    }

    private static func floatingTabBarViews() -> [UIView] {
        guard let window = keyWindow() else { return [] }
        var bars: [UIView] = []
        func visit(_ view: UIView) {
            let name = NSStringFromClass(type(of: view))
            if view is UITabBar ||
                (name.localizedCaseInsensitiveContains("TabBar") &&
                 view.bounds.height > 20 && view.bounds.height < 140 &&
                 view.bounds.width > 160) {
                bars.append(view)
            }
            view.subviews.forEach(visit)
        }
        visit(window)
        return bars
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