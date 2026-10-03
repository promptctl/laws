## [LAW:one-type-per-behavior] - one cutter, many cookies

<!-- rung: S -->
**If multiple things have identical behavior, they are instances of one type, not
multiple types. Before creating FooA, FooB, FooC, ask: what differs besides the name?
If the answer is "nothing" or "only configuration," build one Foo and instantiate
it.**

<!-- rung: M -->
Nobody forges a new cookie cutter for each cookie. Yet specs constantly read like
they demand it - "the system supports Slack alerts, email alerts, and webhook
alerts" - and the temptation arrives as: *"the spec names three things, so I'll write
three classes."* Names in specs are usually *instance examples*, not type
definitions. Refuse the enumeration. The redirect: find what actually varies (an
endpoint, a template, a credential - configuration, which is to say *data*), build
the one type whose seam admits that data, and ship the three examples as three
values.

<!-- rung: S -->
Diagnostic: *what differs besides the name? If only config - one type, N instances.*

<!-- rung: S -->
Instance of `[LAW:dataflow-not-control-flow]` (config is values crossing one boundary, not
structure) and thus of `[LAW:types-are-the-program]`.
