extends VBoxContainer
class_name Application


static var DEBUG: bool = true
static var VERSION: String = ProjectSettings.get_setting("application/config/version")
const ui_scale: float = 1.0

const APPLICATION_NAME := "Middle Earth"
const DOCUMENTATION_URL := "https://github.com/reni-ferenczi/middle-earth/tree/main/Docs"
static var FILE_FILTERS := PackedStringArray(["*.middle-earth ; Middle Earth Files"])

# Answers a file dialog without showing one. Set by the automation port so a
# scripted run can drive Open and Save As; unset in a normal run.
static var file_dialog_hook: Callable

enum Tool { MOVE, DRAW }

enum FileItem { NEW, OPEN, SAVE, SAVE_AS, PREFERENCES, QUIT }
enum ViewItem { FEATURES, PROPERTIES, TIMELINE, STATUS_BAR, FULL_SCREEN }
enum HelpItem { DOCUMENTATION, ABOUT }

# Item id of the entry that empties the recent file list; above any file index.
const CLEAR_RECENT_ID := 1000

# View menu item to the config key remembering whether that panel is shown.
const PANEL_KEYS := {
	ViewItem.FEATURES: "panel_features",
	ViewItem.PROPERTIES: "panel_properties",
	ViewItem.TIMELINE: "panel_timeline",
	ViewItem.STATUS_BAR: "panel_status_bar",
}

@onready var features: Features = %Features
@onready var planet_view: PlanetView = %PlanetView
@onready var move_button: Button = %Move
@onready var draw_button: Button = %Draw
@onready var menu_bar: MenuBar = %MenuBar
@onready var left_splitter: HSplitContainer = %LeftSplitter
@onready var right_splitter: HSplitContainer = %RightSplitter
@onready var properties: Control = %Properties
@onready var timeline: Timeline = %Timeline
@onready var status_bar: Control = %StatusBar
@onready var status_coordinates: Label = %StatusCoordinates
@onready var status_file: Label = %StatusFile
@onready var leave_full_screen: Button = %LeaveFullScreen

# The open document. Created here so the panels can attach to it when ready.
var document := Document.new()

var active_tool: Tool = Tool.MOVE
var last_triangles: Array = []
var hovered_feature: Feature = null

# True while the automation port is open: the session is not restored and not
# remembered, so scripted runs always start from the same shell.
var automated: bool = false

var file_menu: PopupMenu
var recent_menu: PopupMenu
var view_menu: PopupMenu
var save_prompt: ConfirmationDialog
var about_dialog: AcceptDialog
var preferences_dialog: AcceptDialog
var error_dialog: AcceptDialog
var restore_session_check: CheckBox
var default_folder_edit: LineEdit

# What to do once the unsaved changes prompt has been answered.
var _pending_action: Callable


func _ready() -> void:
	# The switches belong to the application proper. A test runner that hosts
	# this scene passes its own arguments through the same channel, so they are
	# only read when the application is the scene that was started.
	if get_tree().current_scene == self:
		var exit_code := Cli.handle(OS.get_cmdline_user_args())
		if exit_code >= 0:
			get_tree().quit(exit_code)
			return

	get_tree().root.content_scale_factor = Application.ui_scale
	get_tree().set_auto_accept_quit(false)

	# The automation port decides the shell before anything reads a setting: a
	# scripted run starts from the same window every time and leaves the
	# settings of whoever is at the keyboard alone.
	var port := Cli.automation_port(OS.get_cmdline_user_args())
	automated = port != 0
	if automated:
		Config.directory_override = OS.get_user_data_dir().path_join("automation")
		Config.clear()

	features.attach(document)
	document.root_replaced.connect(_on_root_replaced)
	document.state_changed.connect(_update_document_labels)

	_build_menus()
	_build_dialogs()

	# Connect tool buttons
	move_button.pressed.connect(_on_move_pressed)
	draw_button.pressed.connect(_on_draw_pressed)

	# The Save and Load buttons of the feature tree toolbar run the File commands
	features.save_button.pressed.connect(save_document)
	features.load_button.pressed.connect(open_document)

	# Connect feature selection from the features panel
	features.feature_tree.feature_selected.connect(_on_feature_selected)

	# Connect planet click events for drawing
	planet_view.planet.input_event_globe.connect(_on_planet_input_for_drawing)
	planet_view.planet.input_event_map.connect(_on_planet_input_for_drawing)

	# Connect program changes to refresh cratons
	features.feature_tree.program_changed.connect(_on_program_changed)

	# Connect move tool signals
	planet_view.move_started.connect(_on_move_started)
	planet_view.move_to.connect(_on_move_to)
	planet_view.move_ended.connect(_on_move_ended)
	planet_view.move_cancelled.connect(_on_move_cancelled)

	# Connect craton interaction signals
	planet_view.craton_clicked.connect(_on_craton_clicked)
	planet_view.craton_hovered.connect(_on_craton_hovered)
	planet_view.cursor_moved.connect(_on_cursor_moved)

	leave_full_screen.pressed.connect(_toggle_full_screen)

	# Open the test automation port if requested: -- --automation-port=<port>
	if automated:
		add_child(AutomationPort.new(self, port))

	_restore_session()
	_update_document_labels()
	_on_cursor_moved(NAN, NAN)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_application()


