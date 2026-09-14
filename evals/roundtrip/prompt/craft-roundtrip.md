# Writing text another LLM will read

Scope: any text another LLM will read. That includes an instruction handed to a
subagent, the message that opens a run, a prompt written into a file or into code, a
system prompt, a CLAUDE.md, a skill body, and a hook.

This document has a long hold. You will carry it through a whole session, and it has
to still be steering you deep into someone else's file, when your instincts say
"tighten this." Where it restates itself, leans on pictures, or presses harder than
reference material usually does, that is the method at work. It is not padding
waiting for your red pen.

---

## First, before anything else: measure the hold

One quantity governs every other decision in this document. Read it first, because
whatever frame you pick up first is the one you will keep.

**The hold** of a line is the number of the reader's turns, counted from the moment
the text enters its context, during which that line must still be directing what the
reader does.

Picture the reader's context as a desk. When your text arrives it lands on top, and
the reader is looking straight at it. Every turn after that lays another sheet over
it: a tool result, a file, a diff, the reader's own output. A line with a hold of one
does its work while it is still on top of the pile. A line with a hold of forty has
to steer the reader from under forty sheets. The rest of this document is about how
deep in the pile each line must still work.

So before you write, ask of each line, in turns the reader will take:

- How many turns will have piled up before this line has to act?
- Does the reader's own work keep pulling this line back to the top, or must it act
  from under the pile on its own?

Do not infer the hold from anything else: not from the text's kind, not its name, not
the file it lives in, not its length, not its position in the context. Those are the
things that are easy to see, and none of them is the pile.

**The moment this goes wrong.** You are writing a four-line message that launches a
subagent on a long migration. One line says "do not change the public API." You
think: *"This is a short message, not a system prompt. I'll state the boundary once
and trust the reader."* Stop. That thought measured the message's length, not the
line's hold. The run will lay dozens of sheets over that line before the turn where
changing the public API is the easiest way forward. Measure how deep in the pile that
line must act, and build that line for that depth. The message stays four lines; the
one line gets built to last.

- BAD (hold read off the filename): "It's a skill file, so every line gets the full
  long-hold treatment."
- BAD (hold read off the length): "It's three sentences, so each thing gets said once."
- GOOD: "The boundary sentence must act at roughly turn thirty and nothing in the work
  will re-present it; the sentence naming the target file is re-presented every turn
  by the editing itself."

### The pile has a floor and a ceiling

The ceiling is the session. Measure a hold within one session. Guidance that enters
every session does not accumulate a hold across sessions: treat each entry as its own
hold, measured inside the session it entered.

The floor is re-injection. Text that is injected into the context again every turn is
put back on top of the pile every turn, so treat it as a one-turn hold, whatever file
it lives in. Check for re-injection before you give any text the whole-session
treatment described below.

**The moment this goes wrong.** You are editing a hook body that lives in a settings
directory beside the project's standing guidance. You think: *"This lives in the
config. It's standing guidance, so it gets the whole-session devices."* Stop. Where a
file lives says nothing about its hold. Find out whether that text is re-injected
every turn. If it is, it is read from the top of the pile each time, and it gets
written as a one-turn text.

---

## Which lines sink

Inside one text, the lines do not all sink at the same rate.

The reader's ongoing work keeps pulling some lines back to the top of the pile. The
thing being built is in view every turn, because every step of building it shows it
again. Other lines never come back up. These are the **unrefreshed lines**:

- **Boundaries**: what is excluded.
- **The stop condition**: what finished means.
- **Constraints that matter only late in the work**: the ones that cost nothing at
  turn two and bite at turn thirty.
- **Settled decisions**: things decided at the start that the reader may later want
  to reopen.

When you measure the hold, these are the lines whose answer to "does the work pull it
back up?" is no.

---

## Two standards of good, and the hold picks which one grades you

Text can be judged two ways, and they reward opposite things.

Judged as a **specification**, good text is terse and deduplicated, with each
principle stated once. Judged by the **behavior it produces late in a session**, good
text is the one whose principles are still active from deep under the pile.

