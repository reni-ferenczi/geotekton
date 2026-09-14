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
static var PALETTE_FILTERS := PackedStringArray(["*.cpt ; Colour Palette Tables"])
static var SCRIPT_FILTERS := PackedStringArray(["*.py ; Python Scripts"])
# What File > Import takes: a GPlates project, or the feature collection and
# rotation files a project would name. See Docs/Import.md.
static var IMPORT_FILTERS := PackedStringArray([
	"*.gproj ; GPlates Projects",
	"*.gpml, *.gpmlz, *.rot, *.grot, *.shp ; GPlates Feature Collections"])

# Where an import is written before it is opened. The document is cut loose
# from it straight after, so this is scratch space rather than a save.
const IMPORT_SCRATCH := "user://imported.middle-earth"

# How finely the palette preview strip samples the palette it draws.
const PALETTE_PREVIEW_STEPS := 128

# Answers a file dialog without showing one. Set by the automation port so a
# scripted run can drive Open and Save As; unset in a normal run.
static var file_dialog_hook: Callable

enum Tool { MOVE, DRAW, VERTEX, MEASURE, CIRCLE, TOPOLOGY, LIGHT, SPLIT }

# How near, in window pixels, a click has to be to take hold of a vertex or an
# edge, and how near a dragged vertex has to come to another before snapping
# takes it the rest of the way. Pixels rather than a distance on the sphere, so
# a tool behaves the same however far the view is zoomed in.
const VERTEX_PICK_PIXELS := 12.0
const SNAP_PIXELS := 12.0

enum FileItem { NEW, OPEN, IMPORT, SAVE, SAVE_AS, RUN_SCRIPT, PREFERENCES, QUIT }
enum EditItem { UNDO, REDO, CUT, COPY, PASTE, DUPLICATE, DELETE }
enum ViewItem { FEATURES, PROPERTIES, TIMELINE, KINEMATICS, CONSOLE, STATUS_BAR, SETTINGS, FULL_SCREEN }
enum TimeItem { OLDER, YOUNGER, OLDER_KEYFRAME, YOUNGER_KEYFRAME }
enum HelpItem { DOCUMENTATION, ABOUT }

# Item id of the entry that empties the recent file list; above any file index.
const CLEAR_RECENT_ID := 1000

# Item id of the globe in the projection selector, above every MapProjection.Kind.
const GLOBE_PROJECTION_ID := 100

# Where the Scripts submenu's entries start, one per catalog entry in order.
const SCRIPT_ITEM_ID := 2000

# Where the View menu's geometry class switches start, above every ViewItem.
# One item per entry of Styling.CLASSES, in that order.
const CLASS_ITEM_ID := 200

# View menu item to the config key remembering whether that panel is shown.
const PANEL_KEYS := {
	ViewItem.FEATURES: "panel_features",
	ViewItem.PROPERTIES: "panel_properties",
	ViewItem.TIMELINE: "panel_timeline",
	ViewItem.KINEMATICS: "panel_kinematics",
	ViewItem.CONSOLE: "panel_console",
	ViewItem.STATUS_BAR: "panel_status_bar",
}

# The panels a configuration that says nothing shows. Everything is shown but
# the kinematics graphs, which are for looking at motion in detail and are
# asked for from the View menu when they are wanted; the globe is what the rest
# of the window is for.
const PANEL_SHOWN_BY_DEFAULT := {ViewItem.KINEMATICS: false, ViewItem.CONSOLE: false}

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
@onready var segments_spin: SpinBox = %Segments
@onready var segments_label: Label = %SegmentsLabel
@onready var outline_check: CheckButton = %Outline
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
@onready var kinematics: KinematicsPanel = %Kinematics
@onready var console: ConsolePanel = %Console
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

# The Python interpreter and the scripts it can be given. Both exist whether or
# not an interpreter is running: with --no-python the catalog is still listed
# and the entries simply refuse to run.
var python: PythonBridge
var scripts: Array[ScriptCatalog.Entry] = []

var file_menu: PopupMenu
var scripts_menu: PopupMenu
var recent_menu: PopupMenu
var edit_menu: PopupMenu
var view_menu: PopupMenu
var time_menu: PopupMenu
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
var interpreter_edit: LineEdit
var script_directories_edit: TextEdit
var view_dialog: AcceptDialog
# Why the backdrop image is not on the planet, shown under the path field.
var backdrop_warning: Label
# The strip the palette chooser previews the chosen palette with, and why the
# palette it names could not be read.
var palette_preview: TextureRect
var palette_warning: Label
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

# The palette the open document names, read once and kept for the same reason:
# rebuilding the geometry must not read a file. `palette.errors` says what could
# not be read of it.
var palette := Palette.resolve(Palette.DEFAULT)