### Menus


func _build_menus() -> void:
	file_menu = _add_menu("File")
	file_menu.add_item("New", FileItem.NEW, KEY_MASK_CTRL | KEY_N)
	file_menu.add_item("Open...", FileItem.OPEN, KEY_MASK_CTRL | KEY_O)
	recent_menu = PopupMenu.new()
	recent_menu.name = "OpenRecent"
	recent_menu.id_pressed.connect(_on_recent_menu_id_pressed)
	file_menu.add_submenu_node_item("Open Recent", recent_menu)
	file_menu.add_separator()
	file_menu.add_item("Save", FileItem.SAVE, KEY_MASK_CTRL | KEY_S)
	file_menu.add_item("Save As...", FileItem.SAVE_AS, KEY_MASK_CTRL | KEY_MASK_SHIFT | KEY_S)
	file_menu.add_separator()
	file_menu.add_item("Preferences...", FileItem.PREFERENCES)
	file_menu.add_separator()
	file_menu.add_item("Quit", FileItem.QUIT, KEY_MASK_CTRL | KEY_Q)
	file_menu.id_pressed.connect(_on_file_menu_id_pressed)

	view_menu = _add_menu("View")
	view_menu.add_check_item("Features", ViewItem.FEATURES)
	view_menu.add_check_item("Properties", ViewItem.PROPERTIES)
	view_menu.add_check_item("Timeline", ViewItem.TIMELINE)
	view_menu.add_check_item("Status Bar", ViewItem.STATUS_BAR)
	view_menu.add_separator()
	view_menu.add_item("Full Screen", ViewItem.FULL_SCREEN, KEY_F11)
	view_menu.id_pressed.connect(_on_view_menu_id_pressed)

	var help_menu := _add_menu("Help")
	help_menu.add_item("Documentation", HelpItem.DOCUMENTATION, KEY_F1)
	help_menu.add_item("About Middle Earth", HelpItem.ABOUT)
	help_menu.id_pressed.connect(_on_help_menu_id_pressed)

	_rebuild_recent_menu()
	_update_view_menu_checks()


func _add_menu(title: String) -> PopupMenu:
	var menu := PopupMenu.new()
	menu.name = title
	menu_bar.add_child(menu)
	menu_bar.set_menu_title(menu_bar.get_menu_count() - 1, title)
	return menu


func _rebuild_recent_menu() -> void:
	recent_menu.clear()
	var recent := Config.get_recent_files()
	for index in recent.size():
		recent_menu.add_item(str(recent[index]), index)
	if recent.is_empty():
		recent_menu.add_item("(no recent files)", CLEAR_RECENT_ID + 1)
		recent_menu.set_item_disabled(recent_menu.item_count - 1, true)
	else:
		recent_menu.add_separator()
		recent_menu.add_item("Clear", CLEAR_RECENT_ID)


