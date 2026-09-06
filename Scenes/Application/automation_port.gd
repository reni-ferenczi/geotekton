extends Node
class_name AutomationPort

# Test automation port. Enabled only by the user argument --automation-port=<port>.
# Listens on the loopback interface, accepts one client and exchanges
# newline delimited JSON: one request object per line, one response object per line.
# Requests are handled one at a time, in order.

const BUTTONS := {
	"left": MOUSE_BUTTON_LEFT,
	"right": MOUSE_BUTTON_RIGHT,
	"middle": MOUSE_BUTTON_MIDDLE,
}

var app: Application
var port: int

var server := TCPServer.new()
var client: StreamPeerTCP = null
var buffer: String = ""
var busy: bool = false
var quitting: bool = false
var mouse_position := Vector2.ZERO


func _init(app_: Application, port_: int) -> void:
	app = app_
	port = port_


func _ready() -> void:
	var error := server.listen(port, "127.0.0.1")
	if error != OK:
		push_error("Automation port failed to listen on 127.0.0.1:%d (error %d)" % [port, error])
		return
	# Keep injected motion events discrete instead of merging them per frame.
	Input.use_accumulated_input = false
	print("Automation port listening on 127.0.0.1:%d" % port)


func _process(_delta: float) -> void:
	if client == null:
		if server.is_connection_available():
			client = server.take_connection()
			client.set_no_delay(true)
		return

	client.poll()
	if client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		client = null
		buffer = ""
		busy = false
		return

	if busy:
		return

	var available := client.get_available_bytes()
	if available > 0:
		buffer += client.get_utf8_string(available)

	var end := buffer.find("\n")
	if end < 0:
		return

	var line := buffer.substr(0, end)
	buffer = buffer.substr(end + 1)
	busy = true
	_handle(line)


func _handle(line: String) -> void:
	var response: Dictionary
	var json := JSON.new()
	if json.parse(line) != OK:
		response = {"ok": false, "error": "invalid JSON: %s" % json.get_error_message()}
	elif json.data is not Dictionary:
		response = {"ok": false, "error": "request must be a JSON object"}
	else:
		response = await _dispatch(json.data)

	if client != null:
		client.put_data((JSON.stringify(response) + "\n").to_utf8_buffer())
	busy = false

	if quitting:
		await get_tree().process_frame
		get_tree().quit()


func _dispatch(request: Dictionary) -> Dictionary:
	match request.get("cmd", ""):
		"ping":
			return {"ok": true, "version": Application.VERSION}

		"load":
			app.features._load_from_file(str(request.get("path", "")))
			app.refresh_cratons()
			await _frames(2)
			return {"ok": true}

		"get_features":
			var list: Array = []
			_collect_features(app.features.root, 0, list)
			return {"ok": true, "features": list}

		"select":
			var feature := _find_feature(request)
			if feature == null:
				return {"ok": false, "error": "feature not found"}
			app.features.feature_tree.select_node(feature)
			await _frames(2)
			return {"ok": true}

		"get_selected":
			return {"ok": true, "feature": _feature_to_json(app.features.feature_tree.get_selected_node())}

		"get_time":
			return {"ok": true, "time": _timeline().timestamp_slider.value}

		"set_time":
			_timeline().timestamp_slider.value = float(request.get("time", 0.0))
			await _frames(2)
			return {"ok": true}

		"get_view":
			var size := DisplayServer.window_get_size()
			return {
				"ok": true,
				"lat": app.planet_view.planet.lat,
				"lon": app.planet_view.planet.lon,
				"angle": app.planet_view.planet.angle,
				"fov": app.planet_view.camera.fov,
				"show_map": app.planet_view.planet.show_map,
				"window_size": [size.x, size.y],
			}

		"set_view":
			var planet := app.planet_view.planet
			if request.has("lat"):
				planet.lat = float(request["lat"])
			if request.has("lon"):
				planet.lon = float(request["lon"])
			if request.has("angle"):
				planet.angle = float(request["angle"])
			if request.has("show_map"):
				planet.show_map = bool(request["show_map"])
			if request.has("fov"):
				app.planet_view.camera.fov = float(request["fov"])
			await _frames(2)
			return {"ok": true}

		"mouse_move":
			await _move_mouse(_point(request))
			return {"ok": true}

		"click":
			return await _click(request)

		"key":
			var keycode := OS.find_keycode_from_string(str(request.get("key", "")))
			if keycode == KEY_NONE:
				return {"ok": false, "error": "unknown key: %s" % request.get("key", "")}
			var ctrl := bool(request.get("ctrl", false))
			var shift := bool(request.get("shift", false))
			_send_key(keycode, ctrl, shift, true)
			_send_key(keycode, ctrl, shift, false)
			await _frames(2)
			return {"ok": true}

		"latlon_to_screen":
			var screen: Variant = app.planet_view.latlon_to_screen(
				float(request.get("lat", 0.0)), float(request.get("lon", 0.0)))
			return {"ok": true, "screen": null if screen == null else [screen.x, screen.y]}

		"screen_to_latlon":
			var latlon: Variant = app.planet_view.screen_to_latlon(_point(request))
			return {"ok": true, "latlon": null if latlon == null else [latlon.x, latlon.y]}

		"get_pixel":
			var point := _point(request)
			var image := await _capture()
			var color := image.get_pixel(int(point.x), int(point.y))
			return {"ok": true, "color": [color.r, color.g, color.b, color.a]}

		"screenshot":
			var path := str(request.get("path", ""))
			var image := await _capture()
			var error := image.save_png(path)
			if error != OK:
				return {"ok": false, "error": "failed to save %s (error %d)" % [path, error]}
			return {"ok": true, "path": path, "size": [image.get_width(), image.get_height()]}

		"quit":
			quitting = true
			return {"ok": true}

	return {"ok": false, "error": "unknown command: %s" % request.get("cmd", "")}


