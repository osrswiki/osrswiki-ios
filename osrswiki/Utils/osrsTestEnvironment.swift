//
//  osrsTestEnvironment.swift
//  osrswiki
//
//  Lightweight launch-environment checks for deterministic XCTest runs.
//

import Foundation

enum osrsNetworkConditionForTests: Equatable {
    case none
    case latency(seconds: TimeInterval)
    case timeout(after: TimeInterval)
    case connectionLost(after: TimeInterval)
    case serverError(statusCode: Int, after: TimeInterval)
    case captivePortal(after: TimeInterval)

    static func fromLaunchArgument(_ value: String) -> osrsNetworkConditionForTests {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard let name = parts.first?.lowercased() else { return .none }

        switch name {
        case "latency":
            return .latency(seconds: delay(from: parts, at: 1))
        case "timeout":
            return .timeout(after: delay(from: parts, at: 1))
        case "connectionlost", "connection-lost", "lost":
            return .connectionLost(after: delay(from: parts, at: 1))
        case "servererror", "server-error", "server":
            let statusCode = parts.count > 1 ? Int(parts[1]) ?? 503 : 503
            return .serverError(statusCode: statusCode, after: delay(from: parts, at: 2))
        case "captiveportal", "captive-portal", "captive":
            return .captivePortal(after: delay(from: parts, at: 1))
        default:
            return .none
        }
    }

    private static func delay(from parts: [Substring], at index: Int) -> TimeInterval {
        guard parts.indices.contains(index),
              let value = TimeInterval(parts[index]) else {
            return 0
        }
        return max(0, value)
    }
}

enum osrsTestEnvironment {
    static let osrsUITestHarnessLaunchArgument = "-osrsUITestHarness"

    static var isRunningHostedXCTest: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil ||
            environment["XCTestBundlePath"] != nil
    }

    static var isRunningSimulatorUITestHarness: Bool {
#if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains(osrsUITestHarnessLaunchArgument)
#else
        false
#endif
    }

    static var disablesStartupSideEffects: Bool {
        ProcessInfo.processInfo.arguments.contains("-disableBackgroundPreloading") ||
            isRunningHostedXCTest
    }

    static var allowsProxyStartupDuringTests: Bool {
        ProcessInfo.processInfo.arguments.contains("-allowProxyStartupDuringTests")
    }

    static var forcesNetworkOfflineForUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-forceNetworkOfflineForUITests")
    }

    static var networkConditionForUITests: osrsNetworkConditionForTests {
        let arguments = ProcessInfo.processInfo.arguments
        guard let conditionIndex = arguments.firstIndex(of: "-networkConditionForUITests"),
              conditionIndex + 1 < arguments.count else {
            return .none
        }
        return osrsNetworkConditionForTests.fromLaunchArgument(arguments[conditionIndex + 1])
    }

    static var seedsOfflineSavedPageForUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-seedOfflineSavedPageForUITests")
    }

    static var seedsRetryableSavedPageForUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-seedRetryableSavedPageForUITests")
    }

    static var stubsShareSheetsForUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-stubShareSheetsForUITests")
    }

    static var usesTestShareReceiverActivityForUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-useTestShareReceiverActivityForUITests")
    }

    static var forcesArticleRefreshFailureForUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-forceArticleRefreshFailureForUITests")
    }

    static var forcesArticleReloadNetworkFailureAfterFirstSuccessForUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-forceArticleReloadNetworkFailureAfterFirstSuccessForUITests")
    }

    static var disablesSearchAutofocusForUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-disableSearchAutofocusForUITests")
    }

    static var usesDeepNavigationFixtureForUITests: Bool {
#if DEBUG
        isRunningSimulatorUITestHarness &&
            ProcessInfo.processInfo.arguments.contains(osrsDeepNavigationFixtureAudit.useArticleFixtureLaunchArgument)
#else
        false
#endif
    }

    static var runsDeepNavigationFixtureAuditForUITests: Bool {
#if DEBUG
        isRunningSimulatorUITestHarness &&
            ProcessInfo.processInfo.arguments.contains(osrsDeepNavigationFixtureAudit.runAuditLaunchArgument)
#else
        false
#endif
    }
}
