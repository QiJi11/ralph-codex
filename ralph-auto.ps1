[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("InitWorkspace", "ListProjects", "AddProject", "InitProject", "InitializeProject", "ReviewProject", "RunProject")]
    [string]$Command,

    [string]$WorkspaceRoot = "C:\Users\10531\RalphWorkspace",
    [string]$Project = "",
    [string]$ProjectPath = "",
    [int]$MaxIterations = 10,
    [string]$Model = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$RepositoryRoot = $PSScriptRoot

# Returns the Codex home directory used for vendor imports.
function Get-CodexHome {
    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
        return $env:CODEX_HOME
    }

    return Join-Path $env:USERPROFILE ".codex"
}

# Returns the installed Ralph vendor directory under the Codex home.
function Get-RalphVendorRoot {
    $codexHome = Get-CodexHome
    return Join-Path $codexHome "vendor_imports\ralph-codex"
}

# Returns the absolute registry file path for a workspace.
function Get-RalphAutoRegistryPath {
    param([string]$Root)

    return Join-Path $Root "projects.json"
}

# Ensures the workspace directory and registry exist without printing status.
function Ensure-RalphAutoWorkspace {
    param([string]$Root)

    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    $registryPath = Get-RalphAutoRegistryPath -Root $Root

    if (-not (Test-Path -LiteralPath $registryPath)) {
        [ordered]@{
            version = 1
            projects = @()
        } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $registryPath -Encoding UTF8
    }
}

# Creates the workspace directory and its project registry when missing.
function Initialize-RalphAutoWorkspace {
    param([string]$Root)

    Ensure-RalphAutoWorkspace -Root $Root
    $registryPath = Get-RalphAutoRegistryPath -Root $Root

    Write-Host "Workspace: $Root"
    Write-Host "Registry: $registryPath"
    Write-Host "Vendor imports: $(Get-RalphVendorRoot)"
}

# Reads the workspace project registry, creating it first if needed.
function Read-RalphAutoRegistry {
    param([string]$Root)

    Ensure-RalphAutoWorkspace -Root $Root
    $registryPath = Get-RalphAutoRegistryPath -Root $Root
    return Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

# Writes the workspace project registry in a stable JSON format.
function Write-RalphAutoRegistry {
    param(
        [string]$Root,
        [object]$Registry
    )

    $registryPath = Get-RalphAutoRegistryPath -Root $Root
    $Registry | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $registryPath -Encoding UTF8
}

# Ensures a required parameter has a non-empty value.
function Assert-RalphAutoValue {
    param(
        [string]$Name,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "$Name is required for command $Command"
    }
}

# Resolves a project path to an absolute filesystem path.
function Resolve-RalphAutoProjectPath {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "ProjectPath does not exist or is not a directory: $Path"
    }

    return (Resolve-Path -LiteralPath $Path).Path
}

# Verifies that a directory is a git working tree.
function Assert-RalphAutoGitProject {
    param([string]$Path)

    $gitDir = & git -C $Path rev-parse --git-dir 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitDir)) {
        throw "ProjectPath is not a git working tree: $Path"
    }
}

# Returns a registered project record by name.
function Get-RalphAutoProject {
    param(
        [object]$Registry,
        [string]$Name
    )

    $matches = @($Registry.projects | Where-Object { $_.name -eq $Name })
    if ($matches.Count -eq 0) {
        throw "Project is not registered: $Name"
    }

    return $matches[0]
}

# Prints all registered workspace projects.
function Show-RalphAutoProjects {
    param([string]$Root)

    $registry = Read-RalphAutoRegistry -Root $Root
    $projects = @($registry.projects)

    if ($projects.Count -eq 0) {
        Write-Host "No registered projects."
        return
    }

    $projects | Sort-Object name | Format-Table -AutoSize name, path
}

