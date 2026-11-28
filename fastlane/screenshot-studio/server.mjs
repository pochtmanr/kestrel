// Kestrel Screenshot Studio — local App Store screenshot generator.
//   node server.mjs            → http://localhost:4547
// No npm dependencies: Node's http server + Playwright's cached headless Chromium over CDP.

import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { renderSlide } from "./render.mjs";

const ROOT = path.dirname(fileURLToPath(import.meta.url));
// 4547, not Doppler's 4545: localStorage is per origin, and the studios store different variant keys.
const PORT = Number(process.env.PORT || 4547);
const METADATA = path.join(ROOT, "..", "metadata");
const ASSETS = path.join(ROOT, "assets");
const OUT = path.join(ROOT, "out");
const FONTS = { "SFNS.ttf": "/System/Library/Fonts/SFNS.ttf", "NewYork.ttf": "/System/Library/Fonts/NewYork.ttf" };

const readJSON = (p, fallback) => { try { return JSON.parse(fs.readFileSync(p, "utf8")); } catch { return fallback; } };
const project = () => readJSON(path.join(ROOT, "project.json"));
// Store locales are the folders in ../metadata (en-US, de-DE, …); review_information and the like are not locales.
const locales = () => fs.readdirSync(METADATA)
  .filter((d) => /^[a-z]{2,3}(-[A-Za-z]{2,4})?$/.test(d) && fs.statSync(path.join(METADATA, d)).isDirectory()).sort();
const copyFile = (loc) => path.join(ROOT, "copy", `${loc}.json`);
const safe = (s) => /^[A-Za-z0-9._-]+$/.test(s || "");

// Same English copy for en-GB/AU/CA unless they get their own file.
const COPY_FALLBACK = { "en-GB": "en-US", "en-AU": "en-US", "en-CA": "en-US", "fr-CA": "fr-FR", "es-MX": "es-ES", "pt-PT": "pt-BR" };

function copyFor(loc, key) {
  const own = readJSON(copyFile(loc), {})[key];
  if (own && own.title) return { copy: own, missing: false };
  const alt = COPY_FALLBACK[loc] && readJSON(copyFile(COPY_FALLBACK[loc]), {})[key];
  if (alt && alt.title) return { copy: alt, missing: false };
  return { copy: readJSON(copyFile("en-US"), {})[key], missing: loc !== "en-US" };
}

// The slides one variant shows on one device; `skip` in a variant leaves slides out.
function slidesFor(p, dk, v) {
  const va = p.variants[v] || {};
  return p.devices[dk].slides.filter((s) => !(va.skip || []).includes(s.id));
}

// Width × height from a PNG's IHDR chunk, without decoding it.
function pngSize(file) {
  try {
    const fd = fs.openSync(file, "r");
    const b = Buffer.alloc(24);
    fs.readSync(fd, b, 0, 24, 0);
    fs.closeSync(fd);
    if (b.toString("latin1", 1, 4) !== "PNG") return null;
    return [b.readUInt32BE(16), b.readUInt32BE(20)];
  } catch { return null; }
}

// A locale's own screenshot, else the English one.
function shotFor(loc, device, id) {
  for (const l of [loc, "en-US"]) {
    const p = path.join(ASSETS, "shots", l, device, `${id}.png`);
    if (fs.existsSync(p)) return { url: `/assets/shots/${l}/${device}/${id}.png?v=${fs.statSync(p).mtimeMs | 0}`, own: l === loc, size: pngSize(p) };
  }
  return null;
}

// The frame follows the raw shot's real aspect when it has the expected orientation; a shot taken in
// the wrong orientation keeps the configured frame (object-fit: cover crops it) and shows up in status.
function usableSize(device, size) {
  if (!size) return null;
  const want = device.shot[1] > device.shot[0], got = size[1] > size[0];
  return want === got ? size : null;
}

function status() {
  const p = project();
  const out = {};
  for (const loc of locales()) {
    const s = { copyMissing: [], shotsOwn: 0, shotsFallback: 0, shotsMissing: [], own: [], sizeMismatch: [] };
    const keys = new Set();
    for (const [dk, d] of Object.entries(p.devices)) for (const sl of d.slides) {
      keys.add(sl.copy);
      const id = sl.shot || sl.id;
      const sh = shotFor(loc, dk, id);
      if (!sh) s.shotsMissing.push(`${dk}/${id}`);
      else {
        if (sh.own) { s.shotsOwn++; s.own.push(`${dk}/${sl.id}`); } else s.shotsFallback++;
        if (sh.size && (sh.size[0] !== d.shot[0] || sh.size[1] !== d.shot[1])) s.sizeMismatch.push(`${dk}/${id} ${sh.size.join("×")}`);
      }
    }
    s.shotsMissing = [...new Set(s.shotsMissing)];
    s.sizeMismatch = [...new Set(s.sizeMismatch)];
    for (const k of keys) if (copyFor(loc, k).missing) s.copyMissing.push(k);
    out[loc] = s;
  }
  return out;
}

