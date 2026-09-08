extends TestCase

# AnimationSettings: the times playback steps through, for a range, a step size
# and the two switches at the ends. Times are ages, so the usual animation runs
# from a large start down to an end of zero.


func test_the_usual_animation_counts_down_to_the_present() -> void:
	var settings := _settings(100.0, 0.0, 25.0)
	assert_eq(_times(settings), [100.0, 75.0, 50.0, 25.0, 0.0])


func test_an_animation_can_run_the_other_way() -> void:
	var settings := _settings(0.0, 100.0, 25.0)
	assert_eq(_times(settings), [0.0, 25.0, 50.0, 75.0, 100.0])


func test_the_last_frame_lands_on_the_end_when_the_step_does_not_divide_the_range() -> void:
	var settings := _settings(100.0, 0.0, 30.0)
	settings.land_on_end = true
	assert_eq(_times(settings), [100.0, 70.0, 40.0, 10.0, 0.0],
		"a short last step reaches the end exactly")


func test_without_landing_on_the_end_it_stops_at_the_last_whole_step() -> void:
	var settings := _settings(100.0, 0.0, 30.0)
	settings.land_on_end = false
	assert_eq(_times(settings), [100.0, 70.0, 40.0, 10.0], "the end time is never shown")


func test_a_step_that_divides_the_range_needs_no_extra_frame() -> void:
	var settings := _settings(100.0, 0.0, 25.0)
	for land in [true, false]:
		settings.land_on_end = land
		assert_eq(_times(settings), [100.0, 75.0, 50.0, 25.0, 0.0],
			"landing on the end changes nothing when the step already does")


func test_the_frames_are_multiples_of_the_step_and_not_a_running_total() -> void:
	# A tenth cannot be written exactly in binary, so adding it up two thousand
	# times drifts. Every frame is worked out from the start on its own.
	var settings := _settings(200.0, 0.0, 0.1)
	var times := settings.times()
	assert_eq(times.size(), 2001)
	assert_close(times[2000], 0.0, 1e-12, "the last frame is exactly the end")
	assert_close(times[1000], 100.0, 1e-12, "and the middle one is exactly halfway")


func test_a_range_of_no_length_is_one_frame() -> void:
	assert_eq(_times(_settings(50.0, 50.0, 10.0)), [50.0])


func test_the_frame_rate_says_how_long_a_frame_is_shown() -> void:
	var settings := _settings(100.0, 0.0, 10.0)
	settings.frames_per_second = 25.0
	assert_close(settings.frame_seconds(), 0.04, 1e-9)
	assert_eq(_times(settings).size(), 11,
		"the frame rate does not change which times are shown")


func test_looping_does_not_change_the_frames_it_loops_over() -> void:
	var settings := _settings(100.0, 0.0, 25.0)
	var once := _times(settings)
	settings.loop = true
	assert_eq(_times(settings), once,
		"a loop is the same list again, so the list itself is unchanged")


func test_settings_that_cannot_be_played_say_why() -> void:
	var settings := _settings(100.0, 0.0, 10.0)
	assert_eq(settings.problem(), "", "the defaults are playable")

	settings.increment = 0.0
	assert_true(not settings.problem().is_empty(), "a step of nothing never arrives")

	settings = _settings(100.0, 0.0, 10.0)
	settings.frames_per_second = 0.0
	assert_true(not settings.problem().is_empty(), "no frames a second never arrives either")

	settings = _settings(Document.MAX_TIME + 1.0, 0.0, 10.0)
	assert_true(not settings.problem().is_empty(), "a start older than the limit")


func test_the_settings_round_trip_through_the_config_file() -> void:
	var settings := _settings(1234.5, 12.5, 2.5)
	settings.frames_per_second = 30.0
	settings.loop = true
	settings.land_on_end = false
	var back := AnimationSettings.from_json(settings.to_json())
	assert_eq(back.to_json(), settings.to_json())


func test_settings_that_do_not_add_up_are_read_as_the_defaults() -> void:
	var back := AnimationSettings.from_json({"increment": -5.0})
	assert_eq(back.to_json(), AnimationSettings.new().to_json(),
		"a file nobody could play falls back to what a fresh install has")


func test_missing_keys_keep_their_own_default() -> void:
	var back := AnimationSettings.from_json({"loop": true})
	assert_true(back.loop, "what the file said")
	assert_close(back.start, AnimationSettings.DEFAULTS["start"], 1e-9, "and the rest as it was")


### Helpers


func _settings(start: float, end: float, increment: float) -> AnimationSettings:
	var settings := AnimationSettings.new()
	settings.start = start
	settings.end = end
	settings.increment = increment
	return settings


func _times(settings: AnimationSettings) -> Array:
	var times: Array = []
	for time in settings.times():
		times.append(time)
	return times
