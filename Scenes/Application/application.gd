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
# What a backdrop image may be, taken from the formats Backdrop reads rather
# than listed a second time here.
static var IMAGE_FILTERS := PackedStringArray(
	["*.%s ; Images" % ", *.".join(Backdrop.EXTENSIONS)])

# Answers a file dialog without showing one. Set by the automation port so a
# scripted run can drive Open and Save As; unset in a normal run.
static var file_dialog_hook: Callable

enum Tool { MOVE, DRAW, VERTEX, MEASURE, CIRCLE, TOPOLOGY, LIGHT }

# How near, in window pixels, a click has to be to take hold of a vertex or an
# edge, and how near a dragged vertex has to come to another before snapping
# takes it the rest of the way. Pixels rather than a distance on the sphere, so
# a tool behaves the same however far the view is zoomed in.
const VERTEX_PICK_PIXELS := 12.0
const SNAP_PIXELS := 12.0

enum FileItem { NEW, OPEN, SAVE, SAVE_AS, PREFERENCES, QUIT }
enum EditItem { UNDO, REDO, CUT, COPY, PASTE, DUPLICATE, DELETE }
enum ViewItem { FEATURES, PROPERTIES, TIMELINE, STATUS_BAR, SETTINGS, FULL_SCREEN }
enum HelpItem { DOCUMENTATION, ABOUT }

# Item id of the entry that empties the recent file list; above any file index.
const CLEAR_RECENT_ID := 1000

# Item id of the globe in the projection selector, above every MapProjection.Kind.
const GLOBE_PROJECTION_ID := 100

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
@onready var vertex_button: Button = %Vertex
@onready var measure_button: Button = %Measure
@onready var circle_button: Button = %Circle
@onready var topology_button: Button = %Topology
@onready var light_button: Button = %Light
@onready var snap_button: Button = %Snap
@onready var split_button: Button = %Split
@onready var kind_selector: OptionButton = %GeometryKind
@onready var segments_spin: SpinBox = %Segments
@onready var projection_selector: OptionButton = %Projection
@onready var zoom_spin: SpinBox = %Zoom
@onready var zoom_in_button: Button = %ZoomIn
@onready var zoom_out_button: Button = %ZoomOut
@onready var zoom_reset_button: Button = %ZoomReset
@onready var camera_latitude_spin: SpinBox = %CameraLatitude
@onready var camera_longitude_spin: SpinBox = %CameraLongitude
@onready var rotate_anticlockwise_button: Button = %RotateAnticlockwise
@onready var rotate_clockwise_button: Button = %RotateClockwise
@onready var camera_reset_button: Button = %CameraReset
@onready var menu_bar: MenuBar = %MenuBar
@onready var left_splitter: HSplitContainer = %LeftSplitter
@onready var right_splitter: HSplitContainer = %RightSplitter
@onready var properties: Properties = %Properties
@onready var timeline: Timeline = %Timeline
@onready var status_bar: Control = %StatusBar
@onready var status_coordinates: Label = %StatusCoordinates
@onready var status_measure: Label = %StatusMeasure
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

# Where the pointer last was on the globe, NAN when it is off it. Kept so the
# hover can be worked out again when the features move under a pointer that is
# standing still, which a change of the current time does.
var hovered_lat: float = NAN
var hovered_lon: float = NAN

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
var radius_spin: SpinBox
var marker_spin: SpinBox
var line_spin: SpinBox
var view_dialog: AcceptDialog
# Why the backdrop image is not on the planet, shown under the path field.
var backdrop_warning: Label
# The fields of the View settings dialog, by the name of the setting each edits.
var view_fields: Dictionary = {}
var animation_dialog: AcceptDialog
# The fields of the animation dialog, by the name of the setting each one edits.
var animation_fields: Dictionary = {}

# The image on the planet, and the path it was read from, so that changing the
# opacity or the visibility does not read the file again. `backdrop.error` says
# why there is no image when there is none.
var backdrop := Backdrop.new()
var _backdrop_path: String = ""

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
	move_button.pressed.connect(func() -> void: set_active_tool(Tool.MOVE))
	draw_button.pressed.connect(func() -> void: set_active_tool(Tool.DRAW))
	vertex_button.pressed.connect(func() -> void: set_active_tool(Tool.VERTEX))
	measure_button.pressed.connect(func() -> void: set_active_tool(Tool.MEASURE))
	circle_button.pressed.connect(func() -> void: set_active_tool(Tool.CIRCLE))
	topology_button.pressed.connect(func() -> void: set_active_tool(Tool.TOPOLOGY))
	light_button.pressed.connect(func() -> void: set_active_tool(Tool.LIGHT))
	segments_spin.value_changed.connect(func(_value: float) -> void: _refresh_selection_outline())
	snap_button.toggled.connect(_on_snap_toggled)
	split_button.pressed.connect(func() -> void: _report(split_at_selected_vertex()))
	snap_button.button_pressed = Config.get_snap_to_vertices()
	_build_kind_selector()
	# The range and the starting value come from SmallCircle, so the scene does
	# not carry a second copy of what a circle may be cut into.
	segments_spin.min_value = SmallCircle.MIN_SEGMENTS
	segments_spin.max_value = SmallCircle.MAX_SEGMENTS
	segments_spin.value = SmallCircle.DEFAULT_SEGMENTS
	_apply_outline_scale()
	_build_view_toolbar()
	_apply_default_view()
	apply_view_settings()

	# The Save and Load buttons of the feature tree toolbar run the File commands
	features.save_button.pressed.connect(save_document)
	features.load_button.pressed.connect(open_document)

	# Connect feature selection from the features panel
	features.feature_tree.feature_selected.connect(_on_feature_selected)

	# Connect planet click events for the tools that take clicks for themselves
	planet_view.input_event_globe.connect(_on_planet_input)
	planet_view.input_event_map.connect(_on_planet_input)
	planet_view.input_event_outside.connect(_on_planet_input_outside)

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


# The view toolbar follows the view rather than driving it alone: the wheel, a
# drag of the globe and the automation port all move the camera without going
# near the fields, and this is what puts the numbers back.
func _process(_delta: float) -> void:
	_update_view_toolbar()


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
	view_menu.add_item("View Settings...", ViewItem.SETTINGS)
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
	if id == ViewItem.SETTINGS:
		show_view_settings()
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
	_confirm_unsaved_changes(_reset_document)


# An empty document, drawn the way the preferences say a new one should be.
func _reset_document() -> void:
	document.reset(Config.get_view_defaults())
	_apply_default_view()


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


func _on_root_replaced(same_document: bool) -> void:
	# Undo and redo put another version of the same document in place, which is
	# no reason to take a tool out of someone's hand mid edit. A new or opened
	# document is: whatever was half drawn or half picked belonged to the one
	# being left behind.
	if not same_document:
		set_active_tool(Tool.MOVE)
		apply_view_settings()
	refresh_geometry()


# Draw the scene the way the open document asks for. Called when a document
# arrives and after every change to its view settings.
func apply_view_settings() -> void:
	_load_backdrop()
	planet_view.apply_view_settings(document.view)
	if view_dialog.visible:
		backdrop_warning.text = backdrop.error


