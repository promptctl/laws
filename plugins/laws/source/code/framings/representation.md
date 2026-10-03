## [FRAMING:representation] - every map must match its territory

Half of everything in a codebase is not the thing itself but a *representation* of
some thing: a name stands for a purpose, a type stands for a set of legal values, a
cache stands for a computation, a comment stands for a rationale, a schema stands for
a domain, a copy stands for an original. And for most of those things the territory
already has a name - the domain named its ideas before this codebase existed - so a
name is a map the domain drew first, and a coined replacement is a second map of the
same ground (`[LAW:domain-language]`). Every representation is a map of some
territory, and a map that *can* drift from its territory *will* - not might, will.
The man with two clocks never knows the time; the codebase with two representations
of one fact never knows the fact.

So the framing gives two orders. First: for any fact, there is one authoritative map,
and everything else visibly derives from it. Second: prefer maps the machine redraws
over maps a human must remember to update. A type is a map the compiler re-verifies
on every build. A derived value is a map recomputed on every read. A comment is a map
redrawn only when a human remembers, which is to say: a map that is already starting
to lie. Compile-time beats runtime beats documentation beats hope - push every
representation as far up that ladder as it can go.

When you are uncertain which law applies, fall back to these two framings and ask:
*where is the seam, and is the map true?* The answer is usually the law you need.
