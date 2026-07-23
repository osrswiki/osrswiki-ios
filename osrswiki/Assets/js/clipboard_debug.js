(function() {
    'use strict';

    // Helper function to log to Android
    function log(message) {
        if (window.OsrsWikiBridge && typeof window.OsrsWikiBridge.log === 'function') {
            window.OsrsWikiBridge.log('[ClipboardDebug] ' + message);
        }
    }

    /**
     * Test clipboard API availability and log results
     */
    function testClipboardAPI() {
        log('Testing clipboard API availability...');
        
        // Test if navigator.clipboard exists
        if (typeof navigator !== 'undefined' && navigator.clipboard) {
            log('navigator.clipboard exists');
            
            // Test if writeText method exists
            if (typeof navigator.clipboard.writeText === 'function') {
                log('navigator.clipboard.writeText is available');
                
                // Test if we can actually use it (this might fail due to permissions)
                navigator.clipboard.writeText('test').then(function() {
                    log('Clipboard test write successful');
                }).catch(function(error) {
                    log('Clipboard test write failed: ' + error.message);
                });
            } else {
                log('navigator.clipboard.writeText is NOT available');
            }
            
            // Test if readText method exists
            if (typeof navigator.clipboard.readText === 'function') {
                log('navigator.clipboard.readText is available');
            } else {
                log('navigator.clipboard.readText is NOT available');
            }
        } else {
            log('navigator.clipboard does NOT exist');
        }
        
        // Test document.execCommand fallback
        if (typeof document !== 'undefined' && typeof document.execCommand === 'function') {
            log('document.execCommand is available as fallback');
        } else {
            log('document.execCommand is NOT available');
        }
        
        // Test secure context
        if (typeof window !== 'undefined' && window.isSecureContext !== undefined) {
            log('Window secure context: ' + window.isSecureContext);
        } else {
            log('Cannot determine secure context');
        }
        
        // Test if we're in an iframe
        if (typeof window !== 'undefined' && window.parent !== window) {
            log('Running inside iframe - this may affect clipboard access');
        } else {
            log('Running in main window context');
        }
    }

    /**
     * Monitor for YouTube iframe loads and test clipboard access
     */
    function monitorYouTubeIframes() {
        // Test immediately
        testClipboardAPI();
        
        // Test again after a delay to catch any changes
        setTimeout(testClipboardAPI, 2000);
        
        // Monitor for new iframe additions
        if (typeof MutationObserver !== 'undefined') {
            const observer = new MutationObserver(function(mutations) {
                mutations.forEach(function(mutation) {
                    if (mutation.type === 'childList') {
                        mutation.addedNodes.forEach(function(node) {
                            if (node.nodeType === Node.ELEMENT_NODE) {
                                const iframes = node.tagName === 'IFRAME' ? [node] : 
                                               node.querySelectorAll ? Array.from(node.querySelectorAll('iframe')) : [];
                                
                                iframes.forEach(function(iframe) {
                                    if (iframe.src && iframe.src.includes('youtube')) {
                                        log('New YouTube iframe detected: ' + iframe.src);
                                        // Test clipboard API again when new YouTube iframe loads
                                        setTimeout(testClipboardAPI, 1000);
                                    }
                                });
                            }
                        });
                    }
                });
            });
            
            observer.observe(document.body, {
                childList: true,
                subtree: true
            });
        }
    }

    // Initialize when DOM is ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', monitorYouTubeIframes);
    } else {
        monitorYouTubeIframes();
    }

    // Also run on window load
    window.addEventListener('load', function() {
        log('Window loaded, running clipboard API test');
        setTimeout(testClipboardAPI, 500);
    });

})();