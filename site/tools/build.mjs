// Production "build": there is no bundler. This copies the static source into ../dist and
// checks the export: every local asset reference resolves, URLs are relative, nothing is
// hardcoded that must come from /simd-coin.json, and the required footer text is present.
import { cp, mkdir, readFile, readdir, rm, stat } from "node:fs/promises";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const site = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const dist = resolve(site, "..", "dist");
const FILES = ["index.html", "styles.css", "app.js"];

await rm(dist, { recursive: true, force: true });
await mkdir(dist, { recursive: true });
for (const f of FILES) await cp(join(site, f), join(dist, f));
await cp(join(site, "assets"), join(dist, "assets"), { recursive: true });

const problems = [];
const html = await readFile(join(dist, "index.html"), "utf8");
const css = await readFile(join(dist, "styles.css"), "utf8");
const js = await readFile(join(dist, "app.js"), "utf8");

// 1. every local reference in HTML and CSS resolves to a file in dist
const refs = new Set();
for (const m of html.matchAll(/\b(?:href|src)="([^"]+)"/g)) refs.add(m[1]);
for (const m of css.matchAll(/url\("?([^")]+)"?\)/g)) refs.add(m[1]);
for (const ref of refs) {
  if (/^(https?:)?\/\//.test(ref) || ref.startsWith("#") || ref.startsWith("data:") || ref.startsWith("mailto:")) continue;
  if (ref.startsWith("/")) { problems.push(`absolute URL (breaks subpath hosting): ${ref}`); continue; }
  const target = join(dist, ref.split("?")[0].split("#")[0]);
  try { await stat(target); } catch { problems.push(`missing asset: ${ref}`); }
}
// 2. the contract address is never hardcoded
for (const [name, text] of [["index.html", html], ["app.js", js]]) {
  if (/0x[0-9a-fA-F]{40}/.test(text)) problems.push(`${name} contains a hardcoded 0x address`);
}
if (!js.includes('fetch("/simd-coin.json"')) problems.push("app.js does not fetch /simd-coin.json");
if (!html.includes("launching…")) problems.push("index.html lacks the 'launching…' placeholder");
// 3. required copy and hygiene
if (!html.includes("Built 100% by the Identity.md swarm")) problems.push("footer text missing");
if (!html.includes("not financial advice")) problems.push("footer disclaimer missing");
if (/<script[^>]+src="https?:/.test(html)) problems.push("third-party script found");
if (/fonts\.googleapis|googletagmanager|analytics|plausible|hotjar/i.test(html + css + js)) problems.push("external font or tracker reference found");
if (/<form\b|<input\b/.test(html)) problems.push("the site must not collect data: form/input found");
if (/(wagmi|rainbowkit|viem|ethers)/i.test(js)) problems.push("wallet library reference found");

// 4. report sizes
async function walk(dir) {
  const out = [];
  for (const e of await readdir(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) out.push(...(await walk(p)));
    else out.push(p);
  }
  return out;
}
let total = 0;
const rows = [];
for (const f of await walk(dist)) {
  const s = await stat(f);
  total += s.size;
  rows.push(`${String(s.size).padStart(8)}  ${relative(dist, f)}`);
}
console.log("dist/ export:");
console.log(rows.sort().join("\n"));
console.log(`${String(total).padStart(8)}  total bytes`);

if (problems.length) {
  console.error("\nBUILD FAILED:");
  for (const p of problems) console.error(" - " + p);
  process.exit(1);
}
console.log("\nbuild ok: dist/index.html and assets written with relative URLs");
