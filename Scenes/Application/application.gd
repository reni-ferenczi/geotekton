extends VBoxContainer
class_name Application


static var DEBUG: bool = true
static var VERSION: String = ProjectSettings.get_setting("application/config/version")
const ui_scale: float = 1.0

const APPLICATION_NAME := "Geotekton"
const DOCUMENTATION_URL := "https://github.com/reni-ferenczi/geotekton/tree/main/Docs"
# Where an isolated run keeps its settings, under the user data directory.
const ISOLATED_SETTINGS_DIR := "isolated-settings"

# The Earth texture credited in the About dialog, as listed in README.md.
const EARTH_TEXTURE_URL := "https://wall.alphacoders.com/big.php?i=11433"
static var FILE_FILTERS := PackedStringArray(["*%s ; %s Files" % [Document.EXTENSION, APPLICATION_NAME]])
# What a raster may be, taken from the formats Raster reads rather
# than listed a second time here.
static var IMAGE_FILTERS := PackedStringArray(
	["*.%s ; Images" % ", *.".join(Raster.EXTENSIONS)])
static var PALETTE_FILTERS := PackedStringArray(["*.cpt ; Colour Palette Tables"])
# What File > Export Image writes. One format, since the picture is what the
# planet was drawn into and PNG keeps it exactly.
static var IMAGE_EXPORT_FILTERS := PackedStringArray(["*.png ; PNG Images"])
# What File > Export Video writes, and the extension a path without one gets.
# One container, since the frames are encoded by one ffmpeg command line.
static var VIDEO_EXPORT_FILTERS := PackedStringArray(["*.mp4 ; MP4 Videos"])
const VIDEO_EXTENSION := ".mp4"
# What one frame of a video is called. GDScript formats it with the frame
# number and ffmpeg reads the same pattern as a numbered sequence.
const FRAME_NAME := "frame_%05d.png"
# How fast the frames of a video come, and the bounds the dialog offers. Thirty
# is what a video is usually watched at; the speed in My per second is what
# decides how much of the animation each frame covers.
const DEFAULT_FPS := 30.0
const MIN_FPS := 1.0
const MAX_FPS := 120.0
# How many frames one video may hold. At thirty a second that is ten minutes,
# and it is what stands between a mistyped speed and an export nobody wanted.
const MAX_VIDEO_FRAMES := 18000
# Where ffmpeg is looked for when the preference names none and there is none
# on the path: the copy Shotcut ships, which is the one on this machine.
const FFMPEG_CANDIDATES := ["C:/Program Files/Shotcut/ffmpeg.exe"]
static var SCRIPT_FILTERS := PackedStringArray(["*.py ; Python Scripts"])
# What File > Import takes: a GPlates project, or the feature collection and
# rotation files a project would name. See Docs/Import.md.
static var IMPORT_FILTERS := PackedStringArray([
	"*.gproj ; GPlates Projects",
	"*.gpml, *.gpmlz, *.rot, *.grot, *.shp ; GPlates Feature Collections"])

# Where an import is written before it is opened. The document is cut loose
# from it straight after, so this is scratch space rather than a save.
const IMPORT_SCRATCH := "user://imported.geotekt"

# Answers a file dialog without showing one. Set by the automation port so a
# scripted run can drive Open and Save As; unset in a normal run.
static var file_dialog_hook: Callable

enum Tool { MOVE, ROTATE, POLE, DRAW, VERTEX, MEASURE, TOPOLOGY, SPLIT }

# The key that picks each tool, single letters without a modifier. GPlates'
# own letters where it has one for the same tool. The Topology tool has no key:
# the Pick toggle of the section table in the Properties panel arms it.
const TOOL_KEYS := {
	KEY_M: Tool.MOVE,
	KEY_R: Tool.ROTATE,
	KEY_P: Tool.POLE,
	KEY_D: Tool.DRAW,
	KEY_V: Tool.VERTEX,
	KEY_E: Tool.MEASURE,
	KEY_X: Tool.SPLIT,
}

# How near, in window pixels, a click has to be to take hold of a vertex or an
# edge, and how near a dragged vertex has to come to another before snapping
# takes it the rest of the way. Pixels rather than a distance on the sphere, so
# a tool behaves the same however far the view is zoomed in.
const VERTEX_PICK_PIXELS := 12.0
const SNAP_PIXELS := 12.0

# How far the pointer has to travel before a press counts as a drag rather than
# a click. Only the Pole tool tells the two apart: a click places the pole and
# a drag turns the feature about it.
const DRAG_PIXELS := 4.0

enum FileItem { NEW, OPEN, IMPORT, SAVE, SAVE_AS, EXPORT_IMAGE, EXPORT_VIDEO, RUN_SCRIPT,
	PREFERENCES, QUIT }
enum EditItem { UNDO, REDO, CUT, COPY, PASTE, DUPLICATE, DELETE, COPY_SHAPE, PASTE_SHAPE,
	SNAP }
enum ViewItem { FEATURES, PROPERTIES, TIMELINE, KINEMATICS, KINEMATICS_PLACE, CONSOLE, STATUS_BAR,
	SETTINGS, FULL_SCREEN, HIGHLIGHT_CHILDREN }
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

# The config key remembering whether the kinematics panel graphs latitude and
# longitude as well as the rate. Off when the file says nothing.
const KINEMATICS_PLACE_KEY := "kinematics_place"

# The config key remembering whether the children of the selected feature are
# highlighted, on the planet and in the tree. Off when the file says nothing.
# An older config holds the setting under the second key, which is read when the
# first is absent and not written again.
const HIGHLIGHT_CHILDREN_KEY := "highlight_children"
const HIGHLIGHT_CHILDREN_OLD_KEY := "highlight_riders"

@onready var features: Features = %Features
@onready var planet_view: PlanetView = %PlanetView
@onready var move_button: Button = %Move
@onready var rotate_button: Button = %Rotate
@onready var pole_button: Button = %Pole
@onready var draw_button: Button = %Draw
@onready var vertex_button: Button = %Vertex
@onready var measure_button: Button = %Measure
@onready var split_button: Button = %Split
@onready var segments_spin: SpinBox = %Segments
@onready var segments_label: Label = %SegmentsLabel
@onready var freehand_check: CheckButton = %Freehand
@onready var tolerance_label: Label = %ToleranceLabel
@onready var tolerance_spin: SpinBox = %Tolerance
@onready var ridge_check: CheckButton = %Ridge
@onready var crust_check: CheckButton = %Crust
@onready var children_check: CheckButton = %Children
@onready var parallel_check: CheckButton = %Parallel
@onready var projection_selector: OptionButton = %Projection
@onready var zoom_spin: SpinBox = %Zoom
@onready var zoom_in_button: Button = %ZoomIn
@onready var zoom_out_button: Button = %ZoomOut
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

# The toggle button of each tool, which is what says whether a tool is offered,
# which one is armed and which key picks it. The Topology tool has none.
@onready var tool_buttons: Dictionary = {
	Tool.MOVE: move_button,
	Tool.ROTATE: rotate_button,
	Tool.POLE: pole_button,
	Tool.DRAW: draw_button,
	Tool.VERTEX: vertex_button,
	Tool.MEASURE: measure_button,
	Tool.SPLIT: split_button,
}

# The open document. Created here so the panels can attach to it when ready.
var document := Document.new()

var active_tool: Tool = Tool.MOVE

# The feature tree flattened for the shader and the hit test. Rebuilt when the
# tree changes; where each feature sits at the current time is resolved on it
# separately, which is all a step of an animation touches.
var geometry := Planet.Geometry.new()
var hovered_feature: Feature = null

# Whether the children of the selected feature are highlighted, and which
# they are at the current time; see _find_children().
var highlight_children := false
var coupled_children: Array[Feature] = []

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
# The planet's surface under the radius box, following the box as it changes.
var planet_area_label: Label
var marker_spin: SpinBox
var line_spin: SpinBox
# The line width a new feature starts with.
var default_line_width_spin: SpinBox
var export_width_spin: SpinBox
var ffmpeg_edit: LineEdit
# The colour picker of each feature type in the Preferences dialog, by type id.
var feature_color_pickers: Dictionary = {}
var interpreter_edit: LineEdit
var script_directories_edit: TextEdit
var view_dialog: AcceptDialog
# Why the raster is not on the planet, shown under the path field.
var raster_warning: Label
# The fields of the View settings dialog, by the name of the setting each edits.
var view_fields: Dictionary = {}
var animation_dialog: AcceptDialog
# The fields of the animation dialog, by the name of the setting each one edits.
var animation_fields: Dictionary = {}
var video_dialog: AcceptDialog
# The fields of the video dialog, by the name of the setting each one edits,
# beside the file the video goes to and the frame count under them.
var video_fields: Dictionary = {}
var video_path_edit: LineEdit
var video_count_label: Label
var video_progress_dialog: AcceptDialog
var video_progress_label: Label

# The video export in flight: how many frames are rendered, how many there are
# altogether and whether Cancel has been pressed. A total of zero is nothing
# running. `video_result` is what the last export answered, so a run that
# started one without waiting for it can read how it went.
var video_frames: int = 0
var video_total: int = 0
var video_cancelled: bool = false
var video_result: Dictionary = {}

# The image on the planet, and the path it was read from, so that changing the
# opacity or the visibility does not read the file again. `raster.error` says
# why there is no image when there is none.
var raster := Raster.new()
var _raster_path: String = ""

# Every palette read so far, by source, kept for the same reason: rebuilding
# the geometry must not read a file. Styling reads a palette it has not seen
# into it.
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
		func(on: bool) -> void: start_parent_pick() if on else end_pick())
	properties.pick_plate_requested.connect(
		func(on: bool) -> void: start_plate_pick() if on else end_pick())
	properties.palette_file_requested.connect(choose_palette)
	properties.pick_axis_requested.connect(start_axis_pick)
	properties.pick_section_requested.connect(start_section_pick)
	document.root_replaced.connect(_on_root_replaced)
	document.state_changed.connect(_update_document_labels)
	document.time_changed.connect(_on_time_changed)
	timeline.attach(document)
	timeline.configure_requested.connect(_show_animation_dialog)
	# A hotspot's track has a sample at every skip, and a crust a band, so a new
	# one redraws them and the panel counts the bands again.
	timeline.skip_changed.connect(refresh_motion)
	timeline.skip_changed.connect(properties.show_time)
	kinematics.attach(document, timeline)
	# The Edit menus follow the feature tree's own signal: the undo depth, the
	# selection and the clipboard all reach it, which a copy that records no
	# undo version otherwise would not.
	features.commands_changed.connect(_update_edit_menu)

	_build_menus()
	_build_dialogs()

	# Connect tool buttons
	for tool: Tool in tool_buttons:
		tool_buttons[tool].pressed.connect(func() -> void: set_active_tool(tool))
	segments_spin.value_changed.connect(func(_value: float) -> void: _refresh_selection_outline())
	freehand_check.button_pressed = Config.get_freehand()
	freehand_check.toggled.connect(func(on: bool) -> void:
		Config.set_freehand(on)
		_finish_stroke()
		_refresh_selection_outline()
		_show_measurement())
	tolerance_spin.min_value = Config.MIN_FREEHAND_TOLERANCE
	tolerance_spin.max_value = Config.MAX_FREEHAND_TOLERANCE
	tolerance_spin.step = 1.0
	tolerance_spin.value = Config.get_freehand_tolerance()
	tolerance_spin.value_changed.connect(Config.set_freehand_tolerance)
	ridge_check.button_pressed = Config.get_split_ridge()
	ridge_check.toggled.connect(Config.set_split_ridge)
	crust_check.button_pressed = Config.get_split_crust()
	crust_check.toggled.connect(Config.set_split_crust)
	children_check.button_pressed = Config.get_split_children()
	children_check.toggled.connect(Config.set_split_children)
	_update_split_switches()
	ridge_check.toggled.connect(func(_on: bool) -> void: _update_split_switches())
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
	file_menu.add_item("Export Image...", FileItem.EXPORT_IMAGE)
	file_menu.add_item("Export Video...", FileItem.EXPORT_VIDEO)
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
	view_menu.add_check_item("Kinematics: latitude and longitude", ViewItem.KINEMATICS_PLACE)
	view_menu.add_check_item("Console", ViewItem.CONSOLE)
	view_menu.add_check_item("Status Bar", ViewItem.STATUS_BAR)
	view_menu.add_separator()
	view_menu.add_check_item("Highlight children", ViewItem.HIGHLIGHT_CHILDREN)
	view_menu.add_separator()
	for class_id in Styling.CLASSES:
		view_menu.add_check_item(Styling.class_label(class_id), class_menu_id(class_id))
	view_menu.add_separator()
	view_menu.add_item("View Settings...", ViewItem.SETTINGS)
	view_menu.add_item("Full Screen", ViewItem.FULL_SCREEN, KEY_F11)
	view_menu.id_pressed.connect(_on_view_menu_id_pressed)

	help_menu = _add_menu("Help")
	help_menu.add_item("Documentation", HelpItem.DOCUMENTATION, KEY_F1)
	help_menu.add_item("About %s" % APPLICATION_NAME, HelpItem.ABOUT)
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
	menu.add_separator()
	menu.add_item("Copy Shape", EditItem.COPY_SHAPE, KEY_MASK_CTRL | KEY_MASK_SHIFT | KEY_C)
	menu.add_item("Paste Shape", EditItem.PASTE_SHAPE, KEY_MASK_CTRL | KEY_MASK_SHIFT | KEY_V)
	menu.add_separator()
	menu.add_check_item("Snap to vertices", EditItem.SNAP)
	menu.set_item_checked(menu.get_item_index(EditItem.SNAP), snapping())


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
		FileItem.EXPORT_IMAGE: export_image_as()
		FileItem.EXPORT_VIDEO: show_video_dialog()
		FileItem.RUN_SCRIPT: run_script()
		FileItem.PREFERENCES: show_preferences()
		FileItem.QUIT: quit_application()


