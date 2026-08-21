try; import KaimonSlate; catch; error("This is a Kaimon Slate notebook — running it as plain Julia needs the KaimonSlate runtime in this environment. Add it with `import Pkg; Pkg.add(\"KaimonSlate\")`, or open it in Kaimon Slate."); end; KaimonSlate.standalone!(@__MODULE__; dir=@__DIR__)

#%% md id=intro title
@md"""
# MermaidSlate

## Diagrams as values, not as pictures you maintain

Kahli Burke
"""

#%% md id=overview
@md"""
[Mermaid](https://mermaid.js.org) turns a few lines of text into a rendered diagram. Text is
something Julia is good at producing — so under this extension a diagram stops being a `.png` you
maintain alongside the code it describes, and becomes an ordinary value you can compute, store in a
`Vector`, or return from a function.

`using MermaidSlate` is the whole setup. It gives you two surfaces onto one renderer:

- **`mermaid(source)`** — a value. Return it from a cell and it draws.
- **a ```` ```mermaid ```` fence** in prose — the same value, written where the words are.
"""

#%% code id=setup
using MermaidSlate

#%% md id=fence_demo
@md"""
## A diagram in prose

Write the fence where the sentence needs it and it renders in place — no cell of its own, no
scaffolding. The language tag is what claims it:

```mermaid
flowchart LR
    src[/"notebook.jl"/] --> parse[parse cells]
    parse --> dag[[build dependency graph]]
    dag --> stale{"any stale?"}
    stale -- no --> idle([idle])
    stale -- yes --> run[run cell]
    run <--> cache[(durable memo)]
    run --> render[render output]
    render --> stale
```

A fence tagged with a language nobody claims — ```julia, say — stays an ordinary code block, so
this costs an existing notebook nothing.
"""

#%% md id=value_md
@md"""
## The same diagram as a value

The fence is sugar. Underneath, a diagram is an ordinary Julia value — so it can be built by a
function, held in a variable, or picked out of a collection. `mermaid(source)` is the constructor;
returning one from a cell draws it.
"""

#%% code id=value_demo
mermaid("""
sequenceDiagram
    autonumber
    participant B as Browser
    participant H as Hub
    participant W as Worker

    B->>H: run a cell
    activate H
    H->>W: eval source
    activate W
    W-->>H: value + display data
    deactivate W
    H-->>B: patch output
    deactivate H
    Note over H,W: a slow cell is promoted<br/>to a background job
""")

#%% md id=generated_md
@md"""
## Generated from live values

This is the part a `.png` in a docs folder can't do. Mermaid's input is text, and text is something
Julia is good at producing — so a diagram can be a *function of the program*, recomputed like any
other cell instead of redrawn by hand whenever the thing it describes moves.
"""

#%% code id=type_tree
using InteractiveUtils: subtypes

# The node's IDENTITY is the fully-qualified name (two modules can each export a `Fixed`), but its
# LABEL is the bare one — a qualified path is most of the width of a node and none of the meaning.
node_id(T) = replace(string(T), r"[^A-Za-z0-9]" => "_")

# The subtype tree below `root`, as a Mermaid flowchart. Abstract types get a rounded node and
# concrete ones a box, so the skeleton of the hierarchy reads differently from its leaves.
# (A comment rather than a docstring: this cell re-runs on every slider move, and re-attaching a
# docstring warns each time.)
function type_tree(root::Type; maxdepth::Int = 3)
    lines = ["flowchart TD"]
    label(T) = isabstracttype(T) ? "$(node_id(T))([\"$(nameof(T))\"])" : "$(node_id(T))[\"$(nameof(T))\"]"
    walk(T, d) = d >= maxdepth ? nothing : for C in subtypes(T)
        push!(lines, "    $(label(T)) --> $(label(C))")
        walk(C, d + 1)
    end
    walk(root, 0)
    return join(lines, "\n")
end

@bind depth Slider(1:4; default = 2, label = "depth")
mermaid(type_tree(Number; maxdepth = depth))

#%% code id=gantt
tasks = [
    (section = "Design", name = "extension seams",   start = "2026-08-18", days = 3),
    (section = "Design", name = "asset strategy",    start = "2026-08-20", days = 2),
    (section = "Build",  name = "fence renderer",    start = "2026-08-21", days = 4),
    (section = "Build",  name = "front-end module",  start = "2026-08-24", days = 5),
    (section = "Build",  name = "import map",        start = "2026-08-27", days = 3),
    (section = "Ship",   name = "docs + demo",       start = "2026-08-29", days = 2),
    (section = "Ship",   name = "register",          start = "2026-08-31", days = 1),
]

# One `section` block per distinct section, in first-seen order — the same rows would be a table or
# a bar chart; a Gantt is just a different projection of them.
function gantt_chart(rows; title = "Schedule")
    lines = ["gantt", "    title $title", "    dateFormat YYYY-MM-DD", "    axisFormat %b %d"]
    for section in unique(r.section for r in rows)
        push!(lines, "    section $section")
        for r in Iterators.filter(r -> r.section == section, rows)
            push!(lines, "    $(r.name) :$(r.start), $(r.days)d")
        end
    end
    return join(lines, "\n")
end

mermaid(gantt_chart(tasks; title = "MermaidSlate.jl"))

#%% md id=theme_md
@md"""
## Themes

Diagrams default to `"auto"`, which follows the notebook: the renderer measures the live palette
rather than matching theme *names*, so it stays right for a Slate theme added after this was
written, and redraws when you switch theme rather than waiting for a re-run.

Three levels, narrowest wins: an explicit `theme =` beats `set_theme!(...)` for the notebook, which
beats the `"auto"` default. `themes()` lists them, so a control can be driven straight off it.
"""

#%% code id=theme_demo
@bind picked Select(collect(themes()); label = "theme")

mermaid("""
stateDiagram-v2
    [*] --> Stale : parsed
    Stale --> Running : slot free
    Running --> Fresh : ok
    Running --> Errored : exception
    Fresh --> Stale : upstream changed
    Errored --> Stale : source edited
    Fresh --> [*] : cell deleted
"""; theme = picked)

# ╔═╡ Slate.config · per-notebook settings (Settings panel)
#   docid = 02448677-d2e7-447f-88f5-7c1a0bc6778c
# ╚═╡
