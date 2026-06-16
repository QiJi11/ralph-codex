---
name: ralph-auto
description: "Run the natural-language Ralph autonomous workflow for product implementation requests. Use when the user says RA, Ralph Auto, run with RA, or asks to create, build, implement, complete, run, ship, or execute an MVP, feature, app, project, or autonomous Ralph workflow."
user-invocable: true
---

# Ralph Auto

Turn a natural-language product request into a Ralph workspace run.

Use this skill when the user asks Codex to create, build, implement, complete, run, ship, or iterate on a feature, MVP, app, project, or autonomous Ralph workflow, and they have not already provided a fully prepared `scripts\ralph\prd.json`.

Treat `RA`, `ra`, `Ralph Auto`, and `ralph-auto` as the same trigger. Recommended user phrase:

```text
用 RA 跑 <project> 的 <task>
```

Use parallel mode only when the user explicitly says `并行`, `parallel`, or asks for multiple RA agents:

```text
用 RA 并行跑 <project> 的 <task>
```

## Defaults

- Default workspace: `C:\Users\<current-user>\RalphWorkspace`
- Default shell: Windows PowerShell (`pwsh`)
- Prefer PowerShell commands and `.ps1` helpers. Avoid bash-only commands.
- Do not run Ralph directly from a user profile directory; run it through a workspace project entrypoint.
- Use the current directory only when it is clearly the target project and no workspace/project name is specified.

## Required Flow

1. Identify the target project and workspace.
2. Write a short execution brief before running Ralph.
3. Run optional read-only review before execution when useful.
4. Generate or update a concise PRD for the requested work.
5. Convert the PRD into `scripts\ralph\prd.json`.
6. Run Ralph through the workspace entrypoint for that project.
7. Report the project, workspace, PRD path, and Ralph command used.

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

Unsafe parallel tasks:

- Editing project files.
- Editing Ralph state files.
- Running `RunProject`.
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
- Each worker receives a PRD containing only its assigned story.
- Main RA merges successful worker branches back into the project.
- If a worker fails or a merge conflicts, stop and ask the user; do not rewrite the plan.
- Use `-DryRun` before risky parallel runs to show selected stories and worktree paths.

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
2. If the current directory is not clearly the target, ask one short blocking question for the project name or local git path.
3. After the project is known, follow the registered or unregistered project flow.

## PRD Rules

- Keep stories small enough for one Ralph iteration each.
- Order stories by dependency.
- Add verifiable acceptance criteria, including required checks such as typecheck, tests, build, or browser verification for UI work.
- Set every new story to `"passes": false`.
- Use a feature branch name under `ralph/`.

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

Run Ralph for a workspace project:

```powershell
.\ralph-auto.ps1 -Command RunProject -WorkspaceRoot 'C:\Users\<current-user>\RalphWorkspace' -Project 'my-app' -MaxIterations 10
```
