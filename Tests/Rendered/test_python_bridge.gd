extends RenderedCase

# The bridge protocol, driven against a stub in place of the interpreter.
#
# The stub is a socket in this process rather than a Python one, so what is
# checked here is the application's half of the conversation and nothing else:
# a request answered, a refusal, a request coming the other way against the real
# document, and what happens when the peer disappears mid session. The Python
# half is checked by Tests/Python and the two together by Tests/session.py.
#
# Rendered rather than headless because a request coming the other way is
# answered against the document, the tree and the timeline of a real window.
#
# A request is started without awaiting it and its reply is collected in a list,
# because a test that awaited one could not answer it: both ends run on this
# same main loop, and the stub needs frames of its own to reply in.


# A stand-in for the interpreter. A node, so it gets the frames it needs to
# take the connection, read what arrives and answer.
class Stub extends Node:
	var server := TCPServer.new()
	var peer: StreamPeerTCP = null
	var buffer: String = ""

	# What the application asked for, in order, and what it answered the stub's
	# own requests with.
	var received: Array[Dictionary] = []
	var replies: Array[Dictionary] = []

	# Answers waiting to go back, one per request in order. A request that
	# arrives when this is empty is only recorded, and answered by the test.
	var answers: Array[Dictionary] = []

	func listen() -> int:
		return server.get_local_port() if server.listen(0, "127.0.0.1") == OK else 0

	func _process(_delta: float) -> void:
		if peer == null:
			if server.is_connection_available():
				peer = server.take_connection()
				peer.set_no_delay(true)
			return
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			return
		var available := peer.get_available_bytes()
		if available > 0:
			buffer += peer.get_utf8_string(available)
		while true:
			var end := buffer.find("\n")
			if end < 0:
				return
			var line := buffer.substr(0, end)
			buffer = buffer.substr(end + 1)
			_take(line)

	func _take(line: String) -> void:
		var json := JSON.new()
		if json.parse(line) != OK or json.data is not Dictionary:
			return
		var message: Dictionary = json.data
		if not message.has("cmd"):
			replies.append(message)
			return
		received.append(message)
		if not answers.is_empty():
			var answer: Dictionary = answers.pop_front()
			answer["id"] = message["id"]
			send(answer)

	func send(message: Dictionary) -> void:
		if peer != null:
			peer.put_data((JSON.stringify(message) + "\n").to_utf8_buffer())

	func close() -> void:
		if peer != null:
			peer.disconnect_from_host()
			peer = null
		server.stop()


### Wiring one up


# A bridge of its own, so the application's real one is left alone, wired to a
# stub instead of an interpreter.
func _connect_a_stub() -> Array:
	var stub := Stub.new()
	stub.name = "PythonStub"
	app.add_child(stub)
	var port := stub.listen()
	assert_true(port > 0, "the stub is listening")

	var bridge := PythonBridge.new(app)
	bridge.name = "StubBridge"
	app.add_child(bridge)
	bridge.connect_to(port)

	await _until(func() -> bool: return bridge.is_ready())
	assert_true(bridge.is_ready(), "the application connected to the stub")
	return [stub, bridge]


func _teardown(stub: Stub, bridge: PythonBridge) -> void:
	# The bridge goes first, so a teardown is not read as the peer vanishing.
	bridge.stop()
	stub.close()
	stub.queue_free()
	bridge.queue_free()
	await frames(2)


# Start a request without waiting for it here, and put the reply in `into` when
# it comes.
func _ask(bridge: PythonBridge, cmd: String, params: Dictionary, into: Array) -> void:
	into.append(await bridge.request(cmd, params))


# Give the frames a condition needs, up to a limit that keeps a broken test from
# hanging the run.
func _until(condition: Callable) -> bool:
	for i in 300:
		if condition.call():
			return true
		await frames(1)
	return condition.call()


### A request and its reply


