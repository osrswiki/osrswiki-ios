//
//  LazyView.swift
//  OSRS Wiki
//
//  Generic wrapper to defer view initialization until actually needed
//  This is a common pattern to fix NavigationStack performance issues
//

import SwiftUI

/// LazyView defers the creation of its content until it's actually needed
/// This prevents NavigationLink/navigationDestination from creating views immediately
struct LazyView<Content: View>: View {
    let build: () -> Content
    
    init(_ build: @autoclosure @escaping () -> Content) {
        self.build = build
    }
    
    init(@ViewBuilder _ build: @escaping () -> Content) {
        self.build = build
    }
    
    var body: Content {
        build()
    }
}