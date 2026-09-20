"""End-to-end tests for the Cloud Run service entrypoint (app.py).

Each test launches the real `python3 app.py` process — the exact command
the Dockerfile's CMD runs — and makes real HTTP requests against it, so the
tests exercise what actually ships in the container image, not just an
imported function.

Zero third-party test dependencies: stdlib subprocess/socket/urllib only,
matching the service's own zero-dependency footprint.

Run with:
    cd app && python3 -m unittest discover -s tests -v
"""

import os
import socket
import subprocess
import sys
import time
import unittest
import urllib.error
import urllib.request

APP_PATH = os.path.join(os.path.dirname(__file__), "..", "app.py")


def _free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def _base_env() -> dict:
    # A minimal, hermetic environment (just enough for Python to run) so a
    # SERVICE_NAME/PORT already set in the host shell can't leak into a test
    # and mask a bug.
    env = {"PATH": os.environ.get("PATH", "")}
    if "SYSTEMROOT" in os.environ:  # pragma: no cover (Windows only)
        env["SYSTEMROOT"] = os.environ["SYSTEMROOT"]
    return env


class _RunningService:
    """Context manager: starts `python3 app.py` with a given environment and
    waits until it is accepting connections; tears it down on exit."""

    def __init__(self, env_overrides: dict | None = None):
        self.port = _free_port()
        self.env = _base_env()
        self.env["PORT"] = str(self.port)
        if env_overrides:
            self.env.update(env_overrides)
        self.process: subprocess.Popen | None = None

    def __enter__(self) -> "_RunningService":
        self.process = subprocess.Popen(
            [sys.executable, APP_PATH],
            env=self.env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        self._wait_until_ready()
        return self

    def __exit__(self, *exc_info) -> None:
        if self.process is None:
            return
        self.process.terminate()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait(timeout=5)
        finally:
            if self.process.stdout:
                self.process.stdout.close()

    def _wait_until_ready(self, timeout: float = 5.0) -> None:
        deadline = time.time() + timeout
        while time.time() < deadline:
            if self.process.poll() is not None:
                out = self.process.stdout.read() if self.process.stdout else ""
                raise RuntimeError(f"app.py exited early (code {self.process.returncode}):\n{out}")
            try:
                with socket.create_connection(("127.0.0.1", self.port), timeout=0.2):
                    return
            except OSError:
                time.sleep(0.05)
        raise TimeoutError("app.py did not start listening within the timeout")

    def get(self, path: str):
        url = f"http://127.0.0.1:{self.port}{path}"
        try:
            resp = urllib.request.urlopen(url, timeout=5)
            return resp.status, resp.read().decode("utf-8"), dict(resp.headers)
        except urllib.error.HTTPError as e:
            return e.code, e.read().decode("utf-8"), dict(e.headers)

    def post(self, path: str):
        req = urllib.request.Request(f"http://127.0.0.1:{self.port}{path}", method="POST")
        try:
            resp = urllib.request.urlopen(req, timeout=5)
            return resp.status, resp.read().decode("utf-8")
        except urllib.error.HTTPError as e:
            return e.code, e.read().decode("utf-8")


class AppServiceTest(unittest.TestCase):
    def test_root_returns_200_with_custom_service_name(self):
        with _RunningService({"SERVICE_NAME": "custom-service"}) as svc:
            status, body, headers = svc.get("/")
            self.assertEqual(status, 200)
            self.assertEqual(body, "Hello from custom-service\n")
            self.assertIn("text/plain", headers.get("Content-Type", ""))

    def test_root_falls_back_to_default_service_name(self):
        with _RunningService() as svc:  # SERVICE_NAME intentionally unset
            status, body, _ = svc.get("/")
            self.assertEqual(status, 200)
            self.assertEqual(body, "Hello from mainspring-energy-service\n")

    def test_unknown_path_returns_plain_text_404(self):
        with _RunningService() as svc:
            status, body, headers = svc.get("/does-not-exist")
            self.assertEqual(status, 404)
            self.assertEqual(body, "Not Found\n")
            self.assertIn("text/plain", headers.get("Content-Type", ""))

    def test_listens_on_port_from_env(self):
        # A fixed, unusual port makes sure the service is actually honoring
        # $PORT rather than a hardcoded default.
        with _RunningService() as svc:
            status, _, _ = svc.get("/")
            self.assertEqual(status, 200)  # reachable on svc.port == $PORT

    def test_unsupported_method_is_rejected(self):
        with _RunningService() as svc:
            status, _ = svc.post("/")
            self.assertEqual(status, 501)  # BaseHTTPRequestHandler default for no do_POST


if __name__ == "__main__":
    unittest.main()
