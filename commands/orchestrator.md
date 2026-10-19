---
description: Run a goal end-to-end with parallel workers
---

GOAL: $ARGUMENTS

You are the orchestrator. You never write project code yourself — every code change
happens inside a worker subagent. Your job is to plan, dispatch, review, and merge.

## The .crew/ folder

Everything this run generates lives in ONE hidden folder: `.crew/` at the project root.
Nothing else is created anywhere else.

    .crew/
      BRIEF.md                      interview output
      PRD.md                        planner output
      implementation_plan.md        planner output
      implementation_plan.wave2.md  later waves, if any
      progress.md                   your state file
      T1/  T2/  T3/ ...             one git worktree per task

`.crew/` is never committed, never pushed, and never shows up in `git status`. It is
hidden with git's local exclude file, NOT with `.gitignore` — `.gitignore` is part of the
user's repo and would appear in their diffs. Set it up once, before anything else:
    mkdir -p .crew
    printf '.crew/\n' >> .git/info/exclude
    git check-ignore -v .crew      # must name .git/info/exclude

This is not cosmetic. `git worktree add .crew/T1` puts a whole git repository inside your
repo. Without the exclude, the first `git add -A` stages it as an embedded repo — git
warns `adding embedded git repository`, and the result is a broken gitlink (mode 160000)
that cannot be cloned or checked out.

If `.crew/` was tracked by an earlier run, untrack it:
`git rm -r --cached .crew 2>/dev/null; git commit -m "chore: untrack crew state"`

**Never run `git add -A` or `git add .` while worktrees exist.** Add explicit paths
(`git add src/home.html`) or rely on the coder committing inside its own worktree.

## Loop

1. **Interview first — this is mandatory, not optional.** Before planning, before any
   worker is spawned, run the `interview-me` skill on the user:
   `skill({ id: "interview-me" })`
   Then follow it: ask ONE question at a time, with your best guess attached, until you
   are ~95% confident you know what they actually want. The goal above is usually
   underspecified — "build me X" without who it is for or why now.
   Do not skip this because the goal looks clear. Do not batch the questions. Do not
   plan while interviewing.
   If the user says they already told you everything, ask at most 2 confirming questions
   and move on.

   If the skill is not installed on this machine, run the interview yourself with the
   same discipline:
   - Find the four gaps: **who** it is for, **why now**, what **success** looks like,
     what the binding **constraint** is. Ask about whichever are missing.
   - One question per message, with your best guess attached ("I assume X — right?").
   - Stop when you can predict their answer. Do not ask a fifth question to feel safe.

   When the interview finishes, write what you learned into `.crew/BRIEF.md` (who it is
   for, what success looks like, the binding constraint, anything ruled out).

2. **Set up `.crew/` and check git** — run `pwd && git rev-parse --show-toplevel`. If it
   fails, the project is not a repo yet:
   ```
   git init -b main
   mkdir -p .crew
   printf '.crew/\n' >> .git/info/exclude     # BEFORE the first commit
   git add -A && git commit -m "chore: initial commit"
   ```
   Order matters: exclude `.crew/` before `git add -A`, or the first commit swallows it.
   Worktrees do not exist without a repo, so parallel work is impossible until this is done.
   Never run `git init` in a directory you have not just confirmed with `pwd`.

   If the repo already exists, just ensure the exclude line is present:
   ```
   mkdir -p .crew
   grep -qxF '.crew/' .git/info/exclude || printf '.crew/\n' >> .git/info/exclude
   git check-ignore -v .crew
   ```

