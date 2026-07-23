//
//  osrsProgressViewTestPreview.swift
//  OSRS Wiki
//
//  Test preview for the custom progress bar
//

import SwiftUI

struct osrsProgressViewTestPreview: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("OSRS Custom Progress Bar Test")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("✅ UPDATED: RuneScape font + Vertical centering")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.green)
            
            VStack(spacing: 15) {
                // Different progress states showing improvements
                osrsProgressView(progress: 0.0, progressText: "Starting download...")
                osrsProgressView(progress: 0.1, progressText: "Fetching page data...")
                osrsProgressView(progress: 0.3, progressText: "Downloading content...")
                osrsProgressView(progress: 0.5, progressText: "Processing page...")
                osrsProgressView(progress: 0.7, progressText: "Building page layout...")
                osrsProgressView(progress: 0.9, progressText: "Rendering page...")
                osrsProgressView(progress: 1.0, progressText: "Complete!")
            }
            .padding()
            
            VStack(spacing: 5) {
                Text("✅ RuneScape Plain font (matching Android)")
                    .font(.caption)
                    .foregroundColor(.green)
                
                Text("✅ Vertically centered in container")
                    .font(.caption)
                    .foregroundColor(.green)
                
                Text("✅ Identical Android design & behavior")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .padding()
        .background(Color.osrsBackground)
    }
}

#Preview {
    osrsProgressViewTestPreview()
}