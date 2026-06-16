---
name: run-ralph
description: "Run Ralph Codex from a workspace for a named project. Use when asked to run Ralph, continue Ralph, execute a Ralph task, or run a project from RalphWorkspace."
user-invocable: true
---

# Run Ralph From Workspace

Use this skill when the user asks to run Ralph for a named project from a workspace root.

## Job

1. Confirm the current directory is a Ralph workspace root with `workspace.ps1` and `projects.json`.
2. Identify the target project name from the user request.
3. If the project is not initialized, run:

```powershell
.\workspace.ps1 init-project -Project <project>
```

4. Run Ralph:

```powershell
.\workspace.ps1 run -Project <project> -MaxIterations 10
```

Use the user's requested iteration count when provided.

## Rules

- Do not run Ralph from the user profile root or another broad home directory.
- Do not guess across unrelated repositories; use `projects.json`.
- Do not edit `projects.json` unless the user asks to add or change a project.
- If the requested project is missing, show `.\workspace.ps1 list` output and ask for the correct project name.
- Treat `workspace.ps1` as the entrypoint; do not directly call project-level `scripts\ralph\ralph.ps1` unless `workspace.ps1` is unavailable.
- Ordinary `RunProject` may continue on a dirty worktree.
- `RunParallel` and non-dry-run `CleanupContext` still require a clean worktree.

## Natural Language Examples

User:

```text
用 Ralph 跑 my-app，最多 10 轮
```

Run:

```powershell
.\workspace.ps1 run -Project my-app -MaxIterations 10
```

User:

```text
继续 my-tool 的 Ralph 任务
```

Run:

```powershell
.\workspace.ps1 run -Project my-tool -MaxIterations 10
```
