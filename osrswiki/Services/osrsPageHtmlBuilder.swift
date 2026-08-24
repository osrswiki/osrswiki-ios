//
//  osrsPageHtmlBuilder.swift
//  OSRS Wiki
//
//  Created on article rendering parity session
//

import Foundation
import UIKit

class osrsPageHtmlBuilder {
    private let logTag = "PageLoadTrace"

    // Render-blocking first-paint CSS: theme tokens, typography, above-fold chrome.
    // See shared/css/article-css-priority.json.
    private let criticalStyleSheetAssets = [
        "styles/themes.css",
        "styles/base.css",
        "styles/fonts.css",
        "styles/layout.css",
        "styles/components.css",
        "web/collapsible_tables.css",
        "web/collapsible_sections.css",
        "web/switch_infobox_styles.css",
        "styles/gadget_calc.css",
        "styles/fixes.css"
    ]

    private let criticalArticleBundleAsset = "styles/critical-article.min.css"

    // Heavy wiki fidelity sheets. Downloaded immediately but applied after first paint.
    private let deferredStyleSheetAssets = [
        "styles/wiki-integration.css",
        "styles/navbox_styles.css",
        "styles/ios-article-aesthetics.css"
    ]

    private var styleSheetAssets: [String] {
        criticalStyleSheetAssets + deferredStyleSheetAssets
    }

    // MediaWiki ResourceLoader artifacts
    private let mediawikiArtifacts = [
        "startup.js",
        "js/mediawiki/gadget_calc_core.js"
    ]

    private let articleTransformJsAssetPaths = [
        "web/infobox_switcher_bootstrap.js",
        "web/switch_infobox.js",
        "web/collapsible_content.js",
        "web/first_viewport_assets.js",
        "web/live_article_asset_warm.js",
        "web/mobile_article_polish.js",
        "web/horizontal_scroll_interceptor.js",
        "web/image_area_cap.js"
    ]

    // Base JavaScript assets
    private let jsAssetPaths = [
        "web/map_bridge.js",  // CRITICAL: Load bridge first before other scripts need it
        "js/tablesort.min.js",
        "js/tablesort_init.js",
        "web/article_tools.js",
        "web/osrs_calculator_runtime.js",
        "web/tabber_init.js",
        "web/responsive_videos.js",
        "web/clipboard_bridge.js",
        "web/table_column_normalize.js"
    ]

    private func createThemeUtilityScript() -> String {
        return """
        <script>
            // Theme switching utility for instant theme changes
            window.OSRSWikiTheme = {
                switchTheme: function(isDark) {
                    var body = document.body;
                    var root = document.documentElement;
                    if (!body || !root) return;
                    body.classList.toggle('theme-osrs-dark', !!isDark);
                    root.classList.toggle('theme-osrs-dark', !!isDark);
                    root.style.colorScheme = isDark ? 'dark' : 'light';
                    body.offsetHeight;
                    if (body.style.visibility !== 'visible') {
                        body.style.visibility = 'visible';
                    }
                }
            };
        </script>
        """
    }

    private func createTableCollapseScript(collapseTablesEnabled: Bool) -> String {
        let narrowPainted = osrsLoadPerformancePrefs.narrowFirstViewportPaintedSet ? "true" : "false"
        return """
        <script>
            // Global variable for table collapse preference that collapsible_content.js can read
            window.OSRS_TABLE_COLLAPSED = \(collapseTablesEnabled ? "true" : "false");
            console.log('osrsPageHtmlBuilder: Set global collapse preference to ' + window.OSRS_TABLE_COLLAPSED);
            window.__osrsNarrowFirstViewportPaintedSet = \(narrowPainted);
        </script>
        """
    }

