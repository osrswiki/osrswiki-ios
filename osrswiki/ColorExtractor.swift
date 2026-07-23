import SwiftUI
import UIKit

/**
 * Color Extraction Utility for iOS Tab Bar Testing
 * 
 * This utility extracts the actual rendered colors from iOS tab bars
 * to enable programmatic color comparison testing.
 */

class ColorExtractor {
    
    private static func uiColorToHex(_ color: UIColor) -> String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        
        let rgb: Int = (Int)(r*255)<<16 | (Int)(g*255)<<8 | (Int)(b*255)<<0
        
        return String(format: "#%06x", rgb)
    }
    
    @MainActor static func extractTabBarColors(themeManager: osrsThemeManager) -> [String: String] {
        var results: [String: String] = [:]
        
        // Extract base colors
        let baseColor = UIColor(themeManager.currentTheme.primaryTextColor)
        let surfaceColor = UIColor(themeManager.currentTheme.surface)
        let inactiveColor = baseColor.withAlphaComponent(0.4)
        
        results["base_color"] = uiColorToHex(baseColor)
        results["surface_color"] = uiColorToHex(surfaceColor)
        results["calculated_inactive_40_alpha"] = uiColorToHex(inactiveColor)
        
        // Extract actual tab bar appearance colors
        let appearance = UITabBar.appearance()
        
        results["debug_appearance_tint"] = uiColorToHex(appearance.tintColor ?? UIColor.clear)
        results["debug_appearance_unselected"] = uiColorToHex(appearance.unselectedItemTintColor ?? UIColor.clear)
        results["debug_appearance_background"] = uiColorToHex(appearance.backgroundColor ?? UIColor.clear)
        
        // Extract from standardAppearance - this is what should work in iOS 18
        let standardAppearance = appearance.standardAppearance
        let stackedNormal = standardAppearance.stackedLayoutAppearance.normal
        
        results["debug_stacked_normal_icon"] = uiColorToHex(stackedNormal.iconColor ?? UIColor.clear)
        
        if let titleAttrs = stackedNormal.titleTextAttributes[.foregroundColor] as? UIColor {
            results["debug_stacked_normal_title"] = uiColorToHex(titleAttrs)
        } else {
            results["debug_stacked_normal_title"] = "not_set"
        }
        
        // Try to find actual rendered tab bar if possible
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            let actualTabBar = findTabBarInView(window.rootViewController?.view)
            if let tabBar = actualTabBar {
                results["debug_actual_tabbar_tint"] = uiColorToHex(tabBar.tintColor ?? UIColor.clear)
                results["debug_actual_tabbar_unselected"] = uiColorToHex(tabBar.unselectedItemTintColor ?? UIColor.clear)
            } else {
                results["debug_actual_tabbar"] = "not_found"
            }
        }
        
        // Calculate the visual result of alpha blending
        let visualResult = ColorExtractor.calculateAlphaBlendedColor(
            foreground: baseColor,
            background: surfaceColor,
            alpha: 0.4
        )
        results["visual_40_alpha_result"] = uiColorToHex(visualResult)
        
        return results
    }
    
    static func calculateAlphaBlendedColor(foreground: UIColor, background: UIColor, alpha: CGFloat) -> UIColor {
        var fgR: CGFloat = 0, fgG: CGFloat = 0, fgB: CGFloat = 0, fgA: CGFloat = 0
        var bgR: CGFloat = 0, bgG: CGFloat = 0, bgB: CGFloat = 0, bgA: CGFloat = 0
        
        foreground.getRed(&fgR, green: &fgG, blue: &fgB, alpha: &fgA)
        background.getRed(&bgR, green: &bgG, blue: &bgB, alpha: &bgA)
        
        // Alpha blending formula: result = alpha * foreground + (1 - alpha) * background
        let resultR = alpha * fgR + (1 - alpha) * bgR
        let resultG = alpha * fgG + (1 - alpha) * bgG
        let resultB = alpha * fgB + (1 - alpha) * bgB
        
        return UIColor(red: resultR, green: resultG, blue: resultB, alpha: 1.0)
    }
    
    private static func findTabBarInView(_ view: UIView?) -> UITabBar? {
        guard let view = view else { return nil }
        
        if let tabBar = view as? UITabBar {
            return tabBar
        }
        
        for subview in view.subviews {
            if let found = findTabBarInView(subview) {
                return found
            }
        }
        
        return nil
    }
    
    @MainActor static func exportColorsToJSON(themeManager: osrsThemeManager) {
        let colors = extractTabBarColors(themeManager: themeManager)
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: colors, options: .prettyPrinted)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print("🎨 iOS COLOR EXTRACTION RESULTS:")
                print(jsonString)
                
                // Write to Documents directory for easy access
                if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                    let fileURL = documentsPath.appendingPathComponent("ios_colors.json")
                    try jsonString.write(to: fileURL, atomically: true, encoding: .utf8)
                    print("📱 iOS colors exported to: \(fileURL.path)")
                }
            }
        } catch {
            print("❌ Error exporting iOS colors: \(error)")
        }
    }
}


// Add this to your MainTabView.swift in the onAppear method for debugging
extension MainTabView {
    func debugColorExtraction() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            ColorExtractor.exportColorsToJSON(themeManager: themeManager)
        }
    }
}