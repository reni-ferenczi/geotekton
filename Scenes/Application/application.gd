extends VBoxContainer
class_name Application


static var DEBUG: bool = true
static var VERSION: String = ProjectSettings.get_setting("application/config/version")
const ui_scale: float = 1.0

const APPLICATION_NAME := "Middle Earth"
const DOCUMENTATION_URL := "https://github.com/reni-ferenczi/middle-earth/tree/main/Docs"
# Where an isolated run keeps its settings, under the user data directory.
const ISOLATED_SETTINGS_DIR := "isolated-settings"

# The Earth texture credited in the About dialog, as listed in README.md.
const EARTH_TEXTURE_URL := "https://wall.alphacoders.com/big.php?i=11433"
static var FILE_FILTERS := PackedStringArray(["*%s ; Middle Earth Files" % Document.EXTENSION])

# Answers a file dialog without showing one. Set by the automation port so a
# scripted run can drive Open and Save As; unset in a normal run.
static var file_dialog_hook: Callable

enum Tool { MOVE, DRAW }

enum FileItem { NEW, OPEN, SAVE, SAVE_AS, PREFERENCES, QUIT }
enum EditItem { UNDO, REDO, CUT, COPY, PASTE, DUPLICATE, DELETE }
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
@onready var kind_selector: OptionButton = %GeometryKind
@onready var menu_bar: MenuBar = %MenuBar
@onready var left_splitter: HSplitContainer = %LeftSplitter
@onready var right_splitter: HSplitContainer = %RightSplitter
@onready var properties: Properties = %Properties
@onready var timeline: Timeline = %Timeline
@onready var status_bar: Control = %StatusBar
@onready var status_coordinates: Label = %StatusCoordinates
@onready var status_file: Label = %StatusFile
@onready var leave_full_screen: Button = %LeaveFullScreen

# The open document. Created here so the panels can attach to it when ready.
var document := Document.new()

var active_tool: Tool = Tool.MOVE

# The feature tree flattened for the shader and the hit test. Rebuilt when the
# tree changes; where each feature sits at the current time is resolved on it
# separately, which is all a step of an animation touches.
var geometry := Planet.Geometry.new()
var hovered_feature: Feature = null

# True when the application must leave the settings of whoever is at the
# keyboard alone: a scripted run, or a test runner hosting this scene. The
# session is then neither restored nor remembered, so every run starts from the
# same shell and its settings go to a scratch folder.
var isolated: bool = false

var file_menu: PopupMenu
var recent_menu: PopupMenu
var edit_menu: PopupMenu
var view_menu: PopupMenu
var help_menu: PopupMenu
# The Edit commands again, on a right click on the globe.
var globe_menu: PopupMenu
var save_prompt: ConfirmationDialog
var about_dialog: AcceptDialog
var preferences_dialog: AcceptDialog
var error_dialog: AcceptDialog
var restore_session_check: CheckBox
var default_folder_edit: LineEdit
var animation_dialog: AcceptDialog
# The fields of the animation dialog, by the name of the setting each one edits.
var animation_fields: Dictionary = {}

# What to do once the unsaved changes prompt has been answered.
var _pending_action: Callable


