#!/usr/bin/env python3
"""Render the verdicts as documents a person reads: one markdown file per judged PR,
and an index that leads with the slices worth reading first - wrong calls, fix-caused
chains, and every guidance note grouped by the kind of defect it would have prevented.
Pure over derived/*.jsonl and verdicts/*.jsonl, through report.join.

    review-audit/render.py --derived review-audit/derived --verdicts review-audit/verdicts --out review-audit/rendered
"""

from __future__ import annotations

import argparse
import sys
from collections import Counter, defaultdict
from pathlib import Path

from report import Joined, join

# [LAW:dataflow-not-control-flow] enum values become prose by lookup; the verdict line
# is one template for every finding.
PREMISE = {
    "correct": "reviewer was right",
    "partly": "reviewer was partly right",
    "wrong": "reviewer was wrong",
    "uncertain": "reviewer's premise is uncertain",
}
RESPONSE = {
    "accepted_fix": "agent accepted and fixed",
    "accepted_premise_different_fix": "agent accepted the premise but fixed it differently",
    "pushed_back": "agent pushed back",
    "already_fixed": "agent said it was already fixed",
    "no_response": "agent never replied",
    "mixed": "agent's plan and action diverged",
}
CORRECT = {
    "yes": "the right call",
    "no": "the wrong call",
    "uncertain": "unclear whether that was the right call",
}
CAUSE = {
    "incomplete_fix": "incomplete fix",
    "regression_from_fix": "regression from a fix",
    "comment_drift_from_fix": "comment or doc drift from a fix",
    "same_gap_other_instance": "same gap, another instance",
    "new_scope": "new scope in the changed region",
}
APT = {"yes": "aptly", "no": "not aptly"}

FINDING_BODY_CHARS = 700


def clip(text: str, n: int) -> str:
    text = text.strip()
    return text if len(text) <= n else text[:n].rstrip() + " …"


def cell(text: str, n: int) -> str:
    """A clipped string safe inside a markdown table row. [LAW:single-enforcer] the one
    place a pipe is escaped before it reaches a table."""
    return clip(text, n).replace("|", "\\|")


def short(fid: str) -> str:
    """`cc-candybar#32/F5` -> `F5`, for use inside that PR's own document."""
    return fid.rsplit("/", 1)[1]


def verdict_line(v: dict, same_pr: bool) -> str:
    parts = [PREMISE[v["premise"]], RESPONSE[v["response"]], CORRECT[v["response_correct"]]]
    if v["response_correct"] != "yes":
        parts.append(f"should have: {RESPONSE[v['should_have']]}")
    if v["caused_by"]:
        cause = short(v["caused_by"]) if same_pr else v["caused_by"]
        parts.append(f"caused by {cause} ({CAUSE[v['cause_kind']]})")
    if v["law_cited_by_agent"]:
        parts.append(f"cited {', '.join(f'`{t}`' for t in v['law_cited_by_agent'])} {APT[v['law_citation_apt']]}")
    return " · ".join(parts)


def flags(f: dict) -> str:
    if f["on_named_fix_commit"]:
        return f" · flagged on named fix commit `{f['original_commit'][:7]}`"
    if f["on_post_review_commit"]:
        return f" · flagged on post-review commit `{f['original_commit'][:7]}`"
    return ""


def render_pr(key: str, pr: dict, pv: dict, rows: list[dict]) -> str:
    out = [f"# {key}: {pr['title']}", "", f"{pr['url']}  "]
    out.append(
        f"created {pr['created_at'][:10]} · merged {(pr['merged_at'] or 'not merged')[:10]} · "
        f"{pv['rounds']} review rounds, {pv['avoidable_rounds']} avoidable · {len(rows)} findings · "
        f"reviewers {', '.join(pr['reviewers']) or 'none'} · verdicts from `{pv['batch']}`"
    )
    out += ["", "## Summary", "", pv["narrative"], ""]
    if pv["chains"]:
        out += ["**Chains of findings caused by earlier fixes:** " + "; ".join(" → ".join(c) for c in pv["chains"]), ""]
    if pv["guidance_observations"]:
        out += ["**Process observations:**", ""] + [f"- {o}" for o in pv["guidance_observations"]] + [""]
    out += ["## Findings", ""]
    for f in rows:
        v = f["verdict"]
        sev = f" · S{f['severity']}" if f["severity"] else ""
        out.append(f'<a id="{short(f["id"]).lower()}"></a>')
        out.append(f"### {short(f['id'])} · `{f['path']}:{f['line'] or f['original_line'] or '?'}` · round {f['round']}{sev}{flags(f)}")
        out += ["", f"**Verdict:** {verdict_line(v, same_pr=True)}", ""]
        out += [f"**{f['reviewer']} wrote:** {clip(f['body'], FINDING_BODY_CHARS)}", ""]
        out += [f"**Evidence:** {v['evidence']}", ""]
        if v["guidance_note"]:
            out += [f"**Guidance:** {v['guidance_note']}", ""]
    return "\n".join(out) + "\n"


