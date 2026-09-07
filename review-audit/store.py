#!/usr/bin/env python3
"""The on-disk data bank: where a fetched object lives, how it is written, and
whether what is there is still what was fetched. Nothing here knows GitHub exists.

    <bank>/manifest.json             the index: every object, its upstream version, its hash
    <bank>/prs/<repo>/<number>.json  one pull request as GitHub returned it
    <bank>/commits/<repo>/<oid>.json one commit's diff, per file

The split by mutability is the whole design. A pull request changes upstream, so it
carries GitHub's `updatedAt` as its version and is refetched when that moves. A commit
cannot change - its oid is a hash of its own content - so once stored it is never
fetched again, by any run, ever. Holding both in one file is what made refetching a
pull request silently destroy the commit patches merged into it.
[LAW:one-source-of-truth] [LAW:decomposition]

The manifest is authoritative for what the bank contains: an object absent from it does
not exist here, whatever is lying on disk. Files are written before their manifest entry,
so a kill between the two leaves an orphan the next sync overwrites and `verify` reports -
never a half-written object, because every write lands through a rename.
"""

from __future__ import annotations

import hashlib
import json
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator, Literal

MANIFEST_VERSION = 1

Kind = Literal["prs", "commits"]


def encode(payload: object) -> bytes:
    """The one byte format of a stored object. [LAW:one-source-of-truth] every writer
    goes through here, so the same GitHub state always produces the same bytes and the
    same hash - which is what makes the bank verifiable at all."""
    return (json.dumps(payload, indent=1, sort_keys=True, ensure_ascii=False) + "\n").encode()


@dataclass(frozen=True)
class Ref:
    """Where one object lives. `kind` names its store and is the only thing that differs
    between the two; the read, the write, and the hash are the same operation for both."""

    kind: Kind
    repo: str
    name: str

    @property
    def key(self) -> str:
        return f"{self.kind}/{self.repo}/{self.name}"

    def path(self, root: Path) -> Path:
        return root / self.kind / self.repo / f"{self.name}.json"

    @staticmethod
    def parse(key: str) -> "Ref":
        """[LAW:parse-dont-validate] a manifest key becomes a Ref or raises; no caller
        downstream ever splits a key string again."""
        kind, _, rest = key.partition("/")
        repo, _, name = rest.partition("/")
        if kind not in ("prs", "commits") or not repo or not name:
            raise ValueError(f"not a bank key: {key!r}")
        return Ref(kind, repo, name)


def pr_ref(repo: str, number: int) -> Ref:
    return Ref("prs", repo, str(number))


def commit_ref(repo: str, oid: str) -> Ref:
    return Ref("commits", repo, oid)


class Bank:
    """One data bank rooted at a directory. Open it, ask what it has, put things in it,
    and close it - the manifest is written as you go and again on the way out."""

    def __init__(self, root: Path) -> None:
        self.root = root
        self.manifest_path = root / "manifest.json"
        self.entries: dict[str, dict] = {}
        self._unflushed = 0
        if self.manifest_path.exists():
            doc = json.loads(self.manifest_path.read_text())
            if doc.get("version") != MANIFEST_VERSION:  # [LAW:no-silent-failure]
                raise SystemExit(
                    f"{self.manifest_path} is manifest version {doc.get('version')!r}, "
                    f"this tool writes {MANIFEST_VERSION}. Re-import rather than guessing."
                )
            self.entries = doc["entries"]

    # -- reading -----------------------------------------------------------

    def version_of(self, ref: Ref) -> str | None:
        """The upstream version stored for this object, or None when the bank has no
        such object. For a pull request that is GitHub's `updatedAt`; for a commit it is
        the oid, so `is not None` is the whole freshness question."""
        entry = self.entries.get(ref.key)
        return entry["version"] if entry else None

    def refs(self, kind: Kind) -> Iterator[Ref]:
        """Every object of one kind the bank claims to hold, in key order."""
        for key in sorted(self.entries):
            ref = Ref.parse(key)
            if ref.kind == kind:
                yield ref

    def get(self, ref: Ref) -> dict:
        """One stored object. [LAW:no-silent-failure] the manifest is authoritative, so a
        ref it does not list is an error here rather than a silent read of a stray file."""
        if ref.key not in self.entries:
            raise KeyError(f"{ref.key} is not in {self.manifest_path}")
        return json.loads(ref.path(self.root).read_text())

    # -- writing -----------------------------------------------------------

    def put(self, ref: Ref, payload: object, version: str) -> None:
        """Store one object and record it. The rename makes a half-written object
        unrepresentable: a reader sees the whole old content or the whole new one. The
        temp file is a sibling because `os.replace` is only atomic within a filesystem."""
        raw = encode(payload)
        path = ref.path(self.root)
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_name(path.name + ".tmp")
        tmp.write_bytes(raw)
        os.replace(tmp, path)
        self.entries[ref.key] = {"version": version, "sha256": hashlib.sha256(raw).hexdigest(), "bytes": len(raw)}
        self._unflushed += 1

    def flush(self) -> None:
        """Write the index, atomically. How often to call it is the caller's policy and
        decides one thing: how much fetched work a SIGKILL strands as orphans. Cheap -
        the manifest is a few hundred KB - so call it at every natural boundary."""
        raw = encode({"version": MANIFEST_VERSION, "entries": self.entries})
        self.root.mkdir(parents=True, exist_ok=True)
        tmp = self.manifest_path.with_name(self.manifest_path.name + ".tmp")
        tmp.write_bytes(raw)
        os.replace(tmp, self.manifest_path)
        self._unflushed = 0

    # -- verifying ---------------------------------------------------------

    def integrity(self) -> list[str]:
        """Every way the bytes on disk disagree with the index, offline. Empty means the
        bank holds exactly what it recorded fetching, unchanged."""
        problems: list[str] = []
        for key, entry in sorted(self.entries.items()):
            path = Ref.parse(key).path(self.root)
            if not path.exists():
                problems.append(f"{key}: in the manifest, missing on disk")
                continue
            raw = path.read_bytes()
            if len(raw) != entry["bytes"] or hashlib.sha256(raw).hexdigest() != entry["sha256"]:
                problems.append(f"{key}: {len(raw)} bytes on disk, {entry['bytes']} when fetched - content changed")
        for path in sorted(self.root.glob("*/*/*.json")):
            key = f"{path.parent.parent.name}/{path.parent.name}/{path.stem}"
            if key not in self.entries:
                problems.append(f"{key}: on disk, not in the manifest - an interrupted write; sync will replace it")
        return problems
