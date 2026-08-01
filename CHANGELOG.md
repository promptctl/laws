## v0.24.1 - 2026-08-01

- hooks: minimal route text - lean on skill descriptions, drop disabled laws:ticket route (#12)

## v0.24.0 - 2026-08-01

- hooks: guard one-craft-per-session - refuse a second medium load (promptctl-routing-rat.1) (#11)
- ticket(craft): draw destination-vs-mechanism on the boundary axis, so a precise output isn't stripped (#10)
- evals(judge): an optional reference-anchored judge tier, trusted only after human agreement (#9)
- evals(compare): repeated runs expose the harness's own noise floor (#8)
- evals(compare): one command that runs a task across arms and reports which did better (#7)
- evals(run): a single scored run joining one task and one configuration (#6)
- evals(configs): a configuration format that names a skill body by git ref, or none (#5)
- evals(tasks): a task-spec format pinning repo, commit, task text, and a machine criterion (#4)
- evals(isolation): prove Opus by reading the account banner, not by asking the model (#3)
- evals(driver): complete turns whose replies exceed the visible pane (#2)
- evals(driver): a tmux turn-driver that refuses to emit a bad turn (#1)
- chore(ci): install agent code-review action
- skills(prompt): green language, no reflexive absolutes, integrate-don't-append; one craft per session may be held directly
- skills(code): restore parse-dont-validate as a first-class law; make the boundary exception structural
- chore: track lit integration files, ignore local research scratch
- skills: add project-local laws skill governing laws-skill edits
- skills(prompt): recast far-end device craft as reveal-don't-fog
- skills: drop the "verifiable acceptance criterion" bullet from dispatch skills
- style: normalize em-dashes to hyphens across docs, skills, and scripts
- skills(ticket): replace frontmatter description with PLACEHOLDER
- evals(isolation): isolated interactive session that proves Opus + no CLAUDE.md leak
- skills(ticket): keep subagent-dispatch prompts clean of orchestrator solutioning
- skills(prompt): add proportion principle carried by the orchestra metaphor
- skills(ticket): distinguish requester-imposed constraints from agent-invented mechanism

## v0.23.0 - 2026-07-27

- skills: add laws:application-spec - clean-room spec of an existing application - bump 0.23.0

## v0.22.0 - 2026-07-26

- ci: release workflow - immutable tag, GitHub release, changelog on version bump
- docs: working-with-skills - orchestrator never reads a skill body
- docs: design-goals doc per skill (chat, code, prompt, prose, ticket)
- laws: ticket - from-scratch rewrite of the craft; 38KB→12KB, no cold-executor frame - bump 0.22.0
- skills: artifact crafts move behind references/craft.md dispatch bodies - bump 0.21.0
- skills: add laws:chat - replies to the user present in the session - bump 0.20.0
- laws: ticket - migration proof is a repo fact, not measuring apparatus - bump 0.19.1
- laws: ticket - spikes pay out in backlog structure; verifiability bends for no ticket type - bump 0.19.0
- laws: ticket sizing gains a floor - the boundary tax ends confetti tickets - bump 0.18.0
- skills: add laws:ticket - a plugin-owned 4th medium route - bump 0.17.0
- readme: lead with the payoff - code that holds up, not medium-scoped guidance
- prose: aim is simplicity, and goals decide what is load-bearing - bump 0.16.0
- laws: comments-carry-meaning keys on altitude, not duplication - bump 0.15.0
- laws: comments-carry-intent keys on duplication, not obviousness - bump 0.14.0
- hooks: comments explain why, not the absent jq - bump 0.13.1
- hooks: drop jq - pure-bash printf, pre-sanitized text - bump 0.13.0
- hooks: bmf's engagement text verbatim, one source of truth - bump 0.12.0
- hooks: name laws and devices explicitly in the reminder - bump 0.11.0
- hooks: engage ping is pure reinforcement, not re-routing - bump 0.10.0
- prompt: add [DEVICE:] citation protocol, parallel to [LAW:] - bump 0.9.0
- hooks: once-per-session engagement, not per-prompt routing - bump 0.8.0
- rename: guidance skill -> prompt (laws:prompt), bump 0.7.0
- guidance: drop the style-exemplar specimen - the shipped docs are the exemplars
- guidance: self-exemplifying rewrite - the document practices what it teaches
- guidance: cover the whole continuum - add the proximate end (task prompts)
- guidance: add regime section - same physics, four axes, terseness licensed by proximity
- rename: guidance-authoring skill -> guidance (laws:guidance), bump 0.2.0
- chore: MIT license + point repository at promptctl/laws
- fix(hooks): degrade to silent no-op when jq is missing
- fix(hooks): wrap events in top-level hooks object - required for registration
- feat: initial release of the laws plugin (laws@promptctl)