    private func createInternalArticleLinkNormalizationScript(customScheme: String) -> String {
        let escapedScheme = customScheme
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")

        return """
        <script>
            (function() {
                var handoffBaseURL = '\(escapedScheme)://localhost';
                var trustedWikiHosts = {
                    'oldschool.runescape.wiki': true,
                    'runescape.wiki': true
                };

                function isArticlePath(pathname) {
                    if (!pathname || pathname.indexOf('/w/') !== 0) {
                        return false;
                    }

                    var encodedTitle = pathname.substring(3);
                    if (encodedTitle.length === 0) {
                        return false;
                    }

                    var decodedTitle = encodedTitle;
                    try {
                        decodedTitle = decodeURIComponent(encodedTitle);
                    } catch (_) {}

                    var lowerTitle = decodedTitle.toLowerCase();
                    return lowerTitle.indexOf('file:') !== 0 &&
                        lowerTitle.indexOf('media:') !== 0 &&
                        lowerTitle.indexOf('special:') !== 0;
                }

                function handoffURLForAnchor(anchor) {
                    if (!anchor || !anchor.getAttribute) {
                        return null;
                    }

                    var rawHref = anchor.getAttribute('href');
                    if (!rawHref) {
                        return null;
                    }

                    var url;
                    try {
                        url = new URL(rawHref, 'https://oldschool.runescape.wiki');
                    } catch (_) {
                        return null;
                    }

                    var protocol = url.protocol.toLowerCase();
                    var host = url.hostname.toLowerCase();
                    if (protocol === 'app-assets:' && host === 'localhost' && isArticlePath(url.pathname)) {
                        return url.toString();
                    }

                    if (protocol !== 'https:' || !trustedWikiHosts[host] || !isArticlePath(url.pathname)) {
                        return null;
                    }

                    return handoffBaseURL + url.pathname + url.search + url.hash;
                }

                function normalizeAnchor(anchor) {
                    var handoffURL = handoffURLForAnchor(anchor);
                    if (!handoffURL) {
                        return;
                    }

                    if (anchor.getAttribute('data-osrs-article-href') !== handoffURL) {
                        anchor.setAttribute('data-osrs-article-href', handoffURL);
                    }

                }

                function normalizeInternalArticleLinks(root) {
                    var scope = root && root.querySelectorAll ? root : document;
                    if (scope.matches && scope.matches('a[href]')) {
                        normalizeAnchor(scope);
                    }

                    var anchors = scope.querySelectorAll ? scope.querySelectorAll('a[href]') : [];
                    for (var index = 0; index < anchors.length; index += 1) {
                        normalizeAnchor(anchors[index]);
                    }
                }

                window.OSRSWikiInternalArticleLinks = {
                    normalizeInternalArticleLinks: normalizeInternalArticleLinks
                };

                normalizeInternalArticleLinks(document);

                if (document.readyState === 'loading') {
                    document.addEventListener('DOMContentLoaded', function() {
                        normalizeInternalArticleLinks(document);
                    }, { once: true });
                }

                setTimeout(function() {
                    normalizeInternalArticleLinks(document);
                }, 0);

                setTimeout(function() {
                    normalizeInternalArticleLinks(document);
                }, 250);

                if (window.MutationObserver && document.documentElement) {
                    new MutationObserver(function(mutations) {
                        for (var mutationIndex = 0; mutationIndex < mutations.length; mutationIndex += 1) {
                            var mutation = mutations[mutationIndex];
                            for (var nodeIndex = 0; nodeIndex < mutation.addedNodes.length; nodeIndex += 1) {
                                var node = mutation.addedNodes[nodeIndex];
                                if (node.nodeType === 1) {
                                    normalizeInternalArticleLinks(node);
                                }
                            }
                        }
                    }).observe(document.documentElement, { childList: true, subtree: true });
                }
            })();
        </script>
        """
    }

    private func generateMediaWikiVariables(title: String, bodyContent: String, canonicalTitle: String? = nil) -> String {
        // Generate smart RLPAGEMODULES based on content analysis
        let detectedModules = osrsWikiModuleRegistry.generateRLPAGEMODULES(
            bodyContent: bodyContent,
            title: canonicalTitle ?? title
        )
        let modulesList = detectedModules.map { "\"\($0)\"" }.joined(separator: ", ")
        let pageConfig = osrsWikiWebViewUrl.mediaWikiPageConfig(
            canonicalTitle: canonicalTitle ?? title,
            displayTitle: title
        )
        let safePageName = pageConfig.pageName.replacingOccurrences(of: "\"", with: "\\\"")
        let safeTitle = pageConfig.title.replacingOccurrences(of: "\"", with: "\\\"")
        let namespaceNumber = pageConfig.namespaceNumber
        let canonicalNamespace = pageConfig.canonicalNamespace

        return """
        <script>
            // Smart MediaWiki variables generated based on page content
            // Module detection via osrsWikiModuleRegistry for scalable maintenance
            var RLCONF = {"wgBreakFrames": false, "wgSeparatorTransformTable": ["", ""], "wgDigitTransformTable": ["", ""], "wgDefaultDateFormat": "dmy", "wgMonthNames": ["", "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"], "wgRequestId": "smart-module-loader", "wgCanonicalNamespace": "\(canonicalNamespace)", "wgCanonicalSpecialPageName": false, "wgNamespaceNumber": \(namespaceNumber), "wgPageName": "\(safePageName)", "wgTitle": "\(safeTitle)", "wgCurRevisionId": 0, "wgRevisionId": 0, "wgArticleId": 1, "wgIsArticle": true, "wgIsRedirect": false, "wgAction": "view", "wgUserName": null, "wgUserGroups": ["*"], "wgPageViewLanguage": "en-gb", "wgPageContentLanguage": "en-gb", "wgPageContentModel": "wikitext", "wgRelevantPageName": "\(safePageName)", "wgRelevantArticleId": 1, "wgIsProbablyEditable": true, "wgRelevantPageIsProbablyEditable": true, "wgRestrictionEdit": [], "wgRestrictionMove": [], "wgServer": "https://oldschool.runescape.wiki", "wgServerName": "oldschool.runescape.wiki", "wgScriptPath": "", "wgScript": "/index.php", "wgLoadScript": "/load.php"};
            var RLSTATE = {"ext.gadget.switch-infobox-styles": "ready", "ext.gadget.articlefeedback-styles": "ready", "ext.gadget.falseSubpage": "ready", "ext.gadget.headerTargetHighlight": "ready", "site.styles": "ready", "user.styles": "ready", "user": "ready", "user.options": "loading", "ext.cite.styles": "ready", "ext.kartographer.style": "ready", "skins.minerva.base.styles": "ready", "skins.minerva.content.styles.images": "ready", "mediawiki.hlist": "ready", "skins.minerva.codex.styles": "ready", "skins.minerva.icons.wikimedia": "ready", "skins.minerva.mainMenu.icons": "ready", "skins.minerva.mainMenu.styles": "ready", "jquery.tablesorter.styles": "ready", "ext.embedVideo.styles": "ready", "mobile.init.styles": "ready"};
            var RLPAGEMODULES = [\(modulesList)];

            // Log detected modules for debugging
            console.log('osrsWikiModuleRegistry detected modules for "\(safeTitle)":', RLPAGEMODULES);
        </script>
        """
    }

