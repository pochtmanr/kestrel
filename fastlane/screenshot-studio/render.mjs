// Builds one App Store screenshot as a self-contained HTML page at its exact pixel size.
// The studio shows these pages scaled down in iframes; the exporter screenshots them 1:1.
//
// Slide kinds:  "device" (default) headline + one device ·
//               "hero-device" (landscape) headline + line at the top, the device rising from the bottom edge
//
// Backgrounds are CSS gradients from project.json "backgrounds" (brand colours, no photos).

const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const plain = (s) => esc(String(s ?? "").replace(/\*/g, ""));
// Product terms that must never break at their hyphen
const line = (s) => esc(String(s ?? "").replace(/TRC-20/g, "TRC‑20").replace(/Face ID/g, "Face ID"));

// Kestrel/Shared/Theme.swift, dark palette
const BRAND = {
  sky: "#BBD8FF", ember: "#E8935E", accent: "#62779A", accentText: "#A9BAD3",
  text: "#F2F5F9", body: "rgba(214,224,238,.78)",
};

// New York covers Latin, Cyrillic and Greek. Other scripts get a serif (or the closest calm face) of their own.
const HEAD_FONT = {
  ja: '"Hiragino Mincho ProN"', "zh-Hans": '"Songti SC"', "zh-Hant": '"Songti TC"', ko: '"AppleMyungjo"',
  "ar-SA": '"Al Nile"', "ur-PK": '"Al Nile"', he: '"Arial Hebrew"', th: '"Thonburi"',
  hi: '"Devanagari Sangam MN"', "mr-IN": '"Devanagari Sangam MN"', "bn-BD": '"Bangla Sangam MN"',
  "gu-IN": '"Gujarati Sangam MN"', "pa-IN": '"Gurmukhi Sangam MN"', "or-IN": '"Oriya Sangam MN"',
  "ta-IN": '"Tamil Sangam MN"', "te-IN": '"Telugu Sangam MN"', "kn-IN": '"Kannada Sangam MN"', "ml-IN": '"Malayalam Sangam MN"',
};

// Where the text block and the device sit. Tuned for iPhone 1320×2868 and a 2880×1800 landscape reference.
// `shot` is the real raw screenshot size when the server could read it, so the device frame follows
// whatever the simulator produced instead of cropping it.
function geometry(device, layout, kind, shot) {
  const [W, H] = device.size;
  const [sw, sh] = shot || device.shot;
  const portrait = H > W;
  const big = layout === "bleed";
  const sx = portrait ? W / 1320 : W / 2880;
  const sy = portrait ? H / 2868 : H / 1800;
  const g = { W, H, portrait, sx, sy, textInsetX: Math.round((portrait ? 90 : 220) * sx) };
  if (portrait) {
    g.textTop = Math.round((big ? 180 : 210) * sy);
    g.titleSize = Math.round((big ? 160 : 132) * sx);
    g.titleMaxLines = 3;
    g.bodySize = Math.round(50 * sx);
    g.screenW = Math.round(W * (big ? 1040 / 1320 : 880 / 1320));
    g.screenH = Math.round(g.screenW * sh / sw);
    g.bezel = Math.round(g.screenW * 0.026);
    const frameH = g.screenH + g.bezel * 2;
    const bottomGap = Math.round(130 * sy);
    const maxFrame = H - g.textTop - Math.round(280 * sy) - bottomGap;
    if (!big && frameH > maxFrame && maxFrame > 0) {
      const scale = maxFrame / frameH;
      g.screenW = Math.round(g.screenW * scale);
      g.screenH = Math.round(g.screenH * scale);
      g.bezel = Math.round(g.screenW * 0.026);
    }
    const frameH2 = g.screenH + g.bezel * 2;
    g.deviceTop = big ? Math.round(1010 * sy) : H - bottomGap - frameH2;
  } else {
    g.textTop = Math.round((big ? 110 : 130) * sy);
    g.titleSize = Math.round((big ? 190 : 156) * sx);
    g.titleMaxLines = 2;
    g.bodySize = Math.round(60 * sx);
    g.deviceTop = Math.round((big ? 640 : 560) * sy);
    const bottom = Math.round((big ? -320 : 100) * sy);
    const share = big ? 0.84 : 0.74;
    g.screenH = Math.round(Math.min((H - g.deviceTop - bottom) * 0.96, (W * share) * sh / sw));
    g.screenW = Math.round(g.screenH * sw / sh);
    g.bezel = Math.round(g.screenW * 0.018);
  }
  if (kind === "hero-device") {
    // the device runs off the bottom edge: a fifth to a quarter of it stays hidden
    g.textTop = Math.round((portrait ? 200 : 110) * sy);
    g.titleSize = Math.round((portrait ? 150 : 170) * sx);
    g.screenW = Math.round(W * (portrait ? 0.8 : 0.66));
    g.screenH = Math.round(g.screenW * sh / sw);
    g.bezel = Math.round(g.screenW * 0.018);
    g.deviceTop = Math.round(H * (portrait ? 0.5 : 0.36));
  }
  g.deviceLeft = Math.round((g.W - g.screenW - g.bezel * 2) / 2);
  g.textLimit = g.deviceTop - Math.round((portrait ? 50 : 36) * sy);
  g.eyebrowSize = Math.round((portrait ? 40 : 52) * sx);
  g.bodyMax = Math.round((portrait ? 1000 : 1700) * sx);
  return g;
}

