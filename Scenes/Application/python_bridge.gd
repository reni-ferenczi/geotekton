extends Node
class_name PythonBridge

# The Python interpreter the application talks to, and its half of the protocol.
#
# The interpreter runs as a separate process rather than inside the engine: a
# GDExtension binding would tie the interpreter to the Godot build, and a
# scripting language that can crash should not be able to take the window with
# it. What is lost is speed, which no scripting session here needs, and what is
# gained is that the interpreter can be replaced, upgraded or switched off
# without rebuilding anything.
#
# The interpreter listens and this side connects, so the server lives in
# src/middle_earth/bridge.py; that file describes the messages. One connection
# carries both directions: requests going out are numbered upwards from one,
# requests coming in are numbered downwards from minus one by the interpreter,
# and an output event carries no number at all.
#
# Nothing here blocks. A request is sent and awaited on a signal, so the frame
# keeps running while the interpreter thinks, which is what lets a script call
# back into the document in the middle of the line that started it.
#
# See Docs/Scripting.md.

# What the interpreter is asked to run. It puts its own folder on the import
# path, so the package does not have to be installed into the interpreter.
const ENTRY_POINT := "res://src/middle_earth/__main__.py"

# How long the interpreter has to come up and connect before it is given up on,
# and how often connecting is tried again in the meantime.
const CONNECT_TIMEOUT := 20.0
const RETRY_INTERVAL := 0.25

enum State {
	OFF,       # switched off with --no-python
	STARTING,  # the process is up, the connection is not
	READY,     # connected
	FAILED,    # it could not be started, or it went away
}

# A reply arrived for the request with this id. Awaited by request().
signal replied(id: int, reply: Dictionary)

# The interpreter wrote to stdout or stderr. The console panel shows it.
signal wrote(text: String, stream: String)

# The state or the reason changed, so whatever shows it can follow.
signal state_changed()

var app: Application

var state: State = State.OFF
# Why the interpreter is not running, empty while it is.
var reason: String = ""

var interpreter: String = ""
var pid: int = -1
var port: int = 0

var client := StreamPeerTCP.new()
var buffer: String = ""
var _next_id: int = 0
# The ids of requests still waiting, so a connection that dies can answer them
# all rather than leaving a script waiting for a frame that never comes.
var _waiting: Dictionary = {}
var _deadline: float = 0.0
var _next_attempt: float = 0.0


func _init(app_: Application) -> void:
	app = app_


### Starting and stopping


# Start the interpreter named in the preferences. Returns an empty string when
# the process started; the reason otherwise, which is also left in `reason` for
# the console panel to show. Nothing here pushes a warning: an interpreter that
# will not start is the person's business, not the log's.
func start() -> String:
	stop()
	interpreter = Config.get_python_interpreter()
	if not FileAccess.file_exists(interpreter):
		return _fail("No Python interpreter at %s. Set one in Preferences." % interpreter)

	port = _free_port()
	if port == 0:
		return _fail("No free port for the Python interpreter")

	var entry := ProjectSettings.globalize_path(ENTRY_POINT)
	pid = OS.create_process(interpreter, [entry, "--port=%d" % port])
	if pid <= 0:
		return _fail("Cannot start %s" % interpreter)

	return connect_to(port)


# Take up an interpreter that is already listening on a port, without starting
# one. Public because the tests put a stub there in place of an interpreter,
# which is how the protocol is checked without a Python installation.
func connect_to(port_: int) -> String:
	port = port_
	client = StreamPeerTCP.new()
	buffer = ""
	_deadline = _now() + CONNECT_TIMEOUT
	_next_attempt = 0.0
	_set_state(State.STARTING, "")
	return ""


# Ask the interpreter to end, and make sure it has. Answers every request still
# waiting, so nothing is left hanging on a process that is going away.
func stop() -> void:
	if state == State.READY:
		_send({"id": 0, "cmd": "quit"})
	if client.get_status() != StreamPeerTCP.STATUS_NONE:
		client.disconnect_from_host()
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	pid = -1
	_release_waiting("the interpreter was stopped")
	_set_state(State.OFF, reason)


# Switched off for this run, with no process and no console.
func disable(why: String) -> void:
	stop()
	_set_state(State.OFF, why)


func is_ready() -> bool:
	return state == State.READY


# Whatever the application is quitting for, the interpreter goes with it.
func _exit_tree() -> void:
	stop()


### Requests