    private func createInlineMapBridge() -> String {
        return """
        <script>
        // CRITICAL: Inline Map Bridge for iOS MapLibre integration
        // This ensures the bridge is available as early as possible
        (function() {
            console.log('🚨 [INLINE-BRIDGE] Inline map bridge executing...');
            console.log('🚨 [INLINE-BRIDGE] Document ready state:', document.readyState);

            if (window.OsrsWikiBridge) {
                console.log('🚨 [INLINE-BRIDGE] Bridge already exists, skipping...');
                return;
            }

            // Create OsrsWikiBridge equivalent for iOS MapLibre integration
            window.OsrsWikiBridge = {
                onMapPlaceholderMeasured: function(id, rectJson, mapDataJson) {
                    console.log('🚨 [INLINE-BRIDGE] onMapPlaceholderMeasured called:', id);
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mapBridge) {
                        window.webkit.messageHandlers.mapBridge.postMessage({
                            action: 'onMapPlaceholderMeasured',
                            id: id,
                            rectJson: rectJson,
                            mapDataJson: mapDataJson
                        });
                        console.log('🚨 [INLINE-BRIDGE] Message sent to native layer');
                    } else {
                        console.error('🚨 [INLINE-BRIDGE] webkit.messageHandlers.mapBridge not available');
                    }
                },

                onCollapsibleToggled: function(mapId, isOpening) {
                    console.log('🚨 [INLINE-BRIDGE] onCollapsibleToggled called:', mapId, isOpening);
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mapBridge) {
                        window.webkit.messageHandlers.mapBridge.postMessage({
                            action: 'onCollapsibleToggled',
                            mapId: mapId,
                            isOpening: isOpening
                        });
                    } else {
                        console.error('🚨 [INLINE-BRIDGE] webkit.messageHandlers.mapBridge not available');
                    }
                },

                setHorizontalScroll: function(inProgress) {
                    console.log('🚨 [INLINE-BRIDGE] setHorizontalScroll called:', inProgress);
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mapBridge) {
                        window.webkit.messageHandlers.mapBridge.postMessage({
                            action: 'setHorizontalScroll',
                            inProgress: inProgress
                        });
                    } else {
                        console.error('🚨 [INLINE-BRIDGE] webkit.messageHandlers.mapBridge not available');
                    }
                },

                setHorizontalScrollGesture: function(phase, gestureId, ownerId) {
                    var local = (phase === 'begin' || phase === 'change') && ownerId !== 'article-navigation';
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mapBridge) {
                        window.webkit.messageHandlers.mapBridge.postMessage({
                            action: 'setHorizontalScrollGesture',
                            phase: String(phase || ''),
                            gestureId: String(gestureId || ''),
                            ownerId: String(ownerId || 'article-navigation'),
                            isLocalOwner: !!local
                        });
                    }
                },

                setArticleTouchSequence: function(sequence) {
                    // Handled natively via gesture-id binding on iOS.
                },

                log: function(message) {
                    console.log('🚨 [INLINE-BRIDGE] log called:', message);
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mapBridge) {
                        window.webkit.messageHandlers.mapBridge.postMessage({
                            action: 'log',
                            message: message
                        });
                    } else {
                        console.error('🚨 [INLINE-BRIDGE] webkit.messageHandlers.mapBridge not available');
                    }
                },

                fetchText: function(url) {
                    try {
                        var xhr = new XMLHttpRequest();
                        xhr.open('GET', url, false);
                        xhr.setRequestHeader('Accept', 'application/json');
                        xhr.send(null);
                        return (xhr.status >= 200 && xhr.status < 300) ? (xhr.responseText || '') : '';
                    } catch (e) {
                        return '';
                    }
                },

                openFloorNumberingSettings: function() {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mapBridge) {
                        window.webkit.messageHandlers.mapBridge.postMessage({
                            action: 'openFloorNumberingSettings'
                        });
                    }
                }
            };

            console.log('🗺️ iOS OsrsWikiBridge initialized and ready');
            console.log('🚨 [INLINE-BRIDGE] Bridge object created:', typeof window.OsrsWikiBridge);

            // Test the bridge immediately if possible
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mapBridge) {
                console.log('🚨 [INLINE-BRIDGE] Testing bridge connection...');
                window.OsrsWikiBridge.log('Inline bridge initialization test message');
            } else {
                console.log('🚨 [INLINE-BRIDGE] Bridge created but message handlers not yet available');
            }
        })();
        </script>
        """
    }

