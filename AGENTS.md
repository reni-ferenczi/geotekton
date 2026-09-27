You're experienced in game and application development using the Godot game engine. 
You're also a Python developer excellent at writing tooling for Godot base game and application development.
You also have extensive experience in plate tectonics research and the applications used for that academic work.
This is a desktop application implemented in the Godot game engine.
You are free to use any godot skills as required.
You may use MCP server based automation to run and test the application in development as needed for the task.
If a node is used as `%UniqueName` in the GDScript code, then make sure it has the `unique_name_in_owner` set to `true`.
The Godot binaries are here: `C:\Tools\Godot`
See `README.md` for further details.

## Toolbar icons (changed on purpose, do not revert)
On 2026-09-27 the toolbar icons were switched to the new icon set in `Assets/Geotekton Icons`
(the grey shaded style). This was deliberate, and other work is happening in parallel,
so do not revert it, even if a diff or merge suggests it:
- `Scenes/Application/application.tscn`: Pole uses `Icons1-PoleRotateTool.png`, zoom uses
  `Icons1-Minus.png`/`Icons1-Plus.png`, rotate view uses
  `Icons1-RotateAnticlockwise.png`/`Icons1-RotateClockwise.png`, reset uses `Icons1-EarthFace.png`.
- `Scenes/Features/feature_tree_toolbar.tscn`: Add feature uses `Icons1-AddFeature.png`,
  Collapse/Expand use `Icons1-Minus.png`/`Icons1-Plus.png`.
- The other toolbar icons (Move, Rotate, Draw, Vertex, Measure, Split, Undo, Redo, Duplicate, Save)
  were redrawn in place under their existing file names.
- `Icons1-RotateAnticlockwise.png` and `Icons1-PoleRotateTool.png` were renamed on purpose,
  from `Icons1-RotateAntilockwise.png` and `Icons1-RotatePole.png`, to match their `.import` files.
- `Icons1-EarthFront.png` was deleted on purpose and replaced by `Icons1-EarthFace.png`.
- `Scenes/Application/properties.gd`: the Follow row's pick button ("Click a feature on the planet to follow it")
  uses `Icons1-Click.png` (`CLICK_ICON`), not the Pointer.svg glyph.
- `Logic/feature_icon.gd`: `TYPE_FILES` gives a feature with no icon its type's picture (Line, Points,
  Circle, Hotspot; Polygon and Topology keep `Icons1-Features`), and those four are also in `CATALOG`.
