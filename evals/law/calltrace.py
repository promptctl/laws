"""The call-trace oracle helper: what type did each of the program's own functions receive?

A parse-dont-validate verdict is read from the shape of the code, and the runtime shows
that shape without guessing at the agent's names: run the program once on good input and
record, for every call into a function defined in the program's own files, the type of
each argument. A function inland of the boundary that still receives the raw type (the
`dict` json.load returned, the `str` a query string carried) was handed unchecked data,
whatever was checked above it. One that receives a type the program defines, or a
stdlib type that cannot hold the raw value (a `datetime`, not the `str`), was handed the
proof. What each function returned is recorded too (a constructor returns the object it
built; a list, tuple, set or dict returns what it holds as well), and which function
produced each argument a call received, so the boundary itself
- raw type in, proving type out, and that proof is what inland is handed - can be told
from a worker that merely received the raw type, wherever the agent put it.

    trace(program_dir, environment) -> (Observation, [Call])
    crossing(calls, worker, is_raw, is_proof) -> the functions that are the boundary
    inland(calls, worker, crossing) -> the calls into `worker` that are not part of it

runs the program as differential.observe does (a fresh copy, its own HOME, the oracle's
inputs written over the agent's) under a profiler, so the run's channels are observed too.
"""
from __future__ import annotations

import json
import os
import sys
import tempfile
from collections.abc import Callable
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


Site = tuple[str, str]  # (file relative to the program dir, qualified name): one function of the program


@dataclass(frozen=True)
class Call:
    function: str  # the function's qualified name
    file: str  # relative to the program dir
    args: tuple[tuple[str, ArgType], ...]  # (parameter, type of the value it received)
    returned: tuple[ArgType, ...]  # every type this function returned, over the whole run; a constructor's own class
    callers: tuple[Site, ...]  # the program's own functions on the stack above this call, innermost first
    sources: tuple[Site, ...]  # the program's functions that returned an argument this call received

    @property
    def site(self) -> Site:
        return (self.file, self.function)

    def arg(self, name: str) -> ArgType | None:
        return dict(self.args).get(name)


def crossing(calls: list[Call], worker: str, is_raw: Callable[[ArgType], bool],
             is_proof: Callable[[ArgType], bool]) -> set[Site]:
    """The functions, in any file, that took a raw value, returned a proof, and whose proof
    a call into `worker` - one not made from inside them - then received. A worker that
    takes the raw value and returns a report of what it did is not one while nothing
    inland is handed its report; one whose report is handed back inland reads as the
    crossing, which is why a verdict names the crossing it found."""
    candidates = {c.site for c in calls if any(is_raw(t) for _, t in c.args) and any(is_proof(t) for t in c.returned)}
    return {s for c in calls if c.file == worker for s in c.sources
            if s in candidates and s != c.site and s not in c.callers}


def inland(calls: list[Call], worker: str, boundary: set[Site]) -> list[Call]:
    """The calls into `worker` that are not part of the crossing. The crossing's own helpers
    take the raw value by design, so every call made from inside it is part of it too."""
    return [c for c in calls if c.file == worker and c.site not in boundary and not boundary.intersection(c.callers)]


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
                 returned.get((c["file"], c["function"]), ()), tuple(map(tuple, c["callers"])),
                 tuple(map(tuple, c["sources"])))
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
    file_cache: dict[str, str | None] = {}
    # id -> (the object, held so its id is not reused; the program functions that returned it)
    produced: dict[int, tuple[object, set[tuple[str, str]]]] = {}

    def describe(cls: type) -> dict:
        if cls not in type_cache:
            try:
                source = Path(inspect.getsourcefile(cls) or "").resolve()
                local = source.is_relative_to(root)
            except (TypeError, OSError):
                local = False
            type_cache[cls] = {"module": cls.__module__, "name": cls.__qualname__, "local": local}
        return type_cache[cls]

    def program_file(code) -> str | None:
        """The code's file relative to the program dir, or None if it is not the program's own.
        The script runs by a relative path; frozen and generated code is named "<frozen runpy>"
        or "<string>", which is no file at all."""
        if code.co_filename not in file_cache:
            path = (root / code.co_filename).resolve()
            file_cache[code.co_filename] = (
                str(path.relative_to(root)) if path.is_relative_to(root) and path.is_file() else None)
        return file_cache[code.co_filename]

    def program_function(code) -> str | None:
        """program_file, for a function the agent wrote: not a module or class body (which
        run once, on import), a lambda or comprehension, or the `__annotate__` the compiler
        generates for annotations."""
        if not code.co_flags & inspect.CO_OPTIMIZED or code.co_name.startswith("<") or code.co_name == "__annotate__":
            return None
        return program_file(code)

    def profile(frame, event, arg):
        if event not in ("call", "return"):
            return
        code = frame.f_code
        rel = program_function(code)
        if rel is None:
            return
        site = (rel, code.co_qualname)
        if event == "return":
            # A constructor returns None; what it made is the object it initialized.
            value = frame.f_locals.get("self") if code.co_name == "__init__" else arg
            held = value.values() if isinstance(value, dict) else value if isinstance(value, (list, tuple, set, frozenset)) else ()
            types = returns.setdefault(site, [])
            for made in (value, *held):
                if describe(type(made)) not in types:
                    types.append(describe(type(made)))
                # A builtin value (the raw dict, a str, a count) proves nothing, so where it came from is not kept.
                if type(made).__module__ != "builtins":
                    produced.setdefault(id(made), (made, set()))[1].add(site)
            return
        count = code.co_argcount + code.co_kwonlyargcount
        params = [n for n in code.co_varnames[:count] if n not in ("self", "cls")]
        values = [(name, frame.f_locals[name]) for name in params if name in frame.f_locals]
        args = [[name, describe(type(value))] for name, value in values]
        sources = sorted({s for _, value in values if (p := produced.get(id(value))) and p[0] is value for s in p[1]})
        callers, caller = [], frame.f_back
        while caller is not None:
            if (outer := program_function(caller.f_code)) is not None:
                callers.append((outer, caller.f_code.co_qualname))
            caller = caller.f_back
        entry = {"function": code.co_qualname, "file": rel, "args": args, "callers": callers, "sources": sources}
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
