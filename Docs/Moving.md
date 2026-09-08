# Craton Movement — Implementation Notes

## Overview

Moving a feature rotates its vertices on the sphere rather than shifting lat/lon values directly. This preserves shape at all latitudes — direct lat/lon translation distorts shapes near the poles.

A node stores a list of keyframes alongside the `rings` its geometry is made
of, each one a time and a `Vector3` of degrees. The rings are never modified
during a move; only the keyframes change. What a node's rotation is at a given
time, and how a group's reaches the features under it, is in
[Time](Time.md#keyframes); this document is about the rotation itself.

---

## Rotation Representation

The rotation is a YXZ Euler decomposition:

```
R = Ry(α) · Rx(β) · Rz(γ)
```

A rotation is a `Vector3` of degrees:

- `x` = α (longitude shift, rotation around Y / up axis)
- `y` = β (latitude shift, rotation around X / right axis)
- `z` = γ (self-rotation)

The keyframe table of the Properties panel calls the three of them Lon, Lat and
Spin.

`build_rotation_basis` and `decompose_rotation_degrees` in `Logic/feature.gd`
convert between `Vector3` degrees and `Basis`. They are public because the
keyframe interpolation needs them: it converts both ends to quaternions, slerps,
and converts back.

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

`unapply_rotation` applies the transpose (inverse) of the same matrix.
`apply_basis` takes a `Basis` that has already been built, which is what most
callers have: a node's rotation in the world is composed from its own and its
ancestors', so it arrives as a matrix rather than as three angles.

Committing a new outline on top of a moved feature goes through the inverse of
that composed matrix, `Feature.world_basis(root, feature, time).transposed()`,
so what was clicked in world space is stored in the feature's own frame.

## Moving in time

A drag writes or replaces the keyframe at the current time, and only the release
records an undo version. Cancelling puts the whole keyframe list back the way it
was, not just the one rotation, because a drag may have added a keyframe that
was not there before.

A node inside a group is dragged in the frame its parent gives it. The grabbed
point and the target are both carried into that frame first, so the rotation
that comes out is the node's own and the inherited part is neither undone nor
applied twice:

```gdscript
var parent_inverse := Feature.world_basis(root, root.find_parent(node), time).transposed()
var anchor_local := parent_inverse * anchor_world
var target_local := parent_inverse * target_world
Keyframe.upsert(node.keyframes, time, Feature.compute_move_rotation(
    anchor_local, target_local, node.rotation_at(time)))
```

Conjugating the delta rotation this way maps its axis into the parent's frame
and leaves its angle alone, which is why the same `compute_move_rotation` works
for a node at any depth.

A group can be dragged too, since a group carries motion its children inherit.
The root cannot: turning it would only turn the globe.

---

## Mouse-Driven Movement

### Data flow

1. **LMB press** on globe → physics body input event fires in `planet.gd` → emits `input_event_globe(lat, lon, event)` → `planet_view.gd` emits `move_started(lat, lon)`.
2. `application.gd._on_move_started` records:
   - `move_anchor_local` = the grabbed point in the frame the parent gives it
   - `move_base_rot` = the node's own rotation at the current time
   - `move_base_keyframes` = a copy of the list, for a cancelled drag
3. **Mouse motion** → physics event fires → `move_to(lat, lon)` emitted.
4. `_on_move_to` carries the target into the same frame, calls
   `Feature.compute_move_rotation`, writes the keyframe at the current time and
   refreshes where the features sit.
5. **LMB release on globe** → `stop_moving()` — saves undo, keeps the keyframe.
6. **LMB release outside globe** → `cancel_moving()` — puts the keyframe list back.

### compute_move_rotation

Given the fixed anchor point and a new target point (both unit-sphere vectors), find the new rotation angles such that the anchor tracks the target:

```gdscript
# delta rotation: maps anchor_world → target_world
var axis  := anchor_world.cross(target_world).normalized()
var angle := acos(clamp(dot(anchor, target), -1, 1))
var delta := Basis(axis, angle)

# compose: new = delta · base
var m_new := delta * build_rotation_basis(base_rot)
return decompose_rotation_degrees(m_new)
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
