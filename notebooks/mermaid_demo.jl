try; import KaimonSlate; catch; error("This is a Kaimon Slate notebook — running it as plain Julia needs the KaimonSlate runtime in this environment. Add it with `import Pkg; Pkg.add(\"KaimonSlate\")`, or open it in Kaimon Slate."); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

#%% md id=title title
@md"""
# Mermaid diagrams in Slate

## Text-defined diagrams, generated from live Julia values

Kahli Burke
"""

#%% md id=overview
@md"""
[Mermaid](https://mermaid.js.org) turns a few lines of text into a rendered diagram. That
makes it a natural fit for a reactive notebook: a diagram stops being a static image you
maintain by hand and becomes *a function of your data*, recomputed like any other cell.

This notebook builds a small `mermaid()` helper on top of a browser ES-module import, then
uses it three ways:

1. **Literal diagrams** — the usual flowchart / sequence / state / ER catalogue.
2. **Interactive** — a live editor and a theme switcher, wired through `@bind`.
3. **Generated** — diagrams emitted from Julia values, where the text is computed rather
   than typed.
"""

#%% md id=setup_md
@md"""
## The helper

Two setup cells, and neither one is per-diagram. `@use` declares the browser-side import for
the whole notebook, so front-end JS can `import "mermaid"` by bare name — live and in a static
export. The `web` cell after it defines one function, `mermaidDiagram(root, theme)`, which
resolves that import, reads a diagram source out of the cell, and swaps the rendered SVG in.

Every diagram below is then a `web` cell with the same one-line JS pane. The source rides in a
hidden `<pre>` and is read back as `textContent`, which keeps Mermaid's arrows and `<|--` edges
out of any JS string escaping, and `root` scopes the lookup to that cell's own output so a page
full of diagrams never collides.

A `web` cell is the right vehicle here rather than a code cell returning `WebPage`: only the
`web` cell's JS is re-run when the cell re-renders, which is exactly what a reactive diagram
needs.
"""

#%% code id=mermaid_import
@use "mermaid" => "https://esm.sh/mermaid@11"

#%% md id=5697ad
@md"""
```mermaid
a -> b
```
"""

#%% web id=mermaid_setup
@web(css"""
.mermaid-out { display: flex; justify-content: center; padding: 0.5rem 0 }
.mermaid-out svg { max-width: 100%; height: auto }
.mermaid-err { color: #ff8080; font-family: monospace; white-space: pre-wrap; padding: 0.5rem }
""",
js"""
window.mermaidDiagram = async (root, theme = "dark") => {
  const out = root.querySelector(".mermaid-out");
  try {
    const mermaid = (await import("mermaid")).default;
    mermaid.initialize({ startOnLoad: false, theme, securityLevel: "loose",
                         fontFamily: "inherit" });
    const src = root.querySelector(".mermaid-src").textContent.trim();
    const id  = "mmd-" + Math.random().toString(36).slice(2);
    out.className = "mermaid-out";
    out.innerHTML = (await mermaid.render(id, src)).svg;
  } catch (err) {
    out.className = "mermaid-err";
    out.textContent = String(err.message ?? err);
  }
};
echo("mermaidDiagram(root, theme) ready");
""")

#%% md id=catalogue_md
@md"""
## Literal diagrams

Every cell below is the same shape — a `<pre class="mermaid-src">` holding the diagram text and
a one-line JS pane, `await mermaidDiagram(root)`. Mermaid picks the diagram type from the first
keyword of the source, so the only thing that changes between them is the text.

### Flowchart

The workhorse: nodes, shaped by their brackets, and edges that can carry labels.

One sharp edge, and it is Slate's rather than Mermaid's: the HTML pane interpolates
double-brace expressions, which is also Mermaid's hexagon-node syntax. A literal hexagon in the
HTML pane will be read as an interpolation and fail to parse as Julia. Put such a source in a
Julia string and interpolate the whole thing instead — which is what the generated section
below does anyway.
"""

#%% web id=flowchart
@web(html"""
<pre class="mermaid-src" hidden>
flowchart LR
    src[/"notebook.jl"/] --> parse[parse cells]
    parse --> dag[[build dependency graph]]
    dag --> stale{"any stale?"}
    stale -- no --> idle([idle])
    stale -- yes --> run[run cell]
    run <--> cache[(durable memo)]
    run --> render[render output]
    render --> stale
</pre>
<div class="mermaid-out"></div>
""",
js"""
await mermaidDiagram(root);
""")

