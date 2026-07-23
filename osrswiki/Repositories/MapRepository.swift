//
//  MapRepository.swift
//  OSRS Wiki
//
//  Created on iOS development session
//

import Foundation

class MapRepository {
    
    func fetchDefaultMap() async throws -> MapData {
        // Simulate loading default overworld map
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
        
        return MapData(
            id: "overworld",
            name: "OSRS Overworld Map",
            imageUrl: URL(string: "https://oldschool.runescape.wiki/images/thumb/Gielinor.png/1200px-Gielinor.png")!,
            type: .overworld,
            width: 1200,
            height: 1200
        )
    }
    
    func fetchMap(type: MapType) async throws -> MapData {
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
        
        switch type {
        case .overworld:
            return MapData(
                id: "overworld",
                name: "OSRS Overworld Map",
                imageUrl: URL(string: "https://oldschool.runescape.wiki/images/thumb/Gielinor.png/1200px-Gielinor.png")!,
                type: .overworld,
                width: 1200,
                height: 1200
            )
        case .underground:
            return MapData(
                id: "underground",
                name: "Underground Map",
                imageUrl: URL(string: "https://oldschool.runescape.wiki/images/thumb/Underground.png/1200px-Underground.png")!,
                type: .underground,
                width: 1200,
                height: 1200
            )
        case .zeah:
            return MapData(
                id: "zeah",
                name: "Zeah Map",
                imageUrl: URL(string: "https://oldschool.runescape.wiki/images/thumb/Zeah.png/1200px-Zeah.png")!,
                type: .zeah,
                width: 1000,
                height: 1000
            )
        case .tutorial:
            return MapData(
                id: "tutorial",
                name: "Tutorial Island",
                imageUrl: URL(string: "https://oldschool.runescape.wiki/images/thumb/Tutorial_Island.png/800px-Tutorial_Island.png")!,
                type: .tutorial,
                width: 800,
                height: 600
            )
        }
    }
}