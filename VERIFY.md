# Ralph Codex Verification

Use this checklist after cloning or changing Ralph Codex. Run commands from the repository root unless noted.

## CLI Install

```powershell
.\install-codex.ps1 -Force
```

Expected result:

- Skills are copied to `%USERPROFILE%\.codex\skills` or `$env:CODEX_HOME\skills`.
- Runner templates are copied to `vendor_imports\ralph-codex`.
- Codex should be restarted before relying on newly installed skills.

## Static Checks

```powershell
$files = @('ralph.ps1','ralph-auto.ps1','workspace.ps1','install-codex.ps1')
foreach ($file in $files) {
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile((Join-Path (Get-Location) $file), [ref]$null, [ref]$errors) > $null
    if ($errors) { $errors; exit 1 }
}
git diff --check
```

Expected result: no parser errors and no whitespace errors.

## Flowchart Build

```powershell
Set-Location flowchart
npm run build
Set-Location ..
```

Expected result: TypeScript and Vite build complete successfully.

## Ralph Auto Smoke Checks

List installed workspace projects:

```powershell
.\ralph-auto.ps1 -Command ListProjects -WorkspaceRoot 'C:\Users\<current-user>\RalphWorkspace'
```

Preview a parallel run for a project that already has `scripts\ralph\prd.json`:

```powershell
.\ralph-auto.ps1 -Command RunParallel -WorkspaceRoot 'C:\Users\<current-user>\RalphWorkspace' -Project 'my-app' -MaxWorkers 2 -MaxIterations 3 -DryRun
```

Expected result: either selected stories and worktree paths are printed, or a clear validation error explains what is missing.

For a successful dry-run selection, the project PRD must contain at least one unfinished story with `parallelSafe: true`; any `dependsOn` entries for that story must already be marked complete. The output must not create worktrees or start workers when `-DryRun` is set.

## Prompt Cache Structure

Confirm `ralph.ps1` keeps stable and runtime-specific prompt content separated:

- `New-RalphStablePromptPrefix` reads `CODEX.md` and appears before runtime context.
- `New-RalphDynamicPromptTail` appends project paths, PRD path, progress path, and log path after the stable prefix.
- Timestamps, log paths, project paths, iteration numbers, and story-specific data must not be moved into the stable prefix.

## End State

```powershell
git status --short --branch
```

Expected result: clean working tree unless you are intentionally preparing a commit.
