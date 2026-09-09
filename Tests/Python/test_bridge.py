"""The bridge server, driven the way the application drives it.

A socket pair stands in for the connection the application makes, so these run
without a window, a port or a second process.
"""

import socket
import threading

import pytest

from middle_earth.bridge import Bridge, Connection


class Peer:
    """The application's end of the connection."""

    def __init__(self, sock: socket.socket) -> None:
        self.connection = Connection(sock)
        self.identifier = 0

    def send(self, **message) -> None:
        self.connection.send(message)

    def send_raw(self, text: str) -> None:
        self.connection.socket.sendall((text + "\n").encode("utf-8"))

    def receive(self) -> dict:
        message = self.connection.receive()
        assert isinstance(message, dict), "the bridge sent %r" % (message,)
        return message

    def request(self, cmd: str, answer=None, **params) -> dict:
        """Send one request and collect what comes back before its reply.

        `answer` is called with each request the bridge makes while it works,
        which is how a script reaches the application; it answers with the
        reply body. Output events are collected in `self.output`.
        """
        self.identifier += 1
        self.send(id=self.identifier, cmd=cmd, **params)
        self.output = []
        while True:
            message = self.receive()
            if message.get("event") == "output":
                self.output.append(message["text"])
                continue
            if message.get("id") == self.identifier:
                return message
            assert answer is not None, "unexpected request from the bridge: %r" % (message,)
            self.send(id=message["id"], **answer(message))


@pytest.fixture
def peer():
    ours, theirs = socket.socketpair()
    bridge = Bridge(Connection(theirs))
    thread = threading.Thread(target=bridge.serve, daemon=True)
    thread.start()
    client = Peer(ours)
    client.bridge = bridge
    try:
        yield client
    finally:
        ours.close()
        thread.join(timeout=5)
        theirs.close()


def test_ping_answers_which_interpreter_is_running(peer):
    reply = peer.request("ping")
    assert reply["ok"]
    assert reply["python"].startswith("3.")


def test_a_line_that_is_not_json_is_refused_and_the_bridge_stays_up(peer):
    peer.send_raw("this is not JSON")
    refusal = peer.receive()
    assert not refusal["ok"]
    assert refusal["id"] is None
    assert "not a JSON object" in refusal["error"]

    assert peer.request("ping")["ok"], "the bridge answered after the bad line"


def test_a_request_without_a_command_is_refused(peer):
    peer.send(id=99)
    refusal = peer.receive()
    assert not refusal["ok"]
    assert refusal["id"] == 99


def test_an_unknown_command_is_refused(peer):
    reply = peer.request("nonsense")
    assert not reply["ok"]
    assert "unknown command: nonsense" in reply["error"]


def test_output_arrives_as_events_while_the_line_runs(peer):
    reply = peer.request("eval", source="print('hello')")
    assert reply["ok"] and not reply["incomplete"]
    assert reply["traceback"] == ""
    assert peer.output == ["hello", "\n"]


def test_the_value_of_an_expression_is_printed(peer):
    peer.request("eval", source="6 * 7")
    assert "".join(peer.output).strip() == "42"


def test_a_line_that_could_be_continued_is_incomplete(peer):
    reply = peer.request("eval", source="if True:")
    assert reply["incomplete"]
    assert reply["traceback"] == ""


def test_a_syntax_error_comes_back_as_a_traceback(peer):
    reply = peer.request("eval", source="def (")
    assert not reply["incomplete"]
    assert "SyntaxError" in reply["traceback"]


def test_an_error_in_the_line_comes_back_as_a_traceback(peer):
    reply = peer.request("eval", source="1 / 0")
    assert reply["ok"], "the bridge itself did not fail"
    assert "ZeroDivisionError" in reply["traceback"]
    assert "bridge.py" not in reply["traceback"], "the bridge's own frames are left out"

    assert peer.request("ping")["ok"], "the bridge stayed up"


def test_the_namespace_is_kept_between_lines(peer):
    peer.request("eval", source="craton = 'Rodinia'")
    peer.request("eval", source="print(craton)")
    assert peer.output == ["Rodinia", "\n"]


def test_completion_offers_what_the_word_could_become(peer):
    completions = peer.request("complete", source="app.add_f")["completions"]
    assert "app.add_feature(" in completions

    assert "Document(" in peer.request("complete", source="Docu")["completions"]
    assert peer.request("complete", source="no_such_name_at_all")["completions"] == []


