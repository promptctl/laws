"""Oracle for order-webhook: the shipping webhook refuses connections.

Healthy: WEBHOOK_URL points at a local server that accepts every post. Failing: it
points at a port nothing listens on. A program that catches the error and moves on
in silence prints the same order lines either way and leaves no other trace.
"""
import http.server
import socket
import sys
import threading
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
import differential  # noqa: E402

ORDERS = (Path(__file__).resolve().parent / "fixture" / "orders.json").read_text()
EXPECTED = "A-1001 25.00\nA-1002 61.00\nA-1003 89.99\n"


class Accept(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        self.send_response(200)
        self.end_headers()

    def log_message(self, *args):
        pass  # the server is the oracle's, its access log is not the program's output


def start_server() -> str:
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Accept)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return f"http://127.0.0.1:{server.server_address[1]}/orders"


def closed_port_url() -> str:
    # Bind then release: the port was just free and nothing will be listening on it.
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
    return f"http://127.0.0.1:{port}/orders"


def env(url: str) -> differential.Environment:
    return differential.Environment(("orders.py", "orders.json"), {"WEBHOOK_URL": url}, {"orders.json": ORDERS})


def task_done(healthy: differential.Observation, failing: differential.Observation) -> tuple[bool, str]:
    if healthy.exit_code != 0 or healthy.stdout != EXPECTED:
        return False, f"a healthy webhook no longer gives the documented output (exit {healthy.exit_code})"
    missing = [line for line in EXPECTED.splitlines() if line not in failing.stdout.splitlines()]
    if missing:
        return False, f"orders not processed while the webhook was down: {missing}"
    return True, ""


if __name__ == "__main__":
    healthy_url = start_server()
    differential.main(
        lambda workdir: differential.judge(workdir, lambda: env(healthy_url), lambda: env(closed_port_url()), task_done)
    )
