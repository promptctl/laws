# Design goals: the spec skill

The spec skill is for writing and maintaining the requirements documents for a feature
that is being built: a PRD, an FSD, a technical Spec, and the traceability matrix that
ties them together. It governs what each document carries and how the four stay in
agreement across iterations. It does not govern how the thing is built, and it does not
govern how work is broken into tickets; those are the code skill's and the backlog
skill's jobs.

## What it is for

Most requirements processes spend their effort proving that a need exists before
anything is built. This one takes a real user's request as sufficient proof and spends
the effort on building and trying instead. The documents exist to get to a build and to
record what happened when the build met a real task — not to be complete before the
work starts.

The skill serves the first pass at a feature and every iteration after it. Both are the
same act: update what is known, cut what nobody asked for, and build the smallest thing
that can be put in front of someone.

## The ideas it carries

**Every requirement names the person who asked for it.** A requirement with no source is
removed. The source establishes that the need exists; it makes no claim about how many
people share it. This is what keeps the documents from filling with work nobody
requested, which is the failure mode a requirements process is most prone to and least
able to see.

**Traceability runs both directions, and the reverse direction is the useful one.**
Every functional requirement traces back to a user request, every component traces back
to a functional requirement — and anything that does not trace back is cut. The matrix's
coverage checks are written as findings and actions precisely so the reverse direction
gets run, because it is the one that asks the uncomfortable question: why does this code
exist?

**Rigor is scaled to validation status and to reversibility.** Prototype quality is
acceptable for a draft requirement and never acceptable for stored data, security, or an
interface another team depends on. Heavy test coverage on a draft requirement buys
nothing and slows the change that is expected to follow.

**Observed behavior outranks stated opinion.** The validation log records what a person
or an agent did on a real task — where they hesitated, what they worked around, what
they ignored. Agent testers are given tasks and watched, not asked for their opinions.

**The documents stop at the build.** The stopping point is the smallest set of filled
sections that lets the next iteration be built. What is still unknown stays visible as a
dash and an open issue rather than being resolved on paper.

## Deliberately absent

The five templates are carried as the owner supplied them. The skill points at them and
says how they fit together; it does not paraphrase their contents, and a rule that
belongs in a template is not restated in the skill body. A second copy would be a second
thing to go stale, and the copy is what a reader would believe.

There is no guidance on how long a document should be beyond the bounds the templates
set themselves. Every attempt at a length rule here reduces to either padding or
arbitrary truncation, and the templates' own rules — one page for the PRD's first eight
sections, the validation log as the only section that grows — already say the useful
part.

## Relationship to the other media

The application-spec skill specifies an application that already exists, from the
outside, so an independent team can rebuild it. This skill specifies a feature that does
not exist yet, from the request forward. They point in opposite directions and their
rules do not transfer: a clean-room rule about excluding internals is false here, where
the Spec's whole job is the internals.

The backlog and ticket skills govern how work is planned and written up once these
documents say what the work is. A requirement is not a ticket, and a rule about one must
not be copied into the other.