def test_a_script_line_reaches_the_application(peer):
    """`app.time` becomes a request to the application and its answer comes back."""
    asked: list[dict] = []

    def answer(request):
        asked.append(request)
        return {"ok": True, "time": 1400.0, "playing": False}

    reply = peer.request("eval", source="print(app.time)", answer=answer)
    assert reply["traceback"] == ""
    assert [request["cmd"] for request in asked] == ["time"]
    assert asked[0]["id"] < 0, "the interpreter numbers its own requests apart from ours"
    assert peer.output == ["1400.0", "\n"]


def test_a_refusal_from_the_application_reaches_the_script(peer):
    def answer(_request):
        return {"ok": False, "error": "no feature nonsense"}

    reply = peer.request("eval", source="app.delete_feature('nonsense')", answer=answer)
    assert "AppError: no feature nonsense" in reply["traceback"]


def test_running_a_script_file(peer, tmp_path):
    script = tmp_path / "hello.py"
    script.write_text("print('from a file', __name__)", encoding="utf-8")
    reply = peer.request("run_file", path=str(script))
    assert reply["ok"] and reply["traceback"] == ""
    assert "".join(peer.output).strip() == "from a file __main__"


def test_running_a_file_that_is_not_there_is_refused(peer, tmp_path):
    reply = peer.request("run_file", path=str(tmp_path / "missing.py"))
    assert not reply["ok"]
    assert "cannot read" in reply["error"]


def test_an_error_in_a_script_file_names_the_file(peer, tmp_path):
    script = tmp_path / "broken.py"
    script.write_text("raise ValueError('no')", encoding="utf-8")
    reply = peer.request("run_file", path=str(script))
    assert reply["ok"]
    assert "broken.py" in reply["traceback"]
    assert "ValueError: no" in reply["traceback"]


def test_a_script_file_does_not_leak_into_the_console(peer, tmp_path):
    script = tmp_path / "sets.py"
    script.write_text("only_in_the_script = 1", encoding="utf-8")
    peer.request("run_file", path=str(script))
    reply = peer.request("eval", source="only_in_the_script")
    assert "NameError" in reply["traceback"]


def test_the_bridge_stops_when_the_application_goes_away():
    ours, theirs = socket.socketpair()
    bridge = Bridge(Connection(theirs))
    thread = threading.Thread(target=bridge.serve, daemon=True)
    thread.start()
    ours.close()
    thread.join(timeout=5)
    assert not thread.is_alive(), "serve() returned when the connection closed"
    theirs.close()


def test_quit_ends_the_session(peer):
    assert peer.request("quit")["ok"]
    assert not peer.bridge.running


### Importing a GPlates reconstruction


def test_an_import_writes_a_document_and_says_what_it_found(peer, tmp_path):
    from middle_earth.document import Document
    from test_gplates import a_feature, a_polygon, write_features

    features = write_features(tmp_path / "features.gpml", [a_feature(geometry=a_polygon())])
    output = tmp_path / "imported.middle-earth"
    reply = peer.request("import_gplates", sources=[str(features)], output=str(output))
    assert reply["ok"] and reply["features"] == 1
    assert [feature.title for feature in Document.load(output).features] == ["Somewhere"]
    assert "imported 1 features on 1 plates" in "".join(peer.output)


def test_an_import_of_a_file_that_is_not_there_is_refused(peer, tmp_path):
    reply = peer.request("import_gplates", sources=[str(tmp_path / "gone.gpml")],
                         output=str(tmp_path / "out.middle-earth"))
    assert reply["ok"] and reply["features"] == 0


def test_an_import_with_nowhere_to_write_is_refused(peer, tmp_path):
    reply = peer.request("import_gplates", sources=[str(tmp_path / "features.gpml")])
    assert not reply["ok"]
    assert "output" in reply["error"]


def test_an_import_that_cannot_write_says_why(peer, tmp_path):
    from test_gplates import a_feature, a_polygon, write_features

    features = write_features(tmp_path / "features.gpml", [a_feature(geometry=a_polygon())])
    reply = peer.request("import_gplates", sources=[str(features)],
                         output=str(tmp_path / "no" / "such" / "place.middle-earth"))
    assert not reply["ok"]
    assert "FileNotFoundError" in reply["error"]