func test_a_request_carries_a_command_and_is_answered_by_its_id() -> void:
	var wired: Array = await _connect_a_stub()
	var stub: Stub = wired[0]
	var bridge: PythonBridge = wired[1]

	stub.answers.append({"ok": true, "incomplete": false, "traceback": ""})
	var replies: Array = []
	_ask(bridge, "eval", {"source": "1 + 1"}, replies)
	await _until(func() -> bool: return not replies.is_empty())

	assert_eq(stub.received.size(), 1, "the application sent one request")
	var asked: Dictionary = stub.received[0]
	assert_eq(str(asked.get("cmd", "")), "eval")
	assert_eq(str(asked.get("source", "")), "1 + 1")
	assert_true(int(asked.get("id", 0)) > 0, "the application numbers its requests upwards")

	assert_eq(replies.size(), 1, "the reply came back to the caller")
	assert_true(bool(replies[0].get("ok", false)))
	await _teardown(stub, bridge)


func test_a_refusal_comes_back_as_it_was_sent() -> void:
	var wired: Array = await _connect_a_stub()
	var stub: Stub = wired[0]
	var bridge: PythonBridge = wired[1]

	stub.answers.append({"ok": false, "error": "unknown command: nonsense"})
	var replies: Array = []
	_ask(bridge, "nonsense", {}, replies)
	await _until(func() -> bool: return not replies.is_empty())

	assert_eq(replies.size(), 1)
	assert_true(not bool(replies[0].get("ok", true)))
	assert_eq(str(replies[0].get("error", "")), "unknown command: nonsense")
	await _teardown(stub, bridge)


func test_a_reply_finds_its_own_request() -> void:
	var wired: Array = await _connect_a_stub()
	var stub: Stub = wired[0]
	var bridge: PythonBridge = wired[1]

	var first: Array = []
	var second: Array = []
	_ask(bridge, "ping", {}, first)
	_ask(bridge, "eval", {"source": "2"}, second)
	await _until(func() -> bool: return stub.received.size() == 2)
	assert_eq(stub.received.size(), 2)
	assert_true(int(stub.received[0]["id"]) != int(stub.received[1]["id"]),
		"each request has its own id")

	# Answered the other way round, to show that a reply is matched by its id
	# rather than by the order the answers arrive in.
	stub.send({"id": stub.received[1]["id"], "ok": true, "which": "second"})
	stub.send({"id": stub.received[0]["id"], "ok": true, "which": "first"})
	await _until(func() -> bool: return not first.is_empty() and not second.is_empty())

	assert_eq(str(first[0].get("which", "")), "first")
	assert_eq(str(second[0].get("which", "")), "second")
	await _teardown(stub, bridge)


### Output events


func test_output_reaches_whatever_shows_it() -> void:
	var wired: Array = await _connect_a_stub()
	var stub: Stub = wired[0]
	var bridge: PythonBridge = wired[1]

	var written: Array = []
	bridge.wrote.connect(func(text: String, stream: String) -> void: written.append([text, stream]))
	stub.send({"event": "output", "stream": "stdout", "text": "hello\n"})
	stub.send({"event": "output", "stream": "stderr", "text": "trouble\n"})
	await _until(func() -> bool: return written.size() == 2)

	assert_eq(written, [["hello\n", "stdout"], ["trouble\n", "stderr"]])
	await _teardown(stub, bridge)


### A request coming the other way


func test_the_interpreter_can_ask_about_the_document() -> void:
	await load_sample("motion.middle-earth")
	var wired: Array = await _connect_a_stub()
	var stub: Stub = wired[0]
	var bridge: PythonBridge = wired[1]

	stub.send({"id": -1, "cmd": "document"})
	await _until(func() -> bool: return not stub.replies.is_empty())
	assert_eq(stub.replies.size(), 1)

	var answered: Dictionary = stub.replies[0]
	assert_eq(int(answered.get("id", 0)), -1, "the answer carries the id it was asked with")
	assert_true(bool(answered.get("ok", false)))
	var document: Dictionary = answered["document"]
	assert_eq(str(document.get("application", "")), Document.APPLICATION)
	assert_eq(str(document["features"]["children"][0]["children"][0]["title"]), "Drifting Craton")
	await _teardown(stub, bridge)


