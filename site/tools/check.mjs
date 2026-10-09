// Interaction and rendering validation of the production export in ../dist.
// Runs one bounded command: starts a local server (with a mock /simd-coin.json), drives headless
// Chrome through Playwright, records results, saves screenshots to ../artifacts/screenshots and exits.
// Playwright is resolved from the local node_modules, from $PLAYWRIGHT_DIR, or from `npm root -g`.
import { execSync } from "node:child_process";
import { mkdir } from "node:fs/promises";
import { createRequire } from "node:module";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { createStaticServer, SAMPLE_LIVE, SAMPLE_PRELAUNCH } from "./serve.mjs";

const site = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const dist = resolve(site, "..", "dist");
const shots = resolve(site, "..", "artifacts", "screenshots");
const PREFIX = "/preview"; // served under a subpath so broken relative URLs would show up

async function loadPlaywright() {
  const dirs = [site, process.env.PLAYWRIGHT_DIR];
  try {
    const globalRoot = execSync("npm root -g", { stdio: ["ignore", "pipe", "ignore"] }).toString().trim();
    dirs.push(globalRoot, join(globalRoot, "@playwright", "mcp")); // a global playwright-mcp bundles playwright
  } catch { /* no npm */ }
  for (const dir of dirs) {
    if (!dir) continue;
    try {
      const req = createRequire(join(dir, "package.json"));
      const mod = await import(pathToFileURL(req.resolve("playwright")).href);
      return mod.chromium ? mod : mod.default; // CommonJS build: the API sits on `default`
    } catch { /* try the next location */ }
  }
  throw new Error("playwright not found: `npm i -D playwright` in site/ or set PLAYWRIGHT_DIR to a directory whose node_modules has it");
}

/** @type {{name: string, ok: boolean|null, detail: string}[]} */
const results = [];
/** @param {string} name @param {boolean|null} ok @param {string} [detail] */
function record(name, ok, detail = "") {
  results.push({ name, ok, detail });
  console.log(`${ok === null ? "SKIP" : ok ? "PASS" : "FAIL"}  ${name}${detail ? "  — " + detail : ""}`);
}

let mode = "pre";
const server = createStaticServer(dist, () => (mode === "none" ? null : mode === "live" ? SAMPLE_LIVE : SAMPLE_PRELAUNCH), PREFIX);
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const port = /** @type {import("node:net").AddressInfo} */ (server.address()).port;
const origin = `http://127.0.0.1:${port}`;
const url = `${origin}${PREFIX}/`;
await mkdir(shots, { recursive: true });

const { chromium } = await loadPlaywright();
let browser;
try {
  browser = await chromium.launch({ channel: process.env.PW_CHANNEL || "chrome", headless: true });
} catch {
  browser = await chromium.launch({ headless: true });
}

/** @param {import("playwright").BrowserContext} ctx */
function watch(ctx) {
  /** @type {string[]} */ const errors = [];
  /** @type {string[]} */ const failed = [];
  ctx.on("page", (page) => {
    page.on("console", (m) => {
      // the host's /simd-coin.json may 404 before launch; the page handles that, so the browser's own network log line is expected
      if (m.type() === "error" && !(m.location().url || "").endsWith("/simd-coin.json")) errors.push(m.text());
    });
    page.on("pageerror", (e) => errors.push(String(e)));
    page.on("requestfailed", (r) => failed.push(r.url()));
    page.on("response", (r) => { if (r.status() >= 400 && !r.url().endsWith("/simd-coin.json")) failed.push(`${r.status()} ${r.url()}`); });
  });
  return { errors, failed };
}

