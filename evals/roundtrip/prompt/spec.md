# Authoring Text for LLMs

Scope: any text another LLM will read, including a subagent instruction, a message that opens a run, a prompt written into a file or code, a system prompt, a CLAUDE.md, a skill body, and a hook.

## Terms

- Hold: the number of the reader's turns, counted from when the text enters its context, during which the text must still direct what the reader does.
- Unrefreshed lines: lines the reader's ongoing work does not bring back into view. These are boundaries (what is excluded), the stop condition, constraints that matter only late in the work, and decisions settled at the start that the reader may later want to reopen.

## Requirements

### Measuring the hold

1. Before writing, determine the hold of each line in turns the reader will take: how many turns will have accumulated before the line must act, and whether the reader's work re-presents it. Do not infer the hold from the text's kind, name, file, length, or position in the context. Failure: writers infer the hold from the text's length or filename, and state a short message's boundary once.
2. Measure a hold within one session; for guidance that enters every session, treat each entry as a separate hold.
3. Treat text that is re-injected every turn as having a one-turn hold, whatever file it lives in, and check for re-injection before applying requirement 21. Failure: writers apply the whole-session treatment because the text lives in configuration.

### Specification versus sustained behavior

4. Write a text with a one-turn hold as a specification: terse, deduplicated, each principle stated once. Write a text with a whole-session hold to produce behavior late in the session, per requirements 21 and 30-36. Failure: while editing long-hold text, writers revise it toward the specification standard.
5. Keep a restatement only if it applies in a situation no other restatement covers, and decide whether a given text has too little or too much restatement from that text, not from a default.
6. Do not cut content because it repeats a true statement or because the text feels long. You may cut content that is wrong, points the wrong direction, or restates a situation you can name that a passage you can name already covers; if you cannot name both, do not cut. Failure: writers cut on the feeling that the text is bloated or should be tightened.

### Which lines get emphasis

7. Apply long-hold devices only to unrefreshed lines, to the degree their hold requires, and keep the destination, context, and material as terse as a one-turn instruction, so the emphasized lines stand out. Failure: writers emphasize every line, and the line that must hold becomes one emphasized line among many.

### One-turn hold

8. State the deliverable exactly: the artifact, its format, and where it goes.
9. Include every requirement, in the original requester's words; assume the reader has no conversation history, requester context, or standing guidance.
10. Give one verifiable acceptance criterion describing correct output.
11. At every hold, include at least one concrete negative example, preferably real and quoted, for each behavior that matters. Prefer wrong/right contrast pairs and forbidden-pattern lists over descriptions of good output. Failure: writers describe what good output looks like instead.
12. Explain the reason for any constraint that would otherwise be surprising.
13. Separate instructions, context, and data with tags or sections.
14. When the work returns, read the produced artifact, not the worker's report, and validate it against the requirements, not against the worker's self-assessment.
15. Do not use redundancy, imagery, or stakes framing on a line whose hold is one turn.

### Run hold

16. For text that enters once and must still act, without re-injection, at a later turn of a run: write the body per requirements 8-15 and give unrefreshed lines only the treatment in requirements 17-20. Do not add images, restatement across sections, or register changes, and do not lengthen the text beyond those lines.
17. Give a stop condition the reader can check mechanically against its own output for a yes or no. Failure: without one, readers stop once the obvious part is done or keep making further improvements.
18. Phrase boundaries as exclusions, not as an area to focus on.
19. Name the late temptation in one sentence: the point at which the reader will want to cross the line, and the thought it will have then.
20. Place unrefreshed lines at the opening or the close.

### Whole-session hold

21. For standing guidance with a whole-session hold against situations the writer cannot see, use all of requirements 11 and 31-36, each present in use rather than described, and give each rule a statement, an image, and its temptation.

### Visible versus unseen situations

22. For a situation the writer can see, state the exact instruction. For situations the writer cannot see, state a disposition that generalizes, carried by reusable concrete images rather than enumerated instructions, with requirements 34 and 35 applied.
23. Measure both hold and visibility before writing: a long run against a visible situation gets requirements 16-20 with specific instructions; a short hold against unseen situations gets a disposition stated once, tersely.

### Allocating emphasis

24. When one section overpowers a quieter line, first check whether the loud section is overemphasized and reduce it; add devices to the quiet line only if a second check shows it is under-built. Failure: writers add devices to the quiet line until it matches the loud one.
25. Do not reduce all emphasis to one level; place emphasis deliberately on the guidance that warrants it.

### Style source and placement

26. Do not take a guidance text's writing style from its subject matter. If revising guidance starts to resemble refactoring (deduplicating, extracting, consolidating to one source), stop. Failure: writers applied a code-design document's principles of subtraction and deduplication to that document's own prose.
27. Write guidance expecting that instructions injected into the context mid-session will override the reader's awareness of its situation. Failure: readers follow injected instructions even while discussing why they should not.
28. Place the principle that governs the rest of the text before any content that could establish a contrary frame. Failure: readers keep the frame taught first and do not act on a correct paragraph placed after it.

### Absolutes

29. Do not write an absolute (never, always, every, only, must) unless the statement is an invariant or safety constraint that holds every time; write the frequency that is true. Failure: writers use "never" to sound firm when "rarely" is true.

### Devices for the whole-session hold

30. When one of requirements 11 and 31-36 shapes a sentence you write, cite it in your reasoning or chat, not in the document, as `[DEVICE:<token>]` using only these tokens: `redundancy-is-amplitude` (31), `metaphor-as-retrieval-handle` (32-33), `rehearse-the-temptation` (34), `disarm-counterarguments` (35), `negative-examples` (11), `stakes-not-calm` (36).
31. State each core principle in several forms distributed across the text (definition, image, consequence, diagnostic question, recap), within the limit of requirement 5. Do not merge passages that state one principle when they apply in different situations. Failure: writers merge sections because they say the same thing.
32. Express each abstract principle as a concrete image, preferably sensory, that makes it clearer than the plain statement, reuse that image as the text's vocabulary, and when trimming cut excess words rather than the image. Treat being unable to find the image as a sign you do not yet understand the rule. Failure: writers cut images as unsuitable for a technical document.
33. Use one image per point: do not extend an image past its point, stack several images on one point, or wrap figurative language around an idea until it is hidden, and cut any such passage when found. Failure: writers add a second image believing it deepens the first.
34. For each rule, write the moment of violation: the situation, the reader's rationalization quoted in the first person, the refusal, and the redirect. Treat being unable to write the rationalization as a sign the violation is not yet identified, and identify it before shipping. Failure: writers judge a rule clear enough not to need an imagined violation.
35. Name each well-known maxim that could be cited against the guidance, state where it is correct, and show why the present case is outside that domain; do not dismiss it wholesale. Failure: writers omit objections to avoid drawing attention to them.
36. For guidance that matters, write in a register that states what is lost when the rule breaks and that the loss is silent, not in a calm reference register. Failure: writers neutralize the tone as more professional.

### Structure

37. You may use one short stable token per concept, a protocol requiring token citations where a concept is applied, explicit links from each corollary to the principle it is an instance of, grouped structure, and a closing recap that repeats the tokens verbatim. Do not let structure replace requirements 31-36 or shorten the text.

### Revising

38. Before adding a passage, compare it with the whole text: add it if it applies in a situation nothing else covers; if it repeats an existing passage, sharpen that passage instead; if it contradicts one, decide which is wrong rather than keeping both. Failure: writers append a passage, and readers keep the frame the earlier text set.

### Before shipping

39. Before shipping, check the text against requirements 1 and 7, then 21 and 30-36, then 5-6, then 24 and 32-33, then 38.
