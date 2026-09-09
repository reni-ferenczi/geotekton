"""The bridge between the application and this interpreter.

The application starts one of these and connects to it, so the server is here
and the client is the application. One connection carries traffic both ways:
the application asks this process to evaluate a line, complete a word or run a
script file, and while that is being done the script asks the application about
the open document and edits it.

Messages are one JSON object per line, UTF-8, on the loopback interface.

    request   {"id": 3, "cmd": "eval", "source": "app.time"}
    reply     {"id": 3, "ok": true, "incomplete": false, "traceback": ""}
    error     {"id": 3, "ok": false, "error": "unknown command: nonsense"}
    event     {"event": "output", "stream": "stdout", "text": "1400.0\n"}

Each side numbers its own requests and answers with the id it was given, so a
reply is never mistaken for one to another request. The application counts up
from one and this process counts down from minus one, which keeps the two
sequences apart in a log without either side having to know about the other's.
An event carries no id and is never replied to.

See Docs/Scripting.md.
"""

from __future__ import annotations

import codeop
import json
import logging
import re
import rlcompleter
import socket
import sys
import traceback
from pathlib import Path
from typing import Any, Callable

from middle_earth.api import App
from middle_earth.document import Document, Feature, Keyframe

# How long to wait for the application to connect before giving up. An
# interpreter whose application died before it could connect would otherwise
# sit on the port for as long as the machine is up.
ACCEPT_TIMEOUT = 30.0

# The word a completion is asked for: the dotted name the line ends with.
WORD = re.compile(r"[\w.]*$")


class Connection:
    """Newline delimited JSON over a socket, in both directions."""

    def __init__(self, sock: socket.socket) -> None:
        self.socket = sock
        self.buffer = b""

    def send(self, message: dict) -> None:
        self.socket.sendall((json.dumps(message) + "\n").encode("utf-8"))

    def receive(self) -> dict | str | None:
        """The next message, the raw line when it is not JSON, None at the end."""
        while b"\n" not in self.buffer:
            chunk = self.socket.recv(65536)
            if not chunk:
                return None
            self.buffer += chunk
        line, _, self.buffer = self.buffer.partition(b"\n")
        text = line.decode("utf-8", "replace").strip()
        if not text:
            return {}
        try:
            message = json.loads(text)
        except ValueError:
            return text
        return message if isinstance(message, dict) else text

    def close(self) -> None:
        self.socket.close()


class OutputStream:
    """Stands in for stdout or stderr and sends what is written as an event."""

    def __init__(self, send: Callable[[dict], None], name: str) -> None:
        self._send = send
        self.name = name

    def write(self, text: str) -> int:
        if text:
            self._send({"event": "output", "stream": self.name, "text": text})
        return len(text)

    def flush(self) -> None:
        pass

    def isatty(self) -> bool:
        return False


