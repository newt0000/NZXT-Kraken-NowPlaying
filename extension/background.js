chrome.runtime.onMessage.addListener((msg, sender) => {
  if (msg?.type !== "YOUTUBE_NOWPLAYING") return;

  fetch("http://127.0.0.1:27123/update", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(msg.payload)
  }).catch(() => {
    // server might be down; silently ignore
  });
});
