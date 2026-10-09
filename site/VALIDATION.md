# Swarm Tester website — validation record

Worker-side validation of the one-page site in `site/` and its export in `dist/`. This is the
worker's own report; it is not an independent certification.

## 1. Scope and assumptions

- Reviewed: the single page `dist/index.html` (built from `site/`), in its three data states
  (no `/simd-coin.json` yet → 404, pre-launch JSON without a token, live JSON with token and market
  data) and its primary interactions: Buy/Chart links, copy address, motion switch, scroll power-up,
  dials, levers, BUILD/rocket, keyboard navigation.
- Build/export: `site/tools/build.mjs` copies the static source to `dist/` (no bundler, no build
  step) and checks it. Export served under a subpath (`/preview/`) during checks so that broken
  relative URLs would surface.
- Inferred choices: the logo is framed as a CRT screen rather than cropped into the template's circle
  because it is a full scene, not an avatar; the secondary accent is the lab-coat blue measured in the
  logo (`#2b49f2` family); fonts are self-hosted latin subsets instead of the template's Google Fonts
  link so the page makes no third-party request; a "Run animations" switch was added so the ambient
  animation can be paused (WCAG 2.2.2) and it defaults to off under `prefers-reduced-motion`.
- Launch facts on the page (supply, no mint, no fee, 90% pool / 10% swarm / remainder to the dead
  address, Uniswap v4, IMD pair, 1.25% pool fee) come from the assignment; no price or return claims.
- Excluded: no dark theme, no localization, no forms, no wallet flows (none requested).

## 2. Coverage (six domains)

| Domain | Status | Evidence / unperformed sub-checks |
| --- | --- | --- |
| Accessibility | Checked | Native buttons/links; one `h1`, `h2`s, `main`, skip link; accessible names on every control (script check); `:focus-visible` ring verified visually (`focus-buy-button.jpg`) and computed on 12 Tab stops; Space toggles a lever; `role="status"` live region for build/copy announcements; decorative SVG and workstation grid `aria-hidden`; 24×24 target floor checked at 320/390/768; `prefers-reduced-motion` emulation checked. **Not verified:** a real screen-reader session, forced-colors mode, browser-native 200% zoom (narrow viewports only), physical touch devices. |
| Layout | Checked | No horizontal overflow at 320, 390, 768, 1280 (script, `scrollWidth` and per-element rect check); stacking breakpoints at 860/720/480 viewed in screenshots; logical properties used for inline spacing. **Not verified:** RTL mirror (page is English-only), 200% native zoom. |
| Writing | Checked | Verb-first buttons (`Buy $TESTER`, `View chart`, `Copy`, `Build`); switch labelled for its ON state (`Run animations`); links describe their destination; sentence case for body copy, uppercase mono labels as the template's house style; copy error states say what to do ("Select the address and copy it by hand"). Source review only, as the guide allows. |
| Typography | Checked | Self-hosted Inter variable (100–900) and IBM Plex Mono 400/600 confirmed loaded via `document.fonts`; headings descend (h1 clamp 40–84px, h2 14px uppercase); body 15–16px/1.5 with a 60ch measure; tabular numerals on LCD values; `text-wrap: balance/pretty`; the 42-char contract address wraps with `overflow-wrap: anywhere` (seen in `desktop-1280-live.jpg`). Decorative workstation code is 10px inside an `aria-hidden` block. |
| Colors | Checked | Hex primitives + semantic tokens in `site/styles.css`. Rendered contrast measured in Chrome from computed colours against the nearest opaque background (`site/tools/check.mjs`): all 21 text pairs ≥ 4.99:1 (lowest: `.ws-stat`, `.ctl-label`, `.ca button` at 4.99:1 on `#c9c5b8`). Focus ring `#3452ff` computed against declared backgrounds: 3.74:1 on `#d9d6cc`, 3.21:1 on `#c9c5b8`, 3.45:1 on `#0c0f0c`, 4.4:1 on `#3cff7a` (`test/scratch/contrast.mjs`). **Not verified:** colour-gamut (P3) rendering; text over the wall art is avoided by design, so no image-background pairs were measured. |
| UI | Checked | Hover only under `(hover: hover)`; press scale 0.96 on buttons/dials; transitions name their properties (120–300ms); keyframes only for ambient loops and the one-shot spark; rocket flight uses the Web Animations API with an ease-in curve and a static text cue; busy state via `aria-disabled` keeps focus. **Not verified:** motion replayed at 10% speed in a DevTools Animations panel (not available headless). |

## 3. Findings and fixes

