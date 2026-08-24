/**
 * iOS MapLibre Bridge - equivalent to Android's OsrsWikiBridge
 * Provides JavaScript-to-native communication for map functionality
 */
(function() {
    'use strict';
    
    console.log('🟢 [MAP_BRIDGE] Script executing at:', new Date().toISOString());
    console.log('🟢 [MAP_BRIDGE] Document ready state:', document.readyState);
    console.log('🟢 [MAP_BRIDGE] Window object:', typeof window);
    
    var existingBridge = window.OsrsWikiBridge || {};

    // Create OsrsWikiBridge equivalent for iOS MapLibre integration.
    // Preserve fetchText from the documentStart / inline bridge — replacing
    // the whole object used to drop it and leave GE charts on CORS fetch().
    window.OsrsWikiBridge = {
        onMapPlaceholderMeasured: function(id, rectJson, mapDataJson) {
            console.log('🟢 [MAP_BRIDGE] onMapPlaceholderMeasured called with id:', id);
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mapBridge) {
                window.webkit.messageHandlers.mapBridge.postMessage({
                    action: 'onMapPlaceholderMeasured',
                    id: id,
                    rectJson: rectJson,
                    mapDataJson: mapDataJson
                });
                console.log('🟢 [MAP_BRIDGE] Message sent to native Swift layer');
            } else {
                console.error('🔴 [MAP_BRIDGE] webkit.messageHandlers.mapBridge not available!');
            }
        },
        
        onCollapsibleToggled: function(mapId, isOpening) {
            console.log('🚨 [BRIDGE] onCollapsibleToggled called:', mapId, isOpening);
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mapBridge) {
                window.webkit.messageHandlers.mapBridge.postMessage({
                    action: 'onCollapsibleToggled',
                    mapId: mapId,
                    isOpening: isOpening
                });
            } else {
                console.error('🚨 [BRIDGE] webkit.messageHandlers.mapBridge not available');
            }
        },
        
        setHorizontalScroll: function(inProgress) {
            console.log('🚨 [BRIDGE] setHorizontalScroll called:', inProgress);
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mapBridge) {
                window.webkit.messageHandlers.mapBridge.postMessage({
                    action: 'setHorizontalScroll',
                    inProgress: inProgress
                });
            } else {
                console.error('🚨 [BRIDGE] webkit.messageHandlers.mapBridge not available');
            }
        },

        setHorizontalScrollGesture: function(phase, gestureId, ownerId, isLocalOwner) {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mapBridge) {
                window.webkit.messageHandlers.mapBridge.postMessage({
                    action: 'setHorizontalScrollGesture',
                    phase: phase,
                    gestureId: gestureId,
                    ownerId: ownerId || '',
                    isLocalOwner: !!isLocalOwner
                });
            }
        },
        
        log: function(message) {
            console.log('🚨 [BRIDGE] log called:', message);
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mapBridge) {
                window.webkit.messageHandlers.mapBridge.postMessage({
                    action: 'log',
                    message: message
                });
            } else {
                console.error('🚨 [BRIDGE] webkit.messageHandlers.mapBridge not available');
            }
        },

        openFloorNumberingSettings: function() {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mapBridge) {
                window.webkit.messageHandlers.mapBridge.postMessage({
                    action: 'openFloorNumberingSettings'
                });
            }
        },

        fetchText: (typeof existingBridge.fetchText === 'function') ? existingBridge.fetchText : function(url) {
            try {
                var xhr = new XMLHttpRequest();
                xhr.open('GET', url, false);
                xhr.setRequestHeader('Accept', 'application/json');
                xhr.send(null);
                return (xhr.status >= 200 && xhr.status < 300) ? (xhr.responseText || '') : '';
            } catch (e) {
                return '';
            }
        }
    };
    
    // Debug: Log that bridge is ready
    console.log('🟢 [MAP_BRIDGE] OsrsWikiBridge initialized successfully');
    console.log('🟢 [MAP_BRIDGE] Bridge object type:', typeof window.OsrsWikiBridge);
    console.log('🟢 [MAP_BRIDGE] Available methods:', Object.keys(window.OsrsWikiBridge));
    
    // Test bridge connectivity immediately
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mapBridge) {
        console.log('🟢 [MAP_BRIDGE] Testing bridge connection...');
        window.OsrsWikiBridge.log('MAP_BRIDGE_LOADED_SUCCESSFULLY');
    } else {
        console.error('🔴 [MAP_BRIDGE] CRITICAL: Bridge connection not available!');
        console.log('🔴 [MAP_BRIDGE] webkit available:', !!window.webkit);
        console.log('🔴 [MAP_BRIDGE] messageHandlers available:', !!(window.webkit && window.webkit.messageHandlers));
        console.log('🔴 [MAP_BRIDGE] Available handlers:', window.webkit && window.webkit.messageHandlers ? Object.keys(window.webkit.messageHandlers) : 'none');
    }
})();