func _on_file_menu_id_pressed(id: int) -> void:
	match id:
		FileItem.NEW: new_document()
		FileItem.OPEN: open_document()
		FileItem.SAVE: save_document()
		FileItem.SAVE_AS: save_document_as()
		FileItem.PREFERENCES: show_preferences()
		FileItem.QUIT: quit_application()


func _on_recent_menu_id_pressed(id: int) -> void:
	if id == CLEAR_RECENT_ID:
		Config.clear_recent_files()
		_rebuild_recent_menu()
		return
	var recent := Config.get_recent_files()
	if id < recent.size():
		open_path(str(recent[id]))


func _on_view_menu_id_pressed(id: int) -> void:
	if id == ViewItem.FULL_SCREEN:
		_toggle_full_screen()
		return
	var panel := _panel_node(id)
	panel.visible = not panel.visible
	_update_view_menu_checks()
	_save_panel_visibility()


func _on_help_menu_id_pressed(id: int) -> void:
	match id:
		HelpItem.DOCUMENTATION: OS.shell_open(DOCUMENTATION_URL)
		HelpItem.ABOUT: about_dialog.popup_centered()


func _panel_node(item: int) -> Control:
	match item:
		ViewItem.FEATURES: return features
		ViewItem.PROPERTIES: return properties
		ViewItem.TIMELINE: return timeline
		ViewItem.STATUS_BAR: return status_bar
	return null


func _update_view_menu_checks() -> void:
	for item in PANEL_KEYS:
		view_menu.set_item_checked(view_menu.get_item_index(item), _panel_node(item).visible)


### Full screen


func is_full_screen() -> bool:
	var mode := get_window().mode
	return mode == Window.MODE_FULLSCREEN or mode == Window.MODE_EXCLUSIVE_FULLSCREEN


func _toggle_full_screen() -> void:
	var leaving := is_full_screen()
	get_window().mode = Window.MODE_WINDOWED if leaving else Window.MODE_FULLSCREEN
	# The button floats over the view, as there is no menu bar to leave by.
	leave_full_screen.get_parent().visible = not leaving


### The document


func new_document() -> void:
	_confirm_unsaved_changes(document.reset)


func open_document() -> void:
	_confirm_unsaved_changes(_ask_open_path)


func open_path(path: String) -> void:
	_confirm_unsaved_changes(_load_path.bind(path))


func save_document(after: Callable = Callable()) -> void:
	if document.path.is_empty():
		save_document_as(after)
		return
	_write_to(document.path, after)


func save_document_as(after: Callable = Callable()) -> void:
	_ask_for_path(DisplayServer.FILE_DIALOG_MODE_SAVE_FILE, "Save As", func(path: String) -> void:
		if not path.ends_with(Document.EXTENSION):
			path += Document.EXTENSION
		_write_to(path, after))


func quit_application() -> void:
	_confirm_unsaved_changes(_finish_quit)


func _finish_quit() -> void:
	_save_session()
	get_tree().quit()


func _ask_open_path() -> void:
	_ask_for_path(DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, "Open", _load_path)


func _load_path(path: String) -> void:
	var error := document.load_from_file(path)
	if not error.is_empty():
		_show_error(error)
		return
	_remember_file(path)


func _write_to(path: String, after: Callable) -> void:
	var error := document.save_to_file(path)
	if not error.is_empty():
		_show_error(error)
		return
	_remember_file(path)
	if after.is_valid():
		after.call()


func _remember_file(path: String) -> void:
	Config.set_last_directory_from_file(path)
	Config.add_recent_file(path)
	_rebuild_recent_menu()


func _on_root_replaced() -> void:
	set_active_tool(Tool.MOVE)
	refresh_cratons()


func _update_document_labels() -> void:
	var marker := "*" if document.is_dirty() else ""
	get_window().title = "%s%s — %s" % [marker, document.display_name(), APPLICATION_NAME]
	status_file.text = Document.UNTITLED if document.path.is_empty() else document.path


### Unsaved changes prompt


# Run action, after asking what to do about unsaved changes. Saving opens a
# dialog and returns before it is answered, so what follows it is a callable
# rather than the code after the call.
func _confirm_unsaved_changes(action: Callable) -> void:
	if not document.is_dirty():
		action.call()
		return
	_pending_action = action
	save_prompt.dialog_text = "Save the changes to %s first?" % document.display_name()
	save_prompt.popup_centered()


