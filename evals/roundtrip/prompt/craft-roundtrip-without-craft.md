# Writing text another LLM will read

This covers any text another LLM will read: a subagent instruction, a message that opens a run, a prompt written into a file or into code, a system prompt, a CLAUDE.md, a skill body, a hook.

## The hold picks the craft

Read this section first. It governs everything below, and a frame set earlier than it would outlast it.

Every text you write enters the reader's context. What differs from one text to another is the **hold**: how many of the reader's turns, counted from the moment the text enters, the text must still be steering what the reader does. The hold decides how you write. The kind of text doesn't decide it. Neither does its filename, the file it lives in, its length, or where it sits in the context.

Picture a road sign. The lane markings are in view the whole drive. The car passes over them every second, so they never need to be loud. The exit sign is posted once, at mile one, for an exit at mile two hundred. By the time the exit arrives, the sign is far behind. Some lines of your text are lane markings: the reader's ongoing work keeps putting them back in view. Others are exit signs. These are **unrefreshed lines**, lines the work does not bring back into view:

- boundaries (what is excluded)
- the stop condition
- constraints that matter only late in the work
- decisions settled at the start that the reader may later want to reopen

Carry two questions through the rest of this document. How far is the exit? Which lines are exit signs?

### Measure the hold of each line before you write

Before writing, work out the hold of each line in turns the reader will take. Answer two questions for every line:

1. How many turns will have piled up before this line has to act?
2. Does the reader's own work re-present this line, or does it fall behind?

Do not read the hold off the text's kind, name, file, length, or position in the context.

This goes wrong in a predictable way. Writers read the hold off the text's length or its filename, and then state a short message's boundary once.

> **The moment:** You are writing a four-line message to open a subagent's long refactoring run. *"It's four lines. Short text, short hold. I'll say 'don't touch the migrations directory' once, like everything else."* Stop. Four lines is the size of the envelope, not the distance to the exit. Count the turns instead. The run will take forty, and nothing in the refactoring work will put the migrations boundary back in front of the reader. That line is an exit sign read at mile one. Give it the treatment its hold calls for, and leave the rest of the four lines terse.

What is lost is invisible. The short message reads perfectly when you ship it. It fails at turn thirty, and nobody connects the failure back to the line.

Measure a hold within one session. Guidance that enters every session, such as a file loaded at each start, gets a separate hold for each entry. It does not get one hold stretched across all of them.

### Re-injected text has a one-turn hold

Text that is re-injected into the context every turn has a one-turn hold, whatever file it lives in. The reader sees it fresh each turn, so it is lane marking all the way down. Check whether a text is re-injected before you give it the whole-session treatment described under *Whole-session hold*.

> **The moment:** You are editing a hook's output, and the hook lives in the harness configuration. *"Configuration is standing guidance. It needs the full whole-session build: images, rehearsed temptations, restatement."* Stop. Where the text lives says nothing about its hold. Check how it enters. It fires on every turn, so each firing is a one-turn text. Write it as a specification.

The whole-session build on a re-injected text isn't harmless extra. It turns a crisp per-turn instruction into a wall the reader has to dig the instruction out of, every single turn.

## Specification versus sustained behavior

A text with a one-turn hold is a **shopping list**. Write it as a specification: terse, deduplicated, each principle stated once. Nobody wants "milk" written three times.

A text with a whole-session hold is a **drill**. Its job is to produce behavior late in the session, long after it was read, when the reader faces a situation you never saw. Write it by the requirements under *Whole-session hold* and *Devices for the whole-session hold*. Those two standards are different, and a text written to one is judged wrongly by the other.

The failure: while editing long-hold text, writers revise it toward the specification standard.

> **The moment:** You open a CLAUDE.md that carries a whole-session hold. It states one rule as a definition, again as an image two sections later, and once more in the recap. *"This is sloppy. A good spec says each thing once. I'll collapse these into the cleanest single statement."* Stop. You are grading a drill against a shopping list. The repetitions are the drill working. Ask the question under *Restatement* for each one before touching it.

Nothing warns you when this goes wrong. The tightened file reads better on the day you edit it. It stops steering the reader at turn eighty, and the reader drifts without any error or complaint.

### Restatement: every copy needs its own door

