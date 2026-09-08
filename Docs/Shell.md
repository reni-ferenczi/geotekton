# The application window

The window is one `Application` scene (`Scenes/Application/application.tscn`):
a menu bar, three panels around the planet view, and a status bar. The panels
are split containers, not docks, so they can be resized and hidden but not torn
off or rearranged.

```
menu bar
Features | tools, planet view, timeline | Properties
status bar
```

The two splitters start at 576 px for the feature tree and 320 px for the
properties panel. The feature tree is the wider of the two because its toolbar
sets the floor: thirteen buttons and five separators in one `HBoxContainer` that
never wraps, so a `SplitContainer` cannot give the panel less than they need.
576 px is what that comes to, and the offset says so rather than asking for a
width it cannot have. Making the toolbar take less — wrapping it, scrolling it, a
denser icon size, or moving the rare buttons into a menu — is what it would take
to narrow the panel; see GP-0019.

## Menus

`Application._build_menus()` creates the four menus in code and populates them.
The item ids are the `FileItem`, `EditItem`, `ViewItem` and `HelpItem` enums, so
adding an item means adding an enum value and one `add_item` line.

| File            | Shortcut       | What it does                                     |
| --------------- | -------------- | ------------------------------------------------ |
| New             | Ctrl+N         | Empty document, after asking about unsaved changes |
| Open...         | Ctrl+O         | File dialog, then load                           |
| Open Recent     |                | The remembered files, newest first, and Clear    |
| Save            | Ctrl+S         | Write to the document path, asking for one only when it has none |
| Save As...      | Ctrl+Shift+S   | Always ask for a path                            |
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
| Status Bar  |          | Show or hide the status bar               |
| Full Screen | F11      | Enter or leave full screen                |

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

One page so far, in the dialog under File > Preferences:

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

All of them are written to the config file described in
[Persistence](Persistence.md#the-config-file). So is the state of the Snap
switch in the toolbar, which is not in the dialog because it is toggled while
editing rather than set once.

## Command line

The engine takes the arguments before a bare `--`, the application those after
it:

```
MiddleEarth -- --version
MiddleEarth -- --help
MiddleEarth -- --automation-port=45455
```

`Logic/cli.gd` holds the list of switches and builds the help text from it, so a
new switch appears in `--help` by being added to `SWITCHES`. `--help` and
`--version` print and exit before the application scene is built; run them with
`--headless` for output alone, with no window at all. An unrecognized switch is
reported and exits with code 2. `--automation-port` is described in
[Testing](Testing.md#the-automation-port).
