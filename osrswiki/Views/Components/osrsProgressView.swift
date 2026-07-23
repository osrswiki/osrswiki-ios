//
//  osrsProgressView.swift  
//  OSRS Wiki
//
//  Custom progress view matching Android design
//

import SwiftUI

struct osrsProgressView: View {
    let progress: Double // 0.0 to 1.0
    let progressText: String
    
    // Colors matching Android implementation
    private let backgroundColor = Color.black // osrs_loading_bar_black
    private let borderColor = Color(red: 0x8c/255.0, green: 0x11/255.0, blue: 0x11/255.0) // osrs_loading_bar_red #8c1111
    private let fillColor = Color(red: 0x8c/255.0, green: 0x11/255.0, blue: 0x11/255.0) // osrs_loading_bar_red #8c1111
    
    // Debug flag for font loading
    private static var fontDebugLogged = false
    
    // RuneScape font matching Android implementation
    private var runescapeFont: Font {
        // Debug font loading once
        if !Self.fontDebugLogged {
            Self.fontDebugLogged = true
            let allFonts = UIFont.familyNames.flatMap { UIFont.fontNames(forFamilyName: $0) }
            let runeFonts = allFonts.filter { $0.lowercased().contains("rune") }
            print("🔍 Available RuneScape fonts: \(runeFonts)")
        }
        
        // Try different possible font names for runescape_plain
        let fontNames = ["RuneScape Plain 12", "runescape_plain", "RuneScape Plain", "RuneScape", "runescape", "runescape-plain"]
        for fontName in fontNames {
            if UIFont(name: fontName, size: 14) != nil {
                print("✅ Found RuneScape font: \(fontName)")
                return Font.custom(fontName, size: 14)
            }
        }
        
        // For now, use a distinctive font that shows the difference
        print("⚠️ Using fallback bold monospaced font (should be replaced with RuneScape)")
        return Font.system(size: 14, weight: .bold, design: .monospaced)
    }
    
    var body: some View {
        // Container matching Android size: 305dp × 35dp - will be centered by parent ZStack
        ZStack {
            // Background rectangle with border
            Rectangle()
                .fill(backgroundColor)
                .overlay(
                    Rectangle()
                        .stroke(borderColor, lineWidth: 1)
                )
            
            // Progress fill with clipped width
            HStack {
                Rectangle()
                    .fill(fillColor)
                    .overlay(
                        Rectangle()
                            .stroke(Color.black, lineWidth: 1)
                    )
                    .frame(width: max(0, (305 * progress))) // Clip to progress percentage
                
                Spacer(minLength: 0)
            }
            
            // Progress text overlay (centered)
            Text(progressText)
                .font(runescapeFont) // Use RuneScape font matching Android
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
        }
        .frame(width: 305, height: 35) // Match Android dimensions (dp ≈ points on iOS)
    }
}

#Preview {
    VStack(spacing: 20) {
        osrsProgressView(progress: 0.0, progressText: "Loading page...")
        osrsProgressView(progress: 0.3, progressText: "Loading page...")  
        osrsProgressView(progress: 0.7, progressText: "Loading page...")
        osrsProgressView(progress: 1.0, progressText: "Loading page...")
    }
    .padding()
    .background(Color.gray.opacity(0.1))
}