#!/usr/bin/env python3
"""Count the generated laws:code outputs with Anthropic's count_tokens and record them in counts.json.

Run: python3 plugins/laws/source/count.py                 # record every output's count
     python3 plugins/laws/source/count.py --laws          # also print what each law saves below L
     python3 plugins/laws/source/count.py --keychain-service CLAUDE_CODE_OAUTH_TOKEN_QWR

The credential is read from the macOS keychain (security find-generic-password -s <service>).
An API key (sk-ant-api...) is sent as x-api-key, an OAuth token (sk-ant-oat...) as a bearer
token. Each count is of the text as one user message on the default profile's model; that
is the unit the profile's budget is in. generate.py --check refuses an output whose
recorded count is for different text or another model, so a count is never stale silently.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import urllib.error
import urllib.request

import generate

ENDPOINT = "https://api.anthropic.com/v1/messages/count_tokens"
TIMEOUT_SECONDS = 60


def credential_headers(service: str) -> dict[str, str]:
    found = subprocess.run(["security", "find-generic-password", "-s", service, "-w"], capture_output=True, text=True)
    if found.returncode != 0:
        raise SystemExit(
            f"count: no credential in keychain service {service!r} (security exited {found.returncode}:"
            f" {found.stderr.strip()}); pass --keychain-service"
        )
    secret = found.stdout.strip()
    if secret.startswith("sk-ant-oat"):
        return {"authorization": f"Bearer {secret}", "anthropic-beta": "oauth-2025-04-20"}
    if secret.startswith("sk-ant-api"):
        return {"x-api-key": secret}
    raise SystemExit(f"count: keychain service {service!r} holds neither an API key nor an OAuth token")


def count_tokens(text: str, model: str, headers: dict[str, str]) -> int:
    body = json.dumps({"model": model, "messages": [{"role": "user", "content": text}]}).encode()
    request = urllib.request.Request(ENDPOINT, data=body, method="POST", headers={
        **headers, "anthropic-version": "2023-06-01", "content-type": "application/json",
    })
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            return json.load(response)["input_tokens"]
    except urllib.error.HTTPError as e:
        raise SystemExit(f"count: count_tokens refused ({e.code}): {e.read().decode()}") from e


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--keychain-service", default="anthropic-api-key")
    parser.add_argument("--laws", action="store_true", help="print each law's saving at M and S against all-L")
    args = parser.parse_args(argv)
    headers = credential_headers(args.keychain_service)
    built = generate.build()
    model = built.profile.model
    counts = {
        o.path: {"model": model, "sha256": generate.sha256(o.text), "tokens": count_tokens(o.text, model, headers)}
        for o in built.outputs
    }
    generate.COUNTS.write_text(json.dumps(counts, indent=2) + "\n")
    for path, entry in counts.items():
        print(f"count: {path} {entry['tokens']} tokens on {model}")
    if args.laws:
        laws = built.source.laws
        all_l = count_tokens(built.source.render(generate.uniform("L", laws), "all-L"), model, headers)
        print(f"\nall-L: {all_l} tokens\n\n| law | saves at M | saves at S |\n|---|---:|---:|")
        for law in laws:
            saves = {
                rung: all_l - count_tokens(built.source.render({**generate.uniform("L", laws), law: rung}, rung), model, headers)
                for rung in ("M", "S")
            }
            print(f"| `{law}` | {saves['M']} | {saves['S']} |")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
