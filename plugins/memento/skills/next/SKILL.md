---
name: next
description: Pull the next ticket
---

# Next

Pick up the next ready ticket and start work.

## Init

Run `lit quickstart` if you haven't already.  This provides instructions for using the work tracking system.

If the user provided specific information (e.g., a ticket id or area of the codebase to work on), SKIP THE REST OF THESE INSTRUCTIONS and follow the guidance from `lit quickstart` to follow the user instructions.  The following information is for determining which work to pick when the user did not specify.

## Finding work

Take a look at the backlog (`lit ready`) so you understand what work is in-progress or up next.  Now you need to decide whether you need to wrap up in-progress work or start new work.

### In progress work

If there are uncommitted changes or open PRs in the repo, we want to wrap these up before starting new work.

#### Uncommitted changes

determine if these changes are related to a backlog item.  If so, that is your current ticket.  If not, stop and think to your self: Are these changes worthwhile?  Accidential?  Incidental?  Should we commit or discard them?  Use your brain to think about the right solution because there is no one size fits all rule.

Examples:
- uncommitted pnpm lockfile update: check it out to discard, but then regengerate the lockfile as part of your commit when you do work
- Uncommitted typo in a random file: check it out to discard, it's not needed
- Minor update to the readme to include some more instructions: commit it and proceed
- Major update to the readme that is related to the work on the current branch: commit it and proceed
- Major update to work that is clearly NOT on this branch: stash it and proceed
- A half finished feature: find the ticket it's related to.  THIS TICKET IS YOUR ASSIGNED WORK. Skip the backlog scan and go straight to "Working the ticket". If it's not related to a ticket you see, do a quick code review.  does the code look experimental and temporary or high quality?  Does it look complete or barely started?  Then briefly explain the state of the code, what it does, and any other info you have (no ticket, etc).  Ask if they want you to create a ticket and continue the work, if they want it to committed to work as part of a different ticket, or whether they want you to stash or discard it.  Follow that instruction.

Before proceeding, confirm the uncommitted changes are now resolved (committed, stashed, or discarded per the above).  If anything you did previously resulted in a reference to a specific ticket, THAT IS YOUR TICKET ID and you should skip the backlog scan and go straight to "Working the ticket".

Do NOT proceed without either:
- no uncommitted changes
OR
- A ticket id to work on

#### Open PRs

Check for open PRs related to your current branch — `gh pr list --head "$(git branch --show-current)" --state open` (`lit ready` lists tickets, not GitHub PRs, so it won't surface one).  If there are, THIS IS YOUR TICKET!  Skip the backlog scan below and work that PR through the `address-pr-reviews` skill (that's the memento skill for taking a PR's review feedback to a clean, merged close-out), then pick up the working steps under "Working the ticket".

**If there are no open PRs on the current branch:** we'll proceed with pulling from the backlog. Open PRs are still relevant, though — you want to check whether older open PRs overlap with your work, since rebuilding on top of stale code risks significant merge conflicts. Check this after you pull a ticket; if an older PR touches the same files, surface it to the user with both the ticket and PR references before starting, rather than silently building over it.

#### lit ready

Lit ready shows an overview of the epics and the top ticket in each epic, as well as any in-progress or orphaned tickets.

If there are any orphaned tickets, pull from those first — those tickets are abandoned and need someone to finish them. An orphan is your ticket; skip ahead to "Working the ticket".

Otherwise, take from the top of the ready queue.

## Working the ticket

However you arrived at a ticket — uncommitted work, an open PR, an orphan, or the ready queue — work it through these steps:

1. **Read the ticket fully.** Title, description, acceptance criteria, comments, linked PRs, linked tickets. If the ticket references a spec, doc, or prior PR, read that too. You are about to author code that claims to satisfy this ticket — earn the right to claim it.

2. **Surface blockers before starting.**
   - Acceptance criteria missing or vague? Investigate first (see below); ask only if it stays genuinely unresolvable.
   - Depends on another ticket that isn't done? Stop and report.
   - Spec referenced but doesn't exist? Stop and report.
   - The ticket conflicts with current branch state or uncommitted work? Stop and report.
   - Don't paper over ambiguity with assumptions — confirm scope first.

IN ALL CASES YOU MUST DO AS MUCH OBVIOUS PREPARATORY WORK AS YOU CAN BEFORE ASKING THE USER.

A mature engineer knows when to ask for help, and it isn't at the slightest hint of ambiguity and before they've put in a shred of effort to answer the question themselves.  "What do I do with this uncommited work" is only a good question if it isn't obviously work that Directly corresponds to the ticket matching the branch name.  "Acceptance criteria missing or vague?" It is only a good question if it's not clearly answerable via common sense or existing documentation or some other method. If there's real ambiguity, surface it. If it's just basic information about the repo, see if you can figure it out for yourself. In all cases, the user should be presented with The results of an Extremely quick Investigation rather than "Hey, I don't know what to do. Tell me what to do." 

3. **Set up the workspace.**
   - Create or check out The branch matching the ticket ID. eg, `git checkout -b <ticket id>` or  `git checkout -b <ticket id>_slug` — if that branch already exists (a previously-started ticket), check it out instead with `git checkout <ticket id>`.
   - Confirm the working tree is clean before starting. If dirty, Figure it the f*ck out. You're a mature, responsible, highly skilled engineer. 

4. **State the plan in one paragraph, then start.** What the ticket asks for, how you'll verify it's done (the machine-verifiable criterion), and the first concrete step. Then begin.

## When to stop and ask

To be honest, rarely. You should be capable of figuring this stuff out. 

If you think that there's a chance that this could have negative impacts on other work, you can ask a quick question, but like I said, You need to make an attempt to answer the question yourself.  (The one recurring case — a branch carrying uncommitted work that belongs to no current ticket — is already handled in "Uncommitted changes" above.)
