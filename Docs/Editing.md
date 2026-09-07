# Usage

## Tools

The toolbar contains two mutually exclusive tool buttons and a selector:

- **Move** — Default. Enables globe rotation, dragging, and feature movement.
- **Draw** — Enables drawing on the globe surface. See `Docs/Draw.md` for full details.
- **Geometry kind** — What the Draw tool produces: Polygon, Polyline or Multipoint.

## The feature tree

Each row of the tree carries the title of the feature or group and two buttons:
a colour swatch, on a feature only, and a switch that enables the node. A
disabled node is neither drawn nor hit tested, itself and everything under it.

Up to 0.1.0 the rows also had invert, single, wrap, resize and repeat, five
switches left over from the rule editor this interface came from. Nothing read
them and they were dropped in 0.2.0, files included.

## Moving Features

When the Move tool is active and a leaf feature with geometry is selected in the feature tree, left-clicking on the globe starts moving that feature.

### Input Mapping

| Input | Action |
|-------|--------|
| **LMB press** on globe | Start moving the selected feature |
| **Mouse motion** (while moving) | Turn the feature so that the anchor follows the cursor |
| **LMB release** | Finish moving — saves an undo version |
| **MMB hold** (while moving) | Temporarily rotate the planet instead of moving the feature |
| **MMB release** (while moving) | Resume moving the feature |
| **Ctrl+LMB** | Geographic dragging (unchanged, does not start a move) |
| **MMB** (not moving) | Planet rotation (unchanged) |
| **Scroll wheel** | Zoom in/out (always available) |

### Behavior

- During a move the mouse cursor is hidden and the mouse is captured, so the cursor does not leave the window.
- Horizontal mouse movement changes longitude, vertical movement changes latitude.
- Holding the middle mouse button while moving temporarily switches to planet rotation. Releasing it resumes moving the feature. This allows repositioning the view without letting the feature go.
- Releasing the left mouse button ends the move, restores the cursor, and records an undo version.

### Auto-select After Drawing

After committing a shape (pressing Enter in the Draw tool), the Move tool is automatically selected. This prevents accidentally drawing a second shape on the same feature.

## Globe Navigation

Globe navigation works in both Move and Draw modes unless noted otherwise.

| Input | Action |
|-------|--------|
| **Ctrl+LMB drag** on globe | Geographic dragging — rotates the globe so the surface follows the cursor |
| **MMB drag** | Free rotation — captured mouse rotation of the globe |
| **Scroll wheel** | Zoom in/out (adjusts camera FOV) |