    func buildFullHtmlDocument(
        title: String,
        bodyContent: String,
        theme: any osrsThemeProtocol,
        collapseTablesEnabled: Bool = true,
        includeAssetLinks: Bool = false,
        articleTextScale: CGFloat = 1.0,
        floorConvention: osrsArticleFloorConvention = .current(),
        wrapTableCellsEnabled: Bool = false,
        canonicalTitle: String? = nil,
        inlineFirstPaintCss: Bool = false,
        bakeChromeInsets: Bool = true
    ) -> String {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Clean title and prepare header
        let cleanedTitle = extractMainTitle(title)
        let documentTitle = cleanedTitle.isEmpty ? "OSRS Wiki" : cleanedTitle
        // Wave2c/wave4 residual: Calculator:Sailing mid-wraps under
        // overflow-wrap:break-word. Wave6: also break after subpage slash
        // (Construction/Materials). Spaced titles still wrap on spaces.
        let titleHeaderHtml = "<h1 class=\"page-header\">\(softWrapNamespaceTitle(documentTitle))</h1>"
        let customScheme = UserDefaults.standard.string(forKey: "WKURLSchemeHandler_Scheme") ?? "app-assets"

        // Clean any existing page-header titles from bodyContent to prevent duplication
        let cleanedBodyContent = removeDuplicatePageHeaders(bodyContent)
        let normalizedBodyContent = normalizeInternalArticleLinks(in: cleanedBodyContent, customScheme: customScheme)
        let articleBodyContent = wrapArticleBodyContent(normalizedBodyContent)
        let finalBodyContent = titleHeaderHtml + articleBodyContent

        let themeClass = (theme is osrsDarkTheme) ? "theme-osrs-dark" : ""
        let wrapClass = wrapTableCellsEnabled ? "osrs-table-cells-wrap" : ""
        let clampedArticleTextScale = min(max(articleTextScale, 0.85), 1.40)
        let articleTextScaleLiteral = String(
            format: "%.3f",
            locale: Locale(identifier: "en_US_POSIX"),
            Double(clampedArticleTextScale)
        )
        let chromeClearance = bakeChromeInsets ? Int(
            (osrsSearchControlGeometry.compactHeight + osrsOverlayChromeMetrics.pairedEdgeGap + 8).rounded()
        ) : 0
        let bottomChrome = bakeChromeInsets ? Int(
            (osrsOverlayChromeMetrics.floatingBarHeight + osrsOverlayChromeMetrics.pairedEdgeGap + 24).rounded()
        ) : 0
        let safeAreaTop = bakeChromeInsets ? Int(osrsOverlayChromeMetrics.topInset.rounded()) : 0
        let safeAreaBottom = bakeChromeInsets ? Int(osrsOverlayChromeMetrics.bottomInset.rounded()) : 0
        let readerPreferenceStyle = """
        <style id="osrs-article-reader-preferences">
            html:root {
                --osrs-article-user-text-scale: \(articleTextScaleLiteral);
                --osrs-article-chrome-clearance: \(chromeClearance)px;
                --osrs-article-bottom-chrome: \(bottomChrome)px;
                --osrs-article-safe-area-top: \(safeAreaTop)px;
                --osrs-article-safe-area-bottom: \(safeAreaBottom)px;
            }
        </style>
        """

        // Detect presence of GE price charts in the content and include widget script when needed
        let needsGECharts = cleanedBodyContent.contains("GEChartBox") ||
                           cleanedBodyContent.contains("GEdatachart") ||
                           cleanedBodyContent.contains("GEdataprices")

        if needsGECharts {
            print("\(logTag): Detected GE chart markers in content; will include Chart.js widget script.")
        }

        // Generate CSS links only if requested (disabled for WKUserScript injection)
        let cssLinks = stylesheetMarkup(
            inlineFirstPaintCss: inlineFirstPaintCss,
            includeAssetLinks: includeAssetLinks,
            customScheme: customScheme
        )

        // Generate MediaWiki scripts only if requested
        let mediawikiScripts: String
        if includeAssetLinks {
            mediawikiScripts = mediawikiArtifacts.map { assetPath in
                // Option B: Generate custom scheme URLs for WKURLSchemeHandler
                return "<script src=\"\(customScheme)://localhost/\(assetPath)\"></script>"
            }.joined(separator: "\n")
        } else {
            mediawikiScripts = "<!-- MediaWiki scripts injected via WKUserScript -->"
        }

        // Build the JS list, conditionally appending the GE charts widget
        var dynamicJsAssets = jsAssetPaths
        if needsGECharts {
            dynamicJsAssets.append(contentsOf: [
                "web/chart.umd.min.js",
                "web/ge_charts_init.js"
            ])
        }

        let jsScripts: String
        if includeAssetLinks {
            jsScripts = dynamicJsAssets.map { assetPath in
                let tag = "<script src=\"\(customScheme)://localhost/\(assetPath)\"></script>"
                if assetPath.hasSuffix("chart.umd.min.js") {
                    // Chart.js UMD prefers AMD when present. MediaWiki defines `define`, so
                    // window.Chart never appears unless we temporarily clear it.
                    return """
                    <script>window.__osrsAmdDefine=window.define;try{window.define=undefined;}catch(e){}</script>
                    \(tag)
                    <script>if(typeof window.__osrsAmdDefine!=='undefined'){window.define=window.__osrsAmdDefine;}</script>
                    """
                }
                return tag
            }.joined(separator: "\n")
        } else {
            jsScripts = "<!-- JS assets injected via WKUserScript -->"
        }

        let transformScripts: String
        if includeAssetLinks {
            transformScripts = articleTransformJsAssetPaths.map { assetPath in
                "<script src=\"\(customScheme)://localhost/\(assetPath)\"></script>"
            }.joined(separator: "\n")
        } else {
            transformScripts = "<!-- Transform scripts injected via WKUserScript -->"
        }

        // Generate smart MediaWiki variables
        let smartMediawikiVariables = generateMediaWikiVariables(
            title: cleanedTitle,
            bodyContent: cleanedBodyContent,
            canonicalTitle: canonicalTitle ?? title
        )

        // Create table collapse preference script
        let tableCollapseScript = createTableCollapseScript(collapseTablesEnabled: collapseTablesEnabled)

        // Preload the heading face used by h1.page-header so first paint
        // does not wait for a late @font-face swap that restyles the title.
        let fontPreloadLink: String
        if includeAssetLinks {
            fontPreloadLink = """
            <link rel="preload" href="\(customScheme)://localhost/fonts/alegreya_bold.ttf" as="font" type="font/ttf" crossorigin="anonymous">
            <link rel="preload" href="\(customScheme)://localhost/fonts/runescape_plain.ttf" as="font" type="font/ttf" crossorigin="anonymous">
            """
        } else {
            fontPreloadLink = "<!-- Font preload handled by injected CSS -->"
        }
        let articleFirstPaintStyle = osrsPageHtmlBuilder.articleFirstPaintStyle(
            chromeClearancePx: chromeClearance,
            safeAreaTopPx: safeAreaTop,
            safeAreaBottomPx: safeAreaBottom,
            bottomChromePx: bottomChrome,
            usesDarkTheme: theme is osrsDarkTheme
        )

        // Build final HTML document
        let finalHtml = """
        <!DOCTYPE html>
        <html class="\(themeClass) \(wrapClass)">
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
            <title>\(documentTitle)</title>
            \(articleFirstPaintStyle)
            <meta name="ResourceLoaderDynamicStyles" content="">
            \(fontPreloadLink)
            \(cssLinks)
            \(readerPreferenceStyle)
            \(createThemeUtilityScript())
            \(tableCollapseScript)
            \(smartMediawikiVariables)
        </head>
        <body class="\(themeClass) \(floorConvention.bodyClass) \(wrapClass)">
            \(finalBodyContent)
            \(createInternalArticleLinkNormalizationScript(customScheme: customScheme))
            \(transformScripts)
            \(mediawikiScripts)
            \(osrsTestEnvironment.osrsCalculatorSmokeSubmit ? "<script>window.__osrsCalculatorSmokeSubmit=true;</script>" : "")
            \(jsScripts)
        </body>
        </html>
        """

        let elapsedTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        print("\(logTag): buildFullHtmlDocument() took \(Int(elapsedTime))ms")
        print("LOAD-MINMAX html_ready buildMs=\(Int(elapsedTime)) htmlChars=\(finalHtml.count) inlineFirstPaintCss=\(inlineFirstPaintCss) includeAssetLinks=\(includeAssetLinks)")

        return finalHtml
    }

