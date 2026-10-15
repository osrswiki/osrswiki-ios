/*
 * In-article clickable tooltips.
 *
 * Wiki pages mark a trigger with .js-tooltip-click[data-tooltip-name] and a
 * matching hidden .js-tooltip-wrapper[data-tooltip-for]. Both start display:none
 * so they stay invisible until this script arms them. Clicking a trigger shows
 * the named wrapper near that tap; another tap, Escape, an outside click, or a
 * .js-tooltip-close control hides it.
 */
(function (root, factory) {
    var api = factory();
    if (typeof module === 'object' && module.exports) {
        module.exports = api;
    }
    root.osrsArticleTooltips = api;
    var page = root.document;
    if (page) {
        if (page.readyState === 'loading' && page.addEventListener) {
            page.addEventListener('DOMContentLoaded', function () {
                api.boot(page);
            });
        } else {
            api.boot(page);
        }
    }
}(typeof globalThis !== 'undefined' ? globalThis : this, function () {
    'use strict';

    var OPEN_ATTR = 'data-osrs-tooltip-open';
    var ARMED_ATTR = 'data-osrs-tooltips-armed';
    var lastTrigger = null;

    function attrEscape(value) {
        return String(value == null ? '' : value).replace(/\\/g, '\\\\').replace(/"/g, '\\"');
    }

    function wrapperFor(doc, name) {
        if (!doc || !name) return null;
        return doc.querySelector('.js-tooltip-wrapper[data-tooltip-for="' + attrEscape(name) + '"]');
    }

    function isHidden(el) {
        if (!el) return true;
        if (el.classList && el.classList.contains('hidden')) return true;
        var display = el.style && el.style.display;
        return display === 'none';
    }

    function revealTriggers(doc) {
        var triggers = doc.querySelectorAll('.js-tooltip-click');
        for (var i = 0; i < triggers.length; i++) {
            var trigger = triggers[i];
            if (trigger.classList) trigger.classList.remove('hidden');
            if (trigger.style) trigger.style.display = '';
            if (!trigger.getAttribute('role')) trigger.setAttribute('role', 'button');
            if (!trigger.getAttribute('tabindex')) trigger.setAttribute('tabindex', '0');
            trigger.setAttribute('aria-expanded', 'false');
        }
    }

    function hideWrapper(wrapper) {
        if (!wrapper) return;
        if (wrapper.classList) wrapper.classList.add('hidden');
        if (wrapper.style) wrapper.style.display = 'none';
        wrapper.removeAttribute && wrapper.removeAttribute(OPEN_ATTR);
    }

    function pageDocument(event) {
        if (event && event.target) {
            if (event.target.ownerDocument) return event.target.ownerDocument;
            if (event.target.nodeType === 9) return event.target;
        }
        var g = typeof globalThis !== 'undefined' ? globalThis : null;
        return (g && g.document) || null;
    }

    function viewportSize(doc) {
        var g = typeof globalThis !== 'undefined' ? globalThis : null;
        var win = g && g.window;
        var docEl = (doc && doc.documentElement) || (g && g.document && g.document.documentElement) || null;
        return {
            width: (win && win.innerWidth) || (docEl && docEl.clientWidth) || 320,
            height: (win && win.innerHeight) || (docEl && docEl.clientHeight) || 480
        };
    }

    function arrowSize(wrapper) {
        var raw = wrapper && wrapper.getAttribute && wrapper.getAttribute('data-tooltip-arrow-size');
        var size = parseInt(raw, 10);
        return size > 0 ? size : 10;
    }

    function ensureArrow(wrapper) {
        if (!wrapper || wrapper.getAttribute('data-tooltip-arrow') !== 'yes') return null;
        var arrow = wrapper.querySelector('.js-tooltip-arrow');
        if (!arrow && wrapper.ownerDocument && wrapper.ownerDocument.createElement) {
            arrow = wrapper.ownerDocument.createElement('div');
            arrow.className = 'js-tooltip-arrow';
            wrapper.insertBefore(arrow, wrapper.firstChild || null);
        }
        return arrow;
    }

    function place(wrapper, trigger) {
        if (!wrapper || !trigger || !trigger.getBoundingClientRect) return;
        var rect = trigger.getBoundingClientRect();
        var gap = arrowSize(wrapper);
        var view = viewportSize(wrapper.ownerDocument);
        var left = rect.left;
        var top = rect.bottom + gap;
        if (wrapper.getAttribute('data-tooltip-limit-width') === 'yes' && wrapper.style) {
            wrapper.style.maxWidth = Math.max(120, Math.floor(view.width * 0.75)) + 'px';
        }
        if (wrapper.style) {
            wrapper.style.position = 'fixed';
            wrapper.style.zIndex = '30';
            wrapper.style.left = Math.max(8, Math.min(left, view.width - 16)) + 'px';
            wrapper.style.top = Math.max(8, top) + 'px';
        }
        var arrow = ensureArrow(wrapper);
        if (arrow && arrow.style) {
            var size = gap;
            arrow.style.position = 'absolute';
            arrow.style.left = '12px';
            arrow.style.top = (-size) + 'px';
            arrow.style.borderWidth = '0 ' + size + 'px ' + size + 'px ' + size + 'px';
            arrow.style.borderBottomColor = 'var(--body-border)';
        }
    }

    function setExpanded(doc, name, expanded) {
        var triggers = doc.querySelectorAll('.js-tooltip-click[data-tooltip-name="' + attrEscape(name) + '"]');
        for (var i = 0; i < triggers.length; i++) {
            triggers[i].setAttribute('aria-expanded', expanded ? 'true' : 'false');
        }
    }

    function closeAll(doc) {
        if (!doc) return;
        var openName = openNameOf(doc);
        var wraps = doc.querySelectorAll('.js-tooltip-wrapper');
        for (var i = 0; i < wraps.length; i++) hideWrapper(wraps[i]);
        if (openName) setExpanded(doc, openName, false);
        lastTrigger = null;
    }

    function openNameOf(doc) {
        if (!doc) return null;
        var open = doc.querySelector('.js-tooltip-wrapper[' + OPEN_ATTR + '="1"]');
        if (!open) return null;
        return open.getAttribute('data-tooltip-for') || null;
    }

    function show(doc, name, trigger) {
        if (!doc || !name) return null;
        var wrapper = wrapperFor(doc, name);
        if (!wrapper) return null;
        var already = openNameOf(doc);
        if (already && already !== name) closeAll(doc);
        if (wrapper.classList) wrapper.classList.remove('hidden');
        if (wrapper.style) wrapper.style.display = 'block';
        wrapper.setAttribute(OPEN_ATTR, '1');
        place(wrapper, trigger);
        setExpanded(doc, name, true);
        return wrapper;
    }

    function toggle(doc, name, trigger) {
        if (openNameOf(doc) === name && lastTrigger === trigger) {
            closeAll(doc);
            return null;
        }
        lastTrigger = trigger;
        return show(doc, name, trigger);
    }

    function onDocumentClick(event) {
        var doc = pageDocument(event);
        if (!doc) return;
        var target = event.target;
        if (target && target.closest) {
            if (target.closest('.js-tooltip-close')) {
                closeAll(doc);
                return;
            }
            var trigger = target.closest('.js-tooltip-click');
            if (trigger) {
                var name = trigger.getAttribute('data-tooltip-name');
                toggle(doc, name, trigger);
                return;
            }
            if (target.closest('.js-tooltip-wrapper')) return;
        }
        closeAll(doc);
    }

    function onDocumentKey(event) {
        var doc = pageDocument(event);
        if (!doc) return;
        var key = event.key || event.keyCode;
        if (key === 'Escape' || key === 'Esc' || key === 27) {
            closeAll(doc);
            return;
        }
        var target = event.target;
        if (!target || !target.closest) return;
        var trigger = target.closest('.js-tooltip-click');
        if (!trigger) return;
        if (key === 'Enter' || key === ' ' || key === 13 || key === 32) {
            if (event.preventDefault) event.preventDefault();
            toggle(doc, trigger.getAttribute('data-tooltip-name'), trigger);
        }
    }

    function boot(doc) {
        var g = typeof globalThis !== 'undefined' ? globalThis : null;
        doc = doc || (g && g.document) || null;
        if (!doc) return;
        revealTriggers(doc);
        var root = doc.documentElement;
        if (root && typeof root.getAttribute === 'function' && root.getAttribute(ARMED_ATTR) === '1') {
            return;
        }
        if (root && typeof root.setAttribute === 'function') {
            root.setAttribute(ARMED_ATTR, '1');
        }
        if (doc.addEventListener) {
            doc.addEventListener('click', onDocumentClick);
            doc.addEventListener('keydown', onDocumentKey);
        }
    }

    return {
        boot: boot,
        show: show,
        closeAll: closeAll,
        openName: openNameOf,
        isHidden: isHidden
    };
}));
