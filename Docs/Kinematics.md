# Kinematics

The graphs under the globe: where the selected feature has been over time, and
how fast it has been turning. They answer the question a keyframe list cannot —
what the numbers in it amount to — without anyone having to play the animation
and watch.

The panel is hidden until View > Kinematics puts it up, because the globe is
what the rest of the window is for. Once shown it stays that way, like the other
panels; see [Shell](Shell.md#menus).

## What is graphed

By default the panel draws one row, the rate, over a time axis that runs from
the oldest time on the left to the youngest on the right, exactly as the
timeline slider does. View > Kinematics: latitude and longitude adds a row for
each above the rate, all three sharing the axis, and makes the panel two rows
taller to fit them. The switch is remembered in the settings file as
`kinematics_place`, like the panels themselves. A white line stands on the
current time in every row and moves with it.

| Row       | What it shows                          | Range it is drawn against |
| --------- | -------------------------------------- | ------------------------- |
| Latitude  | Where the middle of the feature is, when switched on | -90° to +90° |
| Longitude | The same, east and west, when switched on | -180° to +180°          |
| Rate      | How fast it turns, one bar per span between keyframes | zero to the fastest span |

The two place rows are drawn against the whole of what a latitude and a
longitude can be, rather than against what this feature happens to cover. A
craton that has hardly moved then reads as one that has hardly moved, instead of
being blown up until its wobble fills the box.

Above the rows is a line of the same numbers at the current time: the title,
the time, the place, and the rate in both units. It gives the latitude and the
longitude whether or not their rows are drawn.

## The quantities

**The middle of a feature** is the mean of its vertices taken as points on the
unit sphere, put back on the sphere. Every vertex counts once, so it is the
middle of the outline rather than of the area inside it; for the shapes anyone
draws the two are close, and this one is also defined for a polyline and for a
multipoint, which have no area at all.

**Where it is** at a time is that point carried through the feature's world
rotation, which is what the user sees move: its own keyframes, composed with
the parent's world rotation while it [follows another feature](Time.md#coupling).
A group above it moves nothing. So the graphs of a coupled feature plot its
world path, not its keyframes relative to the parent.

**The rate** is worked out between one keyframe time and the next: the single
turn that carries where the node stands at one to where it stands at the other,
divided by the millions of years between them. Two units of the same thing:

| Quantity          | Unit  | What it is                                            |
| ----------------- | ----- | ----------------------------------------------------- |
| Angular velocity  | °/My  | The angle of that turn per million years               |
| Rate              | km/My | The same angle in radians times the planet radius      |

The distance is what a point a quarter turn away from the rotation axis covers,
which is the fastest anything on the planet moves under that rotation. A point
nearer the axis covers less, down to nothing at the axis itself. The radius is
the preference, so a document read against a smaller planet reports smaller
distances from the same rotation; see
[Editing](Editing.md#the-planet-radius).

A rate has no direction. A turn back the way it came is as fast as the turn out,
and the bar for that span is as tall.

The times the rate can change at are the feature's keyframe times: a feature
with three keyframes has two spans. A coupled feature's world motion can also
change where a coupling starts or ends, and wherever its parent's motion
changes while it follows it, so those times are added: both ends of every
coupling, and every such time of the parent that falls inside the span,
followed up the chain (`Kinematics.motion_times()`). A ridge follows two
parents at once, and either of them turning moves the midpoint it sits on, so
both are counted.

## What has no graph

- **A group**, which has no geometry of its own and so no middle to follow, and
  carries no motion either.
- **A line topology**, which borrows every vertex of it from the features its
  sections run along and is resolved afresh at each time. Its own rotation
  carries nothing, so a path drawn from it would be a fiction.
- **A feature with no geometry yet**, one that has been added but not drawn.

The panel says which of these it is looking at rather than going blank.

## Outside the keyframes

Nothing is extrapolated. Younger than the first keyframe and older than the
last, the nearest one is held, so the place rows run flat out to the ends of the
axis and the rate row has no bar there. That is what the motion itself does; see
[Time](Time.md#keyframes).

## Where the axis begins and ends

The graphs span the animation range, the same span the timeline slider covers,
so the cursor and the slider handle stand over the same time. Configuring a
different range through the time control lays the graphs out again.

## The code

`Logic/kinematics.gd` works out the numbers and touches no scene, so all of it
is covered by a headless test (`Tests/Unit/test_kinematics.gd`). The panel,
`Scenes/Application/kinematics_panel.gd`, draws them and follows the selection
and the current time; what it holds is read back through the port's
`get_kinematics`, and `Tests/Golden/kinematics.png` is the reference for what it
draws. See [Testing](Testing.md).
