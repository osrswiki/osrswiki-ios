/*
 * Wiki calculator runtime for app WebViews.
 *
 * The wiki gadget builds OOUI forms from pre.jcConfig and parses results via
 * /api.php. App articles load from a local asset origin, so this file:
 *   - leaves the wiki gadget in charge of controls (no custom form replacement)
 *   - wraps the template box + form for mobile layout
 *   - routes /api.php and /cors/ through the native calculator bridge
 */
(function() {
    'use strict';

    window.osrsWikiCalculatorApiUrl = window.osrsWikiCalculatorApiUrl || '/api.php';

    var osrsCalculatorRequestId = 0;
    var osrsCalculatorPending = {};

    window.osrsCalculatorApiComplete = function(payload) {
        if (!payload || payload.id == null) {
            return;
        }
        var finish = osrsCalculatorPending[payload.id];
        if (!finish) {
            return;
        }
        delete osrsCalculatorPending[payload.id];
        finish(payload.result || payload);
        setTimeout(osrsPublishCalculatorResult, 0);
        setTimeout(osrsPublishCalculatorResult, 150);
    };

    
    

    function osrsInstallCalculatorKeyboardGuards() {
        if (window.__osrsCalcKeyboardGuardsInstalled) return;
        window.__osrsCalcKeyboardGuardsInstalled = true;

        function focusedCalcInput() {
            var el = document.activeElement;
            if (!el) return null;
            if (el.closest && el.closest('.osrs-calculator-layout, .jcTable, .oo-ui-numberInputWidget, .jsCalc-field')) {
                return el;
            }
            return null;
        }

        function ensurePageVisible() {
            try {
                var root = document.documentElement;
                var body = document.body;
                if (root) {
                    root.style.visibility = 'visible';
                    root.style.opacity = '1';
                }
                if (body) {
                    body.style.visibility = 'visible';
                    body.style.opacity = '1';
                    body.style.minHeight = '100%';
                }
            } catch (e) {}
        }

        function scrollFocusedIntoView() {
            var el = focusedCalcInput();
            if (!el || !el.scrollIntoView) return;
            try {
                el.scrollIntoView({ block: 'center', inline: 'nearest', behavior: 'instant' });
            } catch (e) {
                try { el.scrollIntoView(true); } catch (e2) {}
            }
            ensurePageVisible();
        }

        document.addEventListener('focusin', function (ev) {
            var t = ev.target;
            if (!t || !t.closest) return;
            if (!t.closest('.osrs-calculator-layout, .jcTable, .oo-ui-numberInputWidget, .jsCalc-field')) return;
            ensurePageVisible();
            setTimeout(scrollFocusedIntoView, 50);
            setTimeout(scrollFocusedIntoView, 300);
        }, true);

        document.addEventListener('focusout', function () {
            setTimeout(ensurePageVisible, 50);
            setTimeout(ensurePageVisible, 350);
        }, true);

        if (window.visualViewport) {
            window.visualViewport.addEventListener('resize', function () {
                ensurePageVisible();
                scrollFocusedIntoView();
            });
            window.visualViewport.addEventListener('scroll', function () {
                ensurePageVisible();
            });
        }
    }

    function osrsStripJavascriptRequiredBanners(root) {
        // Only hide the wiki's JS-required messagebox itself. Matching every
        // `div`/`p` by textContent previously blanked #bodyContent and
        // .mw-parser-output because those ancestors also contain the banner.
        var scope = root || document;
        var nodes = scope.querySelectorAll(
            'table.messagebox, .messagebox, table.ambox, .ambox, table.mbox, .mbox, .js-required, .jcRequired'
        );
        nodes.forEach(function (node) {
            if (node.closest && node.closest('.osrs-calculator-layout, .osrs-calculator-panel, .jcTable')) {
                return;
            }
            var text = (node.textContent || '').replace(/\s+/g, ' ').trim();
            if (/dynamic calculator requires JavaScript/i.test(text) ||
                /this calculator requires JavaScript/i.test(text)) {
                node.style.display = 'none';
                node.setAttribute('data-osrs-calc-js-banner', 'stripped');
            }
        });
    }

    function osrsPromoteCalculatorDescription(layout, formHost) {
        if (!layout || !formHost) return;
        var desc = null;
        var prev = formHost.previousElementSibling;
        while (prev) {
            if (prev.matches && (prev.matches('p') || prev.matches('.calculator-description') || prev.matches('.mw-parser-output > p'))) {
                desc = prev;
                break;
            }
            if (prev.querySelector && prev.querySelector('pre.jcConfig, .jcTable, .oo-ui-widget')) break;
            prev = prev.previousElementSibling;
        }
        if (!desc) {
            var parent = formHost.parentElement;
            if (parent) {
                desc = parent.querySelector(':scope > p, :scope > .calculator-description');
            }
        }
        if (desc && !desc.classList.contains('osrs-calculator-description')) {
            desc.classList.add('osrs-calculator-description');
            layout.insertBefore(desc, layout.firstChild);
        }
    }

    function osrsApplyNumericKeyboards(root) {
        if (!root || !root.querySelectorAll) return;
        root.querySelectorAll('input[type="number"], .oo-ui-numberInputWidget input, .jsCalc-field-int input, .jsCalc-field-number input').forEach(function (input) {
            try {
                input.setAttribute('inputmode', 'decimal');
                input.setAttribute('enterkeyhint', 'done');
                if (!input.getAttribute('type') || input.getAttribute('type') === 'text') {
                    input.setAttribute('type', 'number');
                }
            } catch (e) {}
        });
    }

function parseCalculatorConfig(pre) {
        var config = { params: [] };
        pre.textContent.split('\n').forEach(function(line) {
            var equalsIndex = line.indexOf('=');
            if (equalsIndex < 0) return;
            var key = line.slice(0, equalsIndex).trim().toLowerCase();
            var value = line.slice(equalsIndex + 1).trim();
            if (!key) return;
            if (key === 'param') {
                var parts = value.split(/\s*\|\s*/);
                config.params.push({
                    id: parts[0] || '',
                    label: parts[1] || parts[0] || '',
                    initial: parts[2] || '',
                    type: parts[3] || 'string',
                    options: parts[4] || ''
                });
            } else {
                config[key] = value;
            }
        });
        return config;
    }

    function findCalculatorTemplateBox(pre) {
        var previous = pre.previousElementSibling;
        while (previous) {
            var text = previous.textContent || '';
            if (previous.matches('table.archivelist, .archivelist') && /templates used/i.test(text)) {
                return previous;
            }
            if (previous.matches('table, pre.jcConfig, h1, h2, h3')) {
                break;
            }
            previous = previous.previousElementSibling;
        }
        var nearby = document.querySelectorAll('table.archivelist, .archivelist');
        for (var i = 0; i < nearby.length; i++) {
            if (/templates used/i.test(nearby[i].textContent || '')) {
                return nearby[i];
            }
        }
        return null;
    }

    function findCalculatorResultNode(config, formHost) {
        var resultTarget = config.result ? document.getElementById(config.result) : null;
        if (!resultTarget && formHost && formHost.parentNode) {
            var sibling = formHost.nextElementSibling;
            while (sibling) {
                if (sibling.id && /Result$/.test(sibling.id)) {
                    resultTarget = sibling;
                    break;
                }
                sibling = sibling.nextElementSibling;
            }
        }
        return resultTarget;
    }

    function prepareCalculatorLayout(pre, formTarget, resultTarget) {
        var formHost = formTarget.closest('table') || formTarget;
        var scrollWrap = formHost && formHost.closest && formHost.closest(
            '.osrs-scroll-generated-surface, .osrs-article-scroll-region, .osrs-local-scroll-surface'
        );
        while (scrollWrap && scrollWrap.parentNode &&
                !scrollWrap.classList.contains('mw-parser-output') &&
                !scrollWrap.classList.contains('mw-body-content') &&
                scrollWrap.tagName !== 'BODY' &&
                scrollWrap.tagName !== 'HTML') {
            var wrapParent = scrollWrap.parentNode;
            while (scrollWrap.firstChild) {
                wrapParent.insertBefore(scrollWrap.firstChild, scrollWrap);
            }
            wrapParent.removeChild(scrollWrap);
            formHost = formTarget.closest('table') || formTarget;
            scrollWrap = formHost && formHost.closest && formHost.closest(
                '.osrs-scroll-generated-surface, .osrs-article-scroll-region, .osrs-local-scroll-surface'
            );
        }
        var existing = formHost.closest('.osrs-calculator-layout');
        if (existing) {
            if (resultTarget && !resultTarget.closest('.osrs-calculator-layout')) {
                existing.appendChild(resultTarget);
                resultTarget.classList.add('osrs-calculator-result');
            }
            return;
        }

        var templates = findCalculatorTemplateBox(pre);
        var layout = document.createElement('div');
        layout.className = 'osrs-calculator-layout';
        osrsInstallCalculatorKeyboardGuards();
        osrsStripJavascriptRequiredBanners(document);
        osrsPromoteCalculatorDescription(layout, formHost);
        osrsApplyNumericKeyboards(layout);
        formHost.parentNode.insertBefore(layout, templates || formHost);

        if (templates) {
            templates.classList.add('osrs-calculator-templates');
            layout.appendChild(templates);
        }
        layout.appendChild(formHost);
        if (resultTarget && resultTarget !== formHost) {
            layout.appendChild(resultTarget);
            resultTarget.classList.add('osrs-calculator-result');
        }
        pre.hidden = true;
        formHost.classList.add('osrs-calculator-panel');
        osrsReassertCalculatorThemeSheets();
    }

    function osrsReassertCalculatorThemeSheets() {
        if (!document.querySelector('.osrs-calculator-layout, pre.jcConfig')) {
            return;
        }
        var head = document.head || document.documentElement;
        var names = [
            'wiki-integration.css',
            'gadget_calc.css',
            'fixes.css',
            'ios-article-aesthetics.css',
            'android-article-aesthetics.css'
        ];
        names.forEach(function(name) {
            document.querySelectorAll('link[rel="stylesheet"]').forEach(function(node) {
                var href = node.getAttribute('href') || node.getAttribute('data-osrs-css-href') || '';
                if (href.indexOf(name) !== -1) {
                    head.appendChild(node);
                }
            });
        });
    }

    function shouldProxyCalculatorRequest(url) {
        return typeof url === 'string' && (
            url.indexOf('/api.php') !== -1 ||
            url.indexOf('/cors/') !== -1
        );
    }

    function resolveCalculatorBody(parsed) {
        if (!parsed || !parsed.ok) {
            return null;
        }
        var body = parsed.body;
        if (typeof body === 'string') {
            try {
                body = JSON.parse(body);
            } catch (ignore) {}
        }
        return body;
    }

    function sendNativeCalculatorRequest(payload, deferred) {
        function finish(parsed) {
            var body = resolveCalculatorBody(parsed);
            if (body != null) {
                deferred.resolve(body);
            } else {
                deferred.reject(null, (parsed && parsed.error) || 'calculator-api-failed');
            }
        }

        if (window.osrsCalculatorApi && typeof window.osrsCalculatorApi.request === 'function') {
            try {
                var raw = window.osrsCalculatorApi.request(JSON.stringify(payload));
                finish(JSON.parse(raw));
                return true;
            } catch (err) {
                return false;
            }
        }

        if (window.webkit && webkit.messageHandlers && webkit.messageHandlers.osrsCalculatorApi) {
            var id = String(++osrsCalculatorRequestId);
            osrsCalculatorPending[id] = finish;
            webkit.messageHandlers.osrsCalculatorApi.postMessage({
                id: id,
                method: payload.method,
                url: payload.url,
                data: payload.data
            });
            return true;
        }
        return false;
    }

    function patchAjax() {
        if (!window.jQuery) {
            setTimeout(patchAjax, 25);
            return;
        }
        if (jQuery.ajax.__osrsCalculatorPatched) {
            return;
        }
        var original = jQuery.ajax.bind(jQuery);
        jQuery.ajax = function(url, options) {
            var opts;
            if (typeof url === 'object') {
                opts = url;
            } else {
                opts = jQuery.extend({ url: url }, options || {});
            }
            var requestUrl = opts && opts.url ? String(opts.url) : '';
            if (shouldProxyCalculatorRequest(requestUrl)) {
                var deferred = jQuery.Deferred();
                var handled = sendNativeCalculatorRequest({
                    method: opts.method || opts.type || 'GET',
                    url: requestUrl,
                    data: opts.data || null
                }, deferred);
                if (handled) {
                    return deferred.promise();
                }
            }
            return original.apply(jQuery, arguments);
        };
        jQuery.ajax.__osrsCalculatorPatched = true;
    }

    function osrsHideCalculatorJsPlaceholder() {
        var live = !!document.querySelector(
            '.jcTable .jsCalc-field, .jcTable .oo-ui-buttonElement, .oo-ui-fieldsetLayout .oo-ui-widget, .jcTable input, .jcTable select, .jcTable button'
        );
        if (!live) {
            return;
        }
        document.documentElement.setAttribute('data-osrs-calc-live', '1');
        document.querySelectorAll('.messagebox, .ambox, .mbox, table.messagebox, table.ambox, table.mbox, .js-required, .jcRequired').forEach(function(node) {
            var text = node.textContent || '';
            if (/dynamic calculator requires JavaScript/i.test(text) ||
                /this calculator requires JavaScript/i.test(text)) {
                node.setAttribute('hidden', '');
                node.style.setProperty('display', 'none', 'important');
            }
        });
    }

    function osrsEnsureJQueryAlias() {
        if (window.jQuery && !window.$) {
            window.$ = window.jQuery;
        }
        if (window.$ && !window.jQuery) {
            window.jQuery = window.$;
        }
        return !!(window.$ && window.jQuery);
    }
    function loadCalcCore(attempt) {
        var tries = typeof attempt === 'number' ? attempt : 0;
        if (!document.querySelector('pre.jcConfig')) {
            return;
        }
        if (!window.mw || !mw.loader) {
            if (tries < 80) {
                setTimeout(function() { loadCalcCore(tries + 1); }, 50);
            }
            return;
        }
        osrsEnsureJQueryAlias();
        if (typeof window.__osrsKickCalcCore === 'function') {
            window.__osrsKickCalcCore();
        }
        var start = function() {
            osrsEnsureJQueryAlias();
            patchAjax();
            if (typeof window.__osrsKickCalcCore === 'function') {
                window.__osrsKickCalcCore();
            }
            mw.loader.load('ext.gadget.calc-core');
            if (typeof window.__osrsRebuildCalcs === 'function' &&
                !document.querySelector('.jcTable .jsCalc-field, .oo-ui-fieldsetLayout .oo-ui-widget')) {
                try { window.__osrsRebuildCalcs(); } catch (ignore) {}
            }
            osrsHideCalculatorJsPlaceholder();
            osrsReassertCalculatorThemeSheets();
        };
        function osrsCalcOOUIReady() {
            var cfg = '';
            try {
                var pre = document.querySelector('pre.jcConfig');
                cfg = pre && pre.textContent ? String(pre.textContent) : '';
            } catch (ignore) {}
            if (!(window.OO && OO.ui &&
                    typeof OO.ui.FieldsetLayout === 'function' &&
                    typeof OO.ui.ButtonInputWidget === 'function' &&
                    typeof OO.ui.ButtonOptionWidget === 'function' &&
                    typeof OO.ui.DropdownInputWidget === 'function' &&
                    typeof OO.ui.CheckboxInputWidget === 'function' &&
                    typeof OO.ui.HorizontalLayout === 'function')) {
                return false;
            }
            if (/toggleswitch/i.test(cfg) && typeof OO.ui.ToggleSwitchWidget !== 'function') {
                return false;
            }
            if (/\|\s*group\s*\|/i.test(cfg) && typeof OO.ui.HorizontalLayout !== 'function') {
                return false;
            }
            if (/\|\s*hs\s*\|/i.test(cfg) && typeof OO.ui.ActionFieldLayout !== 'function') {
                return false;
            }
            return true;
        }
        function osrsSanitizeResourceLoaderScript(code) {
            return String(code || '').split('window.OO=module.exports;').join(
                'window.OO=(typeof module!==\'undefined\'&&module.exports)?module.exports:window.OO;'
            );
        }
        function osrsLoadModuleScript(src, done) {
            osrsEnsureJQueryAlias();
            var finish = function() {
                osrsEnsureJQueryAlias();
                if (typeof window.__osrsKickCalcCore === 'function') {
                    window.__osrsKickCalcCore();
                }
                done();
            };
            var injectSrcTag = function() {
                var script = document.createElement('script');
                script.setAttribute('data-osrs-ooui-loader', '1');
                script.src = src;
                script.onload = finish;
                script.onerror = finish;
                (document.head || document.documentElement).appendChild(script);
            };
            if (typeof fetch !== 'function') {
                injectSrcTag();
                return;
            }
            fetch(src).then(function(response) {
                return response.text();
            }).then(function(code) {
                var script = document.createElement('script');
                script.setAttribute('data-osrs-ooui-loader', '1');
                script.text = osrsSanitizeResourceLoaderScript(code);
                (document.head || document.documentElement).appendChild(script);
                finish();
            }).catch(injectSrcTag);
        }
        function injectSequential(index) {
            if (osrsCalcOOUIReady()) {
                start();
                return;
            }
            var steps = [
                {
                    src: '/load.php?modules=jquery&only=scripts',
                    skip: function() { return !!(window.jQuery && jQuery.fn && typeof jQuery.proxy === 'function'); }
                },
                {
                    src: '/load.php?modules=oojs&only=scripts',
                    skip: function() { return !!(window.OO && typeof OO.initClass === 'function'); }
                },
                {
                    src: '/load.php?modules=oojs-ui-core&only=scripts',
                    skip: function() {
                        return !!(window.OO && OO.ui &&
                            typeof OO.ui.FieldsetLayout === 'function' &&
                            typeof OO.ui.ButtonInputWidget === 'function' &&
                            typeof OO.ui.CheckboxInputWidget === 'function' &&
                            typeof OO.ui.ToggleSwitchWidget === 'function' &&
                            typeof OO.ui.HorizontalLayout === 'function' &&
                            typeof OO.ui.DropdownInputWidget === 'function');
                    }
                },
                {
                    src: '/load.php?modules=oojs-ui-widgets&only=scripts',
                    skip: function() { return !!(window.OO && OO.ui && typeof OO.ui.ButtonOptionWidget === 'function'); }
                },
                {
                    src: '/load.php?modules=mediawiki.widgets',
                    skip: function() { return !!(window.mw && mw.widgets); }
                },
                {
                    src: '/load.php?modules=ext.gadget.rsw-util&only=scripts',
                    skip: function() { return !!(window.rs && typeof rs.hasLocalStorage === 'function'); }
                }
            ];
            if (index >= steps.length) {
                start();
                return;
            }
            if (steps[index].skip()) {
                injectSequential(index + 1);
                return;
            }
            osrsLoadModuleScript(steps[index].src, function() {
                setTimeout(function() { injectSequential(index + 1); }, 40);
            });
        }
        function injectOOUIThenStart(pollTries) {
            pollTries = typeof pollTries === 'number' ? pollTries : 0;
            if (osrsCalcOOUIReady()) {
                start();
                return;
            }
            if (document.querySelector('script[data-osrs-ooui-loader]')) {
                if (pollTries < 60) {
                    setTimeout(function() { injectOOUIThenStart(pollTries + 1); }, 100);
                    return;
                }
                start();
                return;
            }
            injectSequential(0);
        }
        if (typeof mw.loader.using === 'function') {
            mw.loader.using(
                ['ext.gadget.rsw-util', 'oojs-ui-core', 'oojs-ui-widgets', 'mediawiki.widgets'],
                function() { injectOOUIThenStart(0); }
            );
            setTimeout(function() {
                if (!osrsCalcOOUIReady()) {
                    injectOOUIThenStart(0);
                }
            }, 1500);
        } else {
            injectOOUIThenStart();
        }
        if (tries === 0) {
            setTimeout(function() {
                var waiting = Array.prototype.some.call(
                    document.querySelectorAll('[id$="Form"], #form'),
                    function(node) {
                        return /please wait for the form/i.test(node.textContent || '');
                    }
                );
                document.documentElement.setAttribute(
                    'data-osrs-calc-state',
                    [
                        'waiting=' + waiting,
                        'coreImpl=' + !!window.__osrsCalcCoreImplemented,
                        'coreRan=' + !!window.__osrsCalcCoreFactoryRan,
                        'jquery=' + !!(window.jQuery || window.$),
                        'OO=' + !!(window.OO && OO.ui),
                        'rs=' + !!(window.rs && rs.hasLocalStorage),
                        'bodyContent=' + !!document.getElementById('bodyContent')
                    ].join(' ')
                );
                if (waiting || !osrsCalcOOUIReady()) {
                    window.__osrsCalcCoreFactoryRan = false;
                    start();
                }
                osrsHideCalculatorJsPlaceholder();
                osrsReassertCalculatorThemeSheets();
            }, 2500);
        }
    }

    function osrsEnsureCalculatorStatus(resultNode) {
        var status = document.getElementById('osrs-calculator-status');
        if (!status) {
            status = document.createElement('p');
            status.id = 'osrs-calculator-status';
            status.setAttribute('role', 'status');
            status.setAttribute('aria-live', 'polite');
            (resultNode && resultNode.parentNode ? resultNode.parentNode : document.body).appendChild(status);
        }
        return status;
    }

    function osrsPublishCalculatorResult() {
        var node = document.querySelector('[id$="Result"]');
        var text = node ? String(node.textContent || '').replace(/\s+/g, ' ').trim() : '';
        var pageText = String((document.body && document.body.innerText) || '').replace(/\s+/g, ' ');
        var missing = pageText.match(/The player "[^"]+" does not exist[^.]*/i);
        if (missing && missing[0]) {
            text = missing[0];
        }
        if (!text) {
            return;
        }
        document.documentElement.setAttribute('data-osrs-calc-result', text.slice(0, 300));
        var status = osrsEnsureCalculatorStatus(node);
        status.textContent = text;
        osrsRevealCalculatorNode(status);
    }

    function osrsRevealCalculatorNode(node) {
        if (!node || typeof node.scrollIntoView !== 'function') {
            return;
        }
        node.scrollIntoView({ block: 'center', inline: 'nearest' });
    }

    function osrsWatchCalculatorResults() {
        if (window.__osrsCalculatorResultWatcher) {
            osrsPublishCalculatorResult();
            return;
        }
        window.__osrsCalculatorResultWatcher = true;
        var observer = new MutationObserver(function() {
            osrsPublishCalculatorResult();
        });
        document.querySelectorAll('[id$="Result"], [id$="Form"], #bodyContent').forEach(function(node) {
            observer.observe(node, { childList: true, subtree: true, characterData: true });
        });
        osrsPublishCalculatorResult();
    }

        function osrsClickCalculatorSubmit() {
        var nodes = document.querySelectorAll('.jcSubmit');
        for (var i = 0; i < nodes.length; i++) {
            var widget = window.jQuery ? jQuery(nodes[i]).data('oouiButton') : null;
            if (widget && typeof widget.emit === 'function') {
                widget.emit('click');
            } else if (nodes[i].click) {
                nodes[i].click();
            }
        }
        if (nodes.length > 0) {
            setTimeout(osrsPublishCalculatorResult, 400);
        }
        return nodes.length > 0;
    }

    function osrsArmSmokeSubmit() {
        if (!window.__osrsCalculatorSmokeSubmit || window.__osrsCalculatorSmokeArmed) {
            return;
        }
        window.__osrsCalculatorSmokeArmed = true;
        var poll = function(attempt) {
            if (osrsClickCalculatorSubmit()) {
                return;
            }
            if (attempt < 80) {
                setTimeout(function() { poll(attempt + 1); }, 250);
            }
        };
        poll(0);
        if (window.mw && mw.hook && mw.hook('rscalc.setupComplete')) {
            mw.hook('rscalc.setupComplete').add(function() {
                setTimeout(osrsClickCalculatorSubmit, 250);
            });
        }
    }

    function initialize() {
        document.querySelectorAll('pre.jcConfig').forEach(function(pre) {
            var config = parseCalculatorConfig(pre);
            var formTarget = config.form && document.getElementById(config.form);
            if (formTarget) {
                prepareCalculatorLayout(pre, formTarget, findCalculatorResultNode(config, formTarget));
            }
        });
        osrsReassertCalculatorThemeSheets();
        patchAjax();
        loadCalcCore();
        osrsWatchCalculatorResults();
        if (window.mw && mw.hook && mw.hook('rscalc.submit')) {
            mw.hook('rscalc.submit').add(osrsPublishCalculatorResult);
        }
        osrsArmSmokeSubmit();
        (function osrsPollCalculatorLive(attempt) {
            osrsHideCalculatorJsPlaceholder();
            if (!document.documentElement.getAttribute('data-osrs-calc-live') && attempt < 24) {
                setTimeout(function() { osrsPollCalculatorLive(attempt + 1); }, 250);
            }
        })(0);
    }

    function boot() {
        patchAjax();
        if (document.readyState === 'loading') {
            osrsInstallCalculatorKeyboardGuards();
    document.addEventListener('DOMContentLoaded', initialize);
        } else {
            initialize();
        }
        if (window.mw && mw.hook && mw.hook('wikipage.content')) {
            mw.hook('wikipage.content').add(function() {
                patchAjax();
                initialize();
            });
        }
        if (window.mw && mw.hook && mw.hook('rscalc.setupComplete')) {
            mw.hook('rscalc.setupComplete').add(function() {
                patchAjax();
                osrsHideCalculatorJsPlaceholder();
            });
        }
    }

    boot();
})();
