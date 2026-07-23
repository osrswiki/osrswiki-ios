//
//  MinimalArticleView.swift
//  OSRS Wiki
//
//  Created for freeze debugging - minimal version to isolate SwiftUI vs WebView issues
//

import SwiftUI

struct MinimalArticleView: View {
    let pageTitle: String?
    let pageUrl: URL
    
    init(pageTitle: String?, pageUrl: URL) {
        // FREEZE DEBUG: Add precise logging to minimal view creation
        let timestamp = DateFormatter.timeFormatter.string(from: Date())
        print("🟢 [\(timestamp)] MINIMAL ARTICLEVIEW: init called for '\(pageTitle ?? "nil")'")
        
        self.pageTitle = pageTitle
        self.pageUrl = pageUrl
        
        let completedTimestamp = DateFormatter.timeFormatter.string(from: Date())
        print("🟢 [\(completedTimestamp)] MINIMAL ARTICLEVIEW: init completed for '\(pageTitle ?? "nil")'")
    }
    
    var body: some View {
        // FREEZE DEBUG: Log body computation to identify freeze location
        let timestamp = DateFormatter.timeFormatter.string(from: Date())
        let _ = print("🟦 [\(timestamp)] MINIMAL ARTICLEVIEW: body computation started for '\(pageTitle ?? "nil")'")
        
        return VStack {
            Text("Minimal Article View")
                .font(.largeTitle)
                .padding()
            
            Text("Title: \(pageTitle ?? "Unknown")")
                .font(.headline)
                .padding()
            
            Text("URL: \(pageUrl.absoluteString)")
                .font(.caption)
                .padding()
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .onAppear {
            let timestamp = DateFormatter.timeFormatter.string(from: Date())
            print("🟢 [\(timestamp)] MINIMAL ARTICLEVIEW: onAppear called")
        }
        .modifier(MinimalBodyCompletionLogger(title: pageTitle ?? "nil"))
    }
}

// FREEZE DEBUG: Helper to log when minimal body computation is complete
struct MinimalBodyCompletionLogger: ViewModifier {
    let title: String
    
    func body(content: Content) -> some View {
        let completedTimestamp = DateFormatter.timeFormatter.string(from: Date())
        let _ = print("🟦 [\(completedTimestamp)] MINIMAL ARTICLEVIEW: body computation completed for '\(title)'")
        return content
    }
}

#Preview {
    NavigationStack {
        MinimalArticleView(
            pageTitle: "Test Article",
            pageUrl: URL(string: "https://example.com")!
        )
    }
}