| # | Severity | Location | Finding | Fix | Recheck |
| --- | --- | --- | --- | --- | --- |
| 1 | HIGH | `site/index.html` (rocket `<symbol>` and `svg#rocket`) | Duplicate `id="rocket"` on the symbol and the instance: the rocket never rendered and `getElementById` returned the symbol, so BUILD animated nothing. | Renamed the symbol to `rocket-shape`. | Rocket visible in `machine-powered-idle.jpg`; new script check "no duplicate ids" passes. |
| 2 | MEDIUM | `site/styles.css` `--ink-600`, `--blue-400` | Declared muted text `#5a5951` on `#c9c5b8` measured 4.08:1 (< 4.5:1 for 11–12px labels); focus ring `#3f5cff` on `#c9c5b8` measured 2.91:1 (< 3:1). | `--ink-600: #4d4c45` (4.99:1), `--blue-400: #3452ff` (3.21:1). | Rendered measurement in run 2: all pairs pass. |
| 3 | MEDIUM | `site/app.js` `renderControls` | Core/trace colours were set as inline hex values, bypassing the token system. | Replaced by `.cool`/`.over` state classes that switch tokens in CSS. | Lever check passes; colours come from `--blue-400`/`--signal`. |
| 4 | LOW | `site/styles.css` `.ws-grid`, `.code`, `.ws-stat` | 6+2 ragged workstation rows at 1000px; 9px screen text and 11px captions below the 12px floor. | `minmax(196px, 1fr)` → 4×2; code 10px (decorative, hidden from AT), caption 12px. | Seen in `desktop-1280-prelaunch.jpg` (run 2). |
| 5 | LOW | template behaviour | Template's ambient animation (LEDs, bobbing logo, log) had no pause control. | Added the header `Run animations` switch bound to `--play`; OS reduced-motion sets the default. | Script checks "animation switch pauses/resumes" and "reduced motion" pass. |
| 6 | LOW | `site/tools/check.mjs` | Two false negatives in the check script (browser's own 404 console line; carets inside an `overflow: hidden` screen flagged as overflow). | Script now ignores the expected `/simd-coin.json` network line and elements clipped by an ancestor. | Run 2: 48 passed, 0 failed. |

## 4. Verification (actual commands and outcomes)

Run from `site/` on 2026-10-09 with Node 24.21.0, npm 11.19.0, Google Chrome via Playwright
(resolved from the globally installed `@playwright/mcp`):

| Command | Result |
| --- | --- |
| `npm install` | 1 package (typescript 5.9.3); `package-lock.json` written |
| `npm run build` | exit 0 — `dist/` written, 8 files, 306,481 bytes; relative URLs, no hardcoded 0x address, no external fonts/trackers/forms |
| `npm run typecheck` (`tsc -p tsconfig.json`, strict `checkJs` on `app.js`) | exit 0 |
| `npm run check` (run 1) | 45 passed, 2 failed (both script false negatives, see finding 6) |
| `npm run check` (run 2, after fixes 1–6, final source) | exit 0 — 48 passed, 0 failed, 0 skipped |
| `forge build` / `forge test` (repository root) | compiler run successful; 51 tests passed, 0 failed |

Browser tooling note: the assignment's MCP browser tool (Playwright MCP, headless Chrome) refuses
`file:` URLs and no managed preview (`test/scratch/browser/preview.json`) was provided, and the
foreground-command rule forbids leaving a server running for it. The rendered inspection was therefore
done by `site/tools/check.mjs`, which starts its own server, drives the same headless Chrome through
the Playwright library within one bounded command, and saves screenshots that the worker then viewed.

Browser evidence (headless Chrome, `artifacts/screenshots/`, all from the final export):

- `desktop-1280-prelaunch.jpg` — full page at 1280×800, pre-launch JSON.
- `desktop-1280-live.jpg` — live JSON: contract address, formatted market readouts, "Copied" state.
- `focus-buy-button.jpg` — keyboard focus ring on the primary button over the terminal.
- `machine-powered-idle.jpg` — gadget after the scroll power-up (rocket in bay, trace live).
- `machine-build-launch.jpg` — after BUILD: "LAUNCHED", coolant on (blue core), status text.
- `mobile-320.jpg`, `mobile-390-full.jpg`, `mobile-768.jpg` — 320 viewport, 390 full page, 768 viewport.
- `desktop-reduced-motion.jpg` — `prefers-reduced-motion: reduce` emulation (switch off, paused).

Interactions exercised by the script: Tab order (skip link first; buy, chart, motion, freq, gain,
coolant, overdrive, build all reached with a visible ring), scroll power-up, both dials, both
levers (mouse and Space), BUILD → rocket → idle reset, motion switch off/on, copy to clipboard with
granted permission, live/404/pre-launch data states, touch-emulated BUILD at 390px.

## 5. Completion

**Complete for the stated scope.** Remaining limitations: the MCP browser tool itself could not
open the export (see the tooling note above; the Playwright-scripted Chrome run replaced it); no
screen-reader, forced-colors, native 200% zoom or physical-device checks; the live `/simd-coin.json` of the published origin was not
available to this run (mock payloads in `site/tools/serve.mjs` follow the documented shape); the
published site itself (https://swarmtester.si-md.xyz) is deployed by the publisher from the committed
`dist/`, which this run cannot observe.
