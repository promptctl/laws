#!/usr/bin/env bash
# A sample judge scorer. It is handed ONLY the artifact dir and the reference path - never the
# skill under test, the laws, or any skill-derived rubric - so it structurally cannot grade output
# against the treatment. Judge-pass iff the artifact's output.txt contains each reference line as a
# SUBSTRING (grep -F, not an exact-line match). Exit 0 = judge-pass, 1 = judge-fail, 2 = could-not-run.
# This judge is deliberately fallible - two INDEPENDENT blind spots illustrate why a judge must be
# validated against humans before it is trusted:
#   - substring looseness: "UNAPPROVED" would contain "APPROVED" and wrongly pass (a genuine hole,
#     not exercised by the held set);
#   - no semantic judgement: on held case-4 the output IS exactly "APPROVED", so the judge passes it,
#     yet a human labelled it fail (superficially right, actually bad). That disagreement - which has
#     nothing to do with substring matching - is what drops agreement to 4/5.
set -euo pipefail
artifact="${1:?artifact dir}"; reference="${2:?reference path}"

[ -f "$artifact/output.txt" ] || exit 2
[ -f "$reference" ] || exit 2

while IFS= read -r line; do
  [ -z "$line" ] && continue
  grep -qF -- "$line" "$artifact/output.txt" || exit 1
done < "$reference"
exit 0
