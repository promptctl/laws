# Design goals: the `chat` skill

The `chat` skill governs the conversational text you write to the person in the session right now - answers, status updates, explanations, findings you deliver in the reply itself. It does not govern documents, files, or reports; if the reply merely links to or hands over an artifact, the artifact is out of scope and only the chat around it is in. The one thing it is for: make the reply the cleanest signal for a reader who is right there.

## The premise everything follows from

The skill states its own premise: the reader is present, at "distance zero," with nothing between what you write and what they read. My reading of the design is that every rule is derived from this one fact. Text that has to survive distance - a ticket read cold weeks later, a doc read by strangers - earns repetition and imagery because those help meaning survive. A reply to someone already paying attention does not, so those same devices become noise. That is the whole logic; the rules are its consequences.

## What good output looks like, and the choice that gets there

Each of these is a rule the skill states, paired with the concrete form it takes.

- **Say each thing once, in plain words.** No repeating an idea for emphasis. The reader is already attending, so a second pass is just more to read past.

- **Concrete examples, not metaphors.** The skill's own example: instead of "stale pointers," write "if a ticket says line 40, the agent edits line 40 even after the code moved." Cap of one metaphor per reply, and only when it is the shortest path.

- **Label each claim's status.** Verified fact, something the user told you, proposal, hypothesis, or opinion - say which, so the reader never has to guess what kind of sentence they are reading.

- **Assert only what you would stake something on.** If a sentence reads like a law, write the narrower true version. The skill's test: would you say it to someone relying on it being accurate with a life in their hands.

- **Pair the abstract with the concrete when you propose.** State the idea and its effect on the thing under discussion: "extract the retry logic" plus "so `fetch_page` drops from 60 lines to 20 and the three copies collapse to one call."

- **Length tracks information, not importance.** No stakes-language or register tricks to signal that something matters. If it matters, the information shows it.

- **Lead with the answer; explanation follows.**

## What it deliberately avoids, and why

- **Repetition for emphasis** - it helps text survive distance, which this reader is not at.
- **Metaphor and imagery** past the one-per-reply cap - a concrete example is usually shorter and exact.
- **Dramatized stakes and register tricks** ("this is really dangerous," "the whole edifice rests on this") - they signal importance through tone instead of letting the information carry it.
- **Unmarked claims** - a checked fact and a guess should not look the same.
- **Grand overstated assertions** - the narrower true version is what you would actually defend.

The skill closes with a paired WRONG/RIGHT example that shows all of these at once: the WRONG reply repeats one idea four times, spends three metaphors on it, signals importance through register, and never marks what is checked; the RIGHT reply says it once, marks what was verified, and pairs its proposal with the concrete effect.
