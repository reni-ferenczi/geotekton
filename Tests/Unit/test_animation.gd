extends TestCase

# AnimationSettings: where playback reaches after some seconds at a speed, for a
# range and the loop switch. Times are ages, so the usual animation runs from a
# large start down to an end of zero.


func test_the_usual_animation_counts_down_to_the_present() -> void:
	var settings := _settings(100.0, 0.0, 25.0)
	assert_close(settings.advance(100.0, 1.0), 75.0, 1e-9)
	assert_close(settings.advance(75.0, 2.0), 25.0, 1e-9)


func test_an_animation_can_run_the_other_way() -> void:
	var settings := _settings(0.0, 100.0, 25.0)
	assert_close(settings.advance(0.0, 1.0), 25.0, 1e-9)


func test_playback_never_passes_the_end() -> void:
	var settings := _settings(100.0, 0.0, 30.0)
	assert_close(settings.advance(10.0, 1.0), 0.0, 1e-9, "the last second is cut short")
	assert_true(settings.reached_end(0.0), "and that is the end")
	assert_true(not settings.reached_end(10.0), "which 10 Ma is not")


func test_a_slow_frame_moves_the_time_further() -> void:
	# The time is moved by the seconds the last frame took, so the animation
	# reaches the end at the same moment however the frames are spaced.
	var settings := _settings(100.0, 0.0, 10.0)
	var by_tenths := 100.0
	for i in 10:
		by_tenths = settings.advance(by_tenths, 0.1)
	assert_close(by_tenths, settings.advance(100.0, 1.0), 1e-9)


func test_a_range_of_no_length_is_already_at_its_end() -> void:
	var settings := _settings(50.0, 50.0, 10.0)
	assert_close(settings.advance(50.0, 1.0), 50.0, 1e-9)
	assert_true(settings.reached_end(50.0))


func test_looping_does_not_change_how_the_time_moves() -> void:
	var settings := _settings(100.0, 0.0, 25.0)
	var once := settings.advance(100.0, 1.0)
	settings.loop = true
	assert_close(settings.advance(100.0, 1.0), once, 1e-9,
		"a loop is the same run again, so one second is the same second")


func test_settings_that_cannot_be_played_say_why() -> void:
	var settings := _settings(100.0, 0.0, 10.0)
	assert_eq(settings.problem(), "", "the defaults are playable")

	settings.speed = 0.0
	assert_true(not settings.problem().is_empty(), "no speed never arrives")

	settings = _settings(Document.MAX_TIME + 1.0, 0.0, 10.0)
	assert_true(not settings.problem().is_empty(), "a start older than the limit")


func test_the_settings_round_trip_through_the_config_file() -> void:
	var settings := _settings(1234.5, 12.5, 2.5)
	settings.loop = true
	var back := AnimationSettings.from_json(settings.to_json())
	assert_eq(back.to_json(), settings.to_json())


func test_settings_that_do_not_add_up_are_read_as_the_defaults() -> void:
	var back := AnimationSettings.from_json({"speed": -5.0})
	assert_eq(back.to_json(), AnimationSettings.new().to_json(),
		"a file nobody could play falls back to what a fresh install has")


func test_missing_keys_keep_their_own_default() -> void:
	var back := AnimationSettings.from_json({"loop": true})
	assert_true(back.loop, "what the file said")
	assert_close(back.start, AnimationSettings.DEFAULTS["start"], 1e-9, "and the rest as it was")


func test_the_keys_an_older_version_wrote_are_left_unread() -> void:
	# Up to 0.7.0 playback stepped by an increment at a frame rate. Those keys
	# say nothing about a speed, so a file holding them plays at the default.
	var back := AnimationSettings.from_json({
		"start": 400.0, "increment": 10.0, "frames_per_second": 24.0, "land_on_end": true})
	assert_close(back.start, 400.0, 1e-9, "what still means something is read")
	assert_close(back.speed, AnimationSettings.DEFAULTS["speed"], 1e-9)
	assert_true(not back.to_json().has("increment"), "and the old keys are not written back")


### Helpers


func _settings(start: float, end: float, speed: float) -> AnimationSettings:
	var settings := AnimationSettings.new()
	settings.start = start
	settings.end = end
	settings.speed = speed
	return settings
