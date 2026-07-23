//
//  MBTilesReader.swift
//  OSRS Wiki
//
//  MBTiles SQLite database reader for offline map tiles
//

import UIKit
import SQLite3
import Foundation

class MBTilesReader {
    
    private var db: OpaquePointer?
    private let databaseURL: URL
    private let tileCache = NSCache<NSString, NSData>()
    private let dbQueue = DispatchQueue(label: "com.osrswiki.mbtiles", qos: .userInitiated)
    
    init?(mbtilesFileName: String) {
        guard let resourcePath = Bundle.main.path(forResource: mbtilesFileName.replacingOccurrences(of: ".mbtiles", with: ""), ofType: "mbtiles") else {
            print("❌ MBTiles file not found: \(mbtilesFileName)")
            print("📁 Bundle path: \(Bundle.main.bundlePath)")
            if let bundlePath = Bundle.main.resourcePath {
                print("📁 Resource path: \(bundlePath)")
                let fileManager = FileManager.default
                do {
                    let contents = try fileManager.contentsOfDirectory(atPath: bundlePath)
                    print("📁 Bundle contents: \(contents.filter { $0.contains("mbtiles") })")
                } catch {
                    print("❌ Error reading bundle: \(error)")
                }
            }
            return nil
        }
        
        print("✅ Found MBTiles path: \(resourcePath)")
        self.databaseURL = URL(fileURLWithPath: resourcePath)
        
        // Set up tile cache
        tileCache.totalCostLimit = 50 * 1024 * 1024 // 50MB cache
        tileCache.countLimit = 500 // Max 500 tiles cached
        
        if !openDatabase() {
            return nil
        }
        
        print("✅ MBTiles database opened: \(mbtilesFileName)")
    }
    
    deinit {
        closeDatabase()
    }
    
    private func openDatabase() -> Bool {
        print("🔧 Opening database at: \(databaseURL.path)")
        
        // Configure SQLite for multi-threaded access with full mutex protection
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(databaseURL.path, &db, flags, nil)
        
        if result != SQLITE_OK {
            let errorMessage = db != nil ? String(cString: sqlite3_errmsg(db)) : "Unknown SQLite error"
            print("❌ Failed to open MBTiles database: \(errorMessage)")
            if db != nil {
                sqlite3_close(db)
                db = nil
            }
            return false
        }
        print("✅ SQLite database opened successfully with thread safety")
        return true
    }
    
    private func closeDatabase() {
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }
    
    func getTile(z: Int, x: Int, y: Int) -> Data? {
        // Create cache key
        let cacheKey = "tile_\(z)_\(x)_\(y)" as NSString
        
        // Check cache first
        if let cachedData = tileCache.object(forKey: cacheKey) {
            return cachedData as Data
        }
        
        guard let db = db else {
            print("❌ Database not open")
            return nil
        }
        
        // Use dispatch queue to ensure thread-safe SQLite operations
        return dbQueue.sync {
            // MBTiles uses TMS (Tile Map Service) coordinate system
            // We need to flip the Y coordinate for OSM/XYZ tile scheme
            let tmsY = (1 << z) - 1 - y
            
            let query = "SELECT tile_data FROM tiles WHERE zoom_level = ? AND tile_column = ? AND tile_row = ?"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int(statement, 1, Int32(z))
                sqlite3_bind_int(statement, 2, Int32(x))
                sqlite3_bind_int(statement, 3, Int32(tmsY))
                
                if sqlite3_step(statement) == SQLITE_ROW {
                    let dataBlob = sqlite3_column_blob(statement, 0)
                    let dataSize = sqlite3_column_bytes(statement, 0)
                    
                    if let dataBlob = dataBlob {
                        let tileData = Data(bytes: dataBlob, count: Int(dataSize))
                        
                        // Cache the tile data
                        let nsData = tileData as NSData
                        tileCache.setObject(nsData, forKey: cacheKey, cost: tileData.count)
                        
                        sqlite3_finalize(statement)
                        return tileData
                    }
                }
            } else {
                print("❌ Failed to prepare SQL statement: \(String(cString: sqlite3_errmsg(db)))")
            }
            
            sqlite3_finalize(statement)
            return nil
        }
    }
    
    func getMetadata() -> [String: String] {
        guard let db = db else { return [:] }
        
        return dbQueue.sync {
            var metadata: [String: String] = [:]
            let query = "SELECT name, value FROM metadata"
            var statement: OpaquePointer?
            
            if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
                while sqlite3_step(statement) == SQLITE_ROW {
                    if let namePtr = sqlite3_column_text(statement, 0),
                       let valuePtr = sqlite3_column_text(statement, 1) {
                        let name = String(cString: namePtr)
                        let value = String(cString: valuePtr)
                        metadata[name] = value
                    }
                }
            }
            
            sqlite3_finalize(statement)
            return metadata
        }
    }
    
    func getBounds() -> (minLat: Double, minLon: Double, maxLat: Double, maxLon: Double)? {
        let metadata = getMetadata()
        
        if let boundsString = metadata["bounds"] {
            let components = boundsString.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if components.count == 4 {
                return (minLat: components[1], minLon: components[0], maxLat: components[3], maxLon: components[2])
            }
        }
        
        return nil
    }
    
    func getZoomLevels() -> (min: Int, max: Int)? {
        let metadata = getMetadata()
        
        if let minZoomString = metadata["minzoom"],
           let maxZoomString = metadata["maxzoom"],
           let minZoom = Int(minZoomString),
           let maxZoom = Int(maxZoomString) {
            return (min: minZoom, max: maxZoom)
        }
        
        return nil
    }
    
    func clearCache() {
        tileCache.removeAllObjects()
    }
}