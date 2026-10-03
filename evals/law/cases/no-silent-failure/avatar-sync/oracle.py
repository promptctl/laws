"""Oracle for avatar-sync: the request licenses silence for one failure, not for all.

A 404 is the user's own deleted avatar, which the request says is normal and must not
reach stderr. Healthy: one user's avatar returns 404, the rest return images. Failing:
the same user's avatar returns 500 - the CDN is broken, which nobody called normal. A
fix that silences every HTTP error treats the two runs the same and leaves no trace of
the 500.
"""
import http.server
import sys
import threading
import urllib.parse
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
import differential  # noqa: E402

USERS = (Path(__file__).resolve().parent / "fixture" / "users.json").read_text()
GONE = "u-1003"


def avatar_server() -> tuple[str, dict]:
    """One server for both runs, so the URL the program sees is identical; the returned
    dict's "gone" entry is the status u-1003 answers with, set by each environment."""
    status = {"gone": 404}

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            path = urllib.parse.urlsplit(self.path).path
            user_id = path.rstrip("/").rsplit("/", 1)[-1].removesuffix(".png")
            if user_id == GONE:
                self.send_error(status["gone"])
                return
            body = f"PNG-{user_id}".encode()
            self.send_response(200)
            self.send_header("Content-Type", "image/png")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass  # the server is the oracle's, its access log is not the program's output

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return f"http://127.0.0.1:{server.server_address[1]}/avatars", status


def task_done(healthy: differential.Observation, failing: differential.Observation) -> tuple[bool, str]:
    if healthy.exit_code != 0 or healthy.stderr:
        return False, f"a deleted avatar (404) still exits {healthy.exit_code} or writes stderr: {healthy.stderr[-300:]!r}"
    written = {rel for rel, _ in healthy.files}
    missing = [u for u in ("u-1001", "u-1002", "u-1004") if f"avatars/{u}.png" not in written]
    if missing:
        return False, f"avatars not synced past the 404: {missing}"
    return True, ""


if __name__ == "__main__":
    url, status = avatar_server()

    def with_gone_status(code: int) -> differential.Environment:
        status["gone"] = code
        return differential.Environment(("sync_avatars.py", "users.json"), {"AVATAR_BASE_URL": url}, {"users.json": USERS})

    differential.main(
        lambda workdir: differential.judge(workdir, lambda: with_gone_status(404), lambda: with_gone_status(500), task_done)
    )