func _ready() -> void:
	# The switches belong to the application proper. A test runner that hosts
	# this scene passes its own arguments through the same channel, so they are
	# only read when the application is the scene that was started.
	var started_on_its_own := get_tree().current_scene == self
	if started_on_its_own:
		var exit_code := Cli.handle(OS.get_cmdline_user_args())
		if exit_code >= 0:
			get_tree().quit(exit_code)
			return

	get_tree().root.content_scale_factor = Application.ui_scale
	get_tree().set_auto_accept_quit(false)

	# Settled before anything reads a setting, so an isolated run cannot pick one
	# up from the config file it is about to be kept out of.
	var port := Cli.automation_port(OS.get_cmdline_user_args())
	isolated = port != 0 or not started_on_its_own
	if isolated:
		Config.directory_override = OS.get_user_data_dir().path_join(ISOLATED_SETTINGS_DIR)
		Config.clear()

	features.attach(document)
	properties.attach(document)
	properties.edited.connect(_on_properties_edited)
	properties.previewed.connect(refresh_geometry)
	properties.rejected.connect(_show_error)
	document.root_replaced.connect(_on_root_replaced)
	document.state_changed.connect(_update_document_labels)
	document.time_changed.connect(_on_time_changed)
	timeline.attach(document)
	timeline.configure_requested.connect(_show_animation_dialog)
	# The Edit menus offer what the feature tree toolbar offers, so they follow
	# the same signal: the undo depth, the selection and the clipboard all reach
	# it, which a copy that records no undo version otherwise would not.
	features.commands_changed.connect(_update_edit_menu)

	_build_menus()
	_build_dialogs()

	# Connect tool buttons
	move_button.pressed.connect(_on_move_pressed)
	draw_button.pressed.connect(_on_draw_pressed)
	_build_kind_selector()

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
	planet_view.craton_context_menu.connect(_on_craton_context_menu)
	planet_view.craton_hovered.connect(_on_craton_hovered)
	planet_view.cursor_moved.connect(_on_cursor_moved)

	leave_full_screen.pressed.connect(_toggle_full_screen)

	# Open the test automation port if requested: -- --automation-port=<port>
	if port != 0:
		add_child(AutomationPort.new(self, port))

	if not isolated:
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

	edit_menu = _add_menu("Edit")
	_add_edit_items(edit_menu)
	edit_menu.id_pressed.connect(_on_edit_menu_id_pressed)

	# The same commands on a right click on the globe, without the accelerators,
	# which belong to the menu bar and would fire twice from two menus.
	globe_menu = PopupMenu.new()
	globe_menu.name = "GlobeMenu"
	globe_menu.add_item("Duplicate", EditItem.DUPLICATE)
	globe_menu.add_item("Delete", EditItem.DELETE)
	globe_menu.id_pressed.connect(_on_edit_menu_id_pressed)
	add_child(globe_menu)

	view_menu = _add_menu("View")
	view_menu.add_check_item("Features", ViewItem.FEATURES)
	view_menu.add_check_item("Properties", ViewItem.PROPERTIES)
	view_menu.add_check_item("Timeline", ViewItem.TIMELINE)
	view_menu.add_check_item("Status Bar", ViewItem.STATUS_BAR)
	view_menu.add_separator()
	view_menu.add_item("Full Screen", ViewItem.FULL_SCREEN, KEY_F11)
	view_menu.id_pressed.connect(_on_view_menu_id_pressed)

	help_menu = _add_menu("Help")
	help_menu.add_item("Documentation", HelpItem.DOCUMENTATION, KEY_F1)
	help_menu.add_item("About Middle Earth", HelpItem.ABOUT)
	help_menu.id_pressed.connect(_on_help_menu_id_pressed)

	_rebuild_recent_menu()
	_update_view_menu_checks()
	_update_edit_menu()


func _add_edit_items(menu: PopupMenu) -> void:
	menu.add_item("Undo", EditItem.UNDO, KEY_MASK_CTRL | KEY_Z)
	menu.add_item("Redo", EditItem.REDO, KEY_MASK_CTRL | KEY_Y)
	menu.add_separator()
	menu.add_item("Cut", EditItem.CUT, KEY_MASK_CTRL | KEY_X)
	menu.add_item("Copy", EditItem.COPY, KEY_MASK_CTRL | KEY_C)
	menu.add_item("Paste", EditItem.PASTE, KEY_MASK_CTRL | KEY_V)
	menu.add_separator()
	menu.add_item("Duplicate", EditItem.DUPLICATE, KEY_MASK_CTRL | KEY_D)
	menu.add_item("Delete", EditItem.DELETE, KEY_DELETE)


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


func _on_edit_menu_id_pressed(id: int) -> void:
	var selected := features.feature_tree.get_selected_node()
	match id:
		EditItem.UNDO: features.undo()
		EditItem.REDO: features.redo()
		EditItem.CUT: features._on_cut_pressed()
		EditItem.COPY: features._on_copy_pressed()
		EditItem.PASTE: features._on_paste_pressed()
		EditItem.DUPLICATE: features.duplicate_node(selected)
		EditItem.DELETE: features.delete_node(selected)