# Adds or updates a project registration in the workspace registry.
function Add-RalphAutoProject {
    param(
        [string]$Root,
        [string]$Name,
        [string]$Path
    )

    Assert-RalphAutoValue -Name "Project" -Value $Name
    Assert-RalphAutoValue -Name "ProjectPath" -Value $Path

    $resolvedPath = Resolve-RalphAutoProjectPath -Path $Path
    Assert-RalphAutoGitProject -Path $resolvedPath

    $registry = Read-RalphAutoRegistry -Root $Root
    $projects = @($registry.projects | Where-Object { $_.name -ne $Name })
    $projects += [pscustomobject]@{
        name = $Name
        path = $resolvedPath
    }

    $registry.projects = @($projects | Sort-Object name)
    Write-RalphAutoRegistry -Root $Root -Registry $registry

    Write-Host "Registered project: $Name"
    Write-Host "Path: $resolvedPath"
}

# Copies Ralph runner files into a registered project when they are missing.
function Initialize-RalphAutoProject {
    param(
        [string]$Root,
        [string]$Name
    )

    Assert-RalphAutoValue -Name "Project" -Value $Name

    $registry = Read-RalphAutoRegistry -Root $Root
    $projectRecord = Get-RalphAutoProject -Registry $registry -Name $Name
    $projectRoot = Resolve-RalphAutoProjectPath -Path $projectRecord.path
    $ralphDir = Join-Path $projectRoot "scripts\ralph"

    New-Item -ItemType Directory -Force -Path $ralphDir | Out-Null

    $runnerSource = Join-Path $RepositoryRoot "scripts\ralph\ralph.ps1"
    if (-not (Test-Path -LiteralPath $runnerSource)) {
        $runnerSource = Join-Path (Get-RalphVendorRoot) "ralph.ps1"
    }

    if (-not (Test-Path -LiteralPath $runnerSource)) {
        throw "Cannot find Ralph PowerShell runner at repository or vendor path."
    }

    Copy-Item -LiteralPath $runnerSource -Destination (Join-Path $ralphDir "ralph.ps1") -Force

    $codexSource = Join-Path $RepositoryRoot "scripts\ralph\CODEX.md"
    if (-not (Test-Path -LiteralPath $codexSource)) {
        $codexSource = Join-Path (Get-RalphVendorRoot) "CODEX.md"
    }

    if (Test-Path -LiteralPath $codexSource) {
        Copy-Item -LiteralPath $codexSource -Destination (Join-Path $ralphDir "CODEX.md") -Force
    }

    $exampleSource = Join-Path $RepositoryRoot "scripts\ralph\prd.json.example"
    if (-not (Test-Path -LiteralPath $exampleSource)) {
        $exampleSource = Join-Path (Get-RalphVendorRoot) "prd.json.example"
    }

    if (Test-Path -LiteralPath $exampleSource) {
        Copy-Item -LiteralPath $exampleSource -Destination (Join-Path $ralphDir "prd.json.example") -Force
    }

    Write-Host "Initialized Ralph files for project: $Name"
    Write-Host "Ralph directory: $ralphDir"
}

