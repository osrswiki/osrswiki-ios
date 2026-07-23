//
//  UITabBar+FastRestore.swift
//  osrswiki
//
//  Created for immediate tab bar restoration UX optimization
//

import UIKit

extension UIApplication {
    static func restoreTabBarImmediately() {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first else { return }
            
            // Find the tab bar controller in the view hierarchy
            if let tabBarController = findTabBarController(in: window.rootViewController) {
                // Force immediate tab bar visibility
                tabBarController.tabBar.isHidden = false
                tabBarController.tabBar.alpha = 1.0
                
                // Optional: Add a subtle animation for smooth appearance
                UIView.animate(withDuration: 0.15, delay: 0, options: [.allowUserInteraction], animations: {
                    tabBarController.tabBar.transform = .identity
                }, completion: nil)
            }
        }
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