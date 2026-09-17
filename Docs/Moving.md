# Craton Movement — Implementation Notes

## Overview

Moving a feature rotates its vertices on the sphere rather than shifting lat/lon values directly. This preserves shape at all latitudes — direct lat/lon translation distorts shapes near the poles.

A node stores a list of keyframes alongside the `rings` its geometry is made
of, each one a time and a `Vector3` of degrees. The rings are never modified
during a move; only the keyframes change. What a node's rotation is at a given
time, and how a coupling puts one feature's motion on another, is in
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
callers have, since the rotation arrives as a matrix rather than as three
angles.

Committing a new outline on top of a moved feature goes through the inverse of
that composed matrix, `Feature.world_basis(root, feature, time).transposed()`,
so what was clicked in world space is stored in the feature's own frame.

## Moving in time

A drag writes or replaces the keyframe at the current time, and only the release
records an undo version. Cancelling puts the whole keyframe list back the way it
was, not just the one rotation, because a drag may have added a keyframe that
was not there before.

The grabbed point and the target are both in world space, and so is the
rotation that comes out, since a feature's rotation is its own wherever it sits
in the tree:

```gdscript
Keyframe.upsert(node.keyframes, time, Feature.compute_move_rotation(
    anchor_world, target_world, node.rotation_at(time)))
```

Only a leaf feature is dragged. A group carries no motion, so a drag of one
would have nothing to write; see [Time](Time.md#groups-do-not-move).

### Dragging a coupled feature

A feature that [follows another](Time.md#coupling) at the current time is
dragged in world space all the same: the drag starts from its world rotation,
`Feature.world_basis()`, and the rotation that comes out is put into the frame
in effect at the current time before it is written, by
`Coupling.rotation_for()`. Inside a span that is the pose relative to the
parent, so the keyframe is relative and the feature lands where it was dropped.

Dragging a parent moves its children at that time. Nothing is written
to the children: their keyframes are relative already, and
`Planet.Geometry.resolve()` works every child out from its parent's world
rotation, parents first and each once.

---

## Mouse-Driven Movement

### Data flow

1. **LMB press** on the planet → `planet_view.gd` works out the latitude and
   longitude under the pointer with `screen_to_latlon`, emits
   `input_event_globe(lat, lon, event)` (or `input_event_map` on the map) and
   then `move_started(lat, lon)`.
2. `application.gd._on_move_started` records:
   - `move_anchor_local` = the grabbed point in the frame the parent gives it
   - `move_base_rot` = the node's own rotation at the current time
   - `move_base_keyframes` = a copy of the list, for a cancelled drag
3. **Mouse motion** → the same path → `move_to(lat, lon)` emitted.
4. `_on_move_to` carries the target into the same frame, calls
   `Feature.compute_move_rotation`, writes the keyframe at the current time and
   refreshes where the features sit.
5. **LMB release on the planet** → `stop_moving()` — saves undo, keeps the keyframe.
6. **LMB release off the planet** → `cancel_moving()` — puts the keyframe list back.

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

## Rotating

A move carries the grabbed point along a great circle and leaves the feature
facing the way it was. Turning one in place is the other rotation a drag can
write, and the [Rotate and Pole tools](Editing.md#turning-a-feature) write it.
Both turn the feature about an axis rather than along a path, and the axis is
the only thing that differs between them:

- the **Rotate** tool takes the axis through the middle of the feature, which
  `Feature.centroid_axis()` works out as the direction of the sum of its world
  vertices at the current time. The sum is parallel to the axis by construction,
  so turning about it leaves the middle exactly where it was and the feature
  spins in place;
- the **Pole** tool takes the pole a click placed, in world coordinates. A
  feature far from the pole swings around it: every vertex turns by the same
  angle about the pole and keeps its distance from it.

The angle is the one the drag has swept about the axis. Both ends of the drag,
the point that was grabbed and the point under the pointer, are projected onto
the plane normal to the axis, and the angle between the two projections is
measured about the axis, in `Feature.angle_about_axis()`:

```gdscript
var from_flat := from_world - axis * axis.dot(from_world)
var to_flat := to_world - axis * axis.dot(to_world)
return atan2(axis.dot(from_flat.cross(to_flat)), from_flat.dot(to_flat))
```

`atan2` of the cross product along the axis over the dot product gives the
signed angle, counterclockwise seen from the far end of the axis, and the
lengths of the two projections cancel between the two arguments, so they need no
normalizing. A projection shorter than `Feature.MIN_AXIS_OFFSET`, which is a
little under three degrees from the axis or from the point opposite it, has no
direction worth measuring, and the drag keeps the angle it had. That is the same
refusal `compute_move_rotation()` gives an antipodal drag.

What is written is the same kind of composition a move writes,
`Feature.compute_spin_rotation()`:

```gdscript
decompose_rotation_degrees(Basis(axis, angle) * build_rotation_basis(base_rot))
```

The base rotation is the one the feature had when the drag started — its own, or
its world rotation when it follows another — so the turn is applied on top of
wherever the feature already stood. The keyframe goes in at the current time
while the drag runs and the release records one undo version, exactly as a move
does; a child's keyframe goes through `Coupling.rotation_for()` first, so what is
stored is relative to the parent.

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
