# Importing a GPlates reconstruction

**File > Import...** takes a GPlates project, or the feature collections and
rotation files a project would name, and turns them into a Middle Earth
document. Nothing goes the other way: the import is one way, and what comes out
is an ordinary document that is edited, saved and animated like any other.

The conversion is Python's. The application picks the files and hands them to the
interpreter over the [scripting bridge](Scripting.md#the-protocol); the
interpreter reads the GPlates files with `pygplates`, writes a `.middle-earth`
file and says where it is. What opens is **Untitled and unsaved**, because an
import has no file of its own yet, so Save asks where to put it and the GPlates
files are never written to.

An import takes seconds rather than an instant, so the console panel comes up
and says what was found while it runs.

## What can be picked

| Picked                          | What happens                                     |
| ------------------------------- | ------------------------------------------------ |
| A `.gproj` project              | The files it names are read, wherever they are now |
| `.gpml`, `.gpmlz`, `.rot`, `.grot` or `.shp` files | Those files are read           |

The dialog takes several files at once, because a feature collection on its own
has no motion: the rotation file that moves its plates is picked with it.

A project file is a GPlates Scribe binary archive. It holds no geometry: it
names the files the session had loaded, and `middle_earth/gproj.py` reads that
list out of it. The paths in it are absolute and belong to the machine the
project was saved on, so each file is looked for where it says first and then
in the same place relative to the project file — which is what finds the data
in a bundle that was copied somewhere else, as the projects shipping inside a
GPlates install were.

A file that will not read is named in the console and passed over; the rest of
the project is still imported.

Rotation files and feature collections are told apart by what is in them rather
than by their names, so a `.gpml` holding rotation sequences is used as a
rotation model and one holding both is used as both.

## The tree that comes out

GPlates keeps motion in two places: a feature names the plate it follows, and
a rotation file says where every plate was at every time. Middle Earth keeps
motion on each feature, and a group carries none (see
[Time](Time.md#groups-do-not-move)). So the import builds:

```
Planet
├── Plate 101
│   ├── North America      keyframes sampling plate 101's rotation
│   └── Greenland          the same keyframes again
└── Plate 201      ...
```

One group per plate id, named `Plate <id>`, in increasing order, each holding
the features of that plate in the order the files listed them, and every
feature carrying its plate's rotation sampled into keyframes, the same list on
each feature of the plate. The plate circuit GPlates resolves is already
resolved: the rotation is the plate's relative to the anchor, not relative to
its parent plate, so the tree is one level deep and the groups are there to
find things by plate.

The geometry is written down as GPlates holds it, at present day. Nothing is
reconstructed, so the imported document animates rather than being a snapshot
of one time.

### Motion

Each plate's rotation is sampled every ten million years, from the present back
as far as both the rotation model and the oldest feature reach. A sample the
ones on either side of it already say is left out, so a plate that stops moving
early costs a few keyframes rather than one per step, and a plate that never
moves costs none.

Sampling costs accuracy between the samples. On the GPlates mid ocean ridges
the imported features sit exactly where `pygplates` reconstructs them at every
sampled time and up to two degrees away halfway between two of them, which is
where the model turns fastest. A finer step is `import_files(paths, step=...)`
from the [console](Scripting.md); the menu takes the default.

The two programs use different frames — GPlates puts z through the north pole,
Middle Earth puts y there — so a rotation is carried across by swapping the
last two axes in both the rows and the columns of its matrix, and the result is
decomposed into the three angles a keyframe holds. Three coastlines are checked
against `pygplates` at fifty million years in `Tests/Python/test_gplates.py`,
and the whole path is checked through the window in `Tests/session.py`.

### Colour

Every feature on a plate is given a colour of the plate's own, stepped through
the hues by the golden angle so that neighbouring plate ids do not come out
looking alike. It stands in for the plate id colouring GPlates does; Middle
Earth has no plate ids, and a feature's own colour is what it is drawn in until
another [draw style](Styling.md#the-draw-styles) is chosen.

### Feature types

A Middle Earth [type](Properties.md#the-type-catalog) follows the geometry a
feature holds, so the GPGIM type has no say in it. Whatever GPlates calls a
feature, it imports as one of three:

| Geometry in GPlates | Middle Earth |
| ------------------- | ------------ |
| Polygon             | Polygon      |
| Polyline            | Line         |
| Point or multipoint | Points       |

A Coastline outline and a Craton are both Polygons, and a MidOceanRidge drawn
as a line is a Line. Nothing imports as a Circle, which only the Circle tool
makes. The table is `KIND_TYPES` in `src/middle_earth/gplates.py`.

### Time

A feature's GPlates valid time becomes its Middle Earth time range. Both count
the same way, an age in millions of years before present, but GPlates allows
fractions and both infinities where the file format here holds two whole
numbers. The ends are rounded outwards, so a feature is never shown for less
time than GPlates says it is there; valid forever into the past stops at
`Document.MAX_TIME`, and forever into the future stops at the present.

## How much fits

A global data set is more than the application handles today. The coastlines
that ship with GPlates are 2077 features and 59,490 triangles: they take about
a minute to open, because every polygon is triangulated on load, and the planet
draws 16,384 primitives at once, so about a third of them are on the globe. The
console says how much geometry there was and how much of it fits. The features
that are not drawn are still in the tree, still selected, still moved and still
saved; they are simply not painted. See [Shader](Shader.md#measured), and
GP-0030 in the workspace ticket list for the whole of it.

Importing one region rather than the whole planet is what works today.

## What is dropped

| Dropped                      | Why                                                   |
| ---------------------------- | ------------------------------------------------------ |
| Topological features         | Their geometry is resolved from other features rather than held, and Middle Earth resolves [line topologies](Editing.md#topologies) of its own instead |
| Rasters, scalar coverages, deformation networks | No geometry of their own to convert  |
| A polygon's holes            | Interior rings come in as further outlines, since several rings on one polygon are separate outlines here rather than holes; see [Draw](Draw.md#data-model) |
| A feature's second geometry kind | A feature holds rings of one kind, so a feature mixing a line and a polygon keeps the kind of its first geometry |
| Everything else GPlates knows | Plate ids, feature ids, GPGIM properties, colouring, layers and the view the project was saved with |

A feature with nothing to convert is left out with the reason written to the
console, rather than stopping the import.

## Where the code is

| File                                 | What is in it                              |
| ------------------------------------ | ------------------------------------------- |
| `src/middle_earth/gproj.py`          | The project archive: the file list and where the files went |
| `src/middle_earth/gplates.py`        | The conversion                              |
| `src/middle_earth/bridge.py`         | The `import_gplates` command                |
| `Scenes/Application/application.gd`  | File > Import and opening the result         |

Tested by `Tests/Python/test_gproj.py` and `Tests/Python/test_gplates.py`,
which read the data an installed GPlates brings with it when there is one and
build their own when there is not, and by the import scenario in
`Tests/session.py`. See [Testing](Testing.md).
