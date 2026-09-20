"""A minimal HTTP service using only the Python standard library.

Exposes a single endpoint, GET /, which returns a plain-text greeting.
Listens on the port given by the PORT environment variable (Cloud Run
sets this automatically), defaulting to 8080 for local runs.
"""

import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SERVICE_NAME = os.environ.get("SERVICE_NAME", "mainspring-energy-service")
PORT = int(os.environ.get("PORT", "8080"))


class Handler(BaseHTTPRequestHandler):
    def _send_text(self, status: int, body: str) -> None:
        encoded = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def do_GET(self) -> None:
        if self.path == "/":
            self._send_text(200, f"Hello from {SERVICE_NAME}\n")
        else:
            self._send_text(404, "Not Found\n")

    # Quiet, single-line request logging instead of the default verbose format.
    def log_message(self, format: str, *args) -> None:
        print(f"{self.address_string()} - {format % args}")


def main() -> None:
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"{SERVICE_NAME} listening on port {PORT}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
