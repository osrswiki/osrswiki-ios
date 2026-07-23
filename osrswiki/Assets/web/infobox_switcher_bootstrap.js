window.rswiki = {
    initQtyBox: function() {}
};

function safeLog(message, isError = false) {
    const logMessage = '[Switcher Bootstrap] ' + message;
    if (isError) {
        console.error(logMessage);
    } else {
        console.log(logMessage);
    }
    try {
        if (typeof OsrsWikiBridge !== 'undefined' && OsrsWikiBridge.log) {
            OsrsWikiBridge.log('Gadget Log: ' + message);
        }
    } catch (e) {
        // Bridge may not be available. This is expected during initial load.
    }
}

// Only create minimal mw object if none exists (shared compatibility layer should create the full one)
if (typeof window.mw === 'undefined') {
    window.mw = {
        log: function(message) {
            safeLog(JSON.stringify(message));
        },
        hook: function(eventName) {
            return {
                add: function(callback) {
                    if (eventName === 'wikipage.content') {
                        safeLog('mw.hook.add called. Storing callback.');
                        window.infoboxSwitcherCallback = callback;
                    }
                },
                fire: function() {}
            };
        }
    };
} else {
    // Extend existing mw object with hook functionality if needed
    if (!window.mw.hook) {
        window.mw.hook = function(eventName) {
            return {
                add: function(callback) {
                    if (eventName === 'wikipage.content') {
                        safeLog('mw.hook.add called. Storing callback.');
                        window.infoboxSwitcherCallback = callback;
                    }
                },
                fire: function() {}
            };
        };
    }
}

function initializeInfoboxSwitcher() {
    safeLog('Initializer called.');
    if (typeof window.infoboxSwitcherCallback === 'function') {
        safeLog('Dependencies met. Firing callback now.');
        try {
            window.infoboxSwitcherCallback(document);
            safeLog('Callback fired successfully.');
        } catch (e) {
            safeLog('ERROR firing callback: ' + e.message, true);
        }
    } else {
        var status = 'callback=' + (typeof window.infoboxSwitcherCallback);
        safeLog('Dependencies not met (' + status + '). Retrying in 100ms...');
        setTimeout(initializeInfoboxSwitcher, 100);
    }
}
