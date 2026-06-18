# Ralph Auto regression smoke tests for workspace, planning, and dry-run behavior.

[CmdletBinding()]
param(
    [string]$WorkspaceRoot = (Join-Path $env:USERPROFILE "RalphWorkspace"),
    [string]$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.Encoding]::UTF8

function Resolve-SmokeGitCommand {
    $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    if ($null -ne $gitCommand) {
        return $gitCommand.Source
    }

    $candidate = "C:\Program Files\Git\cmd\git.exe"
    if (Test-Path -LiteralPath $candidate) {
        return $candidate
    }

    throw "git is required for RA smoke tests."
}

function Resolve-SmokePwshCommand {
    $pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($null -ne $pwshCommand) {
        return $pwshCommand.Source
    }

    throw "pwsh is required for RA smoke tests."
}

function Remove-SmokeProjectRegistration {
    param(
        [string]$Root,
        [string]$Name
    )

    $registryPath = Join-Path $Root "projects.json"
    if (-not (Test-Path -LiteralPath $registryPath)) {
        return
    }

    $registry = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $registry.projects = @($registry.projects | Where-Object { $_.name -ne $Name })
    $registry | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $registryPath -Encoding UTF8
}

function Invoke-SmokeRalphAuto {
    param([string[]]$Arguments)

    $script:LastOutput = @(& $script:PwshCommand -NoProfile -ExecutionPolicy Bypass -File (Join-Path $script:RepoRoot "ralph-auto.ps1") @Arguments 2>&1)
    return ($script:LastOutput -join "`n")
}

function Assert-SmokeText {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Message
    )

    if ($Text -notmatch $Pattern) {
        Write-Host $Text
        throw $Message
    }
}

function Set-SmokePrd {
    param(
        [string]$ProjectRoot,
        [string]$Json
    )

    $prdPath = Join-Path $ProjectRoot "scripts\ralph\prd.json"
    $Json | Set-Content -LiteralPath $prdPath -Encoding UTF8
}