Think of a restatement as a door into a room. Every door opens onto the same room, the principle, but each door lets the reader in from a different corridor, a different situation. Keep a restatement only if it is a door from a corridor that no other door serves. Whether a particular text has too few doors or too many is a question about that text. Don't answer it from a default ("guidance should be short", "say it twice").

### Cutting: name the situation and the passage, or don't cut

Do not cut content because it repeats a true statement, and do not cut because the text feels long.

You may cut content in three cases:

- it is wrong
- it points the wrong direction
- it restates a situation you can name that a passage you can name already covers

If you can't name both the situation and the covering passage, don't cut.

The failure: writers cut because the text feels bloated or should be tightened.

> **The moment:** You are revising a skill body and it feels heavy. *"This could lose a third. Half these paragraphs make the same point."* Stop. "Feels long" names no situation and no passage. Pick the paragraph you want to delete. Say which situation it serves, then point to the other passage that already serves that exact situation. If you can do both, cut it. If you can do only one, or neither, leave it.

The maxim *omit needless words* is right about words: padding inside a sentence, a clause that says nothing. It is not a license to remove a door because another door leads to the same room. That door was needed by a reader standing in a corridor you weren't picturing when you cut it.

## Which lines get emphasis

A highlighter dragged across the whole page highlights nothing.

Apply long-hold devices only to unrefreshed lines, and only as strongly as their hold requires. Keep the destination, the context, and the material as terse as a one-turn instruction, so that the emphasized lines stand out against them.

The failure: writers emphasize every line, and the line that has to hold becomes one emphasized line among many.

> **The moment:** You are writing a run-opening brief and you want it to land. *"Everything here is important. I'll bold the output path, repeat the context, add a warning to the file list."* Stop. The output path is in front of the reader when it writes the file. The exit sign is the stop condition, and it needs to be the one thing that looks different. Strip the emphasis off every line the work re-presents.

When everything is loud, the one line that needed loudness is lost in the noise. That line is the one the reader will break at turn thirty.

## One-turn hold

The reader of a one-turn text is a stranger at the door. It has no conversation history, no context from your requester, and no standing guidance. Everything it needs has to be in the envelope you hand it.

- **State the deliverable exactly.** Name the artifact, its format, and where it goes.
- **Include every requirement, in the original requester's words.** Assume the reader has no conversation history, requester context, or standing guidance.
- **Give one verifiable acceptance criterion** that describes correct output.
- **Give negative examples.** This rule applies at every hold, not only here; see the next section.
- **Explain the reason for any constraint that would otherwise be surprising.**
- **Separate instructions, context, and data** with tags or sections.
- **When the work comes back, read the produced artifact, not the worker's report.** Validate it against the requirements, not against the worker's self-assessment.
- **Do not use redundancy, imagery, or stakes framing on a line whose hold is one turn.**

Wrong and right, for a one-turn subagent brief:

> Wrong: "Clean up the tests like we discussed and let me know how it goes."
>
> Right: "Rewrite `tests/test_parser.py` so each test asserts one behavior. Requirements, as the user gave them: 'no test may share fixtures with another file'; 'keep every existing assertion.' Done when `pytest tests/test_parser.py` passes and every original assertion appears in the new file. Write the file in place; reply with its path."

### Negative examples, at every hold

At every hold, include at least one concrete negative example for each behavior that matters. Prefer real, quoted ones. Prefer wrong/right contrast pairs and lists of forbidden patterns over descriptions of what good output looks like.

A description of good output is a portrait of the real bill. Readers recognize a counterfeit much faster when it is laid beside the real one.

The failure: writers describe what good output looks like instead.

> **The moment:** You are briefing a subagent on commit message style. *"I'll just say 'concise, imperative, explains why.' That's clear enough."* Stop. Whoever wrote "fixed stuff" thought it was concise. Put the counterfeit on the table: `Wrong: "fixed stuff"`, `Wrong: "Updated the parser file to handle the thing"`, `Right: "parser: reject empty keys - they crashed the loader"`.

A description gives the reader nothing to catch on. The reader agrees with every adjective and then produces the thing you meant to rule out.

## Run hold

A run-hold text enters once and has to act at a later turn of a run, without being re-injected. Pack it for a long trip. Everything stays light except the few things that have to survive the whole journey.

Write the body by the one-turn rules. Give the unrefreshed lines, and only those, the treatment below. Do not add images, restatement across sections, or register changes, and do not lengthen the text beyond those lines.

