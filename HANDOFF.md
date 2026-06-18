# Ralph Codex Handoff

## Current State

- Repo: `C:\Users\tianh\ralph-codex`
- Branch: `codex-support`
- Remote: `origin git@github.com:QiJi11/ralph-codex.git`
- Latest pushed commit: `69b4169 test: add ralph auto smoke regression`
- Working tree before this handoff file: clean and synced with `origin/codex-support`
- Ralph workspace project: `ralph-codex`
- `ReviewProject` status: active lock none, `Stories: 3`, `Unfinished: 0`, `Pending subtasks: 0`

## What Was Completed

1. Plan handoff and dirty continuation:
   - `ralph-auto` recognizes plan handoff phrases such as `RA 上面的内容` and `用 RA 跑刚才的 plan`.
   - Ordinary `RunProject` allows dirty continuation and records the dirty baseline.
   - Dirty continuation now propagates into `ralph.ps1` via `-AllowDirtyContinuation`, so child Codex stays on the current branch and does not require PRD `branchName` checkout.
   - `RunParallel` and real `CleanupContext` still require a clean worktree.

2. Subtask execution model:
   - Stories are normalized into subtasks.
   - `RunProject` plans and executes by subtask.
   - `RunParallel` selects parallel-safe subtasks, not whole stories.
   - Subtasks include dependency and conflict metadata: `dependsOn`, `parallelSafe`, `estimatedFiles`, `touches`, `stateWrites`, and `fileBudget`.

3. Safety and UX hardening:
   - Project-level locks cover write-capable RA commands.
   - `ReviewProject` shows lock state, dirty status, pending subtasks, and next-step hints when `prd.json` or `progress.txt` is missing.
   - Explicit subtasks fail planning when `estimatedFiles.Count > fileBudget`.
   - Final deliverables must be listed in `progress.txt` before completion is accepted.

4. Regression smoke:
   - Added `scripts\test-ra-smoke.ps1`.
   - The smoke validates missing-state review guidance, oversized subtask fail-fast, parallel dry-run selection, and dirty continuation runner dry-run.
   - README and WORKSPACE now document the smoke command.

## Pushed Commits

- `69b4169 test: add ralph auto smoke regression`
- `219f27f feat: harden ralph auto dirty continuation`
- `2c67c18 feat: support RA plan handoff and dirty continuation`
- `abdb676 feat: verify parallel RA and cleanup tasks`
- `1073e46 fix: resolve git on fresh Windows shells`

## Validation Already Run

Use PowerShell on Windows.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\Users\tianh\ralph-codex\scripts\test-ra-smoke.ps1
```

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\Users\tianh\ralph-codex\install-codex.ps1 -Force
```

```powershell
git -C C:\Users\tianh\ralph-codex diff --check
```

```powershell
npm --prefix C:\Users\tianh\ralph-codex\flowchart run build
```

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\Users\tianh\ralph-codex\ralph-auto.ps1 -Command ReviewProject -WorkspaceRoot C:\Users\tianh\RalphWorkspace -Project ralph-codex
```

Expected `ReviewProject` outcome:

- `Active lock: none`
- `Git status: clean`
- `Stories: 3`
- `Unfinished: 0`
- `Pending subtasks: 0`

## Important Files

- `ralph-auto.ps1`: workspace orchestration, project locks, review, dirty continuation, subtask planning, parallel selection.
- `ralph.ps1`: per-project Codex loop, subtask selection, dirty continuation runtime context, completion gates.
- `CODEX.md`: durable instructions for child Codex runs.
- `skills\ralph-auto\SKILL.md`: installed skill behavior contract.
- `scripts\test-ra-smoke.ps1`: RA regression smoke.
- `scripts\ralph\prd.json`: completed RA PRD state for this project.
- `scripts\ralph\progress.txt`: completed RA progress log.

## Known Notes

- `scripts\ralph\runs\`, `scripts\ralph\archive\`, and `scripts\ralph\.last-branch` are intentionally ignored.
- Installed Codex skill copies were synchronized with `install-codex.ps1 -Force`.
- If a new window continues work, first check:

```powershell
git -C C:\Users\tianh\ralph-codex status --short --branch
```

## Suggested Next Work

1. Open a PR or merge `codex-support` after review.
2. Optionally add CI wiring to run `scripts\test-ra-smoke.ps1` on Windows.
3. Optionally add targeted unit-like tests for `New-RalphAutoExecutionPlan` without creating full temporary git projects.
4. Optionally refine the auto-splitting heuristics so generated subtasks include more accurate `estimatedFiles`.
