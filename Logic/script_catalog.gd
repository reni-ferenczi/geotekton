class_name ScriptCatalog

# The Python scripts the configured directories hold, read as files rather than
# through the interpreter. A script says what it is in its module docstring, and
# that is enough for the menu and for --help-command, so the catalog is there
# whether an interpreter is running or not — with --no-python the entries are
# still listed, they simply cannot be run.
#
# Only a script with a docstring is listed. A file without one has nothing to
# put on a menu, and a working file left in a script folder should not become a
# command by accident. See Docs/Scripting.md.

const EXTENSION := ".py"

# How far into a file the docstring is looked for. A file that opens with two
# hundred lines of comments is not one of ours.
const MAX_HEADER_LINES := 200


class Entry extends RefCounted:
	# The file stem, which is what --help-command is given.
	var name: String
	# The absolute path the interpreter is asked to run.
	var path: String
	# The module docstring, whitespace trimmed.
	var doc: String

	# What a menu entry for this script says: the first line of its docstring.
	func title() -> String:
		return doc.split("\n")[0].strip_edges()


# Every script with a docstring in these directories, sorted by name, with the
# first of two files of the same name winning so an earlier directory can put
# its own version of a command in front of a later one.
static func scan(directories: Array) -> Array[Entry]:
	var entries: Array[Entry] = []
	var seen := {}
	for directory in directories:
		for file_name in _python_files(str(directory)):
			var name := file_name.get_basename()
			if seen.has(name):
				continue
			var path := str(directory).path_join(file_name)
			var doc := docstring(_read(path))
			if doc.is_empty():
				continue
			var entry := Entry.new()
			entry.name = name
			entry.path = path
			entry.doc = doc
			seen[name] = true
			entries.append(entry)
	entries.sort_custom(func(a: Entry, b: Entry) -> bool: return a.name < b.name)
	return entries


# The entry with this name, or null when no directory holds one.
static func find(directories: Array, name: String) -> Entry:
	for entry in scan(directories):
		if entry.name == name:
			return entry
	return null


static func _python_files(directory: String) -> PackedStringArray:
	if directory.is_empty() or not DirAccess.dir_exists_absolute(directory):
		return PackedStringArray()
	var found := PackedStringArray()
	for file_name in DirAccess.get_files_at(directory):
		# A dunder file is machinery rather than a command.
		if file_name.ends_with(EXTENSION) and not file_name.begins_with("_"):
			found.append(file_name)
	found.sort()
	return found


static func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	return "" if file == null else file.get_as_text()


# The module docstring of a Python source file, empty when it has none.
#
# What comes before it is skipped: a shebang, comments, blank lines and an
# encoding declaration. Anything else means the file opens with code, and a
# string after that is not a docstring.
static func docstring(source: String) -> String:
	var lines := source.split("\n")
	var index := 0
	while index < lines.size() and index < MAX_HEADER_LINES:
		var line := lines[index].strip_edges()
		if line.is_empty() or line.begins_with("#"):
			index += 1
			continue
		break
	if index >= lines.size():
		return ""

	var rest := "\n".join(lines.slice(index))
	for quote in ['"""', "'''", '"', "'"]:
		if not rest.begins_with(quote):
			continue
		var end := rest.find(quote, quote.length())
		if end < 0:
			return ""
		return rest.substr(quote.length(), end - quote.length()).strip_edges()
	return ""