func _on_save_prompt_confirmed() -> void:
	save_document(_take_pending_action())


func _on_save_prompt_custom_action(action_name: StringName) -> void:
	save_prompt.hide()
	var action := _take_pending_action()
	if action_name == &"discard" and action.is_valid():
		action.call()


func _on_save_prompt_canceled() -> void:
	_pending_action = Callable()


func _take_pending_action() -> Callable:
	var action := _pending_action
	_pending_action = Callable()
	return action


### Dialogs


func _build_dialogs() -> void:
	save_prompt = ConfirmationDialog.new()
	save_prompt.name = "SavePrompt"
	save_prompt.title = "Unsaved changes"
	save_prompt.ok_button_text = "Save"
	save_prompt.add_button("Discard", true, "discard")
	save_prompt.confirmed.connect(_on_save_prompt_confirmed)
	save_prompt.custom_action.connect(_on_save_prompt_custom_action)
	save_prompt.canceled.connect(_on_save_prompt_canceled)
	add_child(save_prompt)

	error_dialog = AcceptDialog.new()
	error_dialog.name = "ErrorDialog"
	error_dialog.title = "Middle Earth"
	add_child(error_dialog)

	about_dialog = AcceptDialog.new()
	about_dialog.name = "AboutDialog"
	about_dialog.title = "About Middle Earth"
	about_dialog.add_child(_build_about_content())
	add_child(about_dialog)

	preferences_dialog = AcceptDialog.new()
	preferences_dialog.name = "PreferencesDialog"
	preferences_dialog.title = "Preferences"
	preferences_dialog.add_child(_build_preferences_content())
	preferences_dialog.confirmed.connect(_on_preferences_confirmed)
	add_child(preferences_dialog)


func _build_about_content() -> Control:
	var text := RichTextLabel.new()
	text.name = "About"
	text.bbcode_enabled = true
	text.fit_content = true
	text.custom_minimum_size = Vector2(520, 0)
	text.meta_clicked.connect(func(meta: Variant) -> void: OS.shell_open(str(meta)))
	text.text = "\n".join([
		"[b]%s %s[/b]" % [APPLICATION_NAME, VERSION],
		"",
		"An alternative user interface for plate tectonic reconstructions,",
		"built with the Godot engine.",
		"",
		"[b]Credits[/b]",
		"Reni Ferenczi and Viktor Ferenczi, development.",
		"Earth texture: NASA Visible Earth, Blue Marble Next Generation,",
		"[url=https://visibleearth.nasa.gov/collection/1484/blue-marble]visibleearth.nasa.gov[/url]",
		"",
		"[url=%s]Documentation[/url]" % DOCUMENTATION_URL,
	])
	return text


func _build_preferences_content() -> Control:
	var box := VBoxContainer.new()
	box.name = "Preferences"
	box.custom_minimum_size = Vector2(520, 0)

	var folder_label := Label.new()
	folder_label.text = "Default folder for Open and Save"
	box.add_child(folder_label)

	default_folder_edit = LineEdit.new()
	default_folder_edit.name = "DefaultFolder"
	box.add_child(default_folder_edit)

	restore_session_check = CheckBox.new()
	restore_session_check.name = "RestoreSession"
	restore_session_check.text = "Reopen the last file on launch"
	box.add_child(restore_session_check)

	return box


func show_preferences() -> void:
	default_folder_edit.text = Config.get_last_directory()
	restore_session_check.button_pressed = bool(Config.get_value("restore_session", true))
	preferences_dialog.popup_centered()


func _on_preferences_confirmed() -> void:
	Config.set_last_directory(default_folder_edit.text)
	Config.set_value("restore_session", restore_session_check.button_pressed)


func _show_error(message: String) -> void:
	push_error(message)
	error_dialog.dialog_text = message
	error_dialog.popup_centered()


### The session: window geometry, panels and the last file