# Send a request and wait for the reply. Always answers: a bridge that is not
# running, or one that goes away mid request, replies with ok false and a reason.
func request(cmd: String, params: Dictionary = {}) -> Dictionary:
	if state != State.READY:
		return {"ok": false, "error": reason if not reason.is_empty() else "Python is not running"}
	_next_id += 1
	var id := _next_id
	_waiting[id] = true
	var message := {"id": id, "cmd": cmd}
	message.merge(params)
	if not _send(message):
		_waiting.erase(id)
		return {"ok": false, "error": "the connection to the interpreter is gone"}

	# Every reply wakes this up, so the id is checked before it is taken; a
	# connection that dies answers what is still waiting, which is what ends
	# the loop when no real reply is coming.
	var answer := {"ok": false, "error": "the interpreter went away"}
	while _waiting.has(id):
		var answered: Array = await replied
		if int(answered[0]) == id:
			answer = answered[1]
			break
	return answer


### The frame


func _process(_delta: float) -> void:
	match state:
		State.STARTING:
			_advance_connection()
		State.READY:
			_pump()
		_:
			pass


func _advance_connection() -> void:
	if pid > 0 and not OS.is_process_running(pid):
		_fail("The Python interpreter stopped before it could be reached")
		return

	var status := client.get_status()
	if status == StreamPeerTCP.STATUS_NONE or status == StreamPeerTCP.STATUS_ERROR:
		if _now() >= _deadline:
			_fail("The Python interpreter did not answer on port %d" % port)
			return
		if _now() < _next_attempt:
			return
		_next_attempt = _now() + RETRY_INTERVAL
		client = StreamPeerTCP.new()
		client.connect_to_host("127.0.0.1", port)
		return

	client.poll()
	if client.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		client.set_no_delay(true)
		_set_state(State.READY, "")


func _pump() -> void:
	client.poll()
	if client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_fail("The Python interpreter closed the connection")
		return
	if pid > 0 and not OS.is_process_running(pid):
		_fail("The Python interpreter stopped")
		return

	var available := client.get_available_bytes()
	if available > 0:
		buffer += client.get_utf8_string(available)

	# Every whole line that has arrived, since a script that prints in a loop
	# sends many before the frame comes round again.
	while true:
		var end := buffer.find("\n")
		if end < 0:
			return
		var line := buffer.substr(0, end)
		buffer = buffer.substr(end + 1)
		_receive(line)
		# Handling a line may have found the connection gone.
		if state != State.READY:
			return


func _receive(line: String) -> void:
	var json := JSON.new()
	if json.parse(line) != OK or json.data is not Dictionary:
		push_warning("The Python interpreter sent something that is not a message: %s" % line)
		return
	var message: Dictionary = json.data

	if message.get("event", "") == "output":
		wrote.emit(str(message.get("text", "")), str(message.get("stream", "stdout")))
		return

	if message.has("cmd"):
		_answer(message)
		return

	var id := int(message.get("id", 0))
	if _waiting.erase(id):
		replied.emit(id, message)


# Answer one command and send the reply back. Started without awaiting it, so a
# command that takes frames does not hold up the line pump; the interpreter
# waits for one reply at a time, so the replies still go out in order.
func _answer(message: Dictionary) -> void:
	var reply: Dictionary = await _serve(message)
	reply["id"] = message.get("id")
	_send(reply)


### What a script may ask of the application
#
# One command per thing a script can do, each finishing the edit the way the
# panels do so the tree, the globe and the undo stack all follow. A refusal is
# an ok false reply, which the API turns back into an exception in the script.