class Bridge:
    """Serves one application: evaluates what it sends and asks it back."""

    def __init__(self, connection: Connection) -> None:
        self.connection = connection
        self.running = True
        self._next_id = 0
        self._compile = codeop.CommandCompiler()
        self.app = App(self.call)
        # What a console session starts with. A script file is run in a copy of
        # it, so what one script leaves behind is not there for the next.
        self.namespace: dict[str, Any] = {
            "__name__": "__console__",
            "__doc__": None,
            "app": self.app,
            "App": App,
            "Document": Document,
            "Feature": Feature,
            "Keyframe": Keyframe,
        }

    ### Talking to the application

    def call(self, request: dict) -> dict:
        """Send a request to the application and wait for its reply."""
        self._next_id -= 1
        identifier = self._next_id
        self.connection.send({"id": identifier, **request})
        while True:
            message = self.connection.receive()
            if message is None:
                raise ConnectionError("the application closed the connection")
            if isinstance(message, dict) and message.get("id") == identifier:
                return message
            # The application waits for its own reply before sending anything
            # else, so nothing else should arrive here. Say so rather than
            # waiting for a reply that is not coming.
            raise ConnectionError("unexpected message while waiting for a reply: %r" % (message,))

    def _emit(self, event: dict) -> None:
        try:
            self.connection.send(event)
        except OSError:
            self.running = False

    ### Serving the application

    def serve(self) -> None:
        while self.running:
            message = self.connection.receive()
            if message is None:
                return
            if isinstance(message, str):
                self.connection.send({"id": None, "ok": False,
                                      "error": "not a JSON object: %s" % message[:200]})
                continue
            if "cmd" not in message:
                self.connection.send({"id": message.get("id"), "ok": False,
                                      "error": "a request needs a cmd"})
                continue
            reply = self.handle(message)
            self.connection.send({"id": message.get("id"), **reply})

    def handle(self, request: dict) -> dict:
        command = str(request.get("cmd", ""))
        if command == "ping":
            return {"ok": True, "python": sys.version.split()[0], "executable": sys.executable}
        if command == "eval":
            return self.evaluate(str(request.get("source", "")))
        if command == "complete":
            return {"ok": True, "completions": self.complete(str(request.get("source", "")))}
        if command == "run_file":
            return self.run_file(str(request.get("path", "")))
        if command == "import_gplates":
            return self.import_gplates([str(source) for source in request.get("sources", [])],
                                       str(request.get("output", "")))
        if command == "quit":
            self.running = False
            return {"ok": True}
        return {"ok": False, "error": "unknown command: %s" % command}

    ### Running code

    def evaluate(self, source: str) -> dict:
        """Run one console line.

        A line that could still be continued is reported as incomplete rather
        than as an error, which is what lets the console take a block one line
        at a time. Anything the code raises is caught and sent back as text: a
        script failing is not a failure of the bridge.
        """
        try:
            compiled = self._compile(source, "<console>", "single")
        except (SyntaxError, OverflowError, ValueError):
            return {"ok": True, "incomplete": False, "traceback": self._format_syntax_error()}
        if compiled is None:
            return {"ok": True, "incomplete": True, "traceback": ""}
        return {"ok": True, "incomplete": False, "traceback": self._execute(compiled, self.namespace)}

    def run_file(self, path: str) -> dict:
        """Run a script file against the open document."""
        file = Path(path)
        try:
            source = file.read_text(encoding="utf-8")
        except OSError as error:
            return {"ok": False, "error": "cannot read %s: %s" % (path, error)}
        try:
            compiled = compile(source, str(file), "exec")
        except SyntaxError:
            return {"ok": True, "traceback": self._format_syntax_error()}
        namespace = dict(self.namespace, __name__="__main__", __file__=str(file))
        return {"ok": True, "traceback": self._execute(compiled, namespace)}

    def import_gplates(self, sources: list[str], output: str) -> dict:
        """Convert GPlates files into a document and write it where asked.

        The conversion needs pygplates, which the rest of the package does not,
        so it is imported here: an interpreter without it still runs scripts and
        serves the console, and only this command says what is missing.
        """
        if not sources or not output:
            return {"ok": False, "error": "an import needs sources and an output path"}
        try:
            from middle_earth.gplates import import_files, import_project
        except ImportError as error:
            return {"ok": False, "error": "the GPlates import needs pygplates: %s" % error}

        # An import takes seconds, so what it finds is said while it runs.
        logger = logging.getLogger("middle_earth.gplates")
        handler = logging.StreamHandler(OutputStream(self._emit, "stdout"))
        handler.setFormatter(logging.Formatter("%(message)s"))
        logger.addHandler(handler)
        level, logger.level = logger.level, logging.INFO
        try:
            if len(sources) == 1 and sources[0].lower().endswith(".gproj"):
                document = import_project(sources[0])
            else:
                document = import_files(sources)
            document.save(output)
        except Exception as error:
            return {"ok": False, "error": "%s: %s" % (type(error).__name__, error)}
        finally:
            logger.removeHandler(handler)
            logger.level = level
        return {"ok": True, "output": output, "features": len(document.features)}

    def _execute(self, compiled, namespace: dict) -> str:
        """Run compiled code with its output going to the console."""
        stdout, stderr = sys.stdout, sys.stderr
        sys.stdout = OutputStream(self._emit, "stdout")
        sys.stderr = OutputStream(self._emit, "stderr")
        try:
            exec(compiled, namespace)
            return ""
        except SystemExit:
            return ""
        except BaseException:
            return self._format_error()
        finally:
            sys.stdout, sys.stderr = stdout, stderr

    @staticmethod
    def _format_syntax_error() -> str:
        """Why the source would not compile, without a traceback into the compiler."""
        kind, value, _ = sys.exc_info()
        return "".join(traceback.format_exception_only(kind, value))

    @staticmethod
    def _format_error() -> str:
        """The traceback of the error being handled, without the bridge's own frames."""
        kind, value, tb = sys.exc_info()
        return "".join(traceback.format_exception(kind, value, tb.tb_next if tb else None))

    ### Completion

    def complete(self, source: str) -> list[str]:
        """What the word the line ends with could be completed to."""
        prefix = WORD.search(source).group(0)
        completer = rlcompleter.Completer(self.namespace)
        found: list[str] = []
        state = 0
        while True:
            try:
                candidate = completer.complete(prefix, state)
            except Exception:
                break
            if candidate is None:
                break
            if candidate not in found:
                found.append(candidate)
            state += 1
        return found


def main(argv: list[str]) -> int:
    port = 0
    for argument in argv:
        if argument.startswith("--port="):
            port = int(argument.split("=", 1)[1])
        else:
            print("unknown option: %s" % argument, file=sys.stderr)
            return 2
    if port <= 0:
        print("usage: python -m middle_earth --port=PORT", file=sys.stderr)
        return 2

    with socket.create_server(("127.0.0.1", port)) as server:
        server.settimeout(ACCEPT_TIMEOUT)
        try:
            sock, _ = server.accept()
        except socket.timeout:
            print("no application connected within %g seconds" % ACCEPT_TIMEOUT, file=sys.stderr)
            return 1
    sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    connection = Connection(sock)
    try:
        Bridge(connection).serve()
    except (OSError, ConnectionError):
        pass
    finally:
        connection.close()
    return 0
