# Codex App Support

Ralph Codex currently has a verified Codex CLI path. Codex App support is not certified yet and must be validated separately from CLI installation.

## Current Status

- Status: `blocked until manual Codex App verification is completed`.
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

- Clone plus `install-codex.ps1` is the supported CLI path today.
- Codex App support is not yet certified as zero-configuration.
- If the App cannot run local PowerShell commands, the supported fallback is Codex CLI.
- Do not advertise full App support until `APP_VERIFY.md` has been tested in Codex App itself.
