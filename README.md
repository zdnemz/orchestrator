# orchestrator

A single opencode command that takes a goal and drives it to done: interviews you, plans
the work into a task DAG, builds tasks **in parallel** in isolated git worktrees, reviews
each one, merges serially, and loops until the goal holds on `main`.

Two human touches per run: approve the plan, read the final report.

```
/orchestrator build me a 5-page marketing site for my coffee shop
```

## Install

```bash
git clone https://github.com/zdnemz/orchestrator.git
cd orchestrator
./install.sh
```

That copies `commands/orchestrator.md` into `~/.config/opencode/commands/`.
Restart opencode, then run `/orchestrator <goal>`.

Requirements:

- [opencode](https://opencode.ai) with `subagent` support (built in)
- `git`
- optional: the `interview-me` skill. The command falls back to built-in interview rules
  when the skill is absent.

The subagent model is whatever your `general` agent resolves to. To pin it, set the model
on `general` in `opencode.json` — this repo does not ship a model choice.

## What it does

1. **Interviews you** — one question at a time, until it knows who the work is for, why
   now, what success looks like, and the binding constraint. Writes `.crew/BRIEF.md`.
2. **Plans** — a planner worker writes `.crew/PRD.md` and `.crew/implementation_plan.md`,
   including a frozen `## Shared contract` and an `## Integration gate`.
3. **Builds in parallel** — up to 4 coder workers at once, each in its own git worktree
   on its own branch. A task starts only when every dependency is **merged** into main.
4. **Reviews** — a read-only reviewer runs the task's gate and reads the diff. PASS/FAIL.
5. **Merges serially** — `git merge --no-ff`, then the gate re-runs on main. Red = revert.
6. **Loops** — recomputes the ready set and keeps going. Plan exhausted but goal unmet?
   It plans another wave. Max 5 waves.
7. **Cleans up** — worktrees removed, `crew/*` branches deleted, `.crew/` deleted.

## The `.crew/` folder

Everything a run generates lives there and nothing else:

```
.crew/
  BRIEF.md      interview output
  PRD.md        what and why
  implementation_plan.md
  progress.md   state journal (the orchestrator's memory)
  T1/ T2/ ...   one worktree per task
```

It is hidden with `.git/info/exclude`, **not** `.gitignore` — your repo's diffs stay clean
and no plumbing file is ever committed. A worktree inside a repo is an embedded git repo;
without that exclude the first `git add -A` stages it as a broken gitlink.

Portable, but note: a git worktree cannot be created inside its own repo root if the path
is tracked. The exclude handles it.

## Why the shared contract exists

Parallel workers cannot see each other. If two tasks must agree on a name — a file path, a
link target, an export, a CSS class — the plan has to pin it before they start.

Without it, every worker guesses independently and all their gates pass while the assembled
product is broken. This actually happened in testing: three pages linked to `index.html`
while the home task created `home.html`. Four green gates, one unusable site.

So the planner must write `## Shared contract` first, each coder receives the rows that
touch its task, and the plan must ship an `## Integration gate` that exercises the seams.

## Bounded, so it cannot spin

| limit | value |
|---|---|
| waves | 5 |
| planner calls per wave | 2 |
| attempts per task | 2 (provider errors do not count) |
| consecutive waves with zero merges | 2, then stop |
| concurrent workers | 4 |

A parked task does not block unrelated work, but it does block its dependents. Every parked
task appears in the final report with its reason and what would unblock it.

## Files

```
commands/orchestrator.md   the entire system — loop, rules, and worker prompts
install.sh                 copies the command into your opencode config
check.sh                   validates the command and the installer
docs/design.md             architecture and known limits
```

## Verify

```bash
./check.sh
```

Checks the command's frontmatter and required sections, the rules that carry the system,
balanced code fences, that no machine-specific path or provider pin leaked in, and that
`install.sh` actually installs an identical copy. Runs in CI on every push.

## License

MIT — see [LICENSE](LICENSE).

## Known limits

- **The loop lives in the model, not in code.** A prompt-driven orchestrator can drift.
  State is on disk in `.crew/progress.md`, so a restart or context compaction resumes
  rather than restarts, but a run is only as disciplined as the model driving it.
- **The gate is prompt-enforced.** Nothing in code stops two tasks being spawned against
  an unfrozen interface. The failure shows up as a merge conflict or a review FAIL.
- **Serial merges.** Deliberate: main has to stay green after every merge.
- **Worktrees need a git repo.** The command will `git init` one if needed, in the current
  directory only.