func _restore_session() -> void:
	if automated:
		return

	var window := get_window()
	var geometry: Variant = Config.get_value("window")
	if geometry is Dictionary:
		window.size = Vector2i(
			int(geometry.get("width", window.size.x)),
			int(geometry.get("height", window.size.y))).clamp(Vector2i(640, 480), DisplayServer.screen_get_size())
		window.position = Vector2i(
			int(geometry.get("x", window.position.x)),
			int(geometry.get("y", window.position.y)))
		if bool(geometry.get("maximized", false)):
			window.mode = Window.MODE_MAXIMIZED

	left_splitter.split_offset = int(Config.get_value("splitter_left", left_splitter.split_offset))
	right_splitter.split_offset = int(Config.get_value("splitter_right", right_splitter.split_offset))

	for item in PANEL_KEYS:
		_panel_node(item).visible = bool(Config.get_value(PANEL_KEYS[item], true))
	_update_view_menu_checks()

	if not bool(Config.get_value("restore_session", true)):
		return
	var recent := Config.get_recent_files()
	if not recent.is_empty() and FileAccess.file_exists(str(recent[0])):
		_load_path(str(recent[0]))


func _save_session() -> void:
	if automated:
		return
	var window := get_window()
	Config.set_value("window", {
		"x": window.position.x,
		"y": window.position.y,
		"width": window.size.x,
		"height": window.size.y,
		"maximized": window.mode == Window.MODE_MAXIMIZED,
	})
	Config.set_value("splitter_left", left_splitter.split_offset)
	Config.set_value("splitter_right", right_splitter.split_offset)
	_save_panel_visibility()


func _save_panel_visibility() -> void:
	if automated:
		return
	for item in PANEL_KEYS:
		Config.set_value(PANEL_KEYS[item], _panel_node(item).visible)


### File dialogs


# Ask for a file path and call on_path with it. The dialog is the one the
# platform provides, so nothing happens when it is cancelled.
func _ask_for_path(mode: int, title: String, on_path: Callable) -> void:
	if file_dialog_hook.is_valid():
		file_dialog_hook.call(mode, title, on_path)
		return
	DisplayServer.file_dialog_show(
		title,
		Config.get_last_directory(),
		"",
		false,
		mode,
		FILE_FILTERS,
		func(status: bool, paths: PackedStringArray, _filter: int) -> void:
			if status and not paths.is_empty():
				on_path.call(paths[0]),
	)


### Status bar


func _on_cursor_moved(lat: float, lon: float) -> void:
	if is_nan(lat) or is_nan(lon):
		status_coordinates.text = "off the planet"
	else:
		status_coordinates.text = "%.2f° %s   %.2f° %s" % [
			absf(lat), "N" if lat >= 0.0 else "S",
			absf(lon), "E" if lon >= 0.0 else "W"]


### Tool button group


func _on_move_pressed() -> void:
	set_active_tool(Tool.MOVE)


func _on_draw_pressed() -> void:
	set_active_tool(Tool.DRAW)


func set_active_tool(tool: Tool) -> void:
	if active_tool == Tool.DRAW and tool != Tool.DRAW:
		_outline_cancel()
	active_tool = tool
	move_button.button_pressed = (tool == Tool.MOVE)
	draw_button.button_pressed = (tool == Tool.DRAW)
	planet_view.drawing_mode = (tool == Tool.DRAW)
	_update_move_enabled()


### Feature selection


func _on_feature_selected(node: Feature) -> void:
	# Clear any in-progress outline when switching features
	if not outline_vertices.is_empty():
		_outline_cancel()

	var is_leaf := node != null and not node.is_group
	draw_button.disabled = not is_leaf

	if is_leaf:
		# Auto-select Draw if the feature has no craton (no vertices)
		if node.vertices.is_empty():
			set_active_tool(Tool.DRAW)
	else:
		# Can't draw on groups or nothing — force Move
		if active_tool == Tool.DRAW:
			set_active_tool(Tool.MOVE)

	_update_move_enabled()
	refresh_cratons()


### Move tool


func _update_move_enabled() -> void:
	var selected := features.feature_tree.get_selected_node()
	var can_move := active_tool == Tool.MOVE and selected != null and not selected.is_group and not selected.vertices.is_empty()
	planet_view.move_enabled = can_move


