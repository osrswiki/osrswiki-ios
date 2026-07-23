#if DEBUG
import SwiftUI

struct osrsThemePreviewView: View {
    @StateObject private var themeManager = osrsThemeManager()

    var body: some View {
        VStack(spacing: 20) {
            Text("OSRS Theme Preview")
                .font(.largeTitle)
                .foregroundStyle(.osrsPrimaryTextColor)

            Text("Primary Text")
                .foregroundStyle(.osrsPrimary)

            Text("Secondary Text")
                .foregroundStyle(.osrsSecondaryTextColor)

            Text("Accent Color")
                .foregroundStyle(.osrsAccent)

            Button("Preview Button") {
                // Preview-only action.
            }
            .foregroundStyle(.osrsOnPrimary)
            .padding()
            .background(.osrsPrimary)
            .cornerRadius(8)

            HStack {
                ForEach(osrsThemeSelection.allCases, id: \.self) { theme in
                    Button(theme.displayName) {
                        themeManager.setTheme(theme)
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(themeManager.selectedTheme == theme ? .osrsAccent : .osrsSurface)
                    .foregroundStyle(themeManager.selectedTheme == theme ? .osrsOnPrimary : .osrsPrimaryTextColor)
                    .cornerRadius(4)
                }
            }
        }
        .padding()
        .background(.osrsBackground)
        .environment(\.osrsTheme, themeManager.currentTheme)
        .environmentObject(themeManager)
    }
}

struct osrsThemePreviewView_Previews: PreviewProvider {
    static var previews: some View {
        osrsThemePreviewView()
    }
}
#endif
