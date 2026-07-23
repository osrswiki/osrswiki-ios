//
//  osrsSpeechRecognitionManager.swift
//  osrswiki
//
//  Created on voice search implementation session
//

import Foundation
import Speech
import AVFoundation
import SwiftUI

@MainActor
class osrsSpeechRecognitionManager: NSObject, ObservableObject {
    
    enum SpeechState {
        case idle
        case listening
        case processing
        case error
    }
    
    @Published var currentState: SpeechState = .idle
    @Published var isListening = false
    @Published var errorMessage: String?
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    private var onResult: ((String) -> Void)?
    private var onPartialResult: ((String) -> Void)?
    private var onError: ((String) -> Void)?
    private var onStateChanged: ((SpeechState) -> Void)?
    
    private var lastClickTime: TimeInterval = 0
    private let debounceInterval: TimeInterval = 1.0
    
    override init() {
        super.init()
        setupSpeechRecognizer()
    }
    
    private func setupSpeechRecognizer() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
        speechRecognizer?.delegate = self
    }
    
    func configure(
        onResult: @escaping (String) -> Void,
        onPartialResult: @escaping (String) -> Void = { _ in },
        onError: @escaping (String) -> Void,
        onStateChanged: @escaping (SpeechState) -> Void = { _ in }
    ) {
        self.onResult = onResult
        self.onPartialResult = onPartialResult
        self.onError = onError
        self.onStateChanged = onStateChanged
    }
    
    func startVoiceRecognition() {
        print("osrsSpeechRecognitionManager: startVoiceRecognition() called, current state: \(currentState)")
        
        // Debounce rapid clicks
        let currentTime = Date().timeIntervalSince1970
        if currentTime - lastClickTime < debounceInterval {
            print("osrsSpeechRecognitionManager: Ignoring rapid click (debounced)")
            return
        }
        lastClickTime = currentTime
        
        // Handle different states
        switch currentState {
        case .listening:
            print("osrsSpeechRecognitionManager: Currently listening, stopping recognition")
            stopListening()
            return
        case .processing:
            print("osrsSpeechRecognitionManager: Already processing, ignoring request")
            return
        case .error, .idle:
            break
        }
        
        // Check if speech recognition is available
        guard let speechRecognizer = speechRecognizer else {
            updateState(.error)
            let errorMsg = "Speech recognition is not available on this device."
            self.errorMessage = errorMsg
            onError?(errorMsg)
            return
        }
        
        guard speechRecognizer.isAvailable else {
            updateState(.error)
            let errorMsg = "Speech recognition is currently not available. Please try again later."
            self.errorMessage = errorMsg
            onError?(errorMsg)
            return
        }
        
        // Request permissions and start listening
        requestPermissionsAndStartListening()
    }
    
    private func requestPermissionsAndStartListening() {
        Task {
            do {
                // Check current permission status and request if appropriate
                let currentSpeechStatus = SFSpeechRecognizer.authorizationStatus()
                print("🎤 Current speech recognition status: \(currentSpeechStatus.rawValue)")
                
                let speechAuthStatus: SFSpeechRecognizerAuthorizationStatus
                if currentSpeechStatus == .notDetermined {
                    print("🎤 Speech recognition not determined, requesting permission...")
                    speechAuthStatus = await requestSpeechRecognitionPermission()
                } else if currentSpeechStatus == .denied {
                    print("🎤 Speech recognition denied, re-attempting request in case user changed settings...")
                    // Try requesting again - iOS may allow it if user changed settings
                    speechAuthStatus = await requestSpeechRecognitionPermission()
                } else {
                    // Already authorized or restricted
                    speechAuthStatus = currentSpeechStatus
                }
                
                guard speechAuthStatus == .authorized else {
                    let errorMsg: String
                    if speechAuthStatus == .denied {
                        errorMsg = "Voice search requires speech recognition permission. Please enable it in Settings > Privacy & Security > Speech Recognition > OSRS Wiki."
                    } else if speechAuthStatus == .restricted {
                        errorMsg = "Speech recognition is restricted on this device."
                    } else {
                        errorMsg = "Speech recognition permission not available."
                    }
                    
                    // CRITICAL: Immediately clean up any resources allocated during permission request
                    await cleanupResourcesOnPermissionDenial()
                    await handleError(errorMsg)
                    return
                }
                
                // Check current microphone permission status and request if appropriate
                let currentMicStatus = AVAudioSession.sharedInstance().recordPermission
                print("🎤 Current microphone status: \(currentMicStatus.rawValue)")
                
                let micAuthStatus: AVAudioSession.RecordPermission
                if currentMicStatus == .undetermined {
                    print("🎤 Microphone permission undetermined, requesting permission...")
                    micAuthStatus = await requestMicrophonePermission()
                } else if currentMicStatus == .denied {
                    print("🎤 Microphone permission denied, re-attempting request in case user changed settings...")
                    // Try requesting again - iOS may allow it if user changed settings
                    micAuthStatus = await requestMicrophonePermission()
                } else {
                    // Already granted
                    micAuthStatus = currentMicStatus
                }
                
                guard micAuthStatus == .granted else {
                    let errorMsg = "Voice search requires microphone access. Please enable it in Settings > Privacy & Security > Microphone > OSRS Wiki."
                    
                    // CRITICAL: Immediately clean up any resources allocated during permission request
                    await cleanupResourcesOnPermissionDenial()
                    await handleError(errorMsg)
                    return
                }
                
                // Start listening
                try await startListening()
                
            } catch {
                await handleError("Failed to start voice recognition: \(error.localizedDescription)")
            }
        }
    }
    
    private func requestSpeechRecognitionPermission() async -> SFSpeechRecognizerAuthorizationStatus {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
    
    private func requestMicrophonePermission() async -> AVAudioSession.RecordPermission {
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted ? .granted : .denied)
            }
        }
    }
    
    private func startListening() async throws {
        print("osrsSpeechRecognitionManager: startListening() called")
        
        // Provide haptic feedback
        let impactGenerator = UIImpactFeedbackGenerator(style: .light)
        impactGenerator.impactOccurred()
        
        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        // Prepare audio engine
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw NSError(domain: "SpeechRecognition", code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: "Unable to create recognition request"])
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // Update state
        updateState(.listening)
        
        // Start recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                if let result = result {
                    let transcription = result.bestTranscription.formattedString
                    print("osrsSpeechRecognitionManager: Transcription - \(transcription)")
                    
                    if result.isFinal {
                        print("osrsSpeechRecognitionManager: Final result: '\(transcription)'")
                        self?.onResult?(transcription)
                        self?.stopListening()
                    } else {
                        print("osrsSpeechRecognitionManager: Partial result: '\(transcription)'")
                        self?.onPartialResult?(transcription)
                    }
                }
                
                if let error = error {
                    print("osrsSpeechRecognitionManager: Recognition error: \(error)")
                    await self?.handleError(self?.getErrorMessage(from: error) ?? "Recognition failed")
                }
            }
        }
        
        // Start audio engine
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        print("osrsSpeechRecognitionManager: Speech recognition started successfully")
    }
    
    func stopListening() {
        print("osrsSpeechRecognitionManager: stopListening() called")
        
        // Stop audio engine
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        // Clean up recognition request
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        // Update state based on current state
        if currentState == .listening {
            updateState(.processing)
        }
        
        // Clean up audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("osrsSpeechRecognitionManager: Failed to deactivate audio session: \(error)")
        }
    }
    
    private func updateState(_ newState: SpeechState) {
        currentState = newState
        isListening = newState == .listening
        onStateChanged?(newState)
        
        // Don't auto-clear error message - let the user dismiss the alert
        // Error message will be cleared when user taps "OK" on the alert
        
        // Auto-reset to idle from processing after a delay
        if newState == .processing {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if self.currentState == .processing {
                    self.updateState(.idle)
                }
            }
        }
    }
    
    private func handleError(_ message: String) async {
        print("🚨 osrsSpeechRecognitionManager: Error - \(message)")
        updateState(.error)
        errorMessage = message
        onError?(message)
        
        print("🚨 Error message set: \(errorMessage ?? "nil")")
        print("🚨 Current state: \(currentState)")
        
        // Clean up
        stopListening()
        
        // Auto-reset to idle after error display (but keep error message for alert)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if self.currentState == .error {
                self.updateState(.idle)
            }
        }
    }
    
    private func getErrorMessage(from error: Error) -> String {
        if let nsError = error as NSError? {
            switch nsError.code {
            case 203: // No speech detected
                return "No speech detected. Please speak clearly and try again."
            case 216: // Network error
                return "Network error. Please check your internet connection and try again."
            case 301: // Audio recording error
                return "Microphone error. Please check if another app is using the microphone."
            default:
                return "Speech recognition error. Please try again."
            }
        }
        return error.localizedDescription
    }
    
    func cleanup() {
        print("osrsSpeechRecognitionManager: cleanup() called")
        
        // Stop any ongoing recognition
        if currentState == .listening || currentState == .processing {
            stopListening()
        }
        
        // Cancel recognition task
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        
        // Reset state
        updateState(.idle)
    }
    
    private func cleanupResourcesOnPermissionDenial() async {
        print("osrsSpeechRecognitionManager: cleanupResourcesOnPermissionDenial() called")
        
        // Immediately stop audio engine if running
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        // Cancel any pending recognition requests
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        // Cancel recognition task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Deactivate audio session immediately to free microphone resources
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            print("osrsSpeechRecognitionManager: Audio session deactivated successfully")
        } catch {
            print("osrsSpeechRecognitionManager: Failed to deactivate audio session: \(error)")
        }
        
        // Reset state to idle
        updateState(.idle)
    }
    
    // MARK: - Permission Utilities
    
    /// Check current permission status for debugging
    func getCurrentPermissionStatus() -> (speech: SFSpeechRecognizerAuthorizationStatus, microphone: AVAudioSession.RecordPermission) {
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        let micStatus = AVAudioSession.sharedInstance().recordPermission
        
        print("🎤 Current Permissions - Speech: \(speechStatus.rawValue), Microphone: \(micStatus.rawValue)")
        
        return (speech: speechStatus, microphone: micStatus)
    }
    
    /// Force request permissions even if previously denied (for testing)
    /// Note: iOS will typically not show dialog if previously denied - user must go to Settings
    func forceRequestPermissions() {
        print("🎤 Force requesting permissions...")
        requestPermissionsAndStartListening()
    }

