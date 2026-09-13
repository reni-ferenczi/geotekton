# Styling

Which features are drawn, and what colour they come out. Four pieces:
`Logic/styling.gd` answers both questions for one feature,
`Logic/group_style.gd` is the style a group colors the features under it with,
`Logic/palette.gd` reads the colour palettes the age style needs, and
`Logic/view_settings.gd` holds which classes of geometry the open document
shows.

The whole of it is resolved in one place, `Planet.collect_geometry()`. That
function flattens the feature tree into the primitives the shader is handed, so
a feature whose class is switched off is simply not among them and a colour is
worked out once per feature rather than once per fragment. The colors go to the
shader in the per feature texture, so `Planet.Geometry.recolor()` can work them
out again without flattening anything. Neither the shader nor the hit test
knows there are styles at all; see [Shader](Shader.md).

A color's alpha is the opacity the feature is drawn at. The feature color
carries the one set in the Properties panel, and the opacity of every group
above the feature is multiplied into it; see [Group styles](#group-styles).

## The visibility switches

The View menu carries one check item per class of geometry:

| Class | What is in it |
| ----- | ------------- |
| Polygons | A feature holding polygon rings |
| Polylines | A feature holding polyline rings |
| Points | A multipoint |
| Circles | A feature whose type is `circle`, whatever geometry it holds |
| Topologies | A [line topology](Editing.md#line-topologies) |

A feature belongs to **exactly one** of them. `Styling.class_of()` decides in
that order: a topology by the geometry it holds, then a circle by its feature
type, and everything else by its geometry kind. A circle is drawn as a polygon
or a polyline, so its type is the only thing that tells it apart; that is why
the type is asked about before the kind.

Because each feature is in one class, each switch takes away its own class and
leaves the other four untouched, which is what
`Tests/Unit/test_styling.gd` measures.

A feature its class is switched off for is left out of the geometry altogether,
so it is neither drawn nor hit tested: a click goes through where it was to
whatever is behind it. That matches what the switch says — the feature is not
being shown — and it means the hit test costs nothing for a class nobody is
looking at.

The switches are stored with the document as `hidden_classes`, the classes that
are **off** rather than the ones that are on. An empty list is everything drawn,
which is what every document said before there were any switches, and a class
name a later version invents cannot quietly hide something this one can then not
show again.

## The draw styles

| Style | Where the colour comes from |
| ----- | --------------------------- |
| Feature colour | The colour the feature itself carries, which is what the Properties panel edits |
| Single colour | One colour for everything under the group, the `color` of its style |
| Feature age | The palette, read at the feature's age |
| Feature type | The color the [feature type](Properties.md) catalog gives its type: one each for polygons, lines, points, circles and topologies |

**Feature colour** is what every document is drawn in until someone picks
another, and it is what every version before 0.7.0 drew. It stands in for the
plate ID colouring GPlates does: Middle Earth has no plate IDs, and a feature's
own colour is the thing it identifies itself by.

**Feature age** is the age at the older end of the feature's
[time range](Time.md#being-there-at-all): the age it came into existence at.
Ages run backwards, so that is the larger of the two numbers.

Picking a style changes nothing about the document's features. The colour a
feature carries is still its own and still what the Properties panel edits; the
style only says which colour is used to draw it.

## Group styles

GPlates colors a layer at once: by plate ID, one color, by age or by type, with
a fill opacity per layer. Middle Earth has no layers, so groups take their
place. Every group carries a **style**:

| Field | Values |
| ----- | ------ |
| `mode` | `inherit`, or one of the four draw styles above |
| `color` | What the single colour mode paints with |
| `opacity` | 0 to 1, multiplied into every feature under the group |
| `palette` | What the feature age mode reads: a built in palette's key or the path of a `.cpt` file |

`Styling.color_of()` goes up from a feature to the nearest group whose mode is
not inherit, and that group's style decides the color. The opacity works
differently: every group above the feature multiplies its own into the alpha,
whichever group decides the color. A feature at 80 percent under two groups at
50 percent is drawn at 20 percent.

The **root group's style is the document default**. Nothing is above it, so a
root on inherit draws each feature's own color, the same as Feature colour. A
new group starts on inherit at full opacity, so it changes nothing until
someone picks a style for it. The View settings dialog edits the root's style
and the Properties panel edits any other group's. A group of cratons on
Feature colour can sit beside a group of continental crust on Single colour.

`Styling.of()` walks the tree once when it is built and remembers the deciding
style and the opacity for every leaf, so `color_of()` looks both up rather than
climbing the tree for each feature.

The style is part of the tree. It is written on the group node in the file, it
is on the undo stack with the rest of the tree, and a duplicated or pasted group
takes a copy of it. GP-0036 adds an age ramp to the same fields.

## Colour palettes

`Logic/palette.gd` reads the GMT **colour palette table** format, the `.cpt`
files GPlates ships in its `sample-data/cpt` folder. Two shapes of palette come
out of the same reader:

- A **regular** palette is a list of slices, each running from one value to
  another between two colours. A slice whose two colours are the same is flat;
  one whose colours differ is a ramp. Nothing switches between the two, so one
  file can hold both and a palette is discrete exactly where its slices are.
- A **categorical** palette is a lookup from a key to a colour, with no order
  and nothing in between. Nothing draws with one yet; the reader takes them
  because the palettes GPlates ships include them.

Three colours stand outside either: `B` below everything the palette covers, `F`
above it, and `N` for a value the palette says nothing about. Without them the
reader uses what GMT does: black, white and grey.

A value on the boundary between two slices belongs to the **lower** of them,
which is the same colour whichever side it is approached from wherever two
slices meet without a step. A value in a gap between two slices is neither below
the palette nor above it, so it comes out as the no-data colour rather than as
the background or the foreground.

### The subset of the format that is read

| Line | Read as |
| ---- | ------- |
| `# anything` or blank | Skipped. This is where a CPT file keeps its comments and its `COLOR_MODEL` declaration, which is why only RGB is understood. |
| `z0 fill z1 fill [flags] [;label]` | One slice of a regular palette. The annotation flags and the label are read past. |
| `key fill [label]` | One entry of a categorical palette. A key with a space in it is written in single quotes. |
| `B fill`, `F fill`, `N fill` | The three colours outside the palette. |

A **fill** is `r/g/b`, three separate numbers `r g b`, or a colour name. Names
are read by Godot's own table, so `#rrggbb` works too. GMT names a few colours
Godot does not by putting `light` or `dark` in front of one it does — `lightred`
is the one the GPlates palettes use — and those are worked out from the colour
behind the prefix. A name Godot knows is always Godot's own colour.

A line that is none of the above does not stop the file: the reader records
which line it was and why, and goes on with the next one. The reasons reach the
palette chooser under the strip, and a run with the automation port open reads
them back as `palette_errors`.

### The chooser

The View settings dialog lists the built in palettes, and a **Load...** button
reads one from a file, which joins the list under its file name. Below the list
is a strip of the chosen palette from one end of its range to the other, drawn
from the palette itself, so what is about to be drawn with is visible before
anything is drawn with it.

The built in palettes are written in the same format a file is and read by the
same reader, so there is one way in:

| Palette | What it is |
| ------- | ---------- |
| Feature age | The example age palette GPlates ships, 0 to 700 Ma through two ramps |
| Rainbow | 0 to 1000 through red, yellow, green, cyan, blue and magenta |
| Grayscale | 0 to 1000, white down to black |
| Discrete steps | Five flat slices two hundred wide: blue, green, yellow, orange, red |

A style stores the palette as one string: the key of a built in palette, or
the path of a file. `Palette.resolve()` takes it back either way. The
application reads each palette once and keeps it by that string, so a rebuild
of the geometry never reads a file it has read before.

That chooser is the root group's. A group's palette row in the Properties panel
lists the built in palettes and the file its style already names, and has no
**Load...** button, so a palette file reaches a group only through a file or a
script that names it.

## What the document carries

The visibility switches live in the [view settings](Persistence.md#view-settings)
block as `hidden_classes`. The colors live in the group styles, the root's among
them, on the [group nodes](Persistence.md#feature-tree-serialization) of the
feature tree. Both are saved with the document and both are on the undo stack,
so picking a style is one step of it. The preferences keep what a new document
starts from: the view block, with the root style under `style`.

Up to 0.9.0 the view block carried `draw_style`, `single_color` and `palette`;
0.10.0 moved them onto the root group. See
[0.9.0 to 0.10.0](Persistence.md#090-to-0100).

## Where the tests are

| Test | What it covers |
| ---- | -------------- |
| `Tests/Unit/test_palette.gd` | The reader: the fixtures in `Tests/Data/Palettes`, the built in palettes, boundary and gap lookups, and every palette GPlates ships when that checkout is beside this one |
| `Tests/Unit/test_styling.gd` | Which class a feature lands in, that each switch removes its own class and no other, the colour each style resolves to, and the group styles: inherit through two levels, the nearest group deciding, the root as the default, opacity multiplying down, the file, clones and undo |
| `Tests/Unit/test_migration.gd` | A 0.7.0 view block's style landing on the root group |
| `Tests/Rendered/test_styling.gd` | Pixel probes of each style on the globe, a group on a single colour beside a group on own colours, a group's opacity, a 0.7.0 file drawn in its single colour, the Earth showing where a switched off class was, and the chooser's list and preview strip |
| `Tests/session.py` | The styling scenario: the styles on a running application, a palette read from a file, the switches through the View menu, and the whole lot through a save and a load. The Properties scenario sets a group's style through the panel, probes it and undoes it |
