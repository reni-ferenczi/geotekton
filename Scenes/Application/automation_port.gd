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

# The last file dialog the application asked for, consumed by get_file_dialog.
var last_file_dialog: Variant = null
# The path the next file dialog answers with, empty when it is cancelled.
var file_dialog_reply: String = ""
var file_dialog_expected: bool = false

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
	# Answer file dialogs from the script instead of opening a native one.
	Application.file_dialog_hook = _on_file_dialog
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
			var error := app.document.load_from_file(str(request.get("path", "")))
			if not error.is_empty():
				return {"ok": false, "error": error}
			await _frames(2)
			return {"ok": true}

		"get_document":
			return {"ok": true, "document": {
				"path": app.document.path,
				"name": app.document.display_name(),
				"dirty": app.document.is_dirty(),
				"title": app.get_window().title,
				"can_undo": app.document.can_undo(),
				"can_redo": app.document.can_redo(),
			}}

		"menu":
			var item: Array = _menu_item(str(request.get("item", "")))
			if item.is_empty():
				return {"ok": false, "error": "unknown menu item: %s" % request.get("item", "")}
			(item[0] as PopupMenu).id_pressed.emit(int(item[1]))
			await _frames(2)
			return {"ok": true}

		"toolbar":
			var buttons := app.features.get_node_or_null("PanelContainer/Buttons")
			var button := buttons.get_node_or_null(str(request.get("button", ""))) if buttons != null else null
			if button is not Button:
				return {"ok": false, "error": "no toolbar button called %s" % request.get("button", "")}
			if (button as Button).disabled:
				return {"ok": false, "error": "the %s button is disabled" % request.get("button", "")}
			(button as Button).pressed.emit()
			await _frames(2)
			return {"ok": true}

		"get_recent":
			return {"ok": true, "recent": Config.get_recent_files()}

		"open_recent":
			app._on_recent_menu_id_pressed(int(request.get("index", 0)))
			await _frames(2)
			return {"ok": true}

		"clear_recent":
			app._on_recent_menu_id_pressed(Application.CLEAR_RECENT_ID)
			await _frames(2)
			return {"ok": true}

		"get_panels":
			return {"ok": true, "panels": {
				"features": app.features.visible,
				"properties": app.properties.visible,
				"timeline": app.timeline.visible,
				"status_bar": app.status_bar.visible,
			}}

		"get_dialog":
			var dialog := _visible_dialog()
			if dialog == null:
				return {"ok": true, "dialog": null}
			return {"ok": true, "dialog": {
				"name": str(dialog.name),
				"title": dialog.title,
				"text": dialog.dialog_text,
				"buttons": _dialog_buttons(dialog),
			}}

		"dialog":
			var open_dialog := _visible_dialog()
			if open_dialog == null:
				return {"ok": false, "error": "no dialog is open"}
			var label := str(request.get("button", ""))
			if not _press_dialog_button(open_dialog, label):
				return {"ok": false, "error": "no button labelled %s" % label}
			await _frames(2)
			return {"ok": true}

		"expect_file_dialog":
			file_dialog_reply = str(request.get("path", ""))
			file_dialog_expected = true
			return {"ok": true}

		"get_file_dialog":
			var asked: Variant = last_file_dialog
			last_file_dialog = null
			return {"ok": true, "file_dialog": asked}

		"get_features":
			var list: Array = []
			_collect_features(app.document.root, 0, list)
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
	return app.timeline


# The menu and item id behind a command name, or an empty array when unknown.
func _menu_item(name: String) -> Array:
	match name:
		"new": return [app.file_menu, Application.FileItem.NEW]
		"open": return [app.file_menu, Application.FileItem.OPEN]
		"save": return [app.file_menu, Application.FileItem.SAVE]
		"save_as": return [app.file_menu, Application.FileItem.SAVE_AS]
		"preferences": return [app.file_menu, Application.FileItem.PREFERENCES]
		"quit": return [app.file_menu, Application.FileItem.QUIT]
		"features": return [app.view_menu, Application.ViewItem.FEATURES]
		"properties": return [app.view_menu, Application.ViewItem.PROPERTIES]
		"timeline": return [app.view_menu, Application.ViewItem.TIMELINE]
		"status_bar": return [app.view_menu, Application.ViewItem.STATUS_BAR]
		"full_screen": return [app.view_menu, Application.ViewItem.FULL_SCREEN]
	return []


func _visible_dialog() -> AcceptDialog:
	for child in app.get_children():
		if child is AcceptDialog and child.visible:
			return child
	return null


# Every button of a dialog, the built in ones and those added to it.
func _dialog_buttons(dialog: AcceptDialog) -> Array:
	var labels: Array = []
	for child in dialog.get_ok_button().get_parent().get_children():
		if child is Button:
			labels.append(child.text)
	return labels


func _press_dialog_button(dialog: AcceptDialog, label: String) -> bool:
	for child in dialog.get_ok_button().get_parent().get_children():
		if child is Button and child.text.to_lower() == label.to_lower():
			child.pressed.emit()
			return true
	return false


# Stands in for the native file dialog while a script is driving the
# application: it records the request and answers it with the expected path.
func _on_file_dialog(mode: int, title: String, on_path: Callable) -> void:
	last_file_dialog = {"mode": mode, "title": title}
	if not file_dialog_expected:
		return
	file_dialog_expected = false
	var path := file_dialog_reply
	file_dialog_reply = ""
	if not path.is_empty():
		on_path.call(path)


func _collect_features(node: Feature, depth: int, list: Array) -> void:
	list.append({"pnid": node.pnid, "title": node.title, "is_group": node.is_group, "depth": depth})
	for child in node.children:
		_collect_features(child, depth + 1, list)


func _find_feature(request: Dictionary) -> Feature:
	var root := app.document.root
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
