// The front-end half of MermaidSlate: renders a `MermaidDiagram`'s source to SVG.
//
// A bare component module — it default-exports the component and never names its own kind. Slate
// wraps this export and registers it under the type-derived kind (see `_register!` in
// src/MermaidSlate.jl), which is why "MermaidSlate.MermaidDiagram" appears nowhere here.
//
// `mermaid` resolves through the page's import map, declared once by `provide_import!` — live, and
// inlined as a self-contained module in an offline export.
import { html, useSignal } from "@slate/widget";

// One Mermaid instance per page, loaded on first use. Every diagram shares it: the import is a
// module-level promise rather than a per-render `import()`, so ten diagrams cost one fetch and one
// parse, not ten.
let mermaidPromise = null;
const loadMermaid = () => (mermaidPromise ??= import("mermaid").then((m) => m.default));

// Mermaid's `render` needs an id unique across the whole document — it briefly attaches a measuring
// node to the body — so diagrams on one page cannot share one.
let seq = 0;
const nextId = () => `mermaid-slate-${++seq}`;

// `initialize` sets GLOBAL config and `render` is async, so two diagrams on different themes can
// interleave and one can draw with the other's palette. Serialising the initialize+render pairs is
// cheaper than fighting it, and diagram rendering is not a hot path.
let queue = Promise.resolve();
const enqueue = (fn) => (queue = queue.then(fn, fn));

