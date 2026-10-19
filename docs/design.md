# Design

Why the system is shaped this way, and what it does not do.

## One file, not a plugin

The first attempt was a ~1200-line opencode plugin with a ledger, an idle-nudge loop, and
a `crew_*` tool surface. It worked, and it was the wrong shape: state machine logic in
TypeScript that only made sense while the server was alive, plus four custom agent files
whose prompts had no effect.

Two findings killed it:

1. **Custom agent system prompts are not delivered.** A probe agent given a prompt that
   said "reply with ORANGE" received the user message, the tool list, and no system
   prompt. It replied normally. Anything written into `agents/*.md` is stored by the server
   and never reaches the model.
2. **Command body text and inline subagent prompts do reach the model.** Those are the only
   two delivery paths that work.

So the entire system is one command file. The loop is instructions, the workers are
`general` subagents with their prompt passed inline, and state is a markdown file on disk.

That is a deliberate downgrade in enforcement and an upgrade in debuggability. There is no
hidden state to inspect — read `.crew/progress.md`.

## State on disk

`.crew/progress.md` is the orchestrator's memory, not its context window. A restart,
compaction, or closed terminal loses nothing important: the status table says which tasks
are merged and which are running, and git says what actually shipped.

The deliverable is always `main`. `.crew/` is disposable.

## Dependencies are merges, not approvals

A task is READY only when every dep is **merged into main**. Not "reviewed", not "PASS".
Workers branch from main, so an unmerged dep is simply absent from their tree. Spawning
early produces a worker that cannot run its own gate, or worse, invents the missing piece.

Four states and what each permits:

| dep state | spawn dependent? |
|---|---|
| `merged` | yes |
| `passed` (reviewed, not merged) | no — merge first |
| `running` / `in review` | no — it will report |
| `parked` / `failed` | no — dependent parks too |

## The shared contract

Parallel workers cannot see each other. Any name two tasks share must be decided before
they start, in the plan, once.

Observed failure without it: four pages were built in parallel. The plan named the home
file `src/home.html`; three workers independently linked to `index.html` because that is
the convention. Every per-task gate checked only its own file's `<title>` and `<h1>`. All
four passed. The site had three dead links.

The fix is three-part and all of it is prompt-level:

1. Planner writes `## Shared contract` before the task table — file names, link targets,
   entry point, CSS class names, exported symbols, API paths, data shapes.
2. Each coder receives the rows that touch its task, and is told to report a blocker
   rather than invent a name.
3. Planner writes `## Integration gate` — one command that tests the seams (link targets
   resolve, imports resolve, primary path works, no unapproved placeholders), run on main
   after each wave.

The orchestrator must run that gate after every wave, and a wave is not done until it
passes — regardless of how many tasks say `merged`.

## Blockers

Never silently skipped, never guessed. The categories that matter:

- **Coder `STATUS: BLOCKED`** — re-spawn once with the reason; a repeated block parks it.
- **Reviewer `FAIL`** — re-spawn with the reason quoted verbatim, not a fresh start.
- **Merge conflict** — a reviewer arbitrates (`DECISION` / `KEEP_FROM` / `FILES` /
  `RATIONALE`); the orchestrator applies mechanically. `both` or `needs human` parks.
- **Gate red on main** — `git reset --hard HEAD~1`, then treat as FAIL.
- **Provider error** — harness failure, does not consume an attempt.
- **Worker never reports** — check the disk, not your assumptions: worktree missing means
  it never started; branch without commits means it is stuck. Re-spawn once, then park.
- **Worker dies mid-task** — its commits survive. Re-spawn telling it to continue, never
  reset.

Two attempts per task. Then park, with the reason in the final report.

## Cleanup

`rm -rf .crew` is not enough. Git keeps internal worktree refs and branch names, so the
next run dies with `fatal: a branch named 'crew/T1' already exists`. The order is:

```
git worktree remove --force <each .crew/* worktree>
git worktree prune
git branch -D crew/*
rm -rf .crew
```

Branches are only deleted when `git log main..crew/<id>` is empty, or when the task was
parked and the report says its branch is the only copy.

## Verification

Verified end-to-end on throwaway repos:

- interview → plan → 4 parallel workers → review → serial merge → main green → cleanup
- dependency enforcement (T1 merges before dependents spawn)
- `.crew/` invisible to git; `git add -A` stages nothing; correct cleanup and re-run
- shared contract + integration gate caught the dead-link class of bug
- absolute worker paths — a worker that once hung on a wrong `cd` now completes
- a run where both workers died still merged, ran the gate, and cleaned up

Not verified: behaviour on very large repos, and runs long enough to hit the 5-wave cap.

## Known limits

- Prompt-enforced, not code-enforced. No structural guard prevents an unfrozen interface.
- The reviewer shares the coder's model, so there is no cross-model review.
- Serial merges keep main green at the cost of wall-clock.
- The `steps:` frontmatter limit on agents is not enforced in current builds; the command
  compensates with explicit STOP RULES in every worker prompt.