- Write a text with a one-turn hold as a specification: terse, deduplicated, each
  principle stated once.
- Write a text with a whole-session hold to produce behavior late in the session,
  using the whole-session devices set out further down.

**What is lost, and how quietly.** A long-hold text revised toward the specification
standard reads better on the page and does less at turn forty. Nothing announces the
loss. The document looks improved, the reader still understands every sentence when
it is on top of the pile, and the drift that follows gets blamed on the task or the
model, never on the edit.

**The moment this goes wrong.** You are editing standing guidance and you notice the
same principle in three places. You think: *"A good document says it once. Let me
clean this up into a tight spec."* Stop. That is the specification standard being
applied to a text graded on late behavior. Ask instead, for each of the three places,
what situation it covers. The next section tells you what to do with the answer.

A maxim will be cited at you here: **"Omit needless words."** It is right for a
one-turn text, and right for any specification: a word that does no work there costs
the reader attention and returns nothing. It does not reach a restatement that covers
a situation no other passage covers, because that restatement is not needless. It is
the only thing on duty in that situation.

---

## How much restatement: the keyring

Think of each restatement of a principle as a key on a ring, and each situation the
principle must act in as a door. A key earns its place on the ring by opening a door
no other key on the ring opens.

- **Keep a restatement only if** it applies in a situation no other restatement
  covers.
- **Decide from the text in front of you**, not from a default, whether that text has
  too little restatement or too much. A lean draft whose principle is stated once may
  need more keys; a text crowded with paraphrases that all open the same door has too
  many. Neither direction is the house setting.

### What you may cut

- **Do not cut** content because it repeats a true statement.
- **Do not cut** content because the text feels long.
- **You may cut** content that is wrong, or that points the wrong direction.
- **You may cut** a restatement that covers a situation you can name, which a passage
  you can name already covers.
- **If you cannot name both** (the situation, and the passage already covering it),
  **do not cut.**

**The moment this goes wrong.** You are three screens into a long guidance document
and you think: *"This is bloated. It needs tightening."* Stop. That feeling is not
evidence; it arrives the same way whether the document has too many keys or exactly
enough. Point at a specific restatement, name the situation it covers, and name the
passage that already covers that same situation. If you can name both, cut that one.
If you cannot, the feeling was the whole of your case, and nothing gets cut.

- BAD cut: "Sections 3 and 8 both say to measure the hold, so I deleted section 8."
- GOOD cut: "This paragraph restates the stop-condition rule for the case where the
  reader finishes early. The paragraph right above it already covers exactly that
  case. Removed."

A second maxim will be cited: **"Don't repeat yourself."** In code it is right: one
fact kept in two places drifts, and the copies disagree. A restatement in guidance
covering a separate situation is not a second copy of a stored fact. It is a second
key to a second door.

---

## Where emphasis goes: the highlighter

Every device for a long hold is a stroke of highlighter. Highlight every line on a
page and the page is exactly as readable as if you had highlighted none; the one line
you needed to jump out is now one yellow line among many.

- **Apply long-hold devices only to unrefreshed lines**, and only to the degree each
  line's hold requires.
- **Keep the destination, the context, and the material as terse as a one-turn
  instruction**, so the emphasized lines stand out against them.

**What is lost, and how quietly.** The boundary that had to hold at turn sixty stops
being special the moment every line is highlighted. The document still looks
emphatic. It just no longer tells the reader which line matters when the pile is deep.

**The moment this goes wrong.** You are building a message for a long run and you
think: *"The whole run matters, so I'll harden every line."* Stop. The target, the
context, and the material are pulled back up by the work every turn. Leave them plain.
Put the highlighter on the boundary, the stop condition, the late constraint, and the
settled decision.

### When a loud section drowns a quiet line

Sometimes one section overpowers a quieter line that matters.

1. **First**, check whether the loud section is over-highlighted, and if it is,
   reduce it.
2. **Only if a second check shows** the quiet line is under-built, add devices to the
   quiet line.

