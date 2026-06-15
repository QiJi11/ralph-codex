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
Build the CSV import MVP for inventory-app with Ralph Auto.
```

For an unregistered local git project, include the path once:

```text
Implement the admin dashboard MVP in D:\AtoC\文档\admin-app with Ralph Auto.
```

Codex should generate or update the PRD, convert it to `scripts\ralph\prd.json`, then run the workspace helper:

```powershell
.\ralph-auto.ps1 -Command RunProject -WorkspaceRoot 'C:\Users\10531\RalphWorkspace' -Project 'inventory-app' -MaxIterations 10
```

## Setup

Initialize the workspace:

```powershell
.\workspace.ps1 init
```

Register an existing local git project:

```powershell
.\workspace.ps1 add-project -Name my-app -Path C:\path\to\my-app
```

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
.\ralph-auto.ps1 -Command InitWorkspace -WorkspaceRoot 'C:\Users\10531\RalphWorkspace'
.\ralph-auto.ps1 -Command AddProject -WorkspaceRoot 'C:\Users\10531\RalphWorkspace' -Project 'inventory-app' -ProjectPath 'D:\AtoC\文档\inventory-app'
.\ralph-auto.ps1 -Command RunProject -WorkspaceRoot 'C:\Users\10531\RalphWorkspace' -Project 'inventory-app' -MaxIterations 10
```

## MVP Limits

- Local projects only.
- No automatic clone.
- No automatic task directory deletion.
- No queue or scheduler.
- Windows PowerShell is the primary supported workspace runner.