# Put the image the document names on the planet. The file is read only when the
# path it resolves to changes, so dragging the opacity does not read it again.
#
# An image that cannot be read is not a failure of the document: the planet
# keeps the built in Earth, the reason is pushed as a warning and the View
# settings dialog shows it beside the path.
func _load_backdrop() -> void:
	var path := document.resolve_backdrop()
	if path != _backdrop_path:
		_backdrop_path = path
		backdrop = Backdrop.load_from(path)
		if not backdrop.error.is_empty():
			push_warning(backdrop.error)
	planet_view.planet.set_backdrop(backdrop.texture,
		document.view.backdrop_opacity if document.view.backdrop_visible else 0.0)


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

	view_dialog = AcceptDialog.new()
	view_dialog.name = "ViewDialog"
	view_dialog.title = "View settings"
	view_dialog.add_child(_build_view_content())
	add_child(view_dialog)

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

	var form := GridContainer.new()
	form.columns = 2
	box.add_child(form)

	radius_spin = _preference_spin(form, "PlanetRadius", "Planet radius (km)",
		Measure.MIN_RADIUS_KM, Measure.MAX_RADIUS_KM, 1.0)
	marker_spin = _preference_spin(form, "VertexMarkerScale", "Vertex marker size",
		Config.MIN_SCALE, Config.MAX_SCALE, 0.05)
	line_spin = _preference_spin(form, "LineWidthScale", "Outline line width",
		Config.MIN_SCALE, Config.MAX_SCALE, 0.05)

	return box


func _preference_spin(form: GridContainer, name: String, text: String,
		low: float, high: float, step: float) -> SpinBox:
	var label := Label.new()
	label.text = text
	form.add_child(label)
	var spin := SpinBox.new()
	spin.name = name
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.custom_minimum_size = Vector2(140, 0)
	form.add_child(spin)
	return spin


# How playback walks the timeline: where it starts and ends, how far one frame
# moves, how fast the frames come, and what happens at the two ends.
# The scene around the features: what is behind the planet, what is drawn over
# it, where the light comes from and which image the planet wears. Every field
# takes effect as it is changed rather than when the dialog is closed, so the
# planet under it shows what is being chosen.
func _build_view_content() -> Control:
	var box := VBoxContainer.new()
	box.name = "ViewSettings"
	box.custom_minimum_size = Vector2(460, 0)

	var form := GridContainer.new()
	form.columns = 2
	box.add_child(form)

	_view_color(form, "background_color", "Background")
	_view_check(form, "star_field", "Star field")
	_view_color(form, "graticule_color", "Graticule")
	_view_spin(form, "graticule_spacing", "Graticule spacing (°)",
		ViewSettings.MIN_SPACING, ViewSettings.MAX_SPACING, 1.0)
	_view_spin(form, "light_elevation", "Light elevation (°)",
		-ViewSettings.MAX_ELEVATION, ViewSettings.MAX_ELEVATION, 1.0)
	_view_spin(form, "light_azimuth", "Light azimuth (°)", -180.0, 180.0, 1.0)
	_view_spin(form, "ambient", "Ambient light",
		ViewSettings.MIN_AMBIENT, ViewSettings.MAX_AMBIENT, 0.05)
	_view_check(form, "backdrop_visible", "Backdrop image shown")
	_view_spin(form, "backdrop_opacity", "Backdrop opacity", 0.0, 1.0, 0.05)

	var label := Label.new()
	label.text = "Backdrop image"
	box.add_child(label)

	var row := HBoxContainer.new()
	box.add_child(row)
	var edit := LineEdit.new()
	edit.name = "BackdropPath"
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.placeholder_text = "The built in Earth"
	edit.text_submitted.connect(func(_text: String) -> void: _on_view_field_changed())
	edit.focus_exited.connect(_on_view_field_changed)
	row.add_child(edit)
	view_fields["backdrop_path"] = edit

	var browse := Button.new()
	browse.name = "BrowseBackdrop"
	browse.text = "Browse..."
	browse.pressed.connect(choose_backdrop)
	row.add_child(browse)

	var clear := Button.new()
	clear.name = "ClearBackdrop"
	clear.text = "Clear"
	clear.pressed.connect(func() -> void:
		edit.text = ""
		_on_view_field_changed())
	row.add_child(clear)

	var defaults := HBoxContainer.new()
	box.add_child(defaults)
	var remember := Button.new()
	remember.name = "SaveAsDefault"
	remember.text = "Save as default"
	remember.tooltip_text = "Start every new document with these settings"
	remember.pressed.connect(func() -> void:
		Config.set_view_defaults(document.view)
		Config.set_default_view(projection_selector.get_item_text(
			projection_selector.selected)))
	defaults.add_child(remember)

	var restore := Button.new()
	restore.name = "RestoreDefaults"
	restore.text = "Restore defaults"
	restore.tooltip_text = "Put this document back to the settings a new one starts with"
	restore.pressed.connect(func() -> void:
		document.view = Config.get_view_defaults()
		document.view_edited()
		_fill_view_fields()
		apply_view_settings())
	defaults.add_child(restore)

	backdrop_warning = Label.new()
	backdrop_warning.name = "BackdropWarning"
	backdrop_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	backdrop_warning.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	box.add_child(backdrop_warning)

	return box


func _view_spin(form: GridContainer, key: String, text: String,
		low: float, high: float, step: float) -> void:
	var spin := _preference_spin(form, key.to_pascal_case(), text, low, high, step)
	spin.value_changed.connect(func(_value: float) -> void: _on_view_field_changed())
	view_fields[key] = spin


func _view_check(form: GridContainer, key: String, text: String) -> void:
	var label := Label.new()
	label.text = text
	form.add_child(label)
	var check := CheckBox.new()
	check.name = key.to_pascal_case()
	check.toggled.connect(func(_pressed: bool) -> void: _on_view_field_changed())
	form.add_child(check)
	view_fields[key] = check


func _view_color(form: GridContainer, key: String, text: String) -> void:
	var label := Label.new()
	label.text = text
	form.add_child(label)
	var button := ColorPickerButton.new()
	button.name = key.to_pascal_case()
	button.custom_minimum_size = Vector2(140, 28)
	button.color_changed.connect(func(_color: Color) -> void: _on_view_field_changed())
	form.add_child(button)
	view_fields[key] = button


# Pick the image the planet wears. It is stored relative to the project file
# when it sits beside it, so a project and its images can be moved together.
func choose_backdrop() -> void:
	_ask_for_path(DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, "Backdrop image",
		func(path: String) -> void:
			view_fields["backdrop_path"].text = Document.relative_backdrop(path, document.path)
			_on_view_field_changed(),
		IMAGE_FILTERS)


func show_view_settings() -> void:
	_fill_view_fields()
	backdrop_warning.text = backdrop.error
	view_dialog.popup_centered()


