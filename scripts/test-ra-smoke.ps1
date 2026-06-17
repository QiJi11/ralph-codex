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

$script:RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$script:GitCommand = Resolve-SmokeGitCommand
$script:PwshCommand = Resolve-SmokePwshCommand
$script:LastOutput = @()
$projectName = "ra-smoke-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$projectRoot = Join-Path $env:TEMP $projectName

try {
    Remove-SmokeProjectRegistration -Root $WorkspaceRoot -Name $projectName
    if (Test-Path -LiteralPath $projectRoot) {
        Remove-Item -LiteralPath $projectRoot -Recurse -Force
    }

    New-Item -ItemType Directory -Path $projectRoot | Out-Null
    & $script:GitCommand -C $projectRoot init --initial-branch=main | Out-Null
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

    $runnerOutput = @(& $script:PwshCommand -NoProfile -ExecutionPolicy Bypass -File (Join-Path $projectRoot "scripts\ralph\ralph.ps1") -ProjectRoot $projectRoot -RalphDir (Join-Path $projectRoot "scripts\ralph") -RunId "smoke-dirty-continuation" -MaxIterations 1 -AllowDirtyContinuation -DryRun 2>&1) -join "`n"
    Assert-SmokeText -Text $runnerOutput -Pattern "Dry run complete" -Message "ralph.ps1 dirty continuation dry-run did not complete."

    Write-Host "RA_SMOKE_OK"
}
finally {
    Remove-SmokeProjectRegistration -Root $WorkspaceRoot -Name $projectName
    if (Test-Path -LiteralPath $projectRoot) {
        Remove-Item -LiteralPath $projectRoot -Recurse -Force
    }
}
