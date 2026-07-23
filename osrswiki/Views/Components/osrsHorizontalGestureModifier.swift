//
//  osrsHorizontalGestureModifier.swift
//  osrswiki
//
//  iOS implementation of horizontal gesture navigation
//  Provides Android feature parity for back gestures and sidebar opening
//

import SwiftUI

/// Direction for horizontal gestures matching Android's Gravity constants
enum HorizontalGestureDirection {
    case start    // Right swipe - equivalent to Android Gravity.START (back)
    case end      // Left swipe - equivalent to Android Gravity.END (sidebar)
}

/// State tracking for gesture conflict resolution
class osrsGestureState: ObservableObject {
    @Published var isHorizontalScrollInProgress = false
    @Published var isJavaScriptScrollBlocked = false
    
    static let shared = osrsGestureState()
    private init() {}
    
    /// Combined state check - mimics Android's multiple blocking layers
    var shouldBlockGestures: Bool {
        return isHorizontalScrollInProgress || isJavaScriptScrollBlocked
    }
    
    /// Reset all gesture blocking states
    func resetState() {
        isHorizontalScrollInProgress = false
        isJavaScriptScrollBlocked = false
    }
}

/// iOS horizontal gesture recognizer matching Android's gesture system
struct osrsHorizontalGestureModifier: ViewModifier {
    let onBackGesture: () -> Void
    let onSidebarGesture: () -> Void
    let isEnabled: Bool
    
    // Back swipes should feel like iOS edge navigation; sidebar swipes keep the
    // more deliberate Android-style threshold to avoid accidental drawer opens.
    private let backEdgeActivationWidth: CGFloat = 56
    private let backHorizontalThreshold: CGFloat = 36
    private let sidebarHorizontalThreshold: CGFloat = 100
    private let verticalThreshold: CGFloat = 32     // Android: 32dp vertical slop
    private let velocityThreshold: CGFloat = 100    // Android: 100px/s velocity
    
    @StateObject private var gestureState = osrsGestureState.shared
    @GestureState private var dragOffset: CGSize = .zero
    @State private var gestureDirection: HorizontalGestureDirection?
    
    init(
        isEnabled: Bool = true,
        onBackGesture: @escaping () -> Void,
        onSidebarGesture: @escaping () -> Void
    ) {
        self.isEnabled = isEnabled
        self.onBackGesture = onBackGesture
        self.onSidebarGesture = onSidebarGesture
    }
    
    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .updating($dragOffset) { value, state, _ in
                        state = value.translation
                    }
                    .onChanged { value in
                        // Only process gestures when enabled and not blocked
                        guard isEnabled && !gestureState.shouldBlockGestures else {
                            return
                        }
                        
                        let translation = value.translation
                        let dx = abs(translation.width)
                        let dy = abs(translation.height)
                        
                        // Log gesture details matching Android pattern
                        print("[HorizontalGesture] dx=\(Int(dx)), dy=\(Int(dy)), blocked=\(gestureState.shouldBlockGestures)")
                        
                        // Check if this is a qualifying horizontal gesture (Android logic)
                        if dy > verticalThreshold {
                            // Vertical scroll detected - disqualify gesture
                            print("[HorizontalGesture] Vertical scroll detected, disqualifying gesture")
                            gestureDirection = nil
                            return
                        }
                        
                        // Check for horizontal gesture threshold
                        let newDirection: HorizontalGestureDirection = translation.width > 0 ? .start : .end
                        let threshold = newDirection == .start ? backHorizontalThreshold : sidebarHorizontalThreshold
                        if dx > threshold {
                            if gestureDirection != newDirection {
                                gestureDirection = newDirection
                                let directionName = newDirection == .start ? "START (back)" : "END (sidebar)"
                                print("[HorizontalGesture] Direction detected: \(directionName)")
                            }
                        }
                    }
                    .onEnded { value in
                        defer {
                            gestureDirection = nil
                            gestureState.resetState()
                        }
                        
                        // Only process if gestures are enabled and not blocked
                        guard isEnabled && !gestureState.shouldBlockGestures else {
                            print("[HorizontalGesture] Gesture blocked or disabled")
                            return
                        }
                        
                        let translation = value.translation  
                        let velocity = value.velocity
                        let dx = abs(translation.width)
                        let dy = abs(translation.height)
                        let velocityX = abs(velocity.width)
                        
                        let isBackGesture = translation.width > 0
                        let horizontalThreshold = isBackGesture ? backHorizontalThreshold : sidebarHorizontalThreshold

                        // Validate gesture meets direction-specific thresholds.
                        let isValidHorizontalGesture =
                            dx > dy &&
                            dx > horizontalThreshold &&
                            velocityX > velocityThreshold &&
                            dy <= verticalThreshold &&
                            (!isBackGesture || value.startLocation.x <= backEdgeActivationWidth)
                        
                        guard isValidHorizontalGesture else {
                            print("[HorizontalGesture] Failed validation - dx_vs_dy=\(dx > dy), dx_threshold=\(dx > horizontalThreshold), vel_threshold=\(velocityX > velocityThreshold), edge=\(value.startLocation.x <= backEdgeActivationWidth)")
                            return
                        }
                        
                        // Execute the appropriate gesture action
                        if translation.width > 0 {
                            // Right swipe - back gesture  
                            print("[HorizontalGesture] Executing back gesture")
                            onBackGesture()
                        } else {
                            // Left swipe - sidebar gesture
                            print("[HorizontalGesture] Executing sidebar gesture")
                            onSidebarGesture()
                        }
                    }
            )
    }
}

/// View extension for easy gesture integration
extension View {
    /// Add horizontal gestures matching Android functionality
    func osrsHorizontalGestures(
        isEnabled: Bool = true,
        onBackGesture: @escaping () -> Void,
        onSidebarGesture: @escaping () -> Void
    ) -> some View {
        self.modifier(osrsHorizontalGestureModifier(
            isEnabled: isEnabled,
            onBackGesture: onBackGesture,
            onSidebarGesture: onSidebarGesture
        ))
    }
}

#Preview {
    VStack {
        Text("Swipe left or right to test gestures")
            .padding()
        
        Rectangle()
            .fill(Color.blue.opacity(0.3))
            .frame(height: 200)
            .overlay(
                Text("Gesture Area\n← Sidebar | Back →")
                    .multilineTextAlignment(.center)
            )
    }
    .osrsHorizontalGestures(
        onBackGesture: {
            print("Back gesture triggered!")
        },
        onSidebarGesture: {
            print("Sidebar gesture triggered!")
        }
    )
}
