# Kinematics

The graphs under the globe: where the selected feature has been over time, and
how fast it has been moving. They answer the question a keyframe list cannot —
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
| Rate      | How fast its middle moves, one bar per span between keyframes | zero to the fastest span |

The two place rows are drawn against the whole of what a latitude and a
longitude can be, rather than against what this feature happens to cover. A
craton that has hardly moved then reads as one that has hardly moved, instead of
being blown up until its wobble fills the box.

The rate row gives the rate at the current time beside its top, in the unit
Preferences > General > **Plate rate in** names, cm/yr unless it says km/My.
That is the only number the panel writes. The bars are scaled against the
fastest span, but that figure is not written anywhere: it says nothing about
the motion at the current time, and a reader took it for the rate (GP-0136).
The place is only graphed, in the latitude and longitude rows. The panel gives
no title, time or bearing (GP-0142); the line above the rows only says why
there is nothing to graph, see below.

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

**The rate** is the speed of the middle of the feature between one motion
time and the next, worked out the way GPlates' kinematic graphs do it
(`calculate_velocity_vector_and_omega()` in `src/maths/CalculateVelocity.cc`):

1. The stage rotation that carries the world rotation at the older end of the
   span to the one at the younger end, `q_young * inverse(q_old)`, the shorter
   of `q` and `-q`.
2. Its angle over the length of the span is the angular velocity, and its axis
   the axis of the turn.
3. The velocity of the middle, where it stands at the younger end, is that
   angular velocity times the planet radius times `cross(axis, middle)`. Its
   length is the rate.

GPlates follows one chosen point, by default the first vertex of the feature;
the middle stands in for it here. A spin about the middle moves the middle by
nothing and reads zero, and a drag reads what the plate did. GPlates works the
velocity out against the fixed Earth equatorial radius; the panel uses the
radius preference instead, so a smaller planet reads slower from the same
rotation (see [Editing](Editing.md#the-planet-radius)). The panel gives no
angle per million years, only this speed.

The angle is taken from the quaternions' parts in doubles, as
`2 * atan2(|v|, w)`. The angle between two 32-bit quaternions moved in steps of
about 0.03 cm/yr with one My between keyframes.

Between two keyframes a feature turns about one axis at one steady rate
(quaternion slerp), so one bar per span is exact, not an average. A plate after
its last keyframe stands still, so it reads zero there.

**Which span is read.** At a time inside a span, that span. At a time where two
spans meet, a keyframe, the older one: the motion that brought the feature
there, like GPlates' default of t + dt to t. So the rate at a keyframe gives
the move just made at it. Before GP-0136 it gave the younger span, and since a
coupling that runs to the present puts a motion time at 0 Ma, a feature that
follows another read the span from its newest keyframe to the present: the
parent's later motion, or nothing, whatever the drag at the keyframe did. At
the oldest motion time the feature has not moved yet and reads zero.

**While dragging.** The Move, Rotate and Pole tools write the keyframe at the
current time as they go, and the panel works its numbers out again at every
step, so the rate and the graph follow the drag before the release.

The rate is given in centimeters per year unless **Plate rate in** asks for a
distance per million years, which is written the way the status bar writes a
distance, so a slow plate reads `850 m/My`. 1 cm/yr is 10 km/My.

A turn back the way it came is as fast as the turn out, and the bar for that
span is as tall.

### Reference speeds

Resting the pointer on the graphs shows the plate speeds of
the worldbuilding tutorial the users follow, Worldbuilding Pasta's "An Apple
Pie From Scratch, Part V", section "Checking and Finalizing Plate Motion":

| Situation                   | cm/yr    |
| --------------------------- | -------- |
| Subducting ocean            | 8 to 20  |
| Recent subduction collision | 6        |
| Active margin continent     | 3        |
| Passive margin continent    | under 1  |

They are ranges to compare with, not targets, so nothing is drawn on the graph
for them and no speed turns a color.

The times the rate can change at are the feature's keyframe times: a feature
with three keyframes has two spans. A coupled feature's world motion can also
change where a coupling starts or ends, and wherever its parent's motion
changes while it follows it, so those times are added: both ends of every
coupling, and every such time of the parent that falls inside the span,
followed up the chain (`Kinematics.motion_times()`). A span may follow two
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
`get_kinematics`, and the golden scene `kinematics` is the reference for what it
draws. See [Testing](Testing.md).
