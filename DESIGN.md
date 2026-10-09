# Swarm Tester ($TESTER) — website design system

This documents the design as implemented in `site/` (source) and exported to `dist/`. It is extracted
from `site/styles.css`, `site/index.html` and `site/app.js`, and confirmed against the rendered export
in headless Chrome (see `artifacts/validation.md`, copied in-repo as `site/VALIDATION.md`, for what
was and was not checked). It exists so a
later contributor can add a page or a module that belongs to the same product.

## Overview

The audience is memecoin visitors who arrive from the SIMD Launchpad. The visual character is the
SIMD Swarm "meme" template's control room: a wall of beige hardware panels (the `panels.webp` art
plus a fine 64px module grid), hard 2px ink borders with offset hard shadows, and a black terminal
with green signal accents at the centre. Everything on the page is a "module" bolted onto the wall:
the terminal, LCD readouts, the Swarm Lab workstation grid, Einstein's machine, and three text
modules (How to buy, Lore, Tokenomics).

System-wide rules:

- Two surfaces only: beige panels (`--bg-panel`, `--bg-panel-2`) and black LCD/CRT screens
  (`--bg-lcd`). Text sits on one of those, never on the wall art.
- Green (`--signal`) means "live signal and primary action". Blue (`--accent-2`, the lab-coat blue
  from the coin logo) is the secondary accent: it marks a *changed machine state* (coolant on, cool
  core, lever engaged) and the focus ring. Amber (`--warn`) is reserved for sparks and the third LED.
- Headings and labels are uppercase IBM Plex Mono with wide tracking; body copy is Inter.
- Motion is ambient and pausable: every keyframe animation reads `animation-play-state: var(--play)`.

Page-specific arrangements (the hero's two-column terminal, the 4×2 workstation grid, the machine's
gadget/deck split) are compositions, not rules.

## Colors

All values are hex custom properties in `site/styles.css` (`:root`). Primitives are named by hue and
are only referenced by the semantic tokens; components use the semantic tokens.

| Role token | Value (primitive) | Used for |
| --- | --- | --- |
| `--bg-page` / `--bg-panel` | `#d9d6cc` (`--beige-200`) | page fallback, panel modules, header bar, LCD cards, footer |
| `--bg-panel-2` | `#c9c5b8` (`--beige-300`) | inset panels: workstation cards, gadget, control deck, copy/switch buttons |
| `--bg-panel-raised` | `#e6e3d9` (`--beige-100`) | dial faces, lever knob, hover on the copy button |
| `--bg-lcd` | `#0c0f0c` (`--lcd-900`) | terminal, LCD readouts, CRT screens, oscilloscope, bars |
| `--text` | `#141414` (`--ink-900`) | body text on beige |
| `--text-muted` | `#4d4c45` (`--ink-600`) | small uppercase labels, captions, notes (5.93:1 on `--bg-panel`, 4.99:1 on `--bg-panel-2`) |
| `--line` | `#2a2a2a` (`--ink-800`) | all 2–3px borders and hard offset shadows |
| `--text-on-lcd` | `#d8ffe0` (`--green-100`) | default text inside the terminal |
| `--text-on-lcd-2` | `#c8e8cf` (`--green-200`) | hero description |
| `--text-on-lcd-muted` | `#9fd8aa` (`--green-300`) | terminal header, prompt line |
| `--text-log` | `#8fb79a` (`--green-400`) | terminal log lines, workstation code |
| `--signal` | `#3cff7a` (`--green-500`) | LCD digits, primary button fill, LEDs, logo frame, core glow, progress fills |
| `--signal-shadow` | `#0a3d1a` (`--green-900`) | hard shadow under `.btn` |
| `--green-600` | `#1fd65c` | primary button hover |
| `--line-lcd` | `#1d2a1f` | dividers inside the terminal |
| `--accent-2` | `#2b49f2` (`--blue-500`) | lever knob when engaged, Pepe lab coats (in the SVG symbols) |
| `--accent-2-soft` | `#9fb0ff` (`--blue-200`) | event lines in the log, "compiling" code on screens |
| `--focus` | `#3452ff` (`--blue-400`) | focus ring, cool core and trace when coolant is on |
| `--text-link-on-panel` | `#1b2f9e` (`--blue-700`) | links inside beige modules (7.42:1) |
| `--warn` | `#ffb43c` (`--amber-500`) | third LED, sparks, "build ok" bar, rocket flame |

Measured contrast (rendered pairs, headless Chrome, `site/tools/check.mjs`): every text pair is ≥
4.99:1; the focus ring is 3.2:1 or better against beige, the darker beige, the LCD black and the
green button (computed from the declared hex values in `test/scratch`, see validation).
There is no dark theme and no other ramp; do not add one.

## Typography

Fonts are self-hosted latin subsets in `site/assets/fonts/` (declared with `@font-face` at the top
of `site/styles.css`, `font-display: swap`, latin `unicode-range`):

- `Inter` — `Inter-variable-latin.woff2`, variable weight axis `100 900` (the page uses 500, 700, 900).
- `IBM Plex Mono` — `IBMPlexMono-400-latin.woff2` and `IBMPlexMono-600-latin.woff2`.

