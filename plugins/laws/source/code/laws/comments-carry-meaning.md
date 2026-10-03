## [LAW:comments-carry-meaning] - the code is the mechanism; the comment is the meaning

<!-- rung: S -->
**A comment earns its place by standing at an altitude the code does not: the intent
behind the mechanism, a relationship to code elsewhere, the reason for this way and
not another - or the mechanism itself lifted into a simplification that meets a reader
who cannot yet read the dense original. It may restate what the code does; it must not
restate it at the code's own altitude, a verbatim echo that adds no height and rots
the moment the code moves. The test is never whether the comment repeats the code, but
whether it stands where the code cannot. And it stands there in the domain's language:
the words an expert already uses, then the project's own names, then whatever a
subsystem names more finely - each layer spoken inside the ones above it, none
replacing them (`[LAW:domain-language]`).**

The code is a photograph; the comment is the caption. Describing the frame is not
forbidden - describing the frame is what captions are for. The dead caption reads the
pixels back at pixel-resolution - `// returns 2+2` over `return 2+2` - serving no one
who could already see them. The living caption names the scene from a height the
pixels don't hand over: "a Gaussian blur across nine neighbor samples," "the last read
before the retry storm," "the accounts legal requires we purge." Whether a viewer
needs that height is not the frame's business - a reader fluent in the language reads
the pixels and skips the caption at no cost, while a reader who cannot (a shader in a
language they don't speak, a codebase annotated for learning) is handed the scene they
could not have resolved alone. Obviousness is a fact about the viewer, never the frame.

A caption calls the things in the frame by the names they already have, and those
names come in layers. First, the domain language: the terms the subject itself uses,
the ones another expert would recognize without a word of explanation - *exponential
backoff with jitter* over a retry loop, *debit* and *credit* in a ledger, *idempotency
key* at a payment endpoint. Then the project's own words for its things: its type
names, its glossary, the terms its docs already use, spelled as the project spells
them. Then whatever a subsystem names more finely still. The layers stack; they never
replace. The narrowest corner of the project still speaks the domain's words for the
domain's ideas, and a project term sits alongside the domain term, not in place of it.
The payoff is that someone fluent in the subject opens the code, the docs, and the
comments and is already at home, and a search for the standard term lands on every
place it matters.

- WRONG: `// bump the wait a bit each time so we don't hammer the server`
- RIGHT: `// exponential backoff with full jitter; the schedule lives in RetryPolicy`

<!-- rung: M -->
So a comment dies three deaths. *"A quick line restating this helps the next reader"*:
only if it rises above the code - a same-altitude echo helps no one and lies the first
time the code changes and the words don't. *"This just says what the code says, delete
it"*: check the altitude first - a teaching gloss or a simplification does work you
cannot see *because* you can already read the code; never strip comprehension on the
grounds that the mechanism is transparent to you. *"The standard term is jargon - my
own phrase or an analogy will land better"*: the term is the shared language, and a
comment that coins a replacement has made a second name for one thing. Now the reader
has to work out whether the two names agree, and the expert who came looking for the
standard word walks past the comment that explains it. Simplify the mechanism as far
as the reader needs; keep the domain's nouns and the project's nouns. An analogy
standing in for a word the subject already has is a translation nobody asked for. And
never flood the other way: the author's mood, the ticket's backstory, the whole domain
re-taught belong outside the frame, not in the caption.

<!-- rung: S -->
Diagnostic: *does this comment stand at an altitude the code does not - a
simplification, an intent, a relationship - scoped to this code and spoken in the
domain's own words, then the project's?*

<!-- rung: S -->
Instance of `[LAW:one-source-of-truth]`, but only at the code's own altitude: a same-altitude
echo is a divergent second copy that will drift, while a comment pitched higher is a
distinct rendering for a reader the code doesn't reach, not a rival source; a coined
synonym is that same second copy at the level of vocabulary. Under
`[FRAMING:representation]`, keep the view the code cannot supply.