func _on_edit_menu_id_pressed(id: int) -> void:
	var selected := features.feature_tree.get_selected_node()
	match id:
		EditItem.UNDO: undo()
		EditItem.REDO: redo()
		EditItem.CUT: features.cut_selected()
		EditItem.COPY: features.copy_selected()
		EditItem.PASTE: features.paste_at_selected()
		EditItem.DUPLICATE: features.duplicate_node(selected)
		EditItem.DELETE: features.delete_node(selected)
		EditItem.COPY_SHAPE: copy_shape()
		EditItem.PASTE_SHAPE: paste_shape()
		EditItem.SNAP: toggle_snapping()


# What the Edit menus offer for the selection, the undo stack and the
# clipboard. The globe menu holds two of the same items, so it is updated from
# here as well.
func _update_edit_menu() -> void:
	if edit_menu == null:
		return
	var selected := features.feature_tree.get_selected_node()
	var is_node := selected != null and not selected.is_root
	var is_leaf := is_node and not selected.is_group
	var pasteable := Document.APPLICATION in DisplayServer.clipboard_get()
	var disabled := {
		EditItem.UNDO: not document.can_undo() and _tool_points().is_empty(),
		EditItem.REDO: not document.can_redo() and taken_back.is_empty(),
		EditItem.CUT: not is_node,
		EditItem.COPY: not is_node,
		EditItem.PASTE: not pasteable,
		EditItem.DUPLICATE: not is_node,
		EditItem.DELETE: not is_node,
		EditItem.COPY_SHAPE: not (is_leaf and selected.has_geometry()),
		EditItem.PASTE_SHAPE: shape_clipboard.is_empty() or not is_leaf,
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
	if id == ViewItem.KINEMATICS_PLACE:
		kinematics.show_place = not kinematics.show_place
	elif id == ViewItem.HIGHLIGHT_CHILDREN:
		highlight_children = not highlight_children
		_refresh_feature_state()
	else:
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
		ViewItem.KINEMATICS: return kinematics
		ViewItem.CONSOLE: return console
		ViewItem.STATUS_BAR: return status_bar
	return null


func _update_view_menu_checks() -> void:
	for item in PANEL_KEYS:
		view_menu.set_item_checked(view_menu.get_item_index(item), _panel_node(item).visible)
	view_menu.set_item_checked(view_menu.get_item_index(ViewItem.KINEMATICS_PLACE),
		kinematics.show_place)
	view_menu.set_item_checked(view_menu.get_item_index(ViewItem.HIGHLIGHT_CHILDREN),
		highlight_children)
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


### Exporting a picture of the map
#
# The map at the age the timeline shows, on its own: the whole sheet, nothing
# but the sheet, and the same size every time a projection is exported. The
# grid, the background, the star field and the raster are whatever the
# view settings have them as; the panels, the measurement label, the selection
# and the tool marks are not in it.


# Why a picture cannot be exported, empty when it can. The globe shows one side
# of the planet rather than a map of the whole of it, so there is no sheet for
# a picture to be the size of.
func export_problem() -> String:
	return "" if planet_view.planet.show_map \
		else "Pick a map projection to export a picture of it."


# The size an export comes out at. A width of zero is the one the preferences
# hold; the height is what the projection's aspect asks for. The globe has no
# aspect of its own, being one side of a sphere, so a picture of it is square.
func export_size(width: int = 0) -> Vector2i:
	var pixels := width if width > 0 else Config.get_export_width()
	if not planet_view.planet.show_map:
		return Vector2i(pixels, pixels)
	return PlanetView.export_size(planet_view.planet.projection, pixels)


# One frame of the planet, rendered on its own. The selection highlight and the
# tool overlay come off for it and the planet is drawn again as it was
# afterwards. It is the one place a frame is rendered, so the video export
# below walks the time and calls this for each of its frames. A picture is
# transparent around the sheet; a video frame keeps the background, since the
# encoder has no alpha to carry and the frames left on disk match the video.
func export_frame(size: Vector2i, transparent: bool) -> Image:
	planet_view.planet.set_feature_state(geometry, null, null)
	planet_view.planet.set_outline([])
	var image: Image = await planet_view.render_export(size, transparent)
	_refresh_feature_state()
	return image


# Write that frame to a PNG. The answer is empty when it was written and says
# why not when it was not.
func export_image(path: String, width: int = 0) -> String:
	var problem := export_problem()
	if not problem.is_empty():
		return problem
	var image: Image = await export_frame(export_size(width), true)
	if image.save_png(path) != OK:
		return "Cannot write %s" % path
	return ""


# File > Export Image: ask where the picture goes and write it there.
func export_image_as() -> void:
	_ask_for_path(DisplayServer.FILE_DIALOG_MODE_SAVE_FILE, "Export Image",
		func(path: String) -> void:
			if path.get_extension().to_lower() != "png":
				path += ".png"
			var size := export_size()
			var problem: String = await export_image(path)
			if problem.is_empty():
				_show_measurement("Exported %s at %d by %d" % [
					path.get_file(), size.x, size.y])
				Config.set_last_directory_from_file(path)
			else:
				_show_error(problem),
		IMAGE_EXPORT_FILTERS)


### Exporting a video of the animation
#
# The animation between two ages as a sequence of PNG frames, which ffmpeg
# encodes into one file when there is an ffmpeg to be found and which are left
# where they were written when there is not. Each frame is one age: the time is
# set and the planet drawn through export_frame(), so a frame of a video and a
# picture of the same age show the same planet. The frame keeps the background
# the picture leaves transparent.


# A size an encoder can take: both sides even, rounded down rather than up so
# the picture is never stretched into a pixel that was not drawn. H.264 in
# yuv420p samples the colour at half the width and half the height, so an odd
# side has half a sample nowhere to put.
static func even_size(size: Vector2i) -> Vector2i:
	return Vector2i(maxi(size.x - size.x % 2, 2), maxi(size.y - size.y % 2, 2))


# The size a video comes out at, which is the size of a picture made even.
func video_size(width: int = 0) -> Vector2i:
	return even_size(export_size(width))


# How many frames a video holds: one at the age it starts from, then one every
# speed / fps million years until the age it ends at, which always gets one.
static func video_frame_count(from: float, to: float, speed: float, fps: float) -> int:
	return int(ceil(absf(from - to) / speed * fps)) + 1


# The age of one frame, walking from `from` towards `to` and never past it.
static func video_frame_time(from: float, to: float, speed: float, fps: float,
		index: int) -> float:
	var walked := from + signf(to - from) * speed / fps * index
	return clampf(walked, minf(from, to), maxf(from, to))


# What a video export takes when the caller says nothing: the range and the
# speed the animation is configured with, thirty frames a second, and the
# width every export shares.
func video_defaults() -> Dictionary:
	return {
		"from": timeline.animation.start,
		"to": timeline.animation.end,
		"speed": timeline.animation.speed,
		"fps": DEFAULT_FPS,
		"width": float(Config.get_export_width()),
	}


# Why these settings cannot be made into a video, empty when they can.
static func video_problem(options: Dictionary) -> String:
	var speed := float(options["speed"])
	var fps := float(options["fps"])
	if speed <= 0.0:
		return "The speed must be more than zero."
	if fps < MIN_FPS or fps > MAX_FPS:
		return "The frame rate must be between %d and %d." % [MIN_FPS, MAX_FPS]
	for key in ["from", "to"]:
		var age := float(options[key])
		if age < 0.0 or age > Document.MAX_TIME:
			return "An age of %s is outside 0 to %d." % [age, Document.MAX_TIME]
	var count := video_frame_count(
		float(options["from"]), float(options["to"]), speed, fps)
	if count > MAX_VIDEO_FRAMES:
		return ("That is %d frames, more than the %d one video may hold. " +
			"Raise the speed or lower the frame rate.") % [count, MAX_VIDEO_FRAMES]
	return ""


# Where ffmpeg is: the preference when it names one, whatever the path holds
# when it does not, and last the copy Shotcut ships. Empty when there is none,
# which is what leaves the frames of a video where they were written. A
# preference naming a file that is not there is an answer too, so a run can say
# that this machine has no encoder.
static func find_ffmpeg() -> String:
	var configured := Config.get_ffmpeg()
	if not configured.is_empty():
		return configured if FileAccess.file_exists(configured) else ""
	# The directories of the path, read rather than tried: running a program to
	# find out whether it is there prints an engine error when it is not.
	var windows := OS.get_name() == "Windows"
	var executable := "ffmpeg.exe" if windows else "ffmpeg"
	for directory in OS.get_environment("PATH").split(";" if windows else ":", false):
		var on_path := directory.strip_edges().replace("\\", "/").path_join(executable)
		if FileAccess.file_exists(on_path):
			return on_path
	for candidate in FFMPEG_CANDIDATES:
		if FileAccess.file_exists(candidate):
			return candidate
	return ""


# Render the animation and encode it. The frames go into a folder beside the
# file and named after it, so they are already where they belong when there is
# no ffmpeg to fold them into one. The answer says what happened: `error` is
# empty when it went through, `frames` is how many were rendered, `encoded`
# whether ffmpeg made a file of them and `folder` where they were left when it
# did not.
func export_video(path: String, options: Dictionary = {}) -> Dictionary:
	video_result = {}
	video_result = await _export_video(path, options)
	return video_result


func _export_video(path: String, options: Dictionary) -> Dictionary:
	if video_total > 0:
		return {"error": "A video is already being exported."}
	if path.strip_edges().is_empty():
		return {"error": "A video needs a file to be written to."}
	var settings := video_defaults()
	for key in options:
		if not settings.has(key):
			return {"error": "A video export has no %s setting." % key}
		settings[key] = float(options[key])
	var problem := video_problem(settings)
	if not problem.is_empty():
		return {"error": problem}

	var file := path.strip_edges()
	if file.get_extension().is_empty():
		file += VIDEO_EXTENSION
	var folder := file.get_basename()
	var from := float(settings["from"])
	var to := float(settings["to"])
	var speed := float(settings["speed"])
	var fps := float(settings["fps"])
	var size := video_size(int(settings["width"]))
	var count := video_frame_count(from, to, speed, fps)

	# Frames of an earlier export of the same name would be read as part of
	# this one, since ffmpeg takes the numbered files in order.
	_remove_frames(folder)
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		return {"error": "Cannot make the folder %s" % folder}

	timeline.pause()
	var was_time := document.current_time
	video_cancelled = false
	video_frames = 0
	video_total = count
	var written := 0
	var trouble := ""
	for index in count:
		if video_cancelled:
			break
		document.set_time(video_frame_time(from, to, speed, fps, index))
		var image: Image = await export_frame(size, false)
		var frame_path := folder.path_join(FRAME_NAME % index)
		if image.save_png(frame_path) != OK:
			trouble = "Cannot write %s" % frame_path
			break
		written += 1
		video_frames = written
		_show_video_progress()
	document.set_time(was_time)
	video_total = 0

	if video_cancelled or not trouble.is_empty():
		_remove_frames(folder)
		return {"error": trouble, "cancelled": video_cancelled, "frames": written,
			"encoded": false, "path": file, "folder": ""}

	var ffmpeg := find_ffmpeg()
	if ffmpeg.is_empty():
		return {"error": "", "cancelled": false, "frames": written,
			"encoded": false, "path": file, "folder": folder}

	var output: Array = []
	var code := OS.execute(ffmpeg, ["-y", "-framerate", str(fps),
		"-i", folder.path_join(FRAME_NAME), "-c:v", "libx264",
		"-pix_fmt", "yuv420p", file], output, true)
	if code != 0:
		# The frames stay where they are: they are the work, and the encoding
		# can be done again by hand from them.
		return {"error": "%s could not encode the frames (%d): %s" % [
			ffmpeg, code, "\n".join(PackedStringArray(output)).strip_edges()],
			"cancelled": false, "frames": written, "encoded": false,
			"path": file, "folder": folder}
	_remove_frames(folder)
	return {"error": "", "cancelled": false, "frames": written, "encoded": true,
		"path": file, "folder": ""}


# Stop the video export that is running at its next frame. Nothing to stop is
# not a refusal: the export may have finished while the question was asked.
func cancel_export() -> void:
	if video_total > 0:
		video_cancelled = true


# Take a frame folder away: the frames this export writes, and then the folder
# itself, which stays if anything else was put in it.
static func _remove_frames(folder: String) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	for name in dir.get_files():
		if name.begins_with("frame_") and name.ends_with(".png"):
			dir.remove(name)
	DirAccess.remove_absolute(folder)


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
	_load_raster()
	planet_view.apply_view_settings(document.view)
	_update_view_menu_checks()
	if view_dialog.visible:
		raster_warning.text = raster.error


# Put the image the document names on the planet. The file is read only when the
# path it resolves to changes, so dragging the opacity does not read it again.
#
# An image that cannot be read is not a failure of the document: the planet
# shows its own color, the reason is pushed as a warning and the View
# settings dialog shows it beside the path.
func _load_raster() -> void:
	var path := document.resolve_raster()
	if path != _raster_path:
		_raster_path = path
		raster = Raster.load_from(path)
		if not raster.error.is_empty():
			push_warning(raster.error)
	planet_view.planet.set_raster(raster.texture,
		document.view.raster_opacity if document.view.raster_visible else 0.0)


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
	error_dialog.title = APPLICATION_NAME
	add_child(error_dialog)

	about_dialog = AcceptDialog.new()
	about_dialog.name = "AboutDialog"
	about_dialog.title = "About %s" % APPLICATION_NAME
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

	video_dialog = AcceptDialog.new()
	video_dialog.name = "VideoDialog"
	video_dialog.title = "Export video"
	video_dialog.ok_button_text = "Export"
	video_dialog.add_child(_build_video_content())
	video_dialog.confirmed.connect(_on_video_confirmed)
	add_child(video_dialog)

	# The export runs frame by frame with the window alive, so the progress is
	# a dialog whose one button stops it rather than a bar nobody can leave.
	video_progress_dialog = AcceptDialog.new()
	video_progress_dialog.name = "VideoProgressDialog"
	video_progress_dialog.title = "Exporting video"
	video_progress_dialog.ok_button_text = "Cancel"
	video_progress_label = Label.new()
	video_progress_label.name = "VideoProgress"
	video_progress_label.custom_minimum_size = Vector2(260, 0)
	video_progress_dialog.add_child(video_progress_label)
	video_progress_dialog.confirmed.connect(cancel_export)
	video_progress_dialog.canceled.connect(cancel_export)
	add_child(video_progress_dialog)


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


# The Preferences dialog is three tabs rather than one column. A column of
# every setting grew taller than a screen that is not full screen, with the OK
# button out of reach below it, and a tab fits with room to spare.
func _build_preferences_content() -> Control:
	var tabs := TabContainer.new()
	tabs.name = "Preferences"
	tabs.custom_minimum_size = Vector2(520, 0)
	# The dialog is sized to the tallest tab, so it stays put when the tab
	# changes rather than growing and shrinking under the pointer.
	tabs.use_hidden_tabs_for_min_size = true
	tabs.add_child(_build_general_preferences())
	tabs.add_child(_build_drawing_preferences())
	tabs.add_child(_build_python_preferences())
	return tabs


# Where files come from and go to, what distances are read against, and how an
# export comes out.
func _build_general_preferences() -> Control:
	var box := VBoxContainer.new()
	box.name = "General"

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

	radius_spin = _form_spin(form, "PlanetRadius", "Planet radius (km)",
		Measure.MIN_RADIUS_KM, Measure.MAX_RADIUS_KM, 1.0)
	form.add_child(Control.new())
	planet_area_label = Label.new()
	planet_area_label.name = "PlanetArea"
	form.add_child(planet_area_label)
	radius_spin.value_changed.connect(func(radius: float) -> void:
		planet_area_label.text = "Surface area %s" % Measure.format_area(Measure.planet_area(radius)))
	export_width_spin = _form_spin(form, "ExportWidth", "Export width (pixels)",
		Config.MIN_EXPORT_WIDTH, Config.MAX_EXPORT_WIDTH, Config.EXPORT_WIDTH_STEP)

	# The encoder a video export hands its frames to. Empty is the one on the
	# path, or the one Shotcut ships where there is none.
	var ffmpeg_label := Label.new()
	ffmpeg_label.text = "ffmpeg for video export"
	box.add_child(ffmpeg_label)

	ffmpeg_edit = LineEdit.new()
	ffmpeg_edit.name = "Ffmpeg"
	ffmpeg_edit.placeholder_text = "Whatever is found on the path"
	box.add_child(ffmpeg_edit)

	return box


# How the outline overlay and new features are drawn: the outline sizes, the
# line width a new feature starts with, and the colour of each feature type.
func _build_drawing_preferences() -> Control:
	var box := VBoxContainer.new()
	box.name = "Drawing"

	var form := GridContainer.new()
	form.columns = 2
	box.add_child(form)

	marker_spin = _form_spin(form, "VertexMarkerScale", "Vertex marker size",
		Config.MIN_SCALE, Config.MAX_SCALE, 0.05)
	line_spin = _form_spin(form, "LineWidthScale", "Outline line width",
		Config.MIN_SCALE, Config.MAX_SCALE, 0.05)
	default_line_width_spin = _form_spin(form, "DefaultLineWidth", "Default line width",
		Feature.MIN_LINE_WIDTH, Feature.MAX_LINE_WIDTH, 0.05)
	default_line_width_spin.tooltip_text = ("The line width a new feature starts with, "
		+ "as a multiple of what its type draws at; a feature keeps its own once it exists")

	# The colour each feature type starts a feature in, in catalog order.
	box.add_child(_view_section("Feature colors"))
	var colors := GridContainer.new()
	colors.columns = 2
	box.add_child(colors)
	for type_id in FeatureType.CATALOG:
		var label := Label.new()
		label.text = FeatureType.label(type_id)
		colors.add_child(label)
		var picker := Helpers.color_button(type_id.to_pascal_case() + "Color", Helpers.COLOR_TOOLTIP)
		picker.edit_alpha = false
		picker.custom_minimum_size = Vector2(140, 28)
		colors.add_child(picker)
		feature_color_pickers[type_id] = picker
	var catalog := Button.new()
	catalog.name = "CatalogColors"
	catalog.text = "Catalog colors"
	catalog.tooltip_text = "Put every feature type back to the color it comes with"
	catalog.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	catalog.pressed.connect(func() -> void:
		for type_id in feature_color_pickers:
			feature_color_pickers[type_id].color = FeatureType.CATALOG[type_id]["color"])
	box.add_child(catalog)

	return box


# Which interpreter runs the scripting bridge and where the scripts that become
# menu entries are looked for, one directory per line.
func _build_python_preferences() -> Control:
	var box := VBoxContainer.new()
	box.name = "Python"

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


func _form_spin(form: GridContainer, name: String, text: String,
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
# it, where the light comes from, the planet's color and which image it wears.
# Every field takes effect as it is changed rather than when the dialog is
# closed, so the planet under it shows what is being chosen.
func _build_view_content() -> Control:
	var box := VBoxContainer.new()
	box.name = "ViewSettings"
	box.custom_minimum_size = Vector2(460, 0)

	var form := GridContainer.new()
	form.columns = 2
	box.add_child(form)

	_view_color(form, "background_color", "Background")
	_view_check(form, "star_field", "Star field")
	_view_color(form, "grid_color", "Grid")
	_view_spin(form, "grid_spacing", "Grid spacing (°)",
		ViewSettings.MIN_SPACING, ViewSettings.MAX_SPACING, 1.0)
	_view_spin(form, "light_elevation", "Light elevation (°)",
		-ViewSettings.MAX_ELEVATION, ViewSettings.MAX_ELEVATION, 1.0)
	_view_spin(form, "light_azimuth", "Light azimuth (°)", -180.0, 180.0, 1.0)
	_view_spin(form, "ambient", "Ambient light",
		ViewSettings.MIN_AMBIENT, ViewSettings.MAX_AMBIENT, 0.05)
	# The planet is never see-through, so its picker offers no alpha.
	_view_color(form, "planet_color", "Planet color").edit_alpha = false
	_view_check(form, "raster_visible", "Raster shown")
	_view_spin(form, "raster_opacity", "Raster opacity", 0.0, 1.0, 0.05)

	box.add_child(_view_section("Raster"))
	var row := HBoxContainer.new()
	box.add_child(row)
	var edit := LineEdit.new()
	edit.name = "RasterPath"
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.placeholder_text = "None"
	edit.text_submitted.connect(func(_text: String) -> void: _on_view_field_changed())
	edit.focus_exited.connect(_on_view_field_changed)
	row.add_child(edit)
	view_fields["raster_path"] = edit

	var browse := Button.new()
	browse.name = "BrowseRaster"
	browse.text = "Browse..."
	browse.pressed.connect(choose_raster)
	row.add_child(browse)

	var earth := Button.new()
	earth.name = "BuiltInEarth"
	earth.text = "Built in Earth"
	earth.tooltip_text = "Wear the Earth image that comes with %s" % APPLICATION_NAME
	earth.pressed.connect(func() -> void:
		edit.text = ViewSettings.BUILT_IN_EARTH
		_on_view_field_changed())
	row.add_child(earth)

	var clear := Button.new()
	clear.name = "ClearRaster"
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
		apply_view_settings()
		refresh_geometry())
	defaults.add_child(restore)

	raster_warning = Label.new()
	raster_warning.name = "RasterWarning"
	raster_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	raster_warning.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	box.add_child(raster_warning)

	return box


func _view_spin(form: GridContainer, key: String, text: String,
		low: float, high: float, step: float) -> void:
	var spin := _form_spin(form, key.to_pascal_case(), text, low, high, step)
	spin.value_changed.connect(func(_value: float) -> void: _on_view_field_changed())
	view_fields[key] = spin


# A heading between two groups of fields on a dialog.
func _view_section(text: String) -> Control:
	var label := Label.new()
	label.text = text
	return label


func _view_check(form: GridContainer, key: String, text: String) -> void:
	var label := Label.new()
	label.text = text
	form.add_child(label)
	var check := CheckBox.new()
	check.name = key.to_pascal_case()
	check.toggled.connect(func(_pressed: bool) -> void: _on_view_field_changed())
	form.add_child(check)
	view_fields[key] = check


func _view_color(form: GridContainer, key: String, text: String) -> ColorPickerButton:
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
	return button


# Pick the image the planet wears. It is stored relative to the project file
# when it sits beside it, so a project and its images can be moved together.
func choose_raster() -> void:
	_ask_for_path(DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, "Raster",
		func(path: String) -> void:
			view_fields["raster_path"].text = Document.relative_raster(path, document.path)
			_on_view_field_changed(),
		IMAGE_FILTERS)


# Pick a GMT color palette table for the group the Properties panel shows,
# which adds it to that group's palette choices. Stored as the path it was
# picked from. The file is read here, again if it was read before, so an edited
# file is picked up and what could not be read of it is said at once. What did
# read is used all the same.
func choose_palette() -> void:
	_ask_for_path(DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, "Colour palette",
		func(path: String) -> void:
			var palette := Palette.resolve(path)
			palettes[path] = palette
			properties.load_palette(path)
			if not palette.errors.is_empty():
				_show_error("%s:\n%s" % [path.get_file(), "\n".join(palette.errors)]),
		PALETTE_FILTERS)


func show_view_settings() -> void:
	_fill_view_fields()
	raster_warning.text = raster.error
	view_dialog.popup_centered()


# Put what the document holds into the fields, without firing the signals that
# would write them straight back.
func _fill_view_fields() -> void:
	var settings := document.view
	view_fields["background_color"].color = settings.background_color
	view_fields["star_field"].set_pressed_no_signal(settings.star_field)
	view_fields["grid_color"].color = settings.grid_color
	view_fields["grid_spacing"].set_value_no_signal(settings.grid_spacing)
	view_fields["light_elevation"].set_value_no_signal(settings.light_direction.x)
	view_fields["light_azimuth"].set_value_no_signal(settings.light_direction.y)
	view_fields["ambient"].set_value_no_signal(settings.ambient)
	view_fields["planet_color"].color = settings.planet_color
	view_fields["raster_visible"].set_pressed_no_signal(settings.raster_visible)
	view_fields["raster_opacity"].set_value_no_signal(settings.raster_opacity)
	view_fields["raster_path"].text = settings.raster_path


# One field moved: take the whole block off the dialog and hand it to the
# document, so the planet follows while the dialog is still open. Every field
# commit is one undo version; a colour being dragged in a picker is applied
# without one until the picker closes.
func _on_view_field_changed(commit: bool = true) -> void:
	var settings := document.view
	settings.background_color = view_fields["background_color"].color
	settings.star_field = view_fields["star_field"].button_pressed
	settings.grid_color = view_fields["grid_color"].color
	settings.grid_spacing = view_fields["grid_spacing"].value
	settings.light_direction = ViewSettings.clamp_light(Vector2(
		view_fields["light_elevation"].value, view_fields["light_azimuth"].value))
	settings.ambient = view_fields["ambient"].value
	settings.planet_color = view_fields["planet_color"].color
	settings.raster_visible = view_fields["raster_visible"].button_pressed
	settings.raster_opacity = view_fields["raster_opacity"].value
	settings.raster_path = view_fields["raster_path"].text
	if commit:
		document.view_edited()
	apply_view_settings()
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


### The video dialog
#
# What File > Export Video asks for: the ages to run between, how fast to run
# and how finely to sample it, how wide the picture is and where the file goes.
# The frame count under the fields follows them as they are typed.


func _build_video_content() -> Control:
	var box := VBoxContainer.new()
	box.name = "Video"
	box.custom_minimum_size = Vector2(420, 0)

	var form := GridContainer.new()
	form.columns = 2
	box.add_child(form)
	_video_spin(form, "from", "From (Ma)", 0.0, Document.MAX_TIME, 1.0)
	_video_spin(form, "to", "To (Ma)", 0.0, Document.MAX_TIME, 1.0)
	_video_spin(form, "speed", "Speed (My per second)", 0.001, Document.MAX_TIME, 0.001)
	_video_spin(form, "fps", "Frames per second", MIN_FPS, MAX_FPS, 1.0)
	_video_spin(form, "width", "Width (pixels)", Config.MIN_EXPORT_WIDTH,
		Config.MAX_EXPORT_WIDTH, Config.EXPORT_WIDTH_STEP)

	var file_label := Label.new()
	file_label.text = "File"
	box.add_child(file_label)

	var row := HBoxContainer.new()
	box.add_child(row)
	video_path_edit = LineEdit.new()
	video_path_edit.name = "VideoPath"
	video_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(video_path_edit)
	var browse := Button.new()
	browse.name = "BrowseVideo"
	browse.text = "..."
	browse.tooltip_text = "Pick where the video goes"
	browse.pressed.connect(choose_video_path)
	row.add_child(browse)

	video_count_label = Label.new()
	video_count_label.name = "VideoFrames"
	video_count_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(video_count_label)

	return box


func _video_spin(form: GridContainer, field: String, text: String,
		low: float, high: float, step: float) -> void:
	var spin := _form_spin(form, field.to_pascal_case(), text, low, high, step)
	spin.value_changed.connect(func(_value: float) -> void: _show_video_frame_count())
	video_fields[field] = spin


# What the fields hold, in the shape export_video() takes.
func _video_options() -> Dictionary:
	var options := {}
	for field in video_fields:
		options[field] = (video_fields[field] as SpinBox).value
	return options


# How many frames the fields ask for and how large they come out, or why they
# ask for something that cannot be made.
func _show_video_frame_count() -> void:
	var options := _video_options()
	var problem := video_problem(options)
	if not problem.is_empty():
		video_count_label.text = problem
		return
	var size := video_size(int(options["width"]))
	video_count_label.text = "%d frames, %d by %d" % [video_frame_count(
		float(options["from"]), float(options["to"]),
		float(options["speed"]), float(options["fps"])), size.x, size.y]


func show_video_dialog() -> void:
	var defaults := video_defaults()
	for field in video_fields:
		(video_fields[field] as SpinBox).set_value_no_signal(float(defaults[field]))
	if video_path_edit.text.strip_edges().is_empty():
		var base := document.path.get_basename() if not document.path.is_empty() \
			else Config.get_last_directory().path_join(document.display_name())
		video_path_edit.text = base + VIDEO_EXTENSION
	_show_video_frame_count()
	video_dialog.popup_centered()


func choose_video_path() -> void:
	_ask_for_path(DisplayServer.FILE_DIALOG_MODE_SAVE_FILE, "Export Video",
		func(path: String) -> void:
			if path.get_extension().is_empty():
				path += VIDEO_EXTENSION
			video_path_edit.text = path,
		VIDEO_EXPORT_FILTERS)


func _on_video_confirmed() -> void:
	var path := video_path_edit.text.strip_edges()
	var problem := video_problem(_video_options())
	if problem.is_empty() and path.is_empty():
		problem = "Pick a file for the video."
	if not problem.is_empty():
		_show_error(problem)
		return
	_show_video_progress()
	video_progress_dialog.popup_centered()
	var answer: Dictionary = await export_video(path, _video_options())
	video_progress_dialog.hide()
	_report_video(answer)


# Say where the export got to, in the dialog it is watched in.
func _show_video_progress() -> void:
	if video_progress_label != null:
		video_progress_label.text = "Frame %d of %d" % [video_frames, video_total]


# What the status bar and, where something has to be done about it, the error
# dialog say about a finished export.
func _report_video(answer: Dictionary) -> void:
	var frames := int(answer.get("frames", 0))
	if not str(answer.get("error", "")).is_empty():
		_show_error(str(answer["error"]))
	elif bool(answer.get("cancelled", false)):
		_show_measurement("Video export cancelled after %d frames" % frames)
	elif bool(answer.get("encoded", false)):
		_show_measurement("Exported %s, %d frames" % [
			str(answer.get("path", "")).get_file(), frames])
		Config.set_last_directory_from_file(str(answer.get("path", "")))
	else:
		var folder := str(answer.get("folder", ""))
		_show_measurement("%d frames written to %s" % [frames, folder.get_file()])
		_show_error(("No ffmpeg was found, so the %d frames are in %s rather than " +
			"in one file. Name an ffmpeg in Preferences to have them encoded.") % [
			frames, folder])
		Config.set_last_directory_from_file(str(answer.get("path", "")))


func show_preferences() -> void:
	default_folder_edit.text = Config.get_last_directory()
	restore_session_check.button_pressed = bool(Config.get_value("restore_session", true))
	radius_spin.value = Config.get_planet_radius()
	marker_spin.value = Config.get_vertex_marker_scale()
	line_spin.value = Config.get_line_width_scale()
	default_line_width_spin.value = Config.get_default_line_width()
	export_width_spin.value = Config.get_export_width()
	ffmpeg_edit.text = Config.get_ffmpeg()
	for type_id in feature_color_pickers:
		feature_color_pickers[type_id].color = FeatureType.color(type_id)
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
	Config.set_default_line_width(default_line_width_spin.value)
	Config.set_export_width(int(export_width_spin.value))
	Config.set_ffmpeg(ffmpeg_edit.text.strip_edges())
	_save_feature_colors()
	_apply_outline_scale()
	_show_measurement()
	properties.show_radius()
	_apply_python_preferences()


# Keep the colours that differ from the catalog. Features keep the colour they
# hold, so only the "Feature type" draw style shows the change at once.
func _save_feature_colors() -> void:
	var colors := {}
	for type_id in feature_color_pickers:
		var picked: Color = feature_color_pickers[type_id].color
		if not picked.is_equal_approx(FeatureType.CATALOG[type_id]["color"]):
			colors[type_id] = picked
	Config.set_feature_colors(colors)
	refresh_colors()


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
	kinematics.show_place = bool(Config.get_value(KINEMATICS_PLACE_KEY, false))
	highlight_children = bool(Config.get_value(HIGHLIGHT_CHILDREN_KEY,
		Config.get_value(HIGHLIGHT_CHILDREN_OLD_KEY, false)))
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
	Config.set_value(KINEMATICS_PLACE_KEY, kinematics.show_place)
	Config.set_value(HIGHLIGHT_CHILDREN_KEY, highlight_children)


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
	# The axis pick lasts one click of the Pole tool; any change of tool ends it.
	picking_axis = false
	if active_tool == Tool.DRAW and tool != Tool.DRAW:
		_outline_cancel()
	if active_tool == Tool.VERTEX and tool != Tool.VERTEX:
		_vertex_cancel_drag()
		_let_every_vertex_go()
	if active_tool == Tool.MEASURE and tool != Tool.MEASURE:
		_measure_clear()
		# The switch is the tool's own rather than a setting, so it starts off
		# every time the tool is picked up.
		parallel_check.button_pressed = false
	if active_tool == Tool.SPLIT and tool != Tool.SPLIT:
		split_points = PackedVector2Array()
		_update_split_switches()
	if _spins(active_tool) and tool != active_tool:
		_spin_cancel()
		pole_at = NO_POLE
	active_tool = tool
	for entry: Tool in tool_buttons:
		tool_buttons[entry].button_pressed = entry == tool
	properties.show_section_picking(tool == Tool.TOPOLOGY)
	# Only the Split tool reads the Ridge and Crust switches, and only the
	# Measure tool the Parallel one. The segment count follows the selection as
	# well, so _update_tool_buttons shows it.
	ridge_check.visible = tool == Tool.SPLIT
	crust_check.visible = tool == Tool.SPLIT
	children_check.visible = tool == Tool.SPLIT
	parallel_check.visible = tool == Tool.MEASURE
	planet_view.tool_handles_clicks = tool != Tool.MOVE
	_update_move_enabled()
	_update_tool_buttons()
	# Whether the selection is highlighted depends on the tool, so the feature
	# state is uploaded again along with the outline.
	_refresh_feature_state()
	_show_measurement()


# Snap to vertices is a setting rather than a tool: a check item of the Edit
# menu, kept in the config. It applies wherever a click or a drag can land on a
# vertex, which is the Vertex drag, the Pole placement and the Draw tool.
func toggle_snapping() -> void:
	Config.set_snap_to_vertices(not snapping())
	edit_menu.set_item_checked(edit_menu.get_item_index(EditItem.SNAP), snapping())


func snapping() -> bool:
	return Config.get_snap_to_vertices()


# The Vertex tool needs a leaf feature holding vertices of its own; there is
# nothing to take hold of otherwise, and a topology's vertices belong to the
# features it runs along. Rotate and Pole want the same thing, since they turn
# those vertices about an axis. Measure needs nothing at all, and Split a
# polygon. Whether Draw is offered follows the feature's type, and so does the
# segment count, which only a circle being drawn reads.
func _update_tool_buttons() -> void:
	var selected := features.feature_tree.get_selected_node()
	var editable := _can_spin(selected)
	vertex_button.disabled = not _can_edit_vertices(selected)
	rotate_button.disabled = not editable
	pole_button.disabled = not editable
	draw_button.disabled = not _can_draw(selected)
	split_button.disabled = not _can_split_along(selected)
	segments_label.visible = _drawing_circle()
	segments_spin.visible = _drawing_circle()
	freehand_check.visible = _can_draw_freehand()
	tolerance_label.visible = _can_draw_freehand()
	tolerance_spin.visible = _can_draw_freehand()


# Whether the armed tool can still work on the selected feature. Only the two
# drawing tools are asked: the type says which of them a feature is drawn with,
# and nothing a type can change reaches the others.
func _tool_fits(node: Feature) -> bool:
	match active_tool:
		Tool.DRAW:
			return _can_draw(node)
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
	var editable := node == null or _can_spin(node)
	if (active_tool == Tool.VERTEX or _spins(active_tool)) and not editable:
		set_active_tool(Tool.MOVE)
	if active_tool == Tool.VERTEX and node != null and not _can_edit_vertices(node):
		set_active_tool(Tool.MOVE)
	# The axis or sections being picked belong to the feature that asked for
	# them.
	if (picking_axis or active_tool == Tool.TOPOLOGY) \
			and node != null and node.pnid != pick_pnid:
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
		if active_tool == Tool.DRAW or active_tool == Tool.TOPOLOGY:
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
	# A picture is of a map sheet, so the globe has nothing to export.
	file_menu.set_item_disabled(
		file_menu.get_item_index(FileItem.EXPORT_IMAGE), not planet.show_map)
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
# panel. It says what the Draw tool commits and which of the two drawing tools
# is offered at all.


# The kind the Draw tool commits. A feature that already holds
# geometry keeps its kind, whatever the type says, since the parts of a feature
# are all of one kind. Before that the type decides: the first kind it allows.
func drawing_kind() -> Feature.GeometryKind:
	var node := features.feature_tree.get_selected_node()
	if node == null or node.is_group:
		return Feature.GeometryKind.POLYGON
	if node.has_geometry():
		return node.geometry_kind
	var kinds := FeatureType.kinds(node.feature_type)
	return Feature.KIND_VALUES[str(kinds[0])] as Feature.GeometryKind


# Which types the Draw tool draws. A Topology is picked together out of other
# features instead. A Circle is drawn from two or three clicks rather than
# vertex by vertex, which _drawing_circle() tells apart, and a Hotspot is put
# down with one click, which _drawing_hotspot() does. A feature carrying no type
# at all, which only a file written before 0.3.0 holds, is drawn like a Polygon.
const DRAW_TYPES := [FeatureType.NONE, "polygon", "line", "points", FeatureType.CIRCLE,
	FeatureType.HOTSPOT]


func _has_type(node: Feature, types: Array) -> bool:
	return node != null and not node.is_group and node.feature_type in types


func _can_build_topology(node: Feature) -> bool:
	return _has_type(node, ["topology"])


func _can_draw(node: Feature) -> bool:
	return _has_type(node, DRAW_TYPES)


# Whether the Draw tool is drawing a circle rather than clicking a shape out
# vertex by vertex: it is armed and the selected feature is typed Circle.
func _drawing_circle() -> bool:
	return active_tool == Tool.DRAW \
		and _has_type(features.feature_tree.get_selected_node(), [FeatureType.CIRCLE])


# Whether the Draw tool is placing a hotspot: it is armed and the selected
# feature is a hotspot.
func _drawing_hotspot() -> bool:
	var selected := features.feature_tree.get_selected_node()
	return active_tool == Tool.DRAW and selected != null and selected.is_hotspot()


# Whether a feature can be edited vertex by vertex or turned about an axis. A
# group carries no motion and no vertices, a topology borrows every vertex it
# draws from the features it runs along, and a feature holding nothing has
# nothing to turn.
func _can_spin(node: Feature) -> bool:
	return node != null and not node.is_group and node.has_own_vertices()


# A circle is rebuilt from its center and radius, so a vertex moved by hand
# would not last; it is turned, not edited.
func _can_edit_vertices(node: Feature) -> bool:
	return _can_spin(node) and not node.is_circle()


# The tool the feature's type calls for, or Move when nothing draws it: a
# feature that holds a shape already, a topology, whose sections are picked from
# the Properties panel, a group, or nothing selected. A hotspot not placed yet
# holds nothing, so it gets the Draw tool.
func _tool_for(node: Feature) -> Tool:
	if node == null or node.is_group or node.has_geometry():
		return Tool.MOVE
	if _can_draw(node):
		return Tool.DRAW
	return Tool.MOVE


### Move tool


# Only a leaf feature is dragged. A group carries no motion since 0.8.0, so
# there is nothing a drag of one could write, and a hotspot is fixed in the
# world frame.
func _update_move_enabled() -> void:
	var selected := features.feature_tree.get_selected_node()
	planet_view.move_enabled = active_tool == Tool.MOVE and selected != null \
		and not selected.is_group and selected.has_geometry() and not selected.is_hotspot()


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
	# A feature that follows another is dragged in world space like any other, and
	# the keyframe is put into the parent's frame when it is written.
	move_base_rot = selected.rotation_at(document.current_time) if selected.couplings.is_empty() \
		else Feature.decompose_rotation_degrees(
			Feature.world_basis(features.root, selected, document.current_time))
	move_anchor = Feature._latlon_to_xyz_s(Vector2(anchor_lat, anchor_lon))


# Dragging writes the keyframe at the current time as it goes, so what is on the
# globe is what will be committed. Only the release records an undo version.
# The children of the dragged feature go with it, since refresh_motion()
# resolves every child from its parent.
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


### The Rotate and Pole tools
#
# Where the Move tool carries a grabbed point along a great circle, these two
# spin the feature about an axis: the one through its own middle with Rotate,
# and one placed with a click with Pole. What they write is the keyframe at the
# current time, the way a move writes one, and only the release records a
# version. The arithmetic is in Logic/feature.gd; see Docs/Moving.md#rotating.

# Where the Pole tool's pole is, in world latitude and longitude, or NO_POLE
# while there is none. It stays while the tool is armed and the selection
# changes, so several features can be turned about one pole in turn.
const NO_POLE := Vector2.INF

var pole_at := NO_POLE

# The drag: the axis being turned about, the point that was grabbed, the
# rotation and the keyframes the feature started with, and the feature itself,
# held rather than looked up for the reason a dragged vertex is. The axis is
# Vector3.ZERO while no drag is running.
var spin_axis := Vector3.ZERO
var spin_anchor := Vector3.ZERO
var spin_base_rot := Vector3.ZERO
var spin_base_keyframes: Array[Keyframe] = []
var spin_feature: Feature = null

# Where the pointer went down, in world latitude and longitude, until it is let
# go again, and how far the feature has been turned since, in radians. The angle
# is NAN while nothing has been turned, which is what the status bar reads.
var spin_press_at := NO_POLE
var spin_angle: float = NAN


func _spins(tool: Tool) -> bool:
	return tool == Tool.ROTATE or tool == Tool.POLE


func _on_spin_input(lat: float, lon: float, event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if spin_axis != Vector3.ZERO:
			_spin_to(lat, lon)
		elif spin_press_at != NO_POLE and _moved_far_enough(lat, lon):
			_spin_start(lat, lon)
		return

	if event is not InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.is_pressed():
		spin_press_at = Vector2(lat, lon)
		spin_angle = NAN
		_show_measurement()
		return

	# A press that became a drag is committed; one that never moved far enough
	# is a click, which is what places the Pole tool's pole.
	if spin_axis != Vector3.ZERO:
		_spin_commit()
	elif active_tool == Tool.POLE and spin_press_at != NO_POLE:
		_place_pole(spin_press_at)
	spin_press_at = NO_POLE


# Whether the pointer has travelled far enough from where it went down for the
# press to be a drag. Measured in window pixels, so it does not depend on how
# far the view is zoomed in.
func _moved_far_enough(lat: float, lon: float) -> bool:
	var from: Variant = planet_view.latlon_to_screen(spin_press_at.x, spin_press_at.y)
	var to: Variant = planet_view.latlon_to_screen(lat, lon)
	if from == null or to == null:
		return false
	return (from as Vector2).distance_to(to) > DRAG_PIXELS


# Take hold of the feature for a turn about the axis the tool gives, with the
# point the press landed on as the anchor. Nothing starts when there is no axis
# to turn about, or when the grab is so near the axis that the direction to it
# says nothing.
func _spin_start(lat: float, lon: float) -> void:
	var feature := features.feature_tree.get_selected_node()
	if picking_axis or not _can_spin(feature):
		return
	var axis := Feature.centroid_axis(features.root, feature, document.current_time) \
		if active_tool == Tool.ROTATE else Feature._latlon_to_xyz_s(pole_at)
	if axis == Vector3.ZERO:
		return
	var anchor := Feature._latlon_to_xyz_s(spin_press_at)
	# The same point twice: null is the grab lying on the axis or its antipode.
	if Feature.angle_about_axis(axis, anchor, anchor) == null:
		return

	spin_feature = feature
	spin_axis = axis
	spin_anchor = anchor
	spin_base_keyframes = Keyframe.clone_list(feature.keyframes)
	# A feature that follows another is turned in world space like any other, and
	# the keyframe is put into the parent's frame when it is written.
	spin_base_rot = feature.rotation_at(document.current_time) if feature.couplings.is_empty() \
		else Feature.decompose_rotation_degrees(
			Feature.world_basis(features.root, feature, document.current_time))
	_spin_to(lat, lon)


# Turn the feature so that the anchor follows the pointer about the axis. The
# keyframe at the current time is written as the drag goes, so what is on the
# globe is what the release will commit.
func _spin_to(lat: float, lon: float) -> void:
	var angle: Variant = Feature.angle_about_axis(
		spin_axis, spin_anchor, Feature._latlon_to_xyz_s(Vector2(lat, lon)))
	if angle == null:
		# The pointer is on the axis, where there is no direction to follow.
		return
	spin_angle = angle
	var rotation: Variant = Feature.compute_spin_rotation(spin_axis, angle, spin_base_rot)
	if not spin_feature.couplings.is_empty():
		rotation = Coupling.rotation_for(spin_feature, document.current_time,
			Feature.build_rotation_basis(rotation), Coupling.index(features.root))
	Keyframe.upsert(spin_feature.keyframes, document.current_time, rotation)
	refresh_motion()
	_show_measurement()


func _spin_commit() -> void:
	spin_axis = Vector3.ZERO
	spin_feature = null
	document.record()
	features.reload()
	_show_selection(features.feature_tree.get_selected_node())
	refresh_geometry()
	_show_measurement()


# Give the drag up and put the keyframe list back the way it was, the whole
# list rather than the one rotation, since the drag may have added a keyframe
# that was not there before.
func _spin_cancel() -> void:
	if spin_feature != null:
		spin_feature.keyframes = spin_base_keyframes
		refresh_motion()
	spin_axis = Vector3.ZERO
	spin_feature = null
	spin_press_at = NO_POLE
	spin_angle = NAN


# Put the pole where it was clicked, or on the nearest vertex of any feature
# while Snap is on, the way a dragged vertex snaps onto one.
func _place_pole(at: Vector2) -> void:
	pole_at = at
	if snapping():
		var screen: Variant = planet_view.latlon_to_screen(at.x, at.y)
		if screen != null:
			var candidates := _vertices_on_screen()
			var picked := GeometryEdit.nearest_point(candidates[0], screen, SNAP_PIXELS)
			if picked >= 0:
				pole_at = candidates[2][picked]
	if picking_axis:
		_finish_axis_pick(pole_at)
		return
	_refresh_selection_outline()
	_show_measurement()


### Picking the axis of a circle
#
# The Pick axis button of the Properties panel arms the Pole tool for one click,
# with its cross on the current axis. The click, snapped like any pole, becomes
# the new axis in the feature's own frame, and the tool goes back to Move.
# Escape or another tool gives the pick up. See Docs/Editing.md#axis-circles.

var picking_axis: bool = false
var pick_pnid: int = -1


func start_axis_pick() -> void:
	var feature := features.feature_tree.get_selected_node()
	if feature == null or not feature.is_circle():
		return
	set_active_tool(Tool.POLE)
	picking_axis = true
	pick_pnid = feature.pnid
	var to_world := Feature.world_basis(features.root, feature, document.current_time)
	pole_at = Feature.apply_basis(PackedVector2Array([feature.axis]), to_world)[0]
	_refresh_selection_outline()
	_show_measurement()


func _finish_axis_pick(world: Vector2) -> void:
	var feature := features.feature_tree.get_selected_node()
	set_active_tool(Tool.MOVE)
	if feature == null or not feature.is_circle():
		return
	var to_local := Feature.world_basis(features.root, feature, document.current_time).transposed()
	var axis := Feature.apply_basis(PackedVector2Array([world]), to_local)[0]
	var error := document.set_circle(feature, axis, feature.radius, feature.circle_segments,
		feature.polar)
	if not error.is_empty():
		_report(error)
		return
	features.reload()
	_show_selection(features.feature_tree.get_selected_node())
	refresh_geometry()


# How far each arm of the cross marking the pole reaches, in degrees.
const POLE_CROSS := 3.0


# The pole in the outline overlay: a point with a short cross through it, so it
# is not taken for a vertex. The arms are half as wide as a feature line
# (Planet.BOLD_SCALE), wider than an outline line, so the cross is easy to see. Empty unless the Pole tool holds one.
func _pole_outline() -> Array:
	if active_tool != Tool.POLE or pole_at == NO_POLE:
		return []
	return [
		{"vertices": PackedVector2Array([pole_at]), "style": Planet.OutlineStyle.POINTS},
		{"vertices": PackedVector2Array([
			pole_at + Vector2(-POLE_CROSS, 0.0), pole_at + Vector2(POLE_CROSS, 0.0)]),
			"style": Planet.OutlineStyle.BOLD},
		{"vertices": PackedVector2Array([
			pole_at + Vector2(0.0, -POLE_CROSS), pole_at + Vector2(0.0, POLE_CROSS)]),
			"style": Planet.OutlineStyle.BOLD},
	]


### Drawing


# The shape being drawn, in world space, before it is committed to a feature.
var outline_vertices := PackedVector2Array()

# Every input event on the planet, sent to whichever tool takes clicks. The
# Move tool is not here: selecting, dragging and the right click menu are the
# view's own, and it leaves them alone while a tool owns the clicks.
func _on_planet_input(lat: float, lon: float, event: InputEvent) -> void:
	# The second press of a double click is the first click over again, and no
	# tool wants a click twice: the Draw tool would put the same vertex down
	# twice, which is a corner the fill cannot reach. See Docs/Draw.md.
	if event is InputEventMouseButton and event.double_click:
		return
	# The pick mode takes the click ahead of every tool, whichever one is armed.
	if picking != Pick.NONE:
		_on_pick_input(lat, lon, event)
		return
	match active_tool:
		Tool.ROTATE, Tool.POLE:
			_on_spin_input(lat, lon, event)
		Tool.DRAW:
			_on_draw_input(lat, lon, event)
		Tool.VERTEX:
			_on_vertex_input(lat, lon, event)
		Tool.MEASURE:
			_on_measure_input(lat, lon, event)
		Tool.TOPOLOGY:
			_on_topology_input(lat, lon, event)
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
	elif active_tool == Tool.DRAW:
		# A stroke that runs off the planet ends where it left it.
		_finish_stroke()
	elif _spins(active_tool):
		# Off the planet there is no angle to turn to, so the drag is given up
		# and the keyframes go back the way they were, as a move does.
		_spin_cancel()


### Undo and redo
#
# A tool that takes clicks before it commits them — the shape or the circle
# being drawn, the ends of a measurement — holds them outside the
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


# The points of the Draw tool come in groups: one per click, and one per
# freehand stroke, which is taken back and put back whole. The groups are
# counts, oldest first, adding up to the points held; taken_back_groups are
# those of the points taken back, in the order they were taken. Either list
# that does not add up to its points, because something reset the points
# without it, is read as one point per group, which is what every click is.
var draw_groups: Array[int] = []
var taken_back_groups: Array[int] = []


func undo() -> void:
	var points := _tool_points()
	if points.is_empty():
		features.undo()
		return
	var count := _last_group(draw_groups, points.size())
	for i in count:
		taken_back.append(points[points.size() - count + i])
	points.resize(points.size() - count)
	if active_tool == Tool.DRAW:
		_sync_groups(points.size() + count)
		draw_groups.resize(draw_groups.size() - 1)
		taken_back_groups.append(count)
	_set_tool_points(points)


func redo() -> void:
	if taken_back.is_empty():
		features.redo()
		return
	var points := _tool_points()
	var count := _last_group(taken_back_groups, taken_back.size())
	points.append_array(taken_back.slice(taken_back.size() - count))
	taken_back.resize(taken_back.size() - count)
	if active_tool == Tool.DRAW:
		if taken_back_groups.size() > 0:
			taken_back_groups.resize(taken_back_groups.size() - 1)
		_sync_groups(points.size() - count)
		draw_groups.append(count)
	_set_tool_points(points)


# How many points the last group holds: the last entry when the groups add up
# to the points and the tool is Draw, otherwise one.
func _last_group(groups: Array[int], size: int) -> int:
	if active_tool != Tool.DRAW or groups.is_empty() or size == 0:
		return 1
	var total := 0
	for count in groups:
		total += count
	return groups[groups.size() - 1] if total == size else 1


# Make draw_groups add up to size, one point per group where they do not.
func _sync_groups(size: int) -> void:
	var total := 0
	for count in draw_groups:
		total += count
	if total != size:
		draw_groups.clear()
		for i in size:
			draw_groups.append(1)


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
		Tool.MEASURE:
			# A finished path holds nothing to take back, so Ctrl+Z reaches the
			# document again; the next click throws the path away.
			return PackedVector2Array() if measure_done else measure_points
		Tool.SPLIT:
			return split_points
	return PackedVector2Array()


# Give the active tool its points and show them the way that tool does.
func _set_tool_points(points: PackedVector2Array) -> void:
	match active_tool:
		Tool.DRAW:
			outline_vertices = points
			_refresh_outline()
		Tool.MEASURE:
			measure_points = points
			_refresh_selection_outline()
			_show_measurement()
		Tool.SPLIT:
			split_points = points
			_update_split_switches()
			_refresh_selection_outline()
			_show_measurement()
	_update_edit_menu()


func _on_draw_input(lat: float, lon: float, event: InputEvent) -> void:
	if freehand() and _on_freehand_input(lat, lon, event):
		return
	if event is not InputEventMouseButton or not event.is_pressed():
		return

	var selected := features.feature_tree.get_selected_node()
	if selected == null or selected.is_group:
		return
	if selected.feature_type == FeatureType.CIRCLE:
		_on_draw_circle_input(lat, lon, event)
		return
	if selected.is_hotspot():
		if event.button_index == MOUSE_BUTTON_LEFT:
			_place_hotspot(selected, Vector2(lat, lon))
		return

	if event.button_index == MOUSE_BUTTON_LEFT:
		var snap := _draw_snap(lat, lon)
		if snap.is_empty():
			_draw_points(PackedVector2Array([Vector2(lat, lon)]), [{}])
		elif event.shift_pressed:
			_draw_trace(snap)
		else:
			_draw_points(PackedVector2Array([snap["point"]]), [snap])
	elif event.button_index == MOUSE_BUTTON_RIGHT and not outline_vertices.is_empty():
		undo()


### Freehand drawing
#
# With the Freehand switch on, the Draw tool lays a line down under the
# pointer: the left button pressed starts a stroke, the pointer moving adds a
# point every few pixels, and the button let go ends it, whereupon the stroke
# is simplified to the tolerance beside the switch and joins the held points
# as one group, which RMB and Ctrl+Z take back whole. Nothing else changes:
# Enter commits, Escape cancels, and the vertices are as sampled, which is
# what a freehand line is under everything that stores or draws one. See
# Docs/Draw.md#freehand.

# How far the pointer moves, in window pixels, before the stroke takes the
# next point. Without it a slow drag lays down hundreds of points a pixel
# apart, which on a polygon is also the repeated vertex case.
const FREEHAND_SPACING := 3.0

# The stroke being drawn, in world latitude and longitude and in window
# pixels side by side, and whether the button is down.
var stroke := PackedVector2Array()
var stroke_screen := PackedVector2Array()
var stroke_on := false


# Whether the Draw tool can draw freehand on what is selected: a line or a
# polygon, which are drawn vertex by vertex; a multipoint, a circle and a
# hotspot are not lines.
func _can_draw_freehand() -> bool:
	if active_tool != Tool.DRAW or _drawing_circle() or _drawing_hotspot():
		return false
	var selected := features.feature_tree.get_selected_node()
	if selected == null or selected.is_group:
		return false
	return drawing_kind() in [Feature.GeometryKind.POLYGON, Feature.GeometryKind.POLYLINE]


# Whether the Draw tool is drawing freehand now.
func freehand() -> bool:
	return freehand_check.button_pressed and _can_draw_freehand()


# The tolerance a stroke is simplified to when it ends, in window pixels.
func freehand_tolerance() -> float:
	return tolerance_spin.value


# The freehand part of the Draw tool's input. Returns whether the event was
# the stroke's: a left press, the motion while it is down and the release. A
# right press falls through to the take back.
func _on_freehand_input(lat: float, lon: float, event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		if not stroke_on:
			return false
		var screen: Variant = planet_view.latlon_to_screen(lat, lon)
		if screen == null:
			return true
		var last := stroke_screen[stroke_screen.size() - 1]
		if (screen as Vector2).distance_to(last) >= FREEHAND_SPACING:
			stroke.append(Vector2(lat, lon))
			stroke_screen.append(screen)
			_refresh_outline()
		return true
	if event is not InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
		return false
	if event.is_pressed():
		var screen: Variant = planet_view.latlon_to_screen(lat, lon)
		if screen == null:
			return true
		stroke = PackedVector2Array([Vector2(lat, lon)])
		stroke_screen = PackedVector2Array([screen])
		stroke_on = true
		_refresh_outline()
		return true
	_finish_stroke()
	return true


# End the stroke: simplify it to the tolerance in window pixels and add what
# is left to the held points as one group. A stroke of one point is a click.
func _finish_stroke() -> void:
	if not stroke_on:
		return
	stroke_on = false
	var kept := PackedVector2Array()
	for index in GeometryEdit.simplified(stroke_screen, freehand_tolerance()):
		kept.append(stroke[index])
	stroke = PackedVector2Array()
	stroke_screen = PackedVector2Array()
	if kept.is_empty():
		_refresh_outline()
		return
	var snaps := []
	snaps.resize(kept.size())
	_draw_points(kept, snaps)
	# One group for the whole stroke, in place of the one per point that
	# _draw_points gave.
	draw_groups.resize(draw_groups.size() - kept.size())
	draw_groups.append(kept.size())
	_show_measurement()


# Forget a stroke without adding it, when the drawing is cancelled or the
# tool is left.
func _drop_stroke() -> void:
	stroke_on = false
	stroke = PackedVector2Array()
	stroke_screen = PackedVector2Array()


# Put the hotspot where the Draw tool was clicked, on the feature under the
# click when that can be its plate, and stay in Draw, so the next click moves it.
# Otherwise the plate it had is kept. One undo version, and nothing is held.
func _place_hotspot(hotspot: Feature, at: Vector2) -> void:
	var plate := hotspot.plate_uuid
	var hit := Planet.hit_test(at.x, at.y, geometry)
	if hit != null and Hotspot.plate_problem(features.root, hotspot, hit.uuid).is_empty():
		plate = hit.uuid
	var error := document.set_hotspot(hotspot, at, plate, hotspot.time_step)
	if not error.is_empty():
		_report(error)
		return
	features.reload()
	_show_selection(features.feature_tree.get_selected_node())
	refresh_geometry()
	_show_measurement()


# What each held point of the drawing snapped to, side by side with
# outline_vertices: {"feature": pnid, "vertex": Vector2i(part, index)}, or an
# empty dictionary for a free point. A take back leaves the entry past the end
# alone, so a put back finds it again; a new point cuts the list to the points
# held before it goes on.
var draw_snapped: Array = []


# Append points to the drawing with what each one snapped to, each its own
# group for taking back; see draw_groups.
func _draw_points(points: PackedVector2Array, snaps: Array) -> void:
	draw_snapped.resize(outline_vertices.size())
	draw_snapped.append_array(snaps)
	_sync_groups(outline_vertices.size())
	for i in points.size():
		draw_groups.append(1)
	var held := outline_vertices.duplicate()
	held.append_array(points)
	taken_back = PackedVector2Array()
	taken_back_groups.clear()
	_set_tool_points(held)


# The vertex of a shown feature a click at lat, lon lands on, as a
# draw_snapped entry plus its world "point", or empty when Snap is off or no
# vertex is within SNAP_PIXELS.
func _draw_snap(lat: float, lon: float) -> Dictionary:
	if not snapping():
		return {}
	var screen: Variant = planet_view.latlon_to_screen(lat, lon)
	if screen == null:
		return {}
	var candidates := _vertices_on_screen()
	var picked := GeometryEdit.nearest_point(candidates[0], screen, SNAP_PIXELS)
	if picked < 0:
		return {}
	return {"feature": (candidates[3][picked] as Feature).pnid,
		"vertex": candidates[1][picked], "point": candidates[2][picked]}


# Shift+click: when the last held point sits on another vertex of the ring the
# click snapped to, append the vertices between the two along that ring, the
# clicked one included. A closed ring goes the way with fewer vertices. With no
# such point the click is a snapped one.
func _draw_trace(snap: Dictionary) -> void:
	var last := outline_vertices.size() - 1
	var previous: Dictionary = draw_snapped[last] \
		if last >= 0 and last < draw_snapped.size() and draw_snapped[last] != null else {}
	var part: int = snap["vertex"].x
	var feature: Feature = null
	for shown in geometry.features:
		if shown.pnid == snap["feature"]:
			feature = shown
	if previous.get("feature", -1) != snap["feature"] or previous["vertex"].x != part \
			or feature == null:
		_draw_points(PackedVector2Array([snap["point"]]), [snap])
		return

	var ring := Feature.apply_basis(feature.rings[part],
		Feature.world_basis(features.root, feature, document.current_time))
	var from: int = previous["vertex"].y
	var to: int = snap["vertex"].y
	# A closed polyline repeats its first vertex at the end; the repeat is the
	# first one as far as the way around is concerned.
	var closed := feature.geometry_kind == Feature.GeometryKind.POLYGON
	if ring.size() > 2 and ring[0] == ring[ring.size() - 1] and not closed:
		closed = true
		ring.resize(ring.size() - 1)
		from %= ring.size()
		to %= ring.size()

	var step := signi(to - from)
	var count := absi(to - from)
	if closed:
		var forward := posmod(to - from, ring.size())
		step = 1 if forward <= ring.size() - forward else -1
		count = forward if step == 1 else ring.size() - forward
	var points := PackedVector2Array()
	var snaps := []
	for k in range(1, count + 1):
		var index := posmod(from + step * k, ring.size())
		points.append(ring[index])
		snaps.append({"feature": snap["feature"], "vertex": Vector2i(part, index)})
	_draw_points(points, snaps)


# Single key shortcuts and the time keys, taken before the GUI pass rather than
# after it. A focused Button answers Space itself and a focused Tree scrolls on
# Page Up, so a shortcut left to _unhandled_key_input would reach whatever was
# last clicked instead of the application.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.is_pressed() or key.is_echo():
		return
	# Ctrl+S and the rest belong to the menus; only the time keys take Ctrl.
	if key.shift_pressed or key.alt_pressed or key.meta_pressed:
		return
	if _typing():
		return
	# Delete belongs to the vertex in hand ahead of Edit > Delete, whose
	# accelerator would otherwise take the whole feature.
	if key.keycode == KEY_DELETE and active_tool == Tool.VERTEX \
			and vertex_in_hand() != NO_VERTEX:
		_report_problem(delete_selected_vertex())
		get_viewport().set_input_as_handled()
	elif _hotkey(key):
		get_viewport().set_input_as_handled()


# Act on a shortcut and say whether it was one: Page Up and Page Down for the
# timeline's < and > buttons, with Ctrl for << and >>, Space for the animation,
# and a letter for each tool.
func _hotkey(event: InputEventKey) -> bool:
	if event.keycode == KEY_PAGEUP or event.keycode == KEY_PAGEDOWN:
		var older := event.keycode == KEY_PAGEUP
		if event.ctrl_pressed:
			timeline.jump_keyframe(older)
		else:
			timeline.step(older)
		return true
	if event.ctrl_pressed:
		return false
	if TOOL_KEYS.has(event.keycode):
		# A tool the toolbar greys out for what is selected is not armed by its
		# key either, and the key is still the application's rather than
		# something else's to act on.
		var tool: Tool = TOOL_KEYS[event.keycode]
		if not tool_buttons[tool].disabled:
			set_active_tool(tool)
		return true
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

	# Escape ends the pick whatever the tool, since the mode is not one.
	if picking != Pick.NONE and event.keycode == KEY_ESCAPE:
		end_pick()
		get_viewport().set_input_as_handled()
		return

	match active_tool:
		Tool.POLE:
			if event.keycode == KEY_ESCAPE and picking_axis:
				set_active_tool(Tool.MOVE)
			elif event.keycode == KEY_ESCAPE:
				_spin_cancel()
				pole_at = NO_POLE
				_refresh_selection_outline()
				_show_measurement()
			else:
				return
		Tool.DRAW:
			# A hotspot holds no points to cancel, so Escape leaves the tool.
			if event.keycode == KEY_ESCAPE and _drawing_hotspot():
				set_active_tool(Tool.MOVE)
			elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
				if _drawing_circle():
					_report(_circle_commit())
				else:
					_finish_stroke()
					_outline_commit()
			elif event.keycode == KEY_ESCAPE:
				_outline_cancel()
			else:
				return
		Tool.VERTEX:
			if event.keycode == KEY_S:
				_report(hold_split_from() if event.shift_pressed
					else split_at_selected_vertex())
			elif event.keycode == KEY_ESCAPE:
				_vertex_cancel_drag()
				_let_every_vertex_go()
				_update_tool_buttons()
			else:
				return
		Tool.MEASURE:
			if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
				# The path and its numbers stay where they are; the next click
				# starts a new one from where it falls.
				measure_done = not measure_points.is_empty()
				taken_back = PackedVector2Array()
				_show_measurement()
			elif event.keycode == KEY_ESCAPE:
				_measure_clear()
				_refresh_selection_outline()
			else:
				return
		Tool.TOPOLOGY:
			if event.keycode == KEY_ESCAPE:
				set_active_tool(Tool.MOVE)
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


# Show a problem, and leave the status bar alone when there is none: for an
# action that has already said what it did, such as a deletion that took a
# whole part with it.
func _report_problem(problem: String) -> void:
	if not problem.is_empty():
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
	_drop_stroke()
	outline_vertices = PackedVector2Array()
	taken_back = PackedVector2Array()
	draw_groups.clear()
	taken_back_groups.clear()
	_refresh_selection_outline()
	_show_measurement()


func _refresh_outline() -> void:
	if _drawing_circle():
		planet_view.planet.set_outline(_child_outline() + _circle_outline())
		_show_measurement()
		return
	var shown := outline_vertices.duplicate()
	if stroke_on:
		shown.append_array(stroke)
	planet_view.planet.set_outline(_child_outline() + [{
		"vertices": shown,
		"style": _drawing_outline_style(shown.size()),
	}])


# How the shape being drawn is shown. A polygon gets a faint closing segment,
# so it is clear that the shape is not finished; a multipoint gets markers only.
# A freehand line is sampled too finely to mark, so it is drawn with no vertex
# markers: open, or closed once a polygon has three points.
func _drawing_outline_style(count: int = outline_vertices.size()) -> Planet.OutlineStyle:
	var closed := drawing_kind() == Feature.GeometryKind.POLYGON and count >= 3
	if freehand():
		return Planet.OutlineStyle.OUTLINE if closed else Planet.OutlineStyle.OPEN_LINE
	match drawing_kind():
		Feature.GeometryKind.MULTIPOINT:
			return Planet.OutlineStyle.POINTS
		Feature.GeometryKind.POLYGON:
			if closed:
				return Planet.OutlineStyle.CLOSED_PREVIEW
	return Planet.OutlineStyle.OPEN


### The shape clipboard
#
# Copy Shape and Paste Shape carry the vertices of one feature into another,
# where the Vertex tool can then move, insert and delete them. The shape travels
# in world coordinates at the time it was copied, so it lands where it was seen
# whatever either feature has done since. The system clipboard is left out of
# it: that one carries whole features, for Copy and Paste.
#
# See Docs/Editing.md#copying-a-shape.


# The shape being held, as Document.shape_of() gives it, empty when nothing has
# been copied. It outlives the document it came from, which is what makes a
# shape carryable from one file into another.
var shape_clipboard: Dictionary = {}


func copy_shape() -> void:
	var selected := features.feature_tree.get_selected_node()
	var shape := document.shape_of(selected)
	if shape.is_empty():
		_report("There is no shape to copy.")
		return
	shape_clipboard = shape
	_update_edit_menu()
	var parts: int = (shape["rings"] as Array).size()
	_report("Copied %d part%s of %s." % [parts, "" if parts == 1 else "s", selected.title])


func paste_shape() -> void:
	var selected := features.feature_tree.get_selected_node()
	# While drawing, the shape's vertices become held points of the drawing,
	# every part in order, and nothing reaches the document until Enter.
	if active_tool == Tool.DRAW and selected != null and not selected.is_group \
			and not shape_clipboard.is_empty():
		var points := PackedVector2Array()
		for ring in shape_clipboard["rings"]:
			points.append_array(ring)
		var snaps := []
		snaps.resize(points.size())
		_draw_points(points, snaps)
		_report("")
		return
	var error := document.paste_shape(selected, shape_clipboard)
	if not error.is_empty():
		_report(error)
		return
	features.reload()
	refresh_geometry()
	# The Vertex tool, so the pasted vertices can be edited straight away, which
	# is what copying a shape into a feature is for.
	set_active_tool(Tool.VERTEX)
	_report("")


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
	if screen == null:
		return
	if event.ctrl_pressed:
		_vertex_ctrl_press(feature, screen)
	else:
		_vertex_press(feature, screen)


# Ctrl+press takes out the vertex under the pointer the way Delete does, and
# does nothing anywhere else.
func _vertex_ctrl_press(feature: Feature, screen: Vector2) -> void:
	var own := _vertices_on_screen(feature)
	var picked := GeometryEdit.nearest_point(own[0], screen, VERTEX_PICK_PIXELS)
	if picked >= 0:
		hovered_vertex = own[1][picked]
		_report_problem(delete_selected_vertex())


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
		# An edge with an end round the back, where a screen distance means
		# nothing, is left alone; the edges on the near side are offered
		# whatever the rest of the ring does.
		var found := GeometryEdit.nearest_visible_segment(
			_ring_on_screen(feature, part), screen, closed)
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


# Take out the vertex the tool is working on. A part left under the minimum its
# kind needs goes with it, and the status bar says so, since a triangle
# vanishing under one key press should not pass in silence. That is how one
# part of a feature of several is taken out; the feature itself stays, with no
# geometry once its last part is gone, and is drawn on again like a new one.
# Returns why it could not be done, or an empty string.
func delete_selected_vertex() -> String:
	var feature := features.feature_tree.get_selected_node()
	var target := vertex_in_hand()
	if feature == null or feature.is_group or target == NO_VERTEX:
		return "The pointer is on no vertex, and none is picked."
	if target.x >= feature.rings.size() or target.y >= feature.rings[target.x].size():
		return "That vertex is no longer there."
	var problem := GeometryEdit.removal_problem(feature.rings[target.x], target.y)
	if not problem.is_empty():
		return problem
	var parts := feature.rings.size()
	var error := document.remove_vertex(feature, target.x, target.y)
	if not error.is_empty():
		return error
	hovered_vertex = NO_VERTEX
	selected_vertex = NO_VERTEX
	split_from = NO_VERTEX
	_after_vertex_edit()
	if feature.rings.size() < parts:
		_show_measurement("Removed the last part of %s" % feature.title
			if feature.rings.is_empty() else "Removed a part of %s" % feature.title)
	else:
		_show_measurement()
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
		and node.geometry_kind == Feature.GeometryKind.POLYGON and not node.is_circle()


func _on_split_input(lat: float, lon: float, event: InputEvent) -> void:
	if event is not InputEventMouseButton or not event.is_pressed():
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		_place_point(Vector2(lat, lon))
	elif event.button_index == MOUSE_BUTTON_RIGHT and not split_points.is_empty():
		undo()


# Cut the selected polygon along the points clicked. The part cut is the one
# whose boundary is nearest the first point. A cut that touches no part of a
# feature of several divides the parts instead, each to its side of the cut;
# see Document.divide_feature(). A refused cut keeps its points, so the one at
# fault can be taken back rather than the whole cut clicked again.
#
# Returns what the status bar says about the cut: why it was refused, or which
# features it left behind.
func split_along_points() -> String:
	var feature := features.feature_tree.get_selected_node()
	if not _can_split_along(feature):
		return "Select a polygon to split."
	if split_points.size() < 2:
		return "Click where the cut starts and where it ends."
	var path := _split_path(feature)
	# Neither a ridge nor a crust follows a divide, since the two share no edge.
	var ridge := ridge_check.button_pressed and not ridge_check.disabled
	var crust := ridge and crust_check.button_pressed
	var error: String
	if _split_divides(feature):
		error = document.divide_feature(feature, path, children_check.button_pressed)
	else:
		var part := 0
		var nearest := INF
		for index in feature.rings.size():
			var distance: float = GeometryEdit.nearest_segment(feature.rings[index], path[0], true)[1]
			if distance < nearest:
				nearest = distance
				part = index
		error = document.split_feature_along(feature, part, path, ridge, crust,
			children_check.button_pressed)
	if not error.is_empty():
		return error
	# The halves, and the ridge and crust behind them, sit side by side where
	# the polygon was, so the status bar reads them straight off the tree. The
	# children cut with them are wherever they were, and the document names them.
	var group := features.root.find_parent(feature)
	var at := group.find_child(feature)
	var made := PackedStringArray()
	for child in group.children.slice(at, at + 2 + int(ridge) + 4 * int(crust)):
		made.append(child.title)
	for piece in document.split_children:
		made.append(piece.title)
	split_points = PackedVector2Array()
	features.reload()
	refresh_geometry()
	set_active_tool(Tool.MOVE)
	return "Split into %s" % ", ".join(made)


# Grey out Ridge while the points clicked would divide the parts rather than
# cut one, since the two sides of a divide share no edge to leave a ridge
# along; and Crust whenever there is no ridge, since the crust lies between the
# ridge and the halves.
func _update_split_switches() -> void:
	ridge_check.disabled = _split_divides(features.feature_tree.get_selected_node())
	crust_check.disabled = ridge_check.disabled or not ridge_check.button_pressed


# The points clicked so far, in the selected feature's own frame: they were
# clicked in world space, and a feature keeps its vertices before its rotation.
func _split_path(feature: Feature) -> PackedVector2Array:
	var into_local := Feature.world_basis(
		features.root, feature, document.current_time).transposed()
	return Feature.apply_basis(split_points, into_local)


# Whether the points clicked so far would divide the feature's parts rather
# than cut one of them: two or more points, none of them inside a part and no
# stretch between them crossing a part's edge. Until there are two points there
# is nothing to touch a part with, so the answer is a cut.
func _split_divides(feature: Feature) -> bool:
	if feature == null or split_points.size() < 2 or feature.rings.size() < 2:
		return false
	var path := _split_path(feature)
	for ring in feature.rings:
		if GeometryEdit.touches(ring, path):
			return false
	return true


### Drawing a circle
#
# The Draw tool on a feature typed Circle. The circle is drawn as a preview and
# committed as a polyline of a chosen number of segments. Two clicks are a
# centre and a point on the rim;
# three are three points the circle passes through. Which one is meant follows
# from how many points have been clicked, so there is no mode to pick: the
# preview shows what the clicks so far describe and a third click changes it
# from the one construction to the other. The clicked points are held in
# outline_vertices, like the vertices of any other shape being drawn, so undo,
# redo and a cancel treat them alike. Snapping and tracing do not apply.


# Called by _on_draw_input, which has already checked the event and the
# selection.
func _on_draw_circle_input(lat: float, lon: float, event: InputEvent) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if outline_vertices.size() >= 3:
			outline_vertices = PackedVector2Array()
		_place_point(Vector2(lat, lon))
	elif event.button_index == MOUSE_BUTTON_RIGHT and not outline_vertices.is_empty():
		undo()


# The points clicked for the circle, or none while no circle is being drawn.
func circle_points() -> PackedVector2Array:
	return outline_vertices if _drawing_circle() else PackedVector2Array()


# The circle the clicked points describe, as [centre, angular radius], or an
# empty array while they describe none.
func circle_from_points() -> Array:
	var points := circle_points()
	if points.size() == 2:
		var radius := Circle.radius_to(points[0], points[1])
		return [] if radius < 1e-6 else [points[0], radius]
	if points.size() == 3:
		return Circle.through(points[0], points[1], points[2])
	return []


# How many segments the circle is cut into, as the toolbar has it.
func circle_segments() -> int:
	return int(segments_spin.value)


# The circle being previewed, in world coordinates, or an empty ring. It is the
# polyline the tool commits, so it repeats its first vertex at the end.
func circle_ring() -> PackedVector2Array:
	var circle := circle_from_points()
	if circle.is_empty():
		return PackedVector2Array()
	return Circle.vertices(circle[0], circle[1], circle_segments(), false)


# The clicked points as markers, with the circle they describe over them.
func _circle_outline() -> Array:
	var parts: Array = []
	if not outline_vertices.is_empty():
		parts.append({"vertices": outline_vertices, "style": Planet.OutlineStyle.POINTS})
	var ring := circle_ring()
	if not ring.is_empty():
		# The shader draws the curve itself, from the center and a point of
		# the rim, so the preview is the circle the feature will draw.
		parts.append({"vertices": PackedVector2Array([circle_from_points()[0], ring[0]]),
			"style": Planet.OutlineStyle.CIRCLE})
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

	# The circle was worked out in world space; a feature keeps its own frame,
	# which at the current time is where its keyframes put it. The feature is
	# typed Circle already, since that is what made Draw draw a circle, and the
	# new circle takes the place of the one it had, drawn at both ends of the
	# axis if that one was.
	var into_local := Feature.world_basis(
		features.root, selected, document.current_time).transposed()
	var center := Feature.apply_basis(PackedVector2Array([circle[0]]), into_local)[0]
	var error := document.set_circle(selected, center, circle[1], circle_segments(),
		selected.polar)
	if not error.is_empty():
		return error

	outline_vertices = PackedVector2Array()
	features.reload()
	refresh_geometry()
	set_active_tool(Tool.MOVE)
	return ""


### The Topology tool
#
# Building a line topology by clicking the features it runs along, in order. The
# tool has no toolbar button: the Pick toggle of the section table arms it for
# the selected topology, and Escape, another selection or another tool ends it.
# A click adds the whole of one part of whatever is under it as a section; a
# right click takes the last section back. There is nothing to commit: each
# click is one edit and one undo version, so the boundary is on the globe as it
# grows.
#
# Which section runs which way, and which vertices of a feature a section
# covers, are set afterwards in the Properties panel; see
# Docs/Editing.md#topologies.


func start_section_pick(on: bool) -> void:
	var feature := features.feature_tree.get_selected_node()
	if on and _can_build_topology(feature):
		pick_pnid = feature.pnid
		set_active_tool(Tool.TOPOLOGY)
	elif active_tool == Tool.TOPOLOGY or on:
		# Let go, or refused: either way the toggle shows what the tool is.
		set_active_tool(Tool.MOVE)


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


### The Measure tool
#
# The points that have been clicked and the distance along them. A path takes
# any number of points; Enter finishes it and the next click starts a new one.
# The radius the distances are read against is a preference; see
# Config.get_planet_radius().

var measure_points := PackedVector2Array()

# Whether the segment ending at each point runs along the parallel of the point
# before it rather than along the great circle. Side by side with
# measure_points; the first entry is never read, since no segment ends at the
# first point.
#
# Held the way draw_snapped is, which is what keeps it in step with the shared
# tool-points undo without a taken-back array of its own: a take back leaves the
# entry past the end of the points alone, so Ctrl+Y finds the flag again, and a
# new click cuts the list back to the points held before it appends.
var measure_parallel: Array[bool] = []

# Whether Enter has finished the path. A finished path stays on the planet and
# in the status bar; the next left click throws it away and starts a new one,
# rather than taking its last point back.
var measure_done := false

# How finely a parallel segment is sampled for drawing, in degrees of longitude.
const MEASURE_PARALLEL_STEP := 1.0


func _on_measure_input(lat: float, lon: float, event: InputEvent) -> void:
	if event is not InputEventMouseButton or not event.is_pressed():
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		if measure_done:
			_measure_clear()
		var point := Vector2(lat, lon)
		# With the switch on, the click lands on the parallel of the last point,
		# so the segment it closes runs along that latitude. The first point of
		# a path is placed where it was clicked whatever the switch says.
		var parallel := parallel_check.button_pressed and not measure_points.is_empty()
		if parallel:
			point.x = measure_points[measure_points.size() - 1].x
		measure_parallel.resize(measure_points.size())
		measure_parallel.append(parallel)
		_place_point(point)
	elif event.button_index == MOUSE_BUTTON_RIGHT and not measure_done \
			and not measure_points.is_empty():
		undo()


# Whether the segment ending at the given point follows the parallel. The flags
# may run past the points, holding those of points taken back.
func _measure_flag(index: int) -> bool:
	return index < measure_parallel.size() and measure_parallel[index]


# The flags of the points the tool holds, for the automation port.
func measure_flags() -> Array[bool]:
	var flags: Array[bool] = []
	for i in range(measure_points.size()):
		flags.append(_measure_flag(i))
	return flags


func _measure_clear() -> void:
	measure_points = PackedVector2Array()
	measure_parallel = []
	measure_done = false
	taken_back = PackedVector2Array()
	_show_measurement()


# What the Measure tool draws: the path with every parallel segment replaced by
# the run of samples that follows the latitude, and the clicked points as
# markers over it. The run is markerless, or every sample would wear a dot.
func _measure_outline() -> Array:
	if measure_points.is_empty():
		return []
	var run := PackedVector2Array([measure_points[0]])
	for i in range(1, measure_points.size()):
		if _measure_flag(i):
			run.append_array(Measure.parallel_points(measure_points[i - 1],
				measure_points[i], MEASURE_PARALLEL_STEP).slice(1))
		else:
			run.append(measure_points[i])
	return [
		{"vertices": run, "style": Planet.OutlineStyle.OPEN_LINE},
		{"vertices": measure_points, "style": Planet.OutlineStyle.POINTS},
	]


# What the status bar says about distance: an error while there is one to
# report, the measured path while the Measure tool has points, the length of the
# selected geometry while it has none, and nothing at all otherwise.
func _show_measurement(error: String = "") -> void:
	if not error.is_empty():
		status_measure.text = error
		return

	if picking == Pick.PARENT:
		status_measure.text = "Pick the feature to follow"
		return
	if picking == Pick.PLATE:
		status_measure.text = "Pick the feature the hotspot burns through"
		return

	if _drawing_hotspot():
		status_measure.text = "Click to place %s; click again to move it" % \
			features.feature_tree.get_selected_node().title
		return

	if active_tool == Tool.TOPOLOGY:
		var building := features.feature_tree.get_selected_node()
		var count := 0 if building == null else building.sections.size()
		status_measure.text = "click the features the topology runs along" if count == 0 \
			else "%d section%s   right click takes the last one back" % [
				count, "" if count == 1 else "s"]
		return

	if _drawing_circle():
		var circle := circle_from_points()
		status_measure.text = "click a centre and the rim, or three points on the rim" \
			if circle.is_empty() else "centre %.2f° %.2f°   radius %s   %d segments" % [
				(circle[0] as Vector2).x, (circle[0] as Vector2).y,
				Circle.format_radius(circle[1]), circle_segments()]
		return

	if picking_axis:
		status_measure.text = "click the planet to put the axis of the circle there"
		return

	if _spins(active_tool):
		if not is_nan(spin_angle):
			status_measure.text = "Rotating %.1f°" % rad_to_deg(spin_angle)
		elif active_tool == Tool.POLE and pole_at == NO_POLE:
			status_measure.text = "click to place the pole to turn about"
		else:
			status_measure.text = "drag the feature to turn it"
		return

	var radius := Config.get_planet_radius()
	if active_tool == Tool.MEASURE and measure_points.size() >= 2:
		var last := measure_points.size() - 1
		var total := Measure.format_km(
			Measure.measured_length(measure_points, measure_parallel, radius))
		# From the third point on the last segment is worth naming as well; with
		# two points the total is that segment.
		status_measure.text = total if last == 1 else "%s, last %s" % [total,
			Measure.format_km(Measure.segment_length(measure_points[last - 1],
				measure_points[last], _measure_flag(last), radius))]
		# The total beside the line itself, at the midpoint of the last segment,
		# so it stays near where the pointer is working.
		var middle := Measure.along_parallel(measure_points[last - 1], measure_points[last], 0.5) \
			if _measure_flag(last) \
			else Measure.along(measure_points[last - 1], measure_points[last], 0.5)
		planet_view.show_measurement(total, middle.x, middle.y)
		return
	planet_view.hide_measurement()
	if active_tool == Tool.MEASURE:
		status_measure.text = "click the next point   Enter finishes" \
			if measure_points.size() == 1 else "click two points to measure"
		return
	if active_tool == Tool.SPLIT:
		if split_points.size() < 2:
			status_measure.text = "click across the polygon, from one edge to another"
		elif _split_divides(features.feature_tree.get_selected_node()):
			status_measure.text = "%d points   Enter divides the parts along them" \
				% split_points.size()
		else:
			status_measure.text = "%d points   Enter splits the polygon along them" \
				% split_points.size()
		return

	if freehand():
		# The held count says what a stroke came to once simplified, which is
		# what the tolerance is set by.
		status_measure.text = "drag to draw freehand   Enter commits" if outline_vertices.is_empty() 			else "%d vertices   drag to add a stroke   Enter commits" % outline_vertices.size()
		return

	var selected := features.feature_tree.get_selected_node()
	var length := Measure.geometry_length(selected, radius)
	if length <= 0.0:
		status_measure.text = ""
	elif selected.drawn_as() == Feature.GeometryKind.POLYGON:
		status_measure.text = "%s around %s, %s" % [Measure.format_km(length), selected.title,
			Measure.format_area(Measure.geometry_area(selected, radius))]
	else:
		status_measure.text = "%s along %s" % [Measure.format_km(length), selected.title]


### Vertices on screen


# Where vertices are in window pixels, for picking one and for snapping to one.
#
# Returns four lists side by side: the window pixels, the (part, index) each
# came from, the world latitude and longitude each is at, and the feature it
# belongs to. A vertex on the
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
	var owners: Array[Feature] = []

	var wanted: Array[Feature] = []
	if only != null:
		wanted.append(only)
	else:
		# Each feature once rather than once per column of the geometry: a
		# crust takes a column per band and would offer its vertices that
		# many times over.
		for feature: Feature in geometry.index_of:
			if geometry.shown[geometry.index_of[feature]]:
				wanted.append(feature)

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
				owners.append(feature)
	return [points, places, world, owners]


# Where each vertex of one part of a feature is on screen, index for index with
# the ring, null for a vertex that is not shown: round the back of the globe,
# or off the map.
func _ring_on_screen(feature: Feature, part: int) -> Array:
	var m := Feature.world_basis(features.root, feature, document.current_time)
	var points := []
	for vertex in Feature.apply_basis(feature.rings[part], m):
		points.append(planet_view.latlon_to_screen(vertex.x, vertex.y))
	return points


### Picking the parent off the planet
#
# The pointer buttons on the Follow row and on a hotspot's Plate row of the
# Properties panel arm a one shot pick: the next left click on the planet names
# the feature under it in that row's picker, and nothing else about the
# application changes. The selection stays where it is and so does the tool,
# so the planet's own clicks are held back with `tool_handles_clicks` and given
# back once the mode is over. A click that picks nothing the row takes says why
# and leaves the mode on, so a miss costs one more click. See
# Docs/Properties.md#coupling and Docs/Editing.md#hotspots.

# What the pick is for: nothing, the parent to follow or the plate of a hotspot.
enum Pick { NONE, PARENT, PLATE }

var picking := Pick.NONE


func start_parent_pick() -> void:
	_start_pick(Pick.PARENT)


func start_plate_pick() -> void:
	_start_pick(Pick.PLATE)


func _start_pick(pick: Pick) -> void:
	picking = pick
	planet_view.tool_handles_clicks = true
	properties.show_picking(pick == Pick.PARENT, pick == Pick.PLATE)
	_show_measurement()


func end_pick() -> void:
	if picking == Pick.NONE:
		return
	picking = Pick.NONE
	# What _set_tool() would have left it as, rather than what it was when the
	# mode started, so a tool picked while the pointer was armed still decides.
	planet_view.tool_handles_clicks = active_tool != Tool.MOVE
	properties.show_picking(false, false)
	_show_measurement()


func _on_pick_input(lat: float, lon: float, event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.is_pressed() or button.button_index != MOUSE_BUTTON_LEFT:
		return
	var hit := Planet.hit_test(lat, lon, geometry)
	if hit == null:
		_report("Click a feature to follow." if picking == Pick.PARENT
			else "Click the feature the hotspot burns through.")
		return
	if picking == Pick.PARENT and hit.geometry_kind == Feature.GeometryKind.TOPOLOGY:
		_report("A topology is not something to follow.")
		return
	var problem := properties.pick_parent_uuid(hit.uuid) if picking == Pick.PARENT \
		else properties.pick_plate_uuid(hit.uuid)
	if not problem.is_empty():
		_report(problem)
		return
	end_pick()


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
		planet_view.planet.set_feature_state(geometry, hovered_feature, _highlighted_feature(),
			coupled_children)


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
# be built again. A hotspot's track is the same. That costs a document holding
# either the cheap path, which is why it is asked for rather than taken.
func refresh_motion() -> void:
	if Topology.holds_any(features.root) or Hotspot.holds_any(features.root):
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
	_find_children()
	planet_view.planet.set_feature_state(geometry, hovered_feature, _highlighted_feature(),
		coupled_children)
	_refresh_selection_outline()


# The children of the selected feature at the current time, when the View menu
# asks for it, for the planet to draw orange and the tree to tint, in every
# tool. A selected group stands for the leaves under it.
func _find_children() -> void:
	var selected := features.feature_tree.get_selected_node()
	var found: Array[Feature] = []
	if highlight_children and selected != null:
		found = Coupling.children_of(features.root, selected.uuid, document.current_time)
	coupled_children = found
	features.feature_tree.mark_children(found)


# The orange outlines of the children that are polygons, where the planet draws
# them at all; the shader colors the lines and markers of the other children
# itself.
func _child_outline() -> Array:
	var parts: Array = []
	for child in coupled_children:
		var index: int = geometry.index_of.get(child, -1)
		if index < 0 or not geometry.shown[index] \
				or child.drawn_as() != Feature.GeometryKind.POLYGON:
			continue
		for ring in child.rings:
			parts.append({"vertices": Feature.apply_basis(ring, geometry.bases[index]),
				"style": Planet.OutlineStyle.CHILD})
	return parts


# The feature whose lines the shader draws over a white halo: the selected one,
# in the tools that trace the selection. A circle being drawn and the Measure
# tool draw their own overlay instead, and the Vertex tool traces the rings with a dot on every
# vertex, which the halo would cover.
func _highlighted_feature() -> Feature:
	if active_tool in [Tool.VERTEX, Tool.MEASURE] or _drawing_circle():
		return null
	var selected := features.feature_tree.get_selected_node()
	if selected == null or selected.is_group:
		return null
	return selected


# Trace the selected feature over the geometry in the same white the shape
# being drawn is shown in. A polygon gets an outline along its rings and a
# multipoint larger markers; a line needs nothing here, since the shader draws
# it over a halo. Only the Vertex tool puts a dot on every vertex, since picking
# vertices is what it is for.
func _refresh_selection_outline() -> void:
	# A circle being drawn shows the circle its clicks describe, so what
	# pressing Enter would commit is on the globe before it is committed. That
	# covers a change of the segment count, which comes through here.
	if _drawing_circle():
		_refresh_outline()
		return
	# Don't overwrite the drawing outline
	if not outline_vertices.is_empty():
		return
	# The Measure tool draws the path it has been given instead, so the points
	# clicked and the line between them are visible while the distance is read.
	if active_tool == Tool.MEASURE:
		planet_view.planet.set_outline(_child_outline() + _measure_outline())
		return
	# The pole the Pole tool turns about and the children are drawn along with
	# the selection, so they are on the globe whatever else is.
	var parts: Array = _pole_outline() + _child_outline()
	var selected := features.feature_tree.get_selected_node()
	if selected == null or selected.is_group or not selected.has_geometry():
		planet_view.planet.set_outline(parts)
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
				planet_view.planet.set_outline(parts)
				return

	var m := Feature.world_basis(features.root, selected, document.current_time)
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
	# A feature just typed Hotspot waits for its place, so Draw is armed for it.
	var unplaced_hotspot := selected != null and selected.is_hotspot() \
		and not selected.has_geometry() and active_tool != Tool.DRAW
	if not _tool_fits(selected) or unplaced_hotspot:
		set_active_tool(_tool_for(selected))
	elif not outline_vertices.is_empty():
		_refresh_outline()
	timeline.show_keyframes(selected)
	kinematics.show_node(selected)
	refresh_geometry()

