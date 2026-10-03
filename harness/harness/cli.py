"""harness login | status | run <spec.json> --out DIR | verify"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

from . import HarnessError, claude, home
from .run import run
from .session import Spec


def login(_: argparse.Namespace) -> None:
    with home.lock(exclusive=True):
        home.provision()
        binary = claude.resolve_binary(None)
        try:
            claude.auth(binary, home.CONFIG_DIR)
            print(f"{home.CONFIG_DIR} is already logged in on the subscription")
            return
        except HarnessError as error:
            print(f"logging in {home.CONFIG_DIR}: {error.message}", file=sys.stderr)
        subprocess.run([str(binary.path), "auth", "login", "--claudeai"],
                       env=claude.session_env(home.CONFIG_DIR, {}), check=False)
        claude.auth(binary, home.CONFIG_DIR)
        print(f"{home.CONFIG_DIR} is logged in on the subscription")


def status(_: argparse.Namespace) -> None:
    binary = claude.resolve_binary(None)
    auth = claude.auth(binary, home.CONFIG_DIR)
    home.check_config_dir()
    print(json.dumps({"config_dir": str(home.CONFIG_DIR), "claude": {"path": str(binary.path), "version": binary.version},
                      "auth": {"method": auth.method, "provider": auth.provider}}, indent=2))


def run_command(args: argparse.Namespace) -> None:
    data = json.loads(Path(args.spec).read_text())
    if set(data) != {"session", "prompts"}:
        raise HarnessError("spec", f"a run spec is {{session, prompts}}, not {sorted(data)}")
    run_id = args.run_id or datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    result = run(Spec.from_json(data["session"]), list(data["prompts"]), Path(args.out).resolve(), run_id)
    print(json.dumps({"run": str(Path(args.out).resolve() / "run.json"), "turns": len(result["turns"]),
                      "model": result["model"]["served"]}, indent=2))


def verify_command(args: argparse.Namespace) -> None:
    from .verify import verify
    sys.exit(verify(args.model, Path(args.out).resolve() if args.out else None))


def main() -> None:
    parser = argparse.ArgumentParser(prog="harness", description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("login", help="log the harness config dir in on the subscription (needs a browser)").set_defaults(func=login)
    sub.add_parser("status", help="print the binary, the login and the config dir a run would use").set_defaults(func=status)
    run_parser = sub.add_parser("run", help="run one session from a spec")
    run_parser.add_argument("spec")
    run_parser.add_argument("--out", required=True)
    run_parser.add_argument("--run-id")
    run_parser.set_defaults(func=run_command)
    verify_parser = sub.add_parser("verify", help="prove the harness against live sessions")
    verify_parser.add_argument("--model", default="claude-haiku-4-5-20251001")
    verify_parser.add_argument("--out", help="keep the verification runs here (default: a temp dir, removed on success)")
    verify_parser.set_defaults(func=verify_command)
    args = parser.parse_args()
    try:
        args.func(args)
    except HarnessError as error:
        sys.exit(f"ERROR [harness] {error}")
