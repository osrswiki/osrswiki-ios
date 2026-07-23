//
//  osrsWikiModuleRegistry.swift
//  OSRS Wiki
//
//  Created on article rendering parity session
//

import Foundation

class osrsWikiModuleRegistry {
    
    // Core always-loaded modules for essential MediaWiki functionality
    private static let coreModules = [
        "startup",
        "jquery",
        "mediawiki.base",
        "mediawiki.legacy.wikibits"
    ]
    
    // Module mappings for intelligent detection
    private static let modulePatterns: [(pattern: String, modules: [String])] = [
        // Tables and sorting
        ("class=\"wikitable", ["jquery.tablesorter"]),
        ("sortable", ["jquery.tablesorter"]),
        
        // Navigation boxes  
        ("class=\"navbox", ["mediawiki.hlist"]),
        ("navbox-group", ["mediawiki.hlist"]),
        
        // Collapsible content
        ("mw-collapsible", ["jquery.makeCollapsible"]),
        ("collapsible", ["jquery.makeCollapsible"]),
        
        // Citations and references
        ("class=\"reference", ["ext.cite.ux-enhancements"]),
        ("<references", ["ext.cite.ux-enhancements"]),
        
        // Coordinates and maps
        ("class=\"geo", ["ext.kartographer.dialog"]),
        ("coordinates", ["ext.kartographer.dialog"]),
        
        // Embedded videos
        ("embedvideo", ["ext.embedVideo"]),
        ("youtube", ["ext.embedVideo"]),
        
        // Math expressions
        ("math", ["ext.math.styles"]),
        ("texhtml", ["ext.math.styles"]),
        
        // Gallery images
        ("class=\"gallery", ["mediawiki.page.gallery.styles"]),
        
        // Categories
        ("class=\"catlinks", ["mediawiki.action.view.categoryPage.styles"]),
        
        // Tabs and switching interfaces
        ("data-switch-infobox", ["ext.gadget.switch-infobox"]),
        ("switch-info", ["ext.gadget.switch-infobox"]),
        
        // OSRS-specific: Grand Exchange charts
        ("GEChartBox", ["ext.osrs.ge-charts"]),
        ("GEdatachart", ["ext.osrs.ge-charts"]),
        ("GEdataprices", ["ext.osrs.ge-charts"]),
        
        // OSRS-specific: Quest guides and navigation
        ("questguide", ["ext.osrs.quest-nav"]),
        ("navboxquest", ["ext.osrs.quest-nav"]),
        
        // OSRS-specific: Item infoboxes
        ("infobox-item", ["ext.osrs.item-tooltips"]),
        ("item-icon", ["ext.osrs.item-tooltips"]),
        
        // OSRS-specific: Experience tables and calculators
        ("exptable", ["ext.osrs.exp-calculator"]),
        ("calc-table", ["ext.osrs.exp-calculator"])
    ]
    
    // Page-specific modules for certain article types
    private static let pageSpecificModules: [String: [String]] = [
        // Combat-related pages
        "combat": ["ext.osrs.combat-calculator"],
        "monster": ["ext.osrs.combat-calculator", "ext.osrs.drop-tables"],
        "weapon": ["ext.osrs.combat-calculator"],
        
        // Skill-related pages
        "skill": ["ext.osrs.skill-calculator", "ext.osrs.exp-calculator"],
        "training": ["ext.osrs.skill-calculator", "ext.osrs.exp-calculator"],
        
        // Quest pages
        "quest": ["ext.osrs.quest-nav", "ext.osrs.quest-tracker"],
        
        // Location pages  
        "location": ["ext.kartographer.dialog", "ext.osrs.world-map"],
        
        // Item pages
        "item": ["ext.osrs.item-tooltips", "ext.osrs.ge-charts"],
        
        // Update pages
        "update": ["ext.osrs.update-diff"],
        
        // Calculator pages
        "calculator": ["ext.osrs.calculator", "ext.osrs.exp-calculator"]
    ]
    
    static func generateRLPAGEMODULES(bodyContent: String, title: String) -> [String] {
        var detectedModules = Set<String>()
        
        // Always include core modules
        detectedModules.formUnion(coreModules)
        
        // Pattern-based detection
        for (pattern, modules) in modulePatterns {
            if bodyContent.contains(pattern) {
                detectedModules.formUnion(modules)
            }
        }
        
        // Page-specific detection based on title
        let lowercaseTitle = title.lowercased()
        for (keyword, modules) in pageSpecificModules {
            if lowercaseTitle.contains(keyword) {
                detectedModules.formUnion(modules)
            }
        }
        
        // Smart inference for common OSRS patterns
        
        // If we detect multiple tables, likely need advanced table features
        let tableCount = bodyContent.components(separatedBy: "wikitable").count - 1
        if tableCount > 2 {
            detectedModules.insert("jquery.tablesorter.advanced")
        }
        
        // If we detect infoboxes, likely need infobox enhancements
        if bodyContent.contains("infobox") {
            detectedModules.insert("ext.gadget.infobox-styles")
        }
        
        // If we detect many images, preload image handling
        let imageCount = bodyContent.components(separatedBy: "<img").count - 1
        if imageCount > 5 {
            detectedModules.insert("mediawiki.page.gallery")
        }
        
        // Convert to sorted array for consistent output
        return Array(detectedModules).sorted()
    }
    
    // Helper method for debugging module detection
    static func analyzePageContent(bodyContent: String, title: String) -> [String: Any] {
        let modules = generateRLPAGEMODULES(bodyContent: bodyContent, title: title)
        
        var analysis: [String: Any] = [:]
        analysis["title"] = title
        analysis["contentLength"] = bodyContent.count
        analysis["detectedModules"] = modules
        analysis["moduleCount"] = modules.count
        
        // Analyze what triggered each pattern
        var triggeredPatterns: [String] = []
        for (pattern, _) in modulePatterns {
            if bodyContent.contains(pattern) {
                triggeredPatterns.append(pattern)
            }
        }
        analysis["triggeredPatterns"] = triggeredPatterns
        
        return analysis
    }
}