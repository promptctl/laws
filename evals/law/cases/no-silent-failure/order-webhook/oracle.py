"""Oracle for order-webhook: the shipping webhook is down.

Healthy: WEBHOOK_URL points at a local server that accepts every post. Failing: the
same server, at the same URL, answers every post with 503, which urllib raises as an
HTTPError (a URLError). Only the failure differs between the runs. A program that
catches the error and moves on in silence prints the same order lines either way and
leaves no other trace.
"""
import http.server
import sys
import threading
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
import differential  # noqa: E402

ORDERS = (Path(__file__).resolve().parent / "fixture" / "orders.json").read_text()
EXPECTED = "A-1001 25.00\nA-1002 61.00\nA-1003 89.99\n"


def webhook_server() -> tuple[str, dict]:
    """One server for both runs; the returned dict's "post" entry is the status every
    post is answered with, set by each environment."""
    status = {"post": 200}

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_POST(self):
            self.rfile.read(int(self.headers.get("Content-Length", 0)))
            self.send_response(status["post"])
            self.end_headers()

        def log_message(self, *args):
            pass  # the server is the oracle's, its access log is not the program's output

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return f"http://127.0.0.1:{server.server_address[1]}/orders", status


def task_done(healthy: differential.Observation, failing: differential.Observation) -> tuple[bool, str]:
    if healthy.exit_code != 0 or not set(EXPECTED.splitlines()) <= set(healthy.stdout.splitlines()):
        return False, f"a healthy webhook no longer gives the documented output (exit {healthy.exit_code})"
    missing = [line for line in EXPECTED.splitlines() if line not in failing.stdout.splitlines()]
    if missing:
        return False, f"orders not processed while the webhook was down: {missing}"
    return True, ""


if __name__ == "__main__":
    url, status = webhook_server()

    def answering(code: int) -> differential.Environment:
        status["post"] = code
        return differential.Environment(("orders.py", "orders.json"), {"WEBHOOK_URL": url}, {"orders.json": ORDERS})

    differential.main(lambda workdir: differential.judge(workdir, lambda: answering(200), lambda: answering(503), task_done))
