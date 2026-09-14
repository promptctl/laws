# Round-trip evals for the crafts

A craft is the active form of a writing standard: it steers an agent that holds it in
context. Its spec is the inactive form: the same rules stated once, plainly, with
strength, condition and exceptions, and nothing else. The `distill` skill turns a craft
into a spec. `laws:prompt` turns a spec back into a craft. These evals test how much
survives the trip, on one small single-shot task per medium.

## Layout

Each medium has a directory, such as `prose/` or `code/`, holding:

- `meta.json` - the path of the current guidance, the output extension, the reader
  the recompiled craft is written for, and for code the command a judge may run.
- `task.md` - one small single-shot task. It gives fixed facts, names a reader, and
  says what a response may not add, so a judge can score fidelity.
- `spec.md` - the current guidance distilled by a fresh session holding only `distill`.
- `craft-roundtrip.md` - `spec.md` recompiled by a fresh session holding only
  `laws:prompt`, which never saw the current guidance.
- `outputs/control.*`, `outputs/current.*`, `outputs/roundtrip.*` - the task done with
  no guidance, with the current guidance, and with the recompiled craft.
- `judge-spec.md` and `judge-guidance.md` - two blind verdicts, one using the spec as
  rubric and one using the current guidance. `judge-key.md` decodes their letters.

`prose/pilot/` holds the first run, made before these templates existed. Its
`results.md` explains why the protocol looks the way it does.

## Protocol

Every step is a fresh subagent on one model. `distill` and `laws:prompt` are inverse
standards, so no session holds both, and an arm that has seen a craft is no longer a
control. `stage.py` renders each subagent's prompt from `templates/` into a scratch
directory outside the repository; the orchestrating session dispatches them.

```sh
S=<scratch dir outside the repo>
python3 evals/roundtrip/stage.py distill MEDIUM --scratch $S   # then dispatch it
python3 evals/roundtrip/stage.py adopt   MEDIUM --scratch $S
python3 evals/roundtrip/stage.py compile MEDIUM --scratch $S   # then dispatch it
python3 evals/roundtrip/stage.py arms    MEDIUM --scratch $S   # then dispatch three
python3 evals/roundtrip/stage.py judges  MEDIUM --scratch $S   # then dispatch two
python3 evals/roundtrip/stage.py collect MEDIUM --scratch $S
```

The control and current arms need no spec, so `arms --arm control --arm current` can
run before the recompile exists.

Rules the templates and script enforce:

- **The recompile adds nothing.** It may harden a rule with a rehearsed temptation only
  where the spec gives that rule a failure clause, and it adds no permission, method or
  clause the spec lacks. In the pilot the compiler chose its own temptations, and the
  spec grew by a third on the trip back.
- **Arms differ only in guidance.** `stage.py` fails if two arm prompts differ anywhere
  else.
- **Judges are blind.** Outputs are copied as `A`, `B`, `C` in an independent random
  order per judge into a scratch directory. The script fails if a judge prompt names
  an arm or the experiment, or if a response mentions it.
- **Fidelity is scored.** Each judge counts missing, misstated and added facts against
  the task. In the pilot, a judge that scored only the rubric ranked the arm with the
  most inventions first.
- **Two rubrics.** The recompiled craft was built from the spec, so a spec rubric can
  favour it. The second judge uses the current guidance instead.

## Reading the results

Compare the arms per medium. Control is the floor. A gap between current and roundtrip
on a rule or on fidelity means the spec lost something the craft carried, usually a
condition or a failure the craft had rehearsed. One output per arm cannot separate a
craft's effect from run-to-run variance, so treat a one-rule gap as noise until it
repeats.
