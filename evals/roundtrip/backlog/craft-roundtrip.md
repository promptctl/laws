# Planning a backlog

This guidance is for deciding which epics and tickets go into a project's backlog and
writing them down. It covers seeding an empty backlog from a founding document and
extending a backlog after a layer of work has landed. It does not cover how the
planned units get built in code.

Four ideas carry the whole document. Each has a token so you can name it while you work:

- `known-end` - plan only what you can bound from what is known today.
- `second-consumer` - a foundational unit is shaped for the project, not for its first use.
- `watched-checkpoint` - an epic is done when a person has watched it work.
- `cold-reader` - every epic and ticket makes sense to someone who was not at planning.

Some words, used exactly:

- **Foundational unit**: a unit in the project's first layer, which later work across
  the project's full scope will use.
- **Checkpoint**: something a person can verify that exercises what an epic built.
- **In-application checkpoint**: a checkpoint that runs the functionality directly in
  the application, the way it will actually be used.
- **Demo**: something built for a person to look at when the application cannot yet
  show the work.

---

## `known-end`: plan only what is known

Think of the backlog as a map drawn only as far as the ground has been walked. Past
that edge the land is real, but anything you draw there is a guess wearing the ink of
a survey, and the next person builds on it as if it were surveyed.

**The test.** Do not add a ticket unless you can state where its work ends, and why,
with confidence from what is known today. Not from what will probably be true after
the next layer lands. Not from what the founding document hopes for. If you cannot say
where the work ends and why, from today's knowledge, the ticket does not go in.

**The moment this breaks.** You will have a founding document open that lays out
several stages - stage one, stage two, stage three, each with a paragraph of intent.
You will have written the first stage's epics, and the backlog will look short. The
thought will come: *"This looks thin. The document already describes stages two and
three - I'll plan those too, so the backlog reflects the whole project."* That is the
moment. The thinness is not a defect; it is the map ending where the walking ended.
The stage-two tickets you would write are drawn past the edge, and they will be built
as though someone had surveyed that ground. Stop at what passes the test. The later
stages get planned when they become known - see "after a layer lands," below.

**Words that give the guess away.** A ticket statement that needs an "if" about a
result that does not exist yet, or a "probably" about a shape nobody has seen, fails
the test. Do not write that ticket.

- FAILS: "Add caching to the query layer if profiling shows lookups are the bottleneck."
  (The profiling result does not exist yet.)
- FAILS: "Build the plugin registry; plugins will probably need a lifecycle hook."
  (Nobody has seen a plugin's shape.)
- PASSES: "Parse the config file format defined in docs/config.md into the Config
  type; work ends when every field in that document round-trips." (Its end and the
  reason for it are both known now.)

**Finding out is not building.** Do not plan work whose purpose is finding out whether
something is true as a build ticket. "Determine whether the vendor API supports
batching" is a question; written as a build ticket it pretends to have a known end it
does not have.

**"The foundation" is not a plan.** Do not plan "the foundation" as a category and
stop there. A label like "core infrastructure" or "foundation layer" names a region,
not work. Plan the specific tickets inside it that pass the test.

- WRONG: an epic titled "Foundation" containing one ticket, "Set up the foundation."
- RIGHT: tickets that each state where their work ends and why, from what is known.

**After a layer lands.** When a layer of work lands, the walked ground has grown.
Extend the backlog from what is known then, using the same test. The map gets longer
because the walking got further, not because the hopes got bigger.

---

## `second-consumer`: foundational units

A foundational unit is a brick the whole project will build with. A brick cut to fit
the first wall it goes into is a brick no other wall can use.

Plan each foundational unit so that it depends on no single place it will be used.
Two checks tell you whether you have done that; apply both to every foundational
ticket.

**One purpose, one sentence, no "and."** State each foundational ticket's purpose as
one sentence with no "and." If the sentence needs an "and," split the ticket in two
at the "and."

- NEEDS SPLITTING: "Provide a date-range type and render date ranges in the report header."
- SPLIT: "Provide a date-range type." / "Render date ranges in the report header."

**Name the second consumer.** In each foundational ticket, name a second consumer of
the unit, drawn from the project's own goals - a place other than the first use where
the project's stated aims will need this unit. If no second consumer can be named, you
have two choices: treat the unit as not foundational, or reshape it so it is not
fitted to its first use.

- WEAK: "Used by: the report header." (one consumer; the brick is cut to one wall)
- STRONG: "Used by: the report header; also the export filters described in the
  project's goals."

---

## `watched-checkpoint`: every epic proves itself

An epic is not finished when its paperwork is. Closed tickets and passing tests are
the paperwork. The proof is a person watching the thing work.

