# Ralph Agent Instructions

## Overview

Ralph is an autonomous AI agent loop that runs AI coding tools (Codex CLI, Amp, or Claude Code) repeatedly until all PRD items are complete. Each iteration is a fresh instance with clean context.

## Commands

```bash
# Run the flowchart dev server
cd flowchart && npm run dev

# Build the flowchart
cd flowchart && npm run build

# Run Ralph with Codex CLI on Windows PowerShell
.\ralph.ps1 -MaxIterations 10

# Run Ralph with Codex CLI from Bash
./ralph.sh [max_iterations]

# Run Ralph with Amp
./ralph.sh --tool amp [max_iterations]

# Run Ralph with Claude Code
./ralph.sh --tool claude [max_iterations]
```

## Key Files

- `ralph.ps1` - The PowerShell loop that spawns fresh Codex CLI instances on Windows
- `ralph.sh` - The bash loop that spawns fresh AI instances (supports `--tool codex`, `--tool amp`, or `--tool claude`)
- `CODEX.md` - Instructions given to each Codex CLI instance
- `prompt.md` - Instructions given to each AMP instance
- `CLAUDE.md` - Instructions given to each Claude Code instance
- `prd.json.example` - Example PRD format
- `runs/` - Generated per-iteration logs
- `flowchart/` - Interactive React Flow diagram explaining how Ralph works

## Flowchart

The `flowchart/` directory contains an interactive visualization built with React Flow. It's designed for presentations - click through to reveal each step with animations.

To run locally:
```bash
cd flowchart
npm install
npm run dev
```

## Patterns

- Each iteration spawns a fresh AI instance with clean context
- Memory persists via git history, `progress.txt`, `prd.json`, and generated logs
- Stories should be small enough to complete in one context window
- Always update AGENTS.md with discovered patterns for future iterations
- `ralph-auto.ps1` is the PowerShell-first workspace entrypoint; it stores project registrations in `<WorkspaceRoot>\projects.json`.
- Ralph Auto resolves vendor imports from `CODEX_HOME\vendor_imports\ralph-codex`, falling back to `%USERPROFILE%\.codex\vendor_imports\ralph-codex`.
- `install-codex.ps1` installs `ralph-auto.ps1` to `vendor_imports\ralph-codex` and `skills\ralph-auto` to the Codex skills directory.
