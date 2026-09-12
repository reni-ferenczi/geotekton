# Feature types and the Properties panel

## The type catalog

`Logic/feature_type.gd` holds the whole catalog as one constant dictionary.
Middle Earth does not carry the GPGIM over; a type here is three things:

| Id             | Name         | Geometry kinds                 | Default colour |
| -------------- | ------------ | ------------------------------ | -------------- |
| `unclassified` | Unclassified | polygon, polyline, multipoint, topology | chocolate |
| `craton`       | Craton       | polygon                        | tan            |
| `terrane`      | Terrane      | polygon                        | olive          |
| `coastline`    | Coastline    | polygon, polyline              | steel blue     |
| `ridge`        | Ridge        | polyline                       | crimson        |
| `marker`       | Marker       | multipoint                     | gold           |
| `small_circle` | Small circle | polygon, polyline              | dark turquoise |
| `topology`     | Topology     | topology                       | medium purple  |

The kinds are written as the names the file uses, so the catalog needs nothing
from `Feature` to be read and says the same words the `geometry_kind` field
does.

`unclassified` is what a feature has until someone picks a type. It allows every
kind, which is what lets a feature be drawn before it is classified and what
makes a file written before 0.3.0 loadable: those carry no type at all, so every
feature in one arrives unclassified rather than reclassified by guesswork.

An id the catalog does not know — from a hand-written file, or from a catalog
that has since lost an entry — reads back as `unclassified` through
`FeatureType.normalize()`.

### What the type restricts

Two things follow from the type:

- **The geometry kinds the feature may hold.** The Draw tool's kind selector
  offers only the kinds the selected feature's type allows, and changing the
  type of a feature that already holds geometry of a forbidden kind is refused.
  A feature with no geometry yet may take any type.
- **The colour.** A new feature starts in its type's colour, and changing the
  type changes the colour with it — but only while the colour is still the one
  the old type gave. A colour someone picked is never overwritten.

## The Properties panel

`Scenes/Application/properties.gd` builds the panel in code; the scene is the
`PanelContainer` it is attached to and nothing else. What the panel shows
follows the feature tree selection, through
`Application._on_feature_selected()`.

| Row        | Control            | On a group |
| ---------- | ------------------ | ---------- |
| Name       | Line edit          | yes        |
| Type       | Selector           | no         |
| Colour     | Colour picker      | no         |
| Enabled    | Switch             | yes        |
| From (Ma)  | Number             | no         |
| To (Ma)    | Number             | no         |
| Geometry   | Label              | no         |
| Coordinates| Table, Add, Remove | no         |
| Sections   | Table, Reverse, Remove | no     |
| Keyframes  | Table, Key, Delete | yes        |

