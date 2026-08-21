"""
    MermaidSlate

[Mermaid](https://mermaid.js.org) diagrams in Kaimon Slate. Text in, diagram out — which makes a
diagram something you can *compute*, rather than a `.png` you maintain alongside the code it
describes.

```julia
using MermaidSlate

mermaid("flowchart LR; A --> B")          # a value; renders when a cell returns it
```

and, equivalently, in a markdown cell:

    ```mermaid
    flowchart LR
        A --> B
    ```

Built entirely against the lean `SlateExtensionsBase` SDK — no KaimonSlate dependency. Three seams
carry the whole package:

- [`MermaidDiagram`](@ref) + `slate_render` — a returned diagram renders as a component, which is
  what makes it an ordinary value: storable in a `Vector`, returnable from a function, composable.
- `register_fence_renderer!` — ```` ```mermaid ```` blocks in prose render through that same value,
  so the two surfaces can't drift.
- `provide_import!` — the Mermaid runtime is declared once, for every notebook that loads this
  package. Nothing is vendored into this repo, and an offline export inlines it.
"""
module MermaidSlate

using SlateExtensionsBase

export mermaid, MermaidDiagram, set_theme!, themes

# Pinned exactly, not by range: an export resolves this URL to bytes, so a moving target would mean
# two exports of the same notebook shipping different Mermaid builds. `?bundle` matters — esm.sh
# otherwise answers with a stub that re-exports by relative path, which cannot be inlined into a
# self-contained page.
const MERMAID_URL = "https://esm.sh/mermaid@11.4.1?bundle"

# `auto` (the default) follows the notebook: the front-end measures the live Slate palette and picks
# `dark` or `default` to match, so a diagram never arrives light-on-light after a theme switch. The
# rest are Mermaid's own themes, pinned here so a typo fails in Julia — with the valid set in the
# message — instead of silently drawing in the wrong one in the browser.
const THEMES = ("auto", "dark", "default", "base", "forest", "neutral")

# The theme a diagram gets when its constructor isn't given one. Notebook-wide, so a document can
# pick a look once instead of repeating `theme = …` at every call site.
const DEFAULT_THEME = Ref("auto")

"""
    set_theme!(theme) -> theme

Set the theme used by every `mermaid(...)` that doesn't name one itself. `theme` is one of
$(join(repr.(THEMES), ", ")); `"auto"` (the initial value) follows the notebook's own light/dark
setting.

The value is captured when a diagram is CONSTRUCTED, not when it draws — so this affects diagrams
made after the call. Set it above the diagrams it should govern, and re-run to restyle existing ones.

```julia
set_theme!("neutral")     # this notebook's diagrams, unless a call overrides it
```
"""
function set_theme!(theme::AbstractString)
    t = String(theme)
    t in THEMES || throw(ArgumentError(
        "set_theme!: unknown theme $(repr(t)) — expected one of $(join(repr.(THEMES), ", "))"))
    DEFAULT_THEME[] = t
    return t
end

"""
    theme() -> String

The current notebook-wide default theme — see [`set_theme!`](@ref).
"""
theme() = DEFAULT_THEME[]

"""
    themes() -> Tuple{Vararg{String}}

Every theme [`mermaid`](@ref) and [`set_theme!`](@ref) accept, in the order they're offered:
`"auto"` first (follow the notebook), then Mermaid's own. Useful for driving a control —

```julia
@bind t Select(collect(themes()))
mermaid(src; theme = t)
```
"""
themes() = THEMES

"""
    MermaidDiagram(source; theme = MermaidSlate.theme())

A Mermaid diagram: its `source` text and the theme to draw it in. Renders when a cell returns it.
Construct one with [`mermaid`](@ref).
"""
struct MermaidDiagram
    source::String
    theme::String

    function MermaidDiagram(source::AbstractString; theme::AbstractString = DEFAULT_THEME[])
        t = String(theme)
        t in THEMES || throw(ArgumentError(
            "MermaidDiagram: unknown theme $(repr(t)) — expected one of $(join(repr.(THEMES), ", "))"))
        return new(String(strip(source)), t)
    end
end

"""
    mermaid(source; theme = MermaidSlate.theme()) -> MermaidDiagram

A Mermaid diagram from its `source` text. Mermaid infers the diagram type from the first keyword, so
one function covers flowcharts, sequence diagrams, state machines, class and ER diagrams, Gantt
charts and the rest.

```julia
mermaid(\"\"\"
flowchart LR
    parse --> analyse --> run
\"\"\")
```

`theme` is one of $(join(repr.(THEMES), ", ")). Naming one here always wins; omit it to take the
notebook-wide default ([`set_theme!`](@ref)), which starts as `"auto"` — following the notebook's own
light/dark setting, and re-drawing when that setting changes.
"""
mermaid(source::AbstractString; theme::AbstractString = DEFAULT_THEME[]) =
    MermaidDiagram(source; theme = theme)

# Render a returned diagram as this package's front-end component. Deliberately NOT a
# `Base.show(::MIME"text/html")`: outside Slate the struct still shows as a plain value, so the same
# code stays readable in the REPL, in IJulia and in VS Code.
SlateExtensionsBase.slate_render(d::MermaidDiagram) =
    component(MermaidDiagram; source = d.source, theme = d.theme)

# Everything MermaidSlate registers is PROCESS-global and idempotent (last-wins / deduped by id), so
# it can run from anywhere and run twice. It runs at package LOAD, which is the earliest point that
# works and the only one early enough:
#
# - the FENCE renderer must be registered before any markdown cell evaluates its interpolations, and
#   those run in the same batch as the `using MermaidSlate` that loads this package — earlier than
#   the manifest drain, so registering only from `__slate_frontend` leaves every fence in that first
#   batch unclaimed, silently falling back to a plain code block;
# - the COMPONENT must be registered even when nothing runs at all, because a notebook reopened with
#   every cell restored from the durable memo evaluates nothing, and a dispatch-driven seam
#   (`required_assets`) would then never fire and no diagram in the document would draw. A `@bind`
#   widget escapes that because `@bind` statements are replayed on restore; a RETURNED value isn't.
function _register!()
    # The Mermaid runtime, as an import-map entry — the package-level `@use`. A notebook that wants a
    # different build overrides it with its own `@use "mermaid" => …`, which always wins.
    provide_import!("mermaid", MERMAID_URL)
    # Registered under the type-derived kind "MermaidSlate.MermaidDiagram", so the kind string is
    # never written twice — not here, and not in the JS.
    register_component!(MermaidDiagram, @pkg_asset("assets/mermaid-view.js"))
    # ```mermaid blocks in prose become the same value a cell would return, so prose diagrams and
    # computed ones go through one render path rather than two that can disagree.
    register_fence_renderer!("mermaid", src -> MermaidDiagram(src))
    return nothing
end

__init__() = _register!()

# Slate calls this once per notebook that has MermaidSlate loaded, on every drain. Defining it is also
# how Slate DETECTS the package as an extension. Re-registering here is what heals a worker reset or a
# namespace rebuild, which drops the process-global registries `__init__` filled.
__slate_frontend(slate_on) = _register!()

end # module MermaidSlate
