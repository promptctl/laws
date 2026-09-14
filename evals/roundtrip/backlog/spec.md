# Backlog Planning Specification

Scope: planning the set of epics and tickets in a project's backlog, whether seeding an empty backlog or extending one after work has landed; how the planned units are built in code is out of scope.

## Terms

- Foundational unit: a unit in the project's first layer, which later work across the project's full scope will use.
- Checkpoint: something a person can verify that exercises what an epic built.
- In-application checkpoint: a checkpoint that runs the functionality directly in the application, the way it will actually be used.
- Demo: something built for a person to look at when the application cannot yet show the work.

## Requirements

### Plan only what is known

1. Do not add a ticket unless you can state where its work ends, and why, with confidence from what is known today, not from what will probably be true after the next layer lands or from what the founding document hopes for. Failure: when the founding document lays out several stages, writers plan all of them because a backlog with only the first stage looks thin.
2. Treat a ticket statement that needs an "if" about a result that does not exist yet, or a "probably" about a shape nobody has seen, as failing requirement 1, and do not write that ticket.
3. Do not plan work whose purpose is finding out whether something is true as a build ticket.
4. Do not plan "the foundation" as a category and stop there; plan what passes requirement 1.
5. After a layer of work lands, extend the backlog from what is then known, using requirement 1.

### Foundational units

6. Plan each foundational unit so that it depends on no single place it will be used; requirements 7 and 8 are the checks for this.
7. State each foundational ticket's purpose as one sentence with no "and"; if the sentence needs an "and", split the ticket in two at the "and".
8. Name, in each foundational ticket, a second consumer of the unit drawn from the project's own goals. If no second consumer can be named, either treat the unit as not foundational or reshape it so it is not fitted to its first use.

### Epic checkpoints

9. Give every epic a checkpoint, and do not treat an epic as done when its tickets are closed or its tests pass; treat it as done only when a person has watched the checkpoint exercise the work.
10. Prefer a visual checkpoint.
11. Space checkpoints close enough together that the project is never far from one.
12. Make every checkpoint, including a demo, cover more than the happy path: edge cases, the empty input, the value at the boundary, and the case the founding document says will probably break.
13. Prefer an in-application checkpoint and use one by default; requirement 14 gives the exception.

### Demos

14. Do not give an epic a demo unless the application cannot yet show the epic's work and the distance to the next in-application checkpoint has grown too long. No epic has a demo by default.
15. Build a demo to the same quality as everything else in the project.
16. Label a demo as a demo in its ticket and in its code.
17. State explicitly in a demo's ticket that the project learns from the demo's mistakes rather than building on it.
18. Treat the word "quick" in a demo ticket as a sign to revise.

### Self-contained text

19. Do not refer, in any epic or ticket, to anything that exists only in the planning conversation, such as an earlier discussion, plan, or agreement.
20. State in each epic's own text why the epic exists in terms of the project's goals.
21. Include in each ticket what a person with no knowledge of the planning session needs to start the work.
22. Where the founding document already says something, point to it by path; do not restate it, and do not assume the reader has read it.
23. Before writing anything to the tracker, read the planned epics and tickets as someone who cloned the repository this morning, and rewrite anything that only makes sense to someone present at planning until it makes sense to that person.
