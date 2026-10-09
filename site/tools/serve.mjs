// Tiny static file server used by `preview` and `check`. No dependencies.
// Serves a directory and answers /simd-coin.json with whatever `getCoin()` returns,
// which mimics what the SIMD host serves on the published origin.
import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { extname, join, normalize, resolve, sep } from "node:path";

const TYPES = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".png": "image/png",
  ".webp": "image/webp",
  ".svg": "image/svg+xml",
  ".woff2": "font/woff2",
  ".ico": "image/x-icon",
};

/**
 * @param {string} dir directory to serve
 * @param {() => object|null} getCoin current /simd-coin.json payload, or null for a 404
 * @param {string} [prefix] optional URL prefix the site is served under, e.g. "/preview"
 */
export function createStaticServer(dir, getCoin, prefix = "") {
  const rootDir = resolve(dir);
  return createServer(async (req, res) => {
    const url = new URL(req.url || "/", "http://localhost");
    let pathname = decodeURIComponent(url.pathname);
    if (pathname === "/simd-coin.json") {
      const coin = getCoin();
      if (!coin) { res.writeHead(404, { "content-type": "text/plain" }); res.end("not yet"); return; }
      res.writeHead(200, { "content-type": TYPES[".json"], "cache-control": "no-store" });
      res.end(JSON.stringify(coin));
      return;
    }
    if (prefix) {
      if (pathname === prefix) { res.writeHead(302, { location: prefix + "/" }); res.end(); return; }
      if (!pathname.startsWith(prefix + "/")) { res.writeHead(404); res.end("not found"); return; }
      pathname = pathname.slice(prefix.length);
    }
    if (pathname.endsWith("/")) pathname += "index.html";
    const file = normalize(join(rootDir, pathname));
    if (!file.startsWith(rootDir + sep) && file !== rootDir) { res.writeHead(403); res.end("forbidden"); return; }
    try {
      const info = await stat(file);
      if (!info.isFile()) throw new Error("not a file");
      const body = await readFile(file);
      res.writeHead(200, { "content-type": TYPES[extname(file)] || "application/octet-stream", "content-length": body.length });
      res.end(body);
    } catch {
      res.writeHead(404, { "content-type": "text/plain" });
      res.end("not found");
    }
  });
}

/** Sample payloads in the shape the SIMD host serves. */
export const SAMPLE_PRELAUNCH = {
  name: "Swarm Tester",
  symbol: "TESTER",
  token: null,
  chainName: "Ethereum",
  coinUrl: null,
  chartUrl: null,
  status: "launching…",
  market: { marketCap: null, priceUsd: null, volume24h: null },
};
export const SAMPLE_LIVE = {
  name: "Swarm Tester",
  symbol: "TESTER",
  token: "0x1234567890abcdef1234567890abcdef12345678",
  chainName: "Ethereum",
  coinUrl: "https://www.si-md.xyz/launchpad/coin/example",
  chartUrl: "https://www.si-md.xyz/launchpad/coin/example/chart",
  status: "live",
  market: { marketCap: 1234567.89, priceUsd: 0.0012345, volume24h: 45678.9 },
};