function renderPage(q) {
  const p = project();
  const dk = q.get("device");
  const device = p.devices[dk];
  const variant = q.get("variant") || Object.keys(p.variants)[0];
  const slide = device && p.variants[variant] && slidesFor(p, dk, variant).find((s) => s.id === q.get("slide"));
  const loc = q.get("locale") || "en-US";
  if (!slide) return null;
  const { copy, missing } = copyFor(loc, slide.copy);
  const shot = shotFor(loc, dk, slide.shot || slide.id);
  return renderSlide({
    project: p, deviceKey: dk, slide, variantKey: variant, locale: loc, copy, copyMissing: missing,
    shotUrl: shot?.url, shotSize: usableSize(device, shot?.size), fontBase: "/fonts",
  });
}

// ---------- headless Chromium over CDP ----------
function findChrome() {
  if (process.env.CHROME) return process.env.CHROME;
  const base = path.join(os.homedir(), "Library/Caches/ms-playwright");
  const dirs = fs.existsSync(base) ? fs.readdirSync(base).filter((d) => d.startsWith("chromium_headless_shell")).sort().reverse() : [];
  for (const d of dirs) {
    const p = path.join(base, d, "chrome-headless-shell-mac-arm64", "chrome-headless-shell");
    if (fs.existsSync(p)) return p;
  }
  throw new Error("No headless Chromium found. Run `npx playwright install chromium-headless-shell` or set CHROME=/path/to/chrome.");
}

async function launchBrowser() {
  const proc = spawn(findChrome(), ["--headless", "--remote-debugging-port=0", "--hide-scrollbars", "--no-first-run",
    "--force-color-profile=srgb", `--user-data-dir=${fs.mkdtempSync(path.join(os.tmpdir(), "kestrel-shots-"))}`], { stdio: ["ignore", "ignore", "pipe"] });
  const wsUrl = await new Promise((res, rej) => {
    let buf = "";
    proc.stderr.on("data", (d) => { buf += d; const m = buf.match(/ws:\/\/\S+/); if (m) res(m[0]); });
    proc.on("exit", () => rej(new Error("Chromium exited: " + buf.slice(-400))));
  });
  const ws = new WebSocket(wsUrl);
  await new Promise((r) => ws.addEventListener("open", r, { once: true }));
  let id = 0; const pending = new Map(); const waiters = [];
  ws.addEventListener("message", (e) => {
    const m = JSON.parse(e.data);
    if (m.id && pending.has(m.id)) { const { res, rej } = pending.get(m.id); pending.delete(m.id); m.error ? rej(new Error(m.error.message)) : res(m.result); }
    else if (m.method) for (const w of [...waiters]) if (w.method === m.method && w.sessionId === m.sessionId) { waiters.splice(waiters.indexOf(w), 1); w.res(m.params); }
  });
  const send = (method, params = {}, sessionId) => new Promise((res, rej) => { const i = ++id; pending.set(i, { res, rej }); ws.send(JSON.stringify({ id: i, method, params, sessionId })); });
  const once = (method, sessionId) => new Promise((res) => waiters.push({ method, sessionId, res }));
  async function newPage() {
    const { targetId } = await send("Target.createTarget", { url: "about:blank" });
    const { sessionId } = await send("Target.attachToTarget", { targetId, flatten: true });
    await send("Page.enable", {}, sessionId);
    return {
      async shoot(url, w, h, format) {
        await send("Emulation.setDeviceMetricsOverride", { width: w, height: h, deviceScaleFactor: 1, mobile: false }, sessionId);
        const loaded = once("Page.loadEventFired", sessionId);
        await send("Page.navigate", { url }, sessionId);
        await loaded;
        await send("Runtime.evaluate", { expression: "new Promise(r=>{const t=()=>window.__ready?r(1):setTimeout(t,30);t()})", awaitPromise: true }, sessionId);
        const { data } = await send("Page.captureScreenshot", format === "png"
          ? { format: "png", clip: { x: 0, y: 0, width: w, height: h, scale: 1 } }
          : { format: "jpeg", quality: 93, clip: { x: 0, y: 0, width: w, height: h, scale: 1 } }, sessionId);
        return Buffer.from(data, "base64");
      },
    };
  }
  return { newPage, close: () => { try { ws.close(); } catch {} proc.kill(); } };
}