# Every palette read so far, by source: the root group's and whatever other
# groups name. Styling reads a palette it has not seen into it.
var palettes := {}

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
	properties.previewed.connect(refresh_colors)
	# The tree row carries a swatch of the color, so it follows the edit too.
	properties.recolored.connect(func() -> void:
		features.reload()
		refresh_colors())
	properties.rejected.connect(_show_error)
	properties.pick_parent_requested.connect(
		func(on: bool) -> void: start_parent_pick() if on else end_parent_pick())
	document.root_replaced.connect(_on_root_replaced)
	document.state_changed.connect(_update_document_labels)
	document.time_changed.connect(_on_time_changed)
	timeline.attach(document)
	timeline.configure_requested.connect(_show_animation_dialog)
	kinematics.attach(document, timeline)
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
	split_button.pressed.connect(func() -> void: set_active_tool(Tool.SPLIT))
	snap_button.button_pressed = Config.get_snap_to_vertices()
	outline_check.button_pressed = Config.get_circle_outline()
	outline_check.toggled.connect(_on_outline_toggled)
	# The range and the starting value come from Circle, so the scene does
	# not carry a second copy of what a circle may be cut into.
	segments_spin.min_value = Circle.MIN_SEGMENTS
	segments_spin.max_value = Circle.MAX_SEGMENTS
	segments_spin.value = Circle.DEFAULT_SEGMENTS
	_apply_outline_scale()
	_build_view_toolbar()
	_apply_default_view()
	apply_view_settings()

	# The Save and Load buttons of the feature tree toolbar run the File commands
	features.save_button.pressed.connect(save_document)
	features.load_button.pressed.connect(open_document)

	# Connect feature selection from the features panel
	features.feature_tree.feature_selected.connect(_on_feature_selected)
	# A click on a row's colour swatch selects the feature and opens the picker
	# of the Properties panel, which is the one place a colour is edited. It is
	# answered a frame later so the panel is showing the feature just selected.
	features.feature_tree.color_requested.connect(
		properties.open_color_picker, CONNECT_DEFERRED)

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

	# The Python interpreter, started once the console exists so that whatever
	# it says on the way up has somewhere to go. A test runner hosting this
	# scene gets no interpreter: nothing in a headless or rendered test speaks
	# to one, and starting a process per run would only make them slower.
	python = PythonBridge.new(self)
	python.name = "PythonBridge"
	add_child(python)
	console.attach(python)
	if not started_on_its_own:
		python.disable("No interpreter: the application is hosted by a test runner.")
	elif Cli.no_python(OS.get_cmdline_user_args()):
		python.disable("Started with --no-python, so there is no interpreter.")
	else:
		python.start()

	# Open the test automation port if requested: -- --automation-port=<port>
	if port != 0:
		add_child(AutomationPort.new(self, port))

	if not isolated:
		_restore_session()
	# The timeline starts at the oldest age the animation covers, whatever
	# document came up, the way it does after a New or an Open.
	document.set_time(timeline.oldest())
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
	file_menu.add_item("Import...", FileItem.IMPORT)
	file_menu.add_separator()
	file_menu.add_item("Save", FileItem.SAVE, KEY_MASK_CTRL | KEY_S)
	file_menu.add_item("Save As...", FileItem.SAVE_AS, KEY_MASK_CTRL | KEY_MASK_SHIFT | KEY_S)
	file_menu.add_separator()
	file_menu.add_item("Run Script...", FileItem.RUN_SCRIPT)
	scripts_menu = PopupMenu.new()
	scripts_menu.name = "Scripts"
	scripts_menu.id_pressed.connect(_on_scripts_menu_id_pressed)
	file_menu.add_submenu_node_item("Scripts", scripts_menu)
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
	view_menu.add_check_item("Kinematics", ViewItem.KINEMATICS)
	view_menu.add_check_item("Console", ViewItem.CONSOLE)
	view_menu.add_check_item("Status Bar", ViewItem.STATUS_BAR)
	view_menu.add_separator()
	for class_id in Styling.CLASSES:
		view_menu.add_check_item(Styling.class_label(class_id), class_menu_id(class_id))
	view_menu.add_separator()
	view_menu.add_item("View Settings...", ViewItem.SETTINGS)
	view_menu.add_item("Full Screen", ViewItem.FULL_SCREEN, KEY_F11)
	view_menu.id_pressed.connect(_on_view_menu_id_pressed)

	# The skips the timeline's < and > buttons make, as menu items so that their
	# shortcuts work wherever the focus is.
	time_menu = _add_menu("Time")
	time_menu.add_item("Skip Older", TimeItem.OLDER, KEY_PAGEUP)
	time_menu.add_item("Skip Younger", TimeItem.YOUNGER, KEY_PAGEDOWN)
	time_menu.add_separator()
	time_menu.add_item("Older Keyframe", TimeItem.OLDER_KEYFRAME, KEY_MASK_CTRL | KEY_PAGEUP)
	time_menu.add_item("Younger Keyframe", TimeItem.YOUNGER_KEYFRAME, KEY_MASK_CTRL | KEY_PAGEDOWN)
	time_menu.id_pressed.connect(_on_time_menu_id_pressed)

	help_menu = _add_menu("Help")
	help_menu.add_item("Documentation", HelpItem.DOCUMENTATION, KEY_F1)
	help_menu.add_item("About Middle Earth", HelpItem.ABOUT)
	help_menu.id_pressed.connect(_on_help_menu_id_pressed)

	_rebuild_recent_menu()
	rescan_scripts()
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
		FileItem.IMPORT: import_document()
		FileItem.SAVE: save_document()
		FileItem.SAVE_AS: save_document_as()
		FileItem.RUN_SCRIPT: run_script()
		FileItem.PREFERENCES: show_preferences()
		FileItem.QUIT: quit_application()


func _on_edit_menu_id_pressed(id: int) -> void:
	var selected := features.feature_tree.get_selected_node()
	match id:
		EditItem.UNDO: undo()
		EditItem.REDO: redo()
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
		EditItem.UNDO: not document.can_undo() and _tool_points().is_empty(),
		EditItem.REDO: not document.can_redo() and taken_back.is_empty(),
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


### Python scripting
#
# The interpreter is a process this application starts and stops; the console
# panel and the Scripts menu are what reach it. See Docs/Scripting.md.