func test_the_interpreter_can_edit_the_document() -> void:
	await load_sample("empty.middle-earth")
	var wired: Array = await _connect_a_stub()
	var stub: Stub = wired[0]
	var bridge: PythonBridge = wired[1]

	stub.send({"id": -1, "cmd": "add_feature", "title": "From a script",
		"geometry_kind": "polygon", "rings": [[[0, 0], [0, 10], [10, 0]]]})
	await _until(func() -> bool: return not stub.replies.is_empty())
	var added: Dictionary = stub.replies[0]
	assert_true(bool(added.get("ok", false)), str(added.get("error", "")))

	var uuid := str(added.get("uuid", ""))
	var feature: Feature = app.document.root.get_node_by_uuid(uuid)
	assert_true(feature != null, "the feature is in the document")
	if feature == null:
		await _teardown(stub, bridge)
		return
	assert_eq(feature.title, "From a script")
	assert_eq(feature.rings[0].size(), 3)
	assert_true(app.document.can_undo(), "the edit went on the undo stack")

	stub.send({"id": -2, "cmd": "set_keyframe", "uuid": uuid, "time": 600.0,
		"rotation": [-30.0, 10.0, 0.0]})
	await _until(func() -> bool: return stub.replies.size() == 2)
	assert_true(bool(stub.replies[1].get("ok", false)), str(stub.replies[1].get("error", "")))
	assert_eq(feature.keyframes.size(), 1)
	assert_close(feature.keyframes[0].time, 600.0)
	await _teardown(stub, bridge)


func test_an_edit_the_document_refuses_comes_back_as_an_error() -> void:
	var wired: Array = await _connect_a_stub()
	var stub: Stub = wired[0]
	var bridge: PythonBridge = wired[1]

	stub.send({"id": -1, "cmd": "delete_feature", "uuid": "no-such-uuid"})
	stub.send({"id": -2, "cmd": "nonsense"})
	await _until(func() -> bool: return stub.replies.size() == 2)

	assert_true(not bool(stub.replies[0].get("ok", true)))
	assert_true("no-such-uuid" in str(stub.replies[0].get("error", "")))
	assert_true(not bool(stub.replies[1].get("ok", true)))
	assert_true("unknown command" in str(stub.replies[1].get("error", "")))
	await _teardown(stub, bridge)


### The interpreter going away


func test_the_application_survives_the_interpreter_disappearing() -> void:
	var wired: Array = await _connect_a_stub()
	var stub: Stub = wired[0]
	var bridge: PythonBridge = wired[1]

	var replies: Array = []
	_ask(bridge, "eval", {"source": "1"}, replies)
	await _until(func() -> bool: return not stub.received.is_empty())
	stub.close()

	await _until(func() -> bool: return not replies.is_empty())
	assert_eq(replies.size(), 1, "the waiting request was answered, not left hanging")
	assert_true(not bool(replies[0].get("ok", true)))
	assert_true(not str(replies[0].get("error", "")).is_empty(), "and it was told why")

	await _until(func() -> bool: return bridge.state == PythonBridge.State.FAILED)
	assert_eq(bridge.state, PythonBridge.State.FAILED)
	assert_true(not bridge.reason.is_empty(), "the console has something to show")

	# A request made afterwards is refused rather than waited on for ever.
	var afterwards: Array = []
	_ask(bridge, "eval", {"source": "2"}, afterwards)
	await _until(func() -> bool: return not afterwards.is_empty())
	assert_eq(afterwards.size(), 1)
	assert_true(not bool(afterwards[0].get("ok", true)))

	await frames(4)
	assert_true(app.is_inside_tree(), "the application is still up")
	stub.queue_free()
	bridge.queue_free()
	await frames(2)
