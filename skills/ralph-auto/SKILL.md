---
name: ralph-auto
description: "Run the natural-language Ralph autonomous workflow for product implementation requests. Use when the user says RA, Ralph Auto, run with RA, or asks to create, build, implement, complete, run, ship, or execute an MVP, feature, app, project, or autonomous Ralph workflow."
user-invocable: true
---

# Ralph Auto

Turn a natural-language product request into a Ralph workspace run.

Use this skill when the user asks Codex to create, build, implement, complete, run, ship, or iterate on a feature, MVP, app, project, or autonomous Ralph workflow, and they have not already provided a fully prepared `scripts\ralph\prd.json`.

Treat `RA`, `ra`, `Ralph Auto`, and `ralph-auto` as the same trigger. Also treat these as direct Plan Handoff triggers when they refer to the immediately preceding plan:

- `RA 上面的内容`
- `用 RA 跑刚才的 plan`
- `把上面的计划转成 RA 跑`
- `RA 执行刚才的计划`

Recommended user phrase:

```text
用 RA 跑 <project> 的 <task>
```

Use explicit parallel mode when the user says `并行`, `parallel`, asks for multiple RA agents, or asks for isolated parallel execution. Ordinary `RunProject` may also auto-delegate to `RunParallel` when the worktree is clean and execution planning finds a safe non-conflicting batch. If the same project already has an active write-capable RA lock, ordinary `RunProject` automatically falls back to `RunProjectIsolated`, which creates a separate git worktree with independent `scripts\ralph` state:

```text
用 RA 并行跑 <project> 的 <task>
```

## Defaults

- Default workspace: `C:\Users\<current-user>\RalphWorkspace`
- Default shell: Windows PowerShell (`pwsh`)
- Prefer PowerShell commands and `.ps1` helpers. Avoid bash-only commands.
- Do not run Ralph directly from a user profile directory; run it through a workspace project entrypoint.
- Use the current directory only when it is clearly the target project and no workspace/project name is specified.
- `RunProject` allows dirty continuation for the current baseline.
- `RunProjectIsolated` allows multiple independent PRDs for the same registered project by creating an isolated worktree and isolated Ralph state.
- `RunParallel` requires a clean worktree because it creates worktrees, commits, and merges.
- `CleanupContext` requires a clean worktree unless it is `-DryRun`.
- Write-capable commands that share the main project state are project-locked. `RunProjectIsolated` may run beside another same-project RA because it does not write the main project's `scripts\ralph\prd.json` or `progress.txt`.

## Required Flow

1. Identify the target project and workspace.
2. Write a short execution brief before running Ralph.
3. Run optional read-only review before execution when useful.
4. Generate or update a concise PRD for the requested work, including converting the immediately preceding plan when using Plan Handoff.
5. Convert the PRD into `scripts\ralph\prd.json`.
6. Run Ralph through the workspace entrypoint for that project.
7. Report the project, workspace, PRD path, and Ralph command used.
8. If the task produces final files, report every final deliverable path in the user-visible final response.

## Execution Brief

Before starting Ralph, state the execution contract:

- Project
- User goal
- Assumptions
- Story list
- Acceptance checks
- Max iterations

Do not silently change scope, acceptance criteria, project, branch, or max iterations after the brief is set. If the work is blocked, infeasible, too broad, or needs changed criteria, stop and ask the user instead of rewriting the plan yourself.

## Parallel Agent Policy

Use read-only subagents freely for review, investigation, and validation. Use write-capable parallel RA workers only through `RunParallel`, which creates isolated git worktrees.

Safe parallel tasks:

- Inspect the codebase for relevant files and patterns.
- Review the execution brief for missing checks.
- Inspect current Ralph state with `ReviewProject`.
- Review logs and summarize blockers.

Unsafe parallel tasks for read-only subagents:

- Editing project files.
- Editing Ralph state files.
- Running `RunProject` from the subagent itself.
- Committing, merging, rebasing, or pushing.

For a local read-only review, run:

