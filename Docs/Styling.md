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
| Feature type | The color of the feature's [type](Properties.md#the-type-catalog): one each for polygons, lines, points, circles, topologies and polar circles, as the catalog has them or as the Preferences dialog changed them. A change made there repaints these features as soon as the dialog is confirmed |

**Feature colour** is what every document is drawn in until someone picks
another, and it is what every version before 0.7.0 drew. It stands in for the
plate ID colouring GPlates does: Middle Earth has no plate IDs, and a feature's
own colour is the thing it identifies itself by.

**Feature age** is how long the feature has existed at the current time: the
older end of its [time range](Time.md#being-there-at-all), the panel's `From`,
where it came into
existence, minus the current time, and never below zero. Ages run backwards, so
that end is the larger of the two numbers. GPlates colors by age the same way:
begin time minus current time. At the present the age is the whole of that end,
so a document looked at in the present draws the same as before GP-0036.

Because the age moves with the time, so does the color. A step of the animation
works the colors out again whenever some feature is colored by age
(`Styling.by_age`), and uploads them in `feature_data` with the rotations, so
the geometry texture is not touched. See [Shader](Shader.md#per-feature-rotation).

Picking a style changes nothing about the document's features. The colour a
feature carries is still its own and still what the Properties panel edits; the
style only says which colour is used to draw it.

## Group styles

GPlates colors a layer at once: by plate ID, one color, by age or by type, with
a fill opacity per layer. Middle Earth has no layers, so groups take their
place. Every group carries a **style**:

| Field | Values |
| ----- | ------ |
| `mode` | `inherit` (shown as Same as parent), or one of the four draw styles above |
| `color` | What the single colour mode paints with |
| `opacity` | 0 to 1, multiplied into every feature under the group |
| `palette` | What the feature age mode reads: `ramp`, a built in palette's key or the path of a `.cpt` file |
| `ramp_colors`, `ramp_span` | The custom ramp: two colors or more, and the My between one and the next |

`Styling.color_of()` goes up from a feature to the nearest group whose mode is
not inherit, and that group's style decides the color. The opacity works
differently: every group above the feature multiplies its own into the alpha,
whichever group decides the color. A feature at 80 percent under two groups at
50 percent is drawn at 20 percent.

The **root group's style is pinned** to Feature colour at full opacity, with
the default palette and ramp (`GroupStyle.for_root()`). Nothing is above the
root, so this is what a group on inherit resolves to at the top, and what a
feature under no group of its own is drawn in. Nothing edits it: the Properties
panel shows the root with nothing to edit, the View settings dialog has no style
rows, and `Document.set_style()` refuses the root. On load, the root style a
file carries is read and replaced with the pinned one, and saving writes the
pinned one back, so the file format did not change; see
[Persistence](Persistence.md#feature-tree-serialization). A new group starts on
inherit at full opacity, so it changes nothing until someone picks a style for
it in the Properties panel. A group of cratons on Feature colour can sit beside
a group of continental crust on Single colour.

The Properties panel calls `inherit` **Same as parent**, and its tooltip says
what that means: the group colors its features the way the group above does,
while Feature colour and the others decide for themselves. Under a top level
group the two look the same, because the root is pinned to Feature colour.
Nested groups are where they differ. Put a group on Single colour with a group
under it: on Same as parent, the inner group's features take the single color
and change with it when the outer group changes; on Feature colour, they keep
their own colors whatever the outer group does. The file still stores
`inherit`.

`Styling.of()` walks the tree once when it is built and remembers the deciding
style and the opacity for every leaf, so `color_of()` looks both up rather than
climbing the tree for each feature.

The style is part of the tree. It is written on the group node in the file, it
is on the undo stack with the rest of the tree, and a duplicated or pasted group
takes a copy of it.

### The custom ramp

The palette list starts with **Custom** (`ramp`), which is what a new style
uses. Its colors and its span are fields of the style itself, so every group has
its own: a feature is the first color when it comes into existence, moves
towards the next at the same rate whatever the timeline does, reaches it
`ramp_span` My later, then carries on to the one after over another span, and
holds at the last one. A feature younger than the whole ramp never reaches its
end, which is the point: a group of orogenies can go from brown to grey over
300 My while another group ages over a different span. The color in between is a
straight blend of the two stops it sits between, the way a palette slice blends
its ends.

`ramp_colors` holds two colors or more. The **+** button beside the pickers adds
another, a copy of the last one, and the **−** on every color past the second
takes that one off, so the fewest a ramp can have is the two it starts with.

`GroupStyle.ramp()` turns the list and the span into a palette of one slice per
neighbouring pair, so the ramp is looked up and previewed the same way as any
other palette. A new style starts at black to white over 300 My, and the span is
at least 1 My. The `.cpt` palettes stay for anyone who wants steps rather than
blends, and read the same age.

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
which line it was and why, and goes on with the next one. When the file is
loaded from the Properties panel, an error dialog names the file and lists
those lines, and the group still gets the palette, made of the lines that did
read.

### The chooser

A group's **Palette** row in the Properties panel lists the built in palettes,
with Custom first, and the file the group's style names, if it names one. The
**Load...** button beside the list asks for a `.cpt` file, reads it and gives
it to the group as one edit, one undo version. The file joins that group's list
under its file name. The panel asks for the file through its
`palette_file_requested` signal; `Application.choose_palette()` shows the file
dialog, reads the file and hands the path to `Properties.load_palette()`. The
file is read again on every load, so the changes in an edited file show up.

One built in table is left, written in the same format a file is and read by the
same reader, so there is one way in:

| Palette | What it is |
| ------- | ---------- |
| Rainbow | 0 to 1000 through red, yellow, green, cyan, blue and magenta |

A style stores the palette as one string: the key of a built in palette, or
the path of a file. `Palette.resolve()` takes it back either way. The
application reads each palette once and keeps it by that string, so a rebuild
of the geometry never reads a file it has read before.

Below the palette row the panel has the Ramp row with the group's colors and
its span. The colors wrap onto further lines once there are more than fit beside
each other, each with its − button.

## What the document carries

The visibility switches live in the [view settings](Persistence.md#view-settings)
block as `hidden_classes`. The colors live in the group styles, the root's among
them, on the [group nodes](Persistence.md#feature-tree-serialization) of the
feature tree. Both are saved with the document and both are on the undo stack,
so picking a style is one step of it. The preferences keep what a new document
starts from: the view block, with no style in it, since the root's is pinned.

Up to 0.9.0 the view block carried `draw_style`, `single_color` and `palette`;
0.10.0 moved them onto the root group, where the loader now replaces them with
the pinned style. See
[0.9.0 to 0.10.0](Persistence.md#090-to-0100). 0.11.0 added the ramp fields;
see [0.10.0 to 0.11.0](Persistence.md#0100-to-0110). 0.13.0 made the ramp a list
of colors and cut the built in palettes down to Rainbow; see
[0.12.0 to 0.13.0](Persistence.md#0120-to-0130).

## Where the tests are

| Test | What it covers |
| ---- | -------------- |
| `Tests/Unit/test_palette.gd` | The reader: the fixtures in `Tests/Data/Palettes`, the built in palettes, boundary and gap lookups, and every palette GPlates ships when that checkout is beside this one |
| `Tests/Unit/test_styling.gd` | Which class a feature lands in, that each switch removes its own class and no other, the colour each style resolves to, the age so far, and the group styles: inherit shown as Same as parent, inherit through two levels, a nested group following its parent where one on Feature colour does not, the nearest group deciding, the root as the default, a file's root style (Single color at half opacity) pinned on load, opacity multiplying down, the file, clones, undo, and the root refused. A feature born at 500 Ma under a 200 My ramp is color A at 500, halfway at 400 and color B at 300 and at 0, moved only by `Geometry.resolve()` |
| `Tests/Unit/test_migration.gd` | A 0.7.0 view block's style landing on the root group, and a 0.10.0 style reading with the default ramp |
| `Tests/Rendered/test_styling.gd` | Pixel probes of each style on the globe, a group on a single colour beside a group on own colours, a group's opacity, a 0.7.0 file drawn in a single colour opening in the feature colors, one polygon under the ramp red at 500 Ma and blue at 300 Ma without the geometry texture being uploaded again, the Earth showing where a switched off class was, a palette file loaded on a group's Palette row coloring that group, and no Palette row on the root |
| `Tests/session.py` | The styling scenario: the View settings dialog refusing the six style fields, a group's styles on a running application, its ramp, a palette file and a malformed one loaded through the group's Load button, the switches through the View menu, and the whole lot through a save and a load, with the root's pinned style in the file. The Properties scenario sets a group's style and ramp through the panel, probes them and undoes them |
| `Tests/performance.py` | The frame time playing under the age ramp, set on the group that holds every feature, beside the frame time playing in flat colors |