# What the Edit menus offer, following the feature tree toolbar. The globe menu
# holds two of the same items, so it is updated from here as well.
func _update_edit_menu() -> void:
	if edit_menu == null:
		return
	var selected := features.feature_tree.get_selected_node()
	var is_node := selected != null and not selected.is_root
	var pasteable := Document.APPLICATION in DisplayServer.clipboard_get()
	var disabled := {
		EditItem.UNDO: not document.can_undo(),
		EditItem.REDO: not document.can_redo(),
		EditItem.CUT: not is_node,
		EditItem.COPY: not is_node,
		EditItem.PASTE: not pasteable,
		EditItem.DUPLICATE: not is_node,
		EditItem.DELETE: not is_node,
	}
	for menu in [edit_menu, globe_menu]:
		for item in disabled:
			var index: int = menu.get_item_index(item)
			if index >= 0:
				menu.set_item_disabled(index, disabled[item])


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
	if not isolated:
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
	if not isolated:
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
	refresh_geometry()


func _update_document_labels() -> void:
	var marker := "*" if document.is_dirty() else ""
	get_window().title = "%s%s — %s" % [marker, document.display_name(), APPLICATION_NAME]
	# The name only: the whole path would make the status bar jump about.
	status_file.text = "%s%s" % [marker, document.display_name()]
	status_file.tooltip_text = document.path


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

	animation_dialog = AcceptDialog.new()
	animation_dialog.name = "AnimationDialog"
	animation_dialog.title = "Animation"
	animation_dialog.add_child(_build_animation_content())
	animation_dialog.confirmed.connect(_on_animation_confirmed)
	add_child(animation_dialog)


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
		"Earth texture: [url=%s]4K Ultra HD World Map Wallpaper[/url]." % EARTH_TEXTURE_URL,
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


# How playback walks the timeline: where it starts and ends, how far one frame
# moves, how fast the frames come, and what happens at the two ends.
func _build_animation_content() -> Control:
	var form := GridContainer.new()
	form.name = "Animation"
	form.columns = 2
	form.custom_minimum_size = Vector2(360, 0)

	_animation_spin(form, "start", "Start (Ma)", 0.0, Document.MAX_TIME, 1.0)
	_animation_spin(form, "end", "End (Ma)", 0.0, Document.MAX_TIME, 1.0)
	_animation_spin(form, "increment", "Increment (My)", 0.0001, Document.MAX_TIME, 0.0001)
	_animation_spin(form, "frames_per_second", "Frames per second", 0.1, 240.0, 0.1)

	var loop_check := CheckBox.new()
	loop_check.name = "Loop"
	loop_check.text = "Start again at the end"
	form.add_child(Label.new())
	form.add_child(loop_check)
	animation_fields["loop"] = loop_check

	var land_check := CheckBox.new()
	land_check.name = "LandOnEnd"
	land_check.text = "Land exactly on the end time"
	form.add_child(Label.new())
	form.add_child(land_check)
	animation_fields["land_on_end"] = land_check

	return form


func _animation_spin(form: GridContainer, field: String, text: String,
		low: float, high: float, step: float) -> void:
	var spin := SpinBox.new()
	spin.name = field.to_pascal_case()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = text
	form.add_child(label)
	form.add_child(spin)
	animation_fields[field] = spin


func _show_animation_dialog() -> void:
	var settings := timeline.animation
	for field in animation_fields:
		var control: Control = animation_fields[field]
		if control is SpinBox:
			(control as SpinBox).value = float(settings.get(field))
		else:
			(control as CheckBox).button_pressed = bool(settings.get(field))
	animation_dialog.popup_centered()


func _on_animation_confirmed() -> void:
	var settings := AnimationSettings.new()
	for field in animation_fields:
		var control: Control = animation_fields[field]
		if control is SpinBox:
			settings.set(field, (control as SpinBox).value)
		else:
			settings.set(field, (control as CheckBox).button_pressed)
	var problem := settings.problem()
	if not problem.is_empty():
		_show_error(problem)
		return
	timeline.set_animation(settings)


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


# Put the window back the way the last session left it. The caller decides
# whether the session is remembered at all.
func _restore_session() -> void:
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
	_update_kind_selector(node)
	properties.show_node(node)

	if is_leaf:
		# Auto-select Draw when the feature has no geometry yet
		if not node.has_geometry():
			set_active_tool(Tool.DRAW)
	else:
		# Can't draw on groups or nothing — force Move
		if active_tool == Tool.DRAW:
			set_active_tool(Tool.MOVE)

	_update_move_enabled()
	timeline.show_keyframes(node)
	refresh_geometry()


### Geometry kind


# One entry per kind, with the kind itself as the item id.
func _build_kind_selector() -> void:
	kind_selector.clear()
	for kind in Feature.KIND_NAMES:
		kind_selector.add_item(str(Feature.KIND_NAMES[kind]).capitalize(), kind)
	kind_selector.select(kind_selector.get_item_index(Feature.GeometryKind.POLYGON))
	kind_selector.item_selected.connect(func(_index: int) -> void: _refresh_outline())
	_update_kind_selector(null)