### Helpers


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _physics_frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _point(request: Dictionary) -> Vector2:
	return Vector2(float(request.get("x", 0.0)), float(request.get("y", 0.0)))


func _capture() -> Image:
	await RenderingServer.frame_post_draw
	return app.get_viewport().get_texture().get_image()


func _timeline() -> Timeline:
	return app.get_node("LeftSplitter/RightSplitter/Center/Timeline") as Timeline


func _collect_features(node: Feature, depth: int, list: Array) -> void:
	list.append({"pnid": node.pnid, "title": node.title, "is_group": node.is_group, "depth": depth})
	for child in node.children:
		_collect_features(child, depth + 1, list)


func _find_feature(request: Dictionary) -> Feature:
	var root := app.features.root
	if request.has("pnid"):
		var pnid := int(request["pnid"])
		return root if pnid == -1 else root.get_node_by_pnid(pnid)
	if request.has("title"):
		var title: Variant = request["title"]
		return root if title == null else _find_by_title(root, str(title))
	return null


func _find_by_title(node: Feature, title: String) -> Feature:
	if node.title == title:
		return node
	for child in node.children:
		var found := _find_by_title(child, title)
		if found != null:
			return found
	return null


func _feature_to_json(feature: Feature) -> Variant:
	if feature == null:
		return null
	return {
		"pnid": feature.pnid,
		"title": feature.title,
		"is_group": feature.is_group,
		"color": [feature.color.r, feature.color.g, feature.color.b, feature.color.a],
		"rotation": [feature.rotation_angles.x, feature.rotation_angles.y, feature.rotation_angles.z],
		"vertices": _vertices_to_json(feature.vertices),
		"world_vertices": _vertices_to_json(Feature.apply_rotation(feature.vertices, feature.rotation_angles)),
	}


func _vertices_to_json(vertices: Array[Vector2]) -> Array:
	var list: Array = []
	for v in vertices:
		list.append([v.x, v.y])
	return list


func _move_mouse(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.relative = position - mouse_position
	mouse_position = position
	Input.parse_input_event(event)
	await _physics_frames(2)


func _click(request: Dictionary) -> Dictionary:
	var button_name := str(request.get("button", "left"))
	if not BUTTONS.has(button_name):
		return {"ok": false, "error": "unknown button: %s" % button_name}
	var button: int = BUTTONS[button_name]
	var ctrl := bool(request.get("ctrl", false))

	await _move_mouse(_point(request))
	if ctrl:
		_send_key(KEY_CTRL, true, false, true)

	_send_button(button, ctrl, true)
	await _physics_frames(2)
	_send_button(button, ctrl, false)
	await _physics_frames(2)
	# Selection on click is deferred, so give it process frames to land.
	await _frames(2)

	if ctrl:
		_send_key(KEY_CTRL, false, false, false)
	return {"ok": true}


func _send_button(button: int, ctrl: bool, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = mouse_position
	event.global_position = mouse_position
	event.button_index = button
	event.button_mask = (1 << (button - 1)) if pressed else 0
	event.ctrl_pressed = ctrl
	event.pressed = pressed
	Input.parse_input_event(event)


func _send_key(keycode: int, ctrl: bool, shift: bool, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.ctrl_pressed = ctrl
	event.shift_pressed = shift
	event.pressed = pressed
	Input.parse_input_event(event)
