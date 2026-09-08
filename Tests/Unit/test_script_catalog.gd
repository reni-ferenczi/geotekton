extends TestCase

# The script catalog reads Python files as text: what the menu shows and what
# --help-command prints both come from the module docstring, with no
# interpreter involved.

const SCRATCH := "user://test_script_catalog"


func _scratch() -> String:
	var directory := ProjectSettings.globalize_path(SCRATCH)
	DirAccess.make_dir_recursive_absolute(directory)
	for file_name in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory.path_join(file_name))
	return directory


func _write(directory: String, file_name: String, text: String) -> void:
	var file := FileAccess.open(directory.path_join(file_name), FileAccess.WRITE)
	file.store_string(text)
	file.close()


### The docstring itself


func test_a_triple_quoted_docstring_is_read() -> void:
	assert_eq(ScriptCatalog.docstring('"""Add a craton."""\n\nprint(1)\n'), "Add a craton.")
	assert_eq(ScriptCatalog.docstring("'''Add a craton.'''\n"), "Add a craton.")


func test_a_single_quoted_docstring_is_read() -> void:
	assert_eq(ScriptCatalog.docstring('"Add a craton."\n'), "Add a craton.")


func test_a_docstring_over_several_lines_keeps_its_shape() -> void:
	var doc := ScriptCatalog.docstring('"""Add a craton.\n\nDetails follow.\n"""\n')
	assert_eq(doc, "Add a craton.\n\nDetails follow.")


func test_comments_and_blank_lines_before_the_docstring_are_skipped() -> void:
	assert_eq(ScriptCatalog.docstring('#!/usr/bin/env python\n# -*- coding: utf-8 -*-\n\n"""Hi."""\n'), "Hi.")


func test_a_file_that_starts_with_code_has_no_docstring() -> void:
	assert_eq(ScriptCatalog.docstring('import sys\n"""Not a docstring."""\n'), "")
	assert_eq(ScriptCatalog.docstring(""), "")
	assert_eq(ScriptCatalog.docstring("print(1)\n"), "")


func test_an_unterminated_docstring_is_not_one() -> void:
	assert_eq(ScriptCatalog.docstring('"""Never closed\n\nprint(1)\n'), "")


### Scanning a folder


func test_only_python_files_with_a_docstring_are_listed() -> void:
	var directory := _scratch()
	_write(directory, "add_craton.py", '"""Add a craton at the equator."""\n')
	_write(directory, "silent.py", "print('no docstring')\n")
	_write(directory, "_helper.py", '"""Machinery, not a command."""\n')
	_write(directory, "notes.txt", '"""Not Python."""\n')

	var entries := ScriptCatalog.scan([directory])
	assert_eq(entries.size(), 1, "only the documented script is a command")
	assert_eq(entries[0].name, "add_craton")
	assert_eq(entries[0].doc, "Add a craton at the equator.")
	assert_eq(entries[0].path, directory.path_join("add_craton.py"))


func test_entries_are_sorted_and_the_first_directory_wins() -> void:
	var first := _scratch()
	var second := ProjectSettings.globalize_path(SCRATCH + "_second")
	DirAccess.make_dir_recursive_absolute(second)
	for file_name in DirAccess.get_files_at(second):
		DirAccess.remove_absolute(second.path_join(file_name))

	_write(first, "zebra.py", '"""Last by name."""\n')
	_write(first, "shared.py", '"""The one in front."""\n')
	_write(second, "shared.py", '"""The one behind."""\n')
	_write(second, "alpha.py", '"""First by name."""\n')

	var entries := ScriptCatalog.scan([first, second])
	var names: Array[String] = []
	for entry in entries:
		names.append(entry.name)
	assert_eq(names, ["alpha", "shared", "zebra"] as Array[String])
	assert_eq(ScriptCatalog.find([first, second], "shared").doc, "The one in front.")


func test_a_directory_that_is_not_there_is_no_error() -> void:
	assert_eq(ScriptCatalog.scan(["C:/no/such/folder", ""]).size(), 0)


func test_find_answers_by_name() -> void:
	var directory := _scratch()
	_write(directory, "add_craton.py", '"""Add a craton.\n\nMore about it.\n"""\n')
	var entry := ScriptCatalog.find([directory], "add_craton")
	assert_true(entry != null, "the script is found by its file name")
	assert_eq(entry.title(), "Add a craton.", "the menu shows the first line")
	assert_true("More about it." in entry.doc, "the whole docstring is kept")
	assert_true(ScriptCatalog.find([directory], "missing") == null)
