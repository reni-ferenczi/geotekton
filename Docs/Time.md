# Time, motion and animation

## Which way time runs

Time is an **age in millions of years before present**, the convention GPlates
uses. A larger number is older: 0 is now and 2000 is deep past. Everything in
the application says the same thing:

- The timeline slider runs from the oldest time on the left to 0 on the right.
- An animation normally starts at a large time and ends at 0, so it plays from
  left to right and the Earth is watched forwards.
- A feature's time range is an age span, so its `To` is the older end.

Ages run up to `Document.MAX_TIME`, ten thousand million years, which is older
than the Earth and so out of the way of anything anyone models.

## The current time

`Logic/document.gd` owns it. It says where the document is being looked at
rather than anything about the planet, so moving it records no undo version and
leaves the dirty flag alone, and a file always opens at the present.

Everything that moves the time asks the document to move it and then follows the
`time_changed` signal back:

| What moves it       | How                                        |
| ------------------- | ------------------------------------------ |
| The slider          | dragged, or stepped by its buttons          |
| The typed time      | the number beside the slider                |
| Playback            | one frame of the animation at a time        |
| A script            | `set_time` on the automation port           |

What follows the signal is the globe, which redraws at the new time; the feature
tree, which greys out whatever is not there then; and the Properties panel,
which marks the keyframe the time has landed on.

## Keyframes

A node's motion is a list of keyframes, each a time and a rotation, kept sorted
with the youngest first (`Logic/keyframe.gd`). Between two of them the rotation
turns along the shortest path on the sphere of rotations, a quaternion slerp of
the two; outside the first and the last the nearer one is held rather than
extrapolated. A node with one keyframe therefore stands in that one place at
every time, and a node with none does not move at all.

What a list of keyframes amounts to — where the feature has been and how fast it
turned — is graphed in the [Kinematics](Kinematics.md) panel.

Every interpolation starts from the two keyframes around the time being asked
about, never from the frame before it, so a long animation cannot drift away
from what the keyframes say. Landing exactly on a keyframe gives back what that
keyframe holds, without passing through a quaternion on the way.

### Groups carry motion

A group has keyframes too, and everything under it inherits them. A node's
rotation in the world is its own composed with every ancestor's, resolved from
the root down (`Feature.world_basis()`), so a terrane placed inside a craton
group rides on the craton and turns further by whatever it does itself. This
takes the place of the plate circuit GPlates builds out of plate ids and a
rotation tree; here the tree is the one already on screen.

The root group is included, so keyframes on it turn everything at once.

### Precision

Times are plain floats, which GDScript keeps at double precision, and the file
keeps them at full precision. An age runs to thousands of millions of years and
a keyframe has to come back as the time it was written at.

Rotations are `Vector3` degrees, and `Vector2`, `Vector3`, `Basis` and
`Quaternion` are all 32-bit in a standard Godot build. That is about seven
significant digits, far finer than a rotation anyone picks with a mouse, so
only the times need the extra width.

## Making a keyframe

The **Move tool** writes one. Dragging a feature over the globe writes or
replaces the keyframe at the current time as it goes, so what is on the globe
during the drag is what the release records. Moving at one time and again at
another is all it takes to make something move; see
[Moving](Moving.md#moving-in-time).

A group can be dragged as well, because a group carries motion. The root cannot:
turning it would only turn the globe, which the view already does.

The **Properties panel** lists the keyframes of whatever is selected, in a table
of the time and the three angles, with the row the current time sits on marked.
Every cell can be edited, so a keyframe dragged roughly into place can be given
exact numbers. `Key` holds where the node is now as a keyframe at the current
time, which is how a keyframe is made without moving anything, and `Delete`
takes the selected one off. Moving a keyframe onto the time of another is
refused: the two would have to become one, and nobody said which rotation should
survive.

## Being there at all

A leaf feature has a time range, two ages. Outside it the feature is not drawn,
not hit tested, and greyed out in the tree; it is still in the document and
still in the file. Both ends count as inside. A group has no range of its own
and is there whenever its children are.

## The time control

The panel under the globe, `Scenes/Timeline/timeline.gd`:

| Control        | What it does                                            |
| -------------- | ------------------------------------------------------- |
| `<` and `>`    | One increment towards the older or the younger end       |
| Play           | Run the animation from where the time is                 |
| Pause          | Stop where it is                                         |
| Reset          | Back to the start of the animation, stopped              |
| The number     | Type a time                                              |
| Configure...   | The animation dialog                                     |
| The slider     | Drag the time; taking hold of it takes over from playback |
| The strip below| A mark for each keyframe of the selected node, and one for the current time |

The slider holds the negative of the time, which is what puts the oldest end on
the left: a slider always grows to the right and an age grows into the past. It
spans the animation range, so configuring a different range lays it out again.

## The animation

The dialog behind `Configure...` sets six things, kept in the config file
(`Logic/animation_settings.gd`) because they say how fast someone likes to
watch rather than anything about the planet:

| Setting            | Default | Meaning                                      |
| ------------------ | ------- | -------------------------------------------- |
| Start (Ma)         | 2000    | Where playback begins                        |
| End (Ma)           | 0       | Where it ends                                |
| Increment (My)     | 10      | How far one frame moves, always positive     |
| Frames per second  | 24      | How fast the frames come                     |
| Start again at the end | off | Loop instead of stopping                     |
| Land exactly on the end time | on | Add a short last step when the increment does not divide the range |

The direction comes from the two ends, not from the sign of the increment:
start above end counts down, which is the usual way round.

`AnimationSettings.times()` gives the times the animation steps through. Each
one is a whole number of increments from the start rather than the one before it
plus an increment, so two thousand frames of a tenth of a million years still
land exactly on the end. Playback walks that list, so no frame time is ever
accumulated; only the pacing depends on the wall clock, and a slow machine
catches up rather than falling behind.

## What a frame costs

Rotating every vertex on the processor for every frame would not hold up, so it
does not happen. The geometry texture holds the vertices in each feature's own
frame; a second, small texture holds one rotation per feature; and the shader
does the turning. A step of the animation re-uploads three texels per feature
and nothing else, whatever the triangle count is. See
[Shader](Shader.md#per-feature-rotation).

`uv run Tests/run.py performance` measures it. What it measures and what it
found are in [Testing](Testing.md#frame-time).
