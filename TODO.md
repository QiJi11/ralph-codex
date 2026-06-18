# Ralph Codex TODO

Repository: `QiJi11/ralph-codex`
Branch: `codex-support`
Current supported path: Codex CLI
Codex App status: `not certified`; verify only through `APP_VERIFY.md`
Default workspace: `C:\Users\<current-user>\RalphWorkspace`

This file tracks version goals for the Codex-first Ralph fork. Keep upstream
MIT license and attribution to `snarktank/ralph`.

## P0 - Required For This Version

- Keep CLI verification passing:
  - PowerShell parser check for `ralph.ps1`, `ralph-auto.ps1`, `workspace.ps1`, and `install-codex.ps1`.
  - `git diff --check`.
  - `flowchart` build with `npm run build`.
  - `ralph-auto` smoke check with `ListProjects`.
- Record and preserve the verified RA one-command loop:
  - Register a project in `RalphWorkspace`.
  - Initialize `scripts\ralph`.
  - Run `RunProject`.
  - Reach `codex exec`.
  - Update `scripts\ralph\prd.json` and `scripts\ralph\progress.txt`.
- Keep new Windows setup safe:
  - Use PowerShell 7+.
  - Ensure `git`, `pwsh`, `node`, `npm`, and `codex` are available.
  - Restart PowerShell/Codex after installing Git or Ralph skills so PATH and skills are loaded.
  - Do not reuse old-computer absolute project paths.
- Keep Codex App claims conservative:
  - Do not claim Codex App support until `APP_VERIFY.md` is completed.
  - If App cannot execute local PowerShell, record status as `fallback to CLI`.

## P1 - Recommended For This Version

- Add or document a minimal `RunParallel` smoke flow. Status: done for dry-run and real isolated smoke:
  - PRD stories must set `parallelSafe: true`.
  - `dependsOn` must be satisfied before workers run.
  - Workers must use isolated git worktrees.
  - Main RA must merge worker branches and update `prd.json` and `progress.txt`.
- Re-verify prompt cache friendly prompt structure:
  - Stable `CODEX.md` instructions remain at the front.
  - Runtime context remains after the stable prefix.
  - Timestamps, log paths, project paths, iteration numbers, and story-specific data do not enter the stable prefix.
- Improve new-computer workspace documentation:
  - Each real project must be re-registered on the new machine.
  - Registered projects must be git repositories.
  - Users must provide the new local project path before RA runs a real project.
- Keep CLI-first wording consistent across docs and skills.

## P2 - Long-Term Goals

### RA context cleanup / 上下文清理

Goal: add safe RA context cleanup so old Ralph state does not pollute future
Codex runs.

Context sources to manage:

- `scripts\ralph\progress.txt`
- `scripts\ralph\runs\`
- old PRD snapshots or examples
- old worker worktrees
- `scripts\ralph\archive\`
- `RalphWorkspace\tasks\`

Initial requirements:

- Support dry-run.
- Support preview-only cleanup reports.
- Support cleanup of old `runs` logs.
- Support archiving or compressing oversized `progress.txt`.
- Support cleanup of completed worker worktrees under `RalphWorkspace\tasks`.
- Support keeping the most recent N runs.
- Check git status before cleanup.
- Keep RA runnable after cleanup.
- Never delete user code.
- Never delete the current `scripts\ralph\prd.json`.
- Never destroy the necessary summary in the current `progress.txt`.
- Never delete uncommitted important state.

Status: v1 is implemented for `runs` cleanup, `progress.txt` archive/reset, and
dirty-project refusal. v2 is implemented for worker task cleanup preview and
safe removal of empty task directories or clean worker worktrees. Dirty,
unvalidated, or non-git worker directories are reported and preserved.

Possible CLI shape:

```powershell
.\ralph-auto.ps1 -Command CleanupContext -WorkspaceRoot <path> -Project <name> -DryRun
.\ralph-auto.ps1 -Command CleanupContext -WorkspaceRoot <path> -Project <name> -KeepLastRuns 5
.\ralph-auto.ps1 -Command CleanupContext -WorkspaceRoot <path> -Project <name> -ArchiveProgress
```

The exact interface is not final. Analyze existing `ralph-auto.ps1` command
style before implementation.

### RA metrics and monitoring

Do not implement first; keep as planned follow-up.

- `metrics.jsonl`
- token usage
- cached token usage
- prompt chars
- stable prefix chars
- task completion rate
- worker success rate
- merge success rate

## Verification Notes

- CLI install target paths:
  - `skills\prd`
  - `skills\ralph`
  - `skills\run-ralph`
  - `skills\ralph-auto`
  - `vendor_imports\ralph-codex`
- CLI verification source of truth: `VERIFY.md`.
- Codex App verification source of truth: `APP_VERIFY.md`.
- Codex App support result must be exactly one of:
  - `verified`
  - `blocked`
  - `fallback to CLI`
