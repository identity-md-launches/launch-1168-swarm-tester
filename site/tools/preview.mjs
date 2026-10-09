// Local preview of the production export with a sample /simd-coin.json.
//   node tools/preview.mjs            serves ../dist with the pre-launch sample
//   node tools/preview.mjs --live     serves ../dist with the live sample (token, market data)
//   node tools/preview.mjs --src      serves the source in ./ instead of ../dist
// Stop it with Ctrl-C. The port is printed on start (PORT env overrides it).
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createStaticServer, SAMPLE_LIVE, SAMPLE_PRELAUNCH } from "./serve.mjs";

const site = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const args = new Set(process.argv.slice(2));
const dir = args.has("--src") ? site : resolve(site, "..", "dist");
const coin = args.has("--live") ? SAMPLE_LIVE : SAMPLE_PRELAUNCH;
const port = Number(process.env.PORT || 4173);
createStaticServer(dir, () => coin).listen(port, () => {
  console.log(`serving ${dir}`);
  console.log(`open http://localhost:${port}/  (/simd-coin.json is the ${args.has("--live") ? "live" : "pre-launch"} sample)`);
});
