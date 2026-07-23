(function() {
    'use strict';

    // Helper function to log to Android
    function log(message) {
        if (window.OsrsWikiBridge && typeof window.OsrsWikiBridge.log === 'function') {
            window.OsrsWikiBridge.log('[ClipboardBridge] ' + message);
        }
    }

    /**
     * Provide a clipboard API fallback using Android bridge
     */
    function setupClipboardBridge() {
        // Only set up bridge if Android ClipboardBridge is available
        if (typeof window.ClipboardBridge === 'undefined') {
            log('Android ClipboardBridge not available, skipping setup');
            return;
        }

        log('Setting up clipboard bridge...');

        // Create a custom clipboard object that uses Android bridge
        const androidClipboard = {
            writeText: function(text) {
                return new Promise(function(resolve, reject) {
                    try {
                        const success = window.ClipboardBridge.writeText(text);
                        if (success) {
                            log('Android clipboard writeText succeeded');
                            resolve();
                        } else {
                            log('Android clipboard writeText failed');
                            reject(new Error('Failed to write to clipboard'));
                        }
                    } catch (error) {
                        log('Android clipboard writeText error: ' + error.message);
                        reject(error);
                    }
                });
            },
            
            readText: function() {
                return new Promise(function(resolve, reject) {
                    try {
                        const text = window.ClipboardBridge.readText();
                        log('Android clipboard readText succeeded');
                        resolve(text);
                    } catch (error) {
                        log('Android clipboard readText error: ' + error.message);
                        reject(error);
                    }
                });
            }
        };

        // Store original clipboard for fallback
        const originalClipboard = navigator.clipboard;

        // Enhanced clipboard that uses Android bridge directly to avoid focus issues
        const enhancedClipboard = {
            writeText: function(text) {
                // Use Android bridge immediately to avoid document focus issues
                log('Clipboard writeText requested: ' + text + ' - using Android bridge directly');
                return androidClipboard.writeText(text);
            },
            
            readText: function() {
                // Use Android bridge immediately to avoid document focus issues
                log('Clipboard readText requested - using Android bridge directly');
                return androidClipboard.readText();
            }
        };

        // Replace navigator.clipboard with enhanced version
        try {
            Object.defineProperty(navigator, 'clipboard', {
                value: enhancedClipboard,
                writable: false,
                configurable: true
            });
            log('Successfully replaced navigator.clipboard with enhanced version');
        } catch (error) {
            log('Failed to replace navigator.clipboard: ' + error.message);
        }

        // Also expose on window for iframe access
        window.enhancedClipboard = enhancedClipboard;
        
        // Enhanced message listener for iframe clipboard requests
        window.addEventListener('message', function(event) {
            // Only handle messages from YouTube domains for security
            const allowedOrigins = [
                'https://www.youtube.com',
                'https://youtube.com', 
                'https://www.youtube-nocookie.com',
                'https://youtube-nocookie.com'
            ];
            
            const isYouTubeOrigin = allowedOrigins.some(function(origin) {
                return event.origin === origin || event.origin.endsWith('.youtube.com') || event.origin.endsWith('.youtube-nocookie.com');
            });
            
            if (!isYouTubeOrigin) {
                return; // Ignore messages from non-YouTube origins
            }
            
            if (event.data && event.data.type === 'clipboard-request') {
                log('Received clipboard request from YouTube iframe (' + event.origin + '): ' + event.data.action);
                
                if (event.data.action === 'writeText' && event.data.text) {
                    log('Processing clipboard writeText request: ' + event.data.text);
                    
                    enhancedClipboard.writeText(event.data.text).then(function() {
                        log('Clipboard writeText successful, notifying iframe');
                        // Notify iframe of success
                        event.source.postMessage({
                            type: 'clipboard-response',
                            success: true,
                            requestId: event.data.requestId
                        }, event.origin);
                    }).catch(function(error) {
                        log('Clipboard writeText failed: ' + error.message);
                        // Notify iframe of failure
                        event.source.postMessage({
                            type: 'clipboard-response',
                            success: false,
                            error: error.message,
                            requestId: event.data.requestId
                        }, event.origin);
                    });
                } else if (event.data.action === 'readText') {
                    log('Processing clipboard readText request');
                    
                    enhancedClipboard.readText().then(function(text) {
                        log('Clipboard readText successful');
                        // Notify iframe with clipboard content
                        event.source.postMessage({
                            type: 'clipboard-response',
                            success: true,
                            text: text,
                            requestId: event.data.requestId
                        }, event.origin);
                    }).catch(function(error) {
                        log('Clipboard readText failed: ' + error.message);
                        // Notify iframe of failure
                        event.source.postMessage({
                            type: 'clipboard-response',
                            success: false,
                            error: error.message,
                            requestId: event.data.requestId
                        }, event.origin);
                    });
                }
            }
            
            // Log any other messages from YouTube for debugging
            else if (event.data) {
                log('Received message from YouTube iframe: ' + JSON.stringify(event.data));
            }
        });
        
        log('Clipboard bridge setup complete');
    }

    /**
     * Inject clipboard bridge into existing iframes
     */
    function injectClipboardBridgeIntoIframes() {
        const iframes = document.querySelectorAll('iframe[src*="youtube"]');
        
        iframes.forEach(function(iframe, index) {
            try {
                log('Attempting to inject clipboard bridge into iframe ' + index);
                
                // Note: Due to cross-origin restrictions, we can't directly inject
                // JavaScript into YouTube iframes. The iframe will need to use
                // postMessage to communicate with our main window.
                
                // Instead, we'll monitor for clipboard-related errors and 
                // provide user feedback if needed
                
            } catch (error) {
                log('Could not inject into iframe ' + index + ': ' + error.message);
            }
        });
    }

    /**
     * Monitor for YouTube iframes and check their permission settings
     */
    function monitorYouTubeIframePermissions() {
        const checkIframePermissions = function() {
            const youtubeIframes = document.querySelectorAll('iframe[src*="youtube"]');
            
            youtubeIframes.forEach(function(iframe, index) {
                const allow = iframe.getAttribute('allow') || 'none';
                const sandbox = iframe.getAttribute('sandbox') || 'none';
                
                log('YouTube iframe ' + index + ' permissions - allow: ' + allow + ', sandbox: ' + sandbox);
                
                if (allow.includes('clipboard-write')) {
                    log('WARNING: YouTube iframe ' + index + ' still has clipboard-write permission');
                } else {
                    log('SUCCESS: YouTube iframe ' + index + ' clipboard-write permission removed');
                }
            });
        };
        
        // Check immediately
        checkIframePermissions();
        
        // Check again after delays to catch dynamically loaded iframes
        setTimeout(checkIframePermissions, 1000);
        setTimeout(checkIframePermissions, 3000);
    }

    /**
     * Monitor for YouTube iframe clipboard errors and provide user guidance
     */
    function monitorClipboardErrors() {
        // Listen for console messages that might indicate clipboard issues
        const originalConsoleError = console.error;
        console.error = function() {
            const message = Array.prototype.slice.call(arguments).join(' ');
            if (message.toLowerCase().includes('clipboard') || 
                message.toLowerCase().includes('copy')) {
                log('Detected clipboard error in console: ' + message);
            }
            originalConsoleError.apply(console, arguments);
        };
        
        // Also monitor console warnings for clipboard-related issues
        const originalConsoleWarn = console.warn;
        console.warn = function() {
            const message = Array.prototype.slice.call(arguments).join(' ');
            if (message.toLowerCase().includes('clipboard') || 
                message.toLowerCase().includes('copy')) {
                log('Detected clipboard warning in console: ' + message);
            }
            originalConsoleWarn.apply(console, arguments);
        };
    }

    // Initialize when DOM is ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', function() {
            setupClipboardBridge();
            injectClipboardBridgeIntoIframes();
            monitorYouTubeIframePermissions();
            monitorClipboardErrors();
        });
    } else {
        setupClipboardBridge();
        injectClipboardBridgeIntoIframes();
        monitorYouTubeIframePermissions();
        monitorClipboardErrors();
    }

    // Also initialize on window load
    window.addEventListener('load', function() {
        log('Window loaded, checking clipboard bridge and iframe permissions');
        
        // Test the clipboard bridge
        if (window.enhancedClipboard) {
            window.enhancedClipboard.writeText('test').then(function() {
                log('Clipboard bridge test successful');
            }).catch(function(error) {
                log('Clipboard bridge test failed: ' + error.message);
            });
        }
        
        // Check iframe permissions again after window load
        setTimeout(function() {
            monitorYouTubeIframePermissions();
        }, 1000);
    });

})();