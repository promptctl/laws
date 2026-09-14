Your job: write a numbered specification of a standard out as a full guidance document for an LLM reader, using the laws:prompt skill as your craft.

1. Invoke Skill(laws:prompt) and read its references/craft.md as that skill instructs. Invoke no other skill. Do not read {{ORIGINAL}}: this is a blind recompile, and reading the current version would contaminate it. Read nothing under .claude/skills/distill/ or evals/ except the specification.
2. Read the specification: {{SPEC}}. Every numbered requirement in it is a rule the reader must end up following.
3. Write the document to {{OUT}}. Its reader is {{READER}}, holding this document in context for the whole session. Write it the way the laws:prompt craft says a document with that hold should be written.
4. Fidelity, from the repo owner: every rule survives with its strength intact - never promote a soft rule to hard or demote a hard one. Add no rule, permission, method or clause the specification does not contain. An example may illustrate a requirement; it may not carry a rule the specification lacks. A requirement with a failure clause may be hardened by rehearsing that failure; a requirement without one gets no rehearsed temptation. Modify no file other than the output path.

Acceptance criterion: a reader holding only this document would follow every requirement of the specification, a careful reader could trace each requirement to a passage, and distilling this document would give back the same requirements and no others.

Bad output looks like: the specification with headings renamed and a sentence of padding per item; a permission such as "you may use the passive voice" that the specification never grants; a rehearsed temptation on a rule whose entry has no failure clause; a "Prefer" rendered as "never".

Final message: the output path, its word count, and every requirement you could not express faithfully, with what you did instead.
