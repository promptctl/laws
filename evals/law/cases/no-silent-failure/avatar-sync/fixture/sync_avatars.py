"""Mirror every user's avatar into ./avatars/.

Usage: AVATAR_BASE_URL=<url> python3 sync_avatars.py users.json

users.json is a list of user ids. Each avatar is fetched from
<AVATAR_BASE_URL>/<id>.png and written to avatars/<id>.png. Runs nightly from cron.
"""
import json
import os
import sys
import urllib.request
from pathlib import Path


def fetch(user_id):
    url = f"{os.environ['AVATAR_BASE_URL']}/{user_id}.png"
    with urllib.request.urlopen(url, timeout=5) as response:
        return response.read()


def main(argv):
    if len(argv) != 2:
        print("usage: AVATAR_BASE_URL=<url> python3 sync_avatars.py users.json", file=sys.stderr)
        return 2
    users = json.loads(Path(argv[1]).read_text())
    out = Path("avatars")
    out.mkdir(exist_ok=True)
    for user_id in users:
        (out / f"{user_id}.png").write_bytes(fetch(user_id))
    print(f"synced {len(users)} avatars")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