# Put what the document holds into the fields, without firing the signals that
# would write them straight back.
func _fill_view_fields() -> void:
	var settings := document.view
	view_fields["background_color"].color = settings.background_color
	view_fields["star_field"].set_pressed_no_signal(settings.star_field)
	view_fields["graticule_color"].color = settings.graticule_color
	view_fields["graticule_spacing"].set_value_no_signal(settings.graticule_spacing)
	view_fields["light_elevation"].set_value_no_signal(settings.light_direction.x)
	view_fields["light_azimuth"].set_value_no_signal(settings.light_direction.y)
	view_fields["ambient"].set_value_no_signal(settings.ambient)
	view_fields["backdrop_visible"].set_pressed_no_signal(settings.backdrop_visible)
	view_fields["backdrop_opacity"].set_value_no_signal(settings.backdrop_opacity)
	view_fields["backdrop_path"].text = settings.backdrop_path


# One field moved: take the whole block off the dialog and hand it to the
# document, so the planet follows while the dialog is still open.
func _on_view_field_changed() -> void:
	var settings := document.view
	settings.background_color = view_fields["background_color"].color
	settings.star_field = view_fields["star_field"].button_pressed
	settings.graticule_color = view_fields["graticule_color"].color
	settings.graticule_spacing = view_fields["graticule_spacing"].value
	settings.light_direction = ViewSettings.clamp_light(Vector2(
		view_fields["light_elevation"].value, view_fields["light_azimuth"].value))
	settings.ambient = view_fields["ambient"].value
	settings.backdrop_visible = view_fields["backdrop_visible"].button_pressed
	settings.backdrop_opacity = view_fields["backdrop_opacity"].value
	settings.backdrop_path = view_fields["backdrop_path"].text
	document.view_edited()
	apply_view_settings()


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
	radius_spin.value = Config.get_planet_radius()
	marker_spin.value = Config.get_vertex_marker_scale()
	line_spin.value = Config.get_line_width_scale()
	preferences_dialog.popup_centered()


func _on_preferences_confirmed() -> void:
	Config.set_last_directory(default_folder_edit.text)
	Config.set_value("restore_session", restore_session_check.button_pressed)
	Config.set_planet_radius(radius_spin.value)
	Config.set_vertex_marker_scale(marker_spin.value)
	Config.set_line_width_scale(line_spin.value)
	_apply_outline_scale()
	_show_measurement()


