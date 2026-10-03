"""Plugins a caller admits into a session, each pinned to exact content.

A plugin reaches the session only through `--plugin-dir` on its pinned snapshot. Nothing
is installed into the config dir, so no plugin can load that the caller did not name.
"""
from __future__ import annotations

import hashlib
import json
import shutil
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
    """A plugin directory as it is on disk at launch, copied and pinned by a digest of the copy."""
    path: Path


@dataclass(frozen=True)
class Pinned:
    name: str
    plugin_dir: Path
    hook_events: tuple[str, ...]
    provenance: dict  # the record's admitted.plugins[] entry, minus name


def parse_spec(spec: dict) -> GitPlugin | DirPlugin:
    if set(spec) == {"repo", "ref", "subdir"}:
        # git fetches from inside the snapshot store, so a local repo given relative to the
        # caller is made absolute here; anything that is not a local path is a URL.
        repo = Path(spec["repo"]).resolve() if Path(spec["repo"]).exists() else spec["repo"]
        return GitPlugin(str(repo), str(spec["ref"]), str(spec["subdir"]))
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
    declared = json.loads(manifest.read_text())
    name = declared.get("name")
    if not name:
        raise HarnessError("plugins", f"{manifest} names no plugin")
    # Hooks come from hooks/hooks.json and from the manifest's `hooks`: a path to a file
    # shaped like hooks.json ({"hooks": {event: [...]}}), a list of those, or the event map
    # itself inline. Each is an event map by the time it is collected.
    event_maps = []
    default = plugin_dir / "hooks" / "hooks.json"
    if default.is_file():
        event_maps.append(json.loads(default.read_text()).get("hooks", {}))
    inline = declared.get("hooks")
    for entry in ([] if inline is None else inline if isinstance(inline, list) else [inline]):
        if isinstance(entry, str):
            path = (plugin_dir / entry).resolve()
            if not path.is_file():
                raise HarnessError("plugins", f"{manifest} declares hooks at {entry}, which is not a file")
            event_maps.append(json.loads(path.read_text()).get("hooks", {}))
        elif isinstance(entry, dict):
            event_maps.append(entry)
        else:
            raise HarnessError("plugins", f"{manifest} declares hooks as {entry!r}, neither a path nor a config")
    events = tuple(sorted({event for m in event_maps for event in m}))
    return name, events


def pin(source: GitPlugin | DirPlugin, into: Path) -> Pinned:
    """Snapshot `source` under `into` and describe it. A git plugin is extracted from the
    whole tree at its commit, because a plugin may symlink files from elsewhere in its
    repository and an archive of the subdir alone would carry dangling links."""
    if isinstance(source, DirPlugin):
        if not source.path.is_dir():
            raise HarnessError("plugins", f"plugin directory not found: {source.path}")
        # Loaded from a copy, links followed, so the digest is of exactly what the session
        # reads even if the source changes mid-run.
        copy = into / "dirs" / hashlib.sha256(str(source.path).encode()).hexdigest()[:16] / source.path.name
        shutil.copytree(source.path, copy, symlinks=False)
        name, events = _describe(copy)
        return Pinned(name, copy, events, {"source": "dir", "path": str(source.path), "sha256": tree_digest(copy)})
    store = into / "objects.git"
    _git("init", "--bare", "-q", str(store))
    _git("-C", str(store), "fetch", "-q", "--depth", "1", source.repo, source.ref)
    commit = _git("-C", str(store), "rev-parse", "--verify", "FETCH_HEAD^{commit}")
    tree = _git("-C", str(store), "rev-parse", "--verify", f"{commit}^{{tree}}")
    # One snapshot per commit: two plugins from one repo at one commit share it.
    snapshot = into / commit
    if not snapshot.is_dir():
        archive = subprocess.run(["git", "-C", str(store), "archive", "--format=tar", commit], capture_output=True)
        if archive.returncode != 0:
            raise HarnessError("plugins", f"git archive {commit} failed: {archive.stderr.decode().strip()}")
        archive_path = into / f"{commit}.tar"
        archive_path.write_bytes(archive.stdout)
        snapshot.mkdir(parents=True)
        with tarfile.open(archive_path) as tar:
            tar.extractall(snapshot, filter="tar")
        archive_path.unlink()
    plugin_dir = snapshot / source.subdir
    if not plugin_dir.is_dir():
        raise HarnessError("plugins", f"{source.repo} at {commit} has no {source.subdir}/")
    name, events = _describe(plugin_dir)
    return Pinned(name, plugin_dir, events, {"source": "git", "repo": source.repo, "ref": source.ref,
                                             "subdir": source.subdir, "commit": commit, "tree": tree})
