# The application window

The window is one `Application` scene (`Scenes/Application/application.tscn`):
a menu bar, five panels around the planet view, and a status bar. The two
either side of the view are split containers, not docks, so they can be resized
and hidden but not torn off or rearranged; the kinematics graphs, the console
and the time control stack under the view and take the height they ask for.

```
menu bar
Features | tools, view toolbar, planet view, kinematics, console, timeline | Properties
status bar
```

Every panel but the kinematics graphs and the console is shown by default. Those
two are asked for from the View menu when they are wanted, since they take their
height off the planet view; once shown, they are remembered like the rest.

The two splitters start at 576 px for the feature tree and 320 px for the
properties panel. The feature tree is the wider of the two because its toolbar
sets the floor: thirteen buttons and five separators in one `HBoxContainer` that
never wraps, so a `SplitContainer` cannot give the panel less than they need.
576 px is what that comes to, and the offset says so rather than asking for a
width it cannot have. Making the toolbar take less — wrapping it, scrolling it, a
denser icon size, or moving the rare buttons into a menu — is what it would take
to narrow the panel; see GP-0019.

The middle column has the same floor for the same reason, and its wider row is
the [view toolbar](Editing.md#the-view-toolbar) rather than the tools: the two
panels and that row together are what the window has to be wide enough for.

## Menus

`Application._build_menus()` creates the four menus in code and populates them.
The item ids are the `FileItem`, `EditItem`, `ViewItem` and `HelpItem` enums, so
adding an item means adding an enum value and one `add_item` line.

| File            | Shortcut       | What it does                                     |
| --------------- | -------------- | ------------------------------------------------ |
| New             | Ctrl+N         | Empty document, after asking about unsaved changes |
| Open...         | Ctrl+O         | File dialog, then load                           |
| Open Recent     |                | The remembered files, newest first, and Clear    |
| Import...       |                | Convert a GPlates project, or feature collection and rotation files, into a new document; see [Import](Import.md) |
| Save            | Ctrl+S         | Write to the document path, asking for one only when it has none |
| Save As...      | Ctrl+Shift+S   | Always ask for a path                            |
| Export Image... |                | Write the map at the current age to a PNG; greyed out on the globe |
| Export Video... |                | Render the animation between two ages and encode it; the globe as well as a map |
| Run Script...   |                | Pick a Python file and run it; see [Scripting](Scripting.md) |
| Scripts         |                | One entry per documented script in the configured folders |
| Preferences...  |                | The preferences dialog                           |
| Quit            | Ctrl+Q         | Close, after asking about unsaved changes        |

| Edit      | Shortcut | What it does                                        |
| --------- | -------- | --------------------------------------------------- |
| Undo      | Ctrl+Z   | Step back through the undo stack                    |
| Redo      | Ctrl+Y   | Step forward again                                  |
| Cut       | Ctrl+X   | Copy the selected node and delete it                |
| Copy      | Ctrl+C   | Put the selected node on the clipboard              |
| Paste     | Ctrl+V   | Put what is on the clipboard beside the selection   |
| Duplicate | Ctrl+D   | A copy of the selected node, with its own identity  |
| Delete    | Delete   | Remove the selected node                            |

| View        | Shortcut | What it does                              |
| ----------- | -------- | ----------------------------------------- |
| Features    |          | Show or hide the feature tree panel       |
| Properties  |          | Show or hide the properties panel         |
| Timeline    |          | Show or hide the timeline                 |
| Kinematics  |          | Show or hide the motion graphs; see [Kinematics](Kinematics.md) |
| Console     |          | Show or hide the Python prompt; see [Scripting](Scripting.md) |
| Status Bar  |          | Show or hide the status bar               |
| Polygons    |          | Draw the polygons, or leave them off; see [Styling](Styling.md#the-visibility-switches) |
| Polylines   |          | The same for the polylines                |
| Points      |          | The same for the multipoints              |
| Circles     |          | The same for the features typed as circles |
| Topologies  |          | The same for the line topologies          |
| View Settings... |     | The scene around the features and how they are coloured; see [Editing](Editing.md#view-settings) |
| Full Screen | F11      | Enter or leave full screen                |

| Time         | Shortcut  | What it does                              |
| ------------ | --------- | ----------------------------------------- |
| Skip Older   | Page Up   | The timeline's `<` button: one skip towards the older end; see [Time](Time.md#the-time-control) |
| Skip Younger | Page Down | The `>` button: one skip towards the younger end |
| Older Keyframe | Ctrl+Page Up | The `<<` button: the selected node's next keyframe towards the older end |
| Younger Keyframe | Ctrl+Page Down | The `>>` button: the same towards the younger end |

| Help          | Shortcut | What it does                          |
| ------------- | -------- | ------------------------------------- |
| Documentation | F1       | Open the `Docs` folder on GitHub      |
| About         |          | Version, credits and a documentation link |

The shortcuts are menu accelerators, so they work whatever has the keyboard
focus, except where a focused control takes the key first: Ctrl+C and Ctrl+V in
a text field are still the text field's. The Edit commands are on the feature
tree toolbar as well, and Duplicate and Delete are also on a right click on the
globe; see [Properties](Properties.md#edit-commands). The toolbar also has Save
and Load buttons, which run the File > Save and File > Open commands.

**Space** and the tool letters are the shortcuts that are not menu items. Space
starts the animation and stops it again; see
[Time](Time.md#the-time-control). A letter picks a tool, `M` for Move, `R` for
Rotate and so on, as listed in
[Editing](Editing.md#the-tool-keys). All of them are read from anywhere but a
text field, which takes the key as the character it is, and all of them are
single keys: every menu accelerator carries Ctrl or is a key of its own, so
none of them collide.

## Full screen

F11 switches the window between `MODE_WINDOWED` and `MODE_FULLSCREEN`. The menu
bar is not visible in full screen, so a button floats over the top of the view
to leave it again; it lives in the `FullScreenOverlay` canvas layer, which is
hidden while the window is not full screen.

## Status bar

Three fields: where the mouse is on the planet, what the tools have to say, and
the open file.

- The coordinates come from the `cursor_moved` signal of the planet view, which
  fires for the globe and the map. It reads `off the planet` while the pointer
  is over the view but not over the planet, and once the pointer leaves the
  window, which the view learns from its own `mouse_exited` rather than from the
  planet. The craton highlight under the pointer ends at the same moment.
- The middle field is the tools'. The [Measure tool](Editing.md#the-measure-tool)
  shows the last segment and the total along the path being measured; outside it
  the field shows the length along the selected feature's geometry. It is also
  where the [Vertex tool](Editing.md#the-vertex-tool) says why it refused
  something, so a deletion that would leave half a shape is answered in place
  rather than in a dialog.
- The file field shows the file name, with an asterisk while the document has
  unsaved changes, and the whole path as its tooltip. The window title carries
  the same name and marker.

## Preferences

In the dialog under File > Preferences:

- **Default folder for Open and Save** — where the file dialogs start, the same
  setting the dialogs update as files are opened and saved.
- **Reopen the last file on launch** — when off, the application starts with an
  empty document however the last session ended.
- **Planet radius (km)** — what distances are read against, in whole kilometres.
  It defaults to Earth's mean radius; see
  [Editing](Editing.md#the-planet-radius) for why it is a preference and not
  part of a document.
- **Vertex marker size** and **Outline line width** — how large the outline
  overlay draws the vertices of the selected feature and the lines between them,
  as multiples of what the shader draws at.
- **Export width (pixels)** — how wide File > Export Image writes its picture.
  The height comes from the projection, so this one number settles the size of
  every export; see [Exporting a picture of the map](#exporting-a-picture-of-the-map).
- **ffmpeg for video export** — which ffmpeg encodes the frames of a video.
  Empty is the one on the path, or the copy Shotcut ships where there is none
  on the path. A path naming a file that is not there means this machine has no
  encoder, and the frames are then left as they are; see
  [Exporting a video of the animation](#exporting-a-video-of-the-animation).
- **Interpreter** and **Script directories**, under a Python heading — which
  Python runs the scripting bridge and where the scripts that become menu
  entries are looked for. Leaving the interpreter empty means the project's own
  `.venv`; see [Scripting](Scripting.md#preferences).

All of them are written to the config file described in
[Persistence](Persistence.md#the-config-file). So is the state of the Snap
switch in the toolbar, which is not in the dialog because it is toggled while
editing rather than set once.

## Exporting a picture of the map

File > Export Image asks where to put a PNG and writes the map at the age the
timeline shows. The item is greyed out while the globe is shown: the globe is a
view of one side of the planet, and a picture of it would have no size the
projection could settle.

The sheet fills the picture exactly. Its width is the Export width preference,
or whatever the caller asks for, and its height is that width times the
projection's extent, so every export of one projection comes out the same size
whatever the window is doing: 3600 by 1800 for a rectangular or Mollweide map,
3600 by 3600 for Mercator and orthographic, 3600 by 1826 for Robinson. See
[Shader](Shader.md#the-export-camera) for how the camera is fitted to the sheet.

Only the planet is in it. The graticule, the background colour, the star field
and the backdrop image are whatever the view settings have them as; the panels,
the measurement label, the selection highlight and the tool marks are not, and
neither are the zoom, the camera offset or the view angle, which are put back
untouched afterwards. Corners outside a Mollweide, Robinson or orthographic
sheet are the background colour; a rectangular or Mercator sheet is a rectangle,
so it reaches all four corners of its own picture.

The status bar names the file and its size when the picture is written, and a
failure to write reaches the error dialog. A script exports through
`app.export_image()`; see [Scripting](Scripting.md#the-application).

## Exporting a video of the animation

File > Export Video renders the animation frame by frame and hands the frames
to ffmpeg. The dialog asks for six things:

| Field                 | Default                       |
| --------------------- | ----------------------------- |
| From (Ma)             | the animation's start         |
| To (Ma)               | its end                       |
| Speed (My per second) | its speed                     |
| Frames per second     | 30                            |
| Width (pixels)        | the Export width preference   |
| File                  | the document's name with `.mp4` |

The three ages and the speed are the animation's own settings, so the video
runs the way playback does; the frame rate is how finely that run is sampled.
The line under the fields says how many frames they come to and how large each
one is, and follows the fields as they are typed. Eighteen thousand frames is
the most one export may hold, which is ten minutes of video at thirty frames a
second and what stands between a mistyped speed and an export nobody wanted.

Each frame is the planet at one age, rendered the way
[a picture](#exporting-a-picture-of-the-map) is, so a frame and a picture of
the same age are the same image. Unlike the picture, a video can be made of the
globe: the globe keeps the camera it is being watched with, which way it faces
and how far it is zoomed in, and comes out square. A map fills the frame the
way it fills a picture. Both sides are rounded down to an even number of pixels,
which is what H.264 can take.

The frames are written as `frame_00000.png` and up into a folder beside the
file and named after it, so `C:\maps\rodinia.mp4` is rendered into
`C:\maps\rodinia`. Playback is paused for the export and the current time is
put back afterwards, along with the view and the selection. A progress dialog
counts the frames as they are rendered and its Cancel button stops the export
at the next one, leaving neither frames nor video behind.

When the frames are all there, ffmpeg is called on them:

```
ffmpeg -y -framerate <fps> -i frame_%05d.png -c:v libx264 -pix_fmt yuv420p <file>
```

The folder is removed once that has run. Where no ffmpeg can be found, or where
it refuses the frames, they stay in the folder and the status bar and a dialog
say where they are and that Preferences is where an ffmpeg is named. The frames
are the work either way; encoding them again by hand is one command line.

A script exports through `app.export_video()`; see
[Scripting](Scripting.md#the-application).

## Command line

The engine takes the arguments before a bare `--`, the application those after
it:

```
MiddleEarth -- --version
MiddleEarth -- --help
MiddleEarth -- --help-command=list_features
MiddleEarth -- --no-python
MiddleEarth -- --automation-port=45455
```

`Logic/cli.gd` holds the list of switches and builds the help text from it, so a
new switch appears in `--help` by being added to `SWITCHES`. `--help` and
`--version` print and exit before the application scene is built; run them with
`--headless` for output alone, with no window at all. An unrecognized switch is
reported and exits with code 2.

`--help-command NAME` prints the docstring of one script and exits, taking its
name attached with an equals sign or as the next argument. It reads the file
rather than the interpreter, so it answers without starting one. `--no-python`
starts the application with no interpreter at all: the prompt takes nothing,
and the scripts are still listed and simply cannot be run. Both are described in
[Scripting](Scripting.md). `--automation-port` is described in
[Testing](Testing.md#the-automation-port).
