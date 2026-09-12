extends Node
class_name AutomationPort

# Test automation port. Enabled only by the user argument --automation-port=<port>.
# Listens on the loopback interface, accepts one client and exchanges
# newline delimited JSON: one request object per line, one response object per line.
# Requests are handled one at a time, in order.

# The tool names a scripted run uses, matching the toolbar buttons.
const TOOL_NAMES := {
	Application.Tool.MOVE: "move",
	Application.Tool.DRAW: "draw",
	Application.Tool.VERTEX: "vertex",
	Application.Tool.MEASURE: "measure",
	Application.Tool.CIRCLE: "circle",
	Application.Tool.TOPOLOGY: "topology",
	Application.Tool.LIGHT: "light",
}

# The wheel is here so a run can zoom the way a person does, with the pointer
# over the view; a wheel notch is a press and a release like any other button.
const BUTTONS := {
	"left": MOUSE_BUTTON_LEFT,
	"right": MOUSE_BUTTON_RIGHT,
	"middle": MOUSE_BUTTON_MIDDLE,
	"wheel_up": MOUSE_BUTTON_WHEEL_UP,
	"wheel_down": MOUSE_BUTTON_WHEEL_DOWN,
}

var app: Application
var port: int

# The last file dialog the application asked for, consumed by get_file_dialog.
var last_file_dialog: Variant = null
# The path the next file dialog answers with, empty when it is cancelled.
var file_dialog_reply: PackedStringArray = PackedStringArray()
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
				# How many versions are applied, so a run can check that an
				# edit recorded exactly one.
				"undo_depth": app.document.applied,
			}}

		"menu":
			var item: Array = _menu_item(str(request.get("item", "")))
			if item.is_empty():
				return {"ok": false, "error": "unknown menu item: %s" % request.get("item", "")}
			var menu := item[0] as PopupMenu
			if menu.is_item_disabled(menu.get_item_index(int(item[1]))):
				return {"ok": false, "error": "the %s menu item is disabled" % request.get("item", "")}
			menu.id_pressed.emit(int(item[1]))
			await _frames(2)
			return {"ok": true}

		"get_context_menu":
			var globe_menu := app.globe_menu
			return {"ok": true, "context_menu": {
				"visible": globe_menu.visible,
				"items": _menu_items(globe_menu),
			}}

		"context_menu":
			var label := str(request.get("item", ""))
			var index := _menu_index(app.globe_menu, label)
			if index < 0:
				return {"ok": false, "error": "the globe menu has no %s item" % label}
			if app.globe_menu.is_item_disabled(index):
				return {"ok": false, "error": "the %s item is disabled" % label}
			app.globe_menu.hide()
			app.globe_menu.id_pressed.emit(app.globe_menu.get_item_id(index))
			await _frames(2)
			return {"ok": true}

		"set_clipboard":
			# The feature tree toolbar greys its Paste button out by what the
			# clipboard holds, so a run that wants the same window every time
			# has to say what that is.
			DisplayServer.clipboard_set(str(request.get("text", "")))
			app.features.update_button_availability()
			await _frames(2)
			app.features.update_button_availability()
			await _frames(2)
			return {"ok": true}

		"get_properties":
			return {"ok": true, "properties": app.properties.to_json()}

		"set_property":
			var error := app.properties.set_field(
				str(request.get("field", "")), request.get("value"))
			if not error.is_empty():
				return {"ok": false, "error": error}
			await _frames(2)
			return {"ok": true}

		"properties":
			if request.has("part"):
				app.properties.select_vertex(int(request["part"]), int(request.get("index", 0)))
			var button_name := str(request.get("button", ""))
			var vertex_button: Button = {
				"Add": app.properties.add_button,
				"Remove": app.properties.remove_button,
			}.get(button_name)
			if vertex_button == null:
				return {"ok": false, "error": "no properties button called %s" % button_name}
			if vertex_button.disabled:
				return {"ok": false, "error": "the %s button is disabled" % button_name}
			vertex_button.pressed.emit()
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
				"kinematics": app.kinematics.visible,
				"console": app.console.visible,
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
			file_dialog_reply = PackedStringArray()
			for path in request.get("paths", [request.get("path", "")]):
				if not str(path).is_empty():
					file_dialog_reply.append(str(path))
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
			return {"ok": true, "time": app.document.current_time}

		"set_time":
			app.document.set_time(float(request.get("time", 0.0)))
			await _frames(2)
			return {"ok": true}

		"get_performance":
			# What one frame is costing, and how much there is to draw. The
			# engine's own counters: the editor profiler cannot be reached from
			# a scripted run, and these are the numbers it shows.
			return {"ok": true, "performance": {
				"fps": Engine.get_frames_per_second(),
				"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
				"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
				"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				"primitives": app.geometry.primitives.size(),
				"features": app.geometry.features.size(),
				"playing": _timeline().playing,
			}}

		"benchmark_hit_test":
			# What the bounding cap is worth, measured on the document that is
			# loaded. The same points are hit tested twice: once against the
			# caps the geometry was built with, and once against caps widened
			# to the whole sphere, which is what the hit test faced before
			# there were any. Widening a cap is not a switch put in for the
			# benchmark: a feature spanning more than a hemisphere gets exactly
			# that cap, and the loop then behaves as it always did.
			return _benchmark_hit_test(int(request.get("samples", 2000)))

		"get_timeline":
			return {"ok": true, "timeline": _timeline().to_json()}

		"get_kinematics":
			return {"ok": true, "kinematics": app.kinematics.to_json()}

		"timeline":
			var error := _timeline().press(str(request.get("button", "")))
			if not error.is_empty():
				return {"ok": false, "error": error}
			await _frames(2)
			return {"ok": true}

		"set_skip":
			_timeline().skip_spin.value = float(request.get("skip", Config.DEFAULT_SKIP))
			await _frames(2)
			return {"ok": true, "skip": _timeline().skip()}

		"set_animation":
			# The animation dialog without the dialog: whatever the request
			# names is changed, the rest stays as it was.
			var settings := AnimationSettings.from_json(
				_timeline().animation.to_json().merged(request.get("animation", {}), true))
			var problem := settings.problem()
			if not problem.is_empty():
				return {"ok": false, "error": problem}
			_timeline().set_animation(settings)
			await _frames(2)
			return {"ok": true}

		"sections":
			# The section table of a line topology, driven the way the keyframe
			# table is: pick a row, then press one of its buttons.
			if request.has("index"):
				app.properties.select_section(int(request["index"]))
			var section_button: Button = {
				"Reverse": app.properties.reverse_button,
				"Remove": app.properties.remove_section_button,
			}.get(str(request.get("button", "")))
			if section_button == null:
				return {"ok": false, "error":
					"no section button called %s" % request.get("button", "")}
			if section_button.disabled:
				return {"ok": false, "error":
					"the %s button is disabled" % request.get("button", "")}
			section_button.pressed.emit()
			await _frames(2)
			return {"ok": true}

		"keyframes":
			if request.has("index"):
				app.properties.select_keyframe(int(request["index"]))
			var key_button: Button = {
				"Key": app.properties.key_button,
				"Delete": app.properties.delete_key_button,
			}.get(str(request.get("button", "")))
			if key_button == null:
				return {"ok": false, "error": "no keyframe button called %s" % request.get("button", "")}
			if key_button.disabled:
				return {"ok": false, "error": "the %s button is disabled" % request.get("button", "")}
			key_button.pressed.emit()
			await _frames(2)
			return {"ok": true}

		"view":
			# Picking the projection goes through the selector rather than the
			# planet, so what is tested is the toolbar a person uses: "globe"
			# for the globe, or the number of a MapProjection.Kind.
			if request.has("projection"):
				var wanted: int = Application.GLOBE_PROJECTION_ID \
					if str(request["projection"]) == "globe" else int(request["projection"])
				var item := app.projection_selector.get_item_index(wanted)
				if item < 0:
					return {"ok": false, "error": "the selector has no projection %s"
						% request["projection"]}
				app.projection_selector.select(item)
				app.projection_selector.item_selected.emit(item)
				await _frames(2)
				return {"ok": true}

			var view_button: Button = {
				"zoom_in": app.zoom_in_button,
				"zoom_out": app.zoom_out_button,
				"zoom_reset": app.zoom_reset_button,
				"rotate_clockwise": app.rotate_clockwise_button,
				"rotate_anticlockwise": app.rotate_anticlockwise_button,
				"camera_reset": app.camera_reset_button,
			}.get(str(request.get("button", "")))
			if view_button == null:
				return {"ok": false, "error": "no view button called %s" % request.get("button", "")}
			view_button.pressed.emit()
			await _frames(2)
			return {"ok": true}

		"get_view":
			var size := DisplayServer.window_get_size()
			return {
				"ok": true,
				"toolbar": {
					"projection": app.projection_selector.get_item_text(
						app.projection_selector.selected),
					"zoom": app.zoom_spin.value,
					"lat": app.camera_latitude_spin.value,
					"lon": app.camera_longitude_spin.value,
				},
				"lat": app.planet_view.planet.lat,
				"lon": app.planet_view.planet.lon,
				"angle": app.planet_view.planet.angle,
				"zoom": app.planet_view.zoom,
				"fov": app.planet_view.camera.fov,
				"show_map": app.planet_view.planet.show_map,
				"projection": int(app.planet_view.planet.projection),
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
			if request.has("projection"):
				var kind := int(request["projection"])
				if kind < 0 or kind >= MapProjection.NAMES.size():
					return {"ok": false, "error": "no projection numbered %d" % kind}
				planet.projection = kind as MapProjection.Kind
			if request.has("zoom"):
				app.planet_view.set_zoom(float(request["zoom"]))
			await _frames(2)
			return {"ok": true}

		"mouse_move":
			await _move_mouse(_point(request))
			return {"ok": true}

		"click":
			return await _click(request)

		"press":
			return await _button(request, true)

		"release":
			return await _button(request, false)

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

		"get_tool":
			var allowed: Array = []
			for index in app.kind_selector.item_count:
				if not app.kind_selector.is_item_disabled(index):
					allowed.append(Feature.KIND_NAMES[app.kind_selector.get_item_id(index)])
			return {"ok": true,
				"tool": TOOL_NAMES[app.active_tool],
				"kind": Feature.KIND_NAMES[app.drawing_kind()],
				"kind_locked": app.kind_selector.disabled,
				"allowed_kinds": allowed,
				"drawing_vertices": app.outline_vertices.size(),
				"vertex_enabled": not app.vertex_button.disabled,
				"snapping": app.snapping(),
				"selected_vertex": _vertex_to_json(app.selected_vertex),
				"hovered_vertex": _vertex_to_json(app.hovered_vertex),
				"split_from": _vertex_to_json(app.split_from),
				"can_split": not app.split_button.disabled,
				"measure_points": _points_to_json(app.measure_points),
				"circle_points": _points_to_json(app.circle_points),
				"circle": _circle_to_json(),
				"segments": app.circle_segments(),
				"status_measure": app.status_measure.text}

		"set_tool":
			# Only what the toolbar itself allows: no drawing without a leaf
			# feature, and no change of kind once the feature holds geometry.
			var tool_name := str(request.get("tool", ""))
			if tool_name == "draw":
				if app.draw_button.disabled:
					return {"ok": false, "error": "the Draw tool needs a feature selected"}
				app.set_active_tool(Application.Tool.DRAW)
			elif tool_name == "vertex":
				if app.vertex_button.disabled:
					return {"ok": false, "error":
						"the Vertex tool needs a feature holding vertices of its own"}
				app.set_active_tool(Application.Tool.VERTEX)
			elif tool_name == "measure":
				app.set_active_tool(Application.Tool.MEASURE)
			elif tool_name == "circle":
				if app.circle_button.disabled:
					return {"ok": false, "error": "the Circle tool needs a feature selected"}
				app.set_active_tool(Application.Tool.CIRCLE)
			elif tool_name == "topology":
				if app.topology_button.disabled:
					return {"ok": false, "error":
						"the Topology tool needs a feature that can be a topology"}
				app.set_active_tool(Application.Tool.TOPOLOGY)
			elif tool_name == "light":
				if app.light_button.disabled:
					return {"ok": false, "error": "the light is dragged on the globe"}
				app.set_active_tool(Application.Tool.LIGHT)
			elif tool_name == "move":
				app.set_active_tool(Application.Tool.MOVE)
			elif not tool_name.is_empty():
				return {"ok": false, "error": "unknown tool: %s" % tool_name}
			if request.has("segments"):
				app.segments_spin.value = float(request["segments"])
			if request.has("snap"):
				app.snap_button.button_pressed = bool(request["snap"])
				app.snap_button.toggled.emit(app.snap_button.button_pressed)
			if request.has("kind"):
				var kind_name := str(request["kind"])
				if not Feature.KIND_VALUES.has(kind_name):
					return {"ok": false, "error": "unknown geometry kind: %s" % kind_name}
				if app.kind_selector.disabled:
					return {"ok": false, "error": "the geometry kind cannot be changed now"}
				var kind_index := app.kind_selector.get_item_index(Feature.KIND_VALUES[kind_name])
				if app.kind_selector.is_item_disabled(kind_index):
					return {"ok": false, "error": "a %s cannot be a %s" % [
						FeatureType.label(app.features.feature_tree.get_selected_node().feature_type),
						kind_name]}
				app.kind_selector.select(kind_index)
				app.kind_selector.item_selected.emit(app.kind_selector.selected)
			await _frames(2)
			return {"ok": true}

		"vertex":
			# What the Vertex tool does without a mouse: hold the first end of a
			# polygon cut, split, or delete the vertex it is working on. Picking
			# and dragging go through press, mouse_move and release, since
			# picking one is the thing being checked.
			var problem := ""
			match str(request.get("action", "")):
				"split_from":
					problem = app.hold_split_from()
				"split":
					problem = app.split_at_selected_vertex()
				"delete":
					problem = app.delete_selected_vertex()
				_:
					return {"ok": false, "error":
						"unknown vertex action: %s" % request.get("action", "")}
			if not problem.is_empty():
				return {"ok": false, "error": problem}
			await _frames(2)
			return {"ok": true}

		"get_status":
			return {"ok": true, "status": {
				"coordinates": app.status_coordinates.text,
				"measure": app.status_measure.text,
				"file": app.status_file.text,
			}}

		"get_view_settings":
			return {
				"ok": true,
				"view_settings": app.document.view.to_json(),
				# Why the backdrop image is not on the planet, empty while it is.
				"backdrop_error": app.backdrop.error,
				# What could not be read of the palette the document names.
				"palette_errors": Array(app.palette.errors),
			}

		"set_view_settings":
			# The View settings dialog without the dialog: whatever the request
			# names is changed through the same fields, which is what makes the
			# scene follow, and the rest stays as it was.
			app.show_view_settings()
			var block: Dictionary = request.get("view_settings", {})
			var problem := _fill_view_dialog(block)
			var button_name := str(request.get("button", ""))
			if not button_name.is_empty():
				var view_button: Button = app.view_dialog.find_child(button_name, true, false)
				if view_button == null:
					app.view_dialog.hide()
					return {"ok": false, "error": "no view settings button called %s" % button_name}
				view_button.pressed.emit()
			app.view_dialog.hide()
			if not problem.is_empty():
				return {"ok": false, "error": problem}
			await _frames(2)
			return {"ok": true}

		"get_preferences":
			return {"ok": true, "preferences": {
				"default_view": Config.get_default_view(),
				"view_defaults": Config.get_view_defaults().to_json(),
				"planet_radius_km": Config.get_planet_radius(),
				"vertex_marker_scale": Config.get_vertex_marker_scale(),
				"line_width_scale": Config.get_line_width_scale(),
				"snap_to_vertices": Config.get_snap_to_vertices(),
				"python_interpreter": Config.get_python_interpreter(),
				"script_directories": Config.get_script_directories(),
			}}

		"set_preferences":
			# The Preferences dialog without the dialog: whatever the request
			# names is changed through the same fields, the rest stays as it was.
			app.show_preferences()
			var wanted: Dictionary = request.get("preferences", {})
			if wanted.has("planet_radius_km"):
				app.radius_spin.value = float(wanted["planet_radius_km"])
			if wanted.has("vertex_marker_scale"):
				app.marker_spin.value = float(wanted["vertex_marker_scale"])
			if wanted.has("line_width_scale"):
				app.line_spin.value = float(wanted["line_width_scale"])
			if wanted.has("python_interpreter"):
				app.interpreter_edit.text = str(wanted["python_interpreter"])
			if wanted.has("script_directories"):
				var lines := PackedStringArray()
				for directory in wanted["script_directories"]:
					lines.append(str(directory))
				app.script_directories_edit.text = "
".join(lines)
			app.preferences_dialog.hide()
			app.preferences_dialog.confirmed.emit()
			await _frames(2)
			return {"ok": true}

		### Python scripting


		"get_python":
			return {"ok": true, "python": {
				"state": PythonBridge.State.keys()[app.python.state],
				"reason": app.python.reason,
				"interpreter": app.python.interpreter,
				"port": app.python.port,
				"ready": app.python.is_ready(),
			}}

		"get_console":
			return {"ok": true, "console": {
				"visible": app.console.visible,
				"prompt": app.console.prompt_label.text,
				"input": app.console.input.text,
				"editable": app.console.input.editable,
				"transcript": app.console.text(),
				"history": app.console.history,
			}}

		"console":
			# One line typed at the prompt, answered when the interpreter has
			# finished with it, so a run never races the reply.
			await app.console.submit(str(request.get("line", "")))
			await _frames(2)
			return {"ok": true, "transcript": app.console.text(),
				"prompt": app.console.prompt_label.text}

		"console_clear":
			app.console.clear()
			return {"ok": true}

		"console_recall":
			# The Up and Down arrows at the prompt: a negative step goes back.
			app.console.step_history(int(request.get("step", -1)))
			return {"ok": true, "input": app.console.input.text}

		"console_complete":
			# The Tab key at the prompt, over whatever the request types first.
			if request.has("source"):
				app.console.input.text = str(request["source"])
				app.console.input.caret_column = app.console.input.text.length()
			var completions: Array = await app.console.complete()
			await _frames(2)
			return {"ok": true, "completions": completions,
				"input": app.console.input.text}

		"get_scripts":
			var listed: Array = []
			for entry in app.scripts:
				listed.append({"name": entry.name, "title": entry.title(),
					"doc": entry.doc, "path": entry.path})
			return {"ok": true, "scripts": listed}

		"rescan_scripts":
			app.rescan_scripts()
			await _frames(2)
			return {"ok": true}

		"run_script":
			# By path, or by the name of a catalog entry, which is what the
			# Scripts menu runs.
			var path := str(request.get("path", ""))
			if path.is_empty():
				var name := str(request.get("name", ""))
				var index := -1
				for i in app.scripts.size():
					if app.scripts[i].name == name:
						index = i
				if index < 0:
					return {"ok": false, "error": "no script called %s" % name}
				app.scripts_menu.id_pressed.emit(Application.SCRIPT_ITEM_ID + index)
			else:
				app.run_script_file(path)
			# The script runs through the console, which answers on its own
			# frames; wait until it has stopped working.
			while app.console.busy:
				await _frames(1)
			await _frames(2)
			return {"ok": true, "transcript": app.console.text()}

		"quit":
			quitting = true
			return {"ok": true}

	return {"ok": false, "error": "unknown command: %s" % request.get("cmd", "")}


### Helpers


func _vertex_to_json(vertex: Vector2i) -> Variant:
	return null if vertex == Application.NO_VERTEX else [vertex.x, vertex.y]


# The circle the Circle tool has been given, and the ring it would commit, so a
# run can read back what the preview is drawing without looking at the screen.
func _circle_to_json() -> Variant:
	var circle: Array = app.circle_from_points()
	if circle.is_empty():
		return null
	return {
		"centre": [(circle[0] as Vector2).x, (circle[0] as Vector2).y],
		"radius": circle[1],
		"ring": _points_to_json(app.circle_ring()),
	}


# Drive the View settings fields from a block, one field per setting, and say
# which key was not one of them. The elevation and the azimuth are two fields of
# one setting, so a request may name either the pair or one of them.
# Drive the View settings dialog's own fields from a block, and say what could
# not be set. Setting a field is not enough on its own: a colour and a selector
# do not report a change made in code the way a spin box does, so the dialog is
# told once at the end that its fields have moved, exactly as the last field
# someone edits by hand would tell it.
func _fill_view_dialog(block: Dictionary) -> String:
	var fields: Dictionary = app.view_fields
	for key in block:
		var name := str(key)
		if name == "light_direction":
			var pair: Array = block[key]
			fields["light_elevation"].value = float(pair[0])
			fields["light_azimuth"].value = float(pair[1])
			continue
		if name == "hidden_classes":
			var problem := _hide_classes(block[key])
			if not problem.is_empty():
				return problem
			continue
		if name == "palette":
			# A palette is a built in name or the path of a file, and a path is
			# not in the list until the document names it, which is what
			# picking one through the dialog's Load button comes to.
			app.document.view.palette = str(block[key])
			app._fill_palette_choices()
			continue
		if not fields.has(name):
			return "no view setting called %s" % name
		var field: Control = fields[name]
		if field is OptionButton:
			var button := field as OptionButton
			Application.select_option(button, str(block[key]))
			if Application.option_value(button) != str(block[key]):
				return "%s cannot be set to %s" % [name, block[key]]
			continue
		if field is SpinBox:
			(field as SpinBox).value = float(block[key])
		elif field is CheckBox:
			(field as CheckBox).button_pressed = bool(block[key])
		elif field is ColorPickerButton:
			var parts: Array = block[key]
			(field as ColorPickerButton).color = Color(
				float(parts[0]), float(parts[1]), float(parts[2]),
				float(parts[3]) if parts.size() > 3 else 1.0)
		elif field is LineEdit:
			(field as LineEdit).text = str(block[key])
	app._on_view_field_changed()
	return ""


# Switch the geometry classes on and off so that the given ones are the hidden
# ones, through the View menu items themselves.
func _hide_classes(names: Variant) -> String:
	if names is not Array:
		return "hidden_classes must be a list of class names"
	for name in names:
		if not Styling.CLASSES.has(str(name)):
			return "no geometry class called %s" % name
	for class_id in Styling.CLASSES:
		var wanted: bool = class_id in (names as Array)
		if app.document.view.shows_class(class_id) == wanted:
			app.view_menu.id_pressed.emit(Application.class_menu_id(class_id))
	return ""


func _points_to_json(points: PackedVector2Array) -> Array:
	var list: Array = []
	for point in points:
		list.append([point.x, point.y])
	return list


# Hit test the same spread of points with and without the caps, and report the
# microseconds one hit test costs each way.
func _benchmark_hit_test(samples: int) -> Dictionary:
	var geometry: Planet.Geometry = app.geometry
	if geometry.features.is_empty():
		return {"ok": false, "error": "nothing is loaded to hit test"}

	# A spread over the whole globe rather than random points, so two runs of
	# the benchmark ask the same questions. The golden ratio in longitude walks
	# around the planet without ever repeating a meridian.
	var points := PackedVector2Array()
	for i in range(samples):
		var t := (float(i) + 0.5) / float(samples)
		points.append(Vector2(rad_to_deg(asin(2.0 * t - 1.0)), fmod(i * 222.4922, 360.0) - 180.0))

	var capped := _time_hit_tests(points, geometry)
	var hits := 0
	for point in points:
		if Planet.hit_test(point.x, point.y, geometry) != null:
			hits += 1

	var kept := geometry.cap_cosines.duplicate()
	for i in range(geometry.cap_cosines.size()):
		geometry.cap_cosines[i] = -1.0
	var uncapped := _time_hit_tests(points, geometry)
	geometry.cap_cosines = kept

	return {"ok": true, "hit_test": {
		"samples": samples,
		"hits": hits,
		"capped_us": capped / float(samples),
		"uncapped_us": uncapped / float(samples),
		"primitives": geometry.primitives.size(),
		"features": geometry.features.size(),
	}}


func _time_hit_tests(points: PackedVector2Array, geometry: Planet.Geometry) -> float:
	var started := Time.get_ticks_usec()
	for point in points:
		Planet.hit_test(point.x, point.y, geometry)
	return float(Time.get_ticks_usec() - started)


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
		"undo": return [app.edit_menu, Application.EditItem.UNDO]
		"redo": return [app.edit_menu, Application.EditItem.REDO]
		"cut": return [app.edit_menu, Application.EditItem.CUT]
		"copy": return [app.edit_menu, Application.EditItem.COPY]
		"paste": return [app.edit_menu, Application.EditItem.PASTE]
		"duplicate": return [app.edit_menu, Application.EditItem.DUPLICATE]
		"delete": return [app.edit_menu, Application.EditItem.DELETE]
		"new": return [app.file_menu, Application.FileItem.NEW]
		"open": return [app.file_menu, Application.FileItem.OPEN]
		"save": return [app.file_menu, Application.FileItem.SAVE]
		"save_as": return [app.file_menu, Application.FileItem.SAVE_AS]
		"import": return [app.file_menu, Application.FileItem.IMPORT]
		"preferences": return [app.file_menu, Application.FileItem.PREFERENCES]
		"quit": return [app.file_menu, Application.FileItem.QUIT]
		"features": return [app.view_menu, Application.ViewItem.FEATURES]
		"properties": return [app.view_menu, Application.ViewItem.PROPERTIES]
		"timeline": return [app.view_menu, Application.ViewItem.TIMELINE]
		"kinematics": return [app.view_menu, Application.ViewItem.KINEMATICS]
		"console": return [app.view_menu, Application.ViewItem.CONSOLE]
		"status_bar": return [app.view_menu, Application.ViewItem.STATUS_BAR]
		"run_script": return [app.file_menu, Application.FileItem.RUN_SCRIPT]
		"view_settings": return [app.view_menu, Application.ViewItem.SETTINGS]
		"full_screen": return [app.view_menu, Application.ViewItem.FULL_SCREEN]
		"about": return [app.help_menu, Application.HelpItem.ABOUT]
		"skip_older": return [app.time_menu, Application.TimeItem.OLDER]
		"skip_younger": return [app.time_menu, Application.TimeItem.YOUNGER]
		"keyframe_older": return [app.time_menu, Application.TimeItem.OLDER_KEYFRAME]
		"keyframe_younger": return [app.time_menu, Application.TimeItem.YOUNGER_KEYFRAME]
	if Styling.CLASSES.has(name):
		return [app.view_menu, Application.class_menu_id(name)]
	return []


# The label and availability of every item of a popup menu, separators aside.
func _menu_items(menu: PopupMenu) -> Array:
	var items: Array = []
	for index in menu.item_count:
		if menu.is_item_separator(index):
			continue
		items.append({"label": menu.get_item_text(index), "disabled": menu.is_item_disabled(index)})
	return items


func _menu_index(menu: PopupMenu, label: String) -> int:
	for index in menu.item_count:
		if menu.get_item_text(index).to_lower() == label.to_lower():
			return index
	return -1


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
func _on_file_dialog(mode: int, title: String, on_paths: Callable) -> void:
	last_file_dialog = {"mode": mode, "title": title}
	if not file_dialog_expected:
		return
	file_dialog_expected = false
	var paths := file_dialog_reply
	file_dialog_reply = PackedStringArray()
	if not paths.is_empty():
		on_paths.call(paths)


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


# What a feature is and where it is at the current time. `rotation` is what its
# own keyframes give it then and `world_rings` where that puts its vertices once
# every group above it has had its say, so a script reads the same positions the
# globe draws.
func _feature_to_json(feature: Feature) -> Variant:
	if feature == null:
		return null
	var time := app.document.current_time
	var world := Feature.world_basis(app.document.root, feature, time)
	var world_rings: Array[PackedVector2Array] = []
	for ring in feature.rings:
		world_rings.append(Feature.apply_basis(ring, world))
	var rotation := feature.rotation_at(time)
	var data := {
		"pnid": feature.pnid,
		"uuid": feature.uuid,
		"title": feature.title,
		"is_group": feature.is_group,
		"enabled": feature.enabled,
		"feature_type": feature.feature_type,
		"time": time,
		"time_range": [feature.time_range.x, feature.time_range.y],
		"exists_now": feature.exists_at(time),
		"color": [feature.color.r, feature.color.g, feature.color.b, feature.color.a],
		"rotation": [rotation.x, rotation.y, rotation.z],
		"keyframes": Keyframe.list_to_json(feature.keyframes),
		"geometry_kind": Feature.KIND_NAMES[feature.geometry_kind],
		"rings": Feature.rings_to_json(feature.rings),
		"world_rings": Feature.rings_to_json(world_rings),
		"triangles": _vertices_to_json(feature.triangles),
	}
	if feature.geometry_kind == Feature.GeometryKind.TOPOLOGY:
		data["sections"] = _sections_to_json(feature, time)
	return data


# What a line topology names and what each section came to at the current time,
# so a run can read a broken section without looking at the panel.
func _sections_to_json(feature: Feature, time: float) -> Array:
	var resolved := Topology.resolve(app.document.root, feature, time)
	var list: Array = []
	for index in feature.sections.size():
		var section: TopologySection = feature.sections[index]
		var entry: Dictionary = resolved[index]
		list.append({
			"feature": section.feature_uuid,
			"title": entry["title"],
			"part": section.part,
			"from": section.from_index,
			"to": section.to_index,
			"reversed": section.reversed,
			"problem": entry["problem"],
			"vertices": _vertices_to_json(entry["vertices"]),
		})
	return list


func _vertices_to_json(vertices: PackedVector2Array) -> Array:
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


# Half a click, so a script can drag: press, move the mouse, release. A click
# is the two of them at one point, which is not a drag however far the pointer
# went in between.
func _button(request: Dictionary, pressed: bool) -> Dictionary:
	var button_name := str(request.get("button", "left"))
	if not BUTTONS.has(button_name):
		return {"ok": false, "error": "unknown button: %s" % button_name}
	if request.has("x") or request.has("y"):
		await _move_mouse(_point(request))
	_send_button(int(BUTTONS[button_name]), false, pressed)
	await _physics_frames(2)
	await _frames(2)
	return {"ok": true}


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