    private func stylesheetMarkup(
        inlineFirstPaintCss: Bool,
        includeAssetLinks: Bool,
        customScheme: String
    ) -> String {
        let hrefPrefix = "\(customScheme)://localhost/"
        if inlineFirstPaintCss {
            let useBundle = osrsLoadPerformancePrefs.useCriticalArticleBundle
            let criticalPart: String
            if useBundle {
                if let css = loadAssetText(criticalArticleBundleAsset) {
                    criticalPart = "<style data-osrs-inline-css=\"\(criticalArticleBundleAsset)\">\(css)</style>"
                } else {
                    criticalPart = criticalStyleSheetAssets.map { assetPath -> String in
                        if let css = loadAssetText(assetPath) {
                            return "<style data-osrs-inline-css=\"\(assetPath)\">\(css)</style>"
                        }
                        return osrsPageHtmlBuilder.blockingStylesheetLink(asset: assetPath, hrefPrefix: hrefPrefix)
                    }.joined(separator: "\n")
                }
            } else {
                criticalPart = criticalStyleSheetAssets.map { assetPath -> String in
                    if let css = loadAssetText(assetPath) {
                        return "<style data-osrs-inline-css=\"\(assetPath)\">\(css)</style>"
                    }
                    return osrsPageHtmlBuilder.blockingStylesheetLink(asset: assetPath, hrefPrefix: hrefPrefix)
                }.joined(separator: "\n")
            }
            let deferredPart = deferredStyleSheetAssets.map { assetPath -> String in
                if let css = loadAssetText(assetPath) {
                    return "<style data-osrs-inline-css=\"\(assetPath)\">\(css)</style>"
                }
                return osrsPageHtmlBuilder.blockingStylesheetLink(asset: assetPath, hrefPrefix: hrefPrefix)
            }.joined(separator: "\n")
            return criticalPart + "\n" + deferredPart + "\n" + osrsPageHtmlBuilder.articleCssLoaderScript
        }
        if includeAssetLinks {
            print("\(logTag): 🔍 UserDefaults WKURLSchemeHandler_Scheme = '\(UserDefaults.standard.string(forKey: "WKURLSchemeHandler_Scheme") ?? "nil")'")
            print("\(logTag): 🔍 Using scheme: '\(customScheme)'")
            let critical: String
            if osrsLoadPerformancePrefs.useCriticalArticleBundle {
                critical = osrsPageHtmlBuilder.blockingStylesheetLink(asset: criticalArticleBundleAsset, hrefPrefix: hrefPrefix)
            } else {
                critical = criticalStyleSheetAssets.map { assetPath in
                    osrsPageHtmlBuilder.blockingStylesheetLink(asset: assetPath, hrefPrefix: hrefPrefix)
                }.joined(separator: "\n")
            }
            let deferred = deferredStyleSheetAssets.map { assetPath in
                osrsPageHtmlBuilder.deferredStylesheetLinks(asset: assetPath, hrefPrefix: hrefPrefix)
            }.joined(separator: "\n")
            let markup = critical + "\n" + osrsPageHtmlBuilder.articleCssLoaderScript + "\n" + deferred
            print("\(logTag): Including CSS asset links with \(customScheme):// URLs for Option B")
            print("\(logTag): 📋 First CSS link: \(markup.components(separatedBy: "\n").first ?? "none")")
            return markup
        }
        print("\(logTag): Skipping CSS links - using WKUserScript injection")
        return "<!-- CSS assets injected via WKUserScript -->"
    }

