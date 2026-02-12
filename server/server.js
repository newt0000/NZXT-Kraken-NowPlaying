import express from "express";

const app = express();
const PORT = 27123;

// In-memory state
let state = {
  source: "youtube",
  title: "",
  channel: "",
  url: "",
  thumbnail: "",
  duration: 0,
  position: 0,
  playing: false,
  updatedAt: Date.now()
};

app.use(express.json({ limit: "100kb" }));

// Allow CAM/Chromium + extension to talk to localhost
app.use((req, res, next) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  if (req.method === "OPTIONS") return res.sendStatus(200);
  next();
});

// Extension POSTs updates here
app.post("/update", (req, res) => {
  const body = req.body ?? {};

  state = {
    ...state,
    ...body,
    updatedAt: Date.now()
  };

  res.json({ ok: true });
});

// Kraken page polls this
app.get("/nowplaying", (req, res) => {
  res.json(state);
});

// Kraken UI page
app.get("/", (req, res) => {
  res.type("html").send(`<!doctype html>
<html>
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width,height=device-height,initial-scale=1"/>
  <title>Kraken YouTube Now Playing</title>
  <style>
    html, body {
      margin:0; padding:0; width:100%; height:100%;
      background:#000; color:#fff;
      font-family: system-ui, -apple-system, Segoe UI, Roboto, Arial;
      overflow:hidden;
    }

    .wrap {
      width:100%; height:100%;
      display:flex; align-items:center; justify-content:center;
      position:relative;
      overflow:hidden;
    }

    .bg {
      position:absolute;
      inset:-30px; /* bleed so blur doesn't show edges */
      background-size:cover;
      background-position:center;
      filter: blur(2px);
      transform: scale(1.08);
      opacity: 0.95;
    }

    .bgShade {
      position:absolute;
      inset:0;
      background: radial-gradient(circle at center,
        rgba(0,0,0,0.25) 0%,
        rgba(0,0,0,0.65) 62%,
        rgba(0,0,0,0.88) 100%);
    }

    canvas { width:100%; height:100%; position:relative; }

    .center {
      position:absolute; inset:0;
      display:flex; align-items:center; justify-content:center;
      flex-direction:column;
      text-align:center;
      padding:36px;
      gap:10px;
      z-index: 2;
    }

    .title {
      font-size:28px;
      font-weight:700;
      line-height:1.15;
      display:-webkit-box;
      -webkit-line-clamp:3;
      -webkit-box-orient:vertical;
      overflow:hidden;
      text-shadow: 0 2px 14px rgba(0,0,0,0.6);
    }

    .meta {
      font-size:18px;
      opacity:.86;
      white-space:nowrap;
      overflow:hidden;
      text-overflow:ellipsis;
      max-width:90%;
      text-shadow: 0 2px 14px rgba(0,0,0,0.6);
    }

    .time {
      font-size:18px;
      opacity:.92;
      text-shadow: 0 2px 14px rgba(0,0,0,0.6);
    }

    .badge {
      position:absolute;
      bottom:14px;
      left:0; right:0;
      text-align:center;
      font-size:14px;
      opacity:.65;
      z-index: 2;
      text-shadow: 0 2px 14px rgba(0,0,0,0.6);
    }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="bg" id="bg"></div>
    <div class="bgShade"></div>

    <canvas id="ring"></canvas>

    <div class="center">
      <div class="title" id="title">Nothing playing</div>
      <div class="meta" id="channel"></div>
      <div class="time" id="time"></div>
    </div>

    <div class="badge" id="badge"></div>
  </div>

  <script>
    const canvas = document.getElementById("ring");
    const ctx = canvas.getContext("2d");

    const bgEl = document.getElementById("bg");
    const titleEl = document.getElementById("title");
    const channelEl = document.getElementById("channel");
    const timeEl = document.getElementById("time");
    const badgeEl = document.getElementById("badge");

    function resize() {
      canvas.width = Math.floor(window.innerWidth * devicePixelRatio);
      canvas.height = Math.floor(window.innerHeight * devicePixelRatio);
    }
    window.addEventListener("resize", resize);
    resize();

    function fmt(sec) {
      sec = Math.max(0, Math.floor(sec || 0));
      const m = Math.floor(sec / 60);
      const s = sec % 60;
      return m + ":" + String(s).padStart(2, "0");
    }

    function drawRing(progress, playing) {
      const w = canvas.width, h = canvas.height;
      ctx.clearRect(0, 0, w, h);

      const cx = w / 2, cy = h / 2;
      const r = Math.min(w, h) * 0.42;
      const thickness = Math.max(10, Math.min(w, h) * 0.03);

      // background ring
      ctx.lineWidth = thickness;
      ctx.beginPath();
      ctx.strokeStyle = "rgba(255,255,255,0.12)";
      ctx.arc(cx, cy, r, 0, Math.PI * 2);
      ctx.stroke();

      // progress ring
      const start = -Math.PI / 2;
      const end = start + (Math.PI * 2 * progress);

      ctx.beginPath();
      ctx.strokeStyle = playing ? "rgba(255,255,255,0.95)" : "rgba(255,255,255,0.55)";
      ctx.lineCap = "round";
      ctx.arc(cx, cy, r, start, end);
      ctx.stroke();
    }

    async function tick() {
      try {
        const res = await fetch("/nowplaying", { cache: "no-store" });
        const data = await res.json();

        const staleMs = Date.now() - (data.updatedAt || 0);
        const stale = staleMs > 15000; // 15s tolerance

        // background thumbnail
        if (data.thumbnail && typeof data.thumbnail === "string" && data.thumbnail.startsWith("http")) {
          bgEl.style.backgroundImage = "url(\\"" + data.thumbnail.replace(/"/g, '\\"') + "\\")";
        } else {
          bgEl.style.backgroundImage = "none";
        }

        const title = data.title || "Nothing playing";
        titleEl.textContent = title;
        channelEl.textContent = data.channel ? data.channel : "";

        const dur = Number(data.duration || 0);
        const pos = Number(data.position || 0);
        const playing = !!data.playing && !stale;

        if (dur > 0) {
          timeEl.textContent = fmt(pos) + " / " + fmt(dur);
        } else {
          timeEl.textContent = "";
        }

        const progress = (dur > 0) ? Math.min(1, Math.max(0, pos / dur)) : 0;
        drawRing(progress, playing);

        badgeEl.textContent = stale ? "Waiting for YouTube..." : (playing ? "Playing" : "Paused");
      } catch (e) {
        titleEl.textContent = "Server running, no data";
        channelEl.textContent = "";
        timeEl.textContent = "";
        badgeEl.textContent = "Waiting for YouTube...";
        bgEl.style.backgroundImage = "none";
        drawRing(0, false);
      }
    }

    setInterval(tick, 250);
    tick();
  </script>
</body>
</html>`);
});

app.listen(PORT, "127.0.0.1", () => {
  console.log(`NowPlaying server: http://127.0.0.1:${PORT}/`);
});