```powershell
.\ralph-auto.ps1 -Command ReviewProject -WorkspaceRoot 'C:\Users\<current-user>\RalphWorkspace' -Project 'my-app'
```

## Parallel Write Mode

Only use `RunParallel` after the PRD exists and stories intended for parallel execution have:

```json
{
  "parallelSafe": true,
  "dependsOn": []
}
```

RunParallel defaults to 2 workers:

```powershell
.\ralph-auto.ps1 -Command RunParallel -WorkspaceRoot 'C:\Users\<current-user>\RalphWorkspace' -Project 'my-app' -MaxWorkers 2 -MaxIterations 3
```

Rules:

- The main project worktree must be clean before starting.
- Each worker gets a separate git worktree under `RalphWorkspace\tasks`.
- Each worker receives a PRD containing only its assigned subtask and parent story context.
- Main RA merges successful worker branches back into the project.
- If a worker fails or a merge conflicts, stop and ask the user; do not rewrite the plan.
- Use `-DryRun` before risky or user-requested parallel runs to show selected subtasks and worktree paths.
- `RunParallel` still takes the project lock for the duration of the write-capable run.

## Dirty Continuation Policy

Use ordinary `RunProject` when the project is already dirty and the user is continuing the same line of work, including `继续 RA`, `RA 上面的内容`, and `用 RA 跑刚才的 plan`.

Rules:

- Do not ask the user to commit first for ordinary continuation.
- Do not switch branches.
- Do not auto-commit the baseline.
- Do not upgrade a dirty run into `RunParallel`.
- Record the dirty baseline in the execution brief and `scripts\ralph\progress.txt`.
- Pass dirty continuation into the Ralph runner so the child Codex process stays on the current branch and does not require PRD `branchName` checkout for that run.
- If another same-project RA is already active and the new task is a separate PRD, use `RunProjectIsolated` instead of terminating the old RA or overwriting main-project Ralph state.

If the user explicitly asks for isolation, parallel execution, auto-commit, or merge-based fanout while the project is dirty, stop and ask them to commit, stash, or switch back to ordinary `RunProject`.

## Same-Project Isolated Runs

Use `RunProjectIsolated` when the same registered project already has an active RA run but the user wants to start a separate independent task:

```powershell
.\ralph-auto.ps1 -Command RunProjectIsolated -WorkspaceRoot 'C:\Users\<current-user>\RalphWorkspace' -Project 'my-app' -PrdPath 'C:\path\to\new-prd.json' -MaxIterations 10
```

Rules:

- The isolated run creates `RalphWorkspace\tasks\<project>\<runId>\main`.
- The isolated worktree has its own `scripts\ralph\prd.json`, `progress.txt`, and `.run-lock.json`.
- Do not overwrite the main project's PRD while another same-project RA is active.
- Isolated runs leave their branch unmerged by default; use `-MergeOnSuccess` only when the main worktree is clean and automatic merge is explicitly intended.
- Report the isolated worktree, branch, PRD, and progress paths in the final response.

## Final Deliverables

For any task that creates, edits, repairs, or exports final user-facing files:

- Report every final deliverable path in the final user-facing response.
- Record the same paths in `scripts\ralph\progress.txt`.
- List only true deliverables, not temporary renders, QA PNGs, scratch scripts, or caches, unless the plan explicitly says to deliver those too.

This rule applies to document, spreadsheet, presentation, export, patch, and other file-producing stories, not only DOCX work.

## Prompt Cache Hygiene

Ralph places stable `CODEX.md` instructions before runtime-specific context. Keep durable rules in `CODEX.md`, and put changing details in `scripts\ralph\prd.json`, `progress.txt`, or the execution brief. Do not rewrite `CODEX.md` for each run unless the durable operating rules actually changed.

## Project Resolution

### Existing Registered Project

Use this flow when the user names a project that is already registered in the workspace.

1. Use the registered project path from the workspace registry.
2. Read any existing project docs and Ralph files.
3. Generate or update the PRD in that project.
4. Convert it to `scripts\ralph\prd.json`.
5. Run the workspace entrypoint for the registered project.

