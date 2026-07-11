# Codex App Support

Ralph Codex has verified Codex CLI and Codex App plugin paths. App verification remains separate from CLI installation and is recorded in `APP_VERIFY.md`.

## Current Status

- Status: `verified on 2026-07-12`.
- The repository includes `.codex-plugin\plugin.json`.
- The plugin manifest points at this fork and exposes the `skills` directory.
- The runner still executes local PowerShell and Codex CLI commands.
- Manual verification steps are tracked in `APP_VERIFY.md`.

## App Goal

The Codex App path should let a user install or enable the Ralph Codex plugin, discover the bundled skills, and use natural language such as:

```text
用 RA 跑 inventory-app 的 CSV import MVP
```

The first App milestone should still run against local git repositories and `RalphWorkspace`; it should not promise remote/cloud execution.

## Support States

- `verified`: `APP_VERIFY.md` passes in Codex App, including skill discovery and a real `RunProject` or `RunParallel -DryRun`.
- `blocked`: Codex App cannot discover the plugin, cannot discover the skills, or cannot run local PowerShell commands.
- `fallback to CLI`: Codex App can help plan but actual execution must use Codex CLI.

## Known Boundaries

- Clone plus `install-codex.ps1` remains the supported CLI installation path.
- Codex App support requires the plugin to be installed and enabled, with the Ralph skills visible in the App.
- If a specific App environment cannot run local PowerShell commands, the supported fallback remains Codex CLI.
- Treat `APP_VERIFY.md` as the source of truth for the verified App version, route, and local execution checks.