# The kind the Draw tool will produce. A feature that already holds geometry
# keeps its kind, so the selector then shows it and cannot be changed.
func drawing_kind() -> Feature.GeometryKind:
	return kind_selector.get_item_id(kind_selector.selected) as Feature.GeometryKind


# The kinds the selected feature may be drawn in: what its type allows, and only
# the kind it already holds once there is geometry to keep consistent.
func _update_kind_selector(node: Feature) -> void:
	var is_leaf := node != null and not node.is_group
	var has_geometry := is_leaf and node.has_geometry()
	for index in kind_selector.item_count:
		var kind_name: String = Feature.KIND_NAMES[kind_selector.get_item_id(index)]
		kind_selector.set_item_disabled(index,
			is_leaf and not FeatureType.allows(node.feature_type, kind_name))
	if has_geometry:
		kind_selector.select(kind_selector.get_item_index(node.geometry_kind))
	elif is_leaf and kind_selector.is_item_disabled(kind_selector.selected):
		kind_selector.select(_first_allowed_kind())
	kind_selector.disabled = has_geometry or not is_leaf


func _first_allowed_kind() -> int:
	for index in kind_selector.item_count:
		if not kind_selector.is_item_disabled(index):
			return index
	return kind_selector.selected


### Move tool


# A group can be dragged as well as a feature, because a group carries motion
# its children inherit. The root is left out: it holds everything, so turning it
# would only turn the globe, which the view already does.
func _update_move_enabled() -> void:
	var selected := features.feature_tree.get_selected_node()
	planet_view.move_enabled = active_tool == Tool.MOVE and selected != null \
		and not selected.is_root and selected.holds_geometry()


# The point that was grabbed and the rotation the dragged node had when the drag
# started, both in the frame its parent gives it, so an inherited rotation is
# neither undone nor applied twice. The keyframes it started with come back if
# the drag is cancelled.
var move_anchor_local: Vector3
var move_base_rot: Vector3
var move_parent_inverse := Basis()
var move_base_keyframes: Array[Keyframe] = []


func _on_move_started(anchor_lat: float, anchor_lon: float) -> void:
	var selected := features.feature_tree.get_selected_node()
	if selected == null or selected.is_root:
		return
	move_base_keyframes = Keyframe.clone_list(selected.keyframes)
	move_parent_inverse = Feature.world_basis(
		features.root, features.root.find_parent(selected), document.current_time).transposed()
	move_base_rot = selected.rotation_at(document.current_time)
	move_anchor_local = move_parent_inverse * Feature._latlon_to_xyz_s(Vector2(anchor_lat, anchor_lon))


# Dragging writes the keyframe at the current time as it goes, so what is on the
# globe is what will be committed. Only the release records an undo version.
func _on_move_to(lat: float, lon: float) -> void:
	var selected := features.feature_tree.get_selected_node()
	if selected == null or selected.is_root:
		return
	var target_local := move_parent_inverse * Feature._latlon_to_xyz_s(Vector2(lat, lon))
	var new_rot: Variant = Feature.compute_move_rotation(move_anchor_local, target_local, move_base_rot)
	if new_rot != null:
		Keyframe.upsert(selected.keyframes, document.current_time, new_rot)
		refresh_motion()


func _on_move_ended() -> void:
	document.record()
	features.reload()
	var selected := features.feature_tree.get_selected_node()
	properties.show_node(selected)
	timeline.show_keyframes(selected)
	refresh_geometry()


func _on_move_cancelled() -> void:
	var selected := features.feature_tree.get_selected_node()
	if selected != null and not selected.is_root:
		selected.keyframes = move_base_keyframes
	refresh_motion()


### Drawing


# The shape being drawn, in world space, before it is committed to a feature.
var outline_vertices := PackedVector2Array()

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
			outline_vertices.remove_at(outline_vertices.size() - 1)
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
	var selected := features.feature_tree.get_selected_node()
	if selected == null or selected.is_group:
		return
	var kind: Feature.GeometryKind = drawing_kind()
	if outline_vertices.size() < int(Feature.MINIMUM_VERTICES[kind]):
		return

	# The vertices were clicked in world space; a feature keeps its own frame,
	# which at the current time is where its keyframes and its groups' put it.
	var into_local := Feature.world_basis(
		features.root, selected, document.current_time).transposed()
	selected.add_ring(Feature.apply_basis(outline_vertices, into_local), kind)

	outline_vertices = PackedVector2Array()
	document.record()
	features.reload()
	refresh_geometry()
	set_active_tool(Tool.MOVE)


