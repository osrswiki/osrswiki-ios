//
//  MapViewModel.swift
//  OSRS Wiki
//
//  Created on iOS development session
//

import SwiftUI
import Combine

@MainActor
class MapViewModel: ObservableObject {
    @Published var currentMap: MapData?
    @Published var isLoading: Bool = false
    @Published var mapSize: CGSize = CGSize(width: 1000, height: 1000)
    @Published var zoomLevel: Double = 1.0
    
    private let mapRepository = MapRepository()
    
    func loadDefaultMap() async {
        isLoading = true
        
        // Simulate loading default OSRS map
        do {
            currentMap = try await mapRepository.fetchDefaultMap()
        } catch {
            // Handle error
        }
        
        isLoading = false
    }
    
    func switchToMap(_ mapType: MapType) {
        Task {
            isLoading = true
            do {
                currentMap = try await mapRepository.fetchMap(type: mapType)
            } catch {
                // Handle error
            }
            isLoading = false
        }
    }
    
    func zoomIn() {
        zoomLevel = min(zoomLevel * 1.5, 5.0)
        updateMapSize()
    }
    
    func zoomOut() {
        zoomLevel = max(zoomLevel / 1.5, 0.5)
        updateMapSize()
    }
    
    func resetZoom() {
        zoomLevel = 1.0
        updateMapSize()
    }
    
    private func updateMapSize() {
        let baseSize: CGSize = CGSize(width: 1000, height: 1000)
        mapSize = CGSize(
            width: baseSize.width * zoomLevel,
            height: baseSize.height * zoomLevel
        )
    }
}

// MARK: - Models
struct MapData: Identifiable, Codable {
    let id: String
    let name: String
    let imageUrl: URL
    let type: MapType
    let width: Int
    let height: Int
}

enum MapType: String, CaseIterable, Codable {
    case overworld = "overworld"
    case underground = "underground"
    case zeah = "zeah"
    case tutorial = "tutorial"
    
    var displayName: String {
        switch self {
        case .overworld:
            return "Overworld"
        case .underground:
            return "Underground"
        case .zeah:
            return "Zeah"
        case .tutorial:
            return "Tutorial Island"
        }
    }
}