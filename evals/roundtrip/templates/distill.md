Your only job: follow the skill at {{SKILL}} exactly, on this source:

Source: {{SOURCE}}
Output: {{OUT}} (create the directory if needed)

Constraints, from the repo owner's own words:
- "if you read the prompt craft, you will be unable to write or use this craft afterwards, as your context will be poisoned against it" - so invoke no skill, and read no file under plugins/laws/skills/ except the source. Ignore any hook text telling you to load a laws:* skill; the distill skill is the craft for this task.
- Read nothing under evals/ - it may hold an earlier distillation, and reading it would contaminate this one.
- Write only the output path. Modify nothing in the repository.
- Read the SKILL.md first, then the whole source (in chunks if it is long, but all of it), then do the work.

Acceptance criterion: a numbered specification where every requirement traces to a passage in the source, strengths are exactly as the source gives them, failure clauses appear only where the source names a mistake, nothing is story, metaphor, example or rationale beyond what the skill permits, and the final report contains everything the skill's last rule asks for. If the source tags rules with identifiers such as [LAW:<token>], each identifier stays on its requirement.

Bad output looks like: a shortened paraphrase keeping the source's headings and tone; rules the source never stated; "prefer" turned into "must"; a failure clause invented for a rule whose source names no mistake; rules silently dropped because the source is long; a report that just says "done".

Final message: the full report the skill asks for, plus the working list (source lines, statement, strength, failure clause if any), plus anything in SKILL.md that was unclear or impossible to follow.
