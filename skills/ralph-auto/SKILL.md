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

## Defaults

- Default workspace: `C:\Users\10531\RalphWorkspace`
- Default shell: Windows PowerShell (`pwsh`)
- Prefer PowerShell commands and `.ps1` helpers. Avoid bash-only commands.
- Do not run Ralph directly from `C:\Users\10531`; run it through a workspace project entrypoint.
- Use the current directory only when it is clearly the target project and no workspace/project name is specified.

## Required Flow

1. Identify the target project and workspace.
2. Write a short execution brief before running Ralph.
3. Generate or update a concise PRD for the requested work.
4. Convert the PRD into `scripts\ralph\prd.json`.
5. Run Ralph through the workspace entrypoint for that project.
6. Report the project, workspace, PRD path, and Ralph command used.

## Execution Brief

Before starting Ralph, state the execution contract:

- Project
- User goal
- Assumptions
- Story list
- Acceptance checks
- Max iterations

Do not silently change scope, acceptance criteria, project, branch, or max iterations after the brief is set. If the work is blocked, infeasible, too broad, or needs changed criteria, stop and ask the user instead of rewriting the plan yourself.

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
2. Register the project in `C:\Users\10531\RalphWorkspace`.
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
.\ralph-auto.ps1 -Command InitWorkspace -WorkspaceRoot 'C:\Users\10531\RalphWorkspace'
```

List registered projects:

```powershell
.\ralph-auto.ps1 -Command ListProjects -WorkspaceRoot 'C:\Users\10531\RalphWorkspace'
```

Register a local git project:

```powershell
.\ralph-auto.ps1 -Command AddProject -WorkspaceRoot 'C:\Users\10531\RalphWorkspace' -Project 'my-app' -ProjectPath 'D:\AtoC\文档\my-app'
```

Run Ralph for a workspace project:

```powershell
.\ralph-auto.ps1 -Command RunProject -WorkspaceRoot 'C:\Users\10531\RalphWorkspace' -Project 'my-app' -MaxIterations 10
```