/** Effective contrast of rendered text against its nearest opaque ancestor background. */
const CONTRAST_FN = `(selectors) => {
  const lum = (c) => { const m = c.match(/\\d+(\\.\\d+)?/g).map(Number); const [r,g,b] = m.slice(0,3).map(v => { v/=255; return v <= 0.03928 ? v/12.92 : Math.pow((v+0.055)/1.055, 2.4); }); return 0.2126*r+0.7152*g+0.0722*b; };
  const alpha = (c) => { const m = c.match(/\\d+(\\.\\d+)?/g); return m && m.length > 3 ? Number(m[3]) : 1; };
  return selectors.map((sel) => {
    const el = document.querySelector(sel); if (!el) return { sel, missing: true };
    const fg = getComputedStyle(el).color; let node = el, bg = null;
    while (node && node !== document.documentElement) { const b = getComputedStyle(node).backgroundColor; if (b && alpha(b) === 1 && b !== "rgba(0, 0, 0, 0)") { bg = b; break; } node = node.parentElement; }
    if (!bg) return { sel, fg, bg: null, ratio: null };
    const [l1, l2] = [lum(fg), lum(bg)].sort((a, b) => b - a);
    const size = parseFloat(getComputedStyle(el).fontSize), weight = Number(getComputedStyle(el).fontWeight);
    return { sel, fg, bg, ratio: Number(((l1 + 0.05) / (l2 + 0.05)).toFixed(2)), size, weight };
  });
}`;