// out/<variant>/ios/<locale>/iphone_01_home.jpg (and ipad_…), out/<variant>/duo/<locale>/duo_01_home.jpg.
// ios/ is the folder layout fastlane deliver reads; duo/ goes up through the upload_duo_screenshots lane.
async function exportShots({ variants, devices, locales: locs, format }, write) {
  const p = project();
  const jobs = [];
  for (const v of variants) for (const loc of locs) for (const dk of devices) {
    const d = p.devices[dk];
    slidesFor(p, dk, v).forEach((sl, i) => {
      const n = String(i + 1).padStart(2, "0");
      jobs.push({
        url: `http://localhost:${PORT}/render?device=${dk}&slide=${sl.id}&variant=${v}&locale=${loc}`,
        file: path.join(OUT, v, d.folder, loc, `${d.prefix}_${n}_${sl.id}.${format === "png" ? "png" : "jpg"}`),
        w: d.size[0], h: d.size[1],
      });
    });
  }
  write(`${jobs.length} screenshots → ${OUT}\n`);
  const browser = await launchBrowser();
  const t0 = Date.now(); let done = 0;
  try {
    const workers = await Promise.all([0, 1, 2, 3].map(() => browser.newPage()));
    const queue = [...jobs];
    await Promise.all(workers.map(async (page) => {
      for (let j; (j = queue.shift());) {
        fs.mkdirSync(path.dirname(j.file), { recursive: true });
        fs.writeFileSync(j.file, await page.shoot(j.url, j.w, j.h, format));
        done++;
        write(`[${done}/${jobs.length}] ${path.relative(OUT, j.file)}\n`);
      }
    }));
  } finally { browser.close(); }
  write(`DONE ${done} files in ${((Date.now() - t0) / 1000).toFixed(1)} s\n`);
}

// ---------- http ----------
const TYPES = { ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".css": "text/css", ".png": "image/png", ".jpg": "image/jpeg", ".ttf": "font/ttf", ".json": "application/json" };
const body = (req) => new Promise((res) => { const c = []; req.on("data", (d) => c.push(d)); req.on("end", () => res(Buffer.concat(c))); });
const json = (res, obj, code = 200) => { res.writeHead(code, { "content-type": "application/json" }); res.end(JSON.stringify(obj)); };
function file(res, p) {
  if (!fs.existsSync(p) || !fs.statSync(p).isFile()) { res.writeHead(404); return res.end("not found"); }
  res.writeHead(200, { "content-type": TYPES[path.extname(p).toLowerCase()] || "application/octet-stream", "cache-control": "no-cache" });
  fs.createReadStream(p).pipe(res);
}