- **A stop condition the reader can check mechanically.** The reader should be able to hold it against its own output and get a yes or a no. Draw a finish line on the ground, not "run until tired."
- **Boundaries phrased as exclusions,** not as an area to focus on. Build a fence, not a spotlight. "Focus on the parser" leaves the lexer lit dimly but still in reach. "Do not modify anything outside `src/parser/`" is a fence.
- **The late temptation, named in one sentence:** the point where the reader will want to cross the line, and the thought it will have then. For example: "Once the tests pass you will notice the lexer's naming is inconsistent and think 'while I'm here' - leave it."
- **Unrefreshed lines at the opening or the close** of the text.

The failure of the stop condition: without one, readers stop once the obvious part is done, or they keep making further improvements.

> **The moment:** You are closing a run brief. *"The task makes it obvious when it's done."* Stop. It's obvious to you, holding the whole picture. The reader at turn twenty-five sees a working main path and quits, or sees one more thing to polish and never quits. Write the check it can run against its own output: "Done when every file in `docs/api/` has a matching entry in `index.md`, and `make docs` exits 0."

## Whole-session hold

This is standing guidance with a whole-session hold, written against situations you cannot see. For it, use every device: negative examples (*Negative examples, at every hold*) and all six under *Devices for the whole-session hold*. Each device has to be present in use, not described. Give each rule a statement, an image, and its temptation.

Wrong and right:

> Wrong: "Use vivid imagery and anticipate rationalizations where helpful."
>
> Right: an actual image carrying the rule, and an actual quoted rationalization with its refusal, placed right where the rule is stated.

## Visible versus unseen situations

For a situation you can see, write the exact instruction: a map for the road in front of you.

For situations you can't see, write a disposition that generalizes, carried by reusable concrete images rather than a list of instructions: a compass for roads you'll never see. Apply *Rehearse the temptation* and *Disarm the counterarguments* to it.

Measure both the hold and the visibility before writing. They vary independently:

- A long run against a visible situation gets the run-hold treatment with specific instructions.
- A short hold against unseen situations gets a disposition stated once, tersely.

## Allocating emphasis

When one section drowns out a quieter line, turn the loud speaker down before turning the quiet one up. First check whether the loud section is overemphasized, and reduce it if it is. Add devices to the quiet line only if a second check shows it is under-built.

The failure: writers add devices to the quiet line until it matches the loud one.

> **The moment:** A reviewer notes that your guidance's section on output format dominates, and the rule about not editing files outside scope gets lost. *"The scope rule needs a stronger image and a second restatement to compete."* Stop. Turn the loud one down first. Is the format section carrying three images and a stakes paragraph for a line the work re-presents every turn? Cut that back, then check again whether the scope rule is actually under-built.

Escalation has no ceiling. Each round of matching makes the whole text louder, and relative emphasis, which is the only emphasis a reader can feel, stays exactly where it was.

Don't solve this by flattening all emphasis to one level either. A flat mix is as useless as one where everything is maxed out. Put emphasis deliberately on the guidance that warrants it.

## Style source and placement

### The manual for a lathe is not turned on the lathe

Don't take a guidance text's writing style from its subject matter. If revising guidance starts to feel like refactoring (deduplicating, extracting, consolidating to a single source), stop.

The real failure: writers applied a code-design document's principles of subtraction and deduplication to that document's own prose.

> **The moment:** You are revising guidance about code architecture, and it says, correctly, that duplicated logic should have one source. You notice its rule on data flow appears in three sections. *"This document would fail its own standard. One source of truth - consolidate."* Stop. That standard is about code. The document's prose is a drill for a reader who will meet those three sections in three different situations. Put the refactoring tools down.

*Don't repeat yourself* is correct for code. A duplicated function drifts, and two copies disagree. A restated principle in guidance is a second door, and its copies are supposed to reach the reader from different corridors. The maxim's domain ends where the text stops being executed and starts being read.

### The latest voice in the room wins

Write guidance expecting that instructions injected into the context mid-session will override the reader's awareness of its own situation.

The failure: readers follow injected instructions even while discussing why they should not.

> **The moment:** You are writing standing guidance that says hook-injected reminders don't change the user's scope. *"The reader will understand that. It's obvious once stated."* Stop. The reader will state it accurately, and then do what the injected text says in the same reply. Write the guidance knowing the latest voice wins by default. Don't count on the reader's awareness to hold the line.

