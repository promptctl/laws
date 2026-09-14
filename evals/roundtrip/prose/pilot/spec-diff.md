# Prose round trip: spec-level diff

`spec.md` was distilled from the current prose craft. `spec-roundtrip.md` was
distilled from `craft-roundtrip.md`, which a blind session compiled from `spec.md`.
Neither distilling session saw the other's spec. The mapping below was made by
reading both specs and grepping the original craft for every addition.

| Measure | Result |
|---|---|
| Requirements | 26 before, 29 after |
| Words | 753 before, 1009 after |
| Rules lost | none |
| Whole rules added | 2 |
| Permissions added | 2 |
| Rules split | 1 |
| Rules moved | 1 |
| Strength changes | 1 |
| Rules given an extra clause | 11 |

**Nothing was lost.** Every one of the 26 original requirements has a counterpart
that says the same thing. The coined term "load-bearing" came back renamed "needed
fact" with the same definition.

**Every addition is new material.** None of the added clauses appears in the original
craft. The recompiling session was told it decides the rehearsed temptations, so it
wrote some, and the second distill correctly extracted them as rules. The spec grows
on each trip for this reason, and it will keep growing unless the compile step may
only harden failures the spec records.

## Additions

- **Whole rule, new 1.** Do not copy the guidance's headings, repetition or examples
  into the output.
- **Whole rule, new 22.** Signs to revise are not bans. Fix what produced the sign,
  not only the sign.
- **Permission, new 8.** You may reshape a sentence or leave it as it is rather than
  drop a needed fact.
- **Permission, new 15.** The passive voice is allowed when the actor is unknown or
  beside the point, or when object-first reads better.
- **Clauses added.** Write the goals down, even as two lines, and do not skip it
  because you know the reader (2). "A broad category such as developers" (4). "Leaving
  them out feels like respecting the reader's intelligence" (7). "Including on the
  ground that the reader can find the fact elsewhere" (8). "Read the code, run the
  thing, or ask" (10). "Not when the text feels short enough" (11). "Put the
  reasoning after it" (14). "Count its ideas" (17). "Do not break connected reasoning
  into a list" (18). "Check whether a few plain paragraphs would serve" (23). "Not the
  one that follows the most requirements" and "rework any line you would rather they
  skimmed" (28, 29).

## Structural changes

- **Split.** Original 1 became new 2 and new 3.
- **Moved.** Deleting warm-up openers moved from original 11, at drafting, to new 21,
  after drafting.
- **Strength.** Original 14 let the ear and variety overrule ending on the new thing.
  New 16 says do not apply it where it flattens the prose, which is harder. The
  original craft calls it a tendency to listen for, so the original spec had it right.
