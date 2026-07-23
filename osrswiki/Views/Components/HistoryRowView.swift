//
//  HistoryRowView.swift
//  OSRS Wiki
//
//  Created on iOS theming fixes session
//

import SwiftUI

struct HistoryRowView: View {
    @Environment(\.osrsTheme) var osrsTheme
    let historyItem: HistoryItem
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Main content section (title and description) - matches search results exactly
                VStack(alignment: .leading, spacing: 4) {
                    Text(osrsStringUtils.extractMainTitle(historyItem.pageTitle))
                        .font(.osrsListTitle)  // Use same font as search results
                        .lineLimit(1)
                        .foregroundStyle(.osrsPrimaryTextColor)
                        .multilineTextAlignment(.leading)
                    
                    if let description = historyItem.description {
                        Text(description)
                            .font(.subheadline)
                            .lineLimit(2)
                            .foregroundStyle(.osrsPrimaryTextColor) // Use primary color to match search results
                            .multilineTextAlignment(.leading)
                    }
                }
                
                Spacer()
                
                // Thumbnail positioned on the right (matching search results layout)
                if let thumbnailUrl = historyItem.thumbnailUrl {
                    AsyncImage(url: thumbnailUrl) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .clipped()
                    } placeholder: {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .tint(.osrsPrimaryColor)
                            .frame(width: 60, height: 60)
                    }
                    .frame(width: 60, height: 60)
                    .background(.clear)
                    .cornerRadius(8)
                } else {
                    // Fallback placeholder when no thumbnail is available
                    Image(systemName: "doc.text")
                        .font(.title2)
                        .foregroundStyle(.osrsSecondaryTextColor)
                        .frame(width: 60, height: 60)
                        .background(.clear)
                        .cornerRadius(8)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8) // Match search results padding
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .listRowBackground(osrsTheme.surface)
        .listRowSeparator(.visible, edges: .bottom)
        .listRowSeparatorTint(osrsTheme.divider)
    }
}

// MARK: - ThemedHistoryItem Model
struct ThemedHistoryItem: Identifiable, Hashable {
    let id = UUID()
    let pageTitle: String
    let pageUrl: String
    let snippet: String?
    let timestamp: Date
    let source: Int
    
    var sourceDescription: String {
        switch source {
        case 1: return "Search"
        case 2: return "Link"
        case 3: return "External"
        case 4: return "History"
        case 5: return "Saved"
        case 6: return "Main"
        case 7: return "Random"
        case 8: return "News"
        default: return "Unknown"
        }
    }
    
    init(pageTitle: String, pageUrl: String, snippet: String? = nil, timestamp: Date = Date(), source: Int = 1) {
        self.pageTitle = pageTitle
        self.pageUrl = pageUrl
        self.snippet = snippet
        self.timestamp = timestamp
        self.source = source
    }
}

#Preview {
    List {
        HistoryRowView(
            historyItem: HistoryItem(
                id: "1",
                pageTitle: "Dragon Scimitar",
                pageUrl: URL(string: "https://oldschool.runescape.wiki/w/Dragon_scimitar")!,
                visitedDate: Date().addingTimeInterval(-3600),
                thumbnailUrl: nil,
                description: "A powerful melee weapon that requires 60 Attack to wield. The dragon scimitar has a special attack."
            ),
            onTap: { }
        )
        
        HistoryRowView(
            historyItem: HistoryItem(
                id: "2", 
                pageTitle: "Coins",
                pageUrl: URL(string: "https://oldschool.runescape.wiki/w/Coins")!,
                visitedDate: Date().addingTimeInterval(-7200),
                thumbnailUrl: URL(string: "https://oldschool.runescape.wiki/images/0/05/Coins_10000.png"),
                description: "Coins are the most common form of currency in Old School RuneScape."
            ),
            onTap: { }
        )
    }
    .listStyle(PlainListStyle())
    .environment(\.osrsTheme, osrsLightTheme())
}