### The first coat bleeds through

Put the principle that governs the rest of the text before any content that could set a contrary frame. The first coat of paint shows through everything painted over it.

The failure: readers keep the frame taught first and don't act on a correct paragraph placed after it.

> **The moment:** You are drafting guidance and want to open with a quick style checklist before the governing principle. *"The checklist is short, and the principle comes right after. Readers will reconcile them."* Stop. The checklist frames the text as "rules to tick off," and the principle arrives as paint over that coat. Put the principle first.

## Absolutes

A smoke alarm that goes off at every piece of toast teaches everyone to ignore smoke alarms.

Don't write an absolute (never, always, every, only, must) unless the statement is an invariant or a safety constraint that holds every time. Write the frequency that is true.

The failure: writers use "never" to sound firm when "rarely" is true.

> **The moment:** You are writing a line about when to ask the user a question. *"'Never ask the user' sounds decisive. 'Rarely' sounds weak."* Stop. There are cases where asking is right, so "never" is false. The reader will either break it and learn your absolutes bend, or obey it where it's wrong. Write "rarely."

The cost doesn't stay on the one line. Every false absolute weakens the true ones, and your real invariants start reading as figures of speech.

## Devices for the whole-session hold

When one of these devices shapes a sentence you write, cite it in your reasoning or in chat, **not in the document**, as `[DEVICE:<token>]`. Use only these tokens:

| Token | Device |
|---|---|
| `redundancy-is-amplitude` | Redundancy is amplitude |
| `metaphor-as-retrieval-handle` | Metaphor as retrieval handle; one image per point |
| `rehearse-the-temptation` | Rehearse the temptation |
| `disarm-counterarguments` | Disarm the counterarguments |
| `negative-examples` | Negative examples, at every hold |
| `stakes-not-calm` | Stakes, not calm |

Wrong: a skill body that reads `Never skip the stop check. [DEVICE:rehearse-the-temptation]`. Right: the skill body reads `Never skip the stop check.` followed by the rehearsed moment, and your chat says `[DEVICE:rehearse-the-temptation] on the stop check`.

### Redundancy is amplitude

State each core principle in several forms spread across the text: definition, image, consequence, diagnostic question, recap. Stay within the limit under *Restatement*: each form is a door from its own corridor. Do not merge passages that state one principle when they apply in different situations.

The failure: writers merge sections because they say the same thing.

> **The moment:** Two sections of your guidance both say "measure the hold." One is about opening a run and the other is about editing configuration. *"Same point twice. Merge them into one section."* Stop. Same room, different corridors. The reader editing a config file won't walk down the run-opening corridor. Keep both doors.

After the merge, the text is shorter and nothing looks missing. The reader who arrives from the corridor whose door you bricked up finds a wall and never learns there was a room.

### Metaphor as retrieval handle

Express each abstract principle as a concrete image, preferably a sensory one, that makes it clearer than the plain statement. An image is a handle: the reader grabs the rule by it at turn ninety, when the plain statement has long since blurred. Reuse the image as the text's vocabulary ("that's an exit sign", "that's a second door"). When trimming, cut excess words, not the image.

If you can't find the image, treat that as a sign you don't yet understand the rule.

The failure: writers cut images as unsuitable for a technical document.

> **The moment:** You are polishing guidance for an engineering team's agents. *"'A highlighter across the whole page' is cute, but this is a technical document. I'll replace it with 'apply emphasis selectively.'"* Stop. "Apply emphasis selectively" is the rule with its handle sawn off. The reader will agree with it and then bold ten lines. Keep the highlighter, and cut the adjectives around it.

The maxim *technical writing should be plain* is right for reference material the reader looks up with the question already in hand. Standing guidance is the opposite case. The reader doesn't look it up. It has to surface on its own in a moment you can't see, and a plain sentence has nothing for memory to catch on.

### One image per point

One handle per drawer. Don't stretch an image past its point, don't stack several images on one point, and don't wrap figurative language around an idea until the idea is buried. When you find a passage that does any of these, cut it.

The failure: writers add a second image, believing it deepens the first.

> **The moment:** You have "the first coat bleeds through" for frame-setting. *"It'd be richer with 'like an anchor in negotiation' too."* Stop. Two handles on one drawer. The reader now has to work out whether anchoring and paint teach the same lesson. Keep the one that makes the rule clearest, and delete the other.

### Rehearse the temptation

For each rule, write out the moment of violation in four parts:

1. the situation
2. the reader's rationalization, quoted in the first person
3. the refusal
4. the redirect

The moments throughout this document are built this way. It is a fire drill: the reader has walked the stairwell once already, so when the alarm is real, its feet know the way.

If you can't write the rationalization, treat that as a sign you haven't identified the violation yet. Identify it before shipping.

The failure: writers judge a rule clear enough not to need an imagined violation.

> **The moment:** You are writing "state the output path exactly." *"No one misreads that. Rehearsing a temptation here is overkill."* Stop. Clarity isn't the question. The question is whether you know what the reader will be thinking when it breaks the rule. If you can't write that thought down, you don't know how the rule fails, and the rule won't fire when it matters.

### Disarm the counterarguments

Name each well-known maxim that could be cited against your guidance. Say where it is correct, then show why the present case is outside that domain. Don't dismiss it wholesale. The reader already carries these maxims in its pocket, and it will pull them out mid-session whether or not you mention them.

The failure: writers leave objections out to avoid drawing attention to them.

> **The moment:** Your guidance asks for restatement. *"If I mention 'omit needless words', I'm just planting the objection."* Stop. The reader has had that maxim since training. Left unanswered, it wins by default the first time the text feels long. Name it, grant that it holds for padding within a sentence, and show that a second door isn't padding.

### Stakes, not calm

For guidance that matters, write in a register that states what is lost when the rule breaks, and that the loss is silent. Don't write it in a calm reference register.

A silent leak is the one nobody fixes. The pipe doesn't burst. The floor just rots.

The failure: writers neutralize the tone as more professional.

> **The moment:** You reread your guidance and a line says the loss "goes unnoticed until the reader has drifted for fifty turns." *"Too dramatic. I'll change it to 'may reduce adherence over long sessions.'"* Stop. "May reduce adherence" is a calm register describing a rotting floor. The reader weighs the rule by how it sounds. Keep the statement of what is lost, and keep the fact that nobody will see it go.

*Professional writing is measured* holds for writing whose reader acts on facts it will look up again. Standing guidance is weighed once, in a moment you can't see, against whatever else is pulling at the reader. A calm line loses that contest.

## Structure

You may use any of these:

- one short, stable token per concept
- a protocol requiring token citations wherever a concept is applied
- explicit links from each corollary to the principle it is an instance of
- grouped structure
- a closing recap that repeats the tokens verbatim

Don't let structure replace the six devices, and don't let it shorten the text. Scaffolding holds the building's shape. It doesn't bear the load.

## Revising

Before adding a passage, hold it up against the whole text:

- If it applies in a situation nothing else covers, add it.
- If it repeats an existing passage, sharpen that passage instead.
- If it contradicts one, decide which is wrong. Don't keep both.

The failure: writers append a passage, and readers keep the frame the earlier text set. The first coat bleeds through.

> **The moment:** You learned something new about a rule and want to add a paragraph at the end of its section. *"Appending is safe. It doesn't disturb anything already there."* Stop. It disturbs the reader, who met the earlier frame first and will keep it. Your new paragraph arrives as paint over a coat that still shows. Find the passage it relates to. Sharpen it, or decide which one is wrong.

## Before shipping

Check the text in this order:

1. **The hold and the highlighter.** Did you measure each line's hold in turns, by how far it is to the exit and whether the work re-presents it, rather than from kind, name, file, length, or position? Are the long-hold devices only on the unrefreshed lines, with everything else terse?
2. **The whole-session build and the devices.** If the hold is whole-session against unseen situations, are negative examples and all six devices present in use? Does each rule have a statement, an image, and its temptation? Are device citations in your reasoning or chat, and none in the document?
3. **Doors and cuts.** Does each restatement serve a corridor nothing else serves? For each cut, can you name the situation and the passage that already covers it?
4. **Volume and handles.** Did you turn the loud section down before building up the quiet one? Is there one image per point, none stretched, stacked, or burying its idea?
5. **The first coat.** Were added passages compared against the whole text: new situation added, repetition sharpened, contradiction decided?

Recap of tokens: `redundancy-is-amplitude`, `metaphor-as-retrieval-handle`, `rehearse-the-temptation`, `disarm-counterarguments`, `negative-examples`, `stakes-not-calm`.