    /// Shared head loader for deferred CSS activation and load-minmax timeline events.
    /// Keep in lockstep with PageHtmlBuilder.ARTICLE_CSS_LOADER_SCRIPT on Android.
    static let articleCssLoaderScript = """
    <script id="osrs-article-css-loader">
    (function() {
      window.osrsActivateDeferredStylesheet = function(link) {
        if (!link || link.getAttribute('data-osrs-css-activated') === '1') { return; }
        link.media = 'all';
        link.onload = null;
        link.setAttribute('data-osrs-css-activated', '1');
        var href = link.getAttribute('data-osrs-css-href') || link.getAttribute('href') || '';
        if (window.RenderTimeline && typeof window.RenderTimeline.log === 'function') {
          window.RenderTimeline.log('Event: DeferredCssApplied:' + href);
        }
      };
      function osrsActivatePendingDeferredStylesheets() {
        var nodes = document.querySelectorAll('link[data-osrs-css="deferred"]');
        for (var i = 0; i < nodes.length; i++) {
          if (nodes[i].media !== 'all') {
            window.osrsActivateDeferredStylesheet(nodes[i]);
          }
        }
      }
      document.addEventListener('DOMContentLoaded', function() {
        osrsActivatePendingDeferredStylesheets();
        if (window.RenderTimeline && typeof window.RenderTimeline.log === 'function') {
          window.RenderTimeline.log('Event: ParseReady');
        }
      });
      if (window.requestAnimationFrame) {
        requestAnimationFrame(function() {
          requestAnimationFrame(function() {
            if (window.RenderTimeline && typeof window.RenderTimeline.log === 'function') {
              window.RenderTimeline.log('Event: FirstPaint');
            }
          });
        });
      }
    })();
    </script>
    """

    static func blockingStylesheetLink(asset: String, hrefPrefix: String) -> String {
        "<link rel=\"stylesheet\" href=\"\(hrefPrefix)\(asset)\" data-osrs-css=\"critical\">"
    }

    static func deferredStylesheetLinks(asset: String, hrefPrefix: String) -> String {
        let href = "\(hrefPrefix)\(asset)"
        return """
        <link rel="preload" as="style" href="\(href)">
        <link rel="stylesheet" href="\(href)" media="print" onload="osrsActivateDeferredStylesheet(this)" data-osrs-css="deferred" data-osrs-css-href="\(asset)">
        """
    }