export function screenHTML(shotUrl, missingLabel) {
  return shotUrl
    ? `<img class="shot" src="${esc(shotUrl)}" alt="">`
    : `<div class="shot missing"><div>Screenshot missing<br><small>${esc(missingLabel)}</small></div></div>`;
}

export function deviceHTML(kind, g, shotUrl, missingLabel) {
  const screen = screenHTML(shotUrl, missingLabel);
  const w = g.screenW, h = g.screenH, b = g.bezel;
  const box = `left:${g.deviceLeft}px;top:${g.deviceTop}px;width:${w + 2 * b}px;height:${h + 2 * b}px`;
  if (kind === "iphone") {
    const r = Math.round(w * 0.137);
    // Dynamic Island — ~30% of screen width, sits just under the top bezel
    const iw = Math.round(w * 0.30), ih = Math.max(10, Math.round(w * 0.038)), it = Math.round(w * 0.016);
    return `<div class="dev iphone" style="${box};padding:${b}px;border-radius:${r + b}px">
      <div class="screen" style="border-radius:${r}px">${screen}
        <i class="island" style="width:${iw}px;height:${ih}px;top:${it}px;border-radius:${Math.round(ih / 2)}px"></i></div>
      <i class="btn" style="left:-${Math.round(b * 0.45)}px;top:${Math.round(h * 0.2)}px;height:${Math.round(h * 0.06)}px"></i>
      <i class="btn" style="left:-${Math.round(b * 0.45)}px;top:${Math.round(h * 0.29)}px;height:${Math.round(h * 0.06)}px"></i>
      <i class="btn" style="right:-${Math.round(b * 0.45)}px;top:${Math.round(h * 0.25)}px;height:${Math.round(h * 0.1)}px"></i>
    </div>`;
  }
  // iPad / Duo: thin even bezel
  const r = Math.round(w * (kind === "duo" ? 0.03 : 0.022));
  return `<div class="dev ${kind}" style="${box};padding:${b}px;border-radius:${r + b}px">
    <div class="screen" style="border-radius:${r}px">${screen}</div>
  </div>`;
}