def render_index(j: Joined, docs: dict[str, Path], out_dir: Path) -> str:
    rows = j.rows
    by_pr: dict[str, list[dict]] = defaultdict(list)
    for r in rows:
        by_pr[f"{r['repo']}#{r['number']}"].append(r)

    def link(key: str) -> str:
        return f"[{key}]({docs[key].relative_to(out_dir)})"

    def finding_link(fid: str) -> str:
        key = fid.rsplit("/", 1)[0]
        return f"[{fid}]({docs[key].relative_to(out_dir)}#{short(fid).lower()})"

    out = ["# Review audit, rendered", ""]
    out.append(f"{len(j.pr_verdicts)} PRs and {len(rows)} findings judged, from {len(set(v['batch'] for v in j.pr_verdicts.values()))} verdict files. Each PR links to its own document.")
    out += ["", "## Wrong and uncertain calls", ""]
    out.append("Findings where the agent's response was not the right one. The `no_response` rows are PRs merged before the reviewer posted.")
    out += ["", "| finding | what happened | should have | evidence |", "|---|---|---|---|"]
    for r in rows:
        v = r["verdict"]
        if v["response_correct"] != "yes":
            out.append(f"| {finding_link(r['id'])} | {RESPONSE[v['response']]}, {CORRECT[v['response_correct']]} | {RESPONSE[v['should_have']]} | {cell(v['evidence'], 240)} |")

    caused = [r for r in rows if r["verdict"]["caused_by"]]
    out += ["", "## Findings caused by an earlier fix", ""]
    out.append(f"{len(caused)} of {len(rows)} findings exist because of a fix to an earlier finding.")
    out += ["", "| kind | n |", "|---|---|"]
    for kind, n in Counter(r["verdict"]["cause_kind"] for r in caused).most_common():
        out.append(f"| {CAUSE[kind]} | {n} |")
    out += ["", "| finding | caused by | kind | evidence |", "|---|---|---|---|"]
    for r in caused:
        v = r["verdict"]
        out.append(f"| {finding_link(r['id'])} | {finding_link(v['caused_by'])} | {CAUSE[v['cause_kind']]} | {cell(v['evidence'], 240)} |")

    out += ["", "## Guidance notes, by the kind of defect they would have prevented", ""]
    out.append("Every non-empty per-finding guidance note, grouped by the finding's cause kind. Notes on findings not caused by an earlier fix are under *original defect*.")
    grouped: dict[str, list[dict]] = defaultdict(list)
    for r in rows:
        if r["verdict"]["guidance_note"]:
            grouped[r["verdict"]["cause_kind"] or "original"].append(r)
    for kind in sorted(grouped, key=lambda k: -len(grouped[k])):
        out += ["", f"### {CAUSE.get(kind, 'original defect')} ({len(grouped[kind])})", ""]
        out += [f"- {r['verdict']['guidance_note']} ({finding_link(r['id'])})" for r in grouped[kind]]

    out += ["", "## Process observations, by PR", ""]
    for key, pv in sorted(j.pr_verdicts.items(), key=lambda kv: (kv[1]["batch"], kv[0])):
        if pv["guidance_observations"]:
            out += [f"**{link(key)}**", ""] + [f"- {o}" for o in pv["guidance_observations"]] + [""]

    out += ["## PRs", "", "| PR | title | rounds | avoidable | findings | fix-caused | wrong calls |", "|---|---|---|---|---|---|---|"]
    for key, pv in sorted(j.pr_verdicts.items(), key=lambda kv: (kv[0].split("#")[0], int(kv[0].split("#")[1]))):
        fs = by_pr[key]
        out.append(
            f"| {link(key)} | {cell(j.prs[key]['title'], 120)} | {pv['rounds']} | {pv['avoidable_rounds']} | {len(fs)} | "
            f"{sum(1 for r in fs if r['verdict']['caused_by'])} | {sum(1 for r in fs if r['verdict']['response_correct'] != 'yes')} |"
        )
    return "\n".join(out) + "\n"


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--derived", type=Path, required=True)
    ap.add_argument("--verdicts", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args(argv)

    j = join(args.derived, args.verdicts)
    by_pr: dict[str, list[dict]] = defaultdict(list)
    for r in j.rows:
        by_pr[f"{r['repo']}#{r['number']}"].append(r)
    unjudged = {k for k in j.pr_verdicts if k not in by_pr}
    if unjudged:  # [LAW:no-silent-failure] a PR verdict with no finding verdicts is a broken batch
        raise SystemExit(f"PR verdicts without any finding verdicts: {sorted(unjudged)}")

    docs: dict[str, Path] = {}
    for key, pv in j.pr_verdicts.items():
        repo, number = key.split("#")
        path = args.out / repo / f"{number}.md"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(render_pr(key, j.prs[key], pv, by_pr[key]))
        docs[key] = path
    (args.out / "index.md").write_text(render_index(j, docs, args.out))
    print(f"{len(docs)} PR documents and index.md -> {args.out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