### Unregistered Local Git Path

Use this flow when the user gives a local path or the current directory is clearly a git project but it is not registered.

1. Confirm the path is a git working tree.
2. Register the project in `C:\Users\<current-user>\RalphWorkspace`.
3. Initialize Ralph files for the project if they are missing.
4. Generate or update the PRD.
5. Convert it to `scripts\ralph\prd.json`.
6. Run the workspace entrypoint for the new registration.

### Missing Project Name

Use this flow when the request describes work but does not identify a project.

1. Check whether the current directory is a git project and can be used as the target.
2. If the request is a Plan Handoff trigger and the current directory is not a git project, create an ad-hoc project at `C:\Users\<current-user>\RalphWorkspace\projects\ra-adhoc-YYYYMMDD-HHMMSS`.
3. Register the ad-hoc project, initialize Ralph files, and write `scripts\ralph\prd.json` plus `progress.txt`.
4. If it is not a Plan Handoff request and the current directory is not clearly the target, ask one short blocking question for the project name or local git path.
5. After the project is known, follow the registered, unregistered, or ad-hoc project flow.

## Plan Handoff

When the user says `RA 上面的内容`, `用 RA 跑刚才的 plan`, `把上面的计划转成 RA 跑`, or `RA 执行刚才的计划`:

1. Use the immediately preceding plan as the source of truth.
2. Prefer the current directory if it is a git project.
3. If the user names a registered project, use the workspace registration.
4. If there is no git project and no project name, create an ad-hoc project with:

```powershell
.\ralph-auto.ps1 -Command CreateAdhocProject -WorkspaceRoot 'C:\Users\<current-user>\RalphWorkspace'
```

5. Convert the plan into `scripts\ralph\prd.json`.
6. Initialize `scripts\ralph\progress.txt` if it is missing.
7. Run:

```powershell
.\ralph-auto.ps1 -Command RunProject -WorkspaceRoot 'C:\Users\<current-user>\RalphWorkspace' -Project '<resolved-project>' -MaxIterations 10
```

## PRD Rules

- Keep stories small enough for one Ralph iteration each.
- Default to subtasks as the true execution unit. A story may contain multiple subtasks, but each subtask must be completable in one Ralph iteration.
- Order stories by dependency.
- Add verifiable acceptance criteria, including required checks such as typecheck, tests, build, or browser verification for UI work.
- Set every new story to `"passes": false`.
- Use a feature branch name under `ralph/`.
- If a story is still broad, split it before execution into subtasks with `dependsOn`, `parallelSafe`, `touches`, `stateWrites`, and `fileBudget`.
- If an explicit subtask has more `estimatedFiles` than `fileBudget`, execution planning fails and the subtask must be split before running RA.
- If safe independent subtasks exist and the project worktree is clean, prefer automatic parallel execution over manual serial execution.

## PowerShell Examples

Initialize a workspace:

```powershell
.\ralph-auto.ps1 -Command InitWorkspace -WorkspaceRoot 'C:\Users\<current-user>\RalphWorkspace'
```

List registered projects:

```powershell
.\ralph-auto.ps1 -Command ListProjects -WorkspaceRoot 'C:\Users\<current-user>\RalphWorkspace'
```

Register a local git project:

```powershell
.\ralph-auto.ps1 -Command AddProject -WorkspaceRoot 'C:\Users\<current-user>\RalphWorkspace' -Project 'my-app' -ProjectPath 'D:\AtoC\Documents\my-app'
```

Create an ad-hoc project for plan handoff from a non-git directory:

```powershell
.\ralph-auto.ps1 -Command CreateAdhocProject -WorkspaceRoot 'C:\Users\<current-user>\RalphWorkspace'
```

Run Ralph for a workspace project:

```powershell
.\ralph-auto.ps1 -Command RunProject -WorkspaceRoot 'C:\Users\<current-user>\RalphWorkspace' -Project 'my-app' -MaxIterations 10
```