http.createServer(async (req, res) => {
  const u = new URL(req.url, "http://x");
  const q = u.searchParams;
  // Mutating calls only from the studio page itself: blocks other sites posting to localhost.
  const origin = req.headers.origin;
  if (req.method !== "GET" && origin && origin !== `http://localhost:${PORT}` && origin !== `http://127.0.0.1:${PORT}`) {
    res.writeHead(403); return res.end("cross-origin request refused");
  }
  try {
    if (u.pathname === "/") return file(res, path.join(ROOT, "studio.html"));
    if (u.pathname === "/render") {
      const html = renderPage(q);
      if (!html) { res.writeHead(404); return res.end("unknown slide"); }
      res.writeHead(200, { "content-type": TYPES[".html"] }); return res.end(html);
    }
    if (u.pathname.startsWith("/fonts/")) return file(res, FONTS[path.basename(u.pathname)] || "/nonexistent");
    if (u.pathname.startsWith("/assets/")) {
      const p = path.normalize(path.join(ROOT, decodeURIComponent(u.pathname)));
      if (!p.startsWith(ASSETS)) { res.writeHead(403); return res.end(); }
      return file(res, p);
    }
    if (u.pathname.startsWith("/out/")) {
      const p = path.normalize(path.join(ROOT, decodeURIComponent(u.pathname)));
      if (!p.startsWith(OUT)) { res.writeHead(403); return res.end(); }
      return file(res, p);
    }
    if (u.pathname === "/api/state") {
      const p = project();
      return json(res, {
        project: p, locales: locales(), status: status(),
        copy: Object.fromEntries(locales().map((l) => [l, readJSON(copyFile(l), {})])),
        backgrounds: Object.keys(p.backgrounds || {}),
      });
    }
    // Save one slide's copy for one locale: {key, eyebrow, title, body}
    if (u.pathname === "/api/copy" && req.method === "PUT") {
      const loc = q.get("locale"); if (!safe(loc) || !locales().includes(loc)) return json(res, { error: "bad locale" }, 400);
      const { key, ...fields } = JSON.parse(await body(req));
      if (!safe(key)) return json(res, { error: "bad key" }, 400);
      const all = readJSON(copyFile(loc), {});
      all[key] = { eyebrow: fields.eyebrow ?? "", title: fields.title ?? "", body: fields.body ?? "" };
      fs.writeFileSync(copyFile(loc), JSON.stringify(all, null, 2) + "\n");
      return json(res, { ok: true });
    }
    // Change a slide's background (all locales): {device, slide, bg} — bg is a key of project.backgrounds
    if (u.pathname === "/api/slide" && req.method === "PUT") {
      const { device, slide, bg } = JSON.parse(await body(req));
      const p = project(); const s = p.devices[device]?.slides.find((x) => x.id === slide);
      if (!s || !Object.hasOwn(p.backgrounds || {}, bg)) return json(res, { error: "bad slide/bg" }, 400);
      s.bg = bg;
      fs.writeFileSync(path.join(ROOT, "project.json"), JSON.stringify(p, null, 2) + "\n");
      return json(res, { ok: true });
    }
    // Drop a screenshot onto a slide for one locale (raw PNG body)
    if (u.pathname === "/api/shot" && req.method === "POST") {
      const [loc, dev, id] = [q.get("locale"), q.get("device"), q.get("slide")];
      if (![loc, dev, id].every(safe) || !locales().includes(loc) || !Object.hasOwn(project().devices, dev)) return json(res, { error: "bad params" }, 400);
      const buf = await body(req);
      if (buf.subarray(1, 4).toString() !== "PNG") return json(res, { error: "PNG only" }, 400);
      const dir = path.join(ASSETS, "shots", loc, dev); fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(path.join(dir, `${id}.png`), buf);
      return json(res, { ok: true });
    }
    if (u.pathname === "/api/export" && req.method === "POST") {
      const opts = JSON.parse(await body(req));
      const p = project(), known = locales();
      const ok = (a, test) => Array.isArray(a) && a.length > 0 && a.every(test);
      if (!ok(opts.variants, (v) => Object.hasOwn(p.variants, v)) || !ok(opts.devices, (d) => Object.hasOwn(p.devices, d))
        || !ok(opts.locales, (l) => known.includes(l)) || !["jpg", "png"].includes(opts.format)) return json(res, { error: "bad params" }, 400);
      res.writeHead(200, { "content-type": "text/plain; charset=utf-8", "x-content-type-options": "nosniff" });
      try { await exportShots(opts, (s) => res.write(s)); } catch (e) { res.write("ERROR " + e.message + "\n"); }
      return res.end();
    }
    res.writeHead(404); res.end("not found");
  } catch (e) {
    console.error(e); if (!res.headersSent) json(res, { error: e.message }, 500); else res.end();
  }
}).listen(PORT, "127.0.0.1", () => console.log(`Kestrel Screenshot Studio → http://localhost:${PORT}`));

// CLI export without the UI:  node server.mjs export --variants A --devices iphone,ipad,duo --locales all --format jpg
if (process.argv[2] === "export") {
  const arg = (k, d) => { const i = process.argv.indexOf("--" + k); return i > 0 ? process.argv[i + 1] : d; };
  const list = (s, all) => (s === "all" ? all : s.split(","));
  const p = project();
  const opts = {
    variants: list(arg("variants", Object.keys(p.variants)[0]), Object.keys(p.variants)),
    devices: list(arg("devices", "all"), Object.keys(p.devices)),
    locales: list(arg("locales", "en-US"), locales()),
    format: arg("format", "jpg"),
  };
  const bad = [...opts.variants.filter((v) => !p.variants[v]), ...opts.devices.filter((d) => !p.devices[d]), ...opts.locales.filter((l) => !locales().includes(l))];
  if (bad.length) { console.error(`Unknown variant/device/locale: ${bad.join(", ")}`); process.exit(2); }
  setTimeout(() => exportShots(opts, (s) => process.stdout.write(s)).then(() => process.exit(0), (e) => { console.error(e); process.exit(1); }), 200);
}
