(() => {
  let killed = false;

  function getVideoEl() {
    return document.querySelector("video");
  }

  function getTitle() {
    const h1 = document.querySelector("h1.ytd-watch-metadata yt-formatted-string");
    if (h1?.textContent?.trim()) return h1.textContent.trim();

    const t = document.title || "";
    return t.replace(/\s*-\s*YouTube\s*$/i, "").trim();
  }

  function getChannel() {
    const ch = document.querySelector("#channel-name #text a");
    if (ch?.textContent?.trim()) return ch.textContent.trim();
    return "";
  }

  function getUrl() {
    return location.href;
  }

  function getVideoId() {
    try {
      const url = new URL(location.href);

      // watch?v=VIDEOID
      const v = url.searchParams.get("v");
      if (v) return v;

      // shorts/VIDEOID
      const m1 = url.pathname.match(/^\/shorts\/([a-zA-Z0-9_-]{6,})/);
      if (m1?.[1]) return m1[1];

      // embed/VIDEOID
      const m2 = url.pathname.match(/^\/embed\/([a-zA-Z0-9_-]{6,})/);
      if (m2?.[1]) return m2[1];

      // fallback: sometimes YouTube sets canonical link
      const canon = document.querySelector('link[rel="canonical"]')?.href;
      if (canon) {
        const cu = new URL(canon);
        const cv = cu.searchParams.get("v");
        if (cv) return cv;

        const m3 = cu.pathname.match(/^\/shorts\/([a-zA-Z0-9_-]{6,})/);
        if (m3?.[1]) return m3[1];
      }
    } catch (_) {}

    return "";
  }

  function getThumbnailUrl() {
    const id = getVideoId();
    if (id) {
      // hqdefault is always there (maxres isn't guaranteed)
      return `https://i.ytimg.com/vi/${id}/hqdefault.jpg`;
    }

    // Fallback: og:image (can be stale in SPA)
    const og = document.querySelector('meta[property="og:image"]')?.content;
    if (og && og.startsWith("http")) return og;

    return "";
  }

  function safeSend(payload) {
    if (killed) return;
    try {
      chrome.runtime.sendMessage({ type: "YOUTUBE_NOWPLAYING", payload }, () => {
        void chrome.runtime?.lastError;
      });
    } catch (e) {
      killed = true;
      cleanup();
    }
  }

  // ---- Hook management ----
  let hookedVideo = null;
  let heartbeatTimer = null;
  let rehookTimer = null;
  let obs = null;

  let lastSentAt = 0;
  let lastKey = "";
  let lastPos = -1;

  function buildPayload(v) {
    return {
      source: "youtube",
      title: getTitle(),
      channel: getChannel(),
      url: getUrl(),
      videoId: getVideoId(),
      thumbnail: getThumbnailUrl(),
      duration: Number.isFinite(v.duration) ? v.duration : 0,
      position: Number.isFinite(v.currentTime) ? v.currentTime : 0,
      playing: !v.paused && !v.ended
    };
  }

  function maybeSend(v, force = false) {
    if (killed || !v) return;

    const now = Date.now();
    if (!force && now - lastSentAt < 350) return;

    const p = buildPayload(v);

    const key = `${p.url}|${p.videoId}|${p.title}|${p.channel}|${p.thumbnail}|${p.playing}|${Math.round(p.duration)}`;
    const posRounded = Math.floor(p.position);

    const changed =
      force ||
      key !== lastKey ||
      (p.playing && posRounded !== lastPos) ||
      (!p.playing && now - lastSentAt > 1500);

    if (!changed) return;

    lastKey = key;
    lastPos = posRounded;
    lastSentAt = now;

    safeSend(p);
  }

  function onVideoEvent() {
    const v = getVideoEl();
    if (v) maybeSend(v, true);
  }

  function unhookVideo() {
    if (!hookedVideo) return;
    const v = hookedVideo;

    try {
      ["timeupdate", "play", "pause", "seeking", "seeked", "ended", "loadedmetadata"].forEach((ev) => {
        v.removeEventListener(ev, onVideoEvent);
      });
    } catch (_) {}

    hookedVideo = null;
  }

  function hookVideo(v) {
    if (killed || !v) return;
    if (hookedVideo === v) return;

    unhookVideo();
    hookedVideo = v;

    try {
      ["timeupdate", "play", "pause", "seeking", "seeked", "ended", "loadedmetadata"].forEach((ev) => {
        v.addEventListener(ev, onVideoEvent, { passive: true });
      });
    } catch (_) {}

    maybeSend(v, true);
  }

  function rehookNow(forceSend = false) {
    if (killed) return;
    const v = getVideoEl();
    if (v) hookVideo(v);
    if (forceSend && v) maybeSend(v, true);
  }

  function setup() {
    document.addEventListener("yt-navigate-finish", () => {
      // thumbnail/title can lag slightly; poke a couple times
      setTimeout(() => rehookNow(true), 200);
      setTimeout(() => rehookNow(true), 900);
      setTimeout(() => rehookNow(true), 1800);
    });

    window.addEventListener("popstate", () => {
      setTimeout(() => rehookNow(true), 250);
    });

    document.addEventListener("visibilitychange", () => {
      if (!document.hidden) setTimeout(() => rehookNow(true), 150);
    });

    obs = new MutationObserver(() => rehookNow(false));
    obs.observe(document.documentElement, { childList: true, subtree: true });

    heartbeatTimer = setInterval(() => {
      const v = getVideoEl();
      if (v) maybeSend(v, false);
    }, 750);

    rehookTimer = setInterval(() => rehookNow(false), 3000);

    rehookNow(true);
  }

  function cleanup() {
    try {
      if (heartbeatTimer) clearInterval(heartbeatTimer);
      if (rehookTimer) clearInterval(rehookTimer);
      heartbeatTimer = null;
      rehookTimer = null;

      unhookVideo();

      if (obs) obs.disconnect();
      obs = null;
    } catch (_) {}
  }

  setup();
})();
