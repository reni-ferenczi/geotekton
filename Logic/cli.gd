class_name Cli

# Command line switches. Godot swallows its own options, so the application's
# switches come after a bare "--" and arrive through OS.get_cmdline_user_args():
#
#   Geotekton -- --version

# Every supported switch, as name and description. The help text is built from
# this list, so a new switch shows up in --help by adding it here.
const SWITCHES := [
	["--help", "Print this help and exit"],
	["--help-command=NAME", "Print what the script NAME does and exit"],
	["--version", "Print the application version and exit"],
	["--no-python", "Start without the Python interpreter"],
	["--automation-port=PORT", "Open the test automation port on 127.0.0.1:PORT"],
]

const AUTOMATION_PORT_PREFIX := "--automation-port="
const HELP_COMMAND_PREFIX := "--help-command="
const NO_PYTHON := "--no-python"


# Act on the switches before anything is loaded. Returns the exit code the
# application should quit with, or -1 when it should keep running.
static func handle(args: PackedStringArray) -> int:
	var index := 0
	while index < args.size():
		var arg := args[index]
		index += 1
		if arg == "--version":
			print(Application.VERSION)
			return 0
		if arg == "--help":
			print(usage_text())
			return 0
		# The name may be attached with an equals sign or stand as the next
		# argument, since both forms are what people try.
		if arg == "--help-command" or arg.begins_with(HELP_COMMAND_PREFIX):
			var name := arg.trim_prefix(HELP_COMMAND_PREFIX) if arg != "--help-command" else ""
			if name.is_empty() and index < args.size():
				name = args[index]
				index += 1
			return help_command(name)
		if arg == NO_PYTHON:
			continue
		if not arg.begins_with(AUTOMATION_PORT_PREFIX):
			printerr("Unknown option: %s" % arg)
			printerr(usage_text())
			return 2
	return -1


static func usage_text() -> String:
	var lines := ["%s %s" % [Application.APPLICATION_NAME, Application.VERSION], "",
		"Usage: %s [-- OPTIONS]" % Application.APPLICATION_NAME, "", "Options:"]
	for switch in SWITCHES:
		lines.append("  %-24s %s" % [switch[0], switch[1]])
	return "\n".join(lines)


# Print what one script does, from the docstring the script itself carries.
# Runs before the window opens and does not need the interpreter.
static func help_command(name: String) -> int:
	if name.is_empty():
		printerr("--help-command needs the name of a script")
		return 2
	var entry := ScriptCatalog.find(Config.get_script_directories(), name)
	if entry == null:
		printerr("No script called %s in %s" % [
			name, ", ".join(PackedStringArray(Config.get_script_directories()))])
		return 2
	print(entry.doc)
	return 0


# The port given by --automation-port=PORT, or 0 when the switch is absent.
static func automation_port(args: PackedStringArray) -> int:
	for arg in args:
		if arg.begins_with(AUTOMATION_PORT_PREFIX):
			return int(arg.substr(AUTOMATION_PORT_PREFIX.length()))
	return 0


# Whether --no-python was given, which starts the application with no
# interpreter and the console panel switched off.
static func no_python(args: PackedStringArray) -> bool:
	return NO_PYTHON in args
