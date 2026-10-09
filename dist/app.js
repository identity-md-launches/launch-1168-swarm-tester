// Swarm Tester ($TESTER) · control-room behaviour. Classic script, no build step, no dependencies.
// Live data: /simd-coin.json on this same origin. The contract address is never hardcoded.
(function () {
  "use strict";

  /**
   * @typedef {Object} CoinMarket
   * @property {number|null|undefined} [marketCap]
   * @property {number|null|undefined} [priceUsd]
   * @property {number|null|undefined} [volume24h]
   */
  /**
   * @typedef {Object} Coin
   * @property {string} [name]
   * @property {string} [symbol]
   * @property {string} [token]
   * @property {string} [chainName]
   * @property {string} [coinUrl]
   * @property {string} [chartUrl]
   * @property {string} [status]
   * @property {CoinMarket} [market]
   */

  const COIN = { name: "Swarm Tester", symbol: "TESTER", launchpad: "https://www.si-md.xyz/launchpad/" };
  const WORKER_COUNT = 8;
  const root = document.documentElement;

  /** @param {string} id */
  const $ = (id) => {
    const el = document.getElementById(id);
    if (!el) throw new Error("missing #" + id);
    return el;
  };

  // ---- motion: the OS preference sets the default, the header switch overrides it ----
  const reduceQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
  let userChoseMotion = false;
  const motionSwitch = $("motion");
  /** @param {boolean} on */
  function setMotion(on) {
    root.dataset.motion = on ? "on" : "off";
    motionSwitch.setAttribute("aria-pressed", String(on));
  }
  const motionOn = () => root.dataset.motion === "on";
  setMotion(!reduceQuery.matches);
  motionSwitch.addEventListener("click", () => {
    userChoseMotion = true;
    setMotion(!motionOn());
    logLine(motionOn() ? "sim · animations resumed" : "sim · animations paused", "ev");
  });
  reduceQuery.addEventListener("change", () => { if (!userChoseMotion) setMotion(!reduceQuery.matches); });

  // ---- terminal log ----
  const log = $("log");
  const LINES = [
    "swarm lab · online · 8 engineers at their terminals",
    "worker #03 typing src/TESTERToken.sol",
    "forge build · compiled with solc 0.8.26 · cancun",
    "forge test · fixed supply · no owner · no mint",
    "einstein · inventing the next big thing",
    "pool · uniswap v4 · paired with IMD",
    "worker #06 compile ok · sparks",
    "status · launching…",
  ];
  let lineIndex = 0;
  /** @param {string} text @param {string} [cls] */
  function logLine(text, cls) {
    const t = new Date().toISOString().slice(11, 16);
    const span = document.createElement("span");
    if (cls) span.className = cls;
    span.textContent = "> " + t + "  " + text;
    log.appendChild(span);
    while (log.children.length > 6) log.firstChild && log.firstChild.remove();
  }
  function tickLog() {
    const i = lineIndex++ % LINES.length;
    logLine(LINES[i], i === LINES.length - 1 ? "hi" : "");
  }
  for (let i = 0; i < 4; i++) tickLog();
  window.setInterval(() => { if (motionOn()) tickLog(); }, 1400);

  // ---- live data from /simd-coin.json ----
  /** @param {number|null|undefined} n */
  const usd = (n) => {
    if (n == null || !Number.isFinite(Number(n))) return "—";
    const v = Number(n);
    if (v >= 1e9) return "$" + (v / 1e9).toFixed(2) + "B";
    if (v >= 1e6) return "$" + (v / 1e6).toFixed(2) + "M";
    if (v >= 1e3) return "$" + (v / 1e3).toFixed(1) + "K";
    if (v >= 1) return "$" + v.toFixed(2);
    return "$" + v.toPrecision(3);
  };
  const copyBtn = /** @type {HTMLButtonElement} */ ($("copy"));
  const buy = /** @type {HTMLAnchorElement} */ ($("buy"));
  const chart = /** @type {HTMLAnchorElement} */ ($("chart"));
  const buyLink = /** @type {HTMLAnchorElement} */ ($("buy-link"));
  let tokenAddress = "";
  /** @param {Coin} c */
  function paint(c) {
    const name = c.name || COIN.name;
    const symbol = c.symbol || COIN.symbol;
    document.title = name + " ($" + symbol + ")";
    $("name").textContent = name;
    $("ticker").textContent = "$" + symbol;
    $("chain").textContent = c.chainName || "—";
    $("status").textContent = c.status || "launching…";
    if (c.token) {
      if (c.token !== tokenAddress) logLine("deploy · contract live · " + c.token.slice(0, 10) + "…", "hi");
      tokenAddress = c.token;
      $("ca").textContent = c.token;
      copyBtn.disabled = false;
      const coinUrl = c.coinUrl || COIN.launchpad;
      buy.href = coinUrl;
      buyLink.href = coinUrl;
      chart.href = c.chartUrl || coinUrl;
    } else {
      $("ca").textContent = "launching…";
      copyBtn.disabled = true;
    }
    const m = c.market || {};
    $("mc").textContent = usd(m.marketCap);
    $("price").textContent = usd(m.priceUsd);
    $("vol").textContent = usd(m.volume24h);
  }
  function load() {
    return fetch("/simd-coin.json", { cache: "no-store" })
      .then((r) => (r.ok ? r.json() : null))
      .then((c) => { if (c && typeof c === "object") paint(/** @type {Coin} */ (c)); })
      .catch(() => null);
  }
  paint({});
  load();
  window.setInterval(load, 30000);

  // ---- copy the contract address ----
  const status = $("machine-status");
  copyBtn.addEventListener("click", () => {
    if (!tokenAddress) return;
    const done = () => {
      copyBtn.textContent = "Copied";
      window.setTimeout(() => { copyBtn.textContent = "Copy"; }, 1500);
      announce("Contract address copied.");
    };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(tokenAddress).then(done, () => announce("Unable to copy. Select the address and copy it by hand."));
    } else {
      announce("Unable to copy. Select the address and copy it by hand.");
    }
  });
  /** @param {string} text */
  function announce(text) { status.textContent = text; }

  // ---- the lab: rows of engineers typing, compiling and shipping ----
  const SNIPPETS = [
    "contract TESTERToken {", "  uint256 public constant", "    totalSupply = 1e27;", "  function transfer(", "    address to,", "    uint256 value", "  ) external returns (bool)", "  balanceOf[to] += value;", "  emit Transfer(from, to, v);", "forge build", "forge test -vv", "[PASS] testTransfer()", "[PASS] testNoMint()", "$ cast call --rpc-url", "// TODO: more sparks",
  ];
  /** @typedef {{el: HTMLElement, code: HTMLElement, bar: HTMLElement, stat: HTMLElement, state: "typing"|"compiling"|"done", lines: string[], progress: number, t: number, id: number}} Station */
  /** @type {Station[]} */
  const stations = [];
  const grid = $("workers-grid");
  for (let i = 0; i < WORKER_COUNT; i++) {
    const li = document.createElement("li");
    li.className = "ws";
    li.dataset.state = "typing";
    li.innerHTML =
      '<div class="screen"><pre class="code"></pre><i class="spark"></i></div>' +
      '<svg class="pepe" aria-hidden="true"><use href="#pepe"/></svg>' +
      '<div class="pbar"><i></i></div>' +
      '<span class="ws-stat"></span>';
    grid.appendChild(li);
    const station = {
      el: li,
      code: /** @type {HTMLElement} */ (li.querySelector(".code")),
      bar: /** @type {HTMLElement} */ (li.querySelector(".pbar i")),
      stat: /** @type {HTMLElement} */ (li.querySelector(".ws-stat")),
      state: /** @type {"typing"} */ ("typing"),
      lines: SNIPPETS.slice(i % 4, (i % 4) + 3),
      progress: 0,
      t: Math.floor(Math.random() * 20),
      id: i + 1,
    };
    stations.push(station);
    renderStation(station);
  }
  let buildsShipped = 0;
  /** @param {Station} s */
  function renderStation(s) {
    const shown = s.lines.slice(-5).join("\n");
    s.code.textContent = shown;
    if (s.state === "typing") {
      const caret = document.createElement("i");
      caret.className = "caret";
      s.code.appendChild(caret);
      s.stat.textContent = "#" + String(s.id).padStart(2, "0") + " typing";
    } else if (s.state === "compiling") {
      s.stat.textContent = "#" + String(s.id).padStart(2, "0") + " compiling " + s.progress + "%";
    } else {
      s.stat.textContent = "#" + String(s.id).padStart(2, "0") + " build ok";
    }
    s.bar.style.width = s.progress + "%";
  }
  /** @param {Station} s */
  function stepStation(s) {
    s.t++;
    if (s.state === "typing") {
      if (s.t % 2 === 0) s.lines.push(SNIPPETS[(s.id * 7 + s.t) % SNIPPETS.length]);
      if (s.lines.length > 12) s.lines.shift();
      if (s.t > 14 + (s.id % 5) * 3) { s.state = "compiling"; s.progress = 0; s.t = 0; s.lines.push("$ forge build"); }
    } else if (s.state === "compiling") {
      s.progress = Math.min(100, s.progress + 9 + (s.id % 4) * 3);
      if (s.progress >= 100) { s.state = "done"; s.t = 0; s.lines.push("compiled · ok"); buildsShipped++; $("built").textContent = String(buildsShipped); }
    } else if (s.t > 4) {
      s.state = "typing"; s.progress = 0; s.t = 0; s.lines = s.lines.slice(-2);
    }
    s.el.dataset.state = s.state;
    renderStation(s);
  }
  window.setInterval(() => { if (motionOn()) stations.forEach(stepStation); }, 260);

  // ---- Einstein's machine ----
  const machine = $("machine");
  const powerOut = $("power");
  const coreOut = $("core-out");
  const launchedOut = $("launched");
  const traceA = $("trace-a");
  const traceB = $("trace-b");
  const freqBtn = $("freq");
  const gainBtn = $("gain");
  const coolant = $("coolant");
  const overdrive = $("overdrive");
  const buildBtn = $("build");
  const buildFill = $("build-fill");
  const rocket = $("rocket");
  let powered = false;
  let power = 0;
  let freqStep = 6;   // 0..9 → 1.0 … 5.5 MHz
  let gainStep = 5;   // 0..9 → 0 … 90 %
  let rockets = 0;
  let busy = false;

  const freqMHz = () => 1 + freqStep * 0.5;
  const gainPct = () => gainStep * 10;
  /** @param {HTMLElement} btn @param {number} step */
  function setDial(btn, step) { btn.style.setProperty("--angle", String(-135 + step * 30) + "deg"); }
  function renderControls() {
    setDial(freqBtn, freqStep);
    setDial(gainBtn, gainStep);
    $("freq-out").textContent = freqMHz().toFixed(1) + " MHz";
    $("gain-out").textContent = gainPct() + "%";
    const cool = coolant.getAttribute("aria-pressed") === "true";
    const over = overdrive.getAttribute("aria-pressed") === "true";
    $("coolant-out").textContent = cool ? "on" : "off";
    $("overdrive-out").textContent = over ? "on" : "off";
    machine.classList.toggle("cool", cool);
    machine.classList.toggle("over", over);
    coreOut.textContent = !powered ? "cold" : cool && over ? "cryo+boost" : cool ? "cryo" : over ? "hot" : "warm";
    drawTrace(0);
  }
  /** @param {number} phase */
  function drawTrace(phase) {
    const over = overdrive.getAttribute("aria-pressed") === "true";
    const amp = (powered ? 8 + gainPct() * 0.3 : 3) * (over ? 1.6 : 1);
    const cycles = freqMHz() * 1.2;
    let a = "";
    let b = "";
    for (let x = 0; x <= 320; x += 4) {
      const ya = 45 - Math.sin((x / 320) * Math.PI * 2 * cycles + phase) * amp;
      const yb = 45 - Math.sin((x / 320) * Math.PI * 2 * cycles * 0.5 + phase * 0.7) * amp * 0.5;
      a += (x === 0 ? "M" : "L") + x + " " + ya.toFixed(1) + " ";
      b += (x === 0 ? "M" : "L") + x + " " + yb.toFixed(1) + " ";
    }
    traceA.setAttribute("d", a);
    traceB.setAttribute("d", b);
  }
  let phase = 0;
  let lastFrame = 0;
  /** @param {number} now */
  function frame(now) {
    if (powered && motionOn() && now - lastFrame > 40) { phase += 0.25; drawTrace(phase); lastFrame = now; }
    window.requestAnimationFrame(frame);
  }
  window.requestAnimationFrame(frame);

  freqBtn.addEventListener("click", () => { freqStep = (freqStep + 1) % 10; renderControls(); logLine("machine · freq " + freqMHz().toFixed(1) + " MHz", "ev"); });
  gainBtn.addEventListener("click", () => { gainStep = (gainStep + 1) % 10; renderControls(); logLine("machine · gain " + gainPct() + "%", "ev"); });
  /** @param {HTMLElement} lever @param {string} label */
  function wireLever(lever, label) {
    lever.addEventListener("click", () => {
      const on = lever.getAttribute("aria-pressed") !== "true";
      lever.setAttribute("aria-pressed", String(on));
      renderControls();
      logLine("machine · " + label + " " + (on ? "on" : "off"), "ev");
    });
  }
  wireLever(coolant, "coolant");
  wireLever(overdrive, "overdrive");

  /** @param {string} reason */
  function powerUp(reason) {
    if (powered) return;
    powered = true;
    machine.classList.add("on");
    renderControls();
    announce("Machine powered up" + reason + ". Turn the dials, throw the levers, or press Build.");
    logLine("einstein's machine · power up", "hi");
    const start = performance.now();
    const dur = motionOn() ? 1200 : 0;
    /** @param {number} now */
    const tick = (now) => {
      power = dur ? Math.min(100, Math.round(((now - start) / dur) * 100)) : 100;
      powerOut.textContent = power + "%";
      if (power < 100) window.requestAnimationFrame(tick);
    };
    window.requestAnimationFrame(tick);
  }
  if ("IntersectionObserver" in window) {
    const io = new IntersectionObserver((entries) => {
      if (entries.some((e) => e.isIntersecting)) { powerUp(" as you scrolled in"); io.disconnect(); }
    }, { threshold: 0.4 });
    io.observe(machine);
  }

  buildBtn.addEventListener("click", () => {
    if (busy) return;
    busy = true;
    buildBtn.setAttribute("aria-disabled", "true");
    powerUp("");
    buildBtn.textContent = "Building…";
    announce("Building…");
    buildFill.style.width = "0%";
    void buildFill.offsetWidth; // restart the fill from zero
    buildFill.style.width = "100%";
    window.setTimeout(launch, motionOn() ? 1400 : 0);
  });
  function launch() {
    rockets++;
    launchedOut.textContent = String(rockets);
    buildBtn.textContent = "Launched";
    announce("Build " + rockets + " complete. Rocket launched.");
    logLine("build #" + rockets + " complete · $" + COIN.symbol + " rocket launched", "hi");
    if (motionOn()) stations.forEach((s) => { s.state = "done"; s.progress = 100; s.t = 0; s.el.dataset.state = "done"; renderStation(s); });
    /** @param {Animation|null} flight */
    const reset = (flight) => {
      rocket.style.opacity = "0";
      if (flight) flight.cancel();
      window.setTimeout(() => {
        rocket.style.opacity = "1";
        buildFill.style.width = "0%";
        buildBtn.textContent = "Build";
        buildBtn.removeAttribute("aria-disabled");
        busy = false;
      }, 400);
    };
    if (motionOn() && typeof rocket.animate === "function") {
      const flight = rocket.animate(
        [{ transform: "translateY(0) rotate(0deg)" }, { transform: "translateY(-120vh) rotate(6deg)" }],
        { duration: 1600, easing: "cubic-bezier(0.5, 0, 0.9, 0.4)", fill: "forwards" }
      );
      flight.onfinish = () => reset(flight);
    } else {
      window.setTimeout(() => reset(null), 600);
    }
  }
  renderControls();
})();