Stacks: `--sans: Inter, system-ui, -apple-system, "Segoe UI", sans-serif` and
`--mono: "IBM Plex Mono", ui-monospace, "SFMono-Regular", Menlo, monospace`. Non-latin characters
fall back to the system stacks by design.

| Role | Face | Size / line-height | Notes |
| --- | --- | --- | --- |
| Coin name `h1.name` | Inter 900 | `clamp(40px, 7vw, 84px)` / 0.95 | `letter-spacing: -.02em`, `text-wrap: balance`, white on the terminal |
| Ticker `.ticker` | Plex Mono 600 | 28px | `--signal` |
| Section headings `h2` (`.lab h2`, `.machine h2`, `.mod h2`) | Plex Mono 600 | 14px | uppercase, `letter-spacing: .14em` |
| Body (`body`, `.mod p/li/dd`, `.lab-sub`) | Inter 500 | 16px (15px in modules) / 1.5 | measure capped at `--measure: 60ch`, `text-wrap: pretty` |
| Hero description `.desc` | Plex Mono 400 (inherits the terminal) | 16px / 1.55 | |
| LCD labels `.lcd small`, `.ctl-label`, `.specs dt` | Plex Mono | 11–12px | uppercase, `letter-spacing: .14em`, `--text-muted` |
| LCD values `.lcd b` | Plex Mono | 24px / 1.3 (18px in `.lcd.inline`) | `font-variant-numeric: tabular-nums`, `overflow-wrap: anywhere` |
| Terminal log `.log`, prompt, header bar, footer | Plex Mono 400 | 12–13px / 1.5 | |
| Buttons `.btn` | Inter 700 | 16px (`.btn.build` 20px uppercase) | |
| Workstation code `.code` | Plex Mono 400 | 10px / 1.4 | decorative, inside an `aria-hidden` grid |

Rules: `-webkit-font-smoothing: antialiased` once on `html`; links use `text-underline-position:
from-font` and `text-decoration-thickness: from-font`; values that change use tabular numerals; long
values (the contract address) wrap with `overflow-wrap: anywhere` instead of truncating.

## Layout

- Spacing steps: `--space-1` 4px, `--space-2` 8px, `--space-3` 12px, `--space-4` 16px, `--space-5`
  22px, `--space-6` 28px. Modules are 22px apart; inside a module the padding is 16–18px; controls
  inside the deck are 16px apart (24px between dials).
- Content width: 1000px (`max-width` on `.term`, `.lcds`, `.lab`, `.machine`, `.mods`, `footer`);
  the header bar is 1100px. All centred with `margin-inline: auto`; the wall has 16px side padding
  plus `env(safe-area-inset-*)`.
- Grids: `.lcds` and `.mods` use `repeat(auto-fit, minmax(200px|280px, 1fr))`; `.ws-grid` uses
  `repeat(auto-fill, minmax(196px, 1fr))` (4 per row at 1000px); `.term-body` is `232px 1fr`;
  `.machine-body` is `1.2fr 1fr`.
- Breakpoints come from where the content breaks: `≤860px` the machine stacks gadget over deck;
  `≤720px` the hero stacks and centres, the logo frame shrinks to 178px; `≤480px` the header
  centres, the workstation grid is two columns, the two hero buttons go full width, the core and
  Einstein shrink. Verified in Chrome at 320, 390, 768 and 1280px with no horizontal overflow.
- Logical properties (`padding-inline`, `margin-inline-start`, `inset-inline-start`, `float:
  inline-end`) are used for direction-dependent spacing.

## Elevation & depth

Flat, hard-edged hardware: structure is drawn with borders, not soft shadows.

- Modules: `border: 2px solid var(--line)` plus a hard offset shadow `4px 4px 0 var(--line)` (the
  terminal uses 3px border and `8px 8px 0`; dials `3px 3px 0`; `.lcd.inline` `3px 3px 0`).
- Glow is the only soft shadow and only on live hardware: the logo frame (`0 0 40px rgba(60,255,122,.35)`
  plus an inset glow), screens (`inset 0 0 18px rgba(60,255,122,.18)`), the powered core
  (`0 0 36px var(--core-glow)`), an engaged lever (`0 0 12px var(--accent-2)`), LCD digits
  (`text-shadow: 0 0 10px rgba(60,255,122,.6)`).
- Stacking: `.wall::before` draws the module grid overlay; every direct child of the wall is
  `position: relative` so it paints above it. The rocket (`.rocket`, `z-index: 2`) is the only element
  that needs an explicit z-index. The skip link is `z-index: 20`.
- Images get a 1px `rgba(255,255,255,.1)` outline inside the dark frame.

## Shapes

- Rectangles with square corners for all panels, buttons and LCDs (no radius).
- Rounded only where the hardware is round: dials (`border-radius: 50%`), the core and its rings,
  LEDs, the lever track (13px) and knob (10px), the CRT frames (10px outer / 7px inner scanline layer,
  screens 6px), the motion switch's pill indicator (8px).
