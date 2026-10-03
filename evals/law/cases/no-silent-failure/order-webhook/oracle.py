"""Oracle for order-webhook: the shipping webhook refuses connections.

Healthy: WEBHOOK_URL points at a local server that accepts every post. Failing: the
same URL, with the server stopped, so the connection is refused. A program that catches
the error and moves on in silence prints the same order lines either way and leaves no
other trace.
"""
import http.server
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


class Webhook:
    """One port for both runs, so the URL the program sees is identical; only whether
    anything answers on it changes."""

    def __init__(self) -> None:
        self.server: http.server.ThreadingHTTPServer | None = None
        self.port = 0

    def up(self) -> None:
        if self.server is None:
            self.server = http.server.ThreadingHTTPServer(("127.0.0.1", self.port), Accept)
            self.port = self.server.server_address[1]
            threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def down(self) -> None:
        if self.server is not None:
            self.server.shutdown()
            self.server.server_close()
            self.server = None

    def env(self) -> differential.Environment:
        url = f"http://127.0.0.1:{self.port}/orders"
        return differential.Environment(("orders.py", "orders.json"), {"WEBHOOK_URL": url}, {"orders.json": ORDERS})


def task_done(healthy: differential.Observation, failing: differential.Observation) -> tuple[bool, str]:
    if healthy.exit_code != 0 or healthy.stdout != EXPECTED:
        return False, f"a healthy webhook no longer gives the documented output (exit {healthy.exit_code})"
    missing = [line for line in EXPECTED.splitlines() if line not in failing.stdout.splitlines()]
    if missing:
        return False, f"orders not processed while the webhook was down: {missing}"
    return True, ""


if __name__ == "__main__":
    webhook = Webhook()
    webhook.up()  # fixes the port before either environment is built

    def healthy() -> differential.Environment:
        webhook.up()
        return webhook.env()

    def failing() -> differential.Environment:
        webhook.down()
        return webhook.env()

    differential.main(lambda workdir: differential.judge(workdir, healthy, failing, task_done))