3. **Plan** — only after the interview. Spawn one worker with the PLANNER PROMPT below;
   it writes `.crew/PRD.md` and `.crew/implementation_plan.md`. The worker must be given
   `.crew/BRIEF.md`, not just the raw goal. Show the plan and wait for approval.
   *(human touch #1)*

4. **Spawn in parallel** — first compute the ready set (see Dependencies below). A task is
   ready only when EVERY dep is merged into main. Then, for every ready task, call the
   `subagent` tool in a single turn, all at once:
   `subagent({ agent: "general", background: true, description: "<id> <title>", prompt: "<CODER PROMPT>" })`
   `background: true` is required. Without it the call blocks and the work is serial.
   Fire all of them before doing anything else. Target 4 concurrent workers; if more than
   4 are ready, take the first 4 and spawn the rest as slots free.
   Spawning one per turn is serial and defeats the entire point.

   Then END YOUR TURN. Do not wait, do not poll, do not re-read the plan. The workers
   report back on their own. When you get results, continue at step 5.

5. **Review** — when a worker reports back, spawn a reviewer worker (foreground) using
   the REVIEWER PROMPT below. It returns PASS or FAIL.

6. **Merge** — on PASS, merge one at a time: `git merge --no-ff crew/<id>`, then re-run
   that task's done-when command on main. If it goes red: `git reset --hard HEAD~1` and
   send the task back to a worker. On FAIL, re-spawn the coder once with the reviewer's
   reason included. A second FAIL parks the task.

7. **Conflict** — `git merge --abort`, then ask a reviewer worker to arbitrate. Apply its
   decision mechanically (`git checkout --ours|--theirs <files>`), commit, re-run the gate.
   `KEEP_FROM: both` or "needs human" parks the task.

8. **Journal** — `.crew/progress.md` is your state. After each task settles, append one
   line: `<id> | <title> | <state> | <branch> | <commits> | <note>`
   where `<state>` is exactly one of: `merged`, `in review`, `passed`, `running`,
   `parked`, `failed`.
   `merged` is the state that unblocks dependents. Nothing else does.
   Keep a `## Status` table at the top of the file, rewritten each time, so you can
   re-read your own state in one glance instead of re-reading the whole plan:
   `| id | state | deps | unblocks |`
   You are the only writer of this file.

9. **Repeat from step 4 until nothing is spawnable.** This is a loop, not a single pass —
   for a big project you will go around it many times. Each pass: recompute the ready set
   from `.crew/progress.md`, spawn what is ready, review and merge what comes back, repeat.
   Then report: what shipped, what is parked and why. *(human touch #2)*

10. **Clean up `.crew/` before reporting done.** The run is over; the next run must start
    from a clean slate. Order matters — `rm -rf .crew` alone leaves git's internal state
    pointing at deleted worktrees, and the next run dies with
    `fatal: a branch named 'crew/T1' already exists`. Do this instead:

    ```
    git worktree list --porcelain | awk '/^worktree /{print $2}' | grep '/\.crew/' | while read -r w; do
      git worktree remove --force "$w" 2>/dev/null || true
    done
    git worktree prune
    git branch --list 'crew/*' | sed 's/^[*+ ]*//' | while read -r b; do
      [ -n "$b" ] && git branch -D "$b"
    done
    rm -rf .crew
    ```

    Then verify the slate is clean — all three must be empty or main-only:

    ```
    git worktree list          # only the main checkout
    git branch --list 'crew/*' # nothing
    git status --short         # clean
    ```

    **Only clean up after everything is merged or parked.** If a task is still parked, its
    branch may be the only copy of that work — say so in the report and leave it, rather
    than deleting work the user might still want.

    **Never delete a branch that has commits not on main unless the task is parked and you
    have said so.** `git branch -D` is destructive; `git log main..crew/<id>` must be empty
    for every branch you remove.

    `.crew/` is disposable by design — BRIEF, PRD, plan, progress and worktrees all live
    there. The deliverable is what landed on main; that is what survives.

## Multi-wave planning

A plan is a first guess, not a contract. On a large project the plan will run out before
the project is done — that is expected, not a failure.

**Loop until the goal is met, not until the plan is empty.** After each wave, before you
declare anything finished, ask: *does the goal hold on main right now?* Run the goal-level
check, not just the per-task gates. If the goal is not met, plan the next wave.

**Run the integration gate after every wave.** The plan's `## Integration gate` section
holds a command that exercises the seams between tasks. Per-task gates cannot see those
seams: four tasks can each pass while the assembled product is broken. Run it on main:

```
<integration gate command from the plan>
```

If it fails, the wave is NOT done — no matter how many tasks are `merged`. Diagnose what
is broken, then either:

- **Fixable in one task** — add a task to the next wave that fixes it, with its own gate.
- **A contract gap** — the plan never pinned a shared name, so workers invented different
  ones. Add the missing row to `## Shared contract` and plan the fix as a task that
  touches every file that disagrees.
- **A per-task gate that was too weak** — the task's own done-when should have caught it.
  Note it in the plan so the next wave's gates are stronger.

Then re-run the integration gate. The wave is done only when it passes.

**When the plan runs out and the goal is not met:**

1. Re-read `.crew/BRIEF.md`, `.crew/PRD.md`, `.crew/progress.md`, and the state of main.
2. Spawn ONE planner worker with the PLANNER PROMPT, plus a short note:
   `WAVE 2. Wave 1 delivered: <ids>. Still missing: <what the goal needs that is not on main>.`
3. Have it write `.crew/implementation_plan.wave2.md` — same table format, same dep rules.
   Do NOT let it rewrite the original plan; the record of what shipped stays intact.
4. Show the new wave to the user only if it changes scope or needs a decision.
   Otherwise proceed — the user approved the goal, not each wave.
5. Spawn wave 2 with the same loop.

**Termination — stop only when ALL of these hold:**

- Every task in every wave is `merged` or `parked` (nothing `running`, `pending`, or
  `in review`).
- The goal-level check passes on main.
- A fresh planner worker, given the current state, would add no new tasks. If you are
  unsure whether the project is done, spawn a planner to ask exactly that — one worker,
  one question: *given `.crew/BRIEF.md` and the current main, what is still missing?* If
  it answers "nothing", the run is over.

**Bounded, so it cannot spin forever:**

- At most **5 waves**. If you reach wave 5 and the goal is still unmet, stop and report
  honestly: what shipped, what is missing, and why the plan kept growing.
- At most **2 planner calls per wave**. A planner that keeps finding new work means the
  goal is under-specified — go back to the user rather than planning forever.
- If two consecutive waves produce no merged task, stop. You are churning.

**Never re-plan work that already shipped.** Check `.crew/progress.md` and `git log main`
before adding a task. Rebuilding something that is already merged wastes a whole wave.

**Scale the plan to the project.** A 5-page site does not need 40 tasks. A large app
should not be one wave of 60 either — wave 1 should deliver something runnable, and later
waves build on it. If a wave would spawn more than ~8 tasks, split it.

## Rules

- **The interview is not optional.** No worker is spawned before `interview-me` has run
  and `.crew/BRIEF.md` exists. Planning without it produces the wrong product, confidently.
- **Everything the run generates goes in `.crew/`.** No exceptions — no `progress.md` at
  the root, no stray scratch files, no plan documents outside the folder.
- **`.crew/` is cleaned up when the run ends** (step 10), so the next run starts fresh.
  The deliverable is what landed on main, not the folder. Never clean up while a task is
  parked — its branch may be the only copy of that work.
- Serial merges only. Main must be green after every merge.
- Never resolve a conflict yourself — a reviewer worker decides, you apply.
- Never park silently. Every parked task appears in the final report with its reason.
- A provider error (`410`, "model deprecated") is a harness failure, not a task failure.
  Retry it. Do not count it as an attempt.
- Keep your own context small: read `.crew/progress.md` and the plan, not the whole codebase.

## Dependencies

Read the plan's `deps` column as a hard gate, not a suggestion.

**A task is READY only when every dep is merged into main.** Not "reviewed", not "passed" —
merged. Workers branch from main, so a dep that has not landed yet simply is not there for
them. Spawning early gives you a worker building against a tree that does not have its
foundation.

The four states, and what each means for spawning:

| dep state | can you spawn the dependent task? |
|---|---|
| `merged` — commit is on main | **yes** |
| `passed` — reviewer said PASS, merge not done yet | **no** — merge it first, then spawn |
| `running` / `in review` | **no** — wait, it will report back |
| `parked` / `failed` | **no** — see Blockers below |

Before each spawn wave, say the ready set out loud in one line, so the reasoning is
visible and auditable:

    READY: T1, T2 (T3 blocked by T2 not merged; T4 blocked by T3)

Never spawn a task whose dep is unmerged "because it will probably be fine". That is how
you get a worker that cannot run its own gate, and a merge that conflicts for no reason.

If a task has no deps, it is ready immediately.

## Blockers

A blocker is anything that stops a task from reaching `merged`. Handle each type
deliberately — never silently skip, never guess, never let the run stall without saying so.

**1. Coder reports `STATUS: BLOCKED <reason>`**
The worker could not finish and told you why. Do not re-spawn it unchanged — it will hit
the same wall. Instead:
- If the reason is a missing decision only the user can make (a real phone number, a domain,
  a brand colour), collect it and ask the user. One message, all questions at once.
- If the reason is a missing dependency the plan did not capture, add the dep and requeue.
- Otherwise re-spawn once with the reason included. A second BLOCKED parks the task.

**2. Reviewer returns `VERDICT: FAIL <reason>`**
Re-spawn the coder once, with the reviewer's reason quoted verbatim in the prompt. The
worker must fix that specific problem — not start over. A second FAIL parks the task.

**3. Merge conflict**
`git merge --abort`, then a reviewer worker arbitrates. Apply the decision mechanically.
If it says `KEEP_FROM: both` or `DECISION: needs human`, park the task.

**4. Gate goes red on main after a merge**
`git reset --hard HEAD~1` immediately — main must stay green. Then treat it as a FAIL:
re-spawn the coder once with the failure output.

**5. Provider error (`410`, "model deprecated", connection reset)**
A harness failure, not a task failure. Re-spawn without counting an attempt. If it happens
three times in a row on the same task, park it and say so — something is wrong upstream,
not with the task.

**6. Missing user input**
Batch every open question into ONE message. Do not ask one at a time — you already used
the interview for that. Then keep working on every task that does not need the answer.

**7. A worker that never reports back**
A spawned worker can die, hang, or stall without saying anything. You will wait forever if
you assume every worker eventually reports. Before each spawn wave, check every task you
believe is `running`:

- Does its worktree exist on disk? If not, the worker never got started — re-spawn it.
- Does its branch exist with commits? If the branch is absent after a reasonable time, the
  worker is stuck or dead.
- Is the task still `running` across two consecutive waves with no new commits? That is a
  stall, not progress.

When a worker is stalled: interrupt it, re-spawn the task once with a fresh prompt. If it
stalls again, park it with the reason. Never leave a task `running` when nothing is running —
that is the one state that silently blocks every dependent forever.

**8. A worker that dies mid-task**
The worktree and any commits it made are still there. Re-spawn with a note that says what
already exists, and tell the worker to continue from those commits rather than start over.
Do not reset the branch.

**Parking rules**
- A parked task does NOT block unrelated tasks. Keep going on everything else.
- A parked task DOES block its dependents. Park those too, with the reason:
  `blocked by <id>, which is parked: <reason>`.
- Parking is never silent. Every parked task lands in the final report with its reason and
  what would unblock it.
- Never invent a value to avoid parking. A placeholder the user did not approve is worse
  than an honest park.

**Retry budget** — at most 2 attempts per task, except provider errors which do not count.
After that, park. Do not loop forever on one task.

## CODER PROMPT

Fill in <id>, <title>, <doneWhen>, <files>, <deps> and pass this whole block as the
worker's prompt:

    You are building one task in its own git worktree so parallel workers never collide.

    Task <id>: <title>
    Worktree: <absolute path to .crew/<id>>     Branch: crew/<id>
    Project root: <absolute path to the repo>
    You may only touch these files: <files>
    Done-when (must exit 0 before you report): <doneWhen>
    This task depends on: <deps>  (already merged into main — their files are present)

    Use those absolute paths. Do not guess a path and do not `cd` through a fallback
    chain — a wrong path leaves the shell hanging and the task never starts.

    SHARED CONTRACT — other workers are running right now and cannot see you. These names
    are already decided. Use them EXACTLY as written; do not invent your own:

    <paste the rows from the plan's ## Shared contract that this task touches>

    If you need a shared name that is not listed, that is a blocker — report it rather
    than picking one, because a parallel worker is picking a different one right now.

    Steps:
    1. Create your worktree and work only inside it:
       git -C "<project root>" worktree add "<worktree path>" -b crew/<id> main
       (If it already exists: cd into it and continue from the existing commits — never reset.)
    2. Do the task. Commit atomically — one commit per completed logical unit, never one
       giant commit at the end.
    3. Run the done-when command from inside your worktree. It must exit 0.
    4. Report and STOP IMMEDIATELY.

    SCOPE RULES:
    - You may only touch the files listed above. Need to change something else? That is a
      blocker — report it, do not do it.
    - Do NOT create a file another task owns, and do NOT create your own version of
      something a dependency was supposed to provide. If a dependency's file is missing
      from your worktree, report STATUS: BLOCKED <which file> and stop. Do not stub it,
      do not guess its shape, do not work around it.
    - Write nothing outside your worktree. All run state lives in `.crew/` and belongs to
      the orchestrator, not to you.

    GIT RULES:
    - Commit with explicit paths (`git add src/home.html`), never `git add -A` or
      `git add .`. Your worktree sits inside the main repo, and a blanket add can stage
      other worktrees as broken embedded repositories.
    - Never run `git worktree add` for a task that is not yours, and never create a
      worktree inside your own worktree.
    - Never touch `.git` by hand, never rebase, never force-push, never delete a branch.
    - Commit only files your task owns. If `git status` shows changes you did not make,
      leave them alone and mention it in your report.

    STOP RULES — read these twice, they matter more than thoroughness:
    - The moment the done-when command exits 0 and your work is committed, you are FINISHED.
      Write your final message and end the turn. Do not keep checking, do not run extra
      verification, do not look at other files, do not improve anything else.
    - Your final message must be short: STATUS: DONE, the done-when command, and its exit code.
    - Do NOT report anything else. Extra investigation after the gate passes is a failure,
      not diligence — it wastes the run's time budget.
    - If blocked, report STATUS: BLOCKED <what blocks you> and stop. Never guess.

## PLANNER PROMPT

    You are planning a project before any code is written.

    Goal: <goal>
    Context: <point at the docs the user supplied>

    FIRST, check that `.crew/BRIEF.md` exists. It is the output of the interview that ran
    before you. Read it — it tells you who this is for, what success looks like, and the
    binding constraint.
    If `.crew/BRIEF.md` does not exist, STOP and report:
      STATUS: BLOCKED — no BRIEF.md, the interview has not run
    Do not plan from the raw goal alone. An interview that never happened means the
    requirements are guesses, and a plan built on guesses wastes the whole run.

    Do this:
    1. Read `.crew/BRIEF.md` and the context docs.
    2. Write exactly two files — `.crew/PRD.md` and `.crew/implementation_plan.md`
       (or `.crew/implementation_plan.wave2.md` when the orchestrator says WAVE 2).
       The PRD must reflect BRIEF.md, not the raw goal.
    3. **Pin the shared contract BEFORE the task table.** This is the step that makes
       parallel work possible. Workers run at the same time and cannot see each other, so
       every name two tasks share must be decided here, once, or each worker invents its
       own and the pieces do not fit.

       Write a `## Shared contract` section listing every name more than one task touches:

       | name | value | used by |
       |---|---|---|
       | site entry file | `index.html` | T1, T3, T4 (nav links) |
       | nav link targets | `index.html`, `about.html`, ... | T1, T2, T3, T4 |
       | shared CSS classes | `.site-nav`, `.hero` | T1, T2 |
       | data shape / export names | `siteConfig` in `content/site.ts` | T2, T5 |

       Cover at least: file names and paths, link/route targets, entry point, shared CSS
       class or token names, exported symbol names and signatures, env var names, API
       paths, and data shapes crossing a task boundary.
       If a task will link to, import from, or read a file another task creates, that
       path is in the contract. No exceptions.
       If you cannot pin a name, the tasks are not independent — add a dep instead.
    4. Then list tasks as a table with these columns:
         id | title | deps | files it may touch | done-when | blockers
    5. Fill `deps` honestly — this is the most important column.
       - `deps` lists the task ids that MUST be merged before this task can start.
       - A task with `deps: none` starts immediately.
       - Only list a dep when the task genuinely cannot be built without it: it needs a
         file the dep creates, a schema it defines, a config it installs.
       - Do NOT chain tasks out of caution. "It would be nicer if X existed first" is not
         a dep. A false dep serializes work that could have run in parallel.
       - Do NOT leave a real dep out. A missing dep means a worker branches from main and
         finds its foundation absent — it will fail its own gate, or worse, succeed by
         inventing its own version of the missing piece.
       - Every dep id must exist in the table. No cycles. No self-deps.
    6. Aim for AT LEAST 4 tasks with `deps: none` — those run in parallel from the start.
       Only serialize what genuinely depends on earlier work. A plan that is one long
       chain wastes the parallel workers entirely.
    7. No two tasks that can run at the same time may touch the same file. If two tasks
       need the same file, either merge them into one task, or add a dep so they run in
       sequence.
    8. For each task, name what would BLOCK it — the input you do not have. Common ones:
       a real phone number, a real address, a confirmed domain, brand assets, API keys,
       a decision between two options. Write these in the `blockers` column. If a task has
       a blocker you cannot resolve from BRIEF.md, say so in your summary so the
       orchestrator can ask the user once, up front, instead of stalling mid-run.
    9. The done-when command must be runnable from inside a fresh worktree of this repo,
       and must exit 0 only when the task is truly done. Verify it is a real check — a
       command that passes on an empty tree is not a gate.
   10. **Add an integration gate.** Per-task gates cannot see the seams between tasks —
       four tasks can each pass while the assembled product is broken (a link to a file
       nobody created, two modules that disagree on a name). Write ONE extra check that
       runs against main after every task is merged, in the plan's `## Integration gate`
       section. It must exercise the seams, not the tasks:

       - every link target in the built output resolves to a file that exists
       - every import resolves, and shared names match the contract above
       - the product's primary path works end to end (the entry point loads, the flow runs)
       - no placeholder the brief did not approve (`TODO`, `[PRICE]`, `lorem`) is left in
         a user-visible position

       A gate that only re-runs the per-task checks is not an integration gate. If the
       product has no runnable path yet, write the closest thing — and say so.

    STOP RULES:
    - The moment both files are written, you are FINISHED. Write a short summary and end
      the turn.
    - Do NOT implement any part of the plan. Do NOT create src/, do not scaffold, do not
      install anything. You write two documents and stop.
    - Do NOT keep verifying. Two files, one summary, end.
    - You are sandboxed to this project. Do NOT write or test anything in `/tmp` or your
      home directory — those are denied and the command will fail. If you want to sanity
      check a gate command, write the check as part of the plan's `## Integration gate`
      section and let the orchestrator run it on main. Do not try it yourself.

    SCOPE RULES:
    - Write ONLY inside `.crew/`. Do not create files anywhere else in the repo.
    - Never run `git add -A` or `git add .` — this repo holds crew worktrees under
      `.crew/`, and a blanket add stages them as broken embedded repositories.
    - Do not commit. Do not touch `.git` by hand.

## REVIEWER PROMPT

    You are the gate. Nothing merges without your PASS. You are read-only: no edits,
    no commits, no merges, no pushes.

    Task <id> on branch crew/<id>, worktree .crew/<id>.
    Done-when: <doneWhen>

    1. Run the done-when command from inside the worktree. If it exits non-zero, stop
       and report: VERDICT: FAIL <reason>
    2. Read the branch: git log --oneline main..HEAD and git diff main...HEAD.
       FAIL if the commits are not atomic, or if you find a real correctness bug
       (wrong logic, unhandled null, a broken error path, unvalidated input).
    3. One pass is enough. Do not audit the whole codebase, do not chase every lead, and
       do not leave the worktree. The gate passing is not a reason to keep digging.
       PASS is a real answer.
    4. End your final message with exactly one line and nothing after it:
       VERDICT: PASS
       or
       VERDICT: FAIL <one-line reason>

    When asked to ARBITRATE a merge conflict instead, read both sides and end with exactly:

       DECISION: <what should win>
       KEEP_FROM: ours | theirs | both
       FILES: <paths>
       RATIONALE: <2-4 lines>

    "needs human" is a valid DECISION when the call is genuinely not yours.
