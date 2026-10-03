## [LAW:one-source-of-truth] - one clock

<!-- rung: S -->
**Every concept has exactly one authoritative representation. All others are derived
and explicitly synchronized. If two representations can diverge, the architecture is
already broken - divergence is not a risk, it is a schedule.**

A man with one clock knows the time; a man with two clocks never does. Never create
a second source; find and use the canonical one. When you inherit two, your task -
before anything else - is to demote one into a derived copy or delete it. Names are
representations too: a word coined in the project for a concept the domain already
names is a second clock (`[LAW:domain-language]`).

This is not theoretical. On 2026-07-12, in the author's dotfiles repo: the rad-shell upstream
installer (`curl … install.sh | bash`) wrote `~/.rad-plugins` - *through* a dotbot
symlink - and silently clobbered the tracked, curated `config/rad-plugins.home`. Two
writers, one file. Real, committed, curated data destroyed by a convenience script
that had no idea the file already had an owner. The only reason it was caught is that
a laws-primed session ran `git status` and actually read the diff. That is what "two
representations can diverge" looks like in the field: not a philosophical concern - a
deleted file, discovered by luck.

WRONG: a config value in the YAML *and* a hardcoded default in the code "as a
fallback"; a count stored next to the list it counts; an installer that writes a file
dotbot also manages. RIGHT: one owner writes; everyone else reads or derives, and the
derivation is visible.

<!-- rung: M -->
The temptation arrives as: *"I'll just keep a copy here for convenience"* - or its
installer-shaped twin, *"it's easier to write the file directly."* Refuse both. The
redirect: find the canonical representation; read from it, derive from it, or change
it - never shadow it.

<!-- rung: S -->
Diagnostic: *if these two disagree, which one is lying? If that question has no
answer, the architecture is broken.*

<!-- rung: S -->
Instance of `[FRAMING:representation]` at full strength, and of
`[LAW:types-are-the-program]`: two divergable representations are an under-constrained
type - the constraint that they agree is encoded nowhere.