# Read the configured directories again and rebuild the Scripts submenu. Called
# once at startup and whenever the directories change.
func rescan_scripts() -> void:
	scripts = ScriptCatalog.scan(Config.get_script_directories())
	scripts_menu.clear()
	for index in scripts.size():
		scripts_menu.add_item(scripts[index].title(), SCRIPT_ITEM_ID + index)
		scripts_menu.set_item_tooltip(scripts_menu.item_count - 1,
			"%s

%s" % [scripts[index].name, scripts[index].doc])
	if scripts.is_empty():
		scripts_menu.add_item("(no scripts found)", SCRIPT_ITEM_ID - 1)
		scripts_menu.set_item_disabled(scripts_menu.item_count - 1, true)


func _on_scripts_menu_id_pressed(id: int) -> void:
	var index := id - SCRIPT_ITEM_ID
	if index >= 0 and index < scripts.size():
		run_script_file(scripts[index].path)


# Pick a script file and run it against the open document.
func run_script() -> void:
	_ask_for_path(DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, "Run Script",
		run_script_file, SCRIPT_FILTERS)


# Run one script, showing what it prints in the console. The panel is brought
# up for it: a script that says something has nowhere else to say it.
func run_script_file(path: String) -> void:
	if not python.is_ready():
		_show_error("Cannot run %s: %s" % [path.get_file(), python.reason])
		return
	_show_panel(ViewItem.CONSOLE)
	console.run_file(path)


func _show_panel(item: int) -> void:
	var panel := _panel_node(item)
	if panel.visible:
		return
	panel.visible = true
	_update_view_menu_checks()
	if not isolated:
		_save_panel_visibility()


func _on_view_menu_id_pressed(id: int) -> void:
	if id == ViewItem.FULL_SCREEN:
		_toggle_full_screen()
		return
	if id == ViewItem.SETTINGS:
		show_view_settings()
		return
	if id >= CLASS_ITEM_ID:
		var class_id := Styling.CLASSES.keys()[id - CLASS_ITEM_ID] as String
		document.view.hide_class(class_id, document.view.shows_class(class_id))
		document.view_edited()
		_update_view_menu_checks()
		refresh_geometry()
		return
	var panel := _panel_node(id)
	panel.visible = not panel.visible
	_update_view_menu_checks()
	if not isolated:
		_save_panel_visibility()


func _on_time_menu_id_pressed(id: int) -> void:
	match id:
		TimeItem.OLDER: timeline.step(true)
		TimeItem.YOUNGER: timeline.step(false)
		TimeItem.OLDER_KEYFRAME: timeline.jump_keyframe(true)
		TimeItem.YOUNGER_KEYFRAME: timeline.jump_keyframe(false)


func _on_help_menu_id_pressed(id: int) -> void:
	match id:
		HelpItem.DOCUMENTATION: OS.shell_open(DOCUMENTATION_URL)
		HelpItem.ABOUT: about_dialog.popup_centered()


func _panel_node(item: int) -> Control:
	match item:
		ViewItem.FEATURES: return features
		ViewItem.PROPERTIES: return properties
		ViewItem.TIMELINE: return timeline
		ViewItem.KINEMATICS: return kinematics
		ViewItem.CONSOLE: return console
		ViewItem.STATUS_BAR: return status_bar
	return null


func _update_view_menu_checks() -> void:
	for item in PANEL_KEYS:
		view_menu.set_item_checked(view_menu.get_item_index(item), _panel_node(item).visible)
	for class_id in Styling.CLASSES:
		view_menu.set_item_checked(view_menu.get_item_index(class_menu_id(class_id)),
			document.view.shows_class(class_id))


# The View menu item that switches one class of geometry on and off.
static func class_menu_id(class_id: String) -> int:
	return CLASS_ITEM_ID + Styling.CLASSES.keys().find(class_id)


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
	document.reset(Config.get_view_defaults(), Config.get_style_defaults())
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


# Bring a GPlates reconstruction in as a new document. The conversion is
# Python's: the application picks the file, hands it to the interpreter and
# opens what comes back. See Docs/Import.md.
func import_document() -> void:
	_confirm_unsaved_changes(func() -> void:
		_ask_for_paths(DisplayServer.FILE_DIALOG_MODE_OPEN_FILES, "Import",
			import_paths, IMPORT_FILTERS))


# Import GPlates files: one project, or the feature collection and rotation
# files a project would name. The console is brought up because the conversion
# takes seconds and says what it is doing while it runs.
func import_paths(paths: PackedStringArray) -> void:
	if paths.is_empty():
		return
	var named := ", ".join(Array(paths).map(func(path: String) -> String: return path.get_file()))
	if not python.is_ready():
		_show_error("Cannot import %s: %s" % [named, python.reason])
		return
	_show_panel(ViewItem.CONSOLE)
	var scratch := ProjectSettings.globalize_path(IMPORT_SCRATCH)
	var reply: Dictionary = await python.request(
		"import_gplates", {"sources": paths, "output": scratch})
	if not bool(reply.get("ok", false)):
		_show_error("Cannot import %s: %s" % [named, reply.get("error", "")])
		return
	var error := document.load_imported(scratch)
	DirAccess.remove_absolute(scratch)
	if not error.is_empty():
		_show_error(error)
		return
	Config.set_last_directory_from_file(paths[0])


func _ask_open_path() -> void:
	_ask_for_path(DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, "Open", _load_path)


func _load_path(path: String) -> void:
	var error := document.load_from_file(path)
	if not error.is_empty():
		_show_error(error)
		return
	remember_file(path)


func _write_to(path: String, after: Callable) -> void:
	var error := document.save_to_file(path)
	if not error.is_empty():
		_show_error(error)
		return
	remember_file(path)
	if after.is_valid():
		after.call()


func remember_file(path: String) -> void:
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
		# A new or opened document is looked at from the oldest age the animation
		# covers, since the work runs from there towards the present. The
		# document itself opens at 0, so the headless tests and the file model
		# see no change; the animation range is the application's to know.
		document.set_time(timeline.oldest())
	# The version carries the view settings as well as the tree, so the scene
	# and the dialog showing it follow every step of the stack.
	apply_view_settings()
	if view_dialog.visible:
		_fill_view_fields()
	refresh_geometry()


# Draw the scene the way the open document asks for. Called when a document
# arrives and after every change to its view settings.
func apply_view_settings() -> void:
	_load_palette()
	_load_backdrop()
	planet_view.apply_view_settings(document.view)
	_update_view_menu_checks()
	if view_dialog.visible:
		backdrop_warning.text = backdrop.error


# Read the palette the root group names, unless it has been read already. A
# palette that cannot be read is not a failure of the document either: what did
# parse of it is used and the reasons are pushed as warnings.
func _load_palette() -> void:
	var source := document.root.style.palette
	# The ramp is made of the style's own fields, so there is nothing to read.
	if source == Palette.RAMP:
		palette = document.root.style.ramp()
		return
	if not palettes.has(source):
		palettes[source] = Palette.resolve(source)
		for problem in palettes[source].errors:
			push_warning("%s: %s" % [source, problem])
	palette = palettes[source]


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

	# Python: which interpreter runs the scripting bridge and where the scripts
	# that become menu entries are looked for, one directory per line.
	box.add_child(_view_section("Python"))

	var interpreter_label := Label.new()
	interpreter_label.text = "Interpreter"
	box.add_child(interpreter_label)

	interpreter_edit = LineEdit.new()
	interpreter_edit.name = "PythonInterpreter"
	interpreter_edit.placeholder_text = Config.default_interpreter()
	box.add_child(interpreter_edit)

	var directories_label := Label.new()
	directories_label.text = "Script directories, one per line"
	box.add_child(directories_label)

	script_directories_edit = TextEdit.new()
	script_directories_edit.name = "ScriptDirectories"
	script_directories_edit.custom_minimum_size = Vector2(0, 72)
	box.add_child(script_directories_edit)

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
	# The root group's style, which is the document default for colors.
	_view_option(form, "draw_style", "Draw style", Styling.STYLES)
	_view_color(form, "single_color", "Single colour")
	_view_spin(form, "opacity", "Feature opacity", 0.0, 1.0, 0.05)

	box.add_child(_view_section("Palette"))
	var palette_row := HBoxContainer.new()
	box.add_child(palette_row)
	var palette_choice := OptionButton.new()
	palette_choice.name = "Palette"
	palette_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	palette_choice.item_selected.connect(
		func(_index: int) -> void: _on_view_field_changed())
	palette_row.add_child(palette_choice)
	view_fields["palette"] = palette_choice

	var load_palette := Button.new()
	load_palette.name = "LoadPalette"
	load_palette.text = "Load..."
	load_palette.tooltip_text = "Read a GMT colour palette table from a .cpt file"
	load_palette.pressed.connect(choose_palette)
	palette_row.add_child(load_palette)

	# The colours of the custom ramp and the span between two of them. Only the
	# Custom palette reads them.
	var ramp_box := HBoxContainer.new()
	ramp_box.name = "RampBox"
	box.add_child(ramp_box)
	var ramp_label := Label.new()
	ramp_label.text = "Ramp"
	ramp_box.add_child(ramp_label)
	var ramp_row := RampRow.new(Document.MAX_TIME, "My")
	ramp_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ramp_row.previewed.connect(func() -> void: _on_view_field_changed(false))
	ramp_row.committed.connect(func() -> void: _on_view_field_changed())
	ramp_box.add_child(ramp_row)
	view_fields["ramp_colors"] = ramp_row
	view_fields["ramp_span"] = ramp_row.span_spin

	# The palette from one end of its range to the other, so what is about to be
	# drawn with is visible before anything is drawn with it.
	palette_preview = TextureRect.new()
	palette_preview.name = "PalettePreview"
	palette_preview.custom_minimum_size = Vector2(0, 18)
	palette_preview.stretch_mode = TextureRect.STRETCH_SCALE
	palette_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	box.add_child(palette_preview)

	palette_warning = Label.new()
	palette_warning.name = "PaletteWarning"
	palette_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	palette_warning.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	box.add_child(palette_warning)

	box.add_child(_view_section("Backdrop image"))
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
		Config.set_view_defaults(document.view, document.root.style)
		Config.set_default_view(projection_selector.get_item_text(
			projection_selector.selected)))
	defaults.add_child(remember)

	var restore := Button.new()
	restore.name = "RestoreDefaults"
	restore.text = "Restore defaults"
	restore.tooltip_text = "Put this document back to the settings a new one starts with"
	restore.pressed.connect(func() -> void:
		document.view = Config.get_view_defaults()
		document.root.style = Config.get_style_defaults()
		document.view_edited()
		_fill_view_fields()
		apply_view_settings()
		refresh_geometry())
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