    static func articleFirstPaintStyle(
        chromeClearancePx: Int,
        safeAreaTopPx: Int = 0,
        safeAreaBottomPx: Int = 0,
        bottomChromePx: Int? = nil,
        usesDarkTheme: Bool = false
    ) -> String {
        let resolvedBottomChrome = bottomChromePx ?? chromeClearancePx
        let chromePadding: String
        if chromeClearancePx > 0 || safeAreaTopPx > 0 || safeAreaBottomPx > 0 || resolvedBottomChrome > 0 {
            chromePadding = """
                    html:root {
                        --osrs-article-safe-area-top: \(safeAreaTopPx)px;
                        --osrs-article-safe-area-bottom: \(safeAreaBottomPx)px;
                        --osrs-article-chrome-clearance: \(chromeClearancePx)px;
                        --osrs-article-bottom-chrome: \(resolvedBottomChrome)px;
                    }
                    html {
                        padding-top: calc(var(--osrs-article-safe-area-top) + var(--osrs-article-chrome-clearance)) !important;
                        padding-bottom: calc(var(--osrs-article-safe-area-bottom) + var(--osrs-article-bottom-chrome)) !important;
                    }
            """
        } else {
            chromePadding = ""
        }
        let bodyMain = usesDarkTheme ? "#28221d" : "#e2dbc8"
        let bodyLight = usesDarkTheme ? "#3e362f" : "#d8ccb4"
        let textColor = usesDarkTheme ? "#f4eaea" : "#000000"
        let lightFallback = usesDarkTheme ? """
                    html:not(.theme-osrs-dark),
                    html:not(.theme-osrs-dark) body {
                        --body-main: #e2dbc8;
                        --body-light: #d8ccb4;
                        --text-color: #000000;
                        background-color: #e2dbc8 !important;
                        color: #000000 !important;
                    }
        """ : ""
        return """
        <style id="osrs-article-first-paint">
        \(chromePadding)
                    h1.page-header {
                        font-family: 'Alegreya', 'Palatino', 'Georgia', serif !important;
                        font-weight: bold !important;
                        font-size: 1.8em !important;
                        line-height: 1.3 !important;
                        margin-top: 0 !important;
                        margin-bottom: 0.6em !important;
                        padding-bottom: 0.2em !important;
                        min-height: 0;
                        border-bottom: 1px solid var(--sidebar-color, currentColor);
                        box-sizing: border-box;
                    }
                    html, body, .mw-parser-output, .mw-content-text {
                        line-height: 1.35 !important;
                    }
                    html {
                        --body-main: \(bodyMain);
                        --body-light: \(bodyLight);
                        --text-color: \(textColor);
                    }
                    html, body {
                        background-color: \(bodyMain) !important;
                        color: \(textColor) !important;
                    }
                    \(lightFallback)
                    html.theme-osrs-dark {
                        --body-main: #28221d;
                        --body-light: #3e362f;
                        --text-color: #f4eaea;
                    }
                    html.theme-osrs-dark,
                    html.theme-osrs-dark body,
                    body.theme-osrs-dark {
                        background-color: #28221d !important;
                        color: #f4eaea !important;
                    }
                    table.infobox:not(.infobox-bonuses),
                    .infobox-switch:not(.infobox-bonuses),
                    .collapsible-primary-infobox {
                        max-width: 100%;
                        min-width: min(18.75rem, 100%);
                        box-sizing: border-box;
                    }
                    /* Bonuses column sizing lives in critical fixes.css.
                       Do not force table-layout:fixed here alone — that crushed
                       Attack/Defence/Other columns before polish applied. */
                    table.infobox-bonuses {
                        max-width: 100%;
                        min-width: 0;
                        box-sizing: border-box;
                    }
                    .mw-parser-output p,
                    .mw-parser-output > ul,
                    .mw-parser-output > ol,
                    .mw-parser-output > dl,
                    .mw-content-text p {
                        line-height: 1.35 !important;
                    }
        </style>
        """
    }

    /// Get a proper bundle URL for an asset (CSS/JS) that can be loaded by WKWebView
    private func getBundleAssetURL(for assetPath: String) -> URL? {
        // The assets are stored in the bundle under "Assets/" directory
        // e.g., "styles/themes.css" -> "Assets/styles/themes.css"
        let bundleAssetPath = "Assets/\(assetPath)"

        // Try to get the bundle URL for the asset
        if let path = Bundle.main.path(forResource: bundleAssetPath, ofType: nil) {
            return URL(fileURLWithPath: path)
        }

        // If that doesn't work, try without the Assets prefix (for backward compatibility)
        if let path = Bundle.main.path(forResource: assetPath, ofType: nil) {
            return URL(fileURLWithPath: path)
        }

        print("\(logTag): Could not find asset in bundle: \(assetPath)")
        return nil
    }

    /// Get a proper bundle URL for a font file that can be loaded by WKWebView
    private func getBundleFontURL(for fontName: String) -> URL? {
        // Fonts are stored in the bundle under "Font/" directory
        if let path = Bundle.main.path(forResource: fontName, ofType: nil, inDirectory: "Font") {
            return URL(fileURLWithPath: path)
        }

        print("\(logTag): Could not find font in bundle: \(fontName)")
        return nil
    }

