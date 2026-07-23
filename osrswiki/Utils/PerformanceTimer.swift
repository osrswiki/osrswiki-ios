//
//  PerformanceTimer.swift
//  OSRS Wiki
//
//  Simple performance measurement utility
//

import Foundation
import os.log

class PerformanceTimer {
    static let shared = PerformanceTimer()
    private var startTimes: [String: CFAbsoluteTime] = [:]
    private let logger = Logger(subsystem: "osrswiki", category: "Performance")
    
    func start(_ label: String) {
        startTimes[label] = CFAbsoluteTimeGetCurrent()
        print("⏱️ [\(label)] Started")
    }
    
    func end(_ label: String) -> TimeInterval {
        guard let startTime = startTimes[label] else {
            print("⚠️ [\(label)] No start time found")
            return 0
        }
        
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        print("⏱️ [\(label)] Completed in \(String(format: "%.3f", elapsed))s")
        startTimes.removeValue(forKey: label)
        return elapsed
    }
    
    func measure<T>(_ label: String, block: () throws -> T) rethrows -> T {
        start(label)
        defer { _ = end(label) }
        return try block()
    }
    
    func measureAsync<T>(_ label: String, block: () async throws -> T) async rethrows -> T {
        start(label)
        defer { _ = end(label) }
        return try await block()
    }
}