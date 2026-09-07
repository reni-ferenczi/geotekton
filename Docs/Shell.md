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

## Menus

`Application._build_menus()` creates the three menus in code and populates them.
The item ids are the `FileItem`, `ViewItem` and `HelpItem` enums, so adding an
item means adding an enum value and one `add_item` line.

| File            | Shortcut       | What it does                                     |
| --------------- | -------------- | ------------------------------------------------ |
| New             | Ctrl+N         | Empty document, after asking about unsaved changes |
| Open...         | Ctrl+O         | File dialog, then load                           |
| Open Recent     |                | The remembered files, newest first, and Clear    |
| Save            | Ctrl+S         | Write to the document path, asking for one only when it has none |
| Save As...      | Ctrl+Shift+S   | Always ask for a path                            |
| Preferences...  |                | The preferences dialog                           |
| Quit            | Ctrl+Q         | Close, after asking about unsaved changes        |

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
focus. The feature tree keeps its own keys for editing: Delete, Ctrl+Z, Ctrl+Y,
Ctrl+C, Ctrl+X, Ctrl+V and Ctrl+D. Its toolbar also has Save and Load buttons,
which run the File > Save and File > Open commands.

## Full screen

F11 switches the window between `MODE_WINDOWED` and `MODE_FULLSCREEN`. The menu
bar is not visible in full screen, so a button floats over the top of the view
to leave it again; it lives in the `FullScreenOverlay` canvas layer, which is
hidden while the window is not full screen.

## Status bar

Two fields: where the mouse is on the planet, and the open file.

- The coordinates come from the `cursor_moved` signal of the planet view, which
  fires for the globe and the map. It reads `off the planet` while the pointer
  is over the view but not over the planet.
- The file field shows the file name, with an asterisk while the document has
  unsaved changes, and the whole path as its tooltip. The window title carries
  the same name and marker.

## Preferences

One page so far, in the dialog under File > Preferences:

- **Default folder for Open and Save** — where the file dialogs start, the same
  setting the dialogs update as files are opened and saved.
- **Reopen the last file on launch** — when off, the application starts with an
  empty document however the last session ended.

Both are written to the config file described in
[Persistence](Persistence.md#the-config-file).

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
