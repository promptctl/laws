Each version's section is written in the PR that bumps `plugins/laws/.claude-plugin/plugin.json`; pushing the matching `vX.Y.Z` tag publishes that section as the GitHub release notes (`.github/workflows/release.yml`).

## v0.25.0 - 2026-09-03

- laws(prompt): make the hold the spine of the craft - every text enters at distance zero (#41)
- laws(prompt): measure distance at fire time, and split every prompt along objective vs. constraint (#40)
- injector: host the extracted bundle under node, with a boot self-check and a stock fallback (#39)
- refactor(memento): replace the moved skills with pointers to their own repo (#38)
- horizon: seed a run's time zero, reproducibly, from the reference seed (#36)
- injector: recover the bundle in memory from the installed binary (#37)
- horizon: pin the controlled-inclusion instrument, recorded per run (#35)
- Declare markdown out of review scope, and drop paths-ignore (#30)
- memento(context-ceiling): enforce the ceiling where an autonomous session can see it (#34)
- feat(memento): lower the context ceiling to 250k, and give the number one home (#33)
- ci(review): reconverge code-review.yml; the workflow now excludes itself from review (#32)
- Make polishing-by-subtraction citable, and stop comment bloat in review responses (#29)
- ci(release): trigger on master after the default-branch rename
- memento(finalize): the escalation to KILL now asks who it is killing
- laws(inspect-eval): the frontier comment outlived the decision it described
- laws(launcher): release the port hold on every path that leaves, not just the good one
- laws(excise): the switch-gate comment described a design that was never built
- laws(router): a transcript that would not resolve now says so
- laws(launcher): one rule for handing a session back, and one arm per flag
- memento(finalize): a successor that never came up is torn down, not left racing
- laws(inspect-eval): a silent target is the fourth arm, and every call now carries a clock
- laws(excise): which crafts exist is derived, never enumerated
- memento(address-pr-reviews): a promised page nobody named is an error, not a stop
- memento(finalize): say which transport honours --reset, because two of three cannot
- laws(seams): the reload is done — the ledger said it was still to build
- memento(address-pr-reviews): one enforcer for response shape, and cover the paging
- memento(finalize): name the detached path's own failure arms
- memento(finalize): prove the process we retire is the one we captured
- laws(launcher): a switch that cannot be applied hands the session back, resumed
- laws(injector): a dropped socket rejects in-flight calls instead of hanging them
- laws(policy): the policy file is the one source for enforcement AND for the text
- memento(finalize): every session gets the same close-out capability - add the detached-window transport
- routing(gate): release the connect timeout so a completed switch is not stuck 15s
- routing(gate): stop counting discarded transcript branches as engaged crafts
- routing: prefer a fresh subagent over stacking crafts, and say why not a fork
- routing(gate): the craft conflict is directed, not a mutual incompatibility
- Paginate the review-thread read so a long-running PR stays fetchable
- routing(gate): retire the whole conflicting craft set, not one member of it
- routing(gate): stop pinning a session id the user already chose
- routing(gate): make an inspector refusal fail instead of reading as success
- Paginate the reviews read that finds blocking change requests
- routing(gate): identify the switch's owning session instead of inferring it (promptctl-routing-rat.5)
- routing(gate): offer the switch only where it can actually be enacted (promptctl-routing-rat.5)
- routing(gate): stop claiming an ordering the summary flow cannot deliver (promptctl-routing-rat.5)
- routing(gate): retire the craft's engagement, not just its guidance (promptctl-routing-rat.5)
- repo: untrack .in_use/44765 — Claude Code plugin bookkeeping, not source
- routing(gate): put the plugin bin dir on PATH so the deny's instruction is runnable (promptctl-routing-rat.5)
- routing(gate): the reload — claude-laws launcher, laws-switch, and the four-option enactment (promptctl-routing-rat.5)
- routing(gate): SEAM 1 retired — the hook payload already carries transcript_path (promptctl-routing-rat.5)
- routing(gate): the rewind is disk surgery — rewindTo(), verified live (promptctl-routing-rat.5)
- routing(gate): measured — disk-only rewind does not survive --resume on 2.1.226 (promptctl-routing-rat.5)
- routing(gate): injector foundation — inspector channel re-verified on CC 2.1.226 (promptctl-routing-rat.5)
- routing(gate): one source of truth for craft compatibility; correct the runtime gate to fire only on incompatible pairs (promptctl-routing-rat.5)
- memento(finalize): prove the pane we deliver into is really ours, and test it (#22)
- memento(context-ceiling): force the close-out at the 350k token ceiling (#21)
- fix(ci): pass CLAUDE_CODE_OAUTH_TOKEN so PROVIDER=auto can authenticate (#20)
- repo: ignore Claude Code's .in_use bookkeeping and Python bytecode
- memento(finalize): --reset states the next session's context instead of guessing it
- memento(address-pr-reviews): stop restating message-in-a-bottle's delivery semantics
- memento(finalize): delete the drop-file fallback — no transport is a failure, not a delivery
- skills(laws): the session that writes the artifact reads the craft itself (promptctl-routing-rat.3) (#19)
- evals: delete the single-session eval system — banned in this repo, period (#18)
- hooks: compatibility-gate the craft guard - coexist by default, refuse only laws:code + laws:prompt (promptctl-routing-rat.2) (#17)
- memento(finalize-session): gate iTerm2 goal-carry on a readiness probe, not a fixed sleep (#16)
- plugins(memento): extract workflow tooling into its own plugin; symmetric plugins/{laws,memento} (#15)
- evals(suites): headroom for the code suite - a held-out-coverage task and its honestly-recorded campaign (#14)
- evals(suites): the laws:code suite — four tasks, one-command runs, a live sensitivity record (#13)

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

