extends PanelContainer
class_name ConsolePanel

# The Python console under the globe: a transcript, a prompt, the lines already
# typed and the completions the interpreter offers.
#
# Nothing is worked out here. A line goes to the interpreter and whatever comes
# back is shown, which is what makes the console the same language a script file
# is written in rather than a second, smaller one. The interpreter says when a
# line is unfinished, so a block can be typed a line at a time, and it serves
# the completions, so they know about names the session made a moment ago.
#
# See Docs/Scripting.md.

# What the prompt says on the first line of a statement and on its continuation,
# following the interpreter Python ships with.
const PROMPT := ">>> "
const CONTINUATION := "... "

# How many lines back the arrow keys reach.
const MAX_HISTORY := 200

# What the transcript colours each kind of line. The echo is dimmed so the
# answers stand out from the questions.
const ECHO_COLOR := Color(1.0, 1.0, 1.0, 0.55)
const ERROR_COLOR := Color(1.0, 0.55, 0.5, 1.0)
const NOTE_COLOR := Color(1.0, 0.85, 0.35, 1.0)

var bridge: PythonBridge

# The last reason written to the transcript, so a change of state that does not
# change the reason does not repeat it.
var _last_note: String = ""

var transcript: RichTextLabel
var prompt_label: Label
var input: LineEdit

# The lines typed, oldest first, and where the arrow keys are in them.
# `recall` is one past the end when nothing is being recalled.
var history: Array[String] = []
var recall: int = 0

# The lines of a statement that is not finished yet, empty between statements.
var pending: PackedStringArray = PackedStringArray()

# True while a line is with the interpreter, so a second one cannot be sent
# into the middle of the first.
var busy: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(0, 180)

	var box := VBoxContainer.new()
	box.name = "Console"
	add_child(box)

	transcript = RichTextLabel.new()
	transcript.name = "Transcript"
	transcript.bbcode_enabled = true
	transcript.scroll_following = true
	transcript.selection_enabled = true
	transcript.focus_mode = Control.FOCUS_CLICK
	transcript.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(transcript)

	var line := HBoxContainer.new()
	line.name = "Prompt"
	box.add_child(line)

	prompt_label = Label.new()
	prompt_label.name = "PromptLabel"
	prompt_label.text = PROMPT
	line.add_child(prompt_label)

	input = LineEdit.new()
	input.name = "Input"
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.caret_blink = true
	input.text_submitted.connect(_on_submitted)
	input.gui_input.connect(_on_input_key)
	line.add_child(input)


# Follow one bridge for as long as the application lives.
func attach(bridge_: PythonBridge) -> void:
	bridge = bridge_
	bridge.wrote.connect(_on_wrote)
	bridge.state_changed.connect(_show_state)
	_show_state()


### What the interpreter is doing


func _show_state() -> void:
	if bridge == null:
		return
	var ready := bridge.is_ready()
	input.editable = ready
	input.placeholder_text = "" if ready else bridge.reason
	# Starting again passes through more than one state, and saying the same
	# thing twice in a row reads as two things having gone wrong.
	if not ready and not bridge.reason.is_empty() and bridge.reason != _last_note:
		_last_note = bridge.reason
		note(bridge.reason)
	elif ready:
		_last_note = ""


func _on_wrote(text: String, stream: String) -> void:
	if stream == "stderr":
		write(text, ERROR_COLOR)
	else:
		write(text)


### The transcript


# Add text as it is, with no line of its own added: the interpreter sends what
# print() wrote, newlines included, and inventing more would double them.
func write(text: String, color: Variant = null) -> void:
	if text.is_empty():
		return
	if color == null:
		transcript.append_text(_escaped(text))
	else:
		transcript.append_text("[color=#%s]%s[/color]" % [(color as Color).to_html(), _escaped(text)])


# Something the console itself has to say, on a line of its own.
func note(text: String) -> void:
	write(text.strip_edges() + "\n", NOTE_COLOR)


func clear() -> void:
	transcript.clear()


func text() -> String:
	return transcript.get_parsed_text()


static func _escaped(text: String) -> String:
	return text.replace("[", "[lb]")