    func loadAssetText(_ assetPath: String) -> String? {
        guard let url = getBundleAssetURL(for: assetPath) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private func extractMainTitle(_ title: String) -> String {
        // Use enhanced title cleaning that matches Android's functionality
        return osrsStringUtils.extractMainTitle(title)
    }


    /// Insert <wbr> after wiki namespace colons and subpage slashes when the
    /// next char is non-space so unbroken tokens wrap at those separators
    /// (Calculator:Sailing, Calculator:Construction/Materials).
    private func softWrapNamespaceTitle(_ title: String) -> String {
        let colon = applyTitleWbr(title, pattern: #"\b([A-Za-z][A-Za-z ]{0,40}:)(?=\S)"#)
        return applyTitleWbr(colon, pattern: #"(/)(?=[A-Za-z])"#)
    }

    private func applyTitleWbr(_ title: String, pattern: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return title }
        let range = NSRange(title.startIndex..<title.endIndex, in: title)
        return regex.stringByReplacingMatches(
            in: title,
            options: [],
            range: range,
            withTemplate: "$1<wbr>"
        )
    }

    private func removeDuplicatePageHeaders(_ htmlContent: String) -> String {
        do {
            // Use regex to remove h1 elements with class="page-header"
            let regex = try NSRegularExpression(pattern: "<h1\\s+class=\"page-header\"[^>]*>.*?</h1>", options: [.dotMatchesLineSeparators])
            let range = NSRange(location: 0, length: htmlContent.utf16.count)
            return regex.stringByReplacingMatches(in: htmlContent, options: [], range: range, withTemplate: "")
        } catch {
            print("\(logTag): Error removing duplicate page headers: \(error)")
            return htmlContent
        }
    }

    private func wrapArticleBodyContent(_ htmlContent: String) -> String {
        if htmlContent.contains("id=\"bodyContent\"") || htmlContent.contains("id='bodyContent'") {
            return htmlContent
        }
        return "<div id=\"bodyContent\" class=\"mw-body-content\">\(htmlContent)</div>"
    }

    private func normalizeInternalArticleLinks(in htmlContent: String, customScheme: String) -> String {
        do {
            let regex = try NSRegularExpression(pattern: #"href\s*=\s*(['"])([^'"]+)\1"#, options: [.caseInsensitive])
            let nsString = htmlContent as NSString
            let range = NSRange(location: 0, length: nsString.length)
            let matches = regex.matches(in: htmlContent, options: [], range: range)

            let normalizedHtml = NSMutableString(string: htmlContent)
            for match in matches.reversed() {
                guard match.numberOfRanges == 3 else {
                    continue
                }

                let quote = nsString.substring(with: match.range(at: 1))
                let href = nsString.substring(with: match.range(at: 2))
                guard let handoffURL = internalArticleHandoffURL(for: href, customScheme: customScheme) else {
                    continue
                }

                let escapedHandoffURL = escapeHtmlAttribute(handoffURL)
                let escapedHref = escapeHtmlAttribute(href)
                normalizedHtml.replaceCharacters(
                    in: match.range(at: 0),
                    with: "href=\(quote)\(escapedHref)\(quote) data-osrs-article-href=\(quote)\(escapedHandoffURL)\(quote)"
                )
            }

            return normalizedHtml as String
        } catch {
            print("\(logTag): Error normalizing internal article links: \(error)")
            return htmlContent
        }
    }

    private func internalArticleHandoffURL(for href: String, customScheme: String) -> String? {
        let baseURL = URL(string: "https://oldschool.runescape.wiki")!
        guard let url = URL(string: href, relativeTo: baseURL)?.absoluteURL,
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased() else {
            return nil
        }

        let path = url.path
        guard path.hasPrefix("/w/"),
              path.count > 3 else {
            return nil
        }

        let decodedTitle = String(path.dropFirst(3)).removingPercentEncoding ?? String(path.dropFirst(3))
        let lowercasedTitle = decodedTitle.lowercased()
        guard !lowercasedTitle.hasPrefix("file:"),
              !lowercasedTitle.hasPrefix("media:"),
              !lowercasedTitle.hasPrefix("special:") else {
            return nil
        }

        if scheme == customScheme && host == "localhost" {
            return url.absoluteString
        }

        let trustedWikiHosts: Set<String> = [
            "oldschool.runescape.wiki",
            "runescape.wiki"
        ]
        guard scheme == "https",
              trustedWikiHosts.contains(host) else {
            return nil
        }

        var handoffURL = "\(customScheme)://localhost\(path)"
        if let query = url.query,
           !query.isEmpty {
            handoffURL += "?\(query)"
        }
        if let fragment = url.fragment,
           !fragment.isEmpty {
            handoffURL += "#\(fragment)"
        }
        return handoffURL
    }

    private func escapeHtmlAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