#%% md id=sequence_md
@md"""
### Sequence diagram

Participants down the top, time down the page. `activate`/`deactivate` draw the lifeline
bars, and `Note` blocks annotate a moment.
"""

#%% web id=sequence
@web(html"""
<pre class="mermaid-src" hidden>
sequenceDiagram
    autonumber
    participant B as Browser
    participant H as Hub
    participant W as Worker

    B->>H: run cell "flowchart"
    activate H
    H->>H: mark dependents stale
    H->>W: eval source
    activate W
    W-->>H: value + display data
    deactivate W
    H-->>B: patch output
    deactivate H

    Note over H,W: a slow cell is promoted<br/>to a background job

    B->>H: cancel
    H->>W: interrupt
    W-->>H: Cancelled
    H-->>B: run chip clears
</pre>
<div class="mermaid-out"></div>
""",
js"""await mermaidDiagram(root);""")

#%% md id=state_md
@md"""
### State diagram

`stateDiagram-v2` is the one to reach for when the thing you are describing has a small set
of states and named transitions between them. Composite states nest with braces.
"""

#%% web id=state
@web(html"""
<pre class="mermaid-src" hidden>
stateDiagram-v2
    [*] --> Stale : parsed

    Stale --> Queued : upstream ready
    Queued --> Running : slot free

    state Running {
        [*] --> Evaluating
        Evaluating --> Rendering : value returned
        Rendering --> [*]
    }

    Running --> Fresh : ok
    Running --> Errored : exception
    Running --> Background : over grace window

    Background --> Fresh : job completed
    Background --> Cancelled : cancel_eval

    Fresh --> Stale : source or upstream changed
    Errored --> Stale : source edited
    Cancelled --> Stale
    Fresh --> [*] : cell deleted
</pre>
<div class="mermaid-out"></div>
""",
js"""await mermaidDiagram(root);""")

#%% md id=class_md
@md"""
### Class diagram

Class diagrams carry the widest edge vocabulary — inheritance, composition, aggregation,
association — and each arrow head means something specific.
"""

#%% web id=class
@web(html"""
<pre class="mermaid-src" hidden>
classDiagram
    class Cell {
        +String id
        +Symbol kind
        +String source
        +run()
        +stale()
    }
    class CodeCell
    class MarkdownCell
    class WebCell {
        +String html
        +String css
        +String js
    }

    Cell <|-- CodeCell
    Cell <|-- MarkdownCell
    Cell <|-- WebCell

    class Notebook {
        +Vector~Cell~ cells
        +DepGraph graph
    }
    Notebook "1" *-- "0..*" Cell : owns
    Notebook o-- Worker : drives
    WebCell ..> Worker : slateCall
</pre>
<div class="mermaid-out"></div>
""",
js"""await mermaidDiagram(root);""")

#%% md id=er_md
@md"""
### Entity relationship

Cardinality is spelled into the edge itself: `||` is exactly one, `o{` is zero-or-many, and
a dotted line marks a non-identifying relationship.
"""

#%% web id=er
@web(html"""
<pre class="mermaid-src" hidden>
erDiagram
    NOTEBOOK ||--o{ CELL : contains
    CELL ||--o{ OUTPUT : produces
    CELL }o--o{ CELL : "depends on"
    CELL ||--o| MEMO_ENTRY : "keyed by fingerprint"
    NOTEBOOK ||--|| WORKER : "bound to"

    CELL {
        string id PK
        string kind
        string source
        string state
    }
    MEMO_ENTRY {
        string fingerprint PK
        int    bytes
        string created_at
    }
</pre>
<div class="mermaid-out"></div>
""",
js"""await mermaidDiagram(root);""")

#%% md id=interactive_md
@md"""
## Interactive

Nothing above is reactive yet — the diagram source is a literal in the HTML pane. Move that
source into a bound variable and the diagram becomes a normal downstream cell: edit the text
or change the theme, and it re-renders without a kernel round-trip beyond re-assembling the
page.
"""

#%% code id=editor_controls
@bind theme Select(["dark", "default", "forest", "neutral", "base"]; label = "theme")
@bind editor_src TextArea("""
flowchart TD
    A[edit me] --> B{fork}
    B -- left --> C[one]
    B -- right --> D[two]
    C --> E[join]
    D --> E
"""; rows = 10, label = "diagram source")

#%% web id=editor
@web(html"""
<pre class="mermaid-src" hidden>{{ editor_src }}</pre>
<div class="mermaid-out"></div>
""",
js"""await mermaidDiagram(root, {{ theme }});""")

