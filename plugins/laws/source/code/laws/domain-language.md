## [LAW:domain-language] - the territory already has names

<!-- rung: S -->
**Name things in the language of their domain: the term another expert in the subject
would recognize with no explanation. Where the project has its own names, use those
too, spelled as the project spells them; where a subsystem names more finely still,
use that. The layers stack and none replaces the one above it - the domain's word for
a domain's idea holds everywhere in the codebase. Reach for the word the domain
already has before coining one.**

A map is useful because its names match the signposts. The towns already have names;
a cartographer who renames them has drawn a map only its maker can navigate with, and
every traveler now carries a second sheet translating those names back to the signs.
Code is a map of a domain, and the domain was naming its ideas long before this repo
existed: a retry schedule is *exponential backoff*, the thing that makes a retried
payment safe is an *idempotency key*, the two sides of a ledger entry are *debit* and
*credit*, the step that turns bytes into a tree is *parsing*. A reader who knows the
subject reads those names and is home. A reader who meets `waitMultiplier`,
`dupeGuardToken`, `plusSide` and `minusSide`, `loadTree` is in a foreign country with
a phrasebook - and so is the search that goes looking for the standard term and finds
nothing.

Three layers of language, and they stack. On top, the domain language, and it holds
everywhere: the subject's own terms and the industry-standard engineering terms,
anything another expert would recognize unprompted. Under it, the project's language:
the names the project has given its things - its types, its glossary, the words its
docs already use - spelled as the project spells them and used alongside the domain's
terms, never in place of them. Under that, a subsystem may name more finely still,
inside both. A lower layer never overrides a higher one. In the narrowest corner of
the codebase, the domain's word for the domain's idea is still the word.

This is one-source-of-truth at the level of vocabulary, and it is what
interoperability is made of. One concept, one name, and the name is the one the world
already uses - so the code, the docs, the comments, the tests, and the tickets say the
same word, a reader moves among them without a translation step, and a search for the
term lands on every place it lives.

WRONG: `class PaymentRetryTicket` for an idempotency key; `// bump the wait a bit each
time so we don't hammer the server`; `Settlement` in the type and "the payout" in the
comment above it; a comment that explains a ring buffer as "think of it like a lazy
Susan" and never says *ring buffer*.
RIGHT: `IdempotencyKey`; `// exponential backoff with full jitter; the schedule lives
in RetryPolicy`; `Settlement` in both places; `// ring buffer: writes wrap at capacity
and overwrite the oldest entry`.

<!-- rung: M -->
The temptation arrives in two voices. *"The standard term is jargon - my own phrase
will read more naturally."* The term is the shared language; your phrase is a second
name for one thing, and now every reader has to work out whether the two agree. *"An
analogy will make this land."* An analogy that stands beside the domain's term can
teach; one that stands in for it is a translation nobody asked for, and the next
reader learns the analogy instead of the subject. Refuse both. The redirect: find the
word the domain uses - the textbook, the RFC, the spec, the project's glossary - and
use it. Simplify the mechanism as far as the reader needs; keep the nouns.

<!-- rung: S -->
Diagnostic: *would an expert in this subject, reading this name or comment cold,
recognize the concept without a word of explanation - and is it the same word the
project's docs and types use?*

<!-- rung: S -->
Instance of `[FRAMING:representation]` - a name is a map, and the domain drew it
first - and of `[LAW:one-source-of-truth]` at the level of vocabulary: a coined
synonym is a second clock.
