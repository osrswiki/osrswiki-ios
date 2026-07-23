//
//  TabItem.swift
//  OSRS Wiki
//
//  Created on iOS development session
//

import SwiftUI

enum TabItem: String, CaseIterable {
    case news = "news"
    case map = "map" 
    case search = "search"
    case saved = "saved"
    case more = "more"
    
    var title: String {
        switch self {
        case .news:
            return "Home"
        case .map:
            return "Map"
        case .search:
            return "Search"
        case .saved:
            return "Saved"
        case .more:
            return "More"
        }
    }
    
    var iconName: String {
        switch self {
        case .news:
            return "house"
        case .map:
            return "map"
        case .search:
            return "magnifyingglass"
        case .saved:
            return "bookmark"
        case .more:
            return "ellipsis"
        }
    }
    
    var selectedIconName: String {
        switch self {
        case .news:
            return "house.fill"
        case .map:
            return "map.fill"
        case .search:
            return "magnifyingglass"
        case .saved:
            return "bookmark.fill"
        case .more:
            return "ellipsis"
        }
    }
    
    var accessibilityLabel: String {
        return "\(title) tab"
    }
}