function New-SmokeCodexShim {
    param(
        [string]$Root,
        [switch]$OmitDeliverables
    )

    $shimDir = Join-Path $Root "shim-bin"
    New-Item -ItemType Directory -Force -Path $shimDir | Out-Null
    $shimPath = Join-Path $shimDir "codex.cmd"
    $scriptPath = Join-Path $shimDir "codex-shim.ps1"
    $omitValue = if ($OmitDeliverables) { "1" } else { "0" }

    @"
@echo off
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0codex-shim.ps1" %*
"@ | Set-Content -LiteralPath $shimPath -Encoding ASCII

    @"
[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments=`$true)][string[]]`$Args)
Set-StrictMode -Version Latest
`$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
`$prompt = [Console]::In.ReadToEnd()
`$projectRoot = ""
for (`$i = 0; `$i -lt `$Args.Count; `$i++) {
    if (`$Args[`$i] -eq "-C" -and (`$i + 1) -lt `$Args.Count) {
        `$projectRoot = `$Args[`$i + 1]
    }
}
if ([string]::IsNullOrWhiteSpace(`$projectRoot)) {
    throw "Missing -C project root"
}
`$subtaskId = [regex]::Match(`$prompt, 'Current subtask:\s+([^\s]+)').Groups[1].Value
if ([string]::IsNullOrWhiteSpace(`$subtaskId)) {
    `$subtaskId = "US-001-ST-001"
}
`$storyMatch = [regex]::Match(`$prompt, 'Current story:\s+([^\s]+)\s+-\s+(.+)')
`$storyId = if (`$storyMatch.Success) { `$storyMatch.Groups[1].Value } else { "US-001" }
`$storyTitle = if (`$storyMatch.Success) { `$storyMatch.Groups[2].Value.Trim() } else { "Smoke Story" }
`$ralphDir = Join-Path `$projectRoot "scripts\ralph"
`$prdPath = Join-Path `$ralphDir "prd.json"
`$progressPath = Join-Path `$ralphDir "progress.txt"
`$targetName = switch (`$subtaskId) {
    "US-001-ST-001" { "alpha.md" }
    "US-001-ST-002" { "beta.md" }
    default { "single.md" }
}
`$docsDir = Join-Path `$projectRoot "docs"
New-Item -ItemType Directory -Force -Path `$docsDir | Out-Null
`$deliverablePath = Join-Path `$docsDir `$targetName
"completed `$subtaskId" | Set-Content -LiteralPath `$deliverablePath -Encoding UTF8
`$prd = Get-Content -LiteralPath `$prdPath -Raw -Encoding UTF8 | ConvertFrom-Json
foreach (`$story in @(`$prd.userStories)) {
    foreach (`$subtask in @(`$story.subtasks)) {
        if ([string]`$subtask.id -eq `$subtaskId) {
            `$subtask.passes = `$true
        }
    }
    `$story.passes = (@(`$story.subtasks | Where-Object { `$_.passes -ne `$true }).Count -eq 0)
}
`$prd | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath `$prdPath -Encoding UTF8
if (-not (Test-Path -LiteralPath `$progressPath)) {
    "# Ralph Progress Log" | Set-Content -LiteralPath `$progressPath -Encoding UTF8
    "Started: `$(Get-Date -Format o)" | Add-Content -LiteralPath `$progressPath -Encoding UTF8
    "---" | Add-Content -LiteralPath `$progressPath -Encoding UTF8
}
"" | Add-Content -LiteralPath `$progressPath -Encoding UTF8
"## `$(Get-Date -Format 'yyyy-MM-dd HH:mm zzz') - `$subtaskId" | Add-Content -LiteralPath `$progressPath -Encoding UTF8
"- Story: `$storyId - `$storyTitle" | Add-Content -LiteralPath `$progressPath -Encoding UTF8
"- Smoke shim completed `$subtaskId" | Add-Content -LiteralPath `$progressPath -Encoding UTF8
"- Files changed" | Add-Content -LiteralPath `$progressPath -Encoding UTF8
"  `$deliverablePath" | Add-Content -LiteralPath `$progressPath -Encoding UTF8
"- Quality checks run and results" | Add-Content -LiteralPath `$progressPath -Encoding UTF8
"  smoke shim: passed" | Add-Content -LiteralPath `$progressPath -Encoding UTF8
"- Browser verification result, if this was a UI subtask" | Add-Content -LiteralPath `$progressPath -Encoding UTF8
"  not applicable" | Add-Content -LiteralPath `$progressPath -Encoding UTF8
if ("$omitValue" -ne "1") {
    "- Final deliverables:" | Add-Content -LiteralPath `$progressPath -Encoding UTF8
    "  `$deliverablePath" | Add-Content -LiteralPath `$progressPath -Encoding UTF8
}
"- **Learnings for future iterations:**" | Add-Content -LiteralPath `$progressPath -Encoding UTF8
"  - Smoke shim path is isolated to the test PATH." | Add-Content -LiteralPath `$progressPath -Encoding UTF8
"---" | Add-Content -LiteralPath `$progressPath -Encoding UTF8
& git -C `$projectRoot add .
if (`$LASTEXITCODE -ne 0) { exit `$LASTEXITCODE }
& git -C `$projectRoot -c user.name="Smoke" -c user.email="smoke@example.com" commit -m "feat: `$subtaskId - smoke completion"
if (`$LASTEXITCODE -ne 0) { exit `$LASTEXITCODE }
Write-Output "<promise>COMPLETE</promise>"
"@ | Set-Content -LiteralPath $scriptPath -Encoding UTF8

    return $shimDir
}

function Assert-SmokeFileExists {
    param(
        [string]$Path,
        [string]$Message
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw $Message
    }
}

function Assert-SmokePrdSubtaskPasses {
    param(
        [string]$ProjectRoot,
        [string]$SubtaskId
    )

    $prdPath = Join-Path $ProjectRoot "scripts\ralph\prd.json"
    $prd = Get-Content -LiteralPath $prdPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $match = @(
        foreach ($story in @($prd.userStories)) {
            foreach ($subtask in @($story.subtasks)) {
                if ([string]$subtask.id -eq $SubtaskId) {
                    $subtask
                }
            }
        }
    ) | Select-Object -First 1

    if ($null -eq $match -or $match.passes -ne $true) {
        throw "Subtask $SubtaskId was not marked passing in prd.json."
    }
}

$script:RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$script:GitCommand = Resolve-SmokeGitCommand
$script:PwshCommand = Resolve-SmokePwshCommand
$script:LastOutput = @()
$projectName = "ra-smoke-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$projectRoot = Join-Path $env:TEMP $projectName
$shimRoot = Join-Path $env:TEMP "$projectName-shim"
$originalPath = $env:PATH

try {
    Remove-SmokeProjectRegistration -Root $WorkspaceRoot -Name $projectName
    if (Test-Path -LiteralPath $projectRoot) {
        Remove-Item -LiteralPath $projectRoot -Recurse -Force
    }
    if (Test-Path -LiteralPath $shimRoot) {
        Remove-Item -LiteralPath $shimRoot -Recurse -Force
    }

    New-Item -ItemType Directory -Path $projectRoot | Out-Null
    & $script:GitCommand -C $projectRoot init --initial-branch=main | Out-Null
    & $script:GitCommand -C $projectRoot config user.name "Smoke" | Out-Null
    & $script:GitCommand -C $projectRoot config user.email "smoke@example.com" | Out-Null
    "smoke" | Set-Content -LiteralPath (Join-Path $projectRoot "README.md") -Encoding UTF8
    & $script:GitCommand -C $projectRoot add . | Out-Null
    & $script:GitCommand -C $projectRoot -c user.name="Smoke" -c user.email="smoke@example.com" commit -m "init" | Out-Null

    Invoke-SmokeRalphAuto -Arguments @("-Command", "AddProject", "-WorkspaceRoot", $WorkspaceRoot, "-Project", $projectName, "-ProjectPath", $projectRoot) | Out-Null
    Invoke-SmokeRalphAuto -Arguments @("-Command", "InitProject", "-WorkspaceRoot", $WorkspaceRoot, "-Project", $projectName) | Out-Null
    & $script:GitCommand -C $projectRoot add . | Out-Null
    & $script:GitCommand -C $projectRoot -c user.name="Smoke" -c user.email="smoke@example.com" commit -m "add ralph files" | Out-Null

    $reviewOutput = Invoke-SmokeRalphAuto -Arguments @("-Command", "ReviewProject", "-WorkspaceRoot", $WorkspaceRoot, "-Project", $projectName)
    Assert-SmokeText -Text $reviewOutput -Pattern "PRD: missing" -Message "ReviewProject did not report missing PRD."
    Assert-SmokeText -Text $reviewOutput -Pattern "Next step:" -Message "ReviewProject missing-state guidance was not shown."

    $oversizedPrd = @'
{
  "project": "ra-smoke",
  "branchName": "main",
  "description": "oversized smoke",
  "userStories": [
    {
      "id": "US-001",
      "title": "Oversized explicit subtask",
      "description": "Should fail planning.",
      "priority": 1,
      "passes": false,
      "notes": "",
      "subtasks": [
        {
          "id": "US-001-ST-001",
          "title": "Too many files",
          "description": "Touches too many files.",
          "acceptanceCriteria": ["Typecheck passes"],
          "priority": 1,
          "passes": false,
          "notes": "",
          "dependsOn": [],
          "parallelSafe": false,
          "estimatedFiles": ["a.md", "b.md"],
          "touches": ["docs/a"],
          "stateWrites": [],
          "fileBudget": 1
        }
      ]
    }
  ]
}
'@
    Set-SmokePrd -ProjectRoot $projectRoot -Json $oversizedPrd
    & $script:GitCommand -C $projectRoot add scripts/ralph/prd.json | Out-Null
    & $script:GitCommand -C $projectRoot -c user.name="Smoke" -c user.email="smoke@example.com" commit -m "add oversized prd" | Out-Null
    $oversizedOutput = Invoke-SmokeRalphAuto -Arguments @("-Command", "RunParallel", "-WorkspaceRoot", $WorkspaceRoot, "-Project", $projectName, "-DryRun")
    Assert-SmokeText -Text $oversizedOutput -Pattern "exceeds fileBudget" -Message "Oversized explicit subtask did not fail planning."

    $parallelPrd = @'
{
  "project": "ra-smoke",
  "branchName": "main",
  "description": "parallel smoke",
  "userStories": [
    {
      "id": "US-001",
      "title": "Independent docs",
      "description": "Should select both subtasks.",
      "priority": 1,
      "passes": false,
      "notes": "",
      "subtasks": [
        {
          "id": "US-001-ST-001",
          "title": "Alpha",
          "description": "Alpha only.",
          "acceptanceCriteria": ["Typecheck passes"],
          "priority": 1,
          "passes": false,
          "notes": "",
          "dependsOn": [],
          "parallelSafe": true,
          "estimatedFiles": ["docs/alpha.md"],
          "touches": ["docs/alpha"],
          "stateWrites": [],
          "fileBudget": 1
        },
        {
          "id": "US-001-ST-002",
          "title": "Beta",
          "description": "Beta only.",
          "acceptanceCriteria": ["Typecheck passes"],
          "priority": 1,
          "passes": false,
          "notes": "",
          "dependsOn": [],
          "parallelSafe": true,
          "estimatedFiles": ["docs/beta.md"],
          "touches": ["docs/beta"],
          "stateWrites": [],
          "fileBudget": 1
        }
      ]
    }
  ]
}
'@
    Set-SmokePrd -ProjectRoot $projectRoot -Json $parallelPrd
    & $script:GitCommand -C $projectRoot add scripts/ralph/prd.json | Out-Null
    & $script:GitCommand -C $projectRoot -c user.name="Smoke" -c user.email="smoke@example.com" commit -m "add parallel prd" | Out-Null
    $parallelOutput = Invoke-SmokeRalphAuto -Arguments @("-Command", "RunParallel", "-WorkspaceRoot", $WorkspaceRoot, "-Project", $projectName, "-MaxWorkers", "2", "-DryRun")
    Assert-SmokeText -Text $parallelOutput -Pattern "US-001-ST-001" -Message "Parallel dry-run did not select the first subtask."
    Assert-SmokeText -Text $parallelOutput -Pattern "US-001-ST-002" -Message "Parallel dry-run did not select the second subtask."
    Assert-SmokeText -Text $parallelOutput -Pattern "Would branch" -Message "Parallel dry-run did not show branch previews."
    $postDryRunStatus = @(& $script:GitCommand -C $projectRoot status --short)
    if ($postDryRunStatus.Count -gt 0) {
        & $script:GitCommand -C $projectRoot add . | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Failed to stage dry-run normalization changes." }
        & $script:GitCommand -C $projectRoot -c user.name="Smoke" -c user.email="smoke@example.com" commit -m "commit normalized parallel prd" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Failed to commit dry-run normalization changes." }
    }
    $preParallelStatus = @(& $script:GitCommand -C $projectRoot status --short)
    if ($preParallelStatus.Count -gt 0) {
        Write-Host ($preParallelStatus -join "`n")
        throw "Project worktree is dirty before real RunParallel smoke."
    }

    $shimDir = New-SmokeCodexShim -Root $shimRoot
    $env:PATH = "$shimDir;$originalPath"
    $parallelRunOutput = Invoke-SmokeRalphAuto -Arguments @("-Command", "RunParallel", "-WorkspaceRoot", $WorkspaceRoot, "-Project", $projectName, "-MaxWorkers", "2", "-MaxIterations", "1", "-CleanupOnSuccess")
    Assert-SmokeText -Text $parallelRunOutput -Pattern "RunParallel completed" -Message "Real RunParallel smoke did not complete."
    Assert-SmokeFileExists -Path (Join-Path $projectRoot "docs\alpha.md") -Message "RunParallel did not merge alpha deliverable."
    Assert-SmokeFileExists -Path (Join-Path $projectRoot "docs\beta.md") -Message "RunParallel did not merge beta deliverable."
    Assert-SmokePrdSubtaskPasses -ProjectRoot $projectRoot -SubtaskId "US-001-ST-001"
    Assert-SmokePrdSubtaskPasses -ProjectRoot $projectRoot -SubtaskId "US-001-ST-002"
    $progressText = Get-Content -LiteralPath (Join-Path $projectRoot "scripts\ralph\progress.txt") -Raw -Encoding UTF8
    Assert-SmokeText -Text $progressText -Pattern "Completed by parallel RA worker branch" -Message "RunParallel did not append main progress entries."
    $reviewAfterParallel = Invoke-SmokeRalphAuto -Arguments @("-Command", "ReviewProject", "-WorkspaceRoot", $WorkspaceRoot, "-Project", $projectName)
    Assert-SmokeText -Text $reviewAfterParallel -Pattern "Active lock: none" -Message "Project lock was not released after RunParallel."
    Assert-SmokeText -Text $reviewAfterParallel -Pattern "Pending subtasks: 0" -Message "ReviewProject did not report completed subtasks after RunParallel."

    New-Item -ItemType Directory -Force -Path (Join-Path $projectRoot "scripts\ralph\runs") | Out-Null
    "old run" | Set-Content -LiteralPath (Join-Path $projectRoot "scripts\ralph\runs\old.log") -Encoding UTF8
    $cleanupDryRunOutput = Invoke-SmokeRalphAuto -Arguments @("-Command", "CleanupContext", "-WorkspaceRoot", $WorkspaceRoot, "-Project", $projectName, "-KeepLastRuns", "0", "-DryRun")
    Assert-SmokeText -Text $cleanupDryRunOutput -Pattern "DryRun" -Message "CleanupContext dry-run did not report preview mode."
    Assert-SmokeFileExists -Path (Join-Path $projectRoot "scripts\ralph\runs\old.log") -Message "CleanupContext dry-run removed a run file."

    $singlePrd = @'
{
  "project": "ra-smoke",
  "branchName": "main",
  "description": "single completion smoke",
  "userStories": [
    {
      "id": "US-001",
      "title": "Single docs",
      "description": "Should complete through the runner.",
      "priority": 1,
      "passes": false,
      "notes": "",
      "subtasks": [
        {
          "id": "US-001-ST-001",
          "title": "Single",
          "description": "Single only.",
          "acceptanceCriteria": ["Typecheck passes"],
          "priority": 1,
          "passes": false,
          "notes": "",
          "dependsOn": [],
          "parallelSafe": false,
          "estimatedFiles": ["docs/single.md"],
          "touches": ["docs/single"],
          "stateWrites": [],
          "fileBudget": 1
        }
      ]
    }
  ]
}
'@
    Set-SmokePrd -ProjectRoot $projectRoot -Json $singlePrd
    if (Test-Path -LiteralPath (Join-Path $projectRoot "scripts\ralph\progress.txt")) {
        Remove-Item -LiteralPath (Join-Path $projectRoot "scripts\ralph\progress.txt") -Force
    }
    & $script:GitCommand -C $projectRoot add . | Out-Null
    & $script:GitCommand -C $projectRoot -c user.name="Smoke" -c user.email="smoke@example.com" commit -m "reset single completion prd" | Out-Null
    $singleRunOutput = @(& $script:PwshCommand -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot "scripts\ralph\ralph.ps1") -ProjectRoot $projectRoot -RalphDir (Join-Path $projectRoot "scripts\ralph") -RunId "smoke-single-complete" -MaxIterations 1 2>&1) -join "`n"
    Assert-SmokeText -Text $singleRunOutput -Pattern "Ralph completed all tasks" -Message "ralph.ps1 did not accept a valid final-deliverables completion."

    Set-SmokePrd -ProjectRoot $projectRoot -Json $singlePrd
    if (Test-Path -LiteralPath (Join-Path $projectRoot "scripts\ralph\progress.txt")) {
        Remove-Item -LiteralPath (Join-Path $projectRoot "scripts\ralph\progress.txt") -Force
    }
    & $script:GitCommand -C $projectRoot add . | Out-Null
    & $script:GitCommand -C $projectRoot -c user.name="Smoke" -c user.email="smoke@example.com" commit -m "reset missing deliverables prd" | Out-Null
    $badShimDir = New-SmokeCodexShim -Root $shimRoot -OmitDeliverables
    $env:PATH = "$badShimDir;$originalPath"
    $missingDeliverablesOutput = @(& $script:PwshCommand -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot "scripts\ralph\ralph.ps1") -ProjectRoot $projectRoot -RalphDir (Join-Path $projectRoot "scripts\ralph") -RunId "smoke-missing-deliverables" -MaxIterations 1 2>&1) -join "`n"
    Assert-SmokeText -Text $missingDeliverablesOutput -Pattern "missing final deliverable paths" -Message "ralph.ps1 accepted completion without final deliverables."

    $runnerOutput = @(& $script:PwshCommand -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot "scripts\ralph\ralph.ps1") -ProjectRoot $projectRoot -RalphDir (Join-Path $projectRoot "scripts\ralph") -RunId "smoke-dirty-continuation" -MaxIterations 1 -AllowDirtyContinuation -DryRun 2>&1) -join "`n"
    Assert-SmokeText -Text $runnerOutput -Pattern "Dry run complete" -Message "ralph.ps1 dirty continuation dry-run did not complete."

    Write-Host "RA_SMOKE_OK"
}
finally {
    $env:PATH = $originalPath
    Remove-SmokeProjectRegistration -Root $WorkspaceRoot -Name $projectName
    if (Test-Path -LiteralPath $projectRoot) {
        Remove-Item -LiteralPath $projectRoot -Recurse -Force
    }
    if (Test-Path -LiteralPath $shimRoot) {
        Remove-Item -LiteralPath $shimRoot -Recurse -Force
    }
}
