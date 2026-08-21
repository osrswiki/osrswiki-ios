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

    function loadCalcCore(attempt) {
        var tries = typeof attempt === 'number' ? attempt : 0;
        if (!document.querySelector('pre.jcConfig')) {
            return;
        }
        if (!window.mw || !mw.loader) {
            if (tries < 40) {
                setTimeout(function() { loadCalcCore(tries + 1); }, 50);
            }
            return;
        }
        var start = function() {
            patchAjax();
            if (typeof window.__osrsKickCalcCore === 'function') {
                window.__osrsKickCalcCore();
            }
            mw.loader.load('ext.gadget.calc-core');
        };
        function injectOOUIThenStart() {
            if (window.OO && OO.ui && typeof OO.ui.ButtonOptionWidget === 'function') {
                start();
                return;
            }
            if (document.querySelector('script[data-osrs-ooui-loader]')) {
                start();
                return;
            }
            var script = document.createElement('script');
            script.setAttribute('data-osrs-ooui-loader', '1');
            script.src = '/load.php?modules=ext.gadget.rsw-util%7Coojs-ui-core%7Coojs-ui-widgets%7Cmediawiki.widgets';
            script.onload = start;
            script.onerror = start;
            (document.head || document.documentElement).appendChild(script);
        }
        if (typeof mw.loader.using === 'function') {
            mw.loader.using(
                ['ext.gadget.rsw-util', 'oojs-ui-core', 'oojs-ui-widgets', 'mediawiki.widgets'],
                start
            );
            setTimeout(injectOOUIThenStart, 1200);
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
                if (waiting) {
                    start();
                }
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
        patchAjax();
        loadCalcCore();
        osrsWatchCalculatorResults();
        if (window.mw && mw.hook && mw.hook('rscalc.submit')) {
            mw.hook('rscalc.submit').add(osrsPublishCalculatorResult);
        }
        osrsArmSmokeSubmit();
    }

    function boot() {
        patchAjax();
        if (document.readyState === 'loading') {
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
            });
        }
    }

    boot();
})();
