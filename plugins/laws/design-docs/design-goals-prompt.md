# Design goals: the `prompt` skill

This skill governs any text another LLM will read: a one-turn instruction to a
subagent, a message that opens a long run, a prompt written into a file or code, and
standing guidance like CLAUDE.md files, system prompts, skill bodies, and hook text.
The one thing it is for: get the writer to measure the hold before writing, because
the hold picks the craft, and the known failure is reading the hold off something
else - the text's length, its filename, or what it is called.

## The central goal: measure the hold, then match the craft to it

The skill's frame is that every text enters the reader's context at distance zero.
Nothing sits nearer the decision than anything else; the system prompt and the newest
message arrive the same way. So position tells the writer nothing, and the skill
retires "distance" as a working term after the one sentence where it means position.
What varies is the hold: how many turns after entry the text must still be steering
the reader. A one-turn instruction has a hold of one. A short message that opens a
run has a hold of the whole run. Standing guidance has a hold of the session it
enters.

The hold is bounded on both sides, and the skill states both bounds because each
kills a misreading. Above, by the session: nothing needs to be built to last longer
than one session's turns, and guidance that enters every session gets a fresh hold
each time. Below, by re-injection: text that re-enters every turn has a one-turn hold
whatever file it lives in, so a hook body is terse for the same reason a subagent
instruction is.

The craft then follows from the hold. A one-turn hold is graded as a specification:
terse, complete, each thing once. A whole-session hold is graded on behavior induced
deep in the session, against a reader whose window is full of other material feeding
its own defaults; that hold buys redundancy, imagery, and rehearsed temptations.
These are different optimization targets, not points on a spectrum, and text tuned
for the first while deployed for the second measures better and performs worse.

## The hold is spent per line

The design choice that keeps long-hold text from bloating: the hold is measured per
line, not per document. The reader's own loop re-presents the thing it is doing at
every step, so the destination is rehearsed for free and decays slowly. Nothing
re-presents the lines around it: boundaries, the stop condition, constraints that only
bite late, decisions settled up front. Those decay fast, and those are where the
hold's treatment goes. Everything else in the text stays terse. A three-line message
can hold for a session by hardening its one boundary line, not by becoming a page.

The skill states the misreading this defeats in the writer's own voice: "this is a
short message - say it once and trust the reader." That reads the hold off the
length. Length of text and length of hold are unrelated quantities, and the reader at
turn sixty does not have the line.

## What each hold buys

The skill gives three rungs, and the rung is chosen per line:

- A hold of one turn: the deliverable stated exactly, every requirement present
  because the reader starts from zero, one checkable acceptance criterion,
  instructions and context and data kept separate. The one long-hold device kept
  here is the negative example - "do NOT produce output like X" is enforceable in a
  way "be thorough" is not. Importing the others is an anti-rule: at a one-turn hold
  they read as emphasis and distort weighting for a reader already attending.
- A hold of a run: the body stays on the rung above; the decaying lines get cheap
  devices that buy survival without volume - a stop condition that can be re-checked
  mechanically, boundaries phrased as exclusions, one sentence naming the late
  temptation, placement where a re-read lands. Nothing more, so the text grows by the
  lines it needed and no further.
- A hold of the whole session against situations the writer cannot see: the six
  devices in full - restate each principle in many shapes, attach a reusable concrete
  image to each rule, script the moment of temptation with the rationalization
  quoted, name and disarm the proverbs that will be cited against the guidance, show
  wrongness with WRONG/RIGHT pairs, and write in a stakes register rather than a
  neutral one. The stated reasoning for each is retrieval under interference:
  whatever fragment of the document is active at the moment of generation is all of
  it that exists, so amplitude and repetition are how a principle stays on duty deep
  in a session.

## The second axis: a target you can see, or one you cannot

Hold decides how hard a line must work to survive. One independent axis decides what
form the survivor takes: whether the writer can see the situation it will fire in. A
seen situation can be specified, and its failure is ambiguity - the reader didn't
understand. An unseen distribution needs a disposition that generalizes, carried by
transferable images, and its failure is defection - the reader understands and the
local gradient wins anyway - which is why guidance needs temptation scripts and
disarmed proverbs and a one-turn instruction does not. The two axes usually move
together, which is why standing guidance sits at the top rung, but the skill keeps
them separate so a long run against a seen situation gets hardened specifics rather
than a disposition, and a per-turn hook against an unseen distribution gets a terse
disposition rather than the full treatment.