A feature shows either the coordinate table or the section table, never both: a
[line topology](Editing.md#line-topologies) borrows its vertices instead of
holding them. A topology has no keyframe table either, because where it is comes
from the features its sections run along.

With nothing selected the panel says so and shows no rows at all, and so does
the root group, which has no name of its own to change and no switch — the same
as on its tree row.

The panel keeps one width, `CONTENT_WIDTH`, whatever it is showing. Letting its
content set the width would let the split container hand the difference to the
planet view, so the globe would move under the pointer every time the selection
changed.

The time range is two ages in millions of years before the present, the same
axis the timeline slider runs on, so `From` is the younger end. A feature
outside it at the current time is neither drawn nor hit tested, and its tree row
is greyed out. See [Time](Time.md#being-there-at-all).

A group has the keyframe table because a group carries motion its children
inherit, which is the one thing besides its name and its switch that a group
has to edit.

### The coordinate table

One row per part of the geometry, with the vertices of that part under it.
Latitude and longitude are editable in place; a value that is not a number, or
one off the planet, is refused and the table goes back to what the feature
holds. `Add` puts a new vertex after the selected one, in the same place, so it
is moved by editing it rather than by knowing where it goes in advance.
`Remove` takes the selected vertex off, and a part left with too few vertices to
be a shape goes with it — three for a polygon, two for a polyline, one for a
multipoint, as `Feature.MINIMUM_VERTICES` lists them.

With no row picked both buttons work on the last vertex of the last part.

### The section table

Only a [line topology](Editing.md#line-topologies) has one. One row per section:
the feature it runs along, the two vertices it runs between, counted from one
the way the coordinate table counts them, and `on` or `back` for which way round
it is walked.

`From` and `To` are editable, so a section added by clicking a whole feature can
be trimmed to the stretch that belongs to the boundary. `Reverse` turns the
selected section round and `Remove` takes it out; with no row picked both work
on the last section, the way the coordinate table's buttons do.

A section whose feature cannot be followed — deleted, or not there at the
current time — is shown in a warning colour with the reason as its tooltip,
rather than being dropped. The table is filled again whenever the current time
moves, since a section can be followed at one time and not at another.

### The keyframe table

One row per keyframe: `Ma`, the time, and `Lon`, `Lat` and `Spin`, the three
angles [Moving](Moving.md#rotation-representation) names. The row the current
time sits on is marked, so it is clear whether an edit will land on a keyframe
or between two of them.

Every cell can be edited, so a keyframe dragged roughly into place with the Move
tool can be given exact numbers. `Key` holds where the node is now as a keyframe
at the current time, which is how a keyframe is made without moving anything;
the rotation it records is the one the keyframes around the current time already
give, so nothing on the globe moves. `Delete` takes the selected keyframe off.

### Every edit goes through the document

The panel never writes to a feature. Each edit calls one of the editing methods
of `Logic/document.gd`, which validates it, applies it and records exactly one
undo version:

| Method                  | Refuses                                            |
| ----------------------- | -------------------------------------------------- |
| `rename`                | nothing; a long title is cut down the way the tree cuts it |
| `set_enabled`           | nothing                                            |
| `set_color`             | nothing                                            |
| `set_feature_type`      | an unknown type, and one that forbids the kind the feature holds |
| `set_time_range`        | a range that ends before it starts                 |
| `set_vertex`            | a part or vertex that is not there, a point off the planet |
| `insert_vertex`         | the same                                           |
| `remove_vertex`         | a part or vertex that is not there                 |
| `split_feature`         | a group, a topology, a part that is not there, a multipoint, and a cut that would leave half a shape or run outside it |
| `set_keyframe`          | nothing; the time it names replaces or is added    |
| `set_keyframe_time`     | a keyframe that is not there, a time outside 0 to `MAX_TIME`, and a time another keyframe already holds |
| `set_keyframe_rotation` | a keyframe that is not there                       |
| `add_section`           | a group, a feature holding vertices of its own, a type that forbids topologies, and a target that is a group, a topology, the topology itself or has no vertices |
| `remove_section`        | anything but a topology, and a section that is not there |
| `reverse_section`       | the same                                           |
| `set_section_range`     | the same, and a vertex number below one            |

A method that can refuse returns the message saying why and changes nothing;
the panel puts the widget back and shows the message in an error dialog.

The colour picker is the one exception to one edit, one version. While the
picker is open the feature takes every colour the cursor is dragged over, so the
globe shows what is being picked, but only the colour left when the picker
closes reaches the undo stack.

## Edit commands

The commands that were on the feature tree toolbar are also on an **Edit** menu
in the menu bar — Undo, Redo, Cut, Copy, Paste, Duplicate and Delete — with the
shortcuts the feature tree used to handle by itself. The menu owns them now, so
they work wherever the focus is, and a text field still keeps Ctrl+C and Ctrl+V
for its own text, because a focused control is offered a key before a menu
accelerator is.

A right click on the globe or the map selects whatever is under the pointer and
offers Duplicate and Delete on it. Only in the Move tool: in the Draw tool a
right click takes the last placed vertex back, and in the Measure tool it takes
back the last point measured to.

Undo and Redo have the same exception. While the Draw, Circle or Measure tool
holds points it has not committed, Ctrl+Z takes the last of them back and
Ctrl+Y puts it down again, and the document's stack is reached only once no
point is held; see [Draw](Draw.md#visual-feedback). The feature tree toolbar's
Undo and Redo buttons always go to the document.

The Remove button here and the Delete key of the
[Vertex tool](Editing.md#deleting) part company over the last vertices of a
part. This one removes the part along with the vertex; that one refuses. See
[Deleting](Editing.md#deleting) for why.

## The file

A leaf feature carries `feature_type` in the file from 0.3.0 on:

```json
"feature_type": "craton"
```

A 0.2.0 file has no such key and loads with every feature unclassified, so there
is no migration step for it. See [Persistence](Persistence.md#file-format).
