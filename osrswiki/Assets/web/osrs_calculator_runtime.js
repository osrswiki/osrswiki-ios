/*
 * Wiki calculator runtime for app WebViews.
 *
 * The wiki gadget builds OOUI forms from pre.jcConfig and parses results via
 * /api.php. App articles load from a local asset origin, so this file:
 *   - leaves the wiki gadget in charge of controls unless native calc slot-replaces the form
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

    
    

    function osrsEnsureCalculatorPageVisible() {
        try {
            var root = document.documentElement;
            var body = document.body;
            var content = document.getElementById('bodyContent') ||
                document.querySelector('.mw-parser-output') ||
                document.querySelector('.osrs-calculator-layout');
            [root, body, content].forEach(function (node) {
                if (!node || !node.style) return;
                node.style.visibility = 'visible';
                node.style.opacity = '1';
                node.style.display = '';
                if (node === body) {
                    node.style.minHeight = '100%';
                    node.style.transform = 'none';
                }
            });
            if (root) {
                root.removeAttribute('hidden');
            }
            if (body) {
                body.removeAttribute('hidden');
            }
            var scroll = document.scrollingElement || body;
            if (scroll) {
                var maxY = Math.max(0, scroll.scrollHeight - (window.innerHeight || 0));
                if (scroll.scrollTop < 0 || scroll.scrollTop > maxY + 64) {
                    scroll.scrollTop = Math.min(Math.max(scroll.scrollTop, 0), maxY);
                }
            }
        } catch (e) {}
    }
    window.osrsEnsureCalculatorPageVisible = osrsEnsureCalculatorPageVisible;

    function osrsNativeCalcDocumentTop(el) {
        if (!el) return 0;
        var top = 0;
        var node = el;
        while (node) {
            top += node.offsetTop || 0;
            node = node.offsetParent;
        }
        return top;
    }

    function osrsNativeCalcHideGadget(node) {
        if (!node) return;
        node.setAttribute('data-osrs-native-calc-hidden', '1');
        node.setAttribute('aria-hidden', 'true');
        node.style.setProperty('display', 'none', 'important');
    }

    window.osrsInstallNativeCalcSlot = function (opts) {
        opts = opts || {};
        var formId = opts.formId || '';
        var resultId = opts.resultId || '';
        var height = Math.max(1, parseInt(opts.height, 10) || 420);
        var form = (formId && document.getElementById(formId)) ||
            document.querySelector('.jcTable, [id$="Calc"], [id$="Form"]');
        var config = document.querySelector('pre.jcConfig');
        var layout = document.querySelector('.osrs-calculator-layout');
        if (!document.getElementById('osrs-native-calc-slot') &&
            document.querySelectorAll('select').length === 0 &&
            !form && !config && !layout) {
            return JSON.stringify({ missing: true, waiting: true, selectCount: 0 });
        }
        var result = (resultId && document.getElementById(resultId)) ||
            document.querySelector('.osrs-calculator-result, [id$="Results"]');
        var panel = (layout && layout.querySelector('.osrs-calculator-panel, .oo-ui-panelLayout-framed')) ||
            document.querySelector('.osrs-calculator-panel, .oo-ui-panelLayout-framed');

        if (document.documentElement) {
            document.documentElement.classList.add('osrs-native-calc-slot-active');
        }
        var style = document.getElementById('osrs-native-calc-slot-style');
        if (!style) {
            style = document.createElement('style');
            style.id = 'osrs-native-calc-slot-style';
            (document.head || document.documentElement).appendChild(style);
        }
        style.textContent = [
            'html.osrs-native-calc-slot-active pre.jcConfig,',
            'html.osrs-native-calc-slot-active .jcTable,',
            'html.osrs-native-calc-slot-active .jcSubmit,',
            'html.osrs-native-calc-slot-active .jsCalc-field,',
            'html.osrs-native-calc-slot-active .oo-ui-fieldsetLayout,',
            'html.osrs-native-calc-slot-active .oo-ui-panelLayout-framed,',
            'html.osrs-native-calc-slot-active .oo-ui-textInputWidget,',
            'html.osrs-native-calc-slot-active .osrs-calculator-layout .oo-ui-widget,',
            'html.osrs-native-calc-slot-active .osrs-calculator-layout input,',
            'html.osrs-native-calc-slot-active .osrs-calculator-layout select,',
            'html.osrs-native-calc-slot-active .osrs-calculator-layout button,',
            'html.osrs-native-calc-slot-active select,',
            'html.osrs-native-calc-slot-active noscript {',
            'display:none!important;visibility:hidden!important;height:0!important;min-height:0!important;padding:0!important;margin:0!important;border:0!important;overflow:hidden!important;pointer-events:none!important;',
            '}',
            'html.osrs-native-calc-slot-active .osrs-calculator-panel {',
            'display:none!important;visibility:hidden!important;height:0!important;min-height:0!important;padding:0!important;margin:0!important;border:0!important;background:transparent!important;box-shadow:none!important;',
            '}',
            'html.osrs-native-calc-slot-active #osrs-native-calc-slot {',
            'display:block!important;background:transparent!important;border:0!important;box-shadow:none!important;outline:none!important;padding:0!important;margin:0!important;',
            '}',
            'html.osrs-native-calc-slot-active .collapsible-calculator {',
            'display:block!important;max-width:100%!important;box-sizing:border-box!important;background:transparent!important;background-color:transparent!important;box-shadow:none!important;border:0!important;',
            '}',
            'html.osrs-native-calc-slot-active .collapsible-calculator:not(.collapsed) > .collapsible-content,',
            'html.osrs-native-calc-slot-active .collapsible-calculator:not(.collapsed) > .collapsible-content > .osrs-disclosure-body {',
            'overflow-x:auto!important;-webkit-overflow-scrolling:touch!important;',
            '}',
            'html.osrs-native-calc-slot-active .collapsible-calculator.collapsed > .collapsible-content {',
            'display:block!important;height:0!important;max-height:0!important;min-height:0!important;overflow:hidden!important;padding:0!important;margin:0!important;border:0!important;',
            '}',
            'html.osrs-native-calc-slot-active .osrs-calculator-result,',
            'html.osrs-native-calc-slot-active [id$="Results"] {',
            'display:block!important;visibility:visible!important;height:auto!important;min-height:0!important;overflow:visible!important;',
            '}'
        ].join('');

        function hideUnlessResult(node) {
            if (!node || node.id === 'osrs-native-calc-slot') return;
            if (result && (node === result || (result.contains && result.contains(node)))) return;
            osrsNativeCalcHideGadget(node);
        }
        if (panel && result && panel.contains(result) && panel.parentNode) {
            panel.parentNode.insertBefore(result, panel.nextSibling);
        }
        hideUnlessResult(config);
        hideUnlessResult(form);
        hideUnlessResult(panel);
        var hideRoot = layout || document;
        hideRoot.querySelectorAll(
            '.jcTable, .jcSubmit, .oo-ui-fieldsetLayout, pre.jcConfig, .jsCalc-field, .oo-ui-textInputWidget, .osrs-calculator-panel, .oo-ui-panelLayout-framed'
        ).forEach(hideUnlessResult);
        function neutralizeGadgetSelect(node) {
            if (!node || (result && result.contains && result.contains(node))) return;
            try {
                node.disabled = true;
                node.setAttribute('disabled', 'disabled');
                node.setAttribute('aria-hidden', 'true');
                node.style.setProperty('pointer-events', 'none', 'important');
                node.style.setProperty('display', 'none', 'important');
                if (node.parentNode) node.parentNode.removeChild(node);
            } catch (err) {}
        }
        hideRoot.querySelectorAll('select').forEach(neutralizeGadgetSelect);
        hideRoot.querySelectorAll(
            'select, .oo-ui-dropdownWidget, .oo-ui-selectWidget, .oo-ui-comboBoxInputWidget'
        ).forEach(neutralizeGadgetSelect);
        if (!window.__osrsNativeCalcSelectGuard) {
            window.__osrsNativeCalcSelectGuard = new MutationObserver(function () {
                if (!document.documentElement ||
                    !document.documentElement.classList.contains('osrs-native-calc-slot-active')) {
                    return;
                }
                document.querySelectorAll(
                    'select, .oo-ui-dropdownWidget, .oo-ui-selectWidget, .oo-ui-comboBoxInputWidget'
                ).forEach(neutralizeGadgetSelect);
            });
            window.__osrsNativeCalcSelectGuard.observe(document.documentElement, {
                childList: true,
                subtree: true
            });
            document.addEventListener('click', function (event) {
                if (!document.documentElement ||
                    !document.documentElement.classList.contains('osrs-native-calc-slot-active')) {
                    return;
                }
                var target = event.target;
                if (target && target.tagName === 'SELECT') {
                    event.preventDefault();
                    event.stopPropagation();
                }
            }, true);
        }

        var slot = document.getElementById('osrs-native-calc-slot');
        if (!slot) {
            slot = document.createElement('div');
            slot.id = 'osrs-native-calc-slot';
            slot.setAttribute('data-osrs-native-calc-slot', '1');
            slot.setAttribute('aria-hidden', 'true');
            var anchor = panel || form || config;
            var parent = (anchor && anchor.parentNode) || layout ||
                document.querySelector('.mw-parser-output') ||
                document.body;
            if (anchor && anchor.parentNode) {
                anchor.parentNode.insertBefore(slot, anchor);
            } else if (result && result.parentNode) {
                result.parentNode.insertBefore(slot, result);
            } else if (parent) {
                parent.appendChild(slot);
            }
        }
        slot.style.display = 'block';
        slot.style.width = '100%';
        slot.style.minWidth = (document.documentElement.clientWidth || window.innerWidth || 360) + 'px';
        slot.style.boxSizing = 'border-box';
        slot.style.minHeight = height + 'px';
        slot.style.background = 'transparent';
        slot.style.backgroundColor = 'transparent';
        slot.style.border = '0';
        slot.style.outline = 'none';
        slot.style.boxShadow = 'none';
        slot.style.padding = '0';
        slot.style.margin = '0';
        var box = osrsWrapNativeCalcCalculatorBox(slot, height);
        if (window.osrsEnsureCalculatorPageVisible) {
            window.osrsEnsureCalculatorPageVisible();
        }
        return JSON.stringify({
            top: osrsNativeCalcDocumentTop(slot),
            width: slot.offsetWidth || 0,
            height: slot.offsetHeight || height,
            collapsed: !!(box && box.classList.contains('collapsed')),
            category: 'calculator'
        });
    };

    function osrsWrapNativeCalcCalculatorBox(slot, height) {
        if (!slot || !slot.parentNode) return null;
        var container = slot.closest('.collapsible-calculator');
        if (!container) {
            container = document.createElement('div');
            container.className = 'collapsible-container collapsible-calculator primary-collapsible';
            container.setAttribute('data-osrs-disclosure-kind', 'calculator');
            container.dataset.osrsDisclosureKind = 'calculator';
            container.dataset.collapseLabelKind = 'semantic';
            var content = document.createElement('div');
            content.className = 'collapsible-content';
            var body = document.createElement('div');
            body.className = 'osrs-disclosure-body';
            slot.parentNode.insertBefore(container, slot);
            container.appendChild(content);
            content.appendChild(body);
            body.appendChild(slot);
        }
        window.osrsNativeCalcSetCollapsed = function (collapsed) {
            var box = document.querySelector('.collapsible-calculator');
            var nativeSlot = document.getElementById('osrs-native-calc-slot');
            if (!box) return 0;
            if (collapsed) {
                box.classList.add('collapsed');
                box.setAttribute('aria-expanded', 'false');
                if (nativeSlot) nativeSlot.style.minHeight = '0px';
            } else {
                box.classList.remove('collapsed');
                box.setAttribute('aria-expanded', 'true');
                if (nativeSlot) nativeSlot.style.minHeight = Math.max(1, parseInt(height, 10) || 1) + 'px';
            }
            return osrsNativeCalcDocumentTop(nativeSlot);
        };
        window.osrsNativeCalcIsCollapsed = function () {
            var box = document.querySelector('.collapsible-calculator');
            return !!(box && box.classList.contains('collapsed'));
        };
        return container;
    }

    window.osrsNativeCalcSetSlotHeight = function (height) {
        var slot = document.getElementById('osrs-native-calc-slot');
        if (!slot) return;
        slot.style.minHeight = Math.max(1, parseInt(height, 10) || 1) + 'px';
        return osrsNativeCalcDocumentTop(slot);
    };

    window.osrsNativeCalcSetResult = function (resultId, html) {
        var result = (resultId && document.getElementById(resultId)) ||
            document.querySelector('.osrs-calculator-result, [id$="Results"]');
        if (!result) {
            result = document.createElement('div');
            result.id = resultId || 'osrs-native-calc-result';
            result.className = 'osrs-calculator-result';
            var slot = document.getElementById('osrs-native-calc-slot');
            if (slot && slot.parentNode) {
                if (slot.nextSibling) {
                    slot.parentNode.insertBefore(result, slot.nextSibling);
                } else {
                    slot.parentNode.appendChild(result);
                }
            } else {
                var output = document.querySelector('.mw-parser-output') || document.body;
                output.appendChild(result);
            }
        }
        result.removeAttribute('data-osrs-native-calc-hidden');
        result.removeAttribute('aria-hidden');
        result.style.removeProperty('display');
        result.innerHTML = html || '';
        if (window.osrsEnsureCalculatorPageVisible) {
            window.osrsEnsureCalculatorPageVisible();
        }
    };

    window.osrsUninstallNativeCalcSlot = function () {
        if (document.documentElement) {
            document.documentElement.classList.remove('osrs-native-calc-slot-active');
        }
        var style = document.getElementById('osrs-native-calc-slot-style');
        if (style && style.parentNode) {
            style.parentNode.removeChild(style);
        }
        document.querySelectorAll('[data-osrs-native-calc-hidden]').forEach(function (node) {
            node.style.removeProperty('display');
            node.removeAttribute('data-osrs-native-calc-hidden');
            node.removeAttribute('aria-hidden');
        });
        var slot = document.getElementById('osrs-native-calc-slot');
        var wrap = slot && slot.closest && slot.closest('.collapsible-calculator');
        if (wrap && wrap.parentNode) {
            wrap.parentNode.removeChild(wrap);
        } else if (slot && slot.parentNode) {
            slot.parentNode.removeChild(slot);
        }
        delete window.osrsNativeCalcSetCollapsed;
        delete window.osrsNativeCalcIsCollapsed;
    };

    function osrsInstallCalculatorKeyboardGuards() {
        if (window.__osrsCalcKeyboardGuardsInstalled) return;
        window.__osrsCalcKeyboardGuardsInstalled = true;
        osrsInstallCalculatorDropdownIntercept();
        osrsInstallCalculatorThemeSkin();
        osrsCollapseTemplatesUsed(document);
        setTimeout(function(){ osrsCollapseTemplatesUsed(document); }, 500);
        setTimeout(function(){ osrsCollapseTemplatesUsed(document); }, 2000);

        function focusedCalcInput() {
            var el = document.activeElement;
            if (!el) return null;
            if (el.closest && el.closest('.osrs-calculator-layout, .jcTable, .oo-ui-numberInputWidget, .jsCalc-field')) {
                return el;
            }
            return null;
        }

        function keyboardOpen() {
            if (!window.visualViewport) return false;
            var inner = window.innerHeight || document.documentElement.clientHeight || 0;
            return inner > 0 && window.visualViewport.height < inner * 0.82;
        }

        function scrollFocusedIntoView() {
            if (keyboardOpen()) {
                osrsEnsureCalculatorPageVisible();
                return;
            }
            var el = focusedCalcInput();
            if (!el || !el.scrollIntoView) return;
            try {
                el.scrollIntoView({ block: 'nearest', inline: 'nearest', behavior: 'instant' });
            } catch (e) {
                try { el.scrollIntoView(false); } catch (e2) {}
            }
            osrsEnsureCalculatorPageVisible();
        }

        document.addEventListener('focusin', function (ev) {
            var t = ev.target;
            if (!t || !t.closest) return;
            var layout = t.closest('.osrs-calculator-layout, .jcTable');
            if (!layout && !t.closest('.oo-ui-numberInputWidget, .jsCalc-field')) return;
            if (layout) {
                osrsApplyNumericKeyboards(layout);
            } else if (t.tagName === 'INPUT') {
                try {
                    if (t.type === 'number' || (t.closest && t.closest('.oo-ui-numberInputWidget'))) {
                        if (!t.getAttribute('inputmode')) t.setAttribute('inputmode', 'decimal');
                    }
                } catch (e) {}
            }
            osrsEnsureCalculatorPageVisible();
        }, true);

        document.addEventListener('focusout', function () {
            setTimeout(osrsEnsureCalculatorPageVisible, 50);
            setTimeout(osrsEnsureCalculatorPageVisible, 350);
        }, true);

        if (window.visualViewport) {
            var lastViewportHeight = window.visualViewport.height;
            window.visualViewport.addEventListener('resize', function () {
                var nextHeight = window.visualViewport.height;
                var grew = nextHeight > lastViewportHeight + 24;
                lastViewportHeight = nextHeight;
                osrsEnsureCalculatorPageVisible();
                if (grew) {
                    scrollFocusedIntoView();
                }
            });
            window.visualViewport.addEventListener('scroll', function () {
                osrsEnsureCalculatorPageVisible();
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

        function osrsCollapseTemplatesUsed(root) {
        if (!root || !root.querySelectorAll) return;
        var scope = root.querySelectorAll ? root : document;
        scope.querySelectorAll(
            '.templatesUsed, .mw-templatesUsedExplanation, table.archivelist, table.osrs-calculator-templates'
        ).forEach(function (node) {
            try {
                node.setAttribute('data-osrs-templates-collapsed', '1');
                node.style.setProperty('display', 'none', 'important');
                // Also detach so flex/layout CSS cannot resurrect it.
                if (node.parentNode) node.parentNode.removeChild(node);
            } catch (e) {}
        });
    }

function osrsPromoteCalculatorDescription(layout, formHost) {
        if (!layout || !formHost) return;
        var desc = null;
        var prev = formHost.previousElementSibling;
        while (prev) {
            if (prev.matches && (
                prev.matches('p') ||
                prev.matches('.calculator-description') ||
                prev.matches('.mw-parser-output > p') ||
                prev.matches('div.calculator-description')
            )) {
                // Skip obsolete/JS messageboxes — keep real explanatory copy.
                var t = (prev.textContent || '').replace(/\s+/g, ' ').trim();
                if (!/requires JavaScript/i.test(t) && !prev.classList.contains('messagebox')) {
                    desc = prev;
                    break;
                }
            }
            if (prev.querySelector && prev.querySelector('pre.jcConfig, .jcTable, .oo-ui-widget')) break;
            prev = prev.previousElementSibling;
        }
        if (!desc) {
            var root = document.querySelector('.mw-parser-output') || document.body;
            var pre = root.querySelector('pre.jcConfig');
            if (pre) {
                var cursor = pre.previousElementSibling;
                while (cursor) {
                    if (cursor.matches && cursor.matches('p, .calculator-description')) {
                        var tt = (cursor.textContent || '').replace(/\s+/g, ' ').trim();
                        if (tt && !/requires JavaScript/i.test(tt) && !cursor.classList.contains('messagebox')) {
                            desc = cursor;
                            break;
                        }
                    }
                    cursor = cursor.previousElementSibling;
                }
            }
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
        osrsCollapseTemplatesUsed(root || document);
        if (!root || !root.querySelectorAll) return;
        // Prefer 3x3 phone/number pads. Do NOT force type=number (OOUI + iOS
        // often fall back to qwerty-with-numbers). pattern=[0-9]* helps iOS ints.
        var nodes = root.querySelectorAll(
            'input[type="number"], .oo-ui-numberInputWidget input, ' +
            '.jsCalc-field-int input, .jsCalc-field-number input, ' +
            '.jsCalc-field-float input, .jsCalc-field-hs input'
        );
        Array.prototype.forEach.call(nodes, function (input) {
            try {
                var field = input.closest && input.closest('.jsCalc-field, .oo-ui-numberInputWidget');
                var isInt = !!(field && (
                    field.classList.contains('jsCalc-field-int') ||
                    field.classList.contains('oo-ui-numberInputWidget')
                ));
                // decimals / floats keep a decimal pad; pure ints get numeric + pattern
                var mode = 'decimal';
                if (isInt && field && field.classList.contains('jsCalc-field-int')) {
                    mode = 'numeric';
                    if (!input.getAttribute('pattern')) {
                        input.setAttribute('pattern', '[0-9]*');
                    }
                }
                input.setAttribute('inputmode', mode);
                input.setAttribute('enterkeyhint', 'done');
                input.setAttribute('autocomplete', 'off');
                // Keep OOUI type as-is; only hint the soft keyboard.
            } catch (e) {}
        });
        // Also catch bare tel-style quantity fields without OOUI wrappers.
        root.querySelectorAll('input[inputmode="decimal"], input[inputmode="numeric"]').forEach(function (input) {
            try { input.setAttribute('enterkeyhint', 'done'); } catch (e) {}
        });
    }

    /**
     * Install native OS picker intercept for calculator dropdowns.
     * 
     * Replaces broken OOUI dropdowns in calculators with OS-native choice UI:
     * - Android: MaterialAlertDialog with radio list
     * - iOS: Action sheet or picker wheel
     * 
     * Scope: .osrs-calculator-layout, .jcTable, .oo-ui-dropdownWidget inside calculators only.
     */
    function osrsInstallCalculatorDropdownIntercept() {
        if (window.__osrsCalcDropdownInterceptInstalled) return;
        window.__osrsCalcDropdownInterceptInstalled = true;

        function hasAndroidBridge() {
            return !!(window.osrsCalculatorApi &&
                typeof window.osrsCalculatorApi.showChoicePicker === 'function');
        }
        function hasIOSBridge() {
            return !!(window.webkit && window.webkit.messageHandlers &&
                window.webkit.messageHandlers.osrsCalculatorApi);
        }

        /**
         * Extract options from a calculator dropdown element.
         * Supports native <select> and OOUI DropdownWidget.
         */
        function extractDropdownOptions(element) {
            var options = [];
            var currentValue = null;
            var label = '';

            // Find label from nearby structure
            var labelNode = null;
            if (element.closest) {
                var fieldLayout = element.closest('.oo-ui-fieldLayout, .jsCalc-field');
                if (fieldLayout) {
                    labelNode = fieldLayout.querySelector('.oo-ui-labelElement-label, label');
                }
            }
            if (!labelNode && element.previousElementSibling) {
                labelNode = element.previousElementSibling.querySelector('label');
            }
            label = labelNode ? (labelNode.textContent || labelNode.innerText || '').trim() : 'Choose option';

            // Extract from native <select>
            if (element.tagName === 'SELECT') {
                currentValue = element.value;
                Array.prototype.forEach.call(element.options, function(opt) {
                    options.push({
                        label: (opt.textContent || opt.innerText || '').trim(),
                        value: opt.value
                    });
                });
                return { label: label, options: options, currentValue: currentValue, element: element };
            }

            // Extract from OOUI DropdownWidget / DropdownInputWidget
            var dropdownRoot = element.classList.contains('oo-ui-dropdownWidget')
                ? element
                : (element.closest && element.closest('.oo-ui-dropdownWidget'));
            if (dropdownRoot) {
                // Prefer the backing <select> used by DropdownInputWidget — OOUI menus are
                // often not mounted until opened, and $.data(widget) is frequently missing
                // inside the app WebView, so scraping the select is the reliable path.
                var backingSelect = null;
                var fieldRoot = dropdownRoot.closest('.oo-ui-dropdownInputWidget, .oo-ui-fieldLayout, .jsCalc-field') || dropdownRoot.parentElement;
                if (fieldRoot && fieldRoot.querySelector) {
                    backingSelect = fieldRoot.querySelector('select');
                }
                if (!backingSelect && dropdownRoot.parentElement) {
                    backingSelect = dropdownRoot.parentElement.querySelector('select');
                }
                if (backingSelect && backingSelect.options && backingSelect.options.length) {
                    currentValue = backingSelect.value;
                    Array.prototype.forEach.call(backingSelect.options, function(opt) {
                        options.push({
                            label: (opt.textContent || opt.innerText || '').trim(),
                            value: opt.value
                        });
                    });
                    return {
                        label: label,
                        options: options,
                        currentValue: currentValue,
                        element: backingSelect,
                        widget: null,
                        dropdownRoot: dropdownRoot
                    };
                }

                var widget = null;
                try {
                    if (window.$ && window.$.data) {
                        widget = window.$.data(dropdownRoot, 'oo-ui-dropdownWidget') ||
                            window.$.data(dropdownRoot, 'oo-ui-widget');
                    }
                    if (!widget && dropdownRoot.id && window.OO && OO.ui && OO.ui.infuse) {
                        // no-op fallback
                    }
                } catch (e) {}

                if (widget && widget.getMenu) {
                    try {
                        var menu = widget.getMenu();
                        var items = menu.getItems ? menu.getItems() : [];
                        currentValue = widget.getValue ? widget.getValue() : null;
                        items.forEach(function(item) {
                            var itemLabel = item.getLabel ? item.getLabel() : '';
                            var itemData = item.getData ? item.getData() : null;
                            options.push({
                                label: String(itemLabel || '').trim(),
                                value: itemData != null ? String(itemData) : String(itemLabel)
                            });
                        });
                    } catch (e) {}
                }

                // DOM fallback: scrape menu option widgets (works when $.data widget missing)
                if (!options.length) {
                    var menuRoot = dropdownRoot.querySelector('.oo-ui-menuSelectWidget, .oo-ui-selectWidget');
                    var optionNodes = (menuRoot || document).querySelectorAll(
                        '.oo-ui-menuOptionWidget, .oo-ui-optionWidget'
                    );
                    // Prefer options scoped under this dropdown's popup if present
                    if (menuRoot) {
                        optionNodes = menuRoot.querySelectorAll('.oo-ui-menuOptionWidget, .oo-ui-optionWidget');
                    } else {
                        // Closest field may stash options in a clipped menu sibling
                        var field = dropdownRoot.closest('.oo-ui-fieldLayout, .jsCalc-field') || dropdownRoot.parentElement;
                        if (field) {
                            optionNodes = field.querySelectorAll('.oo-ui-menuOptionWidget, .oo-ui-optionWidget');
                        }
                    }
                    Array.prototype.forEach.call(optionNodes, function(node) {
                        var lab = (node.textContent || '').replace(/\s+/g, ' ').trim();
                        if (!lab) return;
                        var val = node.getAttribute('data-data') ||
                            node.getAttribute('data-value') ||
                            lab;
                        options.push({ label: lab, value: String(val) });
                    });
                    var handle = dropdownRoot.querySelector('.oo-ui-dropdownWidget-handle');
                    if (handle) {
                        currentValue = (handle.textContent || '').replace(/\s+/g, ' ').trim();
                    }
                }

                // Last resort: parse from jcConfig select param options in nearby pre (not ideal)
                if (!options.length && label) {
                    var pre = document.querySelector('pre.jcConfig');
                    if (pre) {
                        var lines = (pre.textContent || '').split('\n');
                        for (var li = 0; li < lines.length; li++) {
                            var line = lines[li];
                            if (line.toLowerCase().indexOf('|select|') < 0 &&
                                line.toLowerCase().indexOf('|buttonselect|') < 0) continue;
                            if (label && line.indexOf(label) < 0 && line.toLowerCase().indexOf(label.toLowerCase()) < 0) {
                                // still allow if option list present
                            }
                            var parts = line.split('|');
                            // param = id|Label|default|select|A,B,C
                            if (parts.length >= 5 && /select/i.test(parts[3] || '')) {
                                var optStr = parts[4] || '';
                                // strip trailing ;bindings
                                optStr = optStr.split(';')[0];
                                optStr.split(',').forEach(function(raw) {
                                    var lab2 = raw.trim();
                                    if (!lab2) return;
                                    options.push({ label: lab2, value: lab2 });
                                });
                                if (parts[2]) currentValue = parts[2].trim();
                                if (options.length) break;
                            }
                        }
                    }
                }

                return { label: label, options: options, currentValue: currentValue, element: dropdownRoot, widget: widget };
            }

            return null;
        }

        /**
         * Update dropdown value after native picker selection.
         */
        function updateDropdownValue(dropdownInfo, selectedValue) {
            if (!dropdownInfo || selectedValue == null) return;

            // Update native <select> (including OOUI DropdownInputWidget backing select)
            if (dropdownInfo.element.tagName === 'SELECT') {
                dropdownInfo.element.value = selectedValue;
                var changeEvent = new Event('change', { bubbles: true, cancelable: true });
                dropdownInfo.element.dispatchEvent(changeEvent);
                var inputEvent = new Event('input', { bubbles: true, cancelable: true });
                dropdownInfo.element.dispatchEvent(inputEvent);
                // Keep visible OOUI handle label in sync when we drove a backing select.
                try {
                    var root = dropdownInfo.dropdownRoot ||
                        (dropdownInfo.element.closest && dropdownInfo.element.closest('.oo-ui-dropdownInputWidget, .oo-ui-fieldLayout'));
                    if (root) {
                        var handleLabel = root.querySelector('.oo-ui-dropdownWidget-handle .oo-ui-labelElement-label, .oo-ui-dropdownWidget-handle');
                        var opt = dropdownInfo.element.selectedOptions && dropdownInfo.element.selectedOptions[0];
                        if (handleLabel && opt) {
                            var lab = (opt.textContent || opt.innerText || selectedValue).trim();
                            if (handleLabel.classList.contains('oo-ui-dropdownWidget-handle')) {
                                var inner = handleLabel.querySelector('.oo-ui-labelElement-label');
                                if (inner) inner.textContent = lab;
                            } else {
                                handleLabel.textContent = lab;
                            }
                        }
                    }
                } catch (e) {}
                // Wave2d: also drive OOUI DropdownInputWidget.setValue so field
                // toggles (Level vs XP Current rows) fire. Backing-select change
                // alone often does not notify the OOUI widget.
                try {
                    var oouiWidget = dropdownInfo.widget;
                    var syncRoot = dropdownInfo.dropdownRoot ||
                        (dropdownInfo.element.closest && dropdownInfo.element.closest('.oo-ui-dropdownInputWidget, .oo-ui-fieldLayout'));
                    if (!oouiWidget && window.$ && syncRoot) {
                        var $root = window.$(syncRoot);
                        oouiWidget = $root.data('oo-ui-dropdownInputWidget') ||
                            $root.data('oo-ui-widget') ||
                            (syncRoot.parentElement && window.$(syncRoot.parentElement).data('oo-ui-dropdownInputWidget'));
                    }
                    if (!oouiWidget && syncRoot && window.OO && OO.ui && OO.ui.infuse) {
                        try { oouiWidget = OO.ui.infuse(syncRoot); } catch (infuseErr) {}
                    }
                    if (oouiWidget && typeof oouiWidget.setValue === 'function') {
                        oouiWidget.setValue(selectedValue);
                    }
                } catch (syncErr) {}
                return;
            }

            // Update OOUI widget
            if (dropdownInfo.widget && dropdownInfo.widget.setValue) {
                dropdownInfo.widget.setValue(selectedValue);
                // OOUI widgets emit their own change events
            }
        }

        /**
         * Show native picker for Android.
         */
        function showAndroidPicker(dropdownInfo) {
            if (!hasAndroidBridge()) return false;
            
            try {
                var payload = JSON.stringify({
                    label: dropdownInfo.label,
                    options: dropdownInfo.options,
                    currentValue: dropdownInfo.currentValue
                });
                var result = window.osrsCalculatorApi.showChoicePicker(payload);
                var response = JSON.parse(result);
                
                if (response.selected) {
                    updateDropdownValue(dropdownInfo, response.value);
                }
                return true;
            } catch (e) {
                console.error('[CalcDropdown] Android picker failed:', e);
                return false;
            }
        }

        /**
         * Show native picker for iOS.
         */
        function showIOSPicker(dropdownInfo) {
            if (!hasIOSBridge()) return false;

            try {
                // Create callback for iOS response
                var callbackId = 'calcDropdown_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
                window[callbackId] = function(response) {
                    try {
                        if (response && response.selected) {
                            updateDropdownValue(dropdownInfo, response.value);
                        }
                    } finally {
                        delete window[callbackId];
                    }
                };

                window.webkit.messageHandlers.osrsCalculatorApi.postMessage({
                    action: 'showChoicePicker',
                    label: dropdownInfo.label,
                    options: dropdownInfo.options,
                    currentValue: dropdownInfo.currentValue,
                    callbackId: callbackId
                });
                return true;
            } catch (e) {
                console.error('[CalcDropdown] iOS picker failed:', e);
                return false;
            }
        }

        /**
         * Handle dropdown click/focus to show native picker.
         */
        var lastOpenedAt = 0;
        function handleDropdownInteraction(event) {
            var target = event.target;
            if (!target || !target.closest) return;

            // Check if we're inside a calculator
            var calcContainer = target.closest(
                '.osrs-calculator-layout, .jcTable, .oo-ui-fieldsetLayout, .osrs-calculator-panel'
            );
            if (!calcContainer) return;

            // Find the dropdown element (handle clicks resolve to parent widget)
            var dropdown = target.closest(
                'select, .oo-ui-dropdownWidget, .oo-ui-dropdownInputWidget, .oo-ui-dropdownWidget-handle'
            );
            if (!dropdown && target.closest('.oo-ui-indicator-down, .oo-ui-indicatorElement')) {
                dropdown = target.closest('.oo-ui-dropdownWidget, .oo-ui-dropdownInputWidget');
            }
            if (dropdown && dropdown.classList && dropdown.classList.contains('oo-ui-dropdownWidget-handle')) {
                dropdown = dropdown.closest('.oo-ui-dropdownWidget') || dropdown;
            }
            if (!dropdown) return;
            if (!hasAndroidBridge() && !hasIOSBridge()) return;

            var dropdownInfo = extractDropdownOptions(dropdown);
            if (!dropdownInfo || !dropdownInfo.options || dropdownInfo.options.length === 0) {
                console.log('[CalcDropdown] No options for', dropdown && dropdown.className);
                return;
            }

            // Prevent default dropdown behavior
            if (event.cancelable) event.preventDefault();
            event.stopPropagation();
            if (event.stopImmediatePropagation) event.stopImmediatePropagation();

            var now = Date.now();
            if (now - lastOpenedAt < 700) return;
            lastOpenedAt = now;

            // Blur any focused input to hide keyboard
            if (document.activeElement && document.activeElement.blur) {
                document.activeElement.blur();
            }

            // Show native picker
            var handled = false;
            if (hasAndroidBridge()) {
                handled = showAndroidPicker(dropdownInfo);
            } else if (hasIOSBridge()) {
                handled = showIOSPicker(dropdownInfo);
            }

            if (handled) {
                console.log('[CalcDropdown] Showed native picker for:', dropdownInfo.label);
            }
        }

        function maybeHandleDropdownEvent(event) {
            var target = event.target;
            if (!target || !target.closest) return;
            var calcContainer = target.closest(
                '.osrs-calculator-layout, .jcTable, .oo-ui-fieldsetLayout, .osrs-calculator-panel'
            );
            if (!calcContainer) return;
            var dropdown = target.closest(
                'select, .oo-ui-dropdownWidget, .oo-ui-dropdownWidget-handle, .oo-ui-dropdownInputWidget, .oo-ui-indicator-down'
            );
            if (dropdown) {
                handleDropdownInteraction(event);
            }
        }

        // Simulator HID often synthesizes mouse/touch without pointer events.
        // OOUI also stops click after mousedown, so capture all four.
        ['pointerdown', 'touchstart', 'mousedown', 'click'].forEach(function (type) {
            document.addEventListener(type, maybeHandleDropdownEvent, true);
        });

        // Also intercept focus for native <select>
        document.addEventListener('focus', function(event) {
            var target = event.target;
            if (!target || !target.closest) return;
            if (target.tagName !== 'SELECT') return;

            var calcContainer = target.closest(
                '.osrs-calculator-layout, .jcTable, .oo-ui-fieldsetLayout, .osrs-calculator-panel'
            );
            if (calcContainer) {
                handleDropdownInteraction(event);
            }
        }, true);

        window.__osrsOpenCalcDropdown = function (index) {
            var nodes = document.querySelectorAll(
                '.osrs-calculator-layout select, .osrs-calculator-layout .oo-ui-dropdownWidget'
            );
            var node = nodes[index || 0];
            if (!node) return 'no-dropdown';
            handleDropdownInteraction({
                target: node,
                preventDefault: function () {},
                stopPropagation: function () {},
                stopImmediatePropagation: function () {},
                cancelable: false
            });
            return 'opened:' + nodes.length;
        };

        console.log('[CalcDropdown] Native picker intercept installed');
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
            osrsInstallCalculatorKeyboardGuards();
            osrsApplyNumericKeyboards(existing);
            osrsCollapseTemplatesUsed(document);
            return;
        }

        // Intentionally drop Template:Calc_use "Templates used" archive lists —
        // they waste the first viewport on mobile and are not user-facing.
        var templates = findCalculatorTemplateBox(pre);
        if (templates && templates.parentNode) {
            templates.parentNode.removeChild(templates);
            templates = null;
        }
        var layout = document.createElement('div');
        layout.className = 'osrs-calculator-layout';
        osrsInstallCalculatorKeyboardGuards();
        osrsStripJavascriptRequiredBanners(document);
        osrsPromoteCalculatorDescription(layout, formHost);
        formHost.parentNode.insertBefore(layout, formHost);

        layout.appendChild(formHost);
        if (resultTarget && resultTarget !== formHost) {
            layout.appendChild(resultTarget);
            resultTarget.classList.add('osrs-calculator-result');
        }
        // Apply AFTER formHost is inside layout — OOUI inputs live under formHost.
        osrsApplyNumericKeyboards(layout);
        setTimeout(function () { osrsApplyNumericKeyboards(layout); }, 400);
        setTimeout(function () { osrsApplyNumericKeyboards(layout); }, 1500);
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
        osrsInstallCalculatorThemeSkin();
    }

    function osrsInstallCalculatorThemeSkin() {
        var css = [
            'html body .osrs-calculator-layout,html body .osrs-calculator-panel{max-width:100%!important;width:100%!important;box-sizing:border-box!important;overflow-x:auto!important}',
            'html body .osrs-calculator-layout .jcTable,html body .osrs-calculator-panel{max-width:100%!important;width:100%!important}',
            'html body .osrs-calculator-layout .oo-ui-fieldsetLayout,html body .osrs-calculator-layout .oo-ui-panelLayout-framed{overflow:visible!important}',
            'html body .osrs-calculator-layout .oo-ui-fieldsetLayout-header,html body .osrs-calculator-layout .oo-ui-fieldsetLayout-header>.oo-ui-labelElement-label{display:flex!important;align-items:center!important;overflow:visible!important;height:auto!important;max-height:none!important;min-height:2.85rem!important;line-height:1.45!important;padding:.55em .35em .4em!important;clip:auto!important;clip-path:none!important}',
            'html body .osrs-calculator-panel .oo-ui-fieldLayout.oo-ui-labelElement{display:grid!important;grid-template-columns:minmax(0,1fr)!important}',
            'html body .osrs-calculator-panel .oo-ui-fieldLayout.oo-ui-labelElement>.oo-ui-fieldLayout-body>.oo-ui-fieldLayout-header{grid-column:1!important;grid-row:1!important;max-width:100%!important}',
            'html body .osrs-calculator-panel .oo-ui-fieldLayout.oo-ui-labelElement>.oo-ui-fieldLayout-body>.oo-ui-fieldLayout-field{grid-column:1!important;grid-row:2!important;max-width:100%!important}',
            'html body .osrs-calculator-layout .oo-ui-buttonElement-button,html body .osrs-calculator-layout .oo-ui-buttonElement-button .oo-ui-labelElement-label,html body .osrs-calculator-layout .jcSubmit .oo-ui-buttonElement-button{color:var(--ooui-text,var(--text-color))!important;-webkit-text-fill-color:var(--ooui-text,var(--text-color))!important;background-color:var(--ooui-normal,var(--wikitable-bg))!important;border-color:var(--ooui-normal-border,var(--body-border))!important}',
            'html body .osrs-calculator-layout .jcSubmit.oo-ui-buttonElement>.oo-ui-buttonElement-button,html body .osrs-calculator-layout .oo-ui-flaggedElement-primary.oo-ui-flaggedElement-progressive>.oo-ui-buttonElement-button{background-color:var(--ooui-progressive)!important;border-color:var(--ooui-progressive)!important;color:var(--ooui-on-progressive,#fff)!important;-webkit-text-fill-color:var(--ooui-on-progressive,#fff)!important}',
            'html.theme-osrs-dark .osrs-calculator-layout .jcSubmit .oo-ui-buttonElement-button,html body.wgl-theme-dark .osrs-calculator-layout .jcSubmit .oo-ui-buttonElement-button,html.theme-osrs-dark .osrs-calculator-layout .jcSubmit .oo-ui-buttonElement-button .oo-ui-labelElement-label,html body.wgl-theme-dark .osrs-calculator-layout .jcSubmit .oo-ui-buttonElement-button .oo-ui-labelElement-label{color:#f4efe6!important;-webkit-text-fill-color:#f4efe6!important}',
            'html.theme-osrs-dark .osrs-calculator-layout .oo-ui-buttonElement-button,html body.theme-osrs-dark .osrs-calculator-layout .oo-ui-buttonElement-button,html.theme-osrs-dark .osrs-calculator-layout .oo-ui-numberInputWidget-button,html body.wgl-theme-dark .osrs-calculator-layout .oo-ui-buttonElement-button{color:var(--ooui-text,#f2e6d5)!important;-webkit-text-fill-color:var(--ooui-text,#f2e6d5)!important}',
            'html.theme-osrs-dark .osrs-calculator-layout .oo-ui-iconElement-icon,html body.theme-osrs-dark .osrs-calculator-layout .oo-ui-iconElement-icon,html body.wgl-theme-dark .osrs-calculator-layout .oo-ui-iconElement-icon,html.theme-osrs-dark .osrs-calculator-layout .oo-ui-indicatorElement-indicator,html body.wgl-theme-dark .osrs-calculator-layout .oo-ui-indicatorElement-indicator{filter:invert(1) brightness(1.15)!important;opacity:1!important}',
            'html body .osrs-calculator-layout .oo-ui-numberInputWidget-field{display:flex!important;flex-direction:row!important;align-items:stretch!important;max-width:100%!important;width:100%!important;gap:.2em!important}',
            'html body .osrs-calculator-layout .oo-ui-numberInputWidget-minusButton,html body .osrs-calculator-layout .oo-ui-numberInputWidget-plusButton{flex:0 0 2.25rem!important;max-width:2.25rem!important;min-width:2.25rem!important}',
            'html body .osrs-calculator-layout .oo-ui-numberInputWidget .oo-ui-inputWidget-input{flex:1 1 0!important;min-width:0!important;width:auto!important}',
            'html body .osrs-calculator-layout .oo-ui-dropdownWidget-handle+.oo-ui-labelElement-label,html body .osrs-calculator-layout .oo-ui-dropdownInputWidget>.oo-ui-labelElement-label,html body .osrs-calculator-layout .jsCalc-field-select .oo-ui-fieldLayout-field>.oo-ui-labelElement-label,html body .osrs-calculator-layout .jsCalc-field .oo-ui-fieldLayout-field>span.oo-ui-labelElement-label,html body .osrs-calculator-layout .jsCalc-field-select .oo-ui-fieldLayout-field>.oo-ui-labelElement-label{display:none!important}',
            'html body .osrs-calculator-layout .jsCalc-field-fixed>.oo-ui-fieldLayout-body>.oo-ui-fieldLayout-field>.oo-ui-labelElement-label:empty,html body .osrs-calculator-layout .osrs-calculator-result:empty,html body .osrs-calculator-layout [id$="Result"]:empty,html body #osrs-calculator-status:empty{display:none!important;background:none!important;border:0!important;min-height:0!important;height:0!important;padding:0!important;margin:0!important}',
            'html body .osrs-calculator-layout .oo-ui-fieldLayout-align-right>.oo-ui-fieldLayout-body,html body .osrs-calculator-layout .oo-ui-fieldLayout-align-left>.oo-ui-fieldLayout-body{flex-wrap:wrap!important;max-width:100%!important}',
            'html body .osrs-calculator-layout .oo-ui-fieldLayout-align-right>.oo-ui-fieldLayout-body>.oo-ui-fieldLayout-header,html body .osrs-calculator-layout .oo-ui-fieldLayout-align-left>.oo-ui-fieldLayout-body>.oo-ui-fieldLayout-header{flex:1 1 100%!important;max-width:100%!important;text-align:left!important}',
            'html body .osrs-calculator-layout .oo-ui-fieldLayout-align-right>.oo-ui-fieldLayout-body>.oo-ui-fieldLayout-field,html body .osrs-calculator-layout .oo-ui-fieldLayout-align-left>.oo-ui-fieldLayout-body>.oo-ui-fieldLayout-field{flex:1 1 100%!important;max-width:100%!important}',
            'html body .osrs-calculator-layout .oo-ui-actionFieldLayout>.oo-ui-fieldLayout-body{display:flex!important;flex-wrap:nowrap!important;max-width:100%!important}'
        ].join('');
        var style = document.getElementById('osrs-calc-skin');
        if (!style) {
            style = document.createElement('style');
            style.id = 'osrs-calc-skin';
            style.setAttribute('data-osrs-calc-skin', '1');
            style.appendChild(document.createTextNode(css));
        }
        var head = document.head || document.documentElement;
        if (style.parentNode !== head || head.lastElementChild !== style) {
            head.appendChild(style);
        }
        if (!window.__osrsCalcSkinObserver && document.head) {
            window.__osrsCalcSkinObserver = true;
            var skinPending = false;
            var obs = new MutationObserver(function () {
                var live = document.getElementById('osrs-calc-skin');
                if (live && document.head.lastElementChild === live) return;
                if (skinPending) return;
                skinPending = true;
                setTimeout(function () {
                    skinPending = false;
                    osrsInstallCalculatorThemeSkin();
                }, 80);
            });
            obs.observe(document.head, { childList: true });
        }
        osrsHideEmptyCalculatorOutputs();
        osrsDedupeHiscoreRows();
    }

    function osrsHideEmptyCalculatorOutputs() {
        document.querySelectorAll('.osrs-calculator-layout [id$="Result"], .osrs-calculator-result, #osrs-calculator-status').forEach(function (node) {
            var text = String(node.textContent || '').replace(/\s+/g, ' ').trim();
            var hasMedia = !!(node.querySelector && node.querySelector('img, table, .wikitable, .jcTable, .oo-ui-widget'));
            if (!text && !hasMedia) {
                node.setAttribute('data-osrs-calc-empty', '1');
                node.style.setProperty('display', 'none', 'important');
            } else {
                node.removeAttribute('data-osrs-calc-empty');
                if (node.getAttribute('data-osrs-calc-empty-forced') !== '1') {
                    node.style.removeProperty('display');
                }
            }
        });
        document.querySelectorAll('.jsCalc-field-fixed .oo-ui-labelElement-label').forEach(function (node) {
            if (!(node.textContent || '').trim()) {
                node.style.setProperty('display', 'none', 'important');
            }
        });
    }

    function osrsDedupeHiscoreRows() {
        document.querySelectorAll('.osrs-calculator-layout, .jcTable').forEach(function (root) {
            var rows = root.querySelectorAll('.jsCalc-field-hs');
            if (rows.length < 2) return;
            var seen = {};
            Array.prototype.forEach.call(rows, function (row, index) {
                var label = '';
                var labelNode = row.querySelector('.oo-ui-fieldLayout-header .oo-ui-labelElement-label, .oo-ui-labelElement-label');
                if (labelNode) label = String(labelNode.textContent || '').replace(/\s+/g, ' ').trim().toLowerCase();
                var key = label || ('hs-' + index);
                if (seen[key]) {
                    row.setAttribute('data-osrs-calc-dup-hs', '1');
                    row.style.setProperty('display', 'none', 'important');
                } else {
                    seen[key] = true;
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
        osrsHideEmptyCalculatorOutputs();
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
        osrsInstallCalculatorKeyboardGuards();
        document.querySelectorAll('pre.jcConfig').forEach(function(pre) {
            var config = parseCalculatorConfig(pre);
            var formTarget = config.form && document.getElementById(config.form);
            if (formTarget) {
                prepareCalculatorLayout(pre, formTarget, findCalculatorResultNode(config, formTarget));
            }
        });
        osrsReassertCalculatorThemeSheets();
        osrsDedupeHiscoreRows();
        osrsHideEmptyCalculatorOutputs();
        patchAjax();
        loadCalcCore();
        osrsWatchCalculatorResults();
        if (window.mw && mw.hook && mw.hook('rscalc.submit')) {
            mw.hook('rscalc.submit').add(osrsPublishCalculatorResult);
        }
        osrsArmSmokeSubmit();
        (function osrsPollCalculatorLive(attempt) {
            osrsHideCalculatorJsPlaceholder();
            osrsDedupeHiscoreRows();
            osrsHideEmptyCalculatorOutputs();
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
                if (!document.querySelector('.jsCalc-field, .osrs-calculator-layout .oo-ui-widget')) {
                    initialize();
                } else {
                    osrsReassertCalculatorThemeSheets();
                    osrsDedupeHiscoreRows();
                    osrsHideEmptyCalculatorOutputs();
                }
            });
        }
        if (window.mw && mw.hook && mw.hook('rscalc.setupComplete')) {
            mw.hook('rscalc.setupComplete').add(function() {
                patchAjax();
                osrsHideCalculatorJsPlaceholder();
                osrsInstallCalculatorThemeSkin();
                osrsDedupeHiscoreRows();
                osrsHideEmptyCalculatorOutputs();
                document.querySelectorAll('.osrs-calculator-layout').forEach(function (layout) {
                    osrsApplyNumericKeyboards(layout);
                });
            });
        }
    }

    boot();
})();