export function renderSlide({ project, deviceKey, slide, variantKey, locale, copy, copyMissing, shotUrl, shotSize, fontBase }) {
  const device = project.devices[deviceKey];
  const variant = project.variants[variantKey];
  const kind = slide.kind || "device";
  const g = geometry(device, variant.layout, kind, shotSize);
  const heroDevice = kind === "hero-device";
  const dark = variant.theme === "dark";
  const rtl = project.rtl.includes(locale);
  const c = copy || {};
  const bgCss = (project.backgrounds || {})[slide.bg] || "none";
  const eyebrowColor = dark ? (slide.eyebrow === "ember" ? BRAND.ember : BRAND.sky) : BRAND.accent;

  let text;
  if (heroDevice) {
    // the device fills the bottom of the canvas, so the line stays under the headline
    text = `<div class="text hero-text">
        <h1 id="t">${plain(c.title)}</h1>
        ${c.body ? `<p class="body hero-line" id="b">${line(c.body)}</p>` : ""}</div>`;
  } else {
    text = `<div class="text">
      ${c.eyebrow ? `<div class="eyebrow">${esc(c.eyebrow)}</div>` : ""}
      <h1 id="t">${plain(c.title)}</h1>
      ${c.body ? `<p class="body" id="b">${line(c.body)}</p>` : ""}
    </div>`;
  }

  const devices = deviceHTML(deviceKey, g, shotUrl, `${locale} · ${deviceKey}/${slide.shot || slide.id}`);

  return `<!doctype html><html lang="${esc(locale)}" dir="${rtl ? "rtl" : "ltr"}"><head><meta charset="utf-8">
<style>
@font-face{font-family:"KSans";src:url(${fontBase}/SFNS.ttf);font-weight:100 900}
@font-face{font-family:"KHead";src:url(${fontBase}/NewYork.ttf);font-weight:100 900}
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:${g.W}px;height:${g.H}px;overflow:hidden}
body{position:relative;background:${dark ? project.nightColor || "#0E131A" : project.flatColor || "#F2F4F7"};
  font-family:"KSans",-apple-system,"PingFang SC","Hiragino Sans","Apple SD Gothic Neo","Kohinoor Devanagari","Thonburi",sans-serif;
  color:${dark ? BRAND.text : "#0B1424"};-webkit-font-smoothing:antialiased}
.bg{position:absolute;inset:0;background:${dark ? bgCss : "none"};z-index:0}
.text{position:absolute;left:${g.textInsetX}px;right:${g.textInsetX}px;top:${g.textTop}px;text-align:center;z-index:5}
.eyebrow{font-size:${g.eyebrowSize}px;font-weight:600;letter-spacing:.16em;text-transform:uppercase;color:${eyebrowColor};margin-bottom:${Math.round((g.portrait ? 30 : 26) * g.sx)}px}
h1{font-family:"KHead","New York",Georgia,serif;font-weight:500;font-size:${g.titleSize}px;line-height:1.04;letter-spacing:-.025em;text-wrap:balance}
.hero-text h1{line-height:1.06;text-shadow:0 2px 30px rgba(0,0,0,.25)}
.body{margin:${Math.round((g.portrait ? 36 : 28) * g.sx)}px auto 0;max-width:${g.bodyMax}px;font-size:${g.bodySize}px;line-height:1.3;font-weight:400;
  color:${dark ? BRAND.body : "rgba(11,20,36,.62)"};text-wrap:balance}
.hero-line{color:${dark ? BRAND.accentText : "rgba(11,20,36,.7)"}}
.dev{position:absolute;z-index:4;background:#0A0D12;
  box-shadow:inset 0 0 0 2px #2A313C,0 0 0 ${g.portrait ? 5 : 4}px #262C35,0 ${g.portrait ? 60 : 50}px ${g.portrait ? 120 : 100}px rgba(0,0,0,${dark ? .55 : .2})}
.screen{position:relative;width:100%;height:100%;overflow:hidden;background:#0E131A}
.shot{display:block;width:100%;height:100%;object-fit:cover;object-position:top center}
.missing{display:flex;align-items:center;justify-content:center;text-align:center;background:repeating-linear-gradient(45deg,#141A22 0 40px,#18202A 40px 80px);
  color:${BRAND.ember};font-size:${g.portrait ? 64 : 72}px;font-weight:600;line-height:1.3}
.missing small{font-size:.6em;color:${BRAND.accentText};font-weight:400}
.btn{position:absolute;width:${Math.max(6, Math.round(g.bezel * 0.5))}px;background:#1C222B;border-radius:4px}
.island{position:absolute;left:50%;transform:translateX(-50%);background:#050505;z-index:8;box-shadow:0 0 0 1px rgba(0,0,0,.55),inset 0 1px 0 rgba(255,255,255,.1)}
${locale === "ja" ? "h1,.body{word-break:auto-phrase}" : ""}
${["ko", "th"].includes(locale) ? "h1,.body{word-break:keep-all}" : ""}
${HEAD_FONT[locale] ? `h1{font-family:${HEAD_FONT[locale]},serif;letter-spacing:0;line-height:1.18}` : ""}
</style></head><body data-copy-missing="${copyMissing ? 1 : 0}">
<div class="bg"></div>
${text}
${devices}
<script>
// Long translations: shrink the headline to its line budget, then until the text clears the device.
(async () => {
  await document.fonts.ready;
  const t = document.getElementById("t"), b = document.getElementById("b");
  if (t) {
    let s = parseFloat(getComputedStyle(t).fontSize);
    const lh = parseFloat(getComputedStyle(t).lineHeight) / s;
    const lines = ${heroDevice ? 2 : g.titleMaxLines};
    const min = s * 0.45;
    // too many lines, or one word wider than the column
    const bad = () => t.offsetHeight > s * lh * lines + 4 || t.scrollWidth > t.clientWidth + 1;
    while (bad() && s > min) { s -= 2; t.style.fontSize = s + "px"; }
    const limit = ${g.textLimit};
    const text = document.querySelector(".text");
    const over = () => text.offsetTop + text.offsetHeight > limit;
    let bs = ${g.bodySize};
    while (b && over() && bs > ${Math.round(g.bodySize * 0.7)}) { bs -= 1; b.style.fontSize = bs + "px"; }
    while (over() && s > min) { s -= 2; t.style.fontSize = s + "px"; }
  }
  await Promise.all([...document.images].map((i) => i.decode().catch(() => {})));
  window.__ready = true;
})();
</script>
</body></html>`;
}
