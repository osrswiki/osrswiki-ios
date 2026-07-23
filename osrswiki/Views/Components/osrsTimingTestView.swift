//
//  osrsTimingTestView.swift
//  osrswiki
//
//  Automated timing test view for measuring progress bar to page visibility delay
//

import SwiftUI

struct osrsTimingTestView: View {
    @StateObject private var viewModel = ArticleViewModel(
        pageUrl: URL(string: "https://oldschool.runescape.wiki/w/Abyssal_whip")!,
        pageTitle: "Abyssal whip"
    )
    @State private var timingResults: [String] = []
    @State private var isTestRunning = false
    @State private var testCount = 0
    @Environment(\.osrsTheme) var osrsTheme
    
    var body: some View {
        VStack(spacing: 20) {
            Text("📊 Progress Bar Timing Test")
                .font(.title)
                .padding()
            
            if isTestRunning {
                VStack {
                    if viewModel.isLoading {
                        osrsProgressView(
                            progress: viewModel.loadingProgress,
                            progressText: viewModel.loadingProgressText ?? "Loading..."
                        )
                        .padding()
                    }
                    
                    Text("Test \(testCount) running...")
                        .foregroundColor(.secondary)
                }
            }
            
            Button(action: runTimingTest) {
                Text(isTestRunning ? "Running Test..." : "Run Timing Test")
                    .padding()
                    .background(isTestRunning ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .disabled(isTestRunning)
            
            if !timingResults.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("📊 Timing Results:")
                        .font(.headline)
                    
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(timingResults.enumerated()), id: \.offset) { index, result in
                                Text("\(index + 1). \(result)")
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(.vertical, 2)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            
            Spacer()
        }
        .padding()
        .onAppear {
            setupTimingObserver()
        }
    }
    
    private func setupTimingObserver() {
        // Create a custom observer to capture timing measurements
        // This will monitor console output for timing messages
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // Auto-start the first test with a longer delay to ensure app is ready
            print("🧪 AUTO-STARTING timing tests in 2 seconds...")
            self.runTimingTest()
        }
    }
    
    private func runTimingTest() {
        guard !isTestRunning else { return }
        
        isTestRunning = true
        testCount += 1
        
        print("🧪 TIMING TEST \(testCount): Starting automated timing measurement")
        
        // Reset timing measurements
        viewModel.loadArticle(theme: osrsTheme)
        
        // Monitor for completion and capture timing
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            if !viewModel.isLoading {
                timer.invalidate()
                
                // Give a moment for logs to appear
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    captureTimingResult()
                    
                    // Auto-run next test after a short delay
                    if testCount < 5 { // Run 5 tests automatically
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            runTimingTest()
                        }
                    } else {
                        isTestRunning = false
                        analyzeResults()
                    }
                }
            }
        }
        
        // Safety timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) {
            timer.invalidate()
            if isTestRunning {
                timingResults.append("Test \(testCount): TIMEOUT (>15s)")
                isTestRunning = false
            }
        }
    }
    
    private func captureTimingResult() {
        // Capture real timing result from ArticleViewModel
        if let realDelay = viewModel.lastMeasuredDelay {
            let result = String(format: "Test \(testCount): %.3fs delay (REAL DATA)", realDelay)
            
            timingResults.append(result)
            print("📊 CAPTURED REAL RESULT: \(result)")
            
            // Provide optimization guidance based on real measured data
            if realDelay > 0.2 {
                print("🔧 OPTIMIZATION: HIGH delay detected (\(String(format: "%.3f", realDelay))s). Check WebView rendering pipeline.")
            } else if realDelay > 0.1 {
                print("🔧 OPTIMIZATION: MODERATE delay (\(String(format: "%.3f", realDelay))s). Consider optimizing progress completion logic.")
            } else {
                print("✅ OPTIMIZATION: Timing is within target range (\(String(format: "%.3f", realDelay))s).")
            }
        } else {
            // Fallback if no measurement is available yet
            let result = String(format: "Test \(testCount): No timing data captured")
            timingResults.append(result)
            print("📊 NO TIMING DATA: Test \(testCount) completed but no delay measurement was captured")
            print("📊 NOTE: This may indicate the timing measurement system needs adjustment")
        }
    }
    
    private func analyzeResults() {
        guard !timingResults.isEmpty else { return }
        
        let delays = timingResults.compactMap { result -> Double? in
            if let range = result.range(of: ": "),
               let endRange = result.range(of: "s delay") {
                let delayString = String(result[result.index(range.upperBound, offsetBy: 0)..<endRange.lowerBound])
                return Double(delayString)
            }
            return nil
        }
        
        if !delays.isEmpty {
            let avgDelay = delays.reduce(0, +) / Double(delays.count)
            let maxDelay = delays.max() ?? 0
            let minDelay = delays.min() ?? 0
            
            let summary = String(format: "📊 SUMMARY: Avg=%.3fs, Min=%.3fs, Max=%.3fs", avgDelay, minDelay, maxDelay)
            timingResults.append("")
            timingResults.append(summary)
            
            if avgDelay > 0.1 {
                timingResults.append("🔧 NEEDS OPTIMIZATION: Average delay exceeds 100ms target")
            } else {
                timingResults.append("✅ PERFORMANCE OK: Average delay within acceptable range")
            }
            
            print("📊 AUTOMATED ANALYSIS: \(summary)")
        }
    }
}

#Preview {
    osrsTimingTestView()
        .environment(\.osrsTheme, osrsLightTheme())
}