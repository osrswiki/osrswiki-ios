//
//  osrsSpecConformanceFixtures.swift
//  OSRS Wiki
//
//  Deterministic DEBUG fixtures for spec-driven UI conformance tests.
//

#if DEBUG
import Foundation

enum osrsSpecConformanceFixtures {
    static let homeFeed = WikiFeed(
        recentUpdates: [
            UpdateItem(
                title: "New Regional Worlds Launch TODAY!",
                snippet: "This week's update brings new Regional Worlds and some handy Farming QoL and Sailing Changes!",
                imageUrl: "https://oldschool.runescape.wiki/images/thumb/Lumbridge.png/320px-Lumbridge.png",
                articleUrl: "https://oldschool.runescape.wiki/w/Lumbridge"
            ),
            UpdateItem(
                title: "Bank Tags, Trouver System Rework & More!",
                snippet: "Bank Tags for mobile and the Official Client, Leagues VI rewards tweaks, new Slayer unlocks for Frost Dragons, Trouver System Rework and more!",
                imageUrl: "https://oldschool.runescape.wiki/images/thumb/Varrock.png/320px-Varrock.png",
                articleUrl: "https://oldschool.runescape.wiki/w/Varrock"
            ),
            UpdateItem(
                title: "New Regional Worlds Launch TODAY!",
                snippet: "This week's update brings new Regional Worlds and some handy Farming QoL and Sailing Changes!",
                imageUrl: "https://oldschool.runescape.wiki/images/thumb/Falador.png/320px-Falador.png",
                articleUrl: "https://oldschool.runescape.wiki/w/Falador"
            )
        ],
        announcements: [
            AnnouncementItem(
                date: "Today",
                content: "Spec fixture announcement for conformance testing."
            )
        ],
        onThisDay: OnThisDayItem(
            title: "On this day",
            events: [
                "2007 - Spec fixture milestone",
                "2013 - Spec fixture community update"
            ]
        ),
        popularPages: [
            PopularPageItem(
                title: "Spec Fixture Popular Page",
                pageUrl: "https://oldschool.runescape.wiki/w/Old_School_RuneScape_Wiki"
            ),
            PopularPageItem(
                title: "Spec Fixture Boss Guide",
                pageUrl: "https://oldschool.runescape.wiki/w/Boss"
            )
        ]
    )
}
#endif
