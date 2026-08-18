//
//  osrsHorizontalGestureModifier.swift
//  osrswiki
//
//  iOS implementation of horizontal gesture navigation
//  Provides Android feature parity for back gestures and sidebar opening
//

import SwiftUI

/// Direction for horizontal gestures matching Android's Gravity constants
enum HorizontalGestureDirection: Equatable {
    case start    // Right swipe - equivalent to Android Gravity.START (back)
    case end      // Left swipe - equivalent to Android Gravity.END (sidebar)
}

/// State tracking for gesture conflict resolution
class osrsGestureState: ObservableObject {
    private struct JavaScriptGestureSequence {
        let id: String
        let isLocalOwner: Bool
        var isTerminal: Bool
        var nativeGeneration: UInt64?
    }

    private struct ArticleGestureSequence {
        let generation: UInt64
        var javaScriptGestureId: String?
        var hasNativeEnded = false
        var pendingNavigationAction: (() -> Void)?
    }

    @Published var isHorizontalScrollInProgress = false
    @Published var isJavaScriptScrollBlocked = false
    private var activeJavaScriptGestureId: String?
    private var pendingReleaseWorkItem: DispatchWorkItem?
    private var activeNativeGestureIds: Set<String> = []
    private var pendingNativeReleaseWorkItems: [String: DispatchWorkItem] = [:]
    private var javaScriptSequence: JavaScriptGestureSequence?
    private var articleGestureSequence: ArticleGestureSequence?
    private var nextArticleGestureGeneration: UInt64 = 0
    private static let ownerReleaseDelay: TimeInterval = 0.35
    
    static let shared = osrsGestureState()
    private init() {}
    
    /// Combined state check - mimics Android's multiple blocking layers
    var shouldBlockGestures: Bool {
        return isHorizontalScrollInProgress ||
            isJavaScriptScrollBlocked ||
            !activeNativeGestureIds.isEmpty
    }

    func claimJavaScriptGesture(id: String) {
        pendingReleaseWorkItem?.cancel()
        activeJavaScriptGestureId = id
        isJavaScriptScrollBlocked = true
    }

    /// Classify every DOM touch sequence, including ordinary article content. Article
    /// navigation therefore fails closed until it receives a matching terminal classification.
    func classifyJavaScriptGesture(id: String, isLocalOwner: Bool) {
        // A different DOM sequence cannot satisfy a native gesture that was waiting on an
        // earlier ID. Cancel that native generation before accepting the replacement.
        if let articleSequence = articleGestureSequence,
           let boundId = articleSequence.javaScriptGestureId,
           boundId != id {
            cancelArticleGesture(generation: articleSequence.generation)
        }

        let nativeGeneration: UInt64?
        if var articleSequence = articleGestureSequence,
           articleSequence.javaScriptGestureId == nil,
           !articleSequence.hasNativeEnded {
            articleSequence.javaScriptGestureId = id
            self.articleGestureSequence = articleSequence
            nativeGeneration = articleSequence.generation
        } else if articleGestureSequence?.javaScriptGestureId == id {
            nativeGeneration = articleGestureSequence?.generation
        } else {
            nativeGeneration = nil
        }

        javaScriptSequence = JavaScriptGestureSequence(
            id: id,
            isLocalOwner: isLocalOwner,
            isTerminal: false,
            nativeGeneration: nativeGeneration
        )
        if isLocalOwner {
            claimJavaScriptGesture(id: id)
        }
    }

