# Design goals: the `prose` skill

The `prose` skill is writing guidance for text a person will read - READMEs, docs, reports, commit messages, emails. It exists to get one thing right: the reader comprehends what you meant with the least friction. The skill states this directly - comprehension is the only thing prose is paid to produce, and the reader's time is the budget every sentence spends.

## What good output looks like, and the choices that get there

**The writing serves specific named readers, not "everyone."** The skill's stated aim is that you answer "who reads this, what do they already know, what will they do after" before drafting. The concrete choice: it tells you to name a reader per goal and lead with what that reader needs - a README leads with what the thing is and the install command; a report leads with the recommendation. Its reason: text that serves everyone serves no one.

**It handles the several goals one document actually carries.** The skill's claim is that the honest answer to "what is this for" is usually plural - a README convinces a stranger, gets a hurried user running, and hands the committed reader a path deeper. The choice that follows: list the goals before drafting, and layer the document by familiarity level with headings that front-load their keywords, so each reader can find their level by skimming.

**Prose is as simple as it can be without dropping what the reader needs.** The stated aim is simplicity - plain sentences over piled-up qualifiers - with an explicit floor: "as simple as possible, but not simpler." The choice: reach simplicity by subtraction (cut one element at a time until the next cut would remove a load-bearing fact), and never trade accuracy for tidiness. The skill also states that "load-bearing" is relative - the same detail is the point in a design review and noise in a launch note - so the floor moves with reader and context rather than sitting at a fixed target.

**The techniques are tools, not a checklist.** The skill lists concrete moves - lead with the point, plain words and active voice, put a sentence's weight at its end, one idea per paragraph, concrete over abstract. It explicitly frames these as tools to reach for when a draft reads wrong, not boxes to tick per sentence, and says applying them mechanically flattens prose into sameness. The stated final judge is how the prose reads aloud, not whether a rule was followed.

## What it deliberately avoids, and why

- **Fluent phrases that sound sophisticated but carry no checkable fact** - "becomes residue," "seamlessly integrates," "powerful and flexible." The skill's test: if you can't state what the phrase would look like if it were true, it says nothing, so cut it. It names this as a thing LLM prose reaches for when it wants to sound smart.
- **Oversimplification** - dropping a load-bearing detail to get a cleaner sentence. The skill calls this simplicity's clothes without simplicity.
- **Register tricks that signal importance instead of carrying it** - mid-sentence bold for emphasis, symmetrical filler ("not only X but also Y"), adjectives where evidence belongs ("blazingly fast" instead of the number), throat-clearing openers. The skill lists these under signals you're drifting.

My reading of the SKILL.md file (this is inference, not a stated goal): the skill splits into a short body and a long craft so that the weight arrives only when it is about to be used. SKILL.md is what the router injects, so it stays thin and does one thing - send the writer to `references/craft.md` before any prose is written. The session that writes the prose reads the craft itself; keeping an incompatible standard from stacking on top of it is the runtime gate's job, not the skill body's. The design choice matches the skill's own economy-of-attention goal, applied to the agent rather than the reader.
