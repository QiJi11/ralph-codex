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
Plugin discovery: pass
Notes: The App personal marketplace page shows Ralph Codex, and the card reached `Installed` / `Try in chat` after installation.
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
Skill discovery: pass
Notes: After launching the App with the wrapper-selected global Codex home, the Skills page showed `Prd`, `Ralph`, `Ralph Auto`, and `Run Ralph`.
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
Natural language trigger: pass
Notes: After the Prompt Sensei Desktop fix, a new Codex App thread displayed `ralph-auto` as the visible answer in 12.5 seconds with no Sensei-only continuation or reconnect state. The matching rollout at `C:\Users\tianh\.codex\sessions\2026\07\12\rollout-2026-07-12T01-49-47-019f524c-b8e7-7802-9c45-899985fb6d2a.jsonl` records the exact read-only RA prompt, one `agent_message = ralph-auto`, and `task_complete.last_agent_message = ralph-auto`.
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
Local execution: pass
Notes: Codex App executed the documented `RunParallel -DryRun` command without starting a worker or modifying files. The App visibly reported exit code `1` and the accepted validation error `Project is not registered: inventory-app`. Rollout `C:\Users\tianh\.codex\sessions\2026\07\12\rollout-2026-07-12T01-53-02-019f524f-b399-7dd1-a4ce-e94cdadd1c12.jsonl` records the exact command call, its output, the final answer, and `task_complete`.
```

## Support Decision

Mark exactly one:

```text
Codex App support: verified
Reason: Plugin installation, all four skill entries, CLI route-only eval, the App-side natural-language route, and App-local `RunParallel -DryRun` execution are verified. The post-fix route visibly returned `ralph-auto`; the dry run visibly returned a clear validation error without starting a worker or modifying files. Matching rollouts completed normally without a Sensei-only continuation, and all 15 pre-test CLI/Prodex PIDs remained alive.
Date: 2026-07-12
Tester: Codex
```

Only update README to say "Codex App supported" after the result is `verified`.