# A selector over a dictionary of id to label. The id rides on the item as its
# metadata, so what the document stores never depends on what the item is called.
func _view_option(form: GridContainer, key: String, text: String, entries: Dictionary) -> void:
	var label := Label.new()
	label.text = text
	form.add_child(label)
	var button := OptionButton.new()
	button.name = key.to_pascal_case()
	for id in entries:
		button.add_item(str(entries[id]))
		button.set_item_metadata(button.item_count - 1, id)
	button.item_selected.connect(func(_index: int) -> void: _on_view_field_changed())
	form.add_child(button)
	view_fields[key] = button


# A heading between two groups of fields on a dialog.
func _view_section(text: String) -> Control:
	var label := Label.new()
	label.text = text
	return label


# The id behind the selected item of a selector built by _view_option().
static func option_value(button: OptionButton) -> String:
	return "" if button.selected < 0 else str(button.get_item_metadata(button.selected))


# Pick the item carrying an id. Nothing changes when the list does not hold it.
static func select_option(button: OptionButton, value: String) -> void:
	for index in button.item_count:
		if str(button.get_item_metadata(index)) == value:
			button.select(index)
			return


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
	var button := Helpers.color_button(key.to_pascal_case(), Helpers.COLOR_TOOLTIP)
	button.custom_minimum_size = Vector2(140, 28)
	# The picker sends a colour for every drag of its cursor. The scene takes
	# them all, so what is being picked is visible, but only the colour left
	# when the picker closes reaches the undo stack, the way the feature colour
	# picker of the Properties panel does it.
	button.color_changed.connect(func(_color: Color) -> void: _on_view_field_changed(false))
	button.popup_closed.connect(_on_view_field_changed)
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


# Pick a GMT colour palette table to draw the feature age style with. Stored as
# the path it was picked from, beside the built in palettes it joins in the list.
func choose_palette() -> void:
	_ask_for_path(DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, "Colour palette",
		func(path: String) -> void:
			document.root.style.palette = path
			_fill_palette_choices()
			_on_view_field_changed(),
		PALETTE_FILTERS)


func show_view_settings() -> void:
	_fill_view_fields()
	backdrop_warning.text = backdrop.error
	view_dialog.popup_centered()


# The palettes the chooser offers: the built in ones, and the file the document
# names when it names one. Rebuilt rather than added to, so switching from one
# file to another leaves one entry rather than two.
func _fill_palette_choices() -> void:
	var choice: OptionButton = view_fields["palette"]
	choice.clear()
	var listed := Palette.choices()
	for key in listed:
		choice.add_item(str(listed[key]))
		choice.set_item_metadata(choice.item_count - 1, key)
	var named := document.root.style.palette
	if not named.is_empty() and not listed.has(named):
		choice.add_item(named.get_file())
		choice.set_item_metadata(choice.item_count - 1, named)
		choice.set_item_tooltip(choice.item_count - 1, named)
	select_option(choice, named)


# Draw the chosen palette across its whole range, and say underneath what could
# not be read of it.
func _show_palette_preview() -> void:
	var strip := palette.sample(PALETTE_PREVIEW_STEPS)
	if strip.is_empty():
		palette_preview.texture = null
	else:
		var image := Image.create(strip.size(), 1, false, Image.FORMAT_RGBA8)
		for x in strip.size():
			image.set_pixel(x, 0, strip[x])
		palette_preview.texture = ImageTexture.create_from_image(image)
	palette_warning.text = "
".join(Array(palette.errors))


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
	var style := document.root.style
	select_option(view_fields["draw_style"], Styling.normalize_style(style.mode))
	view_fields["single_color"].color = style.color
	view_fields["opacity"].set_value_no_signal(style.opacity)
	view_fields["ramp_colors"].colors = style.ramp_colors
	view_fields["ramp_span"].set_value_no_signal(style.ramp_span)
	_fill_palette_choices()
	_show_palette_preview()


# One field moved: take the whole block off the dialog and hand it to the
# document, so the planet follows while the dialog is still open. Every field
# commit is one undo version; a colour being dragged in a picker is applied
# without one until the picker closes.
func _on_view_field_changed(commit: bool = true) -> void:
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
	var style := document.root.style
	style.color = view_fields["single_color"].color
	style.mode = option_value(view_fields["draw_style"])
	style.opacity = view_fields["opacity"].value
	style.palette = option_value(view_fields["palette"])
	style.ramp_colors = view_fields["ramp_colors"].colors
	style.ramp_span = view_fields["ramp_span"].value
	if commit:
		document.view_edited()
	apply_view_settings()
	_show_palette_preview()
	refresh_geometry()


func _build_animation_content() -> Control:
	var form := GridContainer.new()
	form.name = "Animation"
	form.columns = 2
	form.custom_minimum_size = Vector2(360, 0)

	_animation_spin(form, "start", "Start (Ma)", 0.0, Document.MAX_TIME, 1.0)
	_animation_spin(form, "end", "End (Ma)", 0.0, Document.MAX_TIME, 1.0)
	_animation_spin(form, "speed", "Speed (My per second)", 0.001, Document.MAX_TIME, 0.001)

	var loop_check := CheckBox.new()
	loop_check.name = "Loop"
	loop_check.text = "Start again at the end"
	form.add_child(Label.new())
	form.add_child(loop_check)
	animation_fields["loop"] = loop_check

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
	interpreter_edit.text = Config.get_python_interpreter()
	script_directories_edit.text = "
