#!/usr/bin/env bash
# A sample judge scorer. It is handed ONLY the artifact dir and the reference path - never the
# skill under test, the laws, or any skill-derived rubric - so it structurally cannot grade output
# against the treatment. Judge-pass iff the artifact's output.txt contains each reference line as a
# SUBSTRING (grep -F, not an exact-line match). Exit 0 = judge-pass, 1 = judge-fail, 2 = could-not-run.
# This substring looseness (e.g. "UNAPPROVED" would contain "APPROVED") is a real blind spot - and
# that is the point: this is a deliberately fallible judge (on held case-4 it passes an artifact a
# human labelled fail), which is exactly the kind of miss the human-agreement bar exists to catch.
set -euo pipefail
artifact="${1:?artifact dir}"; reference="${2:?reference path}"

[ -f "$artifact/output.txt" ] || exit 2
[ -f "$reference" ] || exit 2

while IFS= read -r line; do
  [ -z "$line" ] && continue
  grep -qF -- "$line" "$artifact/output.txt" || exit 1
done < "$reference"
exit 0
