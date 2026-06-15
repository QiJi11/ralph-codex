# Ralph Codex workspace runner for managing multiple local projects.
# Usage: .\workspace.ps1 <init|add-project|list|init-project|run> [options]

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("init", "add-project", "list", "init-project", "run")]
    [string]$Command = "list",

    [string]$WorkspaceRoot = (Get-Location).Path,
    [string]$Project = "",
    [string]$Name = "",
    [string]$Path = "",
    [int]$MaxIterations = 10,
    [string]$Model = "",
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.Encoding]::UTF8

if ($Command -eq "init") {
    New-Item -ItemType Directory -Force -Path $WorkspaceRoot | Out-Null
}

$WorkspaceRoot = (Resolve-Path -LiteralPath $WorkspaceRoot).Path
$ProjectsFile = Join-Path $WorkspaceRoot "projects.json"
$VendorRoot = Join-Path $env:USERPROFILE ".codex\vendor_imports\ralph-codex"

# Reads projects.json and returns the parsed workspace config.
function Read-WorkspaceConfig {
    param([string]$ConfigPath)

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "Missing projects.json at $ConfigPath. Run '.\workspace.ps1 init' first."
    }

    return Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

# Writes the workspace config as stable JSON.
function Write-WorkspaceConfig {
    param(
        [string]$ConfigPath,
        [object]$Config
    )

    $Config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
}

# Resolves a project entry by name.
function Get-WorkspaceProject {
    param(
        [object]$Config,
        [string]$ProjectName
    )

    $match = @($Config.projects | Where-Object { $_.name -eq $ProjectName })
    if ($match.Count -eq 0) {
        throw "Unknown project '$ProjectName'. Run '.\workspace.ps1 list' to see available projects."
    }

    if ($match.Count -gt 1) {
        throw "Duplicate project name '$ProjectName' in projects.json"
    }

    return $match[0]
}

# Ensures a directory exists.
function Ensure-Directory {
    param([string]$Directory)

    New-Item -ItemType Directory -Force -Path $Directory | Out-Null
}

# Copies the Ralph runner templates into a project.
function Install-RalphIntoProject {
    param(
        [string]$ProjectRoot,
        [switch]$Force
    )

    $ralphDir = Join-Path $ProjectRoot "scripts\ralph"
    Ensure-Directory -Directory $ralphDir

    $sourceFiles = @("ralph.ps1", "CODEX.md", "prd.json.example")
    foreach ($file in $sourceFiles) {
        $source = Join-Path $VendorRoot $file
        if (-not (Test-Path -LiteralPath $source)) {
            throw "Missing vendor file: $source. Run install-codex.ps1 first."
        }

        $destination = Join-Path $ralphDir $file
        if ((Test-Path -LiteralPath $destination) -and -not $Force) {
            Write-Host "Keeping existing $destination"
            continue
        }

        Copy-Item -LiteralPath $source -Destination $destination -Force
    }

    $agentsFile = Join-Path $ProjectRoot "AGENTS.md"
    if (-not (Test-Path -LiteralPath $agentsFile)) {
        @"
# Project Agent Notes

## Ralph Codex

- Use `scripts\ralph\ralph.ps1` to run Ralph for this project.
- Keep `scripts\ralph\prd.json` and `scripts\ralph\progress.txt` committed as Ralph state.
- Do not run Ralph from the user home directory; use this project root as `-ProjectRoot`.
"@ | Set-Content -LiteralPath $agentsFile -Encoding UTF8
    }

    Write-Host "Initialized Ralph in $ProjectRoot"
}

# Returns the absolute filesystem path for a project entry.
function Resolve-ProjectPath {
    param([object]$ProjectEntry)

    $projectPath = [string]$ProjectEntry.path
    if ([string]::IsNullOrWhiteSpace($projectPath)) {
        throw "Project '$($ProjectEntry.name)' has no path"
    }

    return (Resolve-Path -LiteralPath $projectPath).Path
}

switch ($Command) {
    "init" {
        Ensure-Directory -Directory (Join-Path $WorkspaceRoot "projects")
        Ensure-Directory -Directory (Join-Path $WorkspaceRoot "tasks")
        Ensure-Directory -Directory (Join-Path $WorkspaceRoot "archive")

        if ((Test-Path -LiteralPath $ProjectsFile) -and -not $Force) {
            Write-Host "projects.json already exists at $ProjectsFile"
            break
        }

        $config = [pscustomobject]@{
            version = 1
            projects = @()
        }
        Write-WorkspaceConfig -ConfigPath $ProjectsFile -Config $config
        Write-Host "Initialized Ralph workspace at $WorkspaceRoot"
    }

    "add-project" {
        if ([string]::IsNullOrWhiteSpace($Name)) {
            throw "-Name is required for add-project"
        }
        if ([string]::IsNullOrWhiteSpace($Path)) {
            throw "-Path is required for add-project"
        }

        $config = Read-WorkspaceConfig -ConfigPath $ProjectsFile
        $projectPath = (Resolve-Path -LiteralPath $Path).Path
        if (-not (Test-Path -LiteralPath (Join-Path $projectPath ".git"))) {
            throw "Project path is not a git repository: $projectPath"
        }

        $existing = @($config.projects | Where-Object { $_.name -eq $Name })
        if ($existing.Count -gt 0 -and -not $Force) {
            throw "Project '$Name' already exists. Re-run with -Force to replace it."
        }

        $projects = @($config.projects | Where-Object { $_.name -ne $Name })
        $projects += [pscustomobject]@{
            name = $Name
            path = $projectPath
        }
        $config.projects = @($projects | Sort-Object name)
        Write-WorkspaceConfig -ConfigPath $ProjectsFile -Config $config
        Write-Host "Added project '$Name' -> $projectPath"
    }

    "list" {
        $config = Read-WorkspaceConfig -ConfigPath $ProjectsFile
        if (@($config.projects).Count -eq 0) {
            Write-Host "No projects configured."
            break
        }

        $config.projects | Sort-Object name | ForEach-Object {
            Write-Host "$($_.name) -> $($_.path)"
        }
    }

    "init-project" {
        if ([string]::IsNullOrWhiteSpace($Project)) {
            throw "-Project is required for init-project"
        }

        $config = Read-WorkspaceConfig -ConfigPath $ProjectsFile
        $entry = Get-WorkspaceProject -Config $config -ProjectName $Project
        $projectPath = Resolve-ProjectPath -ProjectEntry $entry
        Install-RalphIntoProject -ProjectRoot $projectPath -Force:$Force
    }

    "run" {
        if ([string]::IsNullOrWhiteSpace($Project)) {
            throw "-Project is required for run"
        }

        $config = Read-WorkspaceConfig -ConfigPath $ProjectsFile
        $entry = Get-WorkspaceProject -Config $config -ProjectName $Project
        $projectPath = Resolve-ProjectPath -ProjectEntry $entry
        $runner = Join-Path $projectPath "scripts\ralph\ralph.ps1"
        $ralphDir = Join-Path $projectPath "scripts\ralph"

        if (-not (Test-Path -LiteralPath $runner)) {
            throw "Missing project Ralph runner at $runner. Run '.\workspace.ps1 init-project -Project $Project' first."
        }

        $args = @(
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            $runner,
            "-MaxIterations",
            $MaxIterations,
            "-ProjectRoot",
            $projectPath,
            "-RalphDir",
            $ralphDir
        )

        if (-not [string]::IsNullOrWhiteSpace($Model)) {
            $args += @("-Model", $Model)
        }

        & pwsh @args
        exit $LASTEXITCODE
    }
}
