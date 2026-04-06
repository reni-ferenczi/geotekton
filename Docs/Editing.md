# Usage

## Tools

The toolbar contains two mutually exclusive tool buttons:

- **Move** — Default. Enables globe rotation, dragging, and craton movement.
- **Draw** — Enables craton drawing on the globe surface. See `Docs/Draw.md` for full details.

## Moving Cratons

When the Move tool is active and a leaf feature with existing craton data is selected in the feature tree, left-clicking on the globe starts moving that feature's craton.

### Input Mapping

| Input | Action |
|-------|--------|
| **LMB press** on globe | Start moving the selected feature's craton |
| **Mouse motion** (while moving) | Translate all craton vertices along latitude/longitude |
| **LMB release** | Finish moving — saves an undo version |
| **MMB hold** (while moving) | Temporarily rotate the planet instead of moving the craton |
| **MMB release** (while moving) | Resume moving the craton |
| **Ctrl+LMB** | Geographic dragging (unchanged, does not start a move) |
| **MMB** (not moving) | Planet rotation (unchanged) |
| **Scroll wheel** | Zoom in/out (always available) |

### Behavior

- During a move the mouse cursor is hidden and the mouse is captured, so the cursor does not leave the window.
- Horizontal mouse movement changes longitude, vertical movement changes latitude.
- Holding the middle mouse button while moving temporarily switches to planet rotation. Releasing it resumes craton movement. This allows repositioning the view without releasing the craton.
- Releasing the left mouse button ends the move, restores the cursor, and records an undo version.

### Auto-select After Drawing

After committing a craton outline (pressing Enter in the Draw tool), the Move tool is automatically selected. This prevents accidentally drawing a second craton on the same feature.

## Globe Navigation

Globe navigation works in both Move and Draw modes unless noted otherwise.

| Input | Action |
|-------|--------|
| **Ctrl+LMB drag** on globe | Geographic dragging — rotates the globe so the surface follows the cursor |
| **MMB drag** | Free rotation — captured mouse rotation of the globe |
| **Scroll wheel** | Zoom in/out (adjusts camera FOV) |