// ── Following the notebook's theme ────────────────────────────────────────────
// `theme = "auto"` (the default) means "match Slate". Deliberately measured from the live `--bg`
// rather than read off a list of theme names: the palette is what actually determines whether a
// dark or light diagram reads correctly, so this stays right for themes added after this was
// written, and for a custom one that never appears in any list.
function isDarkBackground() {
  let s = "";
  try {
    s = getComputedStyle(document.documentElement).getPropertyValue("--bg").trim();
  } catch (_) {}
  let r, g, b, m;
  if ((m = s.match(/^#([0-9a-f]{3})$/i))) {
    [r, g, b] = [0, 1, 2].map((i) => parseInt(m[1][i] + m[1][i], 16));
  } else if ((m = s.match(/^#([0-9a-f]{6})$/i))) {
    [r, g, b] = [0, 2, 4].map((i) => parseInt(m[1].slice(i, i + 2), 16));
  } else if ((m = s.match(/^rgba?\(([^)]+)\)$/i))) {
    [r, g, b] = m[1].split(",").map(Number);
  } else {
    return true; // unreadable → assume dark, which is Slate's default
  }
  return 0.2126 * r + 0.7152 * g + 0.0722 * b < 128;
}

const resolveTheme = (t) =>
  t && t !== "auto" ? t : isDarkBackground() ? "dark" : "default";

// Live hosts drawing on "auto", so a theme switch can redraw them. Entries are dropped when their
// element leaves the DOM — a cell re-run or a deleted cell would otherwise leak one per render.
const autoHosts = new Set();
if (!window.__mermaidSlateThemeHook) {
  window.__mermaidSlateThemeHook = true;
  const prev = window._onSlateThemeChange;
  window._onSlateThemeChange = function () {
    try { prev && prev.apply(this, arguments); } catch (_) {}
    for (const entry of [...autoHosts]) {
      if (!entry.el.isConnected) { autoHosts.delete(entry); continue; }
      entry.redraw();
    }
  };
}

// ── Rendering for print ───────────────────────────────────────────────────────
// Slate's PDF export captures each mounted component as a figure; without this hook it would take
// the SVG already on screen, and that SVG does not survive Typst. Two reasons, both from the LIVE
// config above and both invisible in a browser:
//
//   - `htmlLabels` (Mermaid's default) puts every node label in a `<foreignObject>` — HTML inside
//     the SVG. Typst renders SVG through resvg, which has no HTML engine, so every label in a
//     flowchart, state or class diagram comes out blank.
//   - `fontFamily: inherit` resolves against the page. A file has no page, so the text falls back to
//     whatever the renderer picks and the boxes Mermaid measured no longer fit it.
//
// Turning `htmlLabels` off is not a fix on its own: labels then become SVG `<text>`, which shows any
// HTML in the source (`<b>`, `<small>`, entities) as literal tags, and the PDF's fonts have no emoji.
// A diagram that looks right on screen should look the same on paper, so a diagram that needs HTML
// labels is rasterised by the browser that already draws it correctly (`rasterFigure`). Diagrams
// without `<foreignObject>` (sequence, Gantt, ...) stay vector through `vectorFigure`, as does any
// diagram in a browser that refuses to read back the canvas.
//
// Both renders are their own renders, not transforms of the live one, with the theme resolved from
// the EXPORT palette rather than the live one: the notebook may be dark on screen and the PDF light.
// `exportFigure` is a named export, picked up by `registerComponent`.
//
// Helvetica/Arial specifically: Mermaid measures label text in the browser to size each node, and
// Typst re-renders it. Metrics only agree if both sides resolve the same font, so the pair to name
// is the one present almost everywhere rather than the one that looks best in either place alone.
const PRINT_FONT = "Helvetica, Arial, sans-serif";

// A page is not a viewport. On screen a diagram is as wide as it wants to be and the reader scrolls;
// on paper it is scaled to the text column, and everything in it shrinks by the same factor — so a
// diagram that lays itself out at 1600px arrives with 4pt labels. These two settings are what keep a
// diagram's TEXT legible after that scaling, by making the drawing narrower rather than the type
// smaller. Both are export-only; neither would be an improvement on screen.
const PRINT_WIDTH = 1000;      // lay out at ~1.5× a text column, so labels survive the scale-down
const PRINT_WRAP  = 400;       // ...and a long identifier stays one word instead of hard-breaking

// Raster resolution: 3× the diagram's own size, capped in total pixels so a very large diagram
// doesn't exceed the browser's canvas limit or bloat the PDF.
const RASTER_SCALE = 3;
const RASTER_MAX_PIXELS = 32e6;

export async function exportFigure(el, { params, dark }) {
  const theme = params.theme && params.theme !== "auto" ? params.theme : dark ? "dark" : "default";
  // Through the same queue as a live draw: `initialize` is global config, so an export landing
  // between a diagram's initialize and its render would draw it in the export's theme.
  return enqueue(async () => {
    const mermaid = await loadMermaid();
    const png = await rasterFigure(mermaid, el, params.source, theme);
    return png ? { png } : vectorFigure(mermaid, params.source, theme);
  });
}

async function vectorFigure(mermaid, source, theme) {
  mermaid.initialize({
    startOnLoad: false,
    theme,
    securityLevel: "loose",
    fontFamily: PRINT_FONT,
    htmlLabels: false,
    flowchart: { htmlLabels: false, wrappingWidth: PRINT_WRAP },
    class: { htmlLabels: false },
    state: { wrappingWidth: PRINT_WRAP },
    gantt: { useWidth: PRINT_WIDTH },
  });
  const { svg } = await mermaid.render(nextId(), source);
  return { svg };
}

// The screen render as a base64 PNG, or null when the diagram has no HTML labels (vector is better)
// or the browser won't rasterise it.
async function rasterFigure(mermaid, el, source, theme) {
  // The SVG is drawn as an isolated image, where `inherit` has nothing to inherit from. Naming the
  // page's font makes Mermaid measure the labels in the same font the image will draw them in.
  const fontFamily = getComputedStyle(el).fontFamily || "system-ui, sans-serif";
  mermaid.initialize({ startOnLoad: false, theme, securityLevel: "loose", fontFamily });
  const { svg } = await mermaid.render(nextId(), source);
  if (!svg.includes("<foreignObject")) return null;

  // Mermaid's string is HTML-serialised (`<br>` unclosed, ...), which fails to load as an image.
  // Parsing it into the DOM and writing it back out with XMLSerializer gives well-formed XML.
  const holder = document.createElement("div");
  holder.innerHTML = svg;
  const node = holder.querySelector("svg");
  const vb = node && node.viewBox && node.viewBox.baseVal;
  if (!vb || !vb.width || !vb.height) return null;
  node.setAttribute("width", vb.width);
  node.setAttribute("height", vb.height);
  node.style.maxWidth = "none";
  const xml = new XMLSerializer().serializeToString(node);

  const img = new Image();
  img.src = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(xml);
  try { await img.decode(); } catch (_) { return null; }

  const scale = Math.min(RASTER_SCALE, Math.sqrt(RASTER_MAX_PIXELS / (vb.width * vb.height)));
  const canvas = document.createElement("canvas");
  canvas.width = Math.ceil(vb.width * scale);
  canvas.height = Math.ceil(vb.height * scale);
  const ctx = canvas.getContext("2d");
  ctx.scale(scale, scale);
  ctx.drawImage(img, 0, 0, vb.width, vb.height);
  // Safari marks a canvas that has drawn an SVG with `<foreignObject>` as tainted, so reading it
  // back throws there; the caller falls back to the vector render.
  try { return canvas.toDataURL("image/png").split(",")[1] || null; } catch (_) { return null; }
}

export default ({ params }) => {
  const error = useSignal("");

  // A callback ref rather than an effect: it fires with the node on mount and on every re-render,
  // so the key check below is what keeps a re-render cheap. Comparing the rendered source (not just
  // identity) means a reactive diagram whose text didn't change doesn't re-run Mermaid at all.
  const draw = (el) => {
    if (!el) return;
    const theme = resolveTheme(params.theme);
    const key = `${theme}\0${params.source}`;
    if (el._mermaidKey === key) return;
    el._mermaidKey = key;

    if (!params.theme || params.theme === "auto") {
      autoHosts.add({ el, redraw: () => { el._mermaidKey = null; draw(el); } });
    }

    enqueue(async () => {
      try {
        const mermaid = await loadMermaid();
        mermaid.initialize({
          startOnLoad: false,
          theme,
          securityLevel: "loose",
          fontFamily: "inherit",   // the notebook's type, not Mermaid's own stack
        });
        const { svg } = await mermaid.render(nextId(), params.source);
        // A newer draw may have started while this one parsed; dropping the stale result keeps the
        // latest edit on screen instead of whichever async render happened to finish last.
        if (el._mermaidKey !== key) return;
        el.innerHTML = svg;
        error.value = "";
      } catch (e) {
        // Mermaid's parse errors name the offending line, so they're worth showing verbatim. The
        // previous SVG is cleared: a stale diagram beside an error reads as though the edit worked.
        el.innerHTML = "";
        el._mermaidKey = null;
        error.value = String((e && e.message) || e);
      }
    });
  };

  return html`
    <div class="mermaid-slate">
      <div class="mermaid-slate-out" ref=${draw}></div>
      ${error.value
        ? html`<pre class="mermaid-slate-err">${error.value}</pre>`
        : null}
    </div>
    <style>
      .mermaid-slate-out { display: flex; justify-content: center; padding: 0.5rem 0 }
      .mermaid-slate-out svg { max-width: 100%; height: auto }
      .mermaid-slate-err {
        color: var(--red, #ff8080); font-family: ui-monospace, monospace;
        white-space: pre-wrap; margin: 0; padding: 0.5rem;
      }
    </style>`;
};