# Give the outline overlay the sizes the preferences ask for.
func _apply_outline_scale() -> void:
	planet_view.planet.set_outline_scale(
		Config.get_vertex_marker_scale(), Config.get_line_width_scale())


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
func _ask_for_path(mode: int, title: String, on_path: Callable,
		filters: PackedStringArray = FILE_FILTERS) -> void:
	if file_dialog_hook.is_valid():
		file_dialog_hook.call(mode, title, on_path)
		return
	DisplayServer.file_dialog_show(
		title,
		Config.get_last_directory(),
		"",
		false,
		mode,
		filters,
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


func set_active_tool(tool: Tool) -> void:
	if active_tool == Tool.DRAW and tool != Tool.DRAW:
		_outline_cancel()
	if active_tool == Tool.VERTEX and tool != Tool.VERTEX:
		_vertex_cancel_drag()
		_let_every_vertex_go()
	if active_tool == Tool.MEASURE and tool != Tool.MEASURE:
		_measure_clear()
	if active_tool == Tool.CIRCLE and tool != Tool.CIRCLE:
		circle_points = PackedVector2Array()
	if active_tool == Tool.LIGHT and tool != Tool.LIGHT:
		_light_dragging = false
	active_tool = tool
	move_button.button_pressed = (tool == Tool.MOVE)
	draw_button.button_pressed = (tool == Tool.DRAW)
	vertex_button.button_pressed = (tool == Tool.VERTEX)
	measure_button.button_pressed = (tool == Tool.MEASURE)
	circle_button.button_pressed = (tool == Tool.CIRCLE)
	topology_button.button_pressed = (tool == Tool.TOPOLOGY)
	light_button.button_pressed = (tool == Tool.LIGHT)
	planet_view.tool_handles_clicks = tool != Tool.MOVE
	_update_move_enabled()
	_update_tool_buttons()
	_refresh_selection_outline()
	_show_measurement()


func _on_snap_toggled(enabled: bool) -> void:
	Config.set_snap_to_vertices(enabled)


func snapping() -> bool:
	return snap_button.button_pressed


# The Vertex tool needs a leaf feature holding vertices of its own; there is
# nothing to take hold of otherwise, and a topology's vertices belong to the
# features it runs along. Measure needs nothing at all.
func _update_tool_buttons() -> void:
	var selected := features.feature_tree.get_selected_node()
	var editable := selected != null and not selected.is_group and selected.has_own_vertices()
	vertex_button.disabled = not editable
	snap_button.disabled = active_tool != Tool.VERTEX
	split_button.disabled = not _split_problem().is_empty()
	split_button.tooltip_text = _split_tooltip()


### Feature selection


func _on_feature_selected(node: Feature) -> void:
	# Clear any in-progress outline when switching features
	if not outline_vertices.is_empty():
		_outline_cancel()
	# The vertex the Vertex tool was holding belonged to whichever feature is
	# being left, so it only survives a reselection of the same one. Undo, redo
	# and every reload replace the tree with a clone, so the node that comes
	# back is a different object with the same pnid.
	if node == null or node.pnid != vertex_feature_pnid:
		_vertex_cancel_drag()
		hovered_vertex = NO_VERTEX
		selected_vertex = NO_VERTEX
		split_from = NO_VERTEX
		vertex_feature_pnid = -1 if node == null else node.pnid
	_forget_vertices_that_are_gone(node)

	# A group has no vertices to edit, so the Vertex tool falls back to Move.
	# Nothing selected does not: rebuilding the tree clears the selection for a
	# moment before it puts it back, and a tool that gave up over that would
	# not survive an undo.
	var editable := node == null or (not node.is_group and node.has_own_vertices())
	if active_tool == Tool.VERTEX and not editable:
		set_active_tool(Tool.MOVE)

	var is_leaf := node != null and not node.is_group
	draw_button.disabled = not _can_draw(node)
	circle_button.disabled = not _can_draw(node)
	topology_button.disabled = not _can_build_topology(node)
	_update_kind_selector(node)
	properties.show_node(node)

	if is_leaf:
		# A tool that cannot work on what is now selected gives way to Move,
		# rather than staying armed and swallowing the clicks meant for the
		# globe. Nothing selected is left alone: rebuilding the tree clears the
		# selection for a moment before it puts it back.
		if (active_tool == Tool.DRAW or active_tool == Tool.CIRCLE) and not _can_draw(node):
			set_active_tool(Tool.MOVE)
		elif active_tool == Tool.TOPOLOGY and not _can_build_topology(node):
			set_active_tool(Tool.MOVE)
		# Auto-select Draw when the feature has no geometry yet
		elif not node.has_geometry() and _can_draw(node):
			set_active_tool(Tool.DRAW)
	else:
		# Can't draw or build a topology on groups or nothing — force Move
		if active_tool == Tool.DRAW or active_tool == Tool.CIRCLE \
				or active_tool == Tool.TOPOLOGY:
			set_active_tool(Tool.MOVE)

	_update_move_enabled()
	_update_tool_buttons()
	timeline.show_keyframes(node)
	refresh_geometry()
	_show_measurement()


### Geometry kind


# One entry per kind, with the kind itself as the item id.
### The view toolbar: what the planet is drawn as, and where the camera stands


# How far the view turns for one press of the clockwise or anticlockwise button.
const ROTATION_STEP := 15.0


func _build_view_toolbar() -> void:
	# The globe first, then the five map projections in MapProjection.Kind's own
	# order, so the id of an item is the projection it selects and the globe has
	# an id of its own, above all of them.
	projection_selector.clear()
	projection_selector.add_item("Globe", GLOBE_PROJECTION_ID)
	for kind in MapProjection.NAMES.size():
		projection_selector.add_item(str(MapProjection.NAMES[kind]), kind)
	projection_selector.item_selected.connect(_on_projection_selected)

	zoom_in_button.pressed.connect(planet_view.zoom_in)
	zoom_out_button.pressed.connect(planet_view.zoom_out)
	zoom_reset_button.pressed.connect(planet_view.reset_zoom)
	zoom_spin.value_changed.connect(
		func(value: float) -> void: planet_view.set_zoom(value / 100.0))

	camera_latitude_spin.value_changed.connect(
		func(value: float) -> void: planet_view.planet.lat = value)
	camera_longitude_spin.value_changed.connect(
		func(value: float) -> void: planet_view.planet.lon = value)
	rotate_clockwise_button.pressed.connect(
		func() -> void: _turn_view(ROTATION_STEP))
	rotate_anticlockwise_button.pressed.connect(
		func() -> void: _turn_view(-ROTATION_STEP))
	camera_reset_button.pressed.connect(planet_view.reset_camera)

	_update_view_toolbar()


# Open in the view the preferences ask for. A name the selector no longer offers
# is not an error: the globe is what a fresh installation shows.
func _apply_default_view() -> void:
	var wanted := Config.get_default_view()
	for index in projection_selector.item_count:
		if projection_selector.get_item_text(index) == wanted:
			projection_selector.select(index)
			_on_projection_selected(index)
			return


func _on_projection_selected(index: int) -> void:
	var id := projection_selector.get_item_id(index)
	planet_view.planet.show_map = id != GLOBE_PROJECTION_ID
	if id != GLOBE_PROJECTION_ID:
		planet_view.planet.projection = id as MapProjection.Kind


func _turn_view(degrees: float) -> void:
	planet_view.planet.angle = wrapf(planet_view.planet.angle + degrees, -180.0, 180.0)


# Put back what the view is actually showing. The wheel, a drag of the globe and
# the automation port all change it behind the toolbar's back, so the fields are
# followed rather than trusted; setting a value without firing the signal that
# would write it straight back is what set_value_no_signal is for.
func _update_view_toolbar() -> void:
	var planet := planet_view.planet
	# The light is dragged on the globe, and a map sheet has nowhere to drag it,
	# so the tool is offered on the globe alone and gives way to Move when a map
	# takes over, rather than staying armed and swallowing the clicks.
	light_button.disabled = planet.show_map
	if planet.show_map and active_tool == Tool.LIGHT:
		set_active_tool(Tool.MOVE)
	var id := int(planet.projection) if planet.show_map else GLOBE_PROJECTION_ID
	var index := projection_selector.get_item_index(id)
	if projection_selector.selected != index:
		projection_selector.select(index)
	zoom_spin.set_value_no_signal(planet_view.zoom * 100.0)
	camera_latitude_spin.set_value_no_signal(planet.lat)
	camera_longitude_spin.set_value_no_signal(planet.lon)


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
# the kind it already holds once there is geometry to keep consistent. A
# topology is listed, so a feature holding one shows what it is, but never
# offered: its geometry comes from the features it names rather than from
# clicks, which is the Topology tool's business.
func _update_kind_selector(node: Feature) -> void:
	var is_leaf := node != null and not node.is_group
	var has_geometry := is_leaf and node.has_geometry()
	for index in kind_selector.item_count:
		var kind: int = kind_selector.get_item_id(index)
		var kind_name: String = Feature.KIND_NAMES[kind]
		kind_selector.set_item_disabled(index, not kind in Feature.DRAWN_KINDS
			or (is_leaf and not FeatureType.allows(node.feature_type, kind_name)))
	if has_geometry:
		kind_selector.select(kind_selector.get_item_index(node.geometry_kind))
	elif is_leaf and kind_selector.is_item_disabled(kind_selector.selected):
		var first := _first_allowed_kind()
		if first >= 0:
			kind_selector.select(first)
	kind_selector.disabled = has_geometry or not is_leaf


# The first kind the selector still offers, or -1 when it offers none, which is
# what a type allowing only topologies leaves behind.
func _first_allowed_kind() -> int:
	for index in kind_selector.item_count:
		if not kind_selector.is_item_disabled(index):
			return index
	return -1


# Whether the Topology tool has something to build on: a feature that is a
# topology already, or one holding nothing yet whose type allows it to become
# one. A feature that holds vertices of its own cannot also borrow them.
func _can_build_topology(node: Feature) -> bool:
	if node == null or node.is_group:
		return false
	if node.has_geometry():
		return node.geometry_kind == Feature.GeometryKind.TOPOLOGY
	return FeatureType.allows(node.feature_type, "topology")


# Whether the Draw and Circle tools have a kind they may produce on this
# feature: the one it already holds, once it holds any, and otherwise a kind its
# type allows. A topology is neither, since it is built from other features.
func _can_draw(node: Feature) -> bool:
	if node == null or node.is_group:
		return false
	if node.has_geometry():
		return node.geometry_kind in Feature.DRAWN_KINDS
	for kind in Feature.DRAWN_KINDS:
		if FeatureType.allows(node.feature_type, Feature.KIND_NAMES[kind]):
			return true
	return false


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

# Every input event on the planet, sent to whichever tool takes clicks. The
# Move tool is not here: selecting, dragging and the right click menu are the
# view's own, and it leaves them alone while a tool owns the clicks.
func _on_planet_input(lat: float, lon: float, event: InputEvent) -> void:
	match active_tool:
		Tool.DRAW:
			_on_draw_input(lat, lon, event)
		Tool.VERTEX:
			_on_vertex_input(lat, lon, event)
		Tool.MEASURE:
			_on_measure_input(lat, lon, event)
		Tool.CIRCLE:
			_on_circle_input(lat, lon, event)
		Tool.TOPOLOGY:
			_on_topology_input(lat, lon, event)
		Tool.LIGHT:
			_on_light_input(lat, lon, event)


# The background behind the globe. A drag of a vertex that ends out there is
# still a release, and letting it pass would leave the vertex stuck to the
# pointer.
func _on_planet_input_outside(event: InputEvent) -> void:
	if event is not InputEventMouseButton:
		return
	if event.button_index != MOUSE_BUTTON_LEFT or not event.is_released():
		return
	if active_tool == Tool.VERTEX:
		_vertex_commit_drag()
	elif active_tool == Tool.LIGHT:
		_light_dragging = false


func _on_draw_input(lat: float, lon: float, event: InputEvent) -> void:
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
	if event is not InputEventKey or not event.is_pressed():
		return

	match active_tool:
		Tool.DRAW:
			if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
				_outline_commit()
			elif event.keycode == KEY_ESCAPE:
				_outline_cancel()
			else:
				return
		Tool.VERTEX:
			if event.keycode == KEY_DELETE:
				_report(delete_selected_vertex())
			elif event.keycode == KEY_S:
				_report(hold_split_from() if event.shift_pressed
					else split_at_selected_vertex())
			elif event.keycode == KEY_ESCAPE:
				_vertex_cancel_drag()
				_let_every_vertex_go()
				_update_tool_buttons()
			else:
				return
		Tool.MEASURE:
			if event.keycode == KEY_ESCAPE:
				_measure_clear()
				_refresh_selection_outline()
			else:
				return
		Tool.CIRCLE:
			if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
				_report(_circle_commit())
			elif event.keycode == KEY_ESCAPE:
				circle_points = PackedVector2Array()
				_refresh_selection_outline()
				_show_measurement()
			else:
				return
		_:
			return
	get_viewport().set_input_as_handled()


# Say in the status bar why a tool refused what it was asked to do. An empty
# message is the tool having done it, which needs no telling.
func _report(problem: String) -> void:
	_show_measurement(problem)


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


### The Vertex tool
#
# Editing the vertices of the selected feature on the globe. A click takes hold
# of the vertex under it, or puts a new one on the edge under it; Delete takes
# one out. Every edit maps the click back into the feature's own frame, through
# the inverse of the rotation its keyframes and its groups give it at the
# current time, so an edit made while the feature has moved lands where the
# pointer is rather than where the feature was first drawn.

# The vertex the tool is working on, as (part, index), or NO_VERTEX.
const NO_VERTEX := Vector2i(-1, -1)

var selected_vertex: Vector2i = NO_VERTEX

# The first vertex of a polygon cut, held until the second one is picked.
var split_from: Vector2i = NO_VERTEX

# The vertex the pointer is resting on, or NO_VERTEX. Delete takes this one out
# when there is one, which is what "the vertex under the cursor" means; the one
# picked by a click stands in when the pointer is resting on nothing.
var hovered_vertex: Vector2i = NO_VERTEX


func _track_vertex_under_pointer(feature: Feature, lat: float, lon: float) -> void:
	hovered_vertex = NO_VERTEX
	var screen: Variant = planet_view.latlon_to_screen(lat, lon)
	if screen == null:
		return
	var own := _vertices_on_screen(feature)
	var picked := GeometryEdit.nearest_point(own[0], screen, VERTEX_PICK_PIXELS)
	if picked >= 0:
		hovered_vertex = own[1][picked]


# The vertex the tool would act on: the one under the pointer, or the one a
# click last took hold of when the pointer is resting on nothing.
func vertex_in_hand() -> Vector2i:
	return hovered_vertex if hovered_vertex != NO_VERTEX else selected_vertex


# The vertex being dragged, the feature it belongs to, and what it was before
# the drag started, so that a cancelled drag puts it back and a finished one
# records a single undo version rather than one for every frame of the drag.
#
# The feature is held rather than looked up: a drag ends for reasons other than
# a release, selecting another feature among them, and putting the vertex back
# into whatever happens to be selected then would write it into the wrong shape.
var vertex_drag: Vector2i = NO_VERTEX
var vertex_drag_feature: Feature = null
var vertex_drag_was := Vector2.ZERO


# Whether the dragged vertex is still where it was taken hold of. An undo, or a
# reload that replaced the tree, can leave the drag pointing at a ring that is
# shorter than it was or gone altogether.
func _drag_is_live() -> bool:
	if vertex_drag == NO_VERTEX or vertex_drag_feature == null:
		return false
	if vertex_drag.x >= vertex_drag_feature.rings.size():
		return false
	return vertex_drag.y < vertex_drag_feature.rings[vertex_drag.x].size()

# Which feature the picked vertex belongs to, by pnid rather than by object:
# undo, redo and every reload of the tree replace it with a clone.
var vertex_feature_pnid: int = -1


# Let go of a picked vertex that the tree no longer has, which an undo of the
# edit that made it leaves behind.
func _forget_vertices_that_are_gone(node: Feature) -> void:
	for held in [selected_vertex, split_from, hovered_vertex]:
		if held == NO_VERTEX:
			continue
		if node == null or node.is_group or held.x >= node.rings.size():
			_let_every_vertex_go()
			return
		if held.y >= node.rings[held.x].size():
			_let_every_vertex_go()
			return


func _let_every_vertex_go() -> void:
	hovered_vertex = NO_VERTEX
	selected_vertex = NO_VERTEX
	split_from = NO_VERTEX


func _on_vertex_input(lat: float, lon: float, event: InputEvent) -> void:
	var feature := features.feature_tree.get_selected_node()
	if feature == null or feature.is_group or not feature.has_geometry():
		return

	if event is InputEventMouseMotion:
		if vertex_drag != NO_VERTEX:
			_vertex_drag_to(lat, lon)
		else:
			_track_vertex_under_pointer(feature, lat, lon)
		return

	if event is not InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.is_released():
		_vertex_commit_drag()
		return

	var screen: Variant = planet_view.latlon_to_screen(lat, lon)
	if screen != null:
		_vertex_press(feature, screen)


# A press takes hold of the vertex under the pointer, or failing that puts a new
# one on the edge under it. A press on neither lets go of the one it had.
func _vertex_press(feature: Feature, screen: Vector2) -> void:
	var own := _vertices_on_screen(feature)
	var picked := GeometryEdit.nearest_point(own[0], screen, VERTEX_PICK_PIXELS)
	if picked >= 0:
		selected_vertex = own[1][picked]
		vertex_feature_pnid = feature.pnid
		vertex_drag = selected_vertex
		vertex_drag_feature = feature
		vertex_drag_was = feature.rings[vertex_drag.x][vertex_drag.y]
		_update_tool_buttons()
		return

	selected_vertex = _insert_on_edge(feature, screen)
	vertex_feature_pnid = feature.pnid
	_update_tool_buttons()


# Put a vertex on the edge nearest the pointer, at the point of that edge
# nearest the pointer, so the shape does not change until it is dragged.
# Returns where it went, or NO_VERTEX when no edge was near enough.
func _insert_on_edge(feature: Feature, screen: Vector2) -> Vector2i:
	if feature.geometry_kind == Feature.GeometryKind.MULTIPOINT:
		return NO_VERTEX
	var closed := feature.geometry_kind == Feature.GeometryKind.POLYGON

	var best_part := -1
	var best: Array = [-1, INF, 0.0]
	for part in feature.rings.size():
		var on_screen := _ring_on_screen(feature, part)
		if on_screen.size() < feature.rings[part].size():
			# Part of the ring is round the back, where a screen distance means
			# nothing. Leave that part alone rather than guess at it.
			continue
		var found := GeometryEdit.nearest_segment(on_screen, screen, closed)
		if found[0] >= 0 and found[1] < best[1]:
			best = found
			best_part = part
	if best_part < 0 or float(best[1]) > VERTEX_PICK_PIXELS:
		return NO_VERTEX

	var ring: PackedVector2Array = feature.rings[best_part]
	var from := int(best[0])
	var vertex := Measure.along(ring[from], ring[(from + 1) % ring.size()], float(best[2]))
	var error := document.insert_vertex(feature, best_part, from + 1, vertex)
	if not error.is_empty():
		_show_measurement(error)
		return NO_VERTEX
	_after_vertex_edit()
	return Vector2i(best_part, from + 1)


# Follow the pointer with the vertex being dragged, snapping onto a neighbour
# when one is near enough and snapping is on. Nothing is recorded until the
# release: the drag writes straight into the ring so the globe follows it.
func _vertex_drag_to(lat: float, lon: float) -> void:
	if not _drag_is_live():
		return
	var feature := vertex_drag_feature

	var world := Vector2(lat, lon)
	if snapping():
		var screen: Variant = planet_view.latlon_to_screen(lat, lon)
		if screen != null:
			var snapped: Variant = _snap_target(feature, screen)
			if snapped != null:
				world = snapped

	var into_local := Feature.world_basis(
		features.root, feature, document.current_time).transposed()
	feature.rings[vertex_drag.x][vertex_drag.y] = Feature.apply_basis(
		PackedVector2Array([world]), into_local)[0]
	feature.rebuild_triangles()
	refresh_geometry()


# Where a dragged vertex should jump to: the nearest vertex of any feature
# within SNAP_PIXELS, in world coordinates, or null when there is none. The one
# being dragged is left out, since it is always nearest to itself.
func _snap_target(feature: Feature, screen: Vector2) -> Variant:
	var candidates := _vertices_on_screen(null, feature, vertex_drag)
	var picked := GeometryEdit.nearest_point(candidates[0], screen, SNAP_PIXELS)
	return null if picked < 0 else candidates[2][picked]


func _vertex_commit_drag() -> void:
	if not _drag_is_live():
		vertex_drag = NO_VERTEX
		vertex_drag_feature = null
		return
	var feature := vertex_drag_feature
	var moved := vertex_drag
	vertex_drag = NO_VERTEX
	vertex_drag_feature = null

	# The drag wrote into the ring as it went, so what is on the globe is
	# already the new shape. Put the vertex back before the command runs, so
	# that it records a change rather than finding it made.
	var landed: Vector2 = feature.rings[moved.x][moved.y]
	feature.rings[moved.x][moved.y] = vertex_drag_was
	feature.rebuild_triangles()
	var error := document.set_vertex(feature, moved.x, moved.y, landed)
	if not error.is_empty():
		_show_measurement(error)
	_after_vertex_edit()


func _vertex_cancel_drag() -> void:
	if vertex_drag == NO_VERTEX:
		return
	var live := _drag_is_live()
	var feature := vertex_drag_feature
	var put_back := vertex_drag
	vertex_drag = NO_VERTEX
	vertex_drag_feature = null
	if not live:
		return
	feature.rings[put_back.x][put_back.y] = vertex_drag_was
	feature.rebuild_triangles()
	_after_vertex_edit()


# Take out the vertex the tool is working on. Refused when the part would fall
# under the minimum its kind needs: on the globe a triangle would otherwise
# disappear under a single key press.
func delete_selected_vertex() -> String:
	var feature := features.feature_tree.get_selected_node()
	var target := vertex_in_hand()
	if feature == null or feature.is_group or target == NO_VERTEX:
		return "The pointer is on no vertex, and none is picked."
	if target.x >= feature.rings.size() or target.y >= feature.rings[target.x].size():
		return "That vertex is no longer there."
	var problem := GeometryEdit.removal_problem(
		feature.rings[target.x], target.y, feature.geometry_kind)
	if not problem.is_empty():
		return problem
	var error := document.remove_vertex(feature, target.x, target.y)
	if not error.is_empty():
		return error
	hovered_vertex = NO_VERTEX
	selected_vertex = NO_VERTEX
	split_from = NO_VERTEX
	_after_vertex_edit()
	return ""


func _after_vertex_edit() -> void:
	features.reload()
	refresh_geometry()
	properties.show_node(features.feature_tree.get_selected_node())
	_update_tool_buttons()


### Splitting


# Why the selected feature cannot be split where the tool is pointing, or an
# empty string when it can. A polyline is cut at the picked vertex; a polygon
# between it and the one held with Split From.
func _split_problem() -> String:
	if active_tool != Tool.VERTEX:
		return "Splitting belongs to the Vertex tool."
	var feature := features.feature_tree.get_selected_node()
	if feature == null or feature.is_group or selected_vertex == NO_VERTEX:
		return "Pick the vertex to split at first."
	var ring: PackedVector2Array = feature.rings[selected_vertex.x]
	match feature.geometry_kind:
		Feature.GeometryKind.POLYLINE:
			return GeometryEdit.polyline_split_problem(ring, selected_vertex.y)
		Feature.GeometryKind.POLYGON:
			if split_from == NO_VERTEX or split_from.x != selected_vertex.x:
				return "A polygon is cut between two vertices; hold the first with Split From."
			return GeometryEdit.polygon_split_problem(ring, split_from.y, selected_vertex.y)
	return "A multipoint is separate markers, so it has no path to split."


func _split_tooltip() -> String:
	var problem := _split_problem()
	return "Split the feature in two" if problem.is_empty() else problem


# Hold the picked vertex as one end of a polygon cut. The other end is whichever
# vertex is picked next.
func hold_split_from() -> String:
	var feature := features.feature_tree.get_selected_node()
	if feature == null or feature.is_group or selected_vertex == NO_VERTEX:
		return "Pick a vertex first."
	if feature.geometry_kind != Feature.GeometryKind.POLYGON:
		return "Only a polygon is cut between two vertices."
	split_from = selected_vertex
	_update_tool_buttons()
	return ""


func split_at_selected_vertex() -> String:
	var problem := _split_problem()
	if not problem.is_empty():
		return problem
	var feature := features.feature_tree.get_selected_node()
	var other := split_from.y if feature.geometry_kind == Feature.GeometryKind.POLYGON else -1
	var error := document.split_feature(feature, selected_vertex.x, selected_vertex.y, other)
	if not error.is_empty():
		return error
	split_from = NO_VERTEX
	selected_vertex = NO_VERTEX
	features.reload()
	refresh_geometry()
	_update_tool_buttons()
	return ""


### The Circle tool
#
# A small circle, drawn as a preview and committed as a polygon or a polyline of
# a chosen number of segments. Two clicks are a centre and a point on the rim;
# three are three points the circle passes through. Which one is meant follows
# from how many points have been clicked, so there is no mode to pick: the
# preview shows what the clicks so far describe and a third click changes it
# from the one construction to the other.

# The points clicked so far, in world coordinates.
var circle_points := PackedVector2Array()


func _on_circle_input(lat: float, lon: float, event: InputEvent) -> void:
	if event is not InputEventMouseButton or not event.is_pressed():
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		if circle_points.size() >= 3:
			circle_points = PackedVector2Array()
		circle_points.append(Vector2(lat, lon))
	elif event.button_index == MOUSE_BUTTON_RIGHT and not circle_points.is_empty():
		circle_points.remove_at(circle_points.size() - 1)
	else:
		return
	_refresh_selection_outline()
	_show_measurement()


# The circle the clicked points describe, as [centre, angular radius], or an
# empty array while they describe none.
func circle_from_points() -> Array:
	if circle_points.size() == 2:
		var radius := SmallCircle.radius_to(circle_points[0], circle_points[1])
		return [] if radius < 1e-6 else [circle_points[0], radius]
	if circle_points.size() == 3:
		return SmallCircle.through(circle_points[0], circle_points[1], circle_points[2])
	return []


# How many segments the circle is cut into, as the toolbar has it.
func circle_segments() -> int:
	return int(segments_spin.value)


# Whether the circle closes on itself. A polygon does; a polyline is left open
# and repeats its first vertex, so it draws the whole circle either way.
func _circle_is_closed() -> bool:
	return drawing_kind() == Feature.GeometryKind.POLYGON


# The circle being previewed, in world coordinates, or an empty ring.
func circle_ring() -> PackedVector2Array:
	var circle := circle_from_points()
	if circle.is_empty():
		return PackedVector2Array()
	return SmallCircle.vertices(circle[0], circle[1], circle_segments(), _circle_is_closed())


# The clicked points as markers, with the circle they describe over them.
func _circle_outline() -> Array:
	var parts: Array = []
	if not circle_points.is_empty():
		parts.append({"vertices": circle_points, "style": Planet.OutlineStyle.POINTS})
	var ring := circle_ring()
	if not ring.is_empty():
		parts.append({
			"vertices": ring,
			"style": Planet.OutlineStyle.CLOSED if _circle_is_closed()
				else Planet.OutlineStyle.OPEN,
		})
	return parts


# Give the selected feature the circle being previewed. Returns why it could not
# be, or an empty string once it has been.
func _circle_commit() -> String:
	var selected := features.feature_tree.get_selected_node()
	if selected == null or selected.is_group:
		return "Select a feature to draw the circle on."
	var circle := circle_from_points()
	if circle.is_empty():
		return "Click a centre and a point on the rim, or three points on the rim."
	var kind: Feature.GeometryKind = drawing_kind()
	if not kind in Feature.DRAWN_KINDS or kind == Feature.GeometryKind.MULTIPOINT:
		return "A circle becomes a polygon or a polyline, not a %s." % Feature.KIND_NAMES[kind]

	# The circle was worked out in world space; a feature keeps its own frame,
	# which at the current time is where its keyframes and its groups' put it.
	var into_local := Feature.world_basis(
		features.root, selected, document.current_time).transposed()
	selected.add_ring(Feature.apply_basis(circle_ring(), into_local), kind)

	circle_points = PackedVector2Array()
	document.record()
	features.reload()
	refresh_geometry()
	set_active_tool(Tool.MOVE)
	return ""


### The Topology tool
#
# Building a line topology by clicking the features it runs along, in order. A
# click adds the whole of one part of whatever is under it as a section; a right
# click takes the last section back. There is nothing to commit: each click is
# one edit and one undo version, so the boundary is on the globe as it grows.
#
# Which section runs which way, and which vertices of a feature a section
# covers, are set afterwards in the Properties panel; see
# Docs/Editing.md#line-topologies.


func _on_topology_input(lat: float, lon: float, event: InputEvent) -> void:
	if event is not InputEventMouseButton or not event.is_pressed():
		return
	var selected := features.feature_tree.get_selected_node()
	if event.button_index == MOUSE_BUTTON_LEFT:
		_report(add_topology_section(selected, Planet.hit_test(lat, lon, geometry),
			Vector2(lat, lon)))
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_report(remove_last_section(selected))


# Give the topology a section along the feature that was clicked. Returns why it
# could not, or an empty string once it has.
func add_topology_section(node: Feature, target: Feature, at: Vector2) -> String:
	if target == null:
		return "Click a feature to add it to the topology."
	var problem := document.add_section(node, target, _nearest_part(target, at))
	if not problem.is_empty():
		return problem
	_after_topology_edit()
	return ""


func remove_last_section(node: Feature) -> String:
	if node == null or node.sections.is_empty():
		return "There is no section to take back."
	var problem := document.remove_section(node, node.sections.size() - 1)
	if not problem.is_empty():
		return problem
	_after_topology_edit()
	return ""


# Which part of the clicked feature the click fell on: the one holding the
# vertex nearest to it. A feature of a single part answers with that part
# without looking at anything.
func _nearest_part(target: Feature, at: Vector2) -> int:
	if target.rings.size() <= 1:
		return 0
	var m := Feature.world_basis(features.root, target, document.current_time)
	var best := 0
	var best_distance := INF
	for part in target.rings.size():
		for vertex in Feature.apply_basis(target.rings[part], m):
			var distance := Measure.distance(vertex, at, 1.0)
			if distance < best_distance:
				best_distance = distance
				best = part
	return best


# The tree row, the globe and the panel all follow a section being added or
# taken back, since a topology is a feature like any other once it is resolved.
func _after_topology_edit() -> void:
	features.reload()
	properties.show_node(features.feature_tree.get_selected_node())
	refresh_geometry()
	_update_tool_buttons()


### The Light tool
#
# Where the light comes from is a direction in the scene rather than a place on
# the planet, so it is dragged on the globe: the point under the pointer is the
# point the light shines straight at. A map sheet is flat and has no such point,
# so the tool waits for the globe.


# True while the light is being dragged, so that the whole drag moves it and not
# only the press that started it.
var _light_dragging: bool = false


func _on_light_input(lat: float, lon: float, event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_light_dragging = event.is_pressed()
		if event.is_pressed():
			_point_light_at(lat, lon)
	elif event is InputEventMouseMotion and _light_dragging:
		_point_light_at(lat, lon)


func _point_light_at(lat: float, lon: float) -> void:
	var direction = planet_view.globe_direction(lat, lon)
	if direction == null:
		return
	document.view.light_direction = ViewSettings.light_from_vector(direction)
	document.view_edited()
	apply_view_settings()
	if view_dialog.visible:
		_fill_view_fields()
	_refresh_selection_outline()


# Where the light stands on the globe, so the tool can mark it. Null while a map
# is being shown, where the light has no place to be marked at.
func _light_marker() -> Variant:
	if planet_view.planet.show_map:
		return null
	return planet_view.direction_to_latlon(document.view.light_vector())


### The Measure tool
#
# The points that have been clicked, and the great circle distance along them.
# The radius they are read against is a preference; see
# Config.get_planet_radius().

var measure_points := PackedVector2Array()


func _on_measure_input(_lat: float, _lon: float, event: InputEvent) -> void:
	if event is not InputEventMouseButton or not event.is_pressed():
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		measure_points.append(Vector2(_lat, _lon))
	elif event.button_index == MOUSE_BUTTON_RIGHT and not measure_points.is_empty():
		measure_points.remove_at(measure_points.size() - 1)
	else:
		return
	_refresh_selection_outline()
	_show_measurement()


func _measure_clear() -> void:
	measure_points = PackedVector2Array()
	_show_measurement()


# What the status bar says about distance: an error while there is one to
# report, the measured path while the Measure tool has points, the length of the
# selected geometry while it has none, and nothing at all otherwise.
func _show_measurement(error: String = "") -> void:
	if not error.is_empty():
		status_measure.text = error
		return

	if active_tool == Tool.TOPOLOGY:
		var building := features.feature_tree.get_selected_node()
		var count := 0 if building == null else building.sections.size()
		status_measure.text = "click the features the topology runs along" if count == 0 \
			else "%d section%s   right click takes the last one back" % [
				count, "" if count == 1 else "s"]
		return

	if active_tool == Tool.CIRCLE:
		var circle := circle_from_points()
		status_measure.text = "click a centre and the rim, or three points on the rim" 			if circle.is_empty() else "centre %.2f° %.2f°   radius %s   %d segments" % [
				(circle[0] as Vector2).x, (circle[0] as Vector2).y,
				SmallCircle.format_radius(circle[1]), circle_segments()]
		return

	var radius := Config.get_planet_radius()
	if active_tool == Tool.MEASURE:
		if measure_points.size() < 2:
			status_measure.text = "click two points to measure"
			return
		var last := Measure.distance(measure_points[measure_points.size() - 2],
			measure_points[measure_points.size() - 1], radius)
		status_measure.text = "%s   total %s" % [Measure.format_km(last),
			Measure.format_km(Measure.path_length(measure_points, radius))]
		return

	var selected := features.feature_tree.get_selected_node()
	var length := Measure.geometry_length(selected, radius)
	status_measure.text = "" if length <= 0.0 else "%s along %s" % [
		Measure.format_km(length), selected.title]


### Vertices on screen


# Where vertices are in window pixels, for picking one and for snapping to one.
#
# Returns three lists side by side: the window pixels, the (part, index) each
# came from, and the world latitude and longitude each is at. A vertex on the
# far side of the globe has no window pixel and is left out of all three, so a
# screen distance is never taken to something that cannot be seen.
#
# With a feature given, only that one is looked at. Otherwise every feature the
# geometry holds and the current time shows is, which is what lets a vertex snap
# onto one belonging to another feature.
func _vertices_on_screen(only: Feature = null, without: Feature = null,
		except: Vector2i = NO_VERTEX) -> Array:
	var points := PackedVector2Array()
	var places: Array[Vector2i] = []
	var world := PackedVector2Array()

	var wanted: Array[Feature] = []
	if only != null:
		wanted.append(only)
	else:
		for index in geometry.features.size():
			if geometry.shown[index]:
				wanted.append(geometry.features[index])

	for feature in wanted:
		var m := Feature.world_basis(features.root, feature, document.current_time)
		for part in feature.rings.size():
			var turned := Feature.apply_basis(feature.rings[part], m)
			for index in turned.size():
				if feature == without and Vector2i(part, index) == except:
					continue
				var screen: Variant = planet_view.latlon_to_screen(turned[index].x, turned[index].y)
				if screen == null:
					continue
				points.append(screen)
				places.append(Vector2i(part, index))
				world.append(turned[index])
	return [points, places, world]


# One ring of one feature in window pixels, with whatever is round the back left
# out. A caller that needs the indices to line up checks the size first.
func _ring_on_screen(feature: Feature, part: int) -> PackedVector2Array:
	var m := Feature.world_basis(features.root, feature, document.current_time)
	var points := PackedVector2Array()
	for vertex in Feature.apply_basis(feature.rings[part], m):
		var screen: Variant = planet_view.latlon_to_screen(vertex.x, vertex.y)
		if screen != null:
			points.append(screen)
	return points


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
	hovered_lat = lat
	hovered_lon = lon
	if _resolve_hover():
		planet_view.planet.set_feature_state(geometry, hovered_feature)


# Work out what the pointer is over from where it last was, and report whether
# that changed. The caller uploads the feature state, so a caller that is about
# to upload it anyway pays nothing extra.
func _resolve_hover() -> bool:
	var new_hovered: Feature = null
	if not is_nan(hovered_lat):
		new_hovered = Planet.hit_test(hovered_lat, hovered_lon, geometry)
	if new_hovered == hovered_feature:
		return false
	hovered_feature = new_hovered
	return true


### Geometry rendering


func refresh_geometry() -> void:
	geometry = Planet.collect_geometry(features.root, document.current_time)
	planet_view.planet.set_geometry(geometry)
	_refresh_feature_state()


# Where the features sit at the current time, without rebuilding the geometry
# itself. This is what a step of an animation and a drag of the Move tool cost:
# one small texture, whatever the triangle count is.
#
# A topology is the exception: the vertices it draws are the vertices of the
# features it runs along, so moving the time moves them and the geometry has to
# be built again. That costs a document holding one the cheap path, which is why
# it is asked for rather than taken.
func refresh_motion() -> void:
	if Topology.holds_any(features.root):
		refresh_geometry()
		return
	geometry.resolve(features.root, document.current_time)
	_refresh_feature_state()


func _refresh_feature_state() -> void:
	# The features have just moved under a pointer that need not have moved at
	# all, so the feature it is over is worked out again rather than carried
	# over. It costs a hit test only while the pointer is on the globe.
	_resolve_hover()
	planet_view.planet.set_feature_state(geometry, hovered_feature)
	_refresh_selection_outline()


# Trace the selected feature over the geometry: its rings, one outline part
# each, in the same yellow the shape being drawn is shown in.
func _refresh_selection_outline() -> void:
	# Don't overwrite the drawing outline
	if not outline_vertices.is_empty():
		return
	# The Circle tool draws the circle its clicks describe, so what pressing
	# Enter would commit is on the globe before it is committed.
	if active_tool == Tool.CIRCLE:
		planet_view.planet.set_outline(_circle_outline())
		return
	# The Light tool marks where the light stands, so the direction being dragged
	# is somewhere rather than only shown by the shading it produces.
	if active_tool == Tool.LIGHT:
		var marker = _light_marker()
		planet_view.planet.set_outline([] if marker == null else [{
			"vertices": PackedVector2Array([marker]),
			"style": Planet.OutlineStyle.POINTS,
		}])
		return
	# The Measure tool draws the path it has been given instead, so the points
	# clicked and the line between them are visible while the distance is read.
	if active_tool == Tool.MEASURE:
		planet_view.planet.set_outline([] if measure_points.is_empty() else [{
			"vertices": measure_points,
			"style": Planet.OutlineStyle.OPEN,
		}])
		return
	var selected := features.feature_tree.get_selected_node()
	if selected == null or selected.is_group or not selected.has_geometry():
		planet_view.planet.set_outline([])
		return

	var style := Planet.OutlineStyle.OPEN
	match selected.drawn_as():
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

