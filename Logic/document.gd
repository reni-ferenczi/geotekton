class_name Document
extends RefCounted

# The open document: the feature tree, the file it came from and whether it
# differs from what is on disk.
#
# The undo stack is the only source of the dirty flag. Every edit records a
# version; the document is clean exactly while the stack sits on the version
# that was last written to or read from a file, so undoing back to that point
# makes it clean again.

const APPLICATION := "middle-earth"
const EXTENSION := ".middle-earth"
const UNTITLED := "Untitled"
const MAX_UNDO_STEPS := 100

# The feature tree was replaced: rebuild the UI from root.
signal root_replaced()

# The path, the dirty flag or the undo depth changed: refresh title and buttons.
signal state_changed()

var root: Feature
var path: String = ""

# Recorded versions of the tree, oldest first, and how many of them are applied.
# The current version is versions[applied - 1]; anything above applied is redo.
var versions: Array[Feature] = []
var applied: int = 0

# The value of applied that matches the file on disk, or -1 once that version
# has fallen out of the undo buffer and the document can no longer become clean.
var _saved: int = 0


func _init() -> void:
	reset()


### The document as a whole


# Start an empty document with a fresh undo stack, as after File > New.
func reset() -> void:
	root = Feature.create_group("Planet")
	root.is_root = true
	versions.clear()
	applied = 0
	record()
	_saved = applied
	path = ""
	root_replaced.emit()
	state_changed.emit()


func is_dirty() -> bool:
	return applied != _saved


# The file name for the window title, or "Untitled" before the first save.
func display_name() -> String:
	return UNTITLED if path.is_empty() else path.get_file()


### Undo stack


# Record the current tree as a new version, dropping any redo versions.
func record() -> void:
	while versions.size() > applied:
		versions.pop_back()
	versions.append(root.clone())
	applied += 1
	while applied > MAX_UNDO_STEPS:
		versions.pop_front()
		applied -= 1
		_saved -= 1
		if _saved < 1:
			# The saved version is gone, so the document stays dirty from here.
			_saved = -1
	state_changed.emit()


func can_undo() -> bool:
	return applied > 1


func can_redo() -> bool:
	return applied < versions.size()


func undo() -> void:
	if not can_undo():
		return
	applied -= 1
	_apply_current()


func redo() -> void:
	if not can_redo():
		return
	applied += 1
	_apply_current()


func _apply_current() -> void:
	root = versions[applied - 1].clone()
	root_replaced.emit()
	state_changed.emit()


### Files


# Read a document from a file. Returns an empty string on success, otherwise a
# message describing why the file could not be read.
func load_from_file(file_path: String) -> String:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return "Cannot read %s: %s" % [file_path, error_string(FileAccess.get_open_error())]

	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return "%s is not valid JSON: %s" % [file_path, json.get_error_message()]

	var data: Variant = json.data
	if data is not Dictionary:
		return "%s is not a Middle Earth file: the root is not an object" % file_path
	if data.get("application", "") != APPLICATION:
		return "%s is not a Middle Earth file" % file_path

	var loaded := Feature.from_json(migrate(data)["features"])
	loaded.is_root = true

	root = loaded
	versions.clear()
	applied = 0
	record()
	_saved = applied
	path = file_path
	root_replaced.emit()
	state_changed.emit()
	return ""


# Write the document to a file and mark it clean. Returns an empty string on
# success, otherwise a message describing why the file could not be written.
func save_to_file(file_path: String) -> String:
	var data := {
		"application": APPLICATION,
		"version": Application.VERSION,
		"features": root.to_json(),
	}
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		return "Cannot write %s: %s" % [file_path, error_string(FileAccess.get_open_error())]
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

	path = file_path
	_saved = applied
	state_changed.emit()
	return ""


static func migrate(data: Dictionary) -> Dictionary:
	# No format migrations while the major version is 0.
	# Once version 1.0.0 is reached, add migrations here for each file format change.
	return data