### Typing


func _on_submitted(line: String) -> void:
	input.clear()
	submit(line)


func _on_input_key(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	match key.keycode:
		KEY_UP:
			step_history(-1)
			accept_event()
		KEY_DOWN:
			step_history(1)
			accept_event()
		KEY_TAB:
			complete()
			accept_event()
		KEY_ESCAPE:
			if not pending.is_empty():
				abandon()
				accept_event()


# Move through the lines already typed. Past the newest is an empty line again,
# which is how a recalled line is dismissed without deleting it by hand.
func step_history(step: int) -> void:
	if history.is_empty():
		return
	recall = clampi(recall + step, 0, history.size())
	input.text = "" if recall >= history.size() else history[recall]
	input.caret_column = input.text.length()


# Drop the unfinished statement and go back to the first prompt.
func abandon() -> void:
	pending = PackedStringArray()
	prompt_label.text = PROMPT
	input.clear()


### Running a line


# Send one line to the interpreter, echoing it first so the transcript reads
# like a session. A statement that is not finished is held here until it is.
func submit(line: String) -> void:
	if bridge == null or busy:
		return
	write(prompt_label.text + line + "\n", ECHO_COLOR)
	if not line.strip_edges().is_empty():
		_remember(line)

	pending.append(line)
	var source := "\n".join(pending)

	busy = true
	var reply := await bridge.request("eval", {"source": source})
	busy = false

	if not reply.get("ok", false):
		write(str(reply.get("error", "the interpreter did not answer")) + "\n", ERROR_COLOR)
		abandon()
		return

	if bool(reply.get("incomplete", false)):
		prompt_label.text = CONTINUATION
		return

	pending = PackedStringArray()
	prompt_label.text = PROMPT
	write(str(reply.get("traceback", "")), ERROR_COLOR)


# Run a script file and show what it printed, as if it had been typed.
func run_file(path: String) -> void:
	if bridge == null or busy:
		return
	note("Running %s" % path)
	busy = true
	var reply := await bridge.request("run_file", {"path": path})
	busy = false
	if not reply.get("ok", false):
		write(str(reply.get("error", "the script could not be run")) + "\n", ERROR_COLOR)
		return
	write(str(reply.get("traceback", "")), ERROR_COLOR)


func _remember(line: String) -> void:
	if history.is_empty() or history[history.size() - 1] != line:
		history.append(line)
	if history.size() > MAX_HISTORY:
		history = history.slice(history.size() - MAX_HISTORY)
	recall = history.size()


### Completion


# Ask the interpreter what the word under the caret could become. One answer
# finishes the word; several are listed and the shared beginning is filled in,
# which is what a shell does.
func complete() -> Array:
	if bridge == null or busy:
		return []
	var source := input.text.substr(0, input.caret_column)
	busy = true
	var reply := await bridge.request("complete", {"source": source})
	busy = false
	if not reply.get("ok", false):
		return []

	var candidates: Array = reply.get("completions", [])
	if candidates.is_empty():
		return []

	var word := _word(source)
	var shared := _shared_start(candidates)
	if shared.length() > word.length():
		var rest := shared.substr(word.length())
		input.text = source + rest + input.text.substr(input.caret_column)
		input.caret_column = source.length() + rest.length()
	if candidates.size() > 1:
		write(prompt_label.text + input.text + "\n", ECHO_COLOR)
		write("  ".join(PackedStringArray(candidates)) + "\n", ECHO_COLOR)
	return candidates


# The dotted word the text ends with, which is what the interpreter completed.
# The same pattern the interpreter uses, so both ends agree on where a word
# begins; see WORD in src/geotekt/bridge.py.
static func _word(source: String) -> String:
	var found := RegEx.create_from_string("[\\w.]*$").search(source)
	return found.get_string() if found != null else ""


# The longest beginning every candidate shares.
static func _shared_start(candidates: Array) -> String:
	var shared := str(candidates[0])
	for candidate in candidates:
		var text_ := str(candidate)
		while not text_.begins_with(shared):
			shared = shared.substr(0, shared.length() - 1)
	return shared
