/*
 * Lightweight article tool support for controls the API sends as static HTML.
 */
(function() {
    'use strict';

    function numberOrDefault(value, fallback) {
        var parsed = parseFloat(value);
        return isNaN(parsed) ? fallback : parsed;
    }

    function formatNumber(value) {
        var rounded = Math.round(value * 100) / 100;
        if (Math.abs(rounded) >= 100) {
            return Math.round(rounded).toLocaleString('en');
        }
        return String(rounded);
    }

    function parseRange(rangeText) {
        var match = String(rangeText || '').match(/^(-?\d+)\s*-\s*(-?\d+)$/);
        return match ? {
            min: parseInt(match[1], 10),
            max: parseInt(match[2], 10)
        } : {};
    }

    function clamp(value, min, max) {
        var result = value;
        if (typeof min === 'number' && !isNaN(min)) result = Math.max(min, result);
        if (typeof max === 'number' && !isNaN(max)) result = Math.min(max, result);
        return result;
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

    function currentCalculatorValues(root) {
        var values = {};
        root.querySelectorAll('[data-osrs-calculator-param]').forEach(function(row) {
            var input = row.querySelector('input, select');
            if (input) values[row.dataset.osrsCalculatorParam] = input.value;
        });
        return values;
    }

    function updateCombatResult(root, resultTarget) {
        if (!resultTarget) return;
        var values = currentCalculatorValues(root);
        var attack = numberOrDefault(values.attack, 1);
        var strength = numberOrDefault(values.strength, 1);
        var ranged = numberOrDefault(values.ranged, 1);
        var magic = numberOrDefault(values.magic, 1);
        var defence = numberOrDefault(values.defence, 1);
        var hitpoints = numberOrDefault(values.hitpoints, 10);
        var prayer = numberOrDefault(values.prayer, 1);

        var base = 0.25 * (defence + hitpoints + Math.floor(prayer / 2));
        var melee = 0.325 * (attack + strength);
        var range = 0.325 * Math.floor(1.5 * ranged);
        var mage = 0.325 * Math.floor(1.5 * magic);
        var level = Math.floor(base + Math.max(melee, range, mage));

        resultTarget.innerHTML = '<div class="osrs-calculator-result"><strong>Combat level:</strong> ' + level + '</div>';
    }

    function createNumberControl(param, onChange) {
        var range = parseRange(param.options);
        var row = document.createElement('label');
        row.className = 'osrs-calculator-row';
        row.dataset.osrsCalculatorParam = param.id;

        var label = document.createElement('span');
        label.className = 'osrs-calculator-label';
        label.textContent = param.label;

        var controls = document.createElement('span');
        controls.className = 'osrs-stepper';

        var decrement = document.createElement('button');
        decrement.type = 'button';
        decrement.textContent = '-';
        decrement.setAttribute('aria-label', 'Decrease ' + param.label);
        decrement.dataset.osrsCalculatorAction = 'decrement';

        var input = document.createElement('input');
        input.type = 'number';
        input.inputMode = 'numeric';
        input.value = param.initial || (typeof range.min === 'number' ? String(range.min) : '0');
        if (typeof range.min === 'number') input.min = String(range.min);
        if (typeof range.max === 'number') input.max = String(range.max);

        var increment = document.createElement('button');
        increment.type = 'button';
        increment.textContent = '+';
        increment.setAttribute('aria-label', 'Increase ' + param.label);
        increment.dataset.osrsCalculatorAction = 'increment';

        function step(delta) {
            var next = clamp(numberOrDefault(input.value, numberOrDefault(param.initial, 0)) + delta, range.min, range.max);
            input.value = String(next);
            onChange();
        }

        decrement.addEventListener('click', function() { step(-1); });
        increment.addEventListener('click', function() { step(1); });
        input.addEventListener('input', onChange);

        controls.appendChild(decrement);
        controls.appendChild(input);
        controls.appendChild(increment);
        row.appendChild(label);
        row.appendChild(controls);
        return row;
    }

    function createTextControl(param) {
        var row = document.createElement('label');
        row.className = 'osrs-calculator-row';
        row.dataset.osrsCalculatorParam = param.id;

        var label = document.createElement('span');
        label.className = 'osrs-calculator-label';
        label.textContent = param.label;

        var input = document.createElement('input');
        input.type = 'text';
        input.value = param.initial || '';

        row.appendChild(label);
        row.appendChild(input);

        if (param.type === 'hs' || param.type === 'rsn') {
            var lookup = document.createElement('button');
            lookup.type = 'button';
            lookup.textContent = 'Lookup';
            lookup.className = 'osrs-calculator-lookup';
            lookup.addEventListener('click', function() {
                input.focus();
            });
            row.appendChild(lookup);
        }

        return row;
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

    function prepareCalculatorLayout(pre, formTarget) {
        var formHost = formTarget.closest('table') || formTarget;
        if (formHost.closest('.osrs-calculator-layout')) return;

        var templates = findCalculatorTemplateBox(pre);
        var layout = document.createElement('div');
        layout.className = 'osrs-calculator-layout';
        formHost.parentNode.insertBefore(layout, templates || formHost);

        if (templates) {
            templates.classList.add('osrs-calculator-templates');
            layout.appendChild(templates);
        }
        layout.appendChild(formHost);
        pre.hidden = true;
    }

    function setupCalculator(pre) {
        var config = parseCalculatorConfig(pre);
        if (!config.form) return;

        var formTarget = document.getElementById(config.form);
        var resultTarget = config.result ? document.getElementById(config.result) : null;
        if (!formTarget || formTarget.dataset.osrsArticleToolReady === 'true') return;

        prepareCalculatorLayout(pre, formTarget);

        var panel = document.createElement('div');
        panel.className = 'osrs-calculator-panel';
        var title = document.createElement('h2');
        title.textContent = config.name || 'Calculator';
        panel.appendChild(title);

        var updateResult = function() {
            if ((config.template || '').toLowerCase().indexOf('combat level') >= 0) {
                updateCombatResult(panel, resultTarget);
            } else if (resultTarget) {
                resultTarget.innerHTML = '<div class="osrs-calculator-result">Calculator controls ready.</div>';
            }
        };

        config.params.forEach(function(param) {
            if (!param.id || param.type === 'hidden' || param.type === 'fixed') return;
            if (param.type === 'int' || param.type === 'number') {
                panel.appendChild(createNumberControl(param, updateResult));
            } else {
                panel.appendChild(createTextControl(param));
            }
        });

        formTarget.textContent = '';
        formTarget.appendChild(panel);
        formTarget.dataset.osrsArticleToolReady = 'true';
        updateResult();
    }

    function updateMoneyMakingValues(table, rate) {
        document.querySelectorAll('.mmg-kph.mmg-variable').forEach(function(element) {
            element.textContent = formatNumber(rate);
        });

        function directCoinChild(element) {
            for (var i = 0; i < element.children.length; i += 1) {
                if (element.children[i].classList.contains('coins')) {
                    return element.children[i];
                }
            }
            return null;
        }

        table.querySelectorAll('.mmg-varieswithkph').forEach(function(element) {
            if (element.classList.contains('mmg-itemline')) {
                var quantity = element.querySelector('.mmg-quantity');
                var cost = element.querySelector('.mmg-cost');
                if (quantity) {
                    quantity.textContent = formatNumber(numberOrDefault(quantity.dataset.mmgQty, 0) * rate);
                }
                if (cost) {
                    var costValue = numberOrDefault(cost.dataset.mmgCostPh, 0) + numberOrDefault(cost.dataset.mmgCostPk, 0) * rate;
                    var coins = cost.querySelector('.coins');
                    if (coins) coins.textContent = formatNumber(costValue);
                }
            } else if (element.classList.contains('mmg-xpline')) {
                var scp = element.querySelector('.scp');
                if (scp && scp.lastChild) {
                    scp.lastChild.nodeValue = ' ' + formatNumber(numberOrDefault(element.dataset.mmgXpPh, 0) + numberOrDefault(element.dataset.mmgXpPk, 0) * rate) + ' ';
                }
            } else {
                var value = numberOrDefault(element.dataset.mmgCostPh, 0) + numberOrDefault(element.dataset.mmgCostPk, 0) * rate;
                var coinValue = directCoinChild(element);
                if (coinValue) {
                    coinValue.textContent = formatNumber(value);
                } else {
                    element.textContent = formatNumber(value);
                }
            }
        });
    }

    function setupMoneyMakingControl(table) {
        if (table.dataset.osrsArticleToolReady === 'true') return;

        var defaultRate = numberOrDefault(table.dataset.defaultKph, 0);
        var labelText = table.dataset.defaultKphName || 'Rate per hour';
        var control = document.createElement('div');
        control.className = 'osrs-mmg-rate-control';

        var info = document.createElement('button');
        info.type = 'button';
        info.className = 'osrs-mmg-info osrs-icon-button';
        info.textContent = 'i';
        info.setAttribute('aria-label', labelText + ' information');
        info.title = labelText;

        var label = document.createElement('label');
        var labelTextElement = document.createElement('span');
        labelTextElement.className = 'osrs-mmg-label-text';
        labelTextElement.textContent = labelText;

        var input = document.createElement('input');
        input.type = 'number';
        input.min = '0';
        input.inputMode = 'numeric';
        input.value = String(defaultRate);

        var decrement = document.createElement('button');
        decrement.type = 'button';
        decrement.textContent = '-';
        decrement.setAttribute('aria-label', 'Decrease ' + labelText);
        decrement.className = 'osrs-icon-button';
        decrement.dataset.osrsMmgAction = 'decrement';

        var increment = document.createElement('button');
        increment.type = 'button';
        increment.textContent = '+';
        increment.setAttribute('aria-label', 'Increase ' + labelText);
        increment.className = 'osrs-icon-button';
        increment.dataset.osrsMmgAction = 'increment';

        var reset = document.createElement('button');
        reset.type = 'button';
        reset.className = 'osrs-mmg-reset osrs-icon-button';
        reset.dataset.osrsMmgAction = 'reset';
        reset.setAttribute('aria-label', 'Reset ' + labelText);
        reset.title = 'Reset ' + labelText;
        reset.innerHTML = '<svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d="M4 4v6h6"/><path d="M5 13a7 7 0 1 0 2-6l-3 3"/></svg>';

        function setRate(value) {
            input.value = String(Math.max(0, Math.round(value)));
            updateMoneyMakingValues(table, numberOrDefault(input.value, defaultRate));
        }

        decrement.addEventListener('click', function() { setRate(numberOrDefault(input.value, defaultRate) - 1); });
        increment.addEventListener('click', function() { setRate(numberOrDefault(input.value, defaultRate) + 1); });
        reset.addEventListener('click', function() { setRate(defaultRate); });
        input.addEventListener('input', function() { updateMoneyMakingValues(table, numberOrDefault(input.value, defaultRate)); });

        label.appendChild(labelTextElement);
        label.appendChild(input);
        control.appendChild(info);
        control.appendChild(label);
        control.appendChild(decrement);
        control.appendChild(increment);
        control.appendChild(reset);
        table.parentNode.insertBefore(control, table);
        table.dataset.osrsArticleToolReady = 'true';
        updateMoneyMakingValues(table, defaultRate);
    }

    function initialize() {
        // Calculator forms are owned by ext.gadget.calc-core. Replacing them here
        // broke every non-combat calculator. Layout wrapping lives in
        // osrs_calculator_runtime.js.
        document.querySelectorAll('table.mmg-table.mmg-isperkill').forEach(setupMoneyMakingControl);
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initialize);
    } else {
        initialize();
    }
})();
