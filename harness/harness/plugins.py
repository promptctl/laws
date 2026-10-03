"""Plugins a caller admits into a session, each pinned to exact content.

A plugin reaches the session only through `--plugin-dir` on its pinned snapshot. Nothing
is installed into the config dir, so no plugin can load that the caller did not name.
"""
from __future__ import annotations

import hashlib
import json
import subprocess
import tarfile
from dataclasses import dataclass
from pathlib import Path

from . import HarnessError


@dataclass(frozen=True)
class GitPlugin:
    """A plugin directory inside a git repository, at one commit."""
    repo: str  # a path or URL git can fetch from
    ref: str
    subdir: str


@dataclass(frozen=True)
class DirPlugin:
    """A plugin directory as it is on disk now, pinned by a digest of its files."""
    path: Path


@dataclass(frozen=True)
class Pinned:
    name: str
    plugin_dir: Path
    hook_events: tuple[str, ...]
    provenance: dict  # the record's admitted.plugins[] entry, minus name


def parse_spec(spec: dict) -> GitPlugin | DirPlugin:
    if set(spec) == {"repo", "ref", "subdir"}:
        return GitPlugin(str(spec["repo"]), str(spec["ref"]), str(spec["subdir"]))
    if set(spec) == {"dir"}:
        return DirPlugin(Path(spec["dir"]).resolve())
    raise HarnessError("spec", f"a plugin is {{repo, ref, subdir}} or {{dir}}, not {spec}")


def _git(*args: str, cwd: Path | None = None) -> str:
    out = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    if out.returncode != 0:
        raise HarnessError("plugins", f"git {' '.join(args)} failed: {out.stderr.strip()}")
    return out.stdout.strip()


def tree_digest(root: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(p for p in root.rglob("*") if p.is_file()):
        digest.update(f"{path.relative_to(root).as_posix()}\0{hashlib.sha256(path.read_bytes()).hexdigest()}\n".encode())
    return digest.hexdigest()


def _describe(plugin_dir: Path) -> tuple[str, tuple[str, ...]]:
    manifest = plugin_dir / ".claude-plugin" / "plugin.json"
    if not manifest.is_file():
        raise HarnessError("plugins", f"{plugin_dir} has no .claude-plugin/plugin.json")
    name = json.loads(manifest.read_text()).get("name")
    if not name:
        raise HarnessError("plugins", f"{manifest} names no plugin")
    hooks_file = plugin_dir / "hooks" / "hooks.json"
    events = tuple(sorted(json.loads(hooks_file.read_text()).get("hooks", {}))) if hooks_file.is_file() else ()
    return name, events


def pin(source: GitPlugin | DirPlugin, into: Path) -> Pinned:
    """Snapshot `source` under `into` and describe it. A git plugin is extracted from the
    whole tree at its commit, because a plugin may symlink files from elsewhere in its
    repository and an archive of the subdir alone would carry dangling links."""
    if isinstance(source, DirPlugin):
        if not source.path.is_dir():
            raise HarnessError("plugins", f"plugin directory not found: {source.path}")
        name, events = _describe(source.path)
        return Pinned(name, source.path, events, {"source": "dir", "path": str(source.path), "sha256": tree_digest(source.path)})
    store = into / "objects.git"
    _git("init", "--bare", "-q", str(store))
    _git("-C", str(store), "fetch", "-q", "--depth", "1", source.repo, source.ref)
    commit = _git("-C", str(store), "rev-parse", "--verify", "FETCH_HEAD^{commit}")
    tree = _git("-C", str(store), "rev-parse", "--verify", f"{commit}^{{tree}}")
    snapshot = into / commit
    snapshot.mkdir(parents=True, exist_ok=False)
    archive = subprocess.run(["git", "-C", str(store), "archive", "--format=tar", commit], capture_output=True)
    if archive.returncode != 0:
        raise HarnessError("plugins", f"git archive {commit} failed: {archive.stderr.decode().strip()}")
    archive_path = into / f"{commit}.tar"
    archive_path.write_bytes(archive.stdout)
    with tarfile.open(archive_path) as tar:
        tar.extractall(snapshot, filter="tar")
    archive_path.unlink()
    plugin_dir = snapshot / source.subdir
    if not plugin_dir.is_dir():
        raise HarnessError("plugins", f"{source.repo} at {commit} has no {source.subdir}/")
    name, events = _describe(plugin_dir)
    return Pinned(name, plugin_dir, events, {"source": "git", "repo": source.repo, "ref": source.ref,
                                             "subdir": source.subdir, "commit": commit, "tree": tree})