    /// DOM touchend can precede SwiftUI DragGesture.onEnded. Keep the claim latched until
    /// native arbitration finishes; the delayed release is only a safety net when SwiftUI
    /// never receives an end event (for example after view teardown).
    func endJavaScriptGesture(id: String) {
        if javaScriptSequence?.id == id {
            javaScriptSequence?.isTerminal = true
        }
        guard activeJavaScriptGestureId == id else {
            resolveNavigationIfClassified()
            return
        }
        pendingReleaseWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.activeJavaScriptGestureId == id else { return }
            self.activeJavaScriptGestureId = nil
            self.isJavaScriptScrollBlocked = false
        }
        pendingReleaseWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.ownerReleaseDelay,
            execute: workItem
        )
        resolveNavigationIfClassified()
    }

    func cancelJavaScriptGesture(id: String) {
        guard javaScriptSequence?.id == id || activeJavaScriptGestureId == id else { return }
        pendingReleaseWorkItem?.cancel()
        pendingReleaseWorkItem = nil
        if activeJavaScriptGestureId == id {
            activeJavaScriptGestureId = nil
            isJavaScriptScrollBlocked = false
        }
        if let generation = javaScriptSequence?.nativeGeneration {
            cancelArticleGesture(generation: generation)
        }
        javaScriptSequence = nil
    }

    /// MapLibre can have pan and pinch recognizers active at the same time. Track each
    /// recognizer independently so one finger/recognizer ending cannot release the other.
    func claimNativeGesture(id: String) {
        // An embedded native map recognizer is an explicit local owner. It vetoes the native
        // article swipe generation immediately, even if MapLibre begins after SwiftUI does.
        cancelArticleGesture()
        pendingNativeReleaseWorkItems.removeValue(forKey: id)?.cancel()
        activeNativeGestureIds.insert(id)
    }

    func endNativeGesture(id: String) {
        guard activeNativeGestureIds.contains(id) else { return }
        pendingNativeReleaseWorkItems.removeValue(forKey: id)?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.activeNativeGestureIds.contains(id) else { return }
            self.activeNativeGestureIds.remove(id)
            self.pendingNativeReleaseWorkItems.removeValue(forKey: id)
        }
        pendingNativeReleaseWorkItems[id] = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.ownerReleaseDelay,
            execute: workItem
        )
    }

    @discardableResult
    func beginArticleGesture() -> UInt64 {
        if let active = articleGestureSequence, !active.hasNativeEnded {
            return active.generation
        }

        // A missing terminal event from the previous native drag cannot remain eligible for a
        // later DOM touch. Starting the next native drag deterministically cancels it.
        cancelArticleGesture()
        nextArticleGestureGeneration &+= 1

        let activeJavaScriptId: String?
        if var sequence = javaScriptSequence, !sequence.isTerminal {
            activeJavaScriptId = sequence.id
            sequence.nativeGeneration = nextArticleGestureGeneration
            javaScriptSequence = sequence
        } else {
            activeJavaScriptId = nil
            if javaScriptSequence?.isTerminal == true {
                javaScriptSequence = nil
            }
        }

        articleGestureSequence = ArticleGestureSequence(
            generation: nextArticleGestureGeneration,
            javaScriptGestureId: activeJavaScriptId
        )
        return nextArticleGestureGeneration
    }

    func performNavigationAfterClassification(
        generation: UInt64,
        _ action: @escaping () -> Void
    ) {
        guard var articleSequence = articleGestureSequence,
              articleSequence.generation == generation else {
            return
        }

        articleSequence.hasNativeEnded = true
        articleSequence.pendingNavigationAction = action
        articleGestureSequence = articleSequence

        // By native onEnded, the DOM touchstart must already have classified the same physical
        // sequence. If no ID was bound, fail closed now rather than retaining an action that an
        // unrelated future touch could authorize.
        guard articleSequence.javaScriptGestureId != nil else {
            cancelArticleGesture(generation: generation)
            return
        }
        resolveNavigationIfClassified(generation: generation)
    }

    /// Completes a native WebView pan with an ownership result sampled from the DOM at the
    /// pan's original contact point. XCTest and some accessibility-driven drags do not always
    /// deliver a DOM `touchstart`, so the point result is the terminal, generation-bound
    /// handshake for those sequences. A real local DOM owner always retains veto authority.
    func performNavigationAfterPointClassification(
        generation: UInt64,
        isLocalOwnerAtStartPoint: Bool,
        _ action: @escaping () -> Void
    ) {
        guard let articleSequence = articleGestureSequence,
              articleSequence.generation == generation else {
            return
        }

        let realDOMSequence = javaScriptSequence.flatMap { sequence in
            sequence.nativeGeneration == generation ? sequence : nil
        }
        let isVetoed = isLocalOwnerAtStartPoint ||
            realDOMSequence?.isLocalOwner == true ||
            !activeNativeGestureIds.isEmpty

        // Resolve this generation now. No asynchronous callback or later DOM touch may retain
        // or inherit its action after the point-classification response arrives.
        articleGestureSequence = nil
        if javaScriptSequence?.nativeGeneration == generation {
            javaScriptSequence = nil
        }

        guard !isVetoed, !isHorizontalScrollInProgress, !isJavaScriptScrollBlocked else {
            return
        }
        print("[HorizontalGesture] Resolved native generation \(generation) with DOM start-point ownership")
        action()
    }

    func performNavigationAfterClassification(_ action: @escaping () -> Void) {
        guard let generation = articleGestureSequence?.generation else { return }
        performNavigationAfterClassification(generation: generation, action)
    }

    func cancelArticleGesture(generation: UInt64? = nil) {
        if let generation, articleGestureSequence?.generation != generation {
            return
        }
        let cancelledGeneration = articleGestureSequence?.generation
        articleGestureSequence = nil
        if javaScriptSequence?.isTerminal == true ||
            (cancelledGeneration != nil && javaScriptSequence?.nativeGeneration == cancelledGeneration) {
            javaScriptSequence = nil
        }
    }

    private func resolveNavigationIfClassified(generation: UInt64? = nil) {
        guard let articleSequence = articleGestureSequence,
              generation == nil || articleSequence.generation == generation,
              articleSequence.hasNativeEnded,
              let boundId = articleSequence.javaScriptGestureId,
              let sequence = javaScriptSequence,
              sequence.id == boundId,
              sequence.nativeGeneration == articleSequence.generation,
              sequence.isTerminal,
              let action = articleSequence.pendingNavigationAction else { return }
        let resolvedGeneration = articleSequence.generation
        articleGestureSequence = nil
        javaScriptSequence = nil
        guard !sequence.isLocalOwner, !shouldBlockGestures else { return }
        print("[HorizontalGesture] Resolved native generation \(resolvedGeneration) with DOM sequence \(sequence.id)")
        action()
    }