func _serve(request_: Dictionary) -> Dictionary:
	var cmd := str(request_.get("cmd", ""))
	match cmd:
		"document":
			return {"ok": true, "document": app.document.to_json(),
				"name": app.document.display_name(), "path": app.document.path}

		"time":
			return {"ok": true, "time": app.document.current_time,
				"playing": app.timeline.playing}

		"set_time":
			app.document.set_time(float(request_.get("time", 0.0)))
			return {"ok": true}

		"play":
			app.timeline.play()
			return {"ok": true}

		"pause":
			app.timeline.pause()
			return {"ok": true}

		"selection":
			var selected := app.features.feature_tree.get_selected_node()
			return {"ok": true, "uuid": selected.uuid if selected != null else ""}

		"select":
			var node := _node(request_)
			if node == null:
				return _no_such(request_)
			app.features.feature_tree.select_node(node)
			return {"ok": true}

		"new":
			app.document.reset(Config.get_view_defaults())
			return {"ok": true}

		"open":
			var error := app.document.load_from_file(str(request_.get("path", "")))
			if not error.is_empty():
				return {"ok": false, "error": error}
			app.remember_file(str(request_.get("path", "")))
			return {"ok": true}

		"save":
			var path := str(request_.get("path", ""))
			if path.is_empty():
				path = app.document.path
			if path.is_empty():
				return {"ok": false, "error": "the document has no path, say where to save it"}
			var problem := app.document.save_to_file(path)
			if not problem.is_empty():
				return {"ok": false, "error": problem}
			app.remember_file(path)
			return {"ok": true}

		"undo":
			if not app.document.can_undo():
				return {"ok": false, "error": "there is nothing to undo"}
			app.document.undo()
			return {"ok": true}

		"redo":
			if not app.document.can_redo():
				return {"ok": false, "error": "there is nothing to redo"}
			app.document.redo()
			return {"ok": true}

		"add_group":
			var parent := _parent(request_)
			if parent == null:
				return {"ok": false, "error": "no group with uuid %s" % request_.get("parent", "")}
			var group := Feature.create_group(str(request_.get("title", "Group")))
			parent.children.append(group)
			app.document.record()
			_refresh()
			return {"ok": true, "uuid": group.uuid}

		"add_feature":
			return _add_feature(request_)

		"edit_feature":
			return _edit_feature(request_)

		"delete_feature":
			var doomed := _node(request_)
			if doomed == null:
				return _no_such(request_)
			if doomed.is_root:
				return {"ok": false, "error": "the root group cannot be deleted"}
			app.features.delete_node(doomed)
			app.refresh_geometry()
			return {"ok": true}

		"set_keyframe":
			var moved := _node(request_)
			if moved == null:
				return _no_such(request_)
			var degrees: Array = request_.get("rotation", [0.0, 0.0, 0.0])
			var problem := app.document.set_keyframe(moved, float(request_.get("time", 0.0)),
				Vector3(degrees[0], degrees[1], degrees[2]))
			if not problem.is_empty():
				return {"ok": false, "error": problem}
			_refresh()
			return {"ok": true}

		"delete_keyframe":
			return _delete_keyframe(request_)

		"export_image":
			# A picture of the map at the current age; see
			# Docs/Shell.md#exporting-a-picture-of-the-map.
			var width := int(request_.get("width", 0))
			var size := app.export_size(width)
			var problem: String = await app.export_image(
				str(request_.get("path", "")), width)
			if not problem.is_empty():
				return {"ok": false, "error": problem}
			return {"ok": true, "size": [size.x, size.y]}

		"export_video":
			# The animation as a video; see Docs/Shell.md#exporting-a-video-of-
			# the-animation. Whatever the options leave out is the animation's
			# own setting.
			var answer: Dictionary = await app.export_video(
				str(request_.get("path", "")), request_.get("options", {}))
			if not str(answer.get("error", "")).is_empty():
				return {"ok": false, "error": answer["error"]}
			return {"ok": true, "frames": answer["frames"],
				"encoded": answer["encoded"], "path": answer["path"],
				"folder": answer["folder"]}

	return {"ok": false, "error": "unknown command: %s" % cmd}


func _add_feature(request_: Dictionary) -> Dictionary:
	var parent := _parent(request_)
	if parent == null:
		return {"ok": false, "error": "no group with uuid %s" % request_.get("parent", "")}

	var kind_name := str(request_.get("geometry_kind", "polygon"))
	if not Feature.KIND_VALUES.has(kind_name):
		return {"ok": false, "error": "no geometry kind called %s" % kind_name}

	var type_id := str(request_.get("feature_type", FeatureType.NONE))
	if not type_id.is_empty() and not FeatureType.CATALOG.has(type_id):
		return {"ok": false, "error": "no feature type called %s" % type_id}
	if not FeatureType.allows(type_id, kind_name):
		return {"ok": false, "error": "a %s cannot be a %s" % [type_id, kind_name]}

	var feature := Feature.create_feature(str(request_.get("title", "Feature")),
		FeatureType.color(type_id))
	feature.feature_type = type_id
	feature.geometry_kind = Feature.KIND_VALUES[kind_name]
	feature.rings = _rings(request_.get("rings", []))
	for ring in feature.rings:
		for vertex in ring:
			var problem := Document.check_coordinates(vertex)
			if not problem.is_empty():
				return {"ok": false, "error": problem}
	feature.rebuild_triangles()
	# Polar circles are built from their parameters, whatever rings came along.
	if feature.is_polar_circles():
		feature.rebuild_polar_circles()

	parent.children.append(feature)
	app.document.record()
	_refresh()
	return {"ok": true, "uuid": feature.uuid}


