(function () {
    'use strict';
    if (window.__osrsFirstViewportAssets) {
        return;
    }
    window.__osrsFirstViewportAssets = true;
    window.__osrsFirstViewPainted = false;

    var reportedComplete = false;

    function srcsetUrls(value) {
        if (!value) {
            return [];
        }
        var withoutData = String(value).replace(/data:[^\s,]+(?:\s+\d+(?:\.\d+)?[wx])?/gi, '');
        return withoutData.split(',').map(function (part) {
            var token = part.trim().split(/\s+/)[0];
            return token || '';
        }).filter(Boolean);
    }

    function elementUrls(el) {
        var urls = [];
        ['src', 'data-src', 'data-osrs-deferred-src', 'data-original', 'data-lazy-src'].forEach(function (name) {
            var value = el.getAttribute(name);
            if (value) {
                urls.push(value);
            }
        });
        ['srcset', 'data-srcset', 'data-osrs-deferred-srcset', 'data-lazy-srcset'].forEach(function (name) {
            urls = urls.concat(srcsetUrls(el.getAttribute(name)));
        });
        if (el.tagName === 'VIDEO') {
            var poster = el.getAttribute('poster');
            if (poster) {
                urls.push(poster);
            }
        }
        return urls;
    }

    function unique(urls) {
        var seen = Object.create(null);
        var out = [];
        urls.forEach(function (url) {
            if (!url || seen[url]) {
                return;
            }
            seen[url] = true;
            out.push(url);
        });
        return out;
    }

    function addFrom(node, urls) {
        if (!node || !node.querySelectorAll) {
            return;
        }
        node.querySelectorAll('img, picture > source, video[poster]').forEach(function (el) {
            Array.prototype.push.apply(urls, elementUrls(el));
        });
    }

    function collectSwitcherSlot(root) {
        var urls = [];
        var infobox = root.querySelector(
            '.infobox-switch, .collapsible-primary-infobox, .switch-infobox, table.infobox, .infobox'
        );
        if (infobox) {
            addFrom(infobox, urls);
            var resourceClass = infobox.getAttribute('data-resource-class');
            if (resourceClass) {
                try {
                    addFrom(root.querySelector(resourceClass), urls);
                } catch (ignore) {}
            }
            addFrom(root.querySelector('.infobox-switch-resources'), urls);
            root.querySelectorAll('[class*="infobox-resources-"]').forEach(function (node) {
                addFrom(node, urls);
            });
            root.querySelectorAll('[data-attr-param] [data-attr-index]').forEach(function (node) {
                addFrom(node, urls);
            });
        }
        root.querySelectorAll('.switch-infobox .item').forEach(function (node) {
            addFrom(node, urls);
        });
        root.querySelectorAll('.infobox-bonuses-image.render-m, .infobox-bonuses-image.render-f').forEach(function (el) {
            Array.prototype.push.apply(urls, elementUrls(el));
            addFrom(el, urls);
        });
        return urls;
    }

    function collectLeadBeforeHeading(root) {
        var urls = [];
        var nodes = root.querySelectorAll('img, picture > source, video[poster], h2, .mw-heading');
        for (var i = 0; i < nodes.length; i++) {
            var node = nodes[i];
            if (node.matches && (node.matches('h2') || node.matches('.mw-heading'))) {
                break;
            }
            if (node.matches && (node.matches('img, picture > source, video[poster]'))) {
                Array.prototype.push.apply(urls, elementUrls(node));
            }
        }
        return urls;
    }

    function collectIntersecting() {
        var urls = [];
        var viewportHeight = window.innerHeight || 0;
        document.querySelectorAll('img, picture > source, video[poster]').forEach(function (el) {
            var rect = el.getBoundingClientRect();
            if (rect.bottom <= 0 || rect.top >= viewportHeight) {
                return;
            }
            if ((rect.width + rect.height) <= 0) {
                return;
            }
            Array.prototype.push.apply(urls, elementUrls(el));
        });
        return urls;
    }

    function slotUrls() {
        return unique(collectSwitcherSlot(document).concat(collectLeadBeforeHeading(document)));
    }

    function notify(urls) {
        if (!urls.length) {
            return;
        }
        try {
            if (window.OsrsWikiBridge && typeof window.OsrsWikiBridge.warmNearViewportAssets === 'function') {
                window.OsrsWikiBridge.warmNearViewportAssets(JSON.stringify(urls));
            }
        } catch (ignore) {}
        try {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.osrsLiveAssetWarm) {
                window.webkit.messageHandlers.osrsLiveAssetWarm.postMessage({ urls: urls });
            }
        } catch (ignore) {}
    }

    function postComplete() {
        try {
            if (window.OsrsWikiBridge && typeof window.OsrsWikiBridge.firstViewComplete === 'function') {
                window.OsrsWikiBridge.firstViewComplete();
            }
        } catch (ignore) {}
        try {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.osrsFirstViewComplete) {
                window.webkit.messageHandlers.osrsFirstViewComplete.postMessage({ complete: true });
            }
        } catch (ignore) {}
        console.log('osrsFirstViewComplete');
    }

    function reportComplete() {
        window.__osrsFirstViewPainted = true;
        if (reportedComplete) {
            return;
        }
        reportedComplete = true;
        postComplete();
    }

    function elementHasDecodedUrl(el, url) {
        if (!el || el.tagName !== 'IMG' || !url) {
            return false;
        }
        if (!(el.complete && el.naturalWidth > 0)) {
            return false;
        }
        var candidates = [el.currentSrc, el.src];
        ['src', 'data-src', 'data-osrs-deferred-src', 'data-original', 'data-lazy-src'].forEach(function (name) {
            candidates.push(el.getAttribute(name));
        });
        for (var i = 0; i < candidates.length; i++) {
            if (candidates[i] && candidates[i] === url) {
                return true;
            }
        }
        return false;
    }

    function domImageAlreadyDecoded(url) {
        if (!url) {
            return true;
        }
        var nodes = document.querySelectorAll('img');
        for (var i = 0; i < nodes.length; i++) {
            if (elementHasDecodedUrl(nodes[i], url)) {
                return true;
            }
        }
        return false;
    }

    function decodeUrl(url) {
        if (domImageAlreadyDecoded(url)) {
            return Promise.resolve();
        }
        return new Promise(function (resolve) {
            var img = new Image();
            var settled = false;
            function finish() {
                if (settled) {
                    return;
                }
                settled = true;
                resolve();
            }
            img.onload = finish;
            img.onerror = finish;
            img.src = url;
            if (typeof img.decode === 'function') {
                img.decode().then(finish, finish);
            }
        });
    }

    function watchComplete() {
        var urls = unique(slotUrls().concat(collectIntersecting()));
        var timeout = setTimeout(reportComplete, 15000);
        var wait = urls.length ? Promise.all(urls.map(decodeUrl)) : Promise.resolve();
        wait.then(function () {
            clearTimeout(timeout);
            reportComplete();
        });
    }

    window.osrsCollectFirstViewportUrls = function () {
        return unique(slotUrls().concat(collectIntersecting()));
    };

    window.osrsNotifyFirstViewComplete = function () {
        window.__osrsFirstViewPainted = true;
        postComplete();
    };

    window.osrsWatchFirstViewComplete = watchComplete;

    function sampleLayoutStability() {
        var target = document.querySelector(
            '.infobox-switch, .collapsible-primary-infobox, table.infobox, .infobox'
        );
        window.__osrsLayoutStability = window.__osrsLayoutStability || {
            samples: [],
            maxTopDelta: 0,
            maxHeightDelta: 0
        };
        if (!target || typeof target.getBoundingClientRect !== 'function') {
            return;
        }
        var samples = [];
        var frames = 0;
        function tick() {
            var rect = target.getBoundingClientRect();
            samples.push({
                t: performance.now(),
                top: rect.top,
                height: rect.height,
                width: rect.width
            });
            frames += 1;
            if (frames < 32) {
                requestAnimationFrame(tick);
                return;
            }
            var tops = samples.map(function (sample) { return sample.top; });
            var heights = samples.map(function (sample) { return sample.height; });
            window.__osrsLayoutStability = {
                samples: samples,
                maxTopDelta: Math.max.apply(null, tops) - Math.min.apply(null, tops),
                maxHeightDelta: Math.max.apply(null, heights) - Math.min.apply(null, heights)
            };
        }
        requestAnimationFrame(tick);
    }

    function start() {
        notify(unique(collectIntersecting()));
        watchComplete();
        sampleLayoutStability();
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', start);
    } else {
        start();
    }
})();
