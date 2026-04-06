# Craton Movement — Implementation Notes

## Overview

Moving a craton rotates its vertices on the sphere rather than shifting lat/lon values directly. This preserves shape at all latitudes — direct lat/lon translation distorts shapes near the poles.

Each leaf feature stores `rotation_angles: Vector3` (degrees) alongside its original `vertices: Array[Vector2]`. The vertices are never modified during a move; only `rotation_angles` changes.

---

## Rotation Representation

The rotation is a YXZ Euler decomposition:

```
R = Ry(α) · Rx(β) · Rz(γ)
```

- `rotation_angles.x` = α (longitude shift, rotation around Y / up axis)
- `rotation_angles.y` = β (latitude shift, rotation around X / right axis)
- `rotation_angles.z` = γ (self-rotation, reserved, kept at 0)

`_build_rotation_basis` and `_decompose_rotation_degrees` in `Logic/feature.gd` convert between `Vector3` degrees and `Basis`.

### Godot Basis Indexing

Godot `Basis` is **column-major**: `m[col][row]`. Code that indexes as if it were row-major will silently read the wrong entries and produce wrong angles.

Standard matrix entry M[row][col] maps to Godot `m[col][row]`.

For M = Ry(α) · Rx(β) · Rz(γ), the entries used in decomposition are:

| Standard entry | Value     | Godot index |
|----------------|-----------|-------------|
| M[1][2]        | −sin β    | `m[2][1]`   |
| M[0][2]        | sin α cos β | `m[2][0]` |
| M[2][2]        | cos α cos β | `m[2][2]` |
| M[1][0]        | cos β sin γ | `m[0][1]` |
| M[1][1]        | cos β cos γ | `m[1][1]` |
| M[2][0] (gimbal) | −sin α  | `m[0][2]`   |
| M[0][0] (gimbal) | cos α   | `m[0][0]`   |

---

## Vertex Transformation

`apply_rotation(verts, rot)` converts each stored lat/lon vertex to a 3D unit-sphere point, applies the rotation matrix, and converts back:

```
xyz = latlon_to_xyz(v)
xyz' = R * xyz
v'  = xyz_to_latlon(xyz')
```

The internal XYZ convention (`_latlon_to_xyz_s` / `_xyz_to_latlon_s`) uses the shader-compatible mapping:

```
xyz = (cos_lat · cos_lon,  sin_lat,  cos_lat · sin_lon)
```

This convention is self-consistent: `apply_rotation` and `compute_move_rotation` both use it, so rotations compose correctly.

`unapply_rotation` applies the transpose (inverse) of the same matrix, used when committing a new outline on top of a moved craton.

---

## Mouse-Driven Movement

### Data flow

1. **LMB press** on globe → physics body input event fires in `planet.gd` → emits `input_event_globe(lat, lon, event)` → `planet_view.gd` emits `move_started(lat, lon)`.
2. `application.gd._on_move_started` records:
   - `move_anchor_world` = `Feature._latlon_to_xyz_s(Vector2(lat, lon))`
   - `move_base_rot` = current `rotation_angles`
3. **Mouse motion** → physics event fires → `move_to(lat, lon)` emitted.
4. `_on_move_to` computes `target_world`, calls `Feature.compute_move_rotation`, updates `rotation_angles`, refreshes the display.
5. **LMB release on globe** → `stop_moving()` — saves undo, keeps new angles.
6. **LMB release outside globe** → `cancel_moving()` — restores `move_base_rot`.

### compute_move_rotation

Given the fixed anchor point and a new target point (both unit-sphere vectors), find the new rotation angles such that the anchor tracks the target:

```gdscript
# delta rotation: maps anchor_world → target_world
var axis  := anchor_world.cross(target_world).normalized()
var angle := acos(clamp(dot(anchor, target), -1, 1))
var delta := Basis(axis, angle)

# compose: new = delta · base
var m_new := delta * _build_rotation_basis(base_rot)
return _decompose_rotation_degrees(m_new)
```

Returns `null` if anchor and target are antipodal (no unique great-circle axis). In that case the caller keeps the previous angles. This is the mechanism that "cancels" the move when the mouse leaves the globe — the last valid angles are retained until LMB release, which either commits (on-globe) or snaps back (off-globe).

### Full-sphere coverage

Using a delta rotation composed with the base matrix (rather than solving for angles analytically) gives full-sphere coverage with no ±45° latitude limit. Analytic solves for individual Euler angles can degenerate outside the reachable range of a single-axis system.

---

## Physics Lat/Lon Extraction

`planet.gd` extracts lat/lon from the 3D hit position in globe-local space:

```gdscript
var local_pos := globe.transform.inverse() * event_position
var rad := Vector2(local_pos.x, local_pos.z).length()
var lat := rad_to_deg(atan2(local_pos.y, rad))
var lon := rad_to_deg(atan2(-local_pos.x, -local_pos.z))
```

This lat/lon feeds directly into `_latlon_to_xyz_s`, so both the anchor/target construction and the vertex transformation use the same coordinate system. No separate convention conversion is needed.
