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
whose `Delete` works only while the time is on a keyframe.

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

### Groups do not move

A group is organization: it holds features and other groups, and carries no
motion. A feature's rotation in the world comes from its own keyframes and its
[couplings](#coupling) (`Feature.world_basis()`), wherever it sits in the tree,
so moving a feature from one group to another changes nothing about where it
is. What rides on what is a coupling between two features over a span of the
timeline, and that is what takes the place of the plate circuit GPlates builds
out of plate ids and a rotation tree.

Up to 0.7.0 a group had keyframes and everything under it inherited them. A
file from then still opens: the composition of every moving group above a
feature is folded into the feature's own keyframes, sampled at every keyframe
time along the chain, so it is drawn where it was at each of those times; see
[Persistence](Persistence.md#070-to-080).

## Coupling

A feature can ride on another feature for part of the animation and go its own
way for the rest. This is the Middle Earth form of the GPlates rotation model,
where a plate's fixed plate changes from one time span to the next. A coupling
is a relation between two leaf features over a **span** of the timeline
(`Logic/coupling.gd`): `from`, the older age where it starts, `to`, the younger
age where it ends, and the parent, named by uuid. A feature can have several
spans, which do not overlap, and a parent can carry any number of riders. The
feature tree plays no part in it.

While a span holds, the rider's keyframes are its pose **relative** to the
parent: its world rotation at a time is the parent's world rotation then,
composed with the rider's own keyframe interpolation. Outside every span its
keyframes are world rotations. A span holds its older end and not its younger
one, so a keyframe at `from` is relative and a keyframe at `to` is a world pose.
A span that runs to the present holds the present too.

The parent may itself ride on another feature, and the chain is followed to its
end.

### Coupling and decoupling

Both act at the current time, from the Properties panel's
[coupling rows](Properties.md#coupling), and each is one undo version.

- **Couple** starts a span at the current time, running until the next span
  the feature already has towards the present, or the present itself. It writes
  a keyframe there holding the feature where it stands, re-expressed in the
  parent's frame.
- **Decouple** ends the span in effect at the current time and writes a keyframe
  there holding the world pose. Decoupling at the time a span starts takes the
  span away. A span that runs to the present cannot be decoupled at the present,
  since nothing is younger than that.
- **Remove** takes a span away altogether.

Every one of these re-expresses each keyframe of the feature in the frame in
effect at its own time afterwards, so nothing on the globe moves at any
keyframe. So a span boundary always has a keyframe on each side of it: the one
at `from` inside, the one at `to` outside.

Couple is refused, with the reason, when:

- the feature already rides on something at that time;
- the parent is the feature itself, a group or a topology;
- the parent already rides on the feature, directly or down a chain, at any
  time;
- the parent is not there, by its time range, all the way from the current time
  to where the span would end.

A topology cannot ride either, having no motion of its own.

### Between keyframes in different frames

Couple and Decouple keep the keyframes on either side of a boundary in their
own frames, but deleting a keyframe can leave two neighbors in different ones.
The rule then is that the span in effect at the **older** keyframe decides the
frame, and the younger keyframe is converted into that frame at its own time.
So a rider whose decoupling keyframe is deleted rides on past the old boundary
until its next keyframe. Younger than the first keyframe, that keyframe's frame
holds. Older than the last one, the frame in effect at the time holds, with the
last keyframe converted into it, so a feature coupled at its only keyframe
stands still before that time.

### A parent that is gone

Deleting a parent leaves the span in place. The Properties panel draws it in a
warning color, like a broken topology section, and the timeline bar turns the
same color. Undo brings the parent back and mends the span. While the parent
cannot be followed, whether missing, turned into something that cannot be
ridden on, or looped back by a hand-written file, it counts as not turning, so
the rider's relative keyframes read as world rotations.

### Splitting a coupled feature

Both halves of a [split](Editing.md#splitting) keep the couplings of the
feature they came from, so both go on riding on the same parent. A feature
that rode on the one split rides on the first half, which keeps the original's
uuid.

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

A group cannot be dragged: it carries no motion, so there would be nothing for
the drag to write.

The **Properties panel** has one keyframe row: how many keyframes the selected
feature has, `Key` and `Delete`. `Key` holds where the feature is now as a
keyframe at the current time, which is how a keyframe is made without moving
anything. `Delete` removes the keyframe at the current time and is greyed out
between keyframes; the keyframe marks and the `<<` and `>>` buttons below land
on one exactly. The panel shows no keyframe times or angles; see
[Properties](Properties.md#the-keyframe-row).

## Being there at all

A leaf feature has a time range, two ages. Outside it the feature is not drawn,
not hit tested, and greyed out in the tree; it is still in the document and
still in the file. Both ends count as inside. A group has no range of its own
and is there whenever its children are.

## The time control

The panel under the globe, `Scenes/Timeline/timeline.gd`:

| Control        | What it does                                            |
| -------------- | ------------------------------------------------------- |
| `<<` and `>>`  | The selected node's next keyframe towards the older or the younger end; greyed out when there is none that way |
| `<` and `>`    | One skip towards the older or the younger end, by the number beside them |
| The skip       | How far `<` and `>` jump, in millions of years; 50 to start with, remembered between runs |
| Play           | Run the animation from where the time is, or from the start when it is at the end |
| Pause          | Stop where it is                                         |
| Reset          | Back to the start of the animation, stopped              |
| The number     | Type a time                                              |
| Configure...   | The animation dialog                                     |
| The slider     | Drag the time; taking hold of it takes over from playback |
| The strip below| A mark for each keyframe of the selected node, and one for the current time. A click on a mark goes to that keyframe exactly, and the pointer over one says its time |

The skip is for moving about while editing. Someone laying out an animation
in 50 My steps and then working on one feature's movement in 10 My steps
types 10 into the box, and nothing about the document or the animation
changes with it. **Page Up** and **Page Down** make the same two skips from
the keyboard, wherever the focus is; they are the Time menu's items, which is
what gives a shortcut that reach. A skip never leaves the animation range.

Landing on a keyframe is a click on its mark, or `<<` and `>>` with
**Ctrl+Page Up** and **Ctrl+Page Down**, which go to the selected node's next
keyframe either way and stop at the last one. A keyframe time is a full
precision float, and the mark is the way to reach it without typing every
digit. The reach of a click is `Timeline.MARKER_PICK_PIXELS` either side of
the mark; between two marks a click does nothing.

The slider holds the negative of the time, which is what puts the oldest end on
the left: a slider always grows to the right and an age grows into the past. It
spans the animation range, so configuring a different range lays it out again.

## The animation

The dialog behind `Configure...` sets four things, kept in the config file
(`Logic/animation_settings.gd`) because they say how fast someone likes to
watch rather than anything about the planet:

| Setting            | Default | Meaning                                      |
| ------------------ | ------- | -------------------------------------------- |
| Start (Ma)         | 2000    | Where playback begins                        |
| End (Ma)           | 0       | Where it ends                                |
| Speed (My per second) | 50   | How far the time moves in a second of watching, always positive |
| Start again at the end | off | Loop instead of stopping                     |

The direction comes from the two ends, not from the sign of the speed: start
above end counts down, which is the usual way round. The default takes the
default range in forty seconds.

Playback is continuous. Every rendered frame moves the time on by the seconds
the frame before it took, times the speed (`AnimationSettings.advance()`), so
between two keyframes what is on the globe is the interpolation the keyframes
already give, linear in time, with no steps to see. Nothing is accumulated
beyond the time itself: a slow frame moves further, and the end is reached at
the same moment on any machine. The last step is cut short at the end, where
playback stops or, with the loop on, starts again from the beginning.

Up to 0.7.0 playback stepped through a list of frames an increment apart at a
frame rate, and the `<` and `>` buttons stepped by the same increment. A config
file from then still opens: the keys playback no longer reads are left alone
and the speed starts at its default.

## What a frame costs

Rotating every vertex on the processor for every frame would not hold up, so it
does not happen. The geometry texture holds the vertices in each feature's own
frame; a second, small texture holds one rotation per feature; and the shader
does the turning. A step of the animation re-uploads three texels per feature
and nothing else, whatever the triangle count is. See
[Shader](Shader.md#per-feature-rotation).

`uv run Tests/run.py performance` measures it. What it measures and what it
found are in [Testing](Testing.md#frame-time).