#if DEBUG
    enum osrsSpeechRecognitionTestEvent: Equatable {
        case listening
        case partialResult(String)
        case finalResult(String)
        case denied
        case unavailable
        case noMatch
        case error(String)
    }

    func simulateRecognitionEventForTests(_ event: osrsSpeechRecognitionTestEvent) {
        switch event {
        case .listening:
            errorMessage = nil
            updateState(.listening)
        case .partialResult(let text):
            errorMessage = nil
            if currentState != .listening {
                updateState(.listening)
            }
            onPartialResult?(text)
        case .finalResult(let text):
            errorMessage = nil
            onResult?(text)
            updateState(.processing)
        case .denied:
            let message = "Voice search requires speech recognition permission. Please enable it in Settings > Privacy & Security > Speech Recognition > OSRS Wiki."
            updateState(.error)
            errorMessage = message
            onError?(message)
        case .unavailable:
            let message = "Speech recognition is currently not available. Please try again later."
            updateState(.error)
            errorMessage = message
            onError?(message)
        case .noMatch:
            let message = "No speech detected. Please speak clearly and try again."
            updateState(.error)
            errorMessage = message
            onError?(message)
        case .error(let message):
            updateState(.error)
            errorMessage = message
            onError?(message)
        }
    }
#endif
    
    /// Clear error message (called when user dismisses alert)
    func clearError() {
        print("🎤 Clearing error message")
        errorMessage = nil
    }
    
    deinit {
        // Force cleanup using Task.detached to escape MainActor context
        Task.detached { [audioEngine, recognitionTask, recognitionRequest] in
            // Stop audio engine immediately (capture values to avoid self reference)
            if audioEngine.isRunning {
                audioEngine.stop()
                audioEngine.inputNode.removeTap(onBus: 0)
            }
            
            // Cancel and clean up recognition resources
            recognitionTask?.cancel()
            recognitionRequest?.endAudio()
            
            // Deactivate audio session
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}

// MARK: - SFSpeechRecognizerDelegate
extension osrsSpeechRecognitionManager: SFSpeechRecognizerDelegate {
    nonisolated func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        print("osrsSpeechRecognitionManager: Speech recognizer availability changed to: \(available)")
        
        Task { @MainActor in
            if !available && (self.currentState == .listening || self.currentState == .processing) {
                await self.handleError("Speech recognition became unavailable. Please try again later.")
            }
        }
    }
}
