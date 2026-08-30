/*
 * In-document calculator chrome (verdict C).
 * Loaded as part of osrs_calculator_runtime.js (spliced). Kept as a sibling
 * source for node unit tests that do not boot the WebView runtime.
 */
(function (root, factory) {
    var api = factory();
    if (typeof module === 'object' && module.exports) {
        module.exports = api;
    }
    root.osrsIndocCalc = api;
}(typeof globalThis !== 'undefined' ? globalThis : this, function () {
    'use strict';

    var KIT = {
        string: true, int: true, number: true, select: true, buttonselect: true,
        check: true, toggleswitch: true, togglebutton: true, hs: true, rsn: true,
        hidden: true, fixed: true, semihidden: true
    };
    var JCCONFIG_OPEN = /<pre[^>]*class="[^"]*jcConfig[^"]*"/gi;

    function normalizeTitle(title) {
        return String(title || '').replace(/_/g, ' ').trim();
    }

    function normalizeAutosubmit(raw) {
        var v = String(raw == null ? 'off' : raw).toLowerCase().trim();
        if (!v || v === 'off' || v === 'disabled' || v === 'false') return 'off';
        if (v === 'enabled' || v === 'on' || v === 'true') return 'on';
        return 'on';
    }

    function countJcConfigs(html) {
        var matches = String(html || '').match(JCCONFIG_OPEN);
        return matches ? matches.length : 0;
    }

    function collectPageTitles() {
        var out = [];
        function push(value) {
            var normalized = normalizeTitle(value);
            if (normalized && out.indexOf(normalized) < 0) out.push(normalized);
        }
        try {
            if (typeof window !== 'undefined' && window.RLCONF) {
                push(window.RLCONF.wgPageName);
                push(window.RLCONF.wgTitle);
            }
        } catch (e) {}
        try {
            if (typeof window !== 'undefined' && window.mw && mw.config && typeof mw.config.get === 'function') {
                push(mw.config.get('wgPageName'));
                push(mw.config.get('wgTitle'));
            }
        } catch (e2) {}
        return out;
    }

    function resolvePageTitle(fallback) {
        var candidates = collectPageTitles();
        if (candidates.length) return candidates[0];
        return normalizeTitle(fallback);
    }

    function splitConfigLine(line) {
        var stripped = String(line || '').trim();
        if (!stripped || stripped.charAt(0) === '#' || stripped.indexOf('=') < 0) return null;
        var index = stripped.indexOf('=');
        return {
            key: stripped.slice(0, index).trim().toLowerCase(),
            value: stripped.slice(index + 1).trim()
        };
    }

    function parseToggles(raw, defaultKey) {
        var trimmed = String(raw || '').trim();
        var on = {};
        var allKeys = [];
        var allVals = [];
        if (!trimmed) return { on: on, off: {} };
        trimmed.split(';').forEach(function (piece) {
            var item = piece.trim();
            if (!item) return;
            var keys;
            var vals;
            var eq = item.indexOf('=');
            if (eq >= 0) {
                keys = item.slice(0, eq).split(',').map(function (s) { return s.trim(); }).filter(Boolean);
                vals = item.slice(eq + 1).split(',').map(function (s) { return s.trim(); }).filter(Boolean);
            } else {
                keys = [defaultKey];
                vals = item.split(',').map(function (s) { return s.trim(); }).filter(Boolean);
            }
            keys.forEach(function (key) {
                on[key] = vals;
                allKeys.push(key);
            });
            allVals = allVals.concat(vals);
        });
        var uniqueVals = [];
        allVals.forEach(function (v) {
            if (uniqueVals.indexOf(v) < 0) uniqueVals.push(v);
        });
        var off = {};
        var seen = {};
        allKeys.forEach(function (key) {
            if (seen[key]) return;
            seen[key] = true;
            var shown = on[key] || [];
            off[key] = uniqueVals.filter(function (v) { return shown.indexOf(v) < 0; });
        });
        return { on: on, off: off };
    }

    function optionsFor(type, range) {
        if (type !== 'select' && type !== 'buttonselect' && type !== 'check') return [];
        if (!range) return [];
        return range.split(',').map(function (s) { return s.trim(); }).filter(Boolean);
    }

    function intRange(range, type) {
        if (type !== 'int' && type !== 'number') return { min: null, max: null };
        var dash = String(range || '').indexOf('-');
        if (dash < 0) return { min: null, max: null };
        var left = parseInt(range.slice(0, dash).trim(), 10);
        var right = parseInt(range.slice(dash + 1).trim(), 10);
        return {
            min: isNaN(left) ? null : left,
            max: isNaN(right) ? null : right
        };
    }

    function firstConfig(text) {
        var html = String(text || '');
        var pre = html.match(/<pre[^>]*class="[^"]*jcConfig[^"]*"[^>]*>([\s\S]*?)<\/pre>/i);
        if (pre) return pre[1];
        var loose = html.match(/(?:^|\n)\s*(?:template|module)\s*=[\s\S]+?(?=\n\s*(?:\{\||----|<pre|$))/i);
        return loose ? loose[0] : html;
    }

    function parse(text, title) {
        var config = firstConfig(text);
        if (!config) return null;
        var name = 'Calculator';
        var formId = '';
        var resultId = '';
        var autosubmit = 'off';
        var invokeKind = null;
        var template = null;
        var moduleName = null;
        var moduleFunc = null;
        var inputs = [];
        var unknownTypes = [];
        String(config).split('\n').forEach(function (rawLine) {
            var parsed = splitConfigLine(rawLine);
            if (!parsed) return;
            if (parsed.key !== 'param') {
                if (parsed.key === 'form') formId = parsed.value;
                else if (parsed.key === 'result') resultId = parsed.value;
                else if (parsed.key === 'name' && parsed.value) name = parsed.value;
                else if (parsed.key === 'autosubmit') autosubmit = normalizeAutosubmit(parsed.value);
                else if (parsed.key === 'template') {
                    invokeKind = 'template';
                    template = parsed.value;
                } else if (parsed.key === 'module') {
                    invokeKind = 'module';
                    moduleName = parsed.value;
                } else if (parsed.key === 'modulefunc') {
                    moduleFunc = parsed.value || 'main';
                }
                return;
            }
            var fields = parsed.value.split(/\s*\|\s*/);
            while (fields.length < 6) fields.push('');
            var inputName = fields[0];
            if (!inputName) return;
            var label = fields[1] || inputName;
            var defaultValue = fields[2];
            var rawType = (fields[3] || '').toLowerCase();
            var range = fields[4];
            var rawToggles = fields[5];
            var type = rawType && KIT[rawType] ? rawType : (rawType ? 'unknown' : 'string');
            if (type === 'unknown') unknownTypes.push(rawType);
            var toggleDefault = defaultValue || (
                (type === 'toggleswitch' || type === 'togglebutton' || type === 'check') ? 'true' : inputName
            );
            if (type === 'toggleswitch' && !defaultValue) defaultValue = 'false';
            var toggles = parseToggles(rawToggles, toggleDefault);
            var bounds = intRange(range, type);
            inputs.push({
                name: inputName,
                label: label,
                defaultValue: defaultValue,
                type: type,
                range: range,
                options: optionsFor(type, range),
                toggles: toggles.on,
                toggleOff: toggles.off,
                minValue: bounds.min,
                maxValue: bounds.max
            });
        });
        if (!invokeKind) return null;
        if (invokeKind === 'module' && !moduleFunc) moduleFunc = 'main';
        var calcId = title ? normalizeTitle(title) : name;
        return {
            schemaVersion: 1,
            id: calcId,
            ui: { name: name, formId: formId, resultId: resultId, autosubmit: autosubmit },
            invoke: { kind: invokeKind, template: template, module: moduleName, moduleFunc: moduleFunc },
            inputs: inputs,
            unknownTypes: unknownTypes
        };
    }

    function isEligible(definition) {
        if (!definition) return false;
        if (definition.invoke.kind === 'template' && !definition.invoke.template) return false;
        if (definition.invoke.kind === 'module' && !definition.invoke.module) return false;
        if (definition.unknownTypes.length) return false;
        if (!definition.inputs.length) return false;
        return definition.inputs.every(function (input) { return KIT[input.type]; });
    }

    function isPageEligible(html, title) {
        var count;
        var source;
        if (html == null && typeof document !== 'undefined') {
            var nodes = document.querySelectorAll('pre.jcConfig');
            count = nodes.length;
            if (count !== 1) return false;
            source = nodes[0].textContent || nodes[0].innerText || '';
            return isEligible(parse(source, title));
        }
        count = countJcConfigs(html);
        if (count !== 1) return false;
        return isEligible(parse(html, title));
    }

    function visibleInputNames(definition, values) {
        var visible = {};
        definition.inputs.forEach(function (input) { visible[input.name] = true; });
        definition.inputs.forEach(function (input) {
            var keys = Object.keys(input.toggles || {});
            if (!keys.length) return;
            var current = values[input.name] != null ? values[input.name] : input.defaultValue;
            var on = input.toggles[current];
            if (on) {
                on.forEach(function (name) { visible[name] = true; });
                (input.toggleOff[current] || []).forEach(function (name) { delete visible[name]; });
            } else {
                keys.forEach(function (key) {
                    (input.toggles[key] || []).forEach(function (name) { delete visible[name]; });
                });
            }
        });
        return visible;
    }

    function boolToken(value) {
        var v = String(value || '').toLowerCase();
        return (v === '1' || v === 'true' || v === 'yes' || v === 'on') ? 'true' : 'false';
    }

    function invokeWikitext(definition, values) {
        if (!definition) return null;
        values = values || {};
        var parts = [];
        if (definition.invoke.kind === 'module') {
            var moduleName = (definition.invoke.module || '').trim();
            if (!moduleName) return null;
            var funcName = (definition.invoke.moduleFunc || 'main').trim() || 'main';
            parts.push('{{#invoke:' + moduleName + '|' + funcName);
        } else {
            var template = (definition.invoke.template || '').trim();
            if (!template) return null;
            parts.push('{{' + template);
        }
        var merged = {};
        definition.inputs.forEach(function (input) { merged[input.name] = input.defaultValue; });
        Object.keys(values).forEach(function (key) { merged[key] = values[key]; });
        var visible = visibleInputNames(definition, merged);
        definition.inputs.forEach(function (input) {
            if (input.type === 'unknown') return;
            var always = input.type === 'hidden' || input.type === 'fixed';
            if (!always && !visible[input.name]) return;
            var value = merged[input.name] == null ? '' : String(merged[input.name]);
            if ((input.type === 'hs' || input.type === 'rsn') && !value) return;
            if (input.type === 'toggleswitch') value = boolToken(value);
            parts.push('|' + input.name + '=' + value);
        });
        parts.push('}}');
        return parts.join('');
    }

    function shouldAutosubmitOnEdit(type) {
        return type !== 'hs' && type !== 'rsn' && type !== 'string';
    }

    function shouldAutosubmit(definition, fieldType) {
        if (!definition || !definition.ui || definition.ui.autosubmit !== 'on') return false;
        if (fieldType == null || fieldType === '') return true;
        return shouldAutosubmitOnEdit(fieldType);
    }

    function chromeTitle(calcId) {
        var rest = normalizeTitle(calcId);
        if (rest.indexOf('Calculator:') === 0) rest = rest.slice('Calculator:'.length);
        rest = rest.trim() || 'Calculator';
        if (rest.toLowerCase().slice(-10) === 'calculator') return rest;
        return rest + ' calculator';
    }

    function escapeHtml(value) {
        return String(value == null ? '' : value)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    function attr(name, value) {
        return ' ' + name + '="' + escapeHtml(value) + '"';
    }

    function fieldHtml(input, value, visible) {
        if (input.type === 'hidden' || input.type === 'fixed' || input.type === 'semihidden') {
            return '<input type="hidden"' + attr('name', input.name) + attr('value', value) +
                attr('data-osrs-indoc-name', input.name) + '>';
        }
        var hidden = visible ? '' : ' hidden';
        var label = escapeHtml(input.label);
        var name = escapeHtml(input.name);
        var start = '<div class="osrs-indoc-calc-field"' + hidden +
            attr('data-osrs-indoc-field', input.name) + '>' +
            '<label class="osrs-indoc-calc-label" for="osrs-indoc-field-' + name + '">' + label + '</label>';
        var control = '';
        if (input.type === 'hs' || input.type === 'rsn' || input.type === 'string') {
            var lookup = input.type === 'hs'
                ? '<button type="button" class="osrs-indoc-calc-btn" data-osrs-indoc-lookup="1" aria-label="Lookup">Lookup</button>'
                : '';
            // hs Name+Lookup: software-keyboard primary key is Go/Search, not Done.
            var enterHint = input.type === 'hs' ? 'go' : 'done';
            control = '<div class="osrs-indoc-calc-row">' +
                '<input id="osrs-indoc-field-' + name + '" class="osrs-indoc-calc-control" type="text"' +
                attr('name', input.name) + attr('value', value) + attr('aria-label', input.label) +
                attr('data-osrs-indoc-type', input.type) +
                ' inputmode="text" autocomplete="off" enterkeyhint="' + enterHint + '">' + lookup + '</div>';
        } else if (input.type === 'int' || input.type === 'number') {
            var inputMode = input.type === 'int' ? 'numeric' : 'decimal';
            control = '<div class="osrs-indoc-calc-row osrs-indoc-calc-step">' +
                '<button type="button" class="osrs-indoc-calc-step-btn" data-osrs-indoc-step="-1"' +
                attr('aria-label', 'Decrease ' + input.label) + '>-</button>' +
                '<input id="osrs-indoc-field-' + name + '" class="osrs-indoc-calc-control" type="number"' +
                attr('name', input.name) + attr('value', value) + attr('aria-label', input.label) +
                attr('data-osrs-indoc-type', input.type) +
                attr('inputmode', inputMode) + ' enterkeyhint="done"' +
                (input.minValue != null ? attr('min', input.minValue) : '') +
                (input.maxValue != null ? attr('max', input.maxValue) : '') + '>' +
                '<button type="button" class="osrs-indoc-calc-step-btn" data-osrs-indoc-step="1"' +
                attr('aria-label', 'Increase ' + input.label) + '>+</button></div>';
        } else if (input.type === 'select') {
            control = '<button type="button" class="osrs-indoc-calc-select" id="osrs-indoc-field-' + name + '"' +
                attr('data-osrs-indoc-name', input.name) + attr('aria-label', input.label) +
                ' aria-haspopup="listbox">' + escapeHtml(value || (input.options[0] || 'Choose')) + '</button>';
        } else if (input.type === 'buttonselect') {
            var chips = input.options.map(function (option) {
                var pressed = option === value ? 'true' : 'false';
                return '<button type="button" class="osrs-indoc-calc-chip"' +
                    attr('data-osrs-indoc-name', input.name) + attr('data-osrs-indoc-option', option) +
                    attr('aria-pressed', pressed) + '>' + escapeHtml(option) + '</button>';
            }).join('');
            control = '<div class="osrs-indoc-calc-chips" role="group"' + attr('aria-label', input.label) + '>' +
                chips + '</div>';
        } else if (input.type === 'toggleswitch' || input.type === 'check' || input.type === 'togglebutton') {
            var on = boolToken(value) === 'true';
            control = '<label class="osrs-indoc-calc-switch">' +
                '<input id="osrs-indoc-field-' + name + '" type="checkbox" role="switch"' +
                attr('name', input.name) + attr('aria-label', input.label) +
                (on ? ' checked' : '') + '>' +
                '<span>' + (on ? 'On' : 'Off') + '</span></label>';
        } else {
            control = '<input id="osrs-indoc-field-' + name + '" class="osrs-indoc-calc-control" type="text"' +
                attr('name', input.name) + attr('value', value) + attr('aria-label', input.label) + '>';
        }
        return start + control + '</div>';
    }

    function renderFormHtml(definition, values) {
        values = values || {};
        var merged = {};
        definition.inputs.forEach(function (input) { merged[input.name] = input.defaultValue; });
        Object.keys(values).forEach(function (key) { merged[key] = values[key]; });
        var visible = visibleInputNames(definition, merged);
        var title = chromeTitle(definition.id);
        var fields = definition.inputs.map(function (input) {
            return fieldHtml(input, merged[input.name] == null ? '' : merged[input.name], !!visible[input.name]);
        }).join('');
        return '<form class="osrs-indoc-calc-form" id="osrs-indoc-calc-form" role="form"' +
            attr('aria-label', title) + '>' +
            '<div class="osrs-indoc-calc-banner" id="osrs-indoc-calc-banner" role="alert"></div>' +
            fields +
            '<button type="submit" class="osrs-indoc-calc-btn osrs-indoc-calc-submit" aria-label="Submit calculator">Submit</button>' +
            '<div class="osrs-indoc-calc-status" id="osrs-indoc-calc-status"></div>' +
            '</form>';
    }

    function applyHiscores(body, mapping) {
        var trimmed = String(body || '').trim();
        if (!trimmed) return null;
        var lowered = trimmed.toLowerCase();
        if (lowered.indexOf('<html') >= 0 || lowered.indexOf('<!doctype') >= 0) return null;
        var lines = trimmed.split('\n');
        if (lines.length <= 1) return null;
        var updates = {};
        mapping.split(';').forEach(function (piece) {
            var parts = piece.split(',').map(function (s) { return s.trim(); });
            if (parts.length < 3) return;
            var skill = parseInt(parts[1], 10);
            var field = parseInt(parts[2], 10);
            if (isNaN(skill) || isNaN(field) || skill < 0 || skill >= lines.length) return;
            var cols = lines[skill].split(',');
            if (field < 0 || field >= cols.length) return;
            var value = cols[field].trim();
            if (value) updates[parts[0]] = value;
        });
        return Object.keys(updates).length ? updates : null;
    }

    function parseResultIsError(html) {
        var body = String(html || '');
        if (!body.trim()) return true;
        var lowered = body.toLowerCase();
        if (lowered.indexOf('scribunto-error') >= 0 || lowered.indexOf('lua error') >= 0) return true;
        if (lowered.indexOf('class="error"') >= 0 || lowered.indexOf("class='error'") >= 0) return true;
        if (lowered.indexOf('expression error') >= 0) return true;
        return false;
    }

    function missingPlayerMessage(player) {
        return 'The player "' + String(player || '') +
            '" does not exist, is banned or unranked, or we couldn\'t fetch your hiscores. Please enter the data manually.';
    }

    // First-party stand-in for OOUI FieldLayout setErrors (stop + exclamation)
    // plus gadget helper.showError's <strong class="error"> in #result.
    function lookupErrorHtml(message) {
        return '<div class="osrs-indoc-calc-error" role="alert">' +
            '<svg class="osrs-indoc-calc-error-icon" viewBox="0 0 20 20" width="20" height="20" aria-hidden="true" focusable="false">' +
            '<polygon class="osrs-indoc-calc-error-stop" points="6,1.5 14,1.5 18.5,6 18.5,14 14,18.5 6,18.5 1.5,14 1.5,6"/>' +
            '<rect class="osrs-indoc-calc-error-bang" x="9" y="5" width="2" height="6.5" rx="0.6"/>' +
            '<rect class="osrs-indoc-calc-error-bang" x="9" y="13.2" width="2" height="2" rx="0.6"/>' +
            '</svg>' +
            '<strong class="error">' + escapeHtml(message) + '</strong></div>';
    }

    return {
        normalizeTitle: normalizeTitle,
        normalizeAutosubmit: normalizeAutosubmit,
        countJcConfigs: countJcConfigs,
        collectPageTitles: collectPageTitles,
        resolvePageTitle: resolvePageTitle,
        parse: parse,
        isEligible: isEligible,
        isPageEligible: isPageEligible,
        visibleInputNames: visibleInputNames,
        invokeWikitext: invokeWikitext,
        shouldAutosubmitOnEdit: shouldAutosubmitOnEdit,
        shouldAutosubmit: shouldAutosubmit,
        chromeTitle: chromeTitle,
        renderFormHtml: renderFormHtml,
        applyHiscores: applyHiscores,
        parseResultIsError: parseResultIsError,
        missingPlayerMessage: missingPlayerMessage,
        lookupErrorHtml: lookupErrorHtml,
        boolToken: boolToken
    };
}));

(function () {
    if (typeof document === 'undefined' || !document.documentElement) return;
    var api = typeof globalThis !== 'undefined' ? globalThis.osrsIndocCalc : null;
    if (!api) return;
    if (!api.isPageEligible(null, api.resolvePageTitle())) return;
    document.documentElement.classList.add('osrs-indoc-calc');
    document.documentElement.classList.add('osrs-native-calc-slot-active');
}());
