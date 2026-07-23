//
//  osrsDeepNavigationFixtureAudit.swift
//  osrswiki
//
//  DEBUG-only deterministic article stack fixture for deep navigation audits.
//

import Foundation

#if DEBUG
struct osrsDeepNavigationFixturePage: Equatable {
    let sampleOrdinal: Int
    let depth: Int
    let title: String
    let url: URL
    let nextTitle: String
    let nextURL: URL

    var bodyHTML: String {
        """
        <section class="mw-parser-output osrs-deep-navigation-fixture">
            <p>Deterministic native article navigation fixture sample \(sampleOrdinal), depth \(depth).</p>
            <p><a href="/w/\(osrsDeepNavigationFixtureAudit.articlePath(sampleOrdinal: sampleOrdinal, depth: depth + 1))">osrs fixture next article</a></p>
            <p><a href="/w/File:osrsDeepNavigationFixture.png">ignored file namespace fixture link</a></p>
            <p><a href="/w/Special:RandomRootpage/main">ignored special namespace fixture link</a></p>
        </section>
        """
    }
}

struct osrsDeepNavigationFixtureAuditResult: Equatable {
    let status: String
    let seed: Int
    let startOffset: Int
    let startCount: Int
    let targetDepth: Int
    let completedStarts: Int
    let forwardTransitions: Int
    let backTransitions: Int
    let mismatchCount: Int
    let firstMismatch: String?
    let elapsedMilliseconds: Int
    let finalActiveURL: String?

    var passed: Bool {
        status == "pass" &&
            completedStarts == startCount &&
            forwardTransitions == startCount * targetDepth &&
            backTransitions == startCount * targetDepth &&
            mismatchCount == 0
    }

    var accessibilityLabel: String {
        [
            "status=\(status)",
            "seed=\(seed)",
            "startOffset=\(startOffset)",
            "startCount=\(startCount)",
            "targetDepth=\(targetDepth)",
            "completedStarts=\(completedStarts)",
            "forwardTransitions=\(forwardTransitions)",
            "backTransitions=\(backTransitions)",
            "mismatches=\(mismatchCount)",
            "elapsedMs=\(elapsedMilliseconds)",
            "finalActive=\(finalActiveURL ?? "nil")",
            "firstMismatch=\(firstMismatch ?? "nil")"
        ].joined(separator: ";")
    }

    var summaryDictionary: [String: Any] {
        [
            "status": status,
            "seed": seed,
            "start_offset": startOffset,
            "start_count": startCount,
            "target_depth": targetDepth,
            "completed_starts": completedStarts,
            "forward_transitions": forwardTransitions,
            "back_transitions": backTransitions,
            "mismatch_count": mismatchCount,
            "first_mismatch": firstMismatch as Any,
            "elapsed_ms": elapsedMilliseconds,
            "final_active_url": finalActiveURL as Any
        ]
    }
}

enum osrsDeepNavigationFixtureAudit {
    static let runAuditLaunchArgument = "-runDeepNavigationFixtureAuditForUITests"
    static let useArticleFixtureLaunchArgument = "-useDeepNavigationFixtureForUITests"
    static let seedLaunchArgument = "-deepNavigationFixtureSeed"
    static let startOffsetLaunchArgument = "-deepNavigationFixtureStartOffset"
    static let startCountLaunchArgument = "-deepNavigationFixtureStartCount"
    static let depthLaunchArgument = "-deepNavigationFixtureDepth"

    static let defaultSeed = 20260709
    static let defaultStartOffset = 0
    static let defaultStartCount = 10_000
    static let defaultDepth = 100

    static func launchIntArgument(_ arguments: [String], name: String, defaultValue: Int) -> Int {
        guard let index = arguments.firstIndex(of: name),
              index + 1 < arguments.count,
              let value = Int(arguments[index + 1]) else {
            return defaultValue
        }
        return value
    }

    static func articlePath(sampleOrdinal: Int, depth: Int) -> String {
        "osrsDeepNavigationFixture/\(sampleOrdinal)/\(depth)"
    }

    static func sampleOrdinal(seed: Int, sequence: Int) -> Int {
        seed + sequence
    }

    static func articleTitle(sampleOrdinal: Int, depth: Int) -> String {
        "osrs Deep Navigation Fixture \(sampleOrdinal) Layer \(depth)"
    }

    static func articleURL(sampleOrdinal: Int, depth: Int) -> URL {
        URL(string: "https://oldschool.runescape.wiki/w/\(articlePath(sampleOrdinal: sampleOrdinal, depth: depth))")!
    }

    static func articleDestination(sampleOrdinal: Int, depth: Int) -> ArticleDestination {
        ArticleDestination(
            title: articleTitle(sampleOrdinal: sampleOrdinal, depth: depth),
            url: articleURL(sampleOrdinal: sampleOrdinal, depth: depth)
        )
    }

    static func page(for url: URL, requestedTitle: String?) -> osrsDeepNavigationFixturePage? {
        guard url.scheme?.lowercased() == "https",
              osrsWebKitSecurityPolicy.isTrustedWikiHost(url.host),
              url.path.hasPrefix("/w/osrsDeepNavigationFixture/") else {
            return nil
        }

        let components = url.path
            .split(separator: "/")
            .map(String.init)
        guard components.count == 4,
              components[0] == "w",
              components[1] == "osrsDeepNavigationFixture",
              let sampleOrdinal = Int(components[2]),
              let depth = Int(components[3]) else {
            return nil
        }

        let title = requestedTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        return osrsDeepNavigationFixturePage(
            sampleOrdinal: sampleOrdinal,
            depth: depth,
            title: title?.isEmpty == false ? title! : articleTitle(sampleOrdinal: sampleOrdinal, depth: depth),
            url: articleURL(sampleOrdinal: sampleOrdinal, depth: depth),
            nextTitle: articleTitle(sampleOrdinal: sampleOrdinal, depth: depth + 1),
            nextURL: articleURL(sampleOrdinal: sampleOrdinal, depth: depth + 1)
        )
    }
}
#endif
