class_name Keyframe
extends RefCounted

# One step of a feature's motion: a time, and the rotation the feature has then.
# A feature keeps a list of these sorted by time; between two of them it turns
# along the shortest path on the sphere of rotations, and outside the first and
# the last it holds the nearest one rather than extrapolating. See Docs/Time.md.
#
# Time is an age in millions of years before present, so a larger number is
# older. The list is sorted ascending, which puts the youngest keyframe first.
#
# The time is a plain float, which GDScript keeps at double precision: ages run
# to thousands of millions of years and a keyframe has to land back on the exact
# time it was written at. The rotation is three degrees in the same YXZ
# convention the rest of the application uses, and is 32-bit like every packed
# Godot type, which is far finer than a rotation anyone can pick with a mouse.

var time: float
var rotation: Vector3


static func create(time_: float, rotation_: Vector3) -> Keyframe:
	var keyframe := Keyframe.new()
	keyframe.time = time_
	keyframe.rotation = rotation_
	return keyframe


func clone() -> Keyframe:
	return Keyframe.create(time, rotation)


### Interpolation


# The rotation the list describes at the given time: that keyframe's own
# rotation at a keyframe time, the blend of the two around it in between, and
# the nearer end beyond either end. An empty list does not rotate at all.
static func interpolate(keyframes: Array[Keyframe], time: float) -> Vector3:
	if keyframes.is_empty():
		return Vector3.ZERO
	if time <= keyframes[0].time:
		return keyframes[0].rotation
	var last: Keyframe = keyframes[keyframes.size() - 1]
	if time >= last.time:
		return last.rotation

	# The two keyframes the time falls between. Each interpolation starts from
	# them rather than from the frame before it, so a long animation cannot
	# drift away from what the keyframes say.
	for i in range(1, keyframes.size()):
		var after: Keyframe = keyframes[i]
		if after.time < time:
			continue
		var before: Keyframe = keyframes[i - 1]
		var span := after.time - before.time
		if span <= 0.0:
			return after.rotation
		return blend(before.rotation, after.rotation, (time - before.time) / span)
	return last.rotation


# The rotation a fraction of the way from one to another, along the shortest
# path on the sphere of rotations. Interpolating the three angles instead would
# take the long way round wherever they wrap, and would slow down and speed up
# through the turn.
static func blend(from: Vector3, to: Vector3, weight: float) -> Vector3:
	var a := Quaternion(Feature.build_rotation_basis(from))
	var b := Quaternion(Feature.build_rotation_basis(to))
	return Feature.decompose_rotation_degrees(Basis(a.slerp(b, weight)))


### Editing the list


# Where the keyframe at that time sits, or -1 when there is none. Times are
# compared approximately, so a time typed back in reaches the keyframe it names.
static func index_at(keyframes: Array[Keyframe], time: float) -> int:
	for i in keyframes.size():
		if is_equal_approx(keyframes[i].time, time):
			return i
	return -1


# Give the list a rotation at that time: replacing the keyframe already there,
# or adding one in the place that keeps the list sorted.
static func upsert(keyframes: Array[Keyframe], time: float, rotation: Vector3) -> void:
	for i in keyframes.size():
		if is_equal_approx(keyframes[i].time, time):
			keyframes[i].rotation = rotation
			return
		if keyframes[i].time > time:
			keyframes.insert(i, Keyframe.create(time, rotation))
			return
	keyframes.append(Keyframe.create(time, rotation))


static func clone_list(keyframes: Array[Keyframe]) -> Array[Keyframe]:
	var result: Array[Keyframe] = []
	for keyframe in keyframes:
		result.append(keyframe.clone())
	return result


### JSON serialization


func to_json() -> Variant:
	return {"time": time, "rotation": [rotation.x, rotation.y, rotation.z]}


static func from_json(data: Variant) -> Keyframe:
	var r: Array = data.get("rotation", [0, 0, 0])
	return Keyframe.create(float(data.get("time", 0.0)), Vector3(r[0], r[1], r[2]))


static func list_to_json(keyframes: Array[Keyframe]) -> Array:
	var result: Array = []
	for keyframe in keyframes:
		result.append(keyframe.to_json())
	return result


# The list a file holds, put back in time order. A file written by hand can
# carry them in any order, and everything downstream expects them sorted.
static func list_from_json(data: Array) -> Array[Keyframe]:
	var result: Array[Keyframe] = []
	for keyframe_data in data:
		result.append(Keyframe.from_json(keyframe_data))
	result.sort_custom(func(a: Keyframe, b: Keyframe) -> bool: return a.time < b.time)
	return result
