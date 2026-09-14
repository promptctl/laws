#!/usr/bin/env python3
"""Render, blind and collect the subagent prompts for one medium's round-trip eval.

The orchestrating session dispatches every subagent; this script only writes their
prompt files, stages blind judge inputs outside the repository, and copies verdicts
back. Each step checks the property that makes the comparison valid.

    stage.py distill  MEDIUM --scratch DIR   prompt: current guidance -> DIR/specs/MEDIUM.spec.md
    stage.py adopt    MEDIUM --scratch DIR   copy that spec to MEDIUM/spec.md
    stage.py compile  MEDIUM --scratch DIR   prompt: MEDIUM/spec.md -> MEDIUM/craft-roundtrip.md
    stage.py arms     MEDIUM --scratch DIR [--arm ARM ...]   prompts: control, current, roundtrip
    stage.py judges   MEDIUM --scratch DIR   blind inputs + prompts for two judges
    stage.py collect  MEDIUM --scratch DIR   copy verdicts back as MEDIUM/judge-*.md
"""
import argparse
import json
import random
import re
import shutil
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent.parent
TEMPLATES = ROOT / "templates"
ARMS = ("control", "current", "roundtrip")
# Words that would tell a judge what is being compared.
PROMPT_LEAKS = ("control", "current", "roundtrip", "round-trip", "craft", "distill", "evals", "outputs/")
BODY_LEAKS = ("roundtrip", "round-trip", "distill")
RUBRIC_INSTRUCTIONS = {
    "spec": (
        "a numbered specification",
        "A table with one row per numbered requirement and one column per response. Each cell is "
        "`met`, `not met`, or `n/a` (nothing in the response can show it). Counts per response at the end.",
    ),
    "guidance": (
        "a standard in long form",
        "List the distinct rules the standard asks of a finished response, skipping rules about the "
        "writer's process that leave nothing in the response. Number them. Then a table with one row "
        "per rule and one column per response, each cell `met`, `not met`, or `n/a`. Counts per "
        "response at the end.",
    ),
}


def fill(template_name: str, values: dict[str, str]) -> str:
    template = (TEMPLATES / template_name).read_text()
    names = set(re.findall(r"\{\{(\w+)\}\}", template))
    if names != set(values):
        sys.exit(f"{template_name}: placeholders {sorted(names)} do not match values {sorted(values)}")
    return re.sub(r"\{\{(\w+)\}\}", lambda m: values[m.group(1)], template)


def require(path: Path) -> Path:
    if not path.is_file() or path.stat().st_size == 0:
        sys.exit(f"missing or empty: {path}")
    return path


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    print(path)


def distill(medium: Path, meta: dict, scratch: Path, arm_names: tuple[str, ...]) -> None:
    write(scratch / "prompts" / f"distill-{medium.name}.md", fill("distill.md", {
        "SKILL": str(require(REPO / ".claude/skills/distill/SKILL.md")),
        "SOURCE": str(require(REPO / meta["guidance"])),
        "OUT": str(scratch / "specs" / f"{medium.name}.spec.md"),
    }))


def adopt(medium: Path, meta: dict, scratch: Path, arm_names: tuple[str, ...]) -> None:
    shutil.copyfile(require(scratch / "specs" / f"{medium.name}.spec.md"), medium / "spec.md")
    print(medium / "spec.md")


def compile_(medium: Path, meta: dict, scratch: Path, arm_names: tuple[str, ...]) -> None:
    original = REPO / meta["guidance"]
    # When the medium's guidance is the compiler's own craft, the compiler must read it,
    # so this one recompile cannot be blind.
    blindness = (
        f"The specification was distilled from {original}, which is also the craft you apply, so you "
        "will read it. Use it only as the craft; write every rule from the specification, and copy no "
        "passage from the craft."
        if meta.get("guidance_is_compiler") else
        f"Do not read {original}: this is a blind recompile, and reading the current version would "
        "contaminate it."
    )
    write(scratch / "prompts" / f"compile-{medium.name}.md", fill("compile.md", {
        "BLINDNESS": blindness,
        "SPEC": str(require(medium / "spec.md")),
        "OUT": str(medium / "craft-roundtrip.md"),
        "READER": meta["reader"],
    }))


