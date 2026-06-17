# Ralph Workspace MVP

Ralph Workspace lets one root folder manage multiple local projects while still running Ralph inside the selected project.

## Recommended Layout

```text
RalphWorkspace\
  projects.json
  workspace.ps1
  projects\
  tasks\
  archive\
```

- `RalphWorkspace` is the control room. Keep it.
- `projects` contains long-lived local git repositories.
- `tasks` is reserved for future temporary worktrees or clones.
- `archive` is reserved for completed task logs and PRD snapshots.

## Natural Language Entry

Use `ralph-auto` as the recommended natural-language Codex entrypoint for workspace-based Ralph runs.

For a registered project, ask Codex for the outcome:

```text
用 RA 跑 inventory-app 的 CSV import MVP
```

`RA` is the short alias for Ralph Auto. It should trigger the same workflow as saying `Ralph Auto`.

For an unregistered local git project, include the path once:

```text
用 RA 跑 D:\AtoC\文档\admin-app 的 admin dashboard MVP
```

Codex should generate or update the PRD, convert it to `scripts\ralph\prd.json`, then run the workspace helper:

```powershell
.\ralph-auto.ps1 -Command RunProject -WorkspaceRoot 'C:\Users\<current-user>\RalphWorkspace' -Project 'inventory-app' -MaxIterations 10
```

Before running Ralph, Codex should state the execution brief: project, goal, assumptions, story list, acceptance checks, and max iterations. If the scope, checks, or iteration budget need to change, Codex should stop and ask the user.

RA can use parallel subagents for read-only review, but only the main RA flow should write project files, Ralph state, or git commits.

Ordinary `RunProject` can continue a dirty baseline. In that mode it stays on the current branch, records the baseline in `progress.txt`, and tells the runner not to enforce PRD `branchName` checkout for that run.

For write-capable multi-agent runs, use `用 RA 并行跑 ...` or let RA auto-detect a safe parallel batch. Parallel mode creates isolated git worktrees under `RalphWorkspace\tasks` and runs subtasks marked `parallelSafe: true` with satisfied `dependsOn` and non-conflicting file/state surfaces.

Ralph prompts are cache-friendly by design: stable instructions from `CODEX.md` are placed before runtime-specific values. Keep `CODEX.md` stable across runs, and put changing story details, logs, timestamps, and paths in `scripts\ralph\prd.json` or `progress.txt`.

## Setup

Initialize the workspace:

```powershell
.\workspace.ps1 init
```

Register an existing local git project:

```powershell
.\workspace.ps1 add-project -Name my-app -Path C:\path\to\my-app
```

On a new computer, register each real project again with its new local path. Do not copy `projects.json` entries from another machine, because old absolute paths will not be valid. Registered project paths must be git repositories.

Install Ralph into that project:

```powershell
.\workspace.ps1 init-project -Project my-app
```

Run Ralph for that project:

```powershell
.\workspace.ps1 run -Project my-app -MaxIterations 10
```

## Ralph Auto Helper

The helper provides the same workspace actions with one stable entrypoint:

```powershell
.\ralph-auto.ps1 -Command InitWorkspace -WorkspaceRoot 'C:\Users\<current-user>\RalphWorkspace'
.\ralph-auto.ps1 -Command AddProject -WorkspaceRoot 'C:\Users\<current-user>\RalphWorkspace' -Project 'inventory-app' -ProjectPath 'D:\AtoC\文档\inventory-app'
.\ralph-auto.ps1 -Command ReviewProject -WorkspaceRoot 'C:\Users\<current-user>\RalphWorkspace' -Project 'inventory-app'
.\ralph-auto.ps1 -Command RunProject -WorkspaceRoot 'C:\Users\<current-user>\RalphWorkspace' -Project 'inventory-app' -MaxIterations 10
.\ralph-auto.ps1 -Command RunParallel -WorkspaceRoot 'C:\Users\<current-user>\RalphWorkspace' -Project 'inventory-app' -MaxWorkers 2 -MaxIterations 3 -DryRun
```

`RunParallel -DryRun` is the minimum safe smoke check for parallel mode. It should print selected subtask IDs, branch names, and worktree paths without creating worktrees or launching workers. If no subtask is ready, it should return a clear validation error explaining that subtasks need `parallelSafe: true`, satisfied `dependsOn`, and non-conflicting file/state surfaces.

Planning fails before execution when an explicit subtask lists more `estimatedFiles` than its `fileBudget`. Split that subtask into smaller work before running RA.

Run the RA smoke suite before and after changing workspace orchestration:

```powershell
.\scripts\test-ra-smoke.ps1
```

Preview Ralph context cleanup without changing files:

```powershell
.\ralph-auto.ps1 -Command CleanupContext -WorkspaceRoot 'C:\Users\<current-user>\RalphWorkspace' -Project 'inventory-app' -KeepLastRuns 5 -DryRun
```

`CleanupContext` preserves the current `scripts\ralph\prd.json`, refuses real cleanup when the project worktree is dirty, and can archive `progress.txt` with `-ArchiveProgress`.

## MVP Limits

- Local projects only.
- No automatic clone.
- No automatic task directory deletion.
- No queue or scheduler.
- Windows PowerShell is the primary supported workspace runner.
