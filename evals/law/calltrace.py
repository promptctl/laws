"""The call-trace oracle helper: what type did each of the program's own functions receive?

A parse-dont-validate verdict is read from the shape of the code, and the runtime shows
that shape without guessing at the agent's names: run the program once on good input and
record, for every call into a function defined in the program's own files, the type of
each argument. A function inland of the boundary that still receives the raw type (the
`dict` json.load returned, the `str` a query string carried) was handed unchecked data,
whatever was checked above it. One that receives a type the program defines, or a
stdlib type that cannot hold the raw value (a `datetime`, not the `str`), was handed the
proof. What each function returned is recorded too, so the boundary itself - raw type in,
proving type out - can be told from a worker that merely received the raw type, wherever
the agent put it.

    trace(program_dir, environment) -> (Observation, [Call])

runs the program as differential.observe does (a fresh copy, its own HOME, the oracle's
inputs written over the agent's) under a profiler, so the run's channels are observed too.
"""
from __future__ import annotations

import json
import os
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import differential  # noqa: E402

OUT_ENV = "LAW_EVAL_CALLTRACE_OUT"


@dataclass(frozen=True)
class ArgType:
    module: str
    name: str
    local: bool  # the class is defined in the program's own files

    def __str__(self) -> str:
        return f"{self.module}.{self.name}" + (" (program)" if self.local else "")


@dataclass(frozen=True)
class Call:
    function: str  # the function's qualified name
    file: str  # relative to the program dir
    args: tuple[tuple[str, ArgType], ...]  # (parameter, type of the value it received)
    returned: tuple[ArgType, ...]  # every type this function returned, over the whole run

    def arg(self, name: str) -> ArgType | None:
        return dict(self.args).get(name)


def trace(program_dir: Path, environment: differential.Environment) -> tuple[differential.Observation, list[Call]]:
    with tempfile.TemporaryDirectory(prefix="law-eval-calltrace-") as tmp:
        out = Path(tmp) / "calls.json"
        traced = differential.Environment(
            (str(Path(__file__).resolve()), *environment.argv),
            {**environment.env, OUT_ENV: str(out)},
            environment.inputs,
        )
        observation = differential.observe(program_dir, traced)
        if not out.exists():
            raise RuntimeError(f"the traced run wrote no trace; stderr: {observation.stderr[-1000:]}")
        trace_data = json.loads(out.read_text())
        returned = {(r["file"], r["function"]): tuple(ArgType(**t) for t in r["types"]) for r in trace_data["returns"]}
        calls = [
            Call(c["function"], c["file"], tuple((p, ArgType(**t)) for p, t in c["args"]),
                 returned.get((c["file"], c["function"]), ()))
            for c in trace_data["calls"]
        ]
    return observation, calls


def _run_traced() -> None:
    """In the program's process: run argv[1] as __main__ under a profiler, then write the trace."""
    import inspect
    import runpy

    root = Path.cwd().resolve()
    calls: list[dict] = []
    seen: set[str] = set()
    returns: dict[tuple[str, str], list[dict]] = {}
    type_cache: dict[type, dict] = {}

    def describe(cls: type) -> dict:
        if cls not in type_cache:
            try:
                source = Path(inspect.getsourcefile(cls) or "").resolve()
                local = source.is_relative_to(root)
            except (TypeError, OSError):
                local = False
            type_cache[cls] = {"module": cls.__module__, "name": cls.__qualname__, "local": local}
        return type_cache[cls]

    def profile(frame, event, arg):
        if event not in ("call", "return"):
            return
        code = frame.f_code
        if code.co_name.startswith("<"):
            return
        # The script runs by a relative path; frozen and generated code is named
        # "<frozen runpy>" or "<string>", which is no file at all.
        path = (root / code.co_filename).resolve()
        if not path.is_relative_to(root) or not path.is_file():
            return
        if event == "return":
            types = returns.setdefault((str(path.relative_to(root)), code.co_qualname), [])
            if describe(type(arg)) not in types:
                types.append(describe(type(arg)))
            return
        count = code.co_argcount + code.co_kwonlyargcount
        params = [n for n in code.co_varnames[:count] if n not in ("self", "cls")]
        args = [[name, describe(type(frame.f_locals[name]))] for name in params if name in frame.f_locals]
        entry = {"function": code.co_qualname, "file": str(path.relative_to(root)), "args": args}
        # One record per distinct call shape keeps a loop over 10k rows from writing 10k records.
        key = json.dumps(entry, sort_keys=True)
        if key not in seen:
            seen.add(key)
            calls.append(entry)

    def dump() -> None:
        sys.setprofile(None)
        listed = [{"file": f, "function": fn, "types": t} for (f, fn), t in returns.items()]
        Path(os.environ[OUT_ENV]).write_text(json.dumps({"calls": calls, "returns": listed}))

    script = sys.argv[1]
    sys.argv = sys.argv[1:]
    # The program imports its own modules, never the oracle's.
    here = Path(__file__).resolve().parent
    sys.path[:] = [str(Path(script).resolve().parent)] + [p for p in sys.path if Path(p or ".").resolve() != here]
    sys.setprofile(profile)
    try:
        runpy.run_path(script, run_name="__main__")
    finally:
        dump()


if __name__ == "__main__":
    _run_traced()