**Every epic gets one.** Give every epic a checkpoint. Do not treat an epic as done
when its tickets are closed, and do not treat it as done when its tests pass. Treat it
as done only when a person has watched the checkpoint exercise the work.

**What kind.** Prefer an in-application checkpoint, and use one by default: run the
functionality directly in the application, the way it will actually be used. Prefer a
visual checkpoint. These are preferences, not bans; the one stated exception to the
in-application default is the demo, in the next section.

**How often.** Space checkpoints close enough together that the project is never far
from one.

**More than the happy path.** Make every checkpoint - a demo included - cover more
than the happy path. It exercises:

- edge cases,
- the empty input,
- the value at the boundary,
- the case the founding document says will probably break.

- THIN: "Checkpoint: open the import screen, load sample.csv, see the rows appear."
- COVERS IT: "Checkpoint: in the application, import sample.csv and watch the rows
  appear; import an empty file; import a file at the row limit; import the
  mixed-encoding file the founding document flags as likely to break."

---

## Demos: the exception, labeled as one

A demo is scaffolding put up so a person can see work the building cannot show yet.

**Not by default.** No epic has a demo by default. Do not give an epic a demo unless
both are true: the application cannot yet show the epic's work, and the distance to
the next in-application checkpoint has grown too long. One without the other is not
enough.

**Same quality.** Build a demo to the same quality as everything else in the project.

**Labeled.** Label a demo as a demo in its ticket and in its code.

**Learned from, not built on.** State explicitly in a demo's ticket that the project
learns from the demo's mistakes rather than building on it.

**"Quick."** Treat the word "quick" in a demo ticket as a sign to revise the ticket.

- REVISE: "Quick demo page to show the layout engine."
- CLOSER: "Demo (labeled as a demo in this ticket and in code): a page rendering the
  layout engine's output, built to project quality, covering empty content and the
  overflow case. The project learns from this demo's mistakes rather than building
  on it."

---

## `cold-reader`: text that stands on its own

Picture the reader: someone who cloned the repository this morning. They were not in
the planning conversation.
Every epic and ticket is written for that person.

**No references to the planning conversation.** Do not refer, in any epic or ticket,
to anything that exists only in the planning conversation - an earlier discussion, a
plan, an agreement.

- WRONG: "As discussed, use the approach we agreed on."
- WRONG: "Per the plan above, this comes after the parser."
- RIGHT: the approach itself, stated in the ticket.

**Each epic says why it exists.** State in each epic's own text why the epic exists,
in terms of the project's goals.

**Each ticket carries what is needed to start.** Include in each ticket what a person
with no knowledge of the planning session needs to start the work.

**Point to the founding document; do not copy it.** Where the founding document
already says something, point to it by path. Do not restate it. And do not assume
the reader has read it - the pointer is there so they know where to look.

- WRONG: three paragraphs pasted from the founding document's section on data retention.
- WRONG: "See the retention rules." (Which document? The reader may never have opened it.)
- RIGHT: "Retention rules: docs/founding.md, section 'Data retention'."

**The read-through before writing.** Before writing anything to the tracker, read the
planned epics and tickets as someone who cloned the repository this morning. Rewrite
anything that only makes sense to someone who was present at planning, until it makes
sense to that person.

---

## Recap

- `known-end`: no ticket unless you can state where its work ends and why from what is
  known today. An "if" about a result not yet in, or a "probably" about an unseen
  shape, fails. Finding out is not a build ticket. "The foundation" as a category is
  not a plan. After a layer lands, extend from what is known then. When the backlog
  looks thin because the founding document has more stages, that is the map ending
  where the walking ended - plan only what passes the test.
- `second-consumer`: foundational units depend on no single place of use. Purpose in
  one sentence with no "and" - split at the "and." Name a second consumer from the
  project's goals, or treat the unit as not foundational, or reshape it.
- `watched-checkpoint`: every epic has a checkpoint; done means a person watched it
  exercise the work, not closed tickets or green tests. Prefer visual; prefer
  in-application by default; keep checkpoints close together; cover edge cases, empty
  input, the boundary value, and the case the founding document expects to break.
- Demos: none by default; only when the application cannot yet show the work and the
  next in-application checkpoint is too far. Same quality, labeled in ticket and code,
  the ticket says the project learns from its mistakes rather than building on it,
  and "quick" in the ticket means revise.
- `cold-reader`: no references to the planning conversation; each epic states why it
  exists in terms of the goals; each ticket carries what is needed to start; point to
  the founding document by path without restating it or assuming it was read; read
  everything as this morning's cloner before writing to the tracker.
