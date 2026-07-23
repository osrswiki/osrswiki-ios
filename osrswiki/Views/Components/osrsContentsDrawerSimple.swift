//
//  osrsContentsDrawerSimple.swift
//  osrswiki
//
//  Simplified implementation to test the concept before adding complexity
//

import SwiftUI
import WebKit

/// Simplified contents drawer implementation
struct osrsContentsDrawerSimple: View {
    @Environment(\.osrsTheme) var osrsTheme
    @Binding var isPresented: Bool
    let sections: [TableOfContentsSection]
    let onSectionSelected: (String) -> Void
    
    var body: some View {
        ZStack {
            // Background overlay
            if isPresented {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isPresented = false
                        }
                    }
            }
            
            // Drawer panel from right
            HStack(spacing: 0) {
                Spacer()
                
                if isPresented {
                    VStack(spacing: 0) {
                        // Header
                        HStack {
                            Text("Contents")
                                .font(.headline)
                                .foregroundColor(osrsTheme.onSurface)
                            Spacer()
                        }
                        .padding()
                        .background(osrsTheme.surface)
                        
                        // Contents list with Android-style layout including dotted rail
                        ZStack(alignment: .trailing) {
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    // Top padding to match Android
                                    Color.clear.frame(height: 64)
                                    
                                    ForEach(sections) { section in
                                        Button(action: {
                                            onSectionSelected(section.id)
                                            withAnimation(.easeInOut(duration: 0.25)) {
                                                isPresented = false
                                            }
                                        }) {
                                            HStack {
                                                // Right-aligned text like Android
                                                Text(section.title)
                                                    .font(fontForSection(section))
                                                    .foregroundColor(osrsTheme.onSurface)
                                                    .multilineTextAlignment(.trailing)
                                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                                
                                                Spacer().frame(width: 16)
                                                
                                                // Bullet point like Android
                                                Circle()
                                                    .frame(width: 8, height: 8)
                                                    .foregroundColor(osrsTheme.onSurfaceVariant)
                                                
                                                Spacer().frame(width: 20)
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .frame(minHeight: 48)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                    
                                    // Bottom padding to match Android
                                    Color.clear.frame(height: 64)
                                }
                            }
                            .background(osrsTheme.surface)
                            
                            // Vertical dotted rail positioned like Android (39dp from right edge)
                            osrsDottedRail()
                                .frame(width: 2)
                                .offset(x: -39)
                        }
                        
                        Spacer()
                    }
                    .frame(width: 280)
                    .frame(maxHeight: .infinity)
                    .background(osrsTheme.surface)
                    .ignoresSafeArea()
                    .transition(.move(edge: .trailing))
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isPresented)
    }
    
    private func fontForSection(_ section: TableOfContentsSection) -> Font {
        switch section.level {
        case 1:
            // Main title - use Alegreya Bold, balanced size (midpoint: 24→28 = 26)
            return .custom("Alegreya-Bold", size: 26).weight(.bold)
        case 2:
            // Main headings - use Alegreya Bold, balanced size (midpoint: 18→22 = 20)
            return .custom("Alegreya-Bold", size: 20).weight(.bold)
        default:
            // Sub-headings - use regular Alegreya, balanced size (midpoint: 14→18 = 16)
            return .custom("Alegreya", size: 16).weight(.medium)
        }
    }
}

#Preview {
    @Previewable @State var isPresented = true
    
    return osrsContentsDrawerSimple(
        isPresented: $isPresented,
        sections: [
            TableOfContentsSection(id: "gameplay", title: "Gameplay", level: 1),
            TableOfContentsSection(id: "contents", title: "Contents", level: 2),
            TableOfContentsSection(id: "history", title: "History", level: 2),
            TableOfContentsSection(id: "transportation", title: "Transportation", level: 2),
            TableOfContentsSection(id: "locations", title: "Locations", level: 2),
            TableOfContentsSection(id: "stores", title: "Stores", level: 3),
            TableOfContentsSection(id: "pubs", title: "Pubs", level: 3),
            TableOfContentsSection(id: "banks", title: "Banks", level: 3)
        ],
        onSectionSelected: { sectionId in
            print("Selected section: \(sectionId)")
        }
    )
    .environment(\.osrsTheme, osrsLightTheme())
}

/// Vertical dotted rail replicating Android DottedLineView
struct osrsDottedRail: View {
    @Environment(\.osrsTheme) var osrsTheme
    
    var body: some View {
        GeometryReader { geometry in
            let dotRadius: CGFloat = 1
            let dotGap: CGFloat = 6
            let totalDotSpacing = (dotRadius * 2) + dotGap
            let numberOfDots = Int(geometry.size.height / totalDotSpacing)
            
            VStack(spacing: dotGap) {
                ForEach(0..<numberOfDots, id: \.self) { _ in
                    Circle()
                        .frame(width: dotRadius * 2, height: dotRadius * 2)
                        .foregroundColor(osrsTheme.onSurfaceVariant)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}