# Ralph Codex TODO

Repository: `QiJi11/ralph-codex`
Branch: `codex-support`
Current supported paths: Codex CLI and Codex App plugin
Codex App status: `verified`; evidence is recorded in `APP_VERIFY.md`
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

### 2026-07-11 local closeout

- [x] Confirmed the only worktree change, `flowchart/src/App.tsx`, extracts node creation from component render so React no longer reads `nodePositions.current` during initial render. The base file fails `react-hooks/refs`; the current file passes lint and build.
- [x] PowerShell parser checks passed for `ralph.ps1`, `ralph-auto.ps1`, `workspace.ps1`, and `install-codex.ps1`; `git diff --check` and `ListProjects` passed.
- [x] `install-codex.ps1 -Force` was verified in an isolated temporary `CODEX_HOME`; all four skill directories and nine vendor files matched the repository. The global install was not overwritten because its `ralph-auto` skill differs from the repository.
- [x] At the 2026-07-11 checkpoint, `APP_VERIFY.md` recorded `Codex App support: blocked` because App plugin/skill discovery and the natural-language trigger had not passed. The 2026-07-12 recheck below supersedes that checkpoint and verifies App support.
- [x] Commit boundary: keep `flowchart/src/App.tsx` as the standalone lint fix and keep `APP_VERIFY.md`/`TODO.md` as verification documentation. No commit or push was performed.

### 2026-07-12 App recheck

- [x] Repaired the invalid global marketplace source, created the personal marketplace, installed `ralph-codex@personal`, and verified the App card reaches `Installed` / `Try in chat`.
- [x] Verified App skill discovery for all four plugin skills: `Prd`, `Ralph`, `Ralph Auto`, and `Run Ralph`.
- [x] CLI route-only eval passed positive cases for all four plugin skills and a negative `ralph-auto` case.
- [x] Verified the App-side natural-language route from the Desktop rollout: the exact read-only `RA 上面的内容` prompt produced `agent_message = ralph-auto`; the later Prompt Sensei Stop-hook continuation caused the empty visible body.
- [x] Verified the post-fix App response end to end: the page visibly showed `ralph-auto`, the matching rollout completed with `last_agent_message = ralph-auto`, no Sensei-only continuation appeared, and all 15 pre-test CLI/Prodex PIDs remained alive.
- [x] Verified App-local execution with the documented `RunParallel -DryRun` command: the App returned exit code `1` and `Project is not registered: inventory-app`, started no worker, modified no files, and recorded the command/output/final answer in rollout `019f524f-b399-7dd1-a4ce-e94cdadd1c12`.
