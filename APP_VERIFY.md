# Codex App Verification

Use this checklist inside Codex App before claiming Ralph Codex App support. The CLI path is verified separately in `VERIFY.md`.

## Preconditions

- Clone this repository locally.
- Confirm the repository has `.codex-plugin\plugin.json`.
- Confirm Codex CLI path works first:

```powershell
.\install-codex.ps1 -Force
```

Restart Codex after installation.

## Plugin Discovery

In Codex App, check whether Ralph Codex is visible as a plugin or installable local plugin.

Expected result:

- Display name: `Ralph Codex`
- Repository or website: `https://github.com/QiJi11/ralph-codex`
- Capabilities include interactive/write behavior or equivalent App wording.

Record result:

```text
Plugin discovery: pass | fail
Notes:
```

## Skill Discovery

Ask Codex App to list or use the installed Ralph skills.

Expected skills:

- `prd`
- `ralph`
- `run-ralph`
- `ralph-auto`

Record result:

```text
Skill discovery: pass | fail
Notes:
```

## Natural Language Trigger

In Codex App, enter:

```text
用 RA 跑 inventory-app 的 CSV import MVP
```

Expected result:

- Codex recognizes `RA` as Ralph Auto.
- Codex prepares or asks for project/workspace details.
- Codex states an execution brief before any run.

Record result:

```text
Natural language trigger: pass | fail
Notes:
```

## Local Execution Boundary

Ask Codex App to run a safe dry run against a registered local project:

```powershell
.\ralph-auto.ps1 -Command RunParallel -WorkspaceRoot 'C:\Users\<current-user>\RalphWorkspace' -Project 'inventory-app' -MaxWorkers 2 -MaxIterations 3 -DryRun
```

Expected result:

- If local command execution is available, Codex App prints selected stories or a clear validation error.
- If local command execution is unavailable, Codex App clearly reports the limitation and the fallback is Codex CLI.

Record result:

```text
Local execution: pass | blocked
Notes:
```

## Support Decision

Mark exactly one:

```text
Codex App support: verified | blocked | fallback to CLI
Reason:
Date:
Tester:
```

Only update README to say "Codex App supported" after the result is `verified`.
