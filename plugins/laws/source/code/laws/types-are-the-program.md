## [LAW:types-are-the-program] - the types are the program

<!-- rung: S -->
**Choose the strongest theorem about your data that is still true: every legal state
representable, every illegal state unrepresentable. The implementation is residue.**

Not a description of the program. Not scaffolding around the program. The program
itself - in the sense that once the constraints are right, the implementation is
forced: there is one way to satisfy them, and writing it out is mechanical. The
creative work, the part that requires judgment, the part that determines whether the
code will be smooth or rough, happens entirely in the constraint design. By the time
you are typing function bodies, the hard part is over.

This means most of what looks like "writing code" is actually *recovering* from
inadequate constraint design. Defensive checks exist because the type did not forbid
the bad state. Branching exists because the type did not carry the discriminator.
Every line that enforces something the type *could have* enforced is a line that
exists to compensate for an under-constrained signature. Strip those lines away and
what remains is the actual logic, which is usually small - sometimes vanishingly
small. That is where "less code, substantially less code" comes from: not terser
code; constraints doing the work that sprawl would otherwise do.

The craft is choosing the **strongest true theorem**. Weaker theorems - `any`,
bag-of-optionals, `string` where the domain has four values - admit illegal states,
which forces every callsite to defend, which is coupling. Stronger-but-false theorems
force the code to lie or break. The exactly-right type is exactly as expressive as
the real domain, and named in the domain's words (`[LAW:domain-language]`). The type
is a theorem; the implementation is its proof.

WRONG - the bag of optionals, every field a maybe, the real structure smuggled into
folklore:

```ts
interface Source { mode: string; path?: string; url?: string; auth?: Auth }
// "if mode is 'url', url and auth are set; if 'file', path is set" - says a comment,
// somewhere, maybe. Every consumer re-derives this, checks half of it, guards the rest.
```

RIGHT - the discriminated union, illegal combinations unrepresentable:

```ts
type Source =
  | { kind: 'file'; path: string }
  | { kind: 'url'; url: string; auth: Auth }
// No consumer can see a url-without-auth or a file-with-url. There is nothing to
// guard, so there are no guards.
```

<!-- rung: M -->
The temptation arrives precisely when implementation feels hard: *"I'll just handle
that case in the body."* That is the moment a crystal forms - the moment a piece of
code becomes single-purpose, the moment leverage flips below one. **Hardness is
information.** When the body is hard, the constraints upstream are wrong. Refuse the
escape: stay in the type until the type is doing the work, even when escaping would
close the task faster. If the body wants to branch, ask what discriminator the type
is missing. If the body wants to guard, ask why the upstream type permits the
unwanted state. If a name needs to convey what the type cannot, fix the type. If a
comment is needed to explain an invariant, the type did not encode it - fix the type,
don't write the comment. The body is the *last* place to write logic and the *first*
place to look for logic that wants to be lifted into types.

And the discipline that follows has its own law, `[LAW:polishing-by-subtraction]`: the
smooth version has *less* code than the rough version, because the constraints have
absorbed the work the sprawl was doing. If your iterations grow the code, you are
crystallizing, not smoothing. Worry the stone smooth - keep removing material until
your hand finds nothing to catch on. The code is not done when it works; it is done
when there are no rough bits left to snag on.

<!-- rung: S -->
Diagnostic: *if the body branches or guards, what discriminator or constraint is the
type missing?*

<!-- rung: S -->
Primary law of `[FRAMING:parts-and-seams]` - the "what seams are made of" face - and
the machine-checked summit of `[FRAMING:representation]`: a type is the one map the
compiler redraws for free on every build. Every law below is an instance of this one
- a specific shape that wrong-state-representability tends to take.
