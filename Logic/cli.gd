class_name Cli

# Command line switches. Godot swallows its own options, so the application's
# switches come after a bare "--" and arrive through OS.get_cmdline_user_args():
#
#   MiddleEarth -- --version

# Every supported switch, as name and description. The help text is built from
# this list, so a new switch shows up in --help by adding it here.
const SWITCHES := [
	["--help", "Print this help and exit"],
	["--version", "Print the application version and exit"],
	["--automation-port=PORT", "Open the test automation port on 127.0.0.1:PORT"],
]

const AUTOMATION_PORT_PREFIX := "--automation-port="


# Act on the switches before anything is loaded. Returns the exit code the
# application should quit with, or -1 when it should keep running.
static func handle(args: PackedStringArray) -> int:
	for arg in args:
		if arg == "--version":
			print(Application.VERSION)
			return 0
		if arg == "--help":
			print(usage_text())
			return 0
		if not arg.begins_with(AUTOMATION_PORT_PREFIX):
			printerr("Unknown option: %s" % arg)
			printerr(usage_text())
			return 2
	return -1


static func usage_text() -> String:
	var lines := ["MiddleEarth %s" % Application.VERSION, "", "Usage: MiddleEarth [-- OPTIONS]", "", "Options:"]
	for switch in SWITCHES:
		lines.append("  %-24s %s" % [switch[0], switch[1]])
	return "\n".join(lines)


# The port given by --automation-port=PORT, or 0 when the switch is absent.
static func automation_port(args: PackedStringArray) -> int:
	for arg in args:
		if arg.begins_with(AUTOMATION_PORT_PREFIX):
			return int(arg.substr(AUTOMATION_PORT_PREFIX.length()))
	return 0