## The discipline on the devices: reveal, don't fog

Metaphor is why the top rung's devices work: it is the core mechanism of knowledge
transfer - a revealing image binds a principle whole and carries it into the later
moment where it must fire. That power is why it needs governing. The test is reveal
vs. fog. An image that reveals makes the idea graspable and beats plain language; the
same image dragged past its work, or several images stacked on one point, is fog, and
fog obscures more than it reveals. Fog spreads: once a document tolerates it, more
follows.

Over all the devices sits one disposition: keep the language green. Green is lean and
agile, still growing; ripe is a fat, sagging mass of language grown past its use - that
sag is the fog. If you're green you're growing; if you're ripe you're rotten. The fix
is never less metaphor, which is the fabric that binds - it is less slack. Be lean, but
never cut richness that is ready to bloom.

The skill also tells the writer to avoid reflexive absolutes - never, always, every,
only - and to write language shaped to the truth, because guidance addresses situations
nobody has seen yet and an absolute leaves the reader no room to judge them. The
absolute is kept for the genuine invariant, where the missing give is the point.

And it tells the writer that a change is made against the whole document, not in a
corner: a passage that merely repeats or contradicts one already there is a bolt-on, so
the writer weaves the change in - sharpening the existing passage, or settling the
contradiction - rather than appending a second. A coherence check, not the distillation
the war story forbids.

This does not reverse the anti-distillation stance below. The enemy was never
repetition of a true thing; it is fog. Cut obscuring language, never a revealing image
or a restatement that fires where the others do not.

## Design choices in the skill itself

Two structural choices, both stated:

- The skill body (SKILL.md) does not contain the craft; it points at
  `references/craft.md` and says to read it before writing. The body stays short
  because it is what the router injects, and the craft is long top-rung material
  that only the session actually writing in this medium needs. The session that
  writes reads it directly; what keeps an incompatible standard from stacking on
  top of it is the runtime gate, not a hand-off.

- `craft.md` is written in the style its own hold demands - a whole session, against
  writers it has never seen - image-anchored and repetitive where repetition fires,
  but spare, not foggy: every image earns its place by revealing, and none is
  extended past its work. The skill calls itself both instruction and specimen, so
  it must model reveal-not-fog, not merely assert it.

- The hold is the organizing spine of the craft, not a section of it. An earlier
  version carried the point as one axis among five, inside a section answering an
  objection, after a hundred lines written in a kind-based frame - and readers
  missed it, filing short texts as "say it once" by their length. The current
  version derives every device from the hold so there is no frame left to fall back
  to.

## What it deliberately avoids, and why

- Distilling or deduplicating guidance prose. The skill's stated origin is a
  rewrite that deduplicated and taxonomized a working guidance document, measured
  better as a spec, and drove worse behavior because it stripped the repetition and
  images that made the original fire. So the skill forbids cutting a passage merely
  because it repeats a true thing; cuts are for content that is wrong, points the
  wrong way, or is fog - language that obscures more than it reveals.

- Importing top-rung devices into one-turn lines. Redundancy, imagery, and stakes
  framing on a line with a one-turn hold read as emphasis and distort the weighting
  for a reader who is already paying attention. The skill states this as an
  anti-rule for the bottom rung.

- Reading the hold off the length, the filename, or the label. Stated as the failure
  the skill exists to prevent, rehearsed in the writer's own voice from both sides:
  "it's short, say it once" and "it's in the config, give it the full treatment."

- Letting a document's subject supply its style. The stated lesson from the origin
  story is that the subject matter of a guidance document is never its style
  authority - code's "one source of truth" aesthetic is correct for code and
  destructive when applied to the guidance document about code.

- Confusing structure with compression. The skill keeps the distillation's genuine
  wins - canonical tokens, a citation protocol, explicit parentage, a closing recap
  - and frames them as skeleton that aids navigation. The line it holds: structure
  is additive and safe, compression is subtractive and destroys the payload.
