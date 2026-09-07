extends TestCase

# The command line switches the application answers before it opens anything.


func test_help_lists_every_switch() -> void:
	var text := Cli.usage_text()
	for switch in Cli.SWITCHES:
		assert_true(str(switch[0]) in text, "--help lists %s" % switch[0])
		assert_true(str(switch[1]) in text, "--help describes %s" % switch[0])
	assert_true(Application.VERSION in text, "--help names the version")


func test_help_and_version_ask_for_a_clean_exit() -> void:
	assert_eq(Cli.handle(PackedStringArray(["--help"])), 0)
	assert_eq(Cli.handle(PackedStringArray(["--version"])), 0)


func test_an_unknown_switch_fails() -> void:
	assert_eq(Cli.handle(PackedStringArray(["--nonsense"])), 2)


func test_the_application_keeps_running_without_switches() -> void:
	assert_eq(Cli.handle(PackedStringArray([])), -1)
	assert_eq(Cli.handle(PackedStringArray(["--automation-port=45455"])), -1)


func test_the_automation_port_is_read_from_the_switch() -> void:
	assert_eq(Cli.automation_port(PackedStringArray(["--automation-port=45455"])), 45455)
	assert_eq(Cli.automation_port(PackedStringArray([])), 0)