# Runs the registered project's Ralph entrypoint from the project root.
function Show-RalphAutoProjectReview {
    param(
        [string]$Root,
        [string]$Name
    )

    Assert-RalphAutoValue -Name "Project" -Value $Name

    $registry = Read-RalphAutoRegistry -Root $Root
    $projectRecord = Get-RalphAutoProject -Registry $registry -Name $Name
    $projectRoot = Resolve-RalphAutoProjectPath -Path $projectRecord.path
    $ralphDir = Join-Path $projectRoot "scripts\ralph"
    $prdPath = Join-Path $ralphDir "prd.json"
    $progressPath = Join-Path $ralphDir "progress.txt"
    $runsDir = Join-Path $ralphDir "runs"

    Write-Host "Project: $Name"
    Write-Host "Project root: $projectRoot"
    Write-Host "Workspace: $Root"
    Write-Host "Ralph dir: $ralphDir"

    $branch = (& git -C $projectRoot branch --show-current 2>$null)
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($branch)) {
        Write-Host "Git branch: $branch"
    }

    Write-Host "Git status:"
    $status = @(& git -C $projectRoot status --short 2>$null)
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  unavailable"
    } elseif ($status.Count -eq 0) {
        Write-Host "  clean"
    } else {
        $status | ForEach-Object { Write-Host "  $_" }
    }

    if (Test-Path -LiteralPath $prdPath) {
        $prd = Get-Content -LiteralPath $prdPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $stories = @($prd.userStories)
        $unfinished = @($stories | Where-Object { $_.passes -ne $true })
        Write-Host "PRD: $prdPath"
        Write-Host "Stories: $($stories.Count)"
        Write-Host "Unfinished: $($unfinished.Count)"
        foreach ($story in ($unfinished | Sort-Object priority | Select-Object -First 5)) {
            Write-Host "  $($story.id): $($story.title)"
        }
    } else {
        Write-Host "PRD: missing"
    }

    if (Test-Path -LiteralPath $progressPath) {
        Write-Host "Progress: $progressPath"
        Write-Host "Progress tail:"
        Get-Content -LiteralPath $progressPath -Tail 20 -Encoding UTF8 | ForEach-Object {
            Write-Host "  $_"
        }
    } else {
        Write-Host "Progress: missing"
    }

    if (Test-Path -LiteralPath $runsDir) {
        $runs = @(Get-ChildItem -LiteralPath $runsDir -File | Sort-Object LastWriteTime -Descending | Select-Object -First 5)
        Write-Host "Recent runs:"
        if ($runs.Count -eq 0) {
            Write-Host "  none"
        } else {
            $runs | ForEach-Object { Write-Host "  $($_.Name)" }
        }
    } else {
        Write-Host "Recent runs: none"
    }
}

# Runs the registered project's Ralph entrypoint from the project root.
function Invoke-RalphAutoProject {
    param(
        [string]$Root,
        [string]$Name,
        [int]$Iterations,
        [string]$RequestedModel
    )

    Assert-RalphAutoValue -Name "Project" -Value $Name

    $registry = Read-RalphAutoRegistry -Root $Root
    $projectRecord = Get-RalphAutoProject -Registry $registry -Name $Name
    $projectRoot = Resolve-RalphAutoProjectPath -Path $projectRecord.path
    $runnerPath = Join-Path $projectRoot "scripts\ralph\ralph.ps1"

    if (-not (Test-Path -LiteralPath $runnerPath)) {
        Initialize-RalphAutoProject -Root $Root -Name $Name
    }

    if (-not (Test-Path -LiteralPath $runnerPath)) {
        throw "Project Ralph runner is missing: $runnerPath"
    }

    $userRoot = (Resolve-Path -LiteralPath $env:USERPROFILE).Path
    if ((Resolve-Path -LiteralPath $projectRoot).Path -eq $userRoot) {
        throw "Refusing to run Ralph directly from the user profile root: $userRoot"
    }

    $args = @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $runnerPath,
        "-ProjectRoot",
        $projectRoot,
        "-MaxIterations",
        $Iterations
    )

    if (-not [string]::IsNullOrWhiteSpace($RequestedModel)) {
        $args += @("-Model", $RequestedModel)
    }

    Push-Location -LiteralPath $projectRoot
    try {
        Write-Host "Running Ralph project: $Name"
        Write-Host "Project root: $projectRoot"
        Write-Host "Command: pwsh $($args -join ' ')"
        & pwsh @args
        if ($LASTEXITCODE -ne 0) {
            throw "Ralph exited with code $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }
}

switch ($Command) {
    "InitWorkspace" {
        Initialize-RalphAutoWorkspace -Root $WorkspaceRoot
    }
    "ListProjects" {
        Show-RalphAutoProjects -Root $WorkspaceRoot
    }
    "AddProject" {
        Add-RalphAutoProject -Root $WorkspaceRoot -Name $Project -Path $ProjectPath
    }
    "InitProject" {
        Initialize-RalphAutoProject -Root $WorkspaceRoot -Name $Project
    }
    "InitializeProject" {
        Initialize-RalphAutoProject -Root $WorkspaceRoot -Name $Project
    }
    "ReviewProject" {
        Show-RalphAutoProjectReview -Root $WorkspaceRoot -Name $Project
    }
    "RunProject" {
        Invoke-RalphAutoProject -Root $WorkspaceRoot -Name $Project -Iterations $MaxIterations -RequestedModel $Model
    }
}
