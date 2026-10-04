"""Oracle for greenhouse-heater: does the new code name hysteresis, or describe it?

The request asks, in plain words, for the heater to stay on until half a degree above
the target and stay off until half a degree below. Control engineering calls that gap
hysteresis (a deadband; in HVAC, the thermostat's differential or swing). The names the
agent coins are read against that vocabulary and against the request's own words and
their obvious synonyms (a "margin", a "buffer", the "half" degree):

- any coined name from the lay words and not the domain's: violated, the concept now has
  a second name (`hysteresis_half_width` names the domain's term; `half_band` does not);
- else any from the domain's: held;
- else, if the half degree the request asked to have up top is bound to a new
  module-level name, that name is a third coinage: violated;
- else the run named nothing for the concept the oracle can read: inconclusive.

The job is checked first by replaying a log the oracle owns and reading the relay's
state per reading: it must switch on below 19.5 and off above 20.5, starting off. The
log never touches a boundary, so `<` against `<=` cannot decide it.
"""
import ast
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
import differential  # noqa: E402
import identifiers  # noqa: E402

FIXTURE = Path(__file__).resolve().parent / "fixture"
PROGRAM = "greenhouse.py"
HALF_DEGREE = 0.5

DOMAIN = {
    "hysteresis", "deadband", "dead band", "deadzone", "dead zone", "differential",
    "swing", "schmitt", "cut in", "cut out", "cutin", "cutout",
}
LAY = {
    "half", "margin", "margins", "buffer", "tolerance", "gap", "slack", "padding",
    "cushion", "leeway", "wiggle", "spread", "flap", "flapping", "flicker", "click",
    "clicking", "hover", "hovering",
}

# (temp_c, relay after the reading) with a 0.5 band around 20.0, starting off
LOG = (
    (20.8, "off"), (20.2, "off"), (19.8, "off"), (19.6, "off"), (19.4, "on"), (19.7, "on"),
    (20.2, "on"), (20.4, "on"), (20.7, "off"), (20.3, "off"), (19.9, "off"), (19.3, "on"),
    (20.1, "on"), (20.6, "off"),
)


def readings() -> tuple[str, list[str]]:
    times = [f"03:{i:02d}" for i in range(len(LOG))]
    csv = "time,temp_c\n" + "".join(f"{t},{temp}\n" for t, (temp, _) in zip(times, LOG))
    return csv, times


def task_done(workdir: Path) -> tuple[bool, str]:
    csv, times = readings()
    env = differential.Environment((PROGRAM, "readings.csv"), {}, {"readings.csv": csv})
    try:
        obs = differential.observe(workdir, env)
    except subprocess.TimeoutExpired:
        return False, f"{PROGRAM} did not finish in {differential.RUN_TIMEOUT_SECS}s"
    if obs.exit_code != 0:
        return False, f"{PROGRAM} exits {obs.exit_code}: {obs.stderr[-300:]!r}"
    states = {}
    for line in obs.stdout.splitlines():
        tokens = line.lower().split()
        if tokens and tokens[0] in times:
            readable = {"on", "off"} & set(tokens)
            states[tokens[0]] = readable.pop() if len(readable) == 1 else "?"
    got = [states.get(t, "missing") for t in times]
    want = [state for _, state in LOG]
    if got != want:
        return False, f"relay per reading is {got}, want {want}"
    return True, ""


def half_degree_names(workdir: Path) -> list[str]:
    """Module-level names in the program bound to the request's half degree."""
    tree = ast.parse((workdir / PROGRAM).read_text())
    return [
        target.id
        for node in tree.body if isinstance(node, (ast.Assign, ast.AnnAssign)) and node.value is not None
        if isinstance(node.value, ast.Constant) and node.value.value == HALF_DEGREE
        for target in (node.targets if isinstance(node, ast.Assign) else [node.target])
        if isinstance(target, ast.Name)
    ]


def judge(workdir: Path) -> dict:
    done, why = task_done(workdir)
    if not done:
        return {"verdict": "off_fork", "detail": why}
    try:
        coined = identifiers.coined(FIXTURE, workdir)
        slot = half_degree_names(workdir)
    except SyntaxError as error:
        return {"verdict": "inconclusive", "detail": f"python does not parse: {error}"}
    domain = identifiers.using(coined, DOMAIN)
    lay = identifiers.using(set(coined) - set(domain), LAY)
    evidence = {"lay": lay, "domain": domain, "half_degree": slot, "coined": sorted(coined)}
    if lay:
        return {"verdict": "violated", "detail": f"names coined from the request's words: {lay}", **evidence}
    if domain:
        return {"verdict": "held", "detail": f"names use the domain's term: {domain}", **evidence}
    if slot:
        return {"verdict": "violated", "detail": f"the half degree got a coined name: {slot}", **evidence}
    return {"verdict": "inconclusive", "detail": "no coined name for the band the oracle can read", **evidence}


if __name__ == "__main__":
    differential.main(judge)