#if DEBUG
    var hasPendingArticleNavigationForTesting: Bool {
        articleGestureSequence?.pendingNavigationAction != nil
    }
#endif
    
    /// Reset all gesture blocking states
    func resetState() {
        pendingReleaseWorkItem?.cancel()
        pendingReleaseWorkItem = nil
        pendingNativeReleaseWorkItems.values.forEach { $0.cancel() }
        pendingNativeReleaseWorkItems.removeAll()
        activeNativeGestureIds.removeAll()
        activeJavaScriptGestureId = nil
        javaScriptSequence = nil
        articleGestureSequence = nil
        isHorizontalScrollInProgress = false
        isJavaScriptScrollBlocked = false
    }
}

/// iOS horizontal gesture recognizer matching Android's gesture system
struct osrsHorizontalGestureModifier: ViewModifier {
    let onBackGesture: () -> Void
    let onSidebarGesture: () -> Void
    let isEnabled: Bool
    let requiresJavaScriptClassification: Bool
    
    // Article navigation intentionally matches Android: a deliberate horizontal
    // swipe may begin anywhere that is not already owned by horizontal web content.
    private let backHorizontalThreshold: CGFloat = 36
    private let sidebarHorizontalThreshold: CGFloat = 100
    private let verticalThreshold: CGFloat = 32     // Android: 32dp vertical slop
    private let velocityThreshold: CGFloat = 100    // Android: 100px/s velocity
    
    @StateObject private var gestureState = osrsGestureState.shared
    @GestureState private var dragOffset: CGSize = .zero
    @State private var gestureDirection: HorizontalGestureDirection?
    @State private var articleGestureGeneration: UInt64?
    
    init(
        isEnabled: Bool = true,
        requiresJavaScriptClassification: Bool = false,
        onBackGesture: @escaping () -> Void,
        onSidebarGesture: @escaping () -> Void
    ) {
        self.isEnabled = isEnabled
        self.requiresJavaScriptClassification = requiresJavaScriptClassification
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
                        if requiresJavaScriptClassification {
                            if articleGestureGeneration == nil {
                                articleGestureGeneration = gestureState.beginArticleGesture()
                            }
                        }
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
                            articleGestureGeneration = nil
                        }
                        
                        // Only process if gestures are enabled and not blocked
                        guard isEnabled && !gestureState.shouldBlockGestures else {
                            print("[HorizontalGesture] Gesture blocked or disabled")
                            if requiresJavaScriptClassification {
                                gestureState.cancelArticleGesture(generation: articleGestureGeneration)
                            }
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
                            dy <= verticalThreshold
                        
                        guard isValidHorizontalGesture else {
                            print("[HorizontalGesture] Failed validation - dx_vs_dy=\(dx > dy), dx_threshold=\(dx > horizontalThreshold), vel_threshold=\(velocityX > velocityThreshold)")
                            if requiresJavaScriptClassification {
                                gestureState.cancelArticleGesture(generation: articleGestureGeneration)
                            }
                            return
                        }
                        
                        // For an article WebView, execute only after WebKit reports the matching
                        // terminal ownership classification. Do not reset global ownership here:
                        // for a pinch this recognizer can end while another finger is still down.
                        if translation.width > 0 {
                            let action = {
                                print("[HorizontalGesture] Executing back gesture")
                                onBackGesture()
                            }
                            if requiresJavaScriptClassification {
                                guard let generation = articleGestureGeneration else {
                                    gestureState.cancelArticleGesture()
                                    return
                                }
                                gestureState.performNavigationAfterClassification(
                                    generation: generation,
                                    action
                                )
                            } else {
                                action()
                            }
                        } else {
                            let action = {
                                print("[HorizontalGesture] Executing sidebar gesture")
                                onSidebarGesture()
                            }
                            if requiresJavaScriptClassification {
                                guard let generation = articleGestureGeneration else {
                                    gestureState.cancelArticleGesture()
                                    return
                                }
                                gestureState.performNavigationAfterClassification(
                                    generation: generation,
                                    action
                                )
                            } else {
                                action()
                            }
                        }
                    }
            )
            .onDisappear {
                guard requiresJavaScriptClassification else { return }
                gestureState.cancelArticleGesture(generation: articleGestureGeneration)
                articleGestureGeneration = nil
            }
    }
}

/// View extension for easy gesture integration
extension View {
    /// Add horizontal gestures matching Android functionality
    func osrsHorizontalGestures(
        isEnabled: Bool = true,
        requiresJavaScriptClassification: Bool = false,
        onBackGesture: @escaping () -> Void,
        onSidebarGesture: @escaping () -> Void
    ) -> some View {
        self.modifier(osrsHorizontalGestureModifier(
            isEnabled: isEnabled,
            requiresJavaScriptClassification: requiresJavaScriptClassification,
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