#%% md id=generated_md
@md"""
## Generated diagrams

This is the part that a static `.png` in a docs folder cannot do. Mermaid's input is text, and
text is something Julia is good at producing — so a diagram can be a function of live values
rather than a drawing you maintain by hand alongside the code it describes.

Two examples: a type hierarchy read out of `subtypes`, and a schedule laid out as a Gantt chart
from a vector of tasks.
"""

#%% code id=type_tree
using InteractiveUtils: subtypes

node_id(T) = replace(string(T), r"[^A-Za-z0-9]" => "_")

"""
    type_tree(root; maxdepth = 3)

The subtype tree below `root`, as a Mermaid flowchart. Abstract types get a rounded node,
concrete ones a box, so the leaves of the hierarchy read differently from its skeleton.
"""
function type_tree(root::Type; maxdepth::Int = 3)
    lines = ["flowchart TD"]
    label(T) = isabstracttype(T) ? "$(node_id(T))([\"$T\"])" : "$(node_id(T))[\"$T\"]"
    walk(T, d) = d >= maxdepth ? nothing : for C in subtypes(T)
        push!(lines, "    $(label(T)) --> $(label(C))")
        walk(C, d + 1)
    end
    walk(root, 0)
    join(lines, "\n")
end

@bind depth Slider(1:5; default = 3, label = "depth")
type_src = type_tree(Number; maxdepth = depth)
print(type_src)

#%% web id=type_tree_view
@web(html"""
<pre class="mermaid-src" hidden>{{ type_src }}</pre>
<div class="mermaid-out"></div>
""",
js"""await mermaidDiagram(root, {{ theme }});""")

#%% code id=gantt
tasks = [
    (section = "Design",  name = "extension seams",   start = "2026-08-18", days = 3),
    (section = "Design",  name = "asset strategy",    start = "2026-08-20", days = 2),
    (section = "Build",   name = "slate_render hook", start = "2026-08-21", days = 4),
    (section = "Build",   name = "front-end module",  start = "2026-08-24", days = 5),
    (section = "Build",   name = "markdown fences",   start = "2026-08-27", days = 3),
    (section = "Ship",    name = "docs + demo",       start = "2026-08-29", days = 2),
    (section = "Ship",    name = "register",          start = "2026-08-31", days = 1),
]

"""
    gantt_chart(tasks; title)

Lay a vector of `(section, name, start, days)` rows out as a Mermaid Gantt chart, one
`section` block per distinct section, in first-seen order.
"""
function gantt_chart(tasks; title = "Schedule")
    lines = ["gantt", "    title $title", "    dateFormat YYYY-MM-DD", "    axisFormat %b %d"]
    for section in unique(t.section for t in tasks)
        push!(lines, "    section $section")
        for t in Iterators.filter(t -> t.section == section, tasks)
            push!(lines, "    $(t.name) :$(t.start), $(t.days)d")
        end
    end
    join(lines, "\n")
end

gantt_src = gantt_chart(tasks; title = "MermaidSlate.jl")
print(gantt_src)

#%% web id=gantt_view
@web(html"""
<pre class="mermaid-src" hidden>{{ gantt_src }}</pre>
<div class="mermaid-out"></div>
""",
js"""await mermaidDiagram(root, {{ theme }});""")

#%% md id=closing_md
@md"""
## Where this wants to live

Everything above is notebook-local: two setup cells that every notebook wanting a diagram
would have to copy, and a `<pre>` / `mermaid-out` pair repeated per diagram. That is the shape
of a Slate **extension** waiting to be extracted.

Against `SlateExtensionsBase` the whole surface collapses to one returned value:

```julia
using MermaidSlate
mermaid("flowchart LR; A --> B")      # renders, because slate_render says how
```

- `slate_render(::MermaidDiagram)` replaces the `web` cell and its `<pre>`, so a diagram is an
  ordinary cell value — composable, storable in a `Vector`, returnable from a function.
- `required_assets` ships the front-end module, so `@use` and the shared `mermaidDiagram`
  setup cell both disappear.
- The double-brace collision disappears with the HTML pane it came from.

The generated section is the argument for doing it: `type_tree` and `gantt_chart` are already
just functions returning `String`, and the only thing standing between them and a rendered
figure is boilerplate a package should own.
"""

#%% code id=smoke_use
using MermaidSlate

#%% code id=smoke_diagram
mermaid("flowchart LR\n    A[start] --> B{decide}\n    B -- yes --> C[done]\n    B -- no --> A")

# ╔═╡ Slate.config · per-notebook settings (Settings panel)
#   docid = 9809bf93-9dee-46fb-b2ae-1e2024b81bf7
# ╚═╡
