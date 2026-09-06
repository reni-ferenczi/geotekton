"""Client for the Middle Earth automation port."""

import json
import os
import socket
import subprocess
import time
from pathlib import Path

DEFAULT_GODOT = r"C:\Tools\Godot\Godot_v4.6.2-stable_win64_console.exe"
REPO_ROOT = Path(__file__).resolve().parents[1]


class AutomationClient:
    """Newline delimited JSON over TCP, one request at a time."""

    def __init__(self, port: int = 45454, host: str = "127.0.0.1", timeout: float = 30.0) -> None:
        self.port = port
        self.host = host
        self.timeout = timeout
        self.socket: socket.socket | None = None
        self.buffer = b""

    def connect(self, retries: int = 50, delay: float = 0.2) -> None:
        for attempt in range(retries):
            try:
                self.socket = socket.create_connection((self.host, self.port), self.timeout)
                self.socket.settimeout(self.timeout)
                return
            except OSError:
                if attempt == retries - 1:
                    raise
                time.sleep(delay)

    def call(self, cmd: str, **params) -> dict:
        assert self.socket is not None, "not connected"
        request = json.dumps({"cmd": cmd, **params}) + "\n"
        self.socket.sendall(request.encode("utf-8"))
        while b"\n" not in self.buffer:
            chunk = self.socket.recv(65536)
            if not chunk:
                raise RuntimeError("connection closed by the application")
            self.buffer += chunk
        line, _, self.buffer = self.buffer.partition(b"\n")
        response = json.loads(line.decode("utf-8"))
        if not response.get("ok"):
            raise RuntimeError(response.get("error", "unknown error"))
        return response

    def close(self) -> None:
        if self.socket is not None:
            self.socket.close()
            self.socket = None

    def __enter__(self) -> "AutomationClient":
        self.connect()
        return self

    def __exit__(self, *_exc) -> None:
        self.close()


def launch_app(port: int, godot: str | None = None, extra_args: list[str] = ()) -> subprocess.Popen:
    """Start the application with the automation port open."""
    command = [godot or os.environ.get("GODOT", DEFAULT_GODOT), "--path", str(REPO_ROOT)]
    command += list(extra_args)
    command += ["--", f"--automation-port={port}"]
    return subprocess.Popen(command, cwd=str(REPO_ROOT))


if __name__ == "__main__":
    process = launch_app(45454)
    try:
        with AutomationClient(45454) as client:
            print(client.call("ping"))
            print(client.call("quit"))
        process.wait(timeout=30)
    finally:
        if process.poll() is None:
            process.kill()