func _edit_feature(request_: Dictionary) -> Dictionary:
	var feature := _node(request_)
	if feature == null:
		return _no_such(request_)
	var fields: Dictionary = request_.get("fields", {})
	for name in fields:
		var value: Variant = fields[name]
		match str(name):
			"title":
				app.document.rename(feature, str(value))
			"enabled":
				app.document.set_enabled(feature, bool(value))
			"color":
				var c: Array = value
				app.document.set_color(feature, Color(c[0], c[1], c[2], c[3] if c.size() > 3 else 1.0))
			"feature_type":
				var problem := app.document.set_feature_type(feature, str(value))
				if not problem.is_empty():
					return {"ok": false, "error": problem}
			"time_range":
				var span: Array = value
				var refused := app.document.set_time_range(feature, Vector2i(span[0], span[1]))
				if not refused.is_empty():
					return {"ok": false, "error": refused}
			"rings":
				if feature.is_group:
					return {"ok": false, "error": "a group has no geometry"}
				if feature.is_polar_circles():
					return {"ok": false, "error":
						"polar circles are built from their axis and radius"}
				var rings := _rings(value)
				for ring in rings:
					for vertex in ring:
						var bad := Document.check_coordinates(vertex)
						if not bad.is_empty():
							return {"ok": false, "error": bad}
				feature.rings = rings
				feature.rebuild_triangles()
				app.document.record()
			_:
				return {"ok": false, "error": "a feature has no %s" % name}
	_refresh()
	return {"ok": true}


func _delete_keyframe(request_: Dictionary) -> Dictionary:
	var feature := _node(request_)
	if feature == null:
		return _no_such(request_)
	var time := float(request_.get("time", 0.0))
	for index in feature.keyframes.size():
		if is_equal_approx(feature.keyframes[index].time, time):
			var problem := app.document.remove_keyframe(feature, index)
			if not problem.is_empty():
				return {"ok": false, "error": problem}
			_refresh()
			return {"ok": true}
	return {"ok": false, "error": "%s has no keyframe at %s" % [feature.title, time]}


### Helpers


func _node(request_: Dictionary) -> Feature:
	return app.document.root.get_node_by_uuid(str(request_.get("uuid", "")))


# The group a new node goes into: the one named, or the root when none is.
func _parent(request_: Dictionary) -> Feature:
	var uuid := str(request_.get("parent", ""))
	if uuid.is_empty():
		return app.document.root
	var parent := app.document.root.get_node_by_uuid(uuid)
	return parent if parent != null and parent.is_group else null


func _no_such(request_: Dictionary) -> Dictionary:
	return {"ok": false, "error": "no feature with uuid %s" % request_.get("uuid", "")}


static func _rings(data: Variant) -> Array[PackedVector2Array]:
	var rings: Array[PackedVector2Array] = []
	for ring_data in data:
		var ring := PackedVector2Array()
		for vertex in ring_data:
			ring.append(Vector2(vertex[0], vertex[1]))
		rings.append(ring)
	return rings


# What the panels do after an edit, so a script's change reaches the tree, the
# globe, the timeline and the graphs the same way a person's does.
#
# The undo version is not recorded here. Every Document setter records one of
# its own, and a second would cost two steps of undo for one edit; only the two
# commands that put a node in the tree themselves record, just above.
func _refresh() -> void:
	app._on_properties_edited()


### State


func _send(message: Dictionary) -> bool:
	if client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return false
	return client.put_data((JSON.stringify(message) + "\n").to_utf8_buffer()) == OK


func _fail(why: String) -> String:
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	pid = -1
	_release_waiting(why)
	_set_state(State.FAILED, why)
	return why


func _release_waiting(why: String) -> void:
	var ids: Array = _waiting.keys()
	_waiting.clear()
	for id in ids:
		replied.emit(int(id), {"ok": false, "error": why})


func _set_state(new_state: State, why: String) -> void:
	state = new_state
	reason = why
	state_changed.emit()


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# A port nothing is listening on, found by listening on one and letting go.
static func _free_port() -> int:
	var probe := TCPServer.new()
	if probe.listen(0, "127.0.0.1") != OK:
		return 0
	var found := probe.get_local_port()
	probe.stop()
	return found