func _outline_cancel() -> void:
	outline_vertices = PackedVector2Array()
	_refresh_selection_outline()


func _refresh_outline() -> void:
	planet_view.planet.set_outline([{
		"vertices": outline_vertices,
		"style": _drawing_outline_style(),
	}])


# How the shape being drawn is shown. A polygon gets a faint closing segment,
# so it is clear that the shape is not finished; a multipoint gets markers only.
func _drawing_outline_style() -> Planet.OutlineStyle:
	match drawing_kind():
		Feature.GeometryKind.MULTIPOINT:
			return Planet.OutlineStyle.POINTS
		Feature.GeometryKind.POLYGON:
			if outline_vertices.size() >= 3:
				return Planet.OutlineStyle.CLOSED_PREVIEW
	return Planet.OutlineStyle.OPEN


### Craton interaction


func _on_craton_clicked(lat: float, lon: float) -> void:
	var hit := Planet.hit_test(lat, lon, geometry)
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


# A right click offers the Edit commands for whatever is under the pointer,
# selecting it first so the menu and the feature tree agree on the target.
func _on_craton_context_menu(lat: float, lon: float) -> void:
	var hit := Planet.hit_test(lat, lon, geometry)
	if hit != null:
		features.feature_tree.select_node(hit)
	_update_edit_menu()
	globe_menu.position = get_window().position + Vector2i(get_viewport().get_mouse_position())
	globe_menu.reset_size()
	globe_menu.popup()


func _on_craton_hovered(lat: float, lon: float) -> void:
	var new_hovered: Feature = null
	if not is_nan(lat):
		new_hovered = Planet.hit_test(lat, lon, geometry)
	if new_hovered != hovered_feature:
		hovered_feature = new_hovered
		planet_view.planet.set_feature_state(geometry, hovered_feature)


### Geometry rendering


func refresh_geometry() -> void:
	geometry = Planet.collect_geometry(features.root, document.current_time)
	planet_view.planet.set_geometry(geometry)
	refresh_motion()


# Where the features sit at the current time, without rebuilding the geometry
# itself. This is what a step of an animation and a drag of the Move tool cost:
# one small texture, whatever the triangle count is.
func refresh_motion() -> void:
	geometry.resolve(features.root, document.current_time)
	planet_view.planet.set_feature_state(geometry, hovered_feature)
	_refresh_selection_outline()


# Trace the selected feature over the geometry: its rings, one outline part
# each, in the same yellow the shape being drawn is shown in.
func _refresh_selection_outline() -> void:
	# Don't overwrite the drawing outline
	if not outline_vertices.is_empty():
		return
	var selected := features.feature_tree.get_selected_node()
	if selected == null or selected.is_group or not selected.has_geometry():
		planet_view.planet.set_outline([])
		return

	var style := Planet.OutlineStyle.OPEN
	match selected.geometry_kind:
		Feature.GeometryKind.POLYGON:
			style = Planet.OutlineStyle.CLOSED
		Feature.GeometryKind.MULTIPOINT:
			style = Planet.OutlineStyle.POINTS

	var m := Feature.world_basis(features.root, selected, document.current_time)
	var parts: Array = []
	for ring in selected.rings:
		parts.append({
			"vertices": Feature.apply_basis(ring, m),
			"style": style,
		})
	planet_view.planet.set_outline(parts)


func _on_program_changed() -> void:
	refresh_geometry()


# Only where things are has changed, so the geometry itself is left alone. The
# tree greys out whatever is outside its time range and the Properties panel
# follows the time in its keyframe list.
func _on_time_changed() -> void:
	refresh_motion()
	features.feature_tree.refresh_time(document.current_time)
	properties.show_time()


# An edit made in the Properties panel: the tree row and the globe follow it,
# and so does the Draw tool, whose kinds depend on the type that may have moved.
func _on_properties_edited() -> void:
	features.reload()
	var selected := features.feature_tree.get_selected_node()
	_update_kind_selector(selected)
	timeline.show_keyframes(selected)
	refresh_geometry()

