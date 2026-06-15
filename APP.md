# Codex App Plan

Ralph Codex currently has a verified Codex CLI path. Codex App support is the next target and should be validated separately from CLI installation.

## Current Status

- The repository includes `.codex-plugin\plugin.json`.
- The plugin manifest points at this fork and exposes the `skills` directory.
- The runner still executes local PowerShell and Codex CLI commands.

## App Goal

The Codex App path should let a user install or enable the Ralph Codex plugin, discover the bundled skills, and use natural language such as:

```text
用 RA 跑 inventory-app 的 CSV import MVP
```

The first App milestone should still run against local git repositories and `RalphWorkspace`; it should not promise remote/cloud execution.

## App Acceptance Checklist

- Codex App can see the Ralph Codex plugin metadata.
- Codex App can discover `prd`, `ralph`, `run-ralph`, and `ralph-auto` skills.
- App chat can trigger the same execution brief required by `ralph-auto`.
- App execution can access the local project path and workspace path.
- App execution can start `ralph-auto.ps1` or clearly reports why local command execution is unavailable.
- A real run is tested with `RunProject` or `RunParallel -DryRun` before claiming App support.

## Known Boundaries

- Clone plus `install-codex.ps1` is the supported CLI path today.
- Codex App support is not yet certified as zero-configuration.
- If the App cannot run local PowerShell commands, the supported fallback is Codex CLI.
- Do not advertise full App support until the checklist above has been tested in Codex App itself.