var move_anchor_world: Vector3
var move_base_rot: Vector3


func _on_move_started(anchor_lat: float, anchor_lon: float) -> void:
	var selected := features.feature_tree.get_selected_node()
	if selected == null or selected.is_group:
		return
	move_base_rot = selected.rotation_angles
	move_anchor_world = Feature._latlon_to_xyz_s(Vector2(anchor_lat, anchor_lon))


func _on_move_to(lat: float, lon: float) -> void:
	var selected := features.feature_tree.get_selected_node()
	if selected == null or selected.is_group:
		return
	var target_world := Feature._latlon_to_xyz_s(Vector2(lat, lon))
	var new_rot: Variant = Feature.compute_move_rotation(move_anchor_world, target_world, move_base_rot)
	if new_rot != null:
		selected.rotation_angles = new_rot
		refresh_cratons()


func _on_move_ended() -> void:
	document.record()
	features.reload()
	refresh_cratons()


func _on_move_cancelled() -> void:
	var selected := features.feature_tree.get_selected_node()
	if selected != null and not selected.is_group:
		selected.rotation_angles = move_base_rot
	refresh_cratons()


### Drawing — Polygon outline mode


var outline_vertices: Array[Vector2] = []


func _on_planet_input_for_drawing(lat: float, lon: float, event: InputEvent) -> void:
	if active_tool != Tool.DRAW:
		return
	if event is not InputEventMouseButton or not event.is_pressed():
		return

	var selected := features.feature_tree.get_selected_node()
	if selected == null or selected.is_group:
		return

	if event.button_index == MOUSE_BUTTON_LEFT:
		outline_vertices.append(Vector2(lat, lon))
		_refresh_outline()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if not outline_vertices.is_empty():
			outline_vertices.pop_back()
			_refresh_outline()


func _unhandled_key_input(event: InputEvent) -> void:
	if active_tool != Tool.DRAW:
		return
	if event is not InputEventKey or not event.is_pressed():
		return

	if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		_outline_commit()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE:
		_outline_cancel()
		get_viewport().set_input_as_handled()


func _outline_commit() -> void:
	if outline_vertices.size() < 3:
		return
	var selected := features.feature_tree.get_selected_node()
	if selected == null or selected.is_group:
		return

	var triangles := _ear_clip(outline_vertices)

	# Ensure front-facing winding on world-space triangles before storing
	for i in range(0, triangles.size() - 2, 3):
		_ensure_front_winding(triangles, i)

	# Convert from world space to local (unrotated) space
	if not selected.rotation_angles.is_zero_approx():
		triangles = Feature.unapply_rotation(triangles, selected.rotation_angles)

	selected.vertices.append_array(triangles)

	outline_vertices.clear()
	_refresh_outline()
	document.record()
	features.reload()
	refresh_cratons()
	set_active_tool(Tool.MOVE)


func _outline_cancel() -> void:
	outline_vertices.clear()
	_refresh_selection_outline()


func _refresh_outline() -> void:
	planet_view.planet.set_outline(outline_vertices, outline_vertices.size() >= 3)


### Ear-clipping triangulation