def arms(medium: Path, meta: dict, scratch: Path, arm_names: tuple[str, ...]) -> None:
    task = require(medium / "task.md").read_text()
    sources = {"control": None, "current": REPO / meta["guidance"], "roundtrip": medium / "craft-roundtrip.md"}
    prompts = {arm: scratch / "prompts" / f"arm-{medium.name}-{arm}.md" for arm in ARMS}
    texts: dict[str, str] = {}
    skeletons: dict[str, str] = {}
    # The control and current arms need no spec, so they can run before the recompile exists.
    # A split run must still give every arm the same prompt, so prompts an earlier run left
    # in the scratch directory are compared along with the ones rendered now.
    for arm in (a for a in ARMS if a in arm_names or prompts[a].is_file()):
        src = sources[arm]
        block = ("There is no guidance for this run beyond the task." if src is None else
                 "Guidance you must follow while doing the task. It is between the markers.\n\n"
                 f"<guidance>\n{require(src).read_text()}\n</guidance>")
        out = medium / "outputs" / f"{arm}.{meta['ext']}"
        texts[arm] = (fill("arm.md", {"OUTPATH": str(out), "GUIDANCE": block, "TASK": task})
                      if arm in arm_names else prompts[arm].read_text())
        skeletons[arm] = texts[arm].replace(block, "<guidance>").replace(str(out), "<out>")
    if len(set(skeletons.values())) != 1:
        sys.exit(f"arm prompts {sorted(skeletons)} differ outside the guidance block and output path "
                 f"(an earlier run's prompt in {scratch / 'prompts'} counts, as does a guidance file "
                 "edited since that run)")
    for arm in arm_names:
        write(prompts[arm], texts[arm])
    (medium / "outputs").mkdir(exist_ok=True)


def judges(medium: Path, meta: dict, scratch: Path, arm_names: tuple[str, ...]) -> None:
    ext = meta["ext"]
    rubrics = {"spec": require(medium / "spec.md"), "guidance": require(REPO / meta["guidance"])}
    key: dict[str, dict] = {}
    for name, rubric in rubrics.items():
        # Not under scratch: its parent would hold the judge key and the arm prompts.
        staging = Path(tempfile.mkdtemp(prefix="review-"))
        order = list(ARMS)
        random.shuffle(order)
        letters = dict(zip("ABC", order))
        for letter, arm in letters.items():
            shutil.copyfile(require(medium / "outputs" / f"{arm}.{ext}"), staging / f"{letter}.{ext}")
        shutil.copyfile(medium / "task.md", staging / "task.md")
        shutil.copyfile(rubric, staging / "rubric.md")
        run = meta.get("run")
        run_line = (f"You may run `{run.format(file='<letter>.' + ext)}` for each response from {staging}, "
                    "and use the result. Run nothing else." if run else "Run nothing.")
        kind, instruction = RUBRIC_INSTRUCTIONS[name]
        text = fill("judge.md", {
            "RUN": run_line, "TASK": str(staging / "task.md"), "RUBRIC": str(staging / "rubric.md"),
            "RUBRIC_KIND": kind, "RUBRIC_INSTRUCTION": instruction, "VERDICT": str(staging / "judge.md"),
            **{letter: str(staging / f"{letter}.{ext}") for letter in "ABC"},
        })
        for word in PROMPT_LEAKS:
            if word in text.lower():
                sys.exit(f"judge prompt for {name} leaks {word!r}")
        # A word every response uses cannot tell the judge which arm is which ("round-trip
        # tests" in all three backlogs); one that only some responses use can.
        bodies = {letter: (staging / f"{letter}.{ext}").read_text().lower() for letter in "ABC"}
        for word in BODY_LEAKS:
            holders = sorted(letter for letter, body in bodies.items() if word in body)
            if holders and len(holders) < 3:
                sys.exit(f"responses {holders} for {name} contain {word!r} and the rest do not; inspect before judging")
        write(scratch / "prompts" / f"judge-{medium.name}-{name}.md", text)
        key[name] = {"staging": str(staging), "letters": letters}
    (scratch / f"judge-key-{medium.name}.json").write_text(json.dumps(key, indent=2))
    lines = ["# Judge key", "",
             "Each judge saw the outputs as <letter> files in its own scratch directory, shuffled "
             "independently, with no arm or experiment name in any path it read.", ""]
    for name, entry in key.items():
        lines += [f"## judge-{name}.md", ""] + [f"- {k}: {v}" for k, v in entry["letters"].items()] + [""]
    write(medium / "judge-key.md", "\n".join(lines))


def collect(medium: Path, meta: dict, scratch: Path, arm_names: tuple[str, ...]) -> None:
    key = json.loads(require(scratch / f"judge-key-{medium.name}.json").read_text())
    for name, entry in key.items():
        shutil.copyfile(require(Path(entry["staging"]) / "judge.md"), medium / f"judge-{name}.md")
        print(medium / f"judge-{name}.md")


STEPS = {"distill": distill, "adopt": adopt, "compile": compile_, "arms": arms, "judges": judges, "collect": collect}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("step", choices=STEPS)
    parser.add_argument("medium")
    parser.add_argument("--scratch", required=True, type=Path, help="directory outside the repository")
    parser.add_argument("--arm", action="append", choices=ARMS, help="arms step only; default all three")
    args = parser.parse_args()
    scratch = args.scratch.resolve()
    if scratch.is_relative_to(REPO):
        sys.exit("--scratch must be outside the repository, or judges could read the arm names")
    medium = ROOT / args.medium
    meta = json.loads(require(medium / "meta.json").read_text())
    STEPS[args.step](medium, meta, scratch, tuple(args.arm or ARMS))


if __name__ == "__main__":
    main()
