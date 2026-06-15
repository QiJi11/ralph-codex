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

## Natural Language Entry

Open Codex in `RalphWorkspace` and say:

```text
Use Ralph Codex to run my-app for 10 iterations.
```

Codex should call:

```powershell
.\workspace.ps1 run -Project my-app -MaxIterations 10
```

## MVP Limits

- Local projects only.
- No automatic clone.
- No automatic task directory deletion.
- No queue or scheduler.
- Windows PowerShell is the primary supported workspace runner.
