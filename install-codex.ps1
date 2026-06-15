# Install Ralph Codex skills and runner templates into the current user's Codex home.
# Usage: .\install-codex.ps1 [-CodexHome <path>] [-Force] [-WhatIf]

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$CodexHome = "",
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.Encoding]::UTF8

if ([string]::IsNullOrWhiteSpace($CodexHome)) {
    $CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE ".codex" }
}

$RepoRoot = $PSScriptRoot
$SkillsSource = Join-Path $RepoRoot "skills"
$RunnerSourceFiles = @("ralph.ps1", "ralph.sh", "CODEX.md", "prd.json.example", "install-codex.ps1", "workspace.ps1", "workspace.example.json", "WORKSPACE.md")
$SkillsDest = Join-Path $CodexHome "skills"
$RunnerDest = Join-Path $CodexHome "vendor_imports\ralph-codex"

# Copies a directory into a destination, optionally replacing the prior copy.
function Copy-RalphDirectory {
    param(
        [string]$Source,
        [string]$Destination,
        [switch]$Force
    )

    if ((Test-Path -LiteralPath $Destination) -and -not $Force) {
        throw "Destination already exists: $Destination. Re-run with -Force to replace it."
    }

    if ($PSCmdlet.ShouldProcess($Destination, "Install directory from $Source")) {
        if (Test-Path -LiteralPath $Destination) {
            Remove-Item -LiteralPath $Destination -Recurse -Force
        }

        New-Item -ItemType Directory -Force -Path $Destination | Out-Null
        Get-ChildItem -LiteralPath $Source -Force | Copy-Item -Destination $Destination -Recurse -Force
    }
}

# Copies runner template files into the Codex vendor_imports directory.
function Copy-RalphRunnerFiles {
    param(
        [string]$Destination,
        [string[]]$Files
    )

    if ($PSCmdlet.ShouldProcess($Destination, "Install Ralph Codex runner files")) {
        New-Item -ItemType Directory -Force -Path $Destination | Out-Null
        foreach ($file in $Files) {
            Copy-Item -LiteralPath (Join-Path $RepoRoot $file) -Destination $Destination -Force
        }
    }
}

if (-not (Test-Path -LiteralPath $SkillsSource)) {
    throw "Missing skills directory at $SkillsSource"
}

foreach ($file in $RunnerSourceFiles) {
    $path = Join-Path $RepoRoot $file
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing required runner file: $path"
    }
}

New-Item -ItemType Directory -Force -Path $CodexHome | Out-Null
Get-ChildItem -LiteralPath $SkillsSource -Directory | ForEach-Object {
    Copy-RalphDirectory -Source $_.FullName -Destination (Join-Path $SkillsDest $_.Name) -Force:$Force
}
Copy-RalphRunnerFiles -Destination $RunnerDest -Files $RunnerSourceFiles

Write-Host "Installed Ralph Codex into $CodexHome"
Write-Host "Skills:"
Get-ChildItem -LiteralPath $SkillsSource -Directory | ForEach-Object {
    Write-Host "  $(Join-Path $SkillsDest $_.Name)"
}
Write-Host "Runner templates:"
Write-Host "  $RunnerDest"
Write-Host "Restart Codex to pick up new skills."
