/**
 * In-article TimedMediaHandler audio: prefer the saved MPEG transcode, paint a
 * non-zero control, and leave loading with an explicit error instead of spinning.
 */
(function (global) {
  'use strict';

  var osrsArticleAudioLoadingTimeoutMs = 8000;
  global.osrsArticleAudioLoadingTimeoutMs = osrsArticleAudioLoadingTimeoutMs;

  function preferredMpegSource(audio) {
    if (!audio || !audio.querySelectorAll) return null;
    var sources = audio.querySelectorAll('source');
    for (var i = 0; i < sources.length; i++) {
      var type = (sources[i].getAttribute('type') || '').toLowerCase();
      var src = sources[i].getAttribute('src') || '';
      if (type.indexOf('audio/mpeg') === 0 || /\.mp3(\?|#|$)/i.test(src)) {
        return sources[i];
      }
    }
    return null;
  }

  function showError(wrap, audio, errorEl) {
    if (!wrap) return;
    wrap.classList.add('is-error');
    if (errorEl) {
      errorEl.hidden = false;
      errorEl.style.display = 'block';
    }
    if (audio) {
      try { audio.pause(); } catch (e) {}
    }
  }

  function enhanceAudio(audio) {
    if (!audio || audio.dataset.osrsArticleAudio === '1') return;
    audio.dataset.osrsArticleAudio = '1';

    var mpeg = preferredMpegSource(audio);
    if (mpeg && mpeg.parentNode === audio) {
      audio.insertBefore(mpeg, audio.firstChild);
    }

    var parent = audio.parentNode;
    if (!parent) return;
    var wrap = document.createElement('div');
    wrap.className = 'osrs-article-audio';
    parent.insertBefore(wrap, audio);
    wrap.appendChild(audio);

    var playBtn = document.createElement('button');
    playBtn.type = 'button';
    playBtn.className = 'osrs-article-audio-play';
    playBtn.textContent = 'Play';
    playBtn.setAttribute('aria-label', 'Play audio');
    playBtn.style.cssText = [
      'display:inline-block',
      'margin:0 0 0.35em',
      'padding:0.45em 0.9em',
      'min-height:44px',
      'min-width:88px',
      'font:inherit',
      'font-weight:600',
      'border:1px solid var(--body-border, #94866d)',
      'border-radius:6px',
      'background:var(--body-light, #d8ccb4)',
      'color:var(--text-color, #000)',
      'cursor:pointer'
    ].join(';');
    playBtn.addEventListener('click', function () {
      audio.dataset.osrsPlayAttempted = '1';
      var mpegNow = preferredMpegSource(audio);
      if (mpegNow) {
        var mpegSrc = mpegNow.getAttribute('src');
        if (mpegSrc) audio.src = mpegSrc;
      }
      var start = audio.play();
      if (start && typeof start.catch === 'function') {
        start.catch(function () {
          showError(wrap, audio, errorEl);
        });
      }
    });
    wrap.insertBefore(playBtn, audio);

    var errorEl = document.createElement('div');
    errorEl.className = 'osrs-article-audio-error';
    errorEl.setAttribute('role', 'status');
    errorEl.textContent = 'Audio unavailable';
    errorEl.hidden = true;
    errorEl.style.display = 'none';
    errorEl.style.margin = '0.35em 0';
    errorEl.style.fontSize = '0.9em';
    wrap.appendChild(errorEl);

    if (!audio.hasAttribute('controls')) {
      audio.setAttribute('controls', '');
    }

    var timer = null;
    function clearLoadingTimer() {
      if (timer) {
        clearTimeout(timer);
        timer = null;
      }
    }
    function markPlayAttempt() {
      audio.dataset.osrsPlayAttempted = '1';
    }
    function armLoadingTimeout() {
      if (audio.dataset.osrsPlayAttempted !== '1') return;
      clearLoadingTimer();
      timer = setTimeout(function () {
        if (audio.readyState < 2 && !audio.ended) {
          showError(wrap, audio, errorEl);
        }
      }, osrsArticleAudioLoadingTimeoutMs);
    }

    audio.addEventListener('play', function () {
      markPlayAttempt();
      armLoadingTimeout();
    });
    audio.addEventListener('error', function () {
      if (audio.dataset.osrsPlayAttempted !== '1') return;
      clearLoadingTimer();
      showError(wrap, audio, errorEl);
    });
    audio.addEventListener('waiting', armLoadingTimeout);
    audio.addEventListener('stalled', armLoadingTimeout);
    audio.addEventListener('playing', clearLoadingTimer);
    audio.addEventListener('canplay', clearLoadingTimer);
    audio.addEventListener('loadeddata', clearLoadingTimer);
  }

  function enhance(root) {
    var scope = root || (typeof document !== 'undefined' ? document : null);
    if (!scope || !scope.querySelectorAll) return;
    var nodes = scope.querySelectorAll(
      '.infobox-media-player audio, audio.mw-file-element, .musicplayer audio, audio[controls]'
    );
    for (var i = 0; i < nodes.length; i++) {
      enhanceAudio(nodes[i]);
    }
  }

  global.OSRSArticleAudio = {
    preferredMpegSource: preferredMpegSource,
    enhance: enhance
  };

  if (typeof document !== 'undefined') {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', function () { enhance(document); });
    } else {
      enhance(document);
    }
  }
})(typeof window !== 'undefined' ? window : globalThis);
