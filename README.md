# Ralph Codex

![Ralph](ralph.webp)

Ralph Codex is an autonomous AI agent loop that runs fresh Codex CLI instances until all PRD items are complete. Memory persists through git history, `progress.txt`, `prd.json`, and per-iteration logs.

This fork is based on [snarktank/ralph](https://github.com/snarktank/ralph) and keeps the original Ralph pattern while adding Codex-first automation.

## Prerequisites

- [Codex CLI](https://github.com/openai/codex) installed and authenticated.
- A git repository for your target project.
- PowerShell 7+ on Windows, or Bash on macOS/Linux/WSL.
- Bash runner dependencies: `jq`, `sed`, `grep`, `tee`, and `seq`.
- Optional legacy tools:
  - [Amp CLI](https://ampcode.com)
  - [Claude Code](https://docs.anthropic.com/en/docs/claude-code)

## Setup

### Quick Start For Codex CLI

Clone this fork, install the skills and runner templates, then restart Codex:

```powershell
git clone https://github.com/QiJi11/ralph-codex
Set-Location ralph-codex
.\install-codex.ps1 -Force
```

After restart, ask Codex from any local project or Ralph workspace:

```text
用 RA 跑 inventory-app 的 CSV import MVP
```

The current supported surface is Codex CLI with local git repositories, PowerShell, and `RalphWorkspace`. Codex App/plugin support is not certified yet; see `APP.md` and `APP_VERIFY.md`.

### Install Into Codex

Install the PRD/Ralph skills and runner templates into your Codex home:

```powershell
.\install-codex.ps1 -Force
```

By default this installs to `$env:CODEX_HOME` when set, otherwise `%USERPROFILE%\.codex`:

- `skills\prd`
- `skills\ralph`
- `skills\run-ralph`
- `skills\ralph-auto`
- `vendor_imports\ralph-codex`

Restart Codex after installing so the skills are discovered.

### Add Ralph To A Project

Copy the Ralph files into your project:

```powershell
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE ".codex" }
$ralphVendor = Join-Path $codexHome "vendor_imports\ralph-codex"
New-Item -ItemType Directory -Force -Path scripts\ralph
Copy-Item (Join-Path $ralphVendor "ralph.ps1") scripts\ralph\
Copy-Item (Join-Path $ralphVendor "CODEX.md") scripts\ralph\
Copy-Item (Join-Path $ralphVendor "prd.json.example") scripts\ralph\
```

Commit these Ralph files before starting the autonomous loop so Codex iterations only commit story work and Ralph state updates.
Do not run directly from `prd.json.example`; generate `scripts\ralph\prd.json` with the `ralph` skill first.
Project-level `scripts\ralph\prd.json` and `scripts\ralph\progress.txt` should be committed as Ralph state.

For Bash-compatible environments:

```bash
mkdir -p scripts/ralph
cp ~/.codex/vendor_imports/ralph-codex/ralph.sh scripts/ralph/
cp ~/.codex/vendor_imports/ralph-codex/CODEX.md scripts/ralph/
cp ~/.codex/vendor_imports/ralph-codex/prd.json.example scripts/ralph/
chmod +x scripts/ralph/ralph.sh
```

Commit these Ralph files before starting the autonomous loop so Codex iterations only commit story work and Ralph state updates.
Do not run directly from `prd.json.example`; generate `scripts/ralph/prd.json` with the `ralph` skill first.
Project-level `scripts/ralph/prd.json` and `scripts/ralph/progress.txt` should be committed as Ralph state.

Ralph Auto adds a natural-language Codex path that can register projects in a workspace, prepare `scripts\ralph\prd.json`, and run Ralph from the project entrypoint. It is installed by `install-codex.ps1` with the other Codex skills and runner templates.

## Workflow

### Natural Language Ralph Auto

After installing Ralph Auto, ask Codex for the product outcome directly:

```text
用 RA 跑 inventory-app 的 CSV import MVP
```

`RA` is the short alias for Ralph Auto. It tells Codex to write the execution brief, prepare `scripts\ralph\prd.json`, and run Ralph from the workspace entrypoint.

For a registered project, Codex uses the workspace registry at `C:\Users\<current-user>\RalphWorkspace\projects.json`, generates or updates the PRD, converts it to `scripts\ralph\prd.json`, and runs:

```powershell
& "$env:CODEX_HOME\vendor_imports\ralph-codex\ralph-auto.ps1" -Command RunProject -WorkspaceRoot 'C:\Users\<current-user>\RalphWorkspace' -Project 'inventory-app' -MaxIterations 10
```

For an unregistered local git project, include the path once:

```text
用 RA 跑 D:\AtoC\文档\reporting-app 的 reporting MVP
```

Codex registers the path, initializes Ralph files if needed, prepares `scripts\ralph\prd.json`, then runs the same workspace entrypoint.

Before running Ralph, Codex should state the execution brief: project, goal, assumptions, story list, acceptance checks, and max iterations. If scope or acceptance needs to change, Codex should stop and ask the user instead of silently changing the plan.

RA may use parallel subagents for read-only review, but the main RA flow owns all writes to `scripts\ralph\prd.json`, `scripts\ralph\progress.txt`, project files, and git commits. Use the helper to inspect a registered project without changing files:

```powershell
& "$env:CODEX_HOME\vendor_imports\ralph-codex\ralph-auto.ps1" -Command ReviewProject -WorkspaceRoot 'C:\Users\<current-user>\RalphWorkspace' -Project 'inventory-app'
```

For write-capable multi-agent work, say `用 RA 并行跑 ...`. Parallel mode uses isolated git worktrees and only runs stories marked `parallelSafe: true` with satisfied `dependsOn`:

```powershell
& "$env:CODEX_HOME\vendor_imports\ralph-codex\ralph-auto.ps1" -Command RunParallel -WorkspaceRoot 'C:\Users\<current-user>\RalphWorkspace' -Project 'inventory-app' -MaxWorkers 2 -MaxIterations 3
```

Use `-DryRun` to preview selected stories, worktree paths, and branches before workers start. If a worker fails or a merge conflicts, RA preserves the worktrees and stops for human review.

Ralph builds Codex prompts with stable instructions first and runtime details last. Keep `CODEX.md` focused on durable rules; put changing facts such as current story details, timestamps, logs, and paths in `scripts\ralph\prd.json` or `progress.txt` instead of editing `CODEX.md` each run. Parallel workers share the same stable prefix and only differ in the runtime tail.

### 1. Create a PRD

Use the `prd` skill to generate a detailed requirements document:

```text
Load the prd skill and create a PRD for [your feature description]
```

The skill saves output to `tasks/prd-[feature-name].md`.

### 2. Convert PRD to Ralph format

Use the `ralph` skill to convert the markdown PRD to JSON:

```text
Load the ralph skill and convert tasks/prd-[feature-name].md to scripts/ralph/prd.json
```

This creates `prd.json` with user stories structured for autonomous execution.

## Workspace MVP

Use a Ralph workspace when you want one root folder to manage multiple local projects.

Recommended layout:

```text
RalphWorkspace\
  projects.json
  workspace.ps1
  projects\
  tasks\
  archive\
```

Initialize a workspace:

```powershell
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE ".codex" }
Copy-Item (Join-Path $codexHome "vendor_imports\ralph-codex\workspace.ps1") .
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

Natural language entry from the workspace root:

```text
Use Ralph Codex to run my-app for 10 iterations.
```

### 3. Run Ralph with Codex

Windows PowerShell:

```powershell
.\scripts\ralph\ralph.ps1 -MaxIterations 10 -ProjectRoot .
```

Bash, WSL, macOS, or Linux:

```bash
./scripts/ralph/ralph.sh --tool codex 10
```

Ralph will:

1. Read `prd.json`.
2. Create or switch to the feature branch from PRD `branchName`.
3. Pick the highest priority story where `passes: false`.
4. Implement that single story in a fresh Codex CLI context.
5. Run quality checks.
6. Commit if checks pass.
7. Update `prd.json` to mark the story as `passes: true`.
8. Append learnings to `progress.txt`.
9. Repeat until all stories pass or max iterations is reached.

## Key Files

- `ralph.ps1` - PowerShell Codex runner for Windows.
- `ralph.sh` - Bash runner for Codex, Amp, or Claude Code.
- `ralph-auto.ps1` - PowerShell workspace helper for natural-language Ralph Auto runs.
- `CODEX.md` - Instructions given to each Codex CLI instance.
- `prompt.md` - Legacy prompt template for Amp.
- `CLAUDE.md` - Legacy prompt template for Claude Code.
- `prd.json` - Generated user stories with `passes` status.
- `prd.json.example` - Example PRD format.
- `progress.txt` - Append-only learnings for future iterations.
- `runs/` - Generated per-iteration logs.
- `skills/prd/` - Skill for generating PRDs.
- `skills/ralph/` - Skill for converting PRDs to JSON.
- `skills/run-ralph/` - Skill for running a named project from a Ralph workspace.
- `skills/ralph-auto/` - Skill for natural-language Ralph Auto workflow requests.
- `workspace.ps1` - Workspace runner for multiple local projects.
- `workspace.example.json` - Example workspace project registry.
- `WORKSPACE.md` - Workspace usage guide.
- `.codex-plugin/` - Optional Codex plugin manifest.
- `.claude-plugin/` - Legacy Claude Code marketplace manifest.
- `flowchart/` - Interactive visualization of how Ralph works.

## Critical Concepts

### Each Iteration Has Fresh Context

Each iteration launches a new Codex CLI process. The only memory between iterations is:

- Git history.
- `progress.txt`.
- `prd.json`.
- `runs/` logs.
- Updated `AGENTS.md` files.

### Small Tasks

Each PRD item should be small enough to complete in one context window.

Right-sized stories:

- Add a database column and migration.
- Add a UI component to an existing page.
- Update one server action.
- Add a filter dropdown to a list.

Too large:

- Build the entire dashboard.
- Add authentication.
- Refactor the whole API.

### Feedback Loops

Ralph only works if there are checks Codex can run:

- Typecheck catches type errors.
- Tests verify behavior.
- Build catches integration issues.
- Browser verification catches UI regressions when browser tools are available.

### Stop Condition

When all stories have `passes: true`, Codex outputs:

```text
<promise>COMPLETE</promise>
```

The runner exits successfully when it sees that signal.

## Debugging

PowerShell:

```powershell
Get-Content .\scripts\ralph\prd.json -Raw | ConvertFrom-Json | Select-Object -ExpandProperty userStories | Select-Object id,title,passes
Get-Content .\scripts\ralph\progress.txt
Get-ChildItem .\scripts\ralph\runs
git log --oneline -10
```

Bash:

```bash
cat scripts/ralph/prd.json | jq '.userStories[] | {id, title, passes}'
cat scripts/ralph/progress.txt
ls scripts/ralph/runs
git log --oneline -10
```

## Legacy Tool Support

The Bash runner still supports the original tools:

```bash
./scripts/ralph/ralph.sh --tool amp 10
./scripts/ralph/ralph.sh --tool claude 10
```

PowerShell support is Codex-only.

## References

- [Original Ralph project](https://github.com/snarktank/ralph)
- [Geoffrey Huntley's Ralph article](https://ghuntley.com/ralph/)
- [Codex CLI](https://github.com/openai/codex)
- [Codex App support status](APP.md)
- [Codex App verification checklist](APP_VERIFY.md)
- [CLI verification checklist](VERIFY.md)