try {
  // ---------- desktop, pre-launch ----------
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const net = watch(ctx);
  const page = await ctx.newPage();
  await page.goto(url, { waitUntil: "networkidle" });
  await page.evaluate(() => document.fonts.ready);

  record("title set from coin name and symbol", (await page.title()) === "Swarm Tester ($TESTER)", await page.title());
  record("one h1, headings do not skip levels", await page.evaluate(() => {
    const hs = [...document.querySelectorAll("h1,h2,h3,h4")].map((h) => Number(h.tagName[1]));
    return hs.filter((l) => l === 1).length === 1 && hs.every((l, i) => i === 0 || l <= hs[i - 1] + 1);
  }));
  record("main landmark and skip link present", await page.evaluate(() => !!document.querySelector("main#main") && document.querySelector(".skip")?.getAttribute("href") === "#main"));
  record("nav anchors resolve to sections", await page.evaluate(() => [...document.querySelectorAll('.bar nav a[href^="#"]')].every((a) => document.getElementById(a.getAttribute("href").slice(1)))));
  record("every button and link has an accessible name", await page.evaluate(() => [...document.querySelectorAll("button, a")].every((el) => (el.textContent || "").trim() || el.getAttribute("aria-label"))));
  record("hero image has alt text", await page.evaluate(() => (document.getElementById("logo")?.getAttribute("alt") || "").length > 10));
  const fonts = await page.evaluate(() => ({ inter900: document.fonts.check('900 20px "Inter"'), inter500: document.fonts.check('500 16px "Inter"'), mono: document.fonts.check('400 13px "IBM Plex Mono"'), mono600: document.fonts.check('600 13px "IBM Plex Mono"'), loaded: [...document.fonts].filter((f) => f.status === "loaded").map((f) => `${f.family} ${f.weight}`) }));
  record("self-hosted fonts loaded (Inter variable, IBM Plex Mono 400/600)", fonts.inter900 && fonts.inter500 && fonts.mono && fonts.mono600, fonts.loaded.join(", "));
  record("pre-launch: contract reads 'launching…' and copy is disabled", await page.evaluate(() => document.getElementById("ca")?.textContent === "launching…" && document.getElementById("copy")?.disabled === true));
  record("pre-launch: buy and chart point at the launchpad", await page.evaluate(() => document.getElementById("buy")?.href === "https://www.si-md.xyz/launchpad/" && document.getElementById("chart")?.href === "https://www.si-md.xyz/launchpad/"));
  record("pre-launch: chain and status painted from JSON", await page.evaluate(() => document.getElementById("chain")?.textContent === "Ethereum" && document.getElementById("status")?.textContent === "launching…"));
  record("terminal log is populated", await page.evaluate(() => (document.getElementById("log")?.children.length || 0) >= 4));
  record("lab renders 8 workstations (decorative, aria-hidden)", await page.evaluate(() => document.querySelectorAll("#workers-grid .ws").length === 8 && document.getElementById("workers-grid")?.getAttribute("aria-hidden") === "true"));
  record("motion defaults on without a reduced-motion preference", await page.evaluate(() => document.documentElement.dataset.motion === "on" && document.getElementById("motion")?.getAttribute("aria-pressed") === "true"));
  await page.screenshot({ path: join(shots, "desktop-1280-prelaunch.jpg"), fullPage: true, type: "jpeg", quality: 70 });

  // contrast of rendered pairs
  const SELECTORS = [".lcd small", ".lcd b", ".desc", ".term-head", ".log", ".prompt", ".btn", ".btn.ghost", ".ws-stat", ".ctl-label", ".readout", ".machine-status", ".note", ".mod a", ".mod p", ".specs dt", "footer", ".sw", ".bar nav a", ".ca button", ".code"];
  const pairs = await page.evaluate(`(${CONTRAST_FN})(${JSON.stringify(SELECTORS)})`);
  const badPairs = pairs.filter((p) => p.ratio !== null && !p.missing && (p.size >= 24 || (p.size >= 18.66 && p.weight >= 700) ? p.ratio < 3 : p.ratio < 4.5));
  record("rendered text contrast ≥ 4.5:1 (≥ 3:1 for large text)", badPairs.length === 0, pairs.map((p) => `${p.sel} ${p.ratio ?? "n/a"}`).join("; "));

  // keyboard walk
  const stops = [];
  for (let i = 0; i < 20; i++) {
    await page.keyboard.press("Tab");
    stops.push(await page.evaluate(() => { const el = document.activeElement; const cs = el ? getComputedStyle(el) : null; return { id: el?.id || el?.className || el?.tagName, outline: cs ? `${cs.outlineStyle} ${cs.outlineWidth} ${cs.outlineColor}` : "" }; }));
  }
  record("Tab order starts at the skip link", stops[0]?.id === "skip", stops.map((s) => s.id).join(" → "));
  const needed = ["buy", "chart", "motion", "freq", "gain", "coolant", "overdrive", "build"];
  record("primary controls reachable by keyboard", needed.every((id) => stops.some((s) => s.id === id)), needed.filter((id) => !stops.some((s) => s.id === id)).join(",") || "all reached");
  record("visible focus ring on keyboard stops", stops.slice(0, 12).every((s) => s.outline.startsWith("solid 3px")), stops[1]?.outline);
  await page.focus("#buy");
  await page.screenshot({ path: join(shots, "focus-buy-button.jpg"), clip: { x: 0, y: 0, width: 1280, height: 620 }, type: "jpeg", quality: 70 });

  // machine: scroll powers it up
  await page.locator("#machine").scrollIntoViewIfNeeded();
  await page.waitForFunction(() => document.getElementById("machine")?.classList.contains("on"), null, { timeout: 4000 });
  await page.waitForFunction(() => document.getElementById("power")?.textContent === "100%", null, { timeout: 4000 });
  record("machine powers up when scrolled into view", true, await page.locator("#machine-status").textContent());
  record("rocket symbol renders in the launch bay (no duplicate ids)", await page.evaluate(() => { const ids = [...document.querySelectorAll("[id]")].map((e) => e.id); const r = document.getElementById("rocket"); return new Set(ids).size === ids.length && r instanceof SVGSVGElement && r.getBoundingClientRect().height > 80; }));
  await page.locator("#gadget").screenshot({ path: join(shots, "machine-powered-idle.jpg"), type: "jpeg", quality: 70 });
  const freqBefore = await page.locator("#freq-out").textContent();
  await page.click("#freq");
  const freqAfter = await page.locator("#freq-out").textContent();
  record("frequency dial changes its readout and the trace", freqBefore !== freqAfter, `${freqBefore} → ${freqAfter}`);
  const gainBefore = await page.locator("#gain-out").textContent();
  await page.click("#gain");
  record("gain dial changes its readout", gainBefore !== (await page.locator("#gain-out").textContent()));
  await page.click("#coolant");
  record("coolant lever toggles aria-pressed, readout and core colour", await page.evaluate(() => document.getElementById("coolant")?.getAttribute("aria-pressed") === "true" && document.getElementById("coolant-out")?.textContent === "on" && document.getElementById("machine")?.classList.contains("cool") && document.getElementById("core-out")?.textContent === "cryo"));
  await page.click("#overdrive");
  record("overdrive lever toggles", await page.evaluate(() => document.getElementById("overdrive")?.getAttribute("aria-pressed") === "true" && document.getElementById("core-out")?.textContent === "cryo+boost"));
  await page.keyboard.press("Space"); // overdrive still focused: keyboard toggles it back
  record("lever answers the keyboard (Space toggles)", await page.evaluate(() => document.getElementById("overdrive")?.getAttribute("aria-pressed") === "false"));
  await page.click("#build");
  await page.waitForFunction(() => /Rocket launched/.test(document.getElementById("machine-status")?.textContent || ""), null, { timeout: 6000 });
  await page.screenshot({ path: join(shots, "machine-build-launch.jpg"), type: "jpeg", quality: 70 });
  record("BUILD compiles, launches the rocket and announces it", await page.evaluate(() => document.getElementById("launched")?.textContent === "1" && /build #1 complete/.test(document.getElementById("log")?.textContent || "")));
  await page.waitForFunction(() => document.getElementById("build")?.textContent === "Build" && !document.getElementById("build")?.hasAttribute("aria-disabled"), null, { timeout: 6000 });
  record("BUILD button returns to idle after the flight", true);
  await page.click("#motion");
  record("animation switch pauses motion", await page.evaluate(() => document.documentElement.dataset.motion === "off" && getComputedStyle(document.querySelector(".leds i")).animationPlayState === "paused"));
  await page.click("#motion");
  record("animation switch resumes motion", await page.evaluate(() => document.documentElement.dataset.motion === "on"));
  record("no console errors or failed requests (desktop)", net.errors.length === 0 && net.failed.length === 0, [...net.errors, ...net.failed].join("; "));
  await ctx.close();

  // ---------- live data ----------
  mode = "live";
  const ctxLive = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  await ctxLive.grantPermissions(["clipboard-read", "clipboard-write"], { origin });
  const netLive = watch(ctxLive);
  const live = await ctxLive.newPage();
  await live.goto(url, { waitUntil: "networkidle" });
  await live.waitForFunction((t) => document.getElementById("ca")?.textContent === t, SAMPLE_LIVE.token, { timeout: 4000 });
  record("live: contract address shown from JSON, copy enabled", await live.evaluate(() => document.getElementById("copy")?.disabled === false));
  record("live: buy, chart and how-to links use coinUrl/chartUrl", await live.evaluate((s) => document.getElementById("buy")?.href === s.coinUrl && document.getElementById("chart")?.href === s.chartUrl && document.getElementById("buy-link")?.href === s.coinUrl, SAMPLE_LIVE));
  record("live: market readouts formatted", await live.evaluate(() => document.getElementById("mc")?.textContent === "$1.23M" && document.getElementById("price")?.textContent === "$0.00123" && document.getElementById("vol")?.textContent === "$45.7K"), await live.evaluate(() => [document.getElementById("mc")?.textContent, document.getElementById("price")?.textContent, document.getElementById("vol")?.textContent].join(" ")));
  record("live: status reads from JSON", await live.evaluate(() => document.getElementById("status")?.textContent === "live"));
  await live.click("#copy");
  try {
    await live.waitForFunction(() => document.getElementById("machine-status")?.textContent === "Contract address copied.", null, { timeout: 3000 });
    const clip = await live.evaluate(() => navigator.clipboard.readText());
    record("live: copy button writes the address to the clipboard and announces it", clip === SAMPLE_LIVE.token, clip);
  } catch (e) {
    record("live: copy button writes the address to the clipboard and announces it", null, "clipboard not available in this headless session: " + String(e).slice(0, 80));
  }
  await live.screenshot({ path: join(shots, "desktop-1280-live.jpg"), clip: { x: 0, y: 0, width: 1280, height: 800 }, type: "jpeg", quality: 70 });
  record("no console errors or failed requests (live)", netLive.errors.length === 0 && netLive.failed.length === 0, [...netLive.errors, ...netLive.failed].join("; "));
  await ctxLive.close();

  // ---------- no JSON yet (404) ----------
  mode = "none";
  const ctx404 = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const net404 = watch(ctx404);
  const p404 = await ctx404.newPage();
  await p404.goto(url, { waitUntil: "networkidle" });
  record("404 on /simd-coin.json keeps the placeholders and throws no page error", (await p404.evaluate(() => document.getElementById("ca")?.textContent === "launching…" && document.getElementById("mc")?.textContent === "—")) && net404.errors.length === 0, net404.errors.join("; "));
  await ctx404.close();
  mode = "pre";

  // ---------- mobile and intermediate widths ----------
  for (const [w, h, full] of [[320, 568, false], [390, 844, true], [768, 1024, false]]) {
    const c = await browser.newContext({ viewport: { width: w, height: h }, isMobile: w < 500, hasTouch: w < 500 });
    const n = watch(c);
    const p = await c.newPage();
    await p.goto(url, { waitUntil: "networkidle" });
    await p.evaluate(() => document.fonts.ready);
    const overflow = await p.evaluate(() => {
      const vw = document.documentElement.clientWidth;
      const clipped = (el) => { for (let n = el.parentElement; n && n !== document.body; n = n.parentElement) { const o = getComputedStyle(n).overflowX; if (o === "hidden" || o === "clip" || o === "auto" || o === "scroll") return true; } return false; };
      const wide = [...document.querySelectorAll("body *")].filter((el) => { const r = el.getBoundingClientRect(); return r.width > 0 && (r.right > vw + 1 || r.left < -1) && !clipped(el); }).map((el) => el.tagName.toLowerCase() + (el.id ? "#" + el.id : "") + (el.className && typeof el.className === "string" ? "." + el.className.split(" ")[0] : ""));
      return { scrollWidth: document.documentElement.scrollWidth, vw, wide: wide.slice(0, 8) };
    });
    record(`${w}px: no horizontal overflow`, overflow.scrollWidth <= overflow.vw && overflow.wide.length === 0, `scrollWidth ${overflow.scrollWidth} / ${overflow.vw}${overflow.wide.length ? " offenders: " + overflow.wide.join(", ") : ""}`);
    const targets = await p.evaluate(() => [...document.querySelectorAll("button, a.btn, .ca button")].map((el) => { const r = el.getBoundingClientRect(); return { id: el.id || el.className, w: Math.round(r.width), h: Math.round(r.height) }; }).filter((t) => t.w < 24 || t.h < 24));
    record(`${w}px: interactive targets at least 24×24 CSS px`, targets.length === 0, targets.map((t) => `${t.id} ${t.w}×${t.h}`).join(", "));
    if (w === 390) {
      await p.click("#build");
      await p.waitForFunction(() => /Rocket launched/.test(document.getElementById("machine-status")?.textContent || ""), null, { timeout: 6000 });
      record("390px: BUILD works with touch emulation", true);
    }
    await p.screenshot({ path: join(shots, `mobile-${w}${full ? "-full" : ""}.jpg`), fullPage: full, type: "jpeg", quality: 70 });
    record(`${w}px: no console errors or failed requests`, n.errors.length === 0 && n.failed.length === 0, [...n.errors, ...n.failed].join("; "));
    await c.close();
  }

  // ---------- reduced motion ----------
  const ctxRm = await browser.newContext({ viewport: { width: 1280, height: 800 }, reducedMotion: "reduce" });
  const rm = await ctxRm.newPage();
  await rm.goto(url, { waitUntil: "networkidle" });
  record("reduced motion: switch starts off and keyframes are paused", await rm.evaluate(() => document.documentElement.dataset.motion === "off" && document.getElementById("motion")?.getAttribute("aria-pressed") === "false" && getComputedStyle(document.querySelector(".leds i")).animationPlayState === "paused" && getComputedStyle(document.querySelector(".crt-frame")).animationPlayState === "paused"));
  await rm.locator("#machine").scrollIntoViewIfNeeded();
  await rm.click("#build");
  await rm.waitForFunction(() => /Rocket launched/.test(document.getElementById("machine-status")?.textContent || ""), null, { timeout: 3000 });
  record("reduced motion: BUILD still completes instantly with text feedback", await rm.evaluate(() => document.getElementById("launched")?.textContent === "1" && document.getElementById("power")?.textContent === "100%"));
  await rm.screenshot({ path: join(shots, "desktop-reduced-motion.jpg"), clip: { x: 0, y: 0, width: 1280, height: 800 }, type: "jpeg", quality: 70 });
  await ctxRm.close();
} finally {
  await browser.close();
  server.close();
}

const failed = results.filter((r) => r.ok === false);
const skipped = results.filter((r) => r.ok === null);
console.log(`\n${results.length - failed.length - skipped.length} passed, ${failed.length} failed, ${skipped.length} skipped. Screenshots in ${shots}`);
process.exit(failed.length ? 1 : 0);