static func _ear_clip(polygon: Array[Vector2]) -> Array[Vector2]:
	var n := polygon.size()
	if n < 3:
		return []

	var result: Array[Vector2] = []

	# Build mutable index list
	var idx: Array[int] = []
	for i in range(n):
		idx.append(i)

	# Determine winding direction using signed area (shoelace formula)
	var area := 0.0
	for i in range(n):
		var j := (i + 1) % n
		area += polygon[i].x * polygon[j].y - polygon[j].x * polygon[i].y
	var winding_sign := 1.0 if area > 0.0 else -1.0

	var max_iterations := n * n
	var iter := 0
	var i := 0

	while idx.size() > 3 and iter < max_iterations:
		iter += 1
		var sz := idx.size()
		var prev := (i - 1 + sz) % sz
		var next := (i + 1) % sz

		var a := polygon[idx[prev]]
		var b := polygon[idx[i]]
		var c := polygon[idx[next]]

		# Check if this vertex forms a convex ear (matches polygon winding)
		var cross_val := (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
		if cross_val * winding_sign <= 0.0:
			i = (i + 1) % sz
			continue

		# Check no other polygon vertex falls inside this triangle
		var is_ear := true
		for k in range(sz):
			if k == prev or k == i or k == next:
				continue
			if _point_in_triangle(polygon[idx[k]], a, b, c):
				is_ear = false
				break

		if is_ear:
			result.append(a)
			result.append(b)
			result.append(c)
			idx.remove_at(i)
			if i >= idx.size():
				i = 0
		else:
			i = (i + 1) % idx.size()

	# Output the final remaining triangle
	if idx.size() == 3:
		result.append(polygon[idx[0]])
		result.append(polygon[idx[1]])
		result.append(polygon[idx[2]])

	return result


static func _point_in_triangle(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := (p.x - b.x) * (a.y - b.y) - (a.x - b.x) * (p.y - b.y)
	var d2 := (p.x - c.x) * (b.y - c.y) - (b.x - c.x) * (p.y - c.y)
	var d3 := (p.x - a.x) * (c.y - a.y) - (c.x - a.x) * (p.y - a.y)
	var has_neg := (d1 < 0) or (d2 < 0) or (d3 < 0)
	var has_pos := (d1 > 0) or (d2 > 0) or (d3 > 0)
	return not (has_neg and has_pos)


### Winding and coordinate helpers


func _ensure_front_winding(verts: Array[Vector2], start: int) -> void:
	var a := _latlon_to_xyz(verts[start])
	var b := _latlon_to_xyz(verts[start + 1])
	var c := _latlon_to_xyz(verts[start + 2])

	var normal := (b - a).cross(c - a)
	var center := (a + b + c) / 3.0

	if normal.dot(center) < 0:
		var tmp := verts[start + 1]
		verts[start + 1] = verts[start + 2]
		verts[start + 2] = tmp


func _latlon_to_xyz(v: Vector2) -> Vector3:
	var lat_rad := deg_to_rad(v.x)
	var lon_rad := deg_to_rad(v.y)
	var cos_lat := cos(lat_rad)
	return Vector3(
		cos_lat * cos(lon_rad),
		sin(lat_rad),
		cos_lat * sin(lon_rad)
	)


### Craton interaction


func _on_craton_clicked(lat: float, lon: float) -> void:
	var hit := Planet.hit_test_craton(lat, lon, last_triangles)
	var selected := features.feature_tree.get_selected_node()
	print("Craton click: hit=%s (pnid=%d), selected=%s (pnid=%d)" % [
		hit.title if hit else "null", hit.pnid if hit else -1,
		selected.title if selected else "null", selected.pnid if selected else -1])
	if hit != null and hit != selected:
		# Clicked a different craton — select it (deferred to avoid Tree UI update issues)
		features.feature_tree.select_node.call_deferred(hit)
	elif planet_view.move_enabled:
		# Clicked on the same craton or empty space — start moving
		planet_view.start_moving(lat, lon)


func _on_craton_hovered(lat: float, lon: float) -> void:
	var new_hovered: Feature = null
	if not is_nan(lat):
		new_hovered = Planet.hit_test_craton(lat, lon, last_triangles)
	if new_hovered != hovered_feature:
		hovered_feature = new_hovered
		planet_view.planet.set_cratons(last_triangles, hovered_feature)


### Craton rendering


func refresh_cratons() -> void:
	last_triangles = Planet.collect_triangles(features.root)
	planet_view.planet.set_cratons(last_triangles, hovered_feature)
	_refresh_selection_outline()


func _refresh_selection_outline() -> void:
	# Don't overwrite the drawing outline
	if not outline_vertices.is_empty():
		return
	var selected := features.feature_tree.get_selected_node()
	if selected != null and not selected.is_group and not selected.vertices.is_empty():
		var verts := Feature.apply_rotation(selected.vertices, selected.rotation_angles)
		planet_view.planet.set_outline(verts, false, true)
	else:
		var empty: Array[Vector2] = []
		planet_view.planet.set_outline(empty)


func _on_program_changed() -> void:
	refresh_cratons()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