**The moment this goes wrong.** You notice a rule about stop conditions is getting lost
beside a long, heavily emphasized section about scope. You think: *"The stop-condition
rule is too weak. Give it more images and a second rehearsal so it can compete."*
Stop. That move raises the quiet line until it matches the loud one, and after enough
edits of that kind the whole page is yellow. Look at the scope section first and ask
whether it is louder than it deserves. Bring it down if so. Build up the quiet line
only if it turns out to be under-built on its own terms.

### Not a flat page either

Do not reduce all emphasis to one level. An unhighlighted page is as useless as a
fully highlighted one. Some guidance warrants emphasis; put it there on purpose.

---

## Negative examples, at every hold `negative-examples`

This rule applies to every hold, the one-turn text included.

- **For each behavior that matters, include at least one concrete negative example**,
  preferably a real one, quoted.
- **Prefer** wrong/right contrast pairs and forbidden-pattern lists over descriptions
  of good output.

A description of good output is a wanted poster that says "looks trustworthy." Every
suspect fits it, including the draft already on the writer's screen. A negative
example is a mugshot: the output either matches it or it does not.

- BAD: "Write clear, specific commit messages."
- GOOD: "Forbidden commit subjects, all real: `fix stuff`, `updates`, `WIP`, `address
  review`. Wrong: `fix bug`. Right: `parser: reject unterminated string literals`."

**The moment this goes wrong.** You are finishing an instruction and you think: *"I'll
just tell it what good looks like: thorough, specific, well-tested."* Stop. That
describes a region the reader's default output already believes it is standing in,
and nothing will change. Find a real example of the wrong output, quote it, and put
it beside the right one.

---

## The one-turn hold: a specification

A text read once, acted on while still on top of the pile, is written as a
specification. Say each thing once.

<one-turn-rules>

- **State the deliverable exactly**: the artifact, its format, and where it goes.
- **Include every requirement, in the original requester's words.** Assume the
  reader has no conversation history, no requester context, and no standing guidance.
- **Give one verifiable acceptance criterion** describing correct output.
- **Include negative examples** as set out in the section above.
- **Explain the reason** for any constraint that would otherwise be surprising.
- **Separate instructions, context, and data** with tags or sections.
- **When the work returns, read the produced artifact**, not the worker's report, and
  validate it against the requirements, not against the worker's self-assessment.
- **Do not use redundancy, imagery, or stakes framing** on a line whose hold is one
  turn.

</one-turn-rules>

- BAD: "Can you look into the flaky checkout test and sort it out? Thanks!"
- GOOD: "Deliverable: a fix to `tests/checkout.spec.ts` committed on this branch.
  Requirement, from the requester: 'the test must pass 50 runs in a row without
  retries.' Acceptance: `for i in $(seq 50); do npm test -- checkout || exit 1; done`
  exits 0. Do not produce: a `retry(3)` wrapper, a longer timeout, or `.skip`. Do not
  touch `src/`; the requester believes the bug is in the test's clock mocking, and a
  source change would hide it."

---

## The run hold: a terse body, a few lines built to last

This is text that enters once, is not re-injected, and must still act at some later
turn of a run.

- **Write the body** by the one-turn rules above.
- **Give the unrefreshed lines only the four treatments below.**
- **Do not add** images, restatement across sections, or register changes, and do not
  make the text longer than those lines require.

<run-treatments>

1. **A stop condition the reader can check mechanically** against its own output and
   get a yes or a no.
2. **Boundaries phrased as exclusions**, not as an area to focus on.
3. **The late temptation, named in one sentence**: the point at which the reader will
   want to cross the line, and the thought it will have then.
4. **Unrefreshed lines placed at the opening or the close** of the text.

</run-treatments>

**What goes wrong without a checkable stop condition.** The reader has no test to run
against its own work, so it does one of two things: it stops once the obvious part is
done, or it keeps making one more improvement after another. Either way, the run ends
somewhere nobody chose.

- BAD stop: "Stop when the migration is done."
- GOOD stop: "Stop when `grep -rn legacyClient src/` prints nothing and `npm test`
  exits 0."
- BAD boundary: "Focus on the parser module."
- GOOD boundary: "Do not edit anything outside `src/parser/`: not the tests, not the
  lexer, not the build config."
- GOOD late temptation: "When a parser test fails for a reason rooted in the lexer,
  you will think a one-line lexer fix is quicker; the lexer is outside the line."

---

## The whole-session hold: all the devices, in use

This is standing guidance: text with a whole-session hold, written against situations
the writer cannot see.

- **Use all of the devices**: `negative-examples` and the five whole-session devices
  below (`redundancy-is-amplitude`, `metaphor-as-retrieval-handle`,
  `rehearse-the-temptation`, `disarm-counterarguments`, `stakes-not-calm`), each
  present in use in the text, not described.
- **Give each rule a statement, an image, and its temptation.**

A document that says "use vivid imagery" without containing any has described a
device, not used one.

---

## The second measurement: can you see the situation?

The hold says how deep in the pile a line must work. Visibility says what form the
line should take.

- **For a situation you can see**, state the exact instruction.
- **For situations you cannot see**, state a disposition that generalizes. Carry it
  with reusable concrete images rather than a list of enumerated instructions, and
  apply `rehearse-the-temptation` and `disarm-counterarguments` to it.

Think of the difference between directions to one address and a sense of direction.
When you know the address, give turn-by-turn directions. When you do not know where
the reader will end up, give it the sense of direction.

**Measure both before writing.** The two measurements come apart:

- A long run against a situation you can see gets the run hold's four treatments,
  with specific instructions.
- A short hold against situations you cannot see gets a disposition, stated once,
  tersely.

---

## Where the reader's frame comes from

### The subject is not the style

Do not take a guidance text's writing style from its subject matter. A guide to
pruning trees is not itself pruned.

If revising guidance starts to resemble refactoring (deduplicating, extracting,
consolidating to one source), **stop.**

**This already happened.** Writers revising a document about code design applied that
document's own principles of subtraction and deduplication to the document's prose.
The principles were right about code. The prose they were applied to was guidance.

**The moment this goes wrong.** You are revising a guidance document whose subject is
clean code. You think: *"This document preaches one source of truth. It should practice
it. Let me consolidate these passages into one."* Stop. That is the subject lending
its style to the document, and a revision that feels like a refactor is the signal to
halt. Go back to the keyring: name the situation each passage covers.

### Injected instructions win against understanding

Write guidance expecting that an instruction injected into the context mid-session
will override the reader's awareness of its own situation.

Picture a loudspeaker announcement cutting into a conversation. The reader keeps
talking about why the announcement does not apply here, and meanwhile its hands do
what the announcement said.

**What this looks like.** Readers follow injected instructions even while they are
discussing why they should not. A reader explaining, correctly, that a long-hold
document must not be compressed will, after a mid-session injection that says "apply
the code-design principles," begin compressing it, and its own correct explanation
does not stop it. Do not write as though the reader's grasp of its situation will
protect a line from that.

### The first frame sets

Place the principle that governs the rest of the text **before** any content that
could establish a contrary frame. A frame is like wet concrete: whatever is poured
first is what sets, and a correct paragraph laid on top later does not reshape it.

**What this looks like.** Readers keep the frame the text taught first and do not act
on a correct paragraph placed after it.

**The moment this goes wrong.** Your document opens by teaching two kinds of text by
their names, and later you realise the hold is the real governing idea. You think:
*"I'll add a section explaining the hold near the end. The correct idea is in the
document now."* Stop. It is in the document and not in the reader: the names were
poured first, and they set. Move the governing principle to the front, ahead of
anything that could frame the text another way.

---

## Absolutes

Do not write an absolute (never, always, every, only, must) unless the statement is
an invariant or a safety constraint that holds every time. Otherwise, write the
frequency that is true.

An absolute is a weld. Weld the joints that must not move; bolt the rest, so the
reader can adjust them when a case arrives that you did not foresee.

- BAD: "Never add a second example." (when a second example is only rarely useful)
- GOOD: "A second example is rarely useful."
- GOOD absolute: "Never print the API key." (a safety constraint that holds every time)

**The moment this goes wrong.** You are writing a rule and "rarely" is the truth. You
think: *"'Rarely' sounds weak. 'Never' will make them take it seriously."* Stop. You
reached for the weld to sound firm, and the rule is now false on the first case that
does not fit. Write "rarely."

---

## The whole-session devices, one by one

### Cite the device where it shapes a sentence

When one of the devices below, or `negative-examples`, shapes a sentence you are
writing, cite it as `[DEVICE:<token>]` **in your reasoning or your chat**, not in the
document itself. Use only these tokens:

| Token | Device |
|---|---|
| `redundancy-is-amplitude` | each core principle stated in several forms |
| `metaphor-as-retrieval-handle` | concrete images, one per point |
| `rehearse-the-temptation` | the moment of violation, written out |
| `disarm-counterarguments` | opposing maxims named and fenced out |
| `negative-examples` | concrete negative examples (see its section above) |
| `stakes-not-calm` | a register that states the loss and its silence |

### `redundancy-is-amplitude`

State each core principle in several forms distributed across the text: a
definition, an image, a consequence, a diagnostic question, a recap. Stay inside the
keyring limit: each form must open a door the others do not.

Do not merge passages that state one principle when they apply in different
situations.

**The moment this goes wrong.** You are tidying a long document and you think:
*"Section 2 and section 7 say the same thing. Merge them."* Stop. Saying the same thing
is not the test. Ask when each one applies. If section 2 is the definition read at the
start and section 7 is the question the reader asks itself mid-edit, they are two keys
to two doors, and merging them locks one door for good.

### `metaphor-as-retrieval-handle`

- **Express each abstract principle as a concrete image**, preferably a sensory one,
  that makes it clearer than the plain statement does.
- **Reuse that image as the text's vocabulary.** This document says "the pile," "the
  keyring," "the highlighter" from start to finish for exactly that reason.
- **When trimming, cut excess words rather than the image.**
- **If you cannot find the image**, treat that as a sign you do not yet understand the
  rule.

- BAD: "Emphasis is relative, so apply it selectively." (true, and nothing to hold on to)
- GOOD: "Highlight every line on the page and nothing is highlighted."

**The moment this goes wrong.** You are polishing standing guidance and you think:
*"The keyring picture is cute, but this is a technical document. Replace it with the
plain statement."* Stop. The image is how the principle reaches a situation the plain
statement never mentioned. Trim the words around it if they sag; keep the image.

A maxim will be cited: **"Technical writing should be literal."** It is right for a
reference table, an API signature, or a one-turn instruction, where the reader is on
the page right now and a figure only slows it down. It does not reach a principle
that must act from deep under the pile in a situation no one listed.

### One image per point

- **Do not extend an image past its point.**
- **Do not stack several images on one point.**
- **Do not wrap figurative language around an idea until the idea is hidden.**
- **When you find any of these, cut the passage.**

- BAD: "An absolute is a weld, a padlock on the gate, a line carved in granite that
  the tide cannot wash away." (four images on one point; none of them lands)
- GOOD: "An absolute is a weld. Weld the joints that must not move."

**The moment this goes wrong.** You have one image that works and you think: *"A second
picture from another angle will deepen it."* Stop. The second image competes with the
first for the same point, and the reader keeps neither clearly. One image, then move
on.

### `rehearse-the-temptation`

For each rule, write the moment of violation:

1. the situation,
2. the reader's rationalization, quoted, in the first person,
3. the refusal,
4. the redirect.

If you cannot write the rationalization, treat that as a sign the violation is not yet
identified, and identify it before you ship.

Every "The moment this goes wrong" passage in this document has that shape.

**The moment this goes wrong.** You reach a rule that seems obvious and you think:
*"This one is clear enough. Nobody needs to imagine breaking it."* Stop. A rule you
cannot picture being broken is a rule whose violation you have not found yet. Find
the situation where it happens and the sentence the reader will think then, and write
them down.

### `disarm-counterarguments`

For each well-known maxim that could be cited against the guidance:

1. name it,
2. state where it is correct,
3. show why the present case is outside that domain.

Do not dismiss the maxim wholesale.

This document does it for "Omit needless words," "Don't repeat yourself," and
"Technical writing should be literal."

- BAD: "Ignore 'Don't repeat yourself' here."
- GOOD: "In code, 'Don't repeat yourself' is right: two copies of one fact drift. A
  restatement covering a separate situation is not a copy of a fact."

**The moment this goes wrong.** You think: *"If I mention 'omit needless words,' I'm
just reminding the reader of it. Better to leave it out."* Stop. The reader already
knows the maxim. Leaving it out does not remove it; it leaves it unanswered for the
moment the reader reaches for it. Name it, grant its ground, and show where that
ground ends.

### `stakes-not-calm`

For guidance that matters, write in a register that states **what is lost** when the
rule breaks and **that the loss is silent**, not in a calm reference register.

- BAD: "Note: restatement can be useful in long documents."
- GOOD: "Merge those two passages and one situation loses its only key. Nothing will
  report it; the reader will just stop doing the right thing there, and nobody will
  trace it back to the edit."

**The moment this goes wrong.** You re-read your guidance and think: *"This tone is a
bit much. A neutral register would be more professional."* Stop. Neutralizing the tone
takes out the part that tells the reader this matters. Say what breaks and that it
breaks without a sound.

---

## Structure

**You may use** any of these:

- one short, stable token per concept;
- a protocol that requires citing the token wherever the concept is applied;
- explicit links from each corollary to the principle it is an instance of;
- grouped structure;
- a closing recap that repeats the tokens verbatim.

**Do not let structure replace** the whole-session devices (`redundancy-is-amplitude`,
`metaphor-as-retrieval-handle`, `rehearse-the-temptation`, `disarm-counterarguments`,
`stakes-not-calm`), and do not let it shorten the text. Scaffolding helps you find your
way around a building; it is not the wall.

---

## Revising: mend the seam, don't sew on a patch

Before adding a passage, compare it with the whole text:

- **If it applies in a situation nothing else covers**, add it.
- **If it repeats an existing passage**, sharpen that passage instead.
- **If it contradicts an existing passage**, decide which one is wrong rather than
  keeping both.

**What this looks like when skipped.** A writer appends a passage, and readers keep the
frame the earlier text set. The new passage is on the page and absent from the
behavior.

**The moment this goes wrong.** You have a correction to make and the document is long.
You think: *"I'll add a short note at the end; it's quicker than working it into the
middle."* Stop. A patch on top leaves the old seam as it was, and the reader follows
the old seam. Find the passage the note touches. Add, sharpen, or settle the
contradiction there.

---

## Before shipping: the checks, in this order

Run these against the text, in this order.

1. **The hold, per line.** For each line that must act later: how many turns will have
   piled up, and does the work pull it back to the top? Was any hold read off the
   text's kind, name, file, length, or position? Were long-hold devices applied only
   to unrefreshed lines, to the degree their hold requires, with the destination,
   context, and material kept terse?
2. **The whole-session devices.** For a whole-session hold: are `negative-examples`,
   `redundancy-is-amplitude`, `metaphor-as-retrieval-handle`,
   `rehearse-the-temptation`, `disarm-counterarguments`, and `stakes-not-calm` each
   present in use, not described? Does each rule have a statement, an image, and its
   temptation? Did you cite each device in your reasoning or chat, not in the
   document, where it shaped a sentence?
3. **The keyring.** Does every restatement cover a situation no other covers? Was
   anything cut for repeating a true statement or for feeling long? For each cut, can
   you name the situation and the passage that already covers it?
4. **The highlighter and the images.** Where a loud section drowned a quiet line, did
   you check the loud section first? Does each abstract principle have a concrete image
   that makes it clearer than the plain statement, reused as the text's vocabulary?
   Is each point carried by one image, not extended past its point, not stacked, not
   hidden in figure?
5. **The seams.** Was each added passage compared with the whole text: added only for
   an uncovered situation, folded into the passage it repeats, or reconciled with the
   passage it contradicts?

Recap of the tokens: `redundancy-is-amplitude`, `metaphor-as-retrieval-handle`,
`rehearse-the-temptation`, `disarm-counterarguments`, `negative-examples`,
`stakes-not-calm`.
