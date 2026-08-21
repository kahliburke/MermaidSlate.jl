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

# ╔═╡ Slate.config · per-notebook settings (Settings panel)
#   docid = 02448677-d2e7-447f-88f5-7c1a0bc6778c
# ╚═╡