".join(PackedStringArray(Config.get_script_directories()))
	preferences_dialog.popup_centered()


func _on_preferences_confirmed() -> void:
	Config.set_last_directory(default_folder_edit.text)
	Config.set_value("restore_session", restore_session_check.button_pressed)
	Config.set_planet_radius(radius_spin.value)
	Config.set_vertex_marker_scale(marker_spin.value)
	Config.set_line_width_scale(line_spin.value)
	_apply_outline_scale()
	_show_measurement()
	_apply_python_preferences()


# Take up a changed interpreter or script list. The interpreter is only started
# again when the path actually changed, so closing Preferences does not throw
# away a console session for nothing.
func _apply_python_preferences() -> void:
	Config.set_python_interpreter(interpreter_edit.text.strip_edges())
	Config.set_script_directories(Array(script_directories_edit.text.split("
")))
	rescan_scripts()
	if python.state != PythonBridge.State.OFF and python.interpreter != Config.get_python_interpreter():
		var problem := python.start()
		if not problem.is_empty():
			console.note(problem)


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
		_panel_node(item).visible = bool(Config.get_value(
			PANEL_KEYS[item], PANEL_SHOWN_BY_DEFAULT.get(item, true)))
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


# Ask for one file path and call on_path with it.
func _ask_for_path(mode: int, title: String, on_path: Callable,
		filters: PackedStringArray = FILE_FILTERS) -> void:
	_ask_for_paths(mode, title, func(paths: PackedStringArray) -> void:
		on_path.call(paths[0]), filters)


# Ask for file paths and call on_paths with them. The dialog is the one the
# platform provides, so nothing happens when it is cancelled. Only a mode that
# takes several answers with more than one.
func _ask_for_paths(mode: int, title: String, on_paths: Callable,
		filters: PackedStringArray = FILE_FILTERS) -> void:
	if file_dialog_hook.is_valid():
		file_dialog_hook.call(mode, title, on_paths)
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
				on_paths.call(paths),
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
	taken_back = PackedVector2Array()
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
	if active_tool == Tool.SPLIT and tool != Tool.SPLIT:
		split_points = PackedVector2Array()
	active_tool = tool
	move_button.button_pressed = (tool == Tool.MOVE)
	draw_button.button_pressed = (tool == Tool.DRAW)
	vertex_button.button_pressed = (tool == Tool.VERTEX)
	measure_button.button_pressed = (tool == Tool.MEASURE)
	circle_button.button_pressed = (tool == Tool.CIRCLE)
	topology_button.button_pressed = (tool == Tool.TOPOLOGY)
	light_button.button_pressed = (tool == Tool.LIGHT)
	split_button.button_pressed = (tool == Tool.SPLIT)
	# Only the Circle tool reads the segment count and the Outline switch, so
	# only it shows them.
	segments_label.visible = tool == Tool.CIRCLE
	segments_spin.visible = tool == Tool.CIRCLE
	outline_check.visible = tool == Tool.CIRCLE
	planet_view.tool_handles_clicks = tool != Tool.MOVE
	_update_move_enabled()
	_update_tool_buttons()
	# Whether the selection is highlighted depends on the tool, so the feature
	# state is uploaded again along with the outline.
	_refresh_feature_state()
	_show_measurement()


func _on_snap_toggled(enabled: bool) -> void:
	Config.set_snap_to_vertices(enabled)


func snapping() -> bool:
	return snap_button.button_pressed


# The Vertex tool needs a leaf feature holding vertices of its own; there is
# nothing to take hold of otherwise, and a topology's vertices belong to the
# features it runs along. Measure needs nothing at all, and Split a polygon.
# Which of Draw, Circle and Topology is offered follows the feature's type.
func _update_tool_buttons() -> void:
	var selected := features.feature_tree.get_selected_node()
	var editable := selected != null and not selected.is_group and selected.has_own_vertices()
	vertex_button.disabled = not editable
	snap_button.disabled = active_tool != Tool.VERTEX
	draw_button.disabled = not _can_draw(selected)
	circle_button.disabled = not _can_draw_circle(selected)
	topology_button.disabled = not _can_build_topology(selected)
	split_button.disabled = not _can_split_along(selected)
	split_button.tooltip_text = "Split the selected polygon along a line drawn across it" \
		if not split_button.disabled else "Select a polygon to split it"


# Whether the armed tool can still work on the selected feature. Only the three
# drawing tools are asked: the type says which of them a feature is drawn with,
# and nothing a type can change reaches the others.
func _tool_fits(node: Feature) -> bool:
	match active_tool:
		Tool.DRAW:
			return _can_draw(node)
		Tool.CIRCLE:
			return _can_draw_circle(node)
		Tool.TOPOLOGY:
			return _can_build_topology(node)
	return true


### Feature selection


# The panels that follow whatever is selected: what the node is, where its
# keyframes sit under the timeline, and how it has moved. Called when the
# selection changes and after an edit that changed the geometry or the motion of
# what is already selected.
func _show_selection(node: Feature) -> void:
	properties.show_node(node)
	timeline.show_keyframes(node)
	kinematics.show_node(node)


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
	if active_tool == Tool.SPLIT and node != null and not _can_split_along(node):
		set_active_tool(Tool.MOVE)

	var is_leaf := node != null and not node.is_group
	_update_tool_buttons()
	_show_selection(node)

	if is_leaf:
		# A tool that cannot work on what is now selected gives way to the one
		# the feature's type is drawn with, rather than staying armed and
		# swallowing the clicks meant for the globe; and a feature holding
		# nothing yet arms that tool whatever was armed before, so drawing can
		# start straight away. Nothing selected is left alone: rebuilding the
		# tree clears the selection for a moment before it puts it back.
		if not _tool_fits(node) or _tool_for(node) != Tool.MOVE:
			set_active_tool(_tool_for(node))
	else:
		# Can't draw or build a topology on groups or nothing — force Move
		if active_tool == Tool.DRAW or active_tool == Tool.CIRCLE \
				or active_tool == Tool.TOPOLOGY:
			set_active_tool(Tool.MOVE)

	_update_move_enabled()
	_update_tool_buttons()
	refresh_geometry()
	_show_measurement()


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


### What the tools draw
#
# The selected feature's type is the one place it is picked, in the Properties
# panel. It says which kind the Draw and Circle tools commit and which of the
# three drawing tools is offered at all.


# The kind the Draw and Circle tools commit. A feature that already holds
# geometry keeps its kind, whatever the type says, since the parts of a feature
# are all of one kind. Before that the type decides: the first kind it allows,
# except that the Circle tool's Outline switch takes the polyline of the two a
# Circle allows.
func drawing_kind() -> Feature.GeometryKind:
	var node := features.feature_tree.get_selected_node()
	if node == null or node.is_group:
		return Feature.GeometryKind.POLYGON
	if node.has_geometry():
		return node.geometry_kind
	var kinds := FeatureType.kinds(node.feature_type)
	if outline_check.button_pressed and "polyline" in kinds:
		return Feature.GeometryKind.POLYLINE
	return Feature.KIND_VALUES[str(kinds[0])] as Feature.GeometryKind


func _on_outline_toggled(enabled: bool) -> void:
	Config.set_circle_outline(enabled)
	_refresh_selection_outline()


# Which tool draws which type. A Circle is drawn with the Circle tool and a
# Topology built with the Topology tool out of other features, so the Draw tool
# is left the three types clicked out vertex by vertex. A feature carrying no
# type at all, which only a file written before 0.3.0 holds, is drawn like a
# Polygon.
const DRAW_TYPES := [FeatureType.NONE, "polygon", "line", "points"]


func _has_type(node: Feature, types: Array) -> bool:
	return node != null and not node.is_group and node.feature_type in types


func _can_build_topology(node: Feature) -> bool:
	return _has_type(node, ["topology"])


func _can_draw(node: Feature) -> bool:
	return _has_type(node, DRAW_TYPES)


func _can_draw_circle(node: Feature) -> bool:
	return _has_type(node, [FeatureType.CIRCLE])


# The tool the feature's type calls for, or Move when nothing draws it: a
# feature that holds a shape already, a group, or nothing selected.
func _tool_for(node: Feature) -> Tool:
	if node == null or node.is_group or node.has_geometry():
		return Tool.MOVE
	if _can_draw(node):
		return Tool.DRAW
	if _can_draw_circle(node):
		return Tool.CIRCLE
	if _can_build_topology(node):
		return Tool.TOPOLOGY
	return Tool.MOVE


### Move tool


# Only a leaf feature is dragged. A group carries no motion since 0.8.0, so
# there is nothing a drag of one could write.
func _update_move_enabled() -> void:
	var selected := features.feature_tree.get_selected_node()
	planet_view.move_enabled = active_tool == Tool.MOVE and selected != null \
		and not selected.is_group and selected.has_geometry()


# The point that was grabbed and the rotation the dragged feature had when the
# drag started. The keyframes it started with come back if the drag is
# cancelled.
var move_anchor: Vector3
var move_base_rot: Vector3
var move_base_keyframes: Array[Keyframe] = []


func _on_move_started(anchor_lat: float, anchor_lon: float) -> void:
	var selected := features.feature_tree.get_selected_node()
	if selected == null or selected.is_group:
		return
	move_base_keyframes = Keyframe.clone_list(selected.keyframes)
	# A feature riding on another is dragged in world space like any other, and
	# the keyframe is put into the parent's frame when it is written.
	move_base_rot = selected.rotation_at(document.current_time) if selected.couplings.is_empty() \
		else Feature.decompose_rotation_degrees(
			Feature.world_basis(features.root, selected, document.current_time))
	move_anchor = Feature._latlon_to_xyz_s(Vector2(anchor_lat, anchor_lon))


# Dragging writes the keyframe at the current time as it goes, so what is on the
# globe is what will be committed. Only the release records an undo version.
# Whatever rides on the dragged feature goes with it, since refresh_motion()
# resolves every rider from its parent.
func _on_move_to(lat: float, lon: float) -> void:
	var selected := features.feature_tree.get_selected_node()
	if selected == null or selected.is_group:
		return
	var target := Feature._latlon_to_xyz_s(Vector2(lat, lon))
	var new_rot: Variant = Feature.compute_move_rotation(move_anchor, target, move_base_rot)
	if new_rot != null:
		if not selected.couplings.is_empty():
			new_rot = Coupling.rotation_for(selected, document.current_time,
				Feature.build_rotation_basis(new_rot), Coupling.index(features.root))
		Keyframe.upsert(selected.keyframes, document.current_time, new_rot)
		refresh_motion()


func _on_move_ended() -> void:
	document.record()
	features.reload()
	_show_selection(features.feature_tree.get_selected_node())
	refresh_geometry()


func _on_move_cancelled() -> void:
	var selected := features.feature_tree.get_selected_node()
	if selected != null and not selected.is_group:
		selected.keyframes = move_base_keyframes
	refresh_motion()


### Drawing


# The shape being drawn, in world space, before it is committed to a feature.
var outline_vertices := PackedVector2Array()

# Every input event on the planet, sent to whichever tool takes clicks. The
# Move tool is not here: selecting, dragging and the right click menu are the
# view's own, and it leaves them alone while a tool owns the clicks.
func _on_planet_input(lat: float, lon: float, event: InputEvent) -> void:
	# The pick mode takes the click ahead of every tool, whichever one is armed.
	if picking_parent:
		_on_pick_parent_input(lat, lon, event)
		return
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
		Tool.SPLIT:
			_on_split_input(lat, lon, event)


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


### Undo and redo
#
# A tool that takes clicks before it commits them — the shape being drawn, the
# points of a circle, the ends of a measurement — holds them outside the
# document, so the document's undo stack knows nothing about them. Ctrl+Z while
# a tool holds points takes the last one back rather than undoing the previous
# edit under the half drawn shape, and Ctrl+Y puts it back; a right click is the
# same take back. With nothing held, both reach the document. The feature tree
# toolbar's own buttons go straight to the document, since the tree is not
# where drawing happens. See Docs/Draw.md.

# The points taken back and not put back yet, oldest first. Forgotten as soon as
# anything else changes the points: a new click, a commit, a cancel, a change
# of tool.
var taken_back := PackedVector2Array()


func undo() -> void:
	var points := _tool_points()
	if points.is_empty():
		features.undo()
		return
	taken_back.append(points[points.size() - 1])
	points.remove_at(points.size() - 1)
	_set_tool_points(points)


func redo() -> void:
	if taken_back.is_empty():
		features.redo()
		return
	var points := _tool_points()
	points.append(taken_back[taken_back.size() - 1])
	taken_back.remove_at(taken_back.size() - 1)
	_set_tool_points(points)


# One more point for the active tool, from a click.
func _place_point(point: Vector2) -> void:
	var points := _tool_points()
	points.append(point)
	taken_back = PackedVector2Array()
	_set_tool_points(points)


# The points the active tool holds before it commits them; none for a tool
# that takes no clicks of that kind.
func _tool_points() -> PackedVector2Array:
	match active_tool:
		Tool.DRAW:
			return outline_vertices
		Tool.CIRCLE:
			return circle_points
		Tool.MEASURE:
			return measure_points
		Tool.SPLIT:
			return split_points
	return PackedVector2Array()


# Give the active tool its points and show them the way that tool does.
func _set_tool_points(points: PackedVector2Array) -> void:
	match active_tool:
		Tool.DRAW:
			outline_vertices = points
			_refresh_outline()
		Tool.CIRCLE:
			circle_points = points
			_refresh_selection_outline()
			_show_measurement()
		Tool.MEASURE:
			measure_points = points
			_refresh_selection_outline()
			_show_measurement()
		Tool.SPLIT:
			split_points = points
			_refresh_selection_outline()
			_show_measurement()
	_update_edit_menu()


func _on_draw_input(lat: float, lon: float, event: InputEvent) -> void:
	if event is not InputEventMouseButton or not event.is_pressed():
		return

	var selected := features.feature_tree.get_selected_node()
	if selected == null or selected.is_group:
		return

	if event.button_index == MOUSE_BUTTON_LEFT:
		_place_point(Vector2(lat, lon))
	elif event.button_index == MOUSE_BUTTON_RIGHT and not outline_vertices.is_empty():
		undo()


# Single key shortcuts, taken before the GUI pass rather than after it. A
# focused Button answers Space itself, so a shortcut left to
# _unhandled_key_input would press whichever button was last clicked instead of
# reaching the application.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.is_pressed() or key.is_echo():
		return
	# A single key means a single key: Ctrl+S and the rest belong to the menus.
	if key.ctrl_pressed or key.shift_pressed or key.alt_pressed or key.meta_pressed:
		return
	if _typing():
		return
	if _hotkey(key):
		get_viewport().set_input_as_handled()


# Act on a single key shortcut and say whether it was one. Later tickets hang
# the tool keys off the same match.
func _hotkey(event: InputEventKey) -> bool:
	match event.keycode:
		KEY_SPACE:
			timeline.toggle()
		_:
			return false
	return true


# True while the keyboard belongs to a text field, which every single key
# shortcut yields to so that typing a name stays typing a name. A SpinBox
# focuses the LineEdit inside it and CodeEdit is a TextEdit, so both are
# covered, and so is the console's input line.
func _typing() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit


func _unhandled_key_input(event: InputEvent) -> void:
	if event is not InputEventKey or not event.is_pressed():
		return

	# Escape ends the parent pick whatever the tool, since the mode is not one.
	if picking_parent and event.keycode == KEY_ESCAPE:
		end_parent_pick()
		get_viewport().set_input_as_handled()
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
				taken_back = PackedVector2Array()
				_refresh_selection_outline()
				_show_measurement()
			else:
				return
		Tool.SPLIT:
			if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
				_report(split_along_points())
			elif event.keycode == KEY_ESCAPE:
				split_points = PackedVector2Array()
				taken_back = PackedVector2Array()
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
	# which at the current time is where its keyframes put it.
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
	taken_back = PackedVector2Array()
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
	_show_selection(features.feature_tree.get_selected_node())
	_update_tool_buttons()


### Splitting


# Why the Vertex tool cannot split the selected feature where it is pointing, or
# an empty string when it can. A polyline is cut at the picked vertex; a polygon
# between it and the one held with Shift+S. The Split tool cuts a polygon along
# a drawn line instead; this is the same cut with no points in between.
func vertex_split_problem() -> String:
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
				return "A polygon is cut between two vertices; hold the first with Shift+S."
			return GeometryEdit.polygon_split_problem(ring, split_from.y, selected_vertex.y)
	return "A multipoint is separate markers, so it has no path to split."


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
	var problem := vertex_split_problem()
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


### The Split tool
#
# Cutting the selected polygon in two along a line drawn across it. Clicks place
# the points of the cut in world coordinates, previewed over the polygon's
# outline; Enter commits them and Escape lets them all go. The two ends need not
# be clicked on the boundary: the commit puts them on the nearest point of it.
# See Docs/Editing.md#the-split-tool.

var split_points := PackedVector2Array()


# The Split tool needs a leaf polygon holding vertices of its own.
func _can_split_along(node: Feature) -> bool:
	return node != null and not node.is_group and node.has_own_vertices() \
		and node.geometry_kind == Feature.GeometryKind.POLYGON


func _on_split_input(lat: float, lon: float, event: InputEvent) -> void:
	if event is not InputEventMouseButton or not event.is_pressed():
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		_place_point(Vector2(lat, lon))
	elif event.button_index == MOUSE_BUTTON_RIGHT and not split_points.is_empty():
		undo()


# Cut the selected polygon along the points clicked. The part cut is the one
# whose boundary is nearest the first point. A refused cut keeps its points, so
# the one at fault can be taken back rather than the whole cut clicked again.
func split_along_points() -> String:
	var feature := features.feature_tree.get_selected_node()
	if not _can_split_along(feature):
		return "Select a polygon to split."
	if split_points.size() < 2:
		return "Click where the cut starts and where it ends."
	# The points were clicked in world space; a feature keeps its own frame.
	var into_local := Feature.world_basis(
		features.root, feature, document.current_time).transposed()
	var path := Feature.apply_basis(split_points, into_local)
	var part := 0
	var nearest := INF
	for index in feature.rings.size():
		var distance: float = GeometryEdit.nearest_segment(feature.rings[index], path[0], true)[1]
		if distance < nearest:
			nearest = distance
			part = index
	var error := document.split_feature_along(feature, part, path)
	if not error.is_empty():
		return error
	split_points = PackedVector2Array()
	features.reload()
	refresh_geometry()
	set_active_tool(Tool.MOVE)
	return ""


### The Circle tool
#
# A circle, drawn as a preview and committed as a polygon or a polyline of
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
		_place_point(Vector2(lat, lon))
	elif event.button_index == MOUSE_BUTTON_RIGHT and not circle_points.is_empty():
		undo()


# The circle the clicked points describe, as [centre, angular radius], or an
# empty array while they describe none.
func circle_from_points() -> Array:
	if circle_points.size() == 2:
		var radius := Circle.radius_to(circle_points[0], circle_points[1])
		return [] if radius < 1e-6 else [circle_points[0], radius]
	if circle_points.size() == 3:
		return Circle.through(circle_points[0], circle_points[1], circle_points[2])
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
	return Circle.vertices(circle[0], circle[1], circle_segments(), _circle_is_closed())


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
	# which at the current time is where its keyframes put it.
	var into_local := Feature.world_basis(
		features.root, selected, document.current_time).transposed()
	selected.add_ring(Feature.apply_basis(circle_ring(), into_local), kind)
	selected.feature_type = FeatureType.CIRCLE

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
	_show_selection(features.feature_tree.get_selected_node())
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


# The light follows the pointer for the whole drag and the release records one
# undo version for all of it, the way a feature drag does.
func _on_light_input(lat: float, lon: float, event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.is_pressed():
			_light_dragging = true
			_point_light_at(lat, lon)
		elif _light_dragging:
			_light_dragging = false
			document.view_edited()
	elif event is InputEventMouseMotion and _light_dragging:
		_point_light_at(lat, lon)


func _point_light_at(lat: float, lon: float) -> void:
	var direction = planet_view.globe_direction(lat, lon)
	if direction == null:
		return
	document.view.light_direction = ViewSettings.light_from_vector(direction)
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
		# A measurement is one segment. A third click starts the next one from
		# where it fell, so a run of measurements is click, click, click.
		if measure_points.size() >= 2:
			measure_points = PackedVector2Array()
		_place_point(Vector2(_lat, _lon))
	elif event.button_index == MOUSE_BUTTON_RIGHT and not measure_points.is_empty():
		undo()


func _measure_clear() -> void:
	measure_points = PackedVector2Array()
	taken_back = PackedVector2Array()
	_show_measurement()


# What the status bar says about distance: an error while there is one to
# report, the measured path while the Measure tool has points, the length of the
# selected geometry while it has none, and nothing at all otherwise.
func _show_measurement(error: String = "") -> void:
	if not error.is_empty():
		status_measure.text = error
		return

	if picking_parent:
		status_measure.text = "Pick the feature to ride on"
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
				Circle.format_radius(circle[1]), circle_segments()]
		return

	var radius := Config.get_planet_radius()
	if active_tool == Tool.MEASURE and measure_points.size() >= 2:
		var distance := Measure.format_km(
			Measure.distance(measure_points[0], measure_points[1], radius))
		status_measure.text = distance
		# The same number beside the line itself, at its midpoint.
		var middle := Measure.along(measure_points[0], measure_points[1], 0.5)
		planet_view.show_measurement(distance, middle.x, middle.y)
		return
	planet_view.hide_measurement()
	if active_tool == Tool.MEASURE:
		status_measure.text = "click two points to measure"
		return
	if active_tool == Tool.SPLIT:
		status_measure.text = "click across the polygon, from one edge to another" \
			if split_points.size() < 2 \
			else "%d points   Enter splits the polygon along them" % split_points.size()
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


### Picking the parent off the planet
#
# The pointer button on the Ride on row of the Properties panel arms a one shot
# pick: the next left click on the planet names the feature under it in the
# picker, and nothing else about the application changes. The selection stays
# where it is and so does the tool, so the planet's own clicks are held back
# with `tool_handles_clicks` and given back once the mode is over. A click that
# picks nothing the picker offers says why and leaves the mode on, so a miss
# costs one more click. See Docs/Properties.md#coupling.

var picking_parent: bool = false

# What `tool_handles_clicks` was before the mode took it, to give back after.
var _clicks_before_pick: bool = false


func start_parent_pick() -> void:
	if picking_parent:
		return
	picking_parent = true
	_clicks_before_pick = planet_view.tool_handles_clicks
	planet_view.tool_handles_clicks = true
	properties.show_picking(true)
	_show_measurement()


func end_parent_pick() -> void:
	if not picking_parent:
		return
	picking_parent = false
	planet_view.tool_handles_clicks = _clicks_before_pick
	properties.show_picking(false)
	_show_measurement()


func _on_pick_parent_input(lat: float, lon: float, event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.is_pressed() or button.button_index != MOUSE_BUTTON_LEFT:
		return
	var hit := Planet.hit_test(lat, lon, geometry)
	if hit == null:
		_report("Click a feature to ride on it.")
		return
	if hit.geometry_kind == Feature.GeometryKind.TOPOLOGY:
		_report("A topology is not something to ride on.")
		return
	var problem := properties.pick_parent_uuid(hit.uuid)
	if not problem.is_empty():
		_report(problem)
		return
	end_parent_pick()


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
		planet_view.planet.set_feature_state(geometry, hovered_feature, _highlighted_feature())


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
	geometry = Planet.collect_geometry(
		features.root, document.current_time, Styling.of(document.view, features.root, palettes))
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


# What color the features are, without rebuilding the geometry. The color
# lives in the per feature texture, so dragging the color picker costs what a
# step of an animation costs.
func refresh_colors() -> void:
	geometry.recolor(Styling.of(document.view, features.root, palettes))
	_refresh_feature_state()


func _refresh_feature_state() -> void:
	# The features have just moved under a pointer that need not have moved at
	# all, so the feature it is over is worked out again rather than carried
	# over. It costs a hit test only while the pointer is on the globe.
	_resolve_hover()
	planet_view.planet.set_feature_state(geometry, hovered_feature, _highlighted_feature())
	_refresh_selection_outline()


# The feature whose lines the shader draws thicker and yellow: the selected one,
# in the tools that trace the selection. Circle, Light and Measure draw their own
# overlay instead, and the Vertex tool traces the rings with a dot on every
# vertex, which a thick line would cover.
func _highlighted_feature() -> Feature:
	if active_tool in [Tool.VERTEX, Tool.CIRCLE, Tool.LIGHT, Tool.MEASURE]:
		return null
	var selected := features.feature_tree.get_selected_node()
	if selected == null or selected.is_group:
		return null
	return selected


# Trace the selected feature over the geometry in the same yellow the shape
# being drawn is shown in. A polygon gets an outline along its rings and a
# multipoint larger markers; a line needs nothing here, since the shader draws
# it thicker. Only the Vertex tool puts a dot on every vertex, since picking
# vertices is what it is for.
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

	var editing := active_tool == Tool.VERTEX
	var style := Planet.OutlineStyle.OPEN
	match selected.drawn_as():
		Feature.GeometryKind.POLYGON:
			style = Planet.OutlineStyle.CLOSED if editing else Planet.OutlineStyle.OUTLINE
		Feature.GeometryKind.MULTIPOINT:
			style = Planet.OutlineStyle.POINTS if editing else Planet.OutlineStyle.MARKERS
		_:
			if not editing:
				planet_view.planet.set_outline([])
				return

	var m := Feature.world_basis(features.root, selected, document.current_time)
	var parts: Array = []
	for ring in selected.rings:
		parts.append({
			"vertices": Feature.apply_basis(ring, m),
			"style": style,
		})
	# The Split tool previews its cut over the polygon's outline, the way the
	# Draw tool previews a shape.
	if active_tool == Tool.SPLIT and not split_points.is_empty():
		parts.append({"vertices": split_points, "style": Planet.OutlineStyle.OPEN})
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
# and so do the drawing tools, since the type that may have moved says which of
# them the feature is drawn with and what they produce.
func _on_properties_edited() -> void:
	features.reload()
	var selected := features.feature_tree.get_selected_node()
	_update_tool_buttons()
	if not _tool_fits(selected):
		set_active_tool(_tool_for(selected))
	elif not outline_vertices.is_empty():
		_refresh_outline()
	timeline.show_keyframes(selected)
	kinematics.show_node(selected)
	refresh_geometry()

