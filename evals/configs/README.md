# Configuration specs (which guidance, at which version — or none)

A **configuration** (arm) says only one thing: *which skill body, at which git ref* to load into
the evaluated session — or **no skill at all** (the control arm). It hard-codes no task: no repo,
no commit, no criterion. That orthogonality is the whole point — an arm is a first-class,
swappable thing, so the identical task can be run under different arms and the results compared
honestly.

## The format

A configuration is a directory:

```
<config>/manifest.sh   # DATA ONLY:
  CONFIG_SKILL   = skill name ("code", "prompt", …), or EMPTY for the control arm
  CONFIG_REF     = the git ref (in the laws repo) whose body to load — required for a skill arm
  CONFIG_SUMMARY = one-line description
```

**The skill version is a git ref, and it is the single source of truth.** The body is read
straight from git at that ref when the arm is resolved (`git show <ref>:<path>`) — never from a
checked-in copy that could drift.

**The body path is derived from git, not hard-coded.** The body is
`skills/<name>/references/craft.md` when that exists at the ref (laws:prompt, laws:prose,
laws:ticket), otherwise `skills/<name>/SKILL.md` (laws:code, laws:chat, laws:application-spec).
Deriving reproduces the documented convention without a second copy of the repo's structure that
could go stale.

## The three arms here

| Config | Skill | Ref | Resolves to |
|--------|-------|-----|-------------|
| `code-ref-a` | `code` | `8f6d15b` | the laws:code body at that commit |
| `code-ref-b` | `code` | `58b573b` | the same skill at a **different** commit (an earlier body) |
| `control`    | —     | —   | **no body** (the baseline) |

## Use it

```sh
evals/configs/validate-config.sh evals/configs/code-ref-a   # well-formed?
evals/configs/resolve-config.sh  evals/configs/code-ref-a   # print the body (empty for control)
evals/configs/verify-configs.sh                              # prove every arm (below)
```

`verify-configs.sh` is the done-claim proof. For every configuration it validates the spec and
asserts the resolved body is **exactly** what git holds at that ref (compared against an
independent `git show <ref>:<path>`), with the control arm resolving to no body. It then proves
the failure arms: a **bad ref**, a **bad skill/path**, and a **smuggled task field** each abort
nonzero rather than yielding an empty or stale body. Exit 0 iff all hold.

## Exit-code contract

`resolve-config.sh`: `0` = resolved (a body, or a deliberate empty for control), nonzero = the
ref/path did not resolve — never an empty body standing in for a failed lookup.
`validate-config.sh`: `0` = valid, nonzero = the first violation, named on stderr.

## Environment

`git`, and a checkout of the laws repo the refs live in — the harness ships inside it, so its
toplevel is the default; override with `CONFIG_LAWS_REPO`.