- Scanlines on every screen: `repeating-linear-gradient(0deg, rgba(0,0,0,.18–.2) 0 2px, transparent 2px 4px)`
  as an `::after` overlay with `pointer-events: none`.

## Components

All components are plain HTML/CSS patterns in `site/index.html` and `site/styles.css`; behaviour is
in `site/app.js` (a classic script, `use strict`, no globals).

- **Header bar `.bar`** — brand, `<nav aria-label="Sections">` anchor links (8px vertical padding so
  each is a 36px-high target), LED cluster (`aria-hidden`), and the motion switch.
- **Motion switch `.sw`** (`button#motion`, `aria-pressed`) — label "Run animations" describes the ON
  state; the pseudo-elements draw a pill indicator and an "on/off" word. It sets
  `html[data-motion="on|off"]`, which drives `--play`. `prefers-reduced-motion: reduce` sets the
  default to off; a user choice overrides it for the session.
- **Terminal `.term`** — `.term-head` status line (workers, chain, status), `.term-body` grid (CRT
  frame + copy), `.log` (`<pre>`, max 6 lines; `.hi` green highlight, `.ev` blue event lines),
  `.prompt`. Extend it by appending `<span>` lines through `logLine()` in `app.js`.
- **Buttons `.btn`** — filled green primary (`Buy $TESTER`); `.btn.ghost` outlined secondary
  (`View chart`); `.btn.build` the 56px BUILD control. 48px min height, hover darkens to
  `--green-600` (only under `@media (hover: hover)`), `:active` scales to 0.96, busy state uses
  `aria-disabled="true"` (keeps focus). Exactly one filled action per view.
- **LCD card `.lcd`** — `<small>` label + `<b>` value; `.lcd.inline` is the compact variant used
  inside the lab head and machine readouts. The contract card wraps `.ca` (value + `button#copy`,
  natively `disabled` until a token address exists; label flips to "Copied" for 1.5s).
- **Workstation `.ws`** (generated by `app.js`, 8 items, the list is `aria-hidden`) — `.screen`
  with `.code` lines and a `.caret`, a `.pepe` SVG `<use href="#pepe">`, `.pbar` progress fill,
  `.ws-stat` caption. States via `data-state="typing|compiling|done"`; `done` fires the `.spark`
  burst and an amber bar.
- **Machine `.machine`** — `.gadget` (Einstein `<use href="#einstein">`, `.core` with three rings,
  `.bay` holding the `svg#rocket` (`<use href="#rocket-shape">`), the `.scope` oscilloscope whose
  two `<path>`s are redrawn by `drawTrace()`, three `.lcd.inline` readouts) and `.deck`
  (`.dial` buttons with `--angle`, `.lever` toggle buttons with `aria-pressed`, the BUILD row with
  `.build-bar`, and `p#machine-status[role="status"]`, the page's single polite live region).
  State classes: `.on` (powered, set by an `IntersectionObserver` at 40% visibility or by BUILD),
  `.cool` (coolant lever, switches `--core-color`/`--core-glow` to blue), `.over` (overdrive,
  `--spin: 1.5s`).
- **Text module `.mod`** — panel with an uppercase `h2`; variants used: ordered list (`How to buy`,
  with the decorative `.dial-deco` floated to the inline end), paragraphs (`Lore`), and the
  `dl.specs` two-column definition list (`Tokenomics`). Links inside use `--text-link-on-panel`.
- **Footer** — single mono line with one link.

Keyboard and focus: all controls are native `<button>`/`<a>`; the global `:focus-visible` ring is
`3px solid var(--focus)` with `3px` offset; the first Tab stop is the `.skip` link to `#main`; all
`[id]` targets have `scroll-margin-top: 16px`.

Loading/empty states: before `/simd-coin.json` returns a token the LCDs show `—`, the contract reads
`launching…`, copy is disabled and both buttons point at the launchpad; a 404 keeps that state.

## Do's and don'ts

- Start a new module from `.mod` (text) or `.lab`/`.machine` (1000px panel with 18px padding); keep
  the 2px `--line` border and 4px hard shadow so it reads as hardware on the wall.
- Put text only on `--bg-panel`, `--bg-panel-2` or `--bg-lcd`; use the matching text token
  (`--text`/`--text-muted` on beige, the green ramp on black). Do not place text over the wall art.
- One filled green `.btn` per view; secondary actions are `.btn.ghost` or the small `.ca button`
  style. Keep blue for state and focus, not for calls to action.
- Any new animation must use `animation-play-state: var(--play)` so the header switch and the OS
  preference pause it, and must have a text or colour cue that works while paused.
- Never hardcode a contract address, price or URL that `/simd-coin.json` supplies; extend `paint()`.
- Do not add forms, wallet connectors, third-party scripts or font CDNs; the export must stay a
  self-contained static site with relative asset URLs.

Recipe for one more page: copy `site/index.html`'s head (fonts, `styles.css`), keep the `.wall` and
`.bar`, put content in `<main>` as `.mod` panels inside a `.mods` grid, close with the same footer,
and include `app.js` only if the page needs the live data or the machine.
