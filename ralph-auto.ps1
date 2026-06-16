[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("InitWorkspace", "ListProjects", "AddProject", "InitProject", "InitializeProject", "ReviewProject", "RunProject", "RunParallel", "CleanupContext")]
    [string]$Command,

    [string]$WorkspaceRoot = (Join-Path $env:USERPROFILE "RalphWorkspace"),
    [string]$Project = "",
    [string]$ProjectPath = "",
    [int]$MaxIterations = 10,
    [string]$Model = "",
    [int]$MaxWorkers = 2,
    [int]$KeepLastRuns = 5,
    [switch]$NoMerge,
    [switch]$CleanupOnSuccess,
    [switch]$ArchiveProgress,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$RepositoryRoot = $PSScriptRoot

# Resolves the git executable even before a fresh shell has picked up PATH changes.
function Resolve-RalphAutoGitCommand {
    $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    if ($null -ne $gitCommand) {
        return $gitCommand.Source
    }

    $programRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique

    $candidates = @()
    foreach ($programRoot in $programRoots) {
        $candidates += (Join-Path $programRoot "Git\cmd\git.exe")
        $candidates += (Join-Path $programRoot "Git\bin\git.exe")
    }

    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    throw "git is required but was not found in PATH or standard Windows install paths."
}

$GitCommand = Resolve-RalphAutoGitCommand

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

    $gitDir = & $GitCommand -C $Path rev-parse --git-dir 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitDir)) {
        throw "ProjectPath is not a git working tree: $Path"
    }
}

# Converts arbitrary text into a branch/path-safe segment.
function Get-RalphAutoSafeName {
    param([string]$Value)

    $safe = $Value -replace '[^\w.-]+', '-'
    $safe = $safe.Trim("-")
    if ([string]::IsNullOrWhiteSpace($safe)) {
        return "item"
    }

    return $safe
}

# Returns true when an object has the named property.
function Test-RalphAutoProperty {
    param(
        [object]$Object,
        [string]$Name
    )

    return $null -ne $Object.PSObject.Properties[$Name]
}

# Resolves a Ralph template file from the repo root, legacy scripts path, or installed vendor path.
function Resolve-RalphAutoTemplateFile {
    param([string]$FileName)

    $candidates = @(
        (Join-Path $RepositoryRoot $FileName),
        (Join-Path $RepositoryRoot "scripts\ralph\$FileName"),
        (Join-Path (Get-RalphVendorRoot) $FileName)
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    return ""
}

# Throws when a git working tree has uncommitted changes.
function Assert-RalphAutoCleanGit {
    param([string]$Path)

    $status = @(& $GitCommand -C $Path status --short)
    if ($LASTEXITCODE -ne 0) {
        throw "Cannot read git status for $Path"
    }

    if ($status.Count -gt 0) {
        throw "Project worktree must be clean before RunParallel: $Path"
    }
}

# Returns the git status lines for a working tree.
function Get-RalphAutoGitStatus {
    param([string]$Path)

    $status = @(& $GitCommand -C $Path status --short)
    if ($LASTEXITCODE -ne 0) {
        throw "Cannot read git status for $Path"
    }

    return $status
}

# Returns worker task directories that CleanupContext can safely remove or report.
function Get-RalphAutoCleanupTaskCandidates {
    param(
        [string]$Root,
        [string]$Name
    )

    $safeProject = Get-RalphAutoSafeName -Value $Name
    $projectTaskRoot = Join-Path $Root "tasks\$safeProject"
    if (-not (Test-Path -LiteralPath $projectTaskRoot -PathType Container)) {
        return @()
    }

    $candidates = @()
    $runDirs = @(Get-ChildItem -LiteralPath $projectTaskRoot -Directory | Sort-Object LastWriteTime -Descending)
    foreach ($runDir in $runDirs) {
        $children = @(Get-ChildItem -LiteralPath $runDir.FullName -Force)
        if ($children.Count -eq 0) {
            $candidates += [pscustomobject]@{
                Path = $runDir.FullName
                Kind = "empty-run-directory"
                SafeToRemove = $true
                Reason = "No worker directories remain."
            }
            continue
        }

        $safeWorkers = @()
        $blockedWorkers = @()
        foreach ($workerDir in @($children | Where-Object { $_.PSIsContainer })) {
            $gitDir = & $GitCommand -C $workerDir.FullName rev-parse --git-dir 2>$null
            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitDir)) {
                $blockedWorkers += "$($workerDir.FullName) is not a git worktree."
                continue
            }

            $status = @(& $GitCommand -C $workerDir.FullName status --short)
            if ($LASTEXITCODE -ne 0) {
                $blockedWorkers += "$($workerDir.FullName) git status is unavailable."
                continue
            }

            if ($status.Count -gt 0) {
                $blockedWorkers += "$($workerDir.FullName) has uncommitted changes."
                continue
            }

            $safeWorkers += $workerDir.FullName
        }

        if ($safeWorkers.Count -gt 0) {
            foreach ($workerPath in $safeWorkers) {
                $candidates += [pscustomobject]@{
                    Path = $workerPath
                    Kind = "clean-worker-worktree"
                    SafeToRemove = $true
                    Reason = "Worker git worktree is clean."
                }
            }
        }

        if ($blockedWorkers.Count -gt 0) {
            $candidates += [pscustomobject]@{
                Path = $runDir.FullName
                Kind = "blocked-run-directory"
                SafeToRemove = $false
                Reason = ($blockedWorkers -join " ")
            }
        }
    }

    $remainingChildren = @(Get-ChildItem -LiteralPath $projectTaskRoot -Force)
    if ($remainingChildren.Count -eq 0) {
        $candidates += [pscustomobject]@{
            Path = $projectTaskRoot
            Kind = "empty-project-task-directory"
            SafeToRemove = $true
            Reason = "No task run directories remain."
        }
    }

    return $candidates
}

# Copies Ralph runner template files into a project path.
function Copy-RalphAutoTemplates {
    param([string]$ProjectRoot)

    $ralphDir = Join-Path $ProjectRoot "scripts\ralph"
    New-Item -ItemType Directory -Force -Path $ralphDir | Out-Null

    $runnerSource = Resolve-RalphAutoTemplateFile -FileName "ralph.ps1"
    if ([string]::IsNullOrWhiteSpace($runnerSource)) {
        throw "Cannot find Ralph PowerShell runner at repository or vendor path."
    }

    Copy-Item -LiteralPath $runnerSource -Destination (Join-Path $ralphDir "ralph.ps1") -Force

    $codexSource = Resolve-RalphAutoTemplateFile -FileName "CODEX.md"
    if (-not [string]::IsNullOrWhiteSpace($codexSource)) {
        Copy-Item -LiteralPath $codexSource -Destination (Join-Path $ralphDir "CODEX.md") -Force
    }

    $exampleSource = Resolve-RalphAutoTemplateFile -FileName "prd.json.example"
    if (-not [string]::IsNullOrWhiteSpace($exampleSource)) {
        Copy-Item -LiteralPath $exampleSource -Destination (Join-Path $ralphDir "prd.json.example") -Force
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

    Copy-RalphAutoTemplates -ProjectRoot $projectRoot

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

    $branch = (& $GitCommand -C $projectRoot branch --show-current 2>$null)
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($branch)) {
        Write-Host "Git branch: $branch"
    }

    Write-Host "Git status:"
    $status = @(& $GitCommand -C $projectRoot status --short 2>$null)
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

# Runs parallel-safe PRD stories in isolated git worktrees.
function Invoke-RalphAutoParallelProject {
    param(
        [string]$Root,
        [string]$Name,
        [int]$Iterations,
        [int]$Workers,
        [string]$RequestedModel,
        [bool]$SkipMerge,
        [bool]$RemoveSuccessfulWorktrees,
        [bool]$PreviewOnly
    )

    Assert-RalphAutoValue -Name "Project" -Value $Name
    if ($Workers -lt 1) {
        throw "MaxWorkers must be 1 or greater"
    }

    $registry = Read-RalphAutoRegistry -Root $Root
    $projectRecord = Get-RalphAutoProject -Registry $registry -Name $Name
    $projectRoot = Resolve-RalphAutoProjectPath -Path $projectRecord.path
    $ralphDir = Join-Path $projectRoot "scripts\ralph"
    $prdPath = Join-Path $ralphDir "prd.json"

    if (-not (Test-Path -LiteralPath $prdPath)) {
        throw "Missing PRD for RunParallel: $prdPath"
    }

    Assert-RalphAutoCleanGit -Path $projectRoot

    $prd = Get-Content -LiteralPath $prdPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $stories = @($prd.userStories)
    $completedIds = @($stories | Where-Object { $_.passes -eq $true } | ForEach-Object { [string]$_.id })
    $ready = @()

    foreach ($story in ($stories | Sort-Object priority)) {
        if ($story.passes -eq $true) {
            continue
        }

        if (-not (Test-RalphAutoProperty -Object $story -Name "parallelSafe") -or $story.parallelSafe -ne $true) {
            continue
        }

        $dependsOn = @()
        if (Test-RalphAutoProperty -Object $story -Name "dependsOn") {
            $dependsOn = @($story.dependsOn | ForEach-Object { [string]$_ })
        }

        $blocked = @($dependsOn | Where-Object { $completedIds -notcontains $_ })
        if ($blocked.Count -eq 0) {
            $ready += $story
        }
    }

    $selected = @($ready | Select-Object -First $Workers)
    if ($selected.Count -eq 0) {
        throw "No parallel-safe ready stories found. Mark stories with parallelSafe: true and satisfied dependsOn."
    }

    $runId = Get-Date -Format "yyyyMMdd-HHmmss"
    $safeProject = Get-RalphAutoSafeName -Value $Name
    $taskRoot = Join-Path $Root "tasks\$safeProject\$runId"
    $baseBranch = (& $GitCommand -C $projectRoot branch --show-current)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($baseBranch)) {
        throw "Cannot determine current branch for $projectRoot"
    }

    Write-Host "RunParallel project: $Name"
    Write-Host "Project root: $projectRoot"
    Write-Host "Base branch: $baseBranch"
    Write-Host "Task root: $taskRoot"
    Write-Host "Selected stories:"
    $selected | ForEach-Object { Write-Host "  $($_.id): $($_.title)" }

    if ($PreviewOnly) {
        Write-Host "DryRun: no worktrees created and no workers started."
        foreach ($story in $selected) {
            $storyId = Get-RalphAutoSafeName -Value ([string]$story.id)
            $branchName = "ralph/parallel/$safeProject/$storyId-$runId"
            $worktreePath = Join-Path $taskRoot $storyId
            Write-Host "Would create: $worktreePath"
            Write-Host "Would branch: $branchName"
        }
        return
    }

    New-Item -ItemType Directory -Force -Path $taskRoot | Out-Null
    $jobs = @()

    foreach ($story in $selected) {
        $storyId = Get-RalphAutoSafeName -Value ([string]$story.id)
        $branchName = "ralph/parallel/$safeProject/$storyId-$runId"
        $worktreePath = Join-Path $taskRoot $storyId

        & $GitCommand -C $projectRoot worktree add -b $branchName $worktreePath $baseBranch | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to create worktree for $($story.id)"
        }

        Copy-RalphAutoTemplates -ProjectRoot $worktreePath

        $workerRalphDir = Join-Path $worktreePath "scripts\ralph"
        $workerPrdPath = Join-Path $workerRalphDir "prd.json"
        $workerPrd = $prd | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $workerPrd.branchName = $branchName
        $workerPrd.userStories = @($story)
        $workerPrd | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $workerPrdPath -Encoding UTF8

        $runnerPath = Join-Path $workerRalphDir "ralph.ps1"
        $workerArgs = @(
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            $runnerPath,
            "-ProjectRoot",
            $worktreePath,
            "-RalphDir",
            $workerRalphDir,
            "-MaxIterations",
            $Iterations
        )

        if (-not [string]::IsNullOrWhiteSpace($RequestedModel)) {
            $workerArgs += @("-Model", $RequestedModel)
        }

        Write-Host "Starting worker $($story.id): pwsh $($workerArgs -join ' ')"
        $job = Start-Job -Name $story.id -ScriptBlock {
            param([string[]]$ArgsForPwsh)
            & pwsh @ArgsForPwsh
            if ($LASTEXITCODE -ne 0) {
                throw "Ralph worker exited with code $LASTEXITCODE"
            }
        } -ArgumentList (,$workerArgs)

        $jobs += [pscustomobject]@{
            StoryId = [string]$story.id
            StoryTitle = [string]$story.title
            Branch = $branchName
            Worktree = $worktreePath
            Job = $job
        }
    }

    $failed = @()
    foreach ($item in $jobs) {
        Wait-Job -Job $item.Job | Out-Null
        Receive-Job -Job $item.Job | Out-Host
        if ($item.Job.State -ne "Completed") {
            $failed += $item
            continue
        }
    }

    if ($failed.Count -gt 0) {
        Write-Host "One or more workers failed. Worktrees were preserved."
        $failed | ForEach-Object { Write-Host "  $($_.StoryId): $($_.Worktree)" }
        throw "RunParallel worker failure"
    }

    if ($SkipMerge) {
        Write-Host "NoMerge was set. Worker branches were left unmerged."
        $jobs | ForEach-Object { Write-Host "  $($_.Branch) -> $($_.Worktree)" }
        return
    }

    foreach ($item in $jobs) {
        & $GitCommand -C $item.Worktree restore --source $baseBranch -- scripts/ralph 2>$null
        & $GitCommand -C $item.Worktree clean -fd -- scripts/ralph | Out-Host
        if ($LASTEXITCODE -eq 0) {
            $stateStatus = @(& $GitCommand -C $item.Worktree status --short -- scripts/ralph)
            if ($stateStatus.Count -gt 0) {
                & $GitCommand -C $item.Worktree add scripts/ralph | Out-Host
                & $GitCommand -C $item.Worktree commit -m "chore: keep worker Ralph state out of merge" | Out-Host
            }
        }

        Write-Host "Merging $($item.Branch)"
        & $GitCommand -C $projectRoot merge --no-ff $item.Branch -m "merge: $($item.StoryId) parallel RA worker" | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Merge conflict or merge failure. Worktree preserved: $($item.Worktree)"
            throw "Failed to merge $($item.Branch)"
        }
    }

    if (Test-Path -LiteralPath $prdPath) {
        $mainPrd = Get-Content -LiteralPath $prdPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($item in $jobs) {
            $mainStory = @($mainPrd.userStories | Where-Object { $_.id -eq $item.StoryId }) | Select-Object -First 1
            if ($null -ne $mainStory) {
                $mainStory.passes = $true
                $note = "Completed by parallel RA worker branch $($item.Branch)"
                if (Test-RalphAutoProperty -Object $mainStory -Name "notes") {
                    $mainStory.notes = $note
                } else {
                    $mainStory | Add-Member -NotePropertyName "notes" -NotePropertyValue $note
                }
            }
        }

        $mainPrd | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $prdPath -Encoding UTF8
        $progressPath = Join-Path $ralphDir "progress.txt"
        if (-not (Test-Path -LiteralPath $progressPath)) {
            "# Ralph Progress Log" | Set-Content -LiteralPath $progressPath -Encoding UTF8
            "Started: $(Get-Date -Format o)" | Add-Content -LiteralPath $progressPath -Encoding UTF8
            "---" | Add-Content -LiteralPath $progressPath -Encoding UTF8
        }

        foreach ($item in $jobs) {
            "" | Add-Content -LiteralPath $progressPath -Encoding UTF8
            "## $(Get-Date -Format 'yyyy-MM-dd HH:mm zzz') - $($item.StoryId)" | Add-Content -LiteralPath $progressPath -Encoding UTF8
            "- Completed by parallel RA worker branch $($item.Branch)." | Add-Content -LiteralPath $progressPath -Encoding UTF8
            "- Worktree: $($item.Worktree)" | Add-Content -LiteralPath $progressPath -Encoding UTF8
            "- Merged into $baseBranch." | Add-Content -LiteralPath $progressPath -Encoding UTF8
            "---" | Add-Content -LiteralPath $progressPath -Encoding UTF8
        }

        & $GitCommand -C $projectRoot add scripts\ralph\prd.json scripts\ralph\progress.txt | Out-Host
        & $GitCommand -C $projectRoot commit -m "chore: update parallel RA state" | Out-Host
    }

    if ($RemoveSuccessfulWorktrees) {
        foreach ($item in $jobs) {
            & $GitCommand -C $projectRoot worktree remove $item.Worktree --force | Out-Host
        }
    }

    Write-Host "RunParallel completed."
}

# Previews or removes old Ralph runtime context without touching user code.
function Invoke-RalphAutoContextCleanup {
    param(
        [string]$Root,
        [string]$Name,
        [int]$RunsToKeep,
        [bool]$ShouldArchiveProgress,
        [bool]$PreviewOnly
    )

    Assert-RalphAutoValue -Name "Project" -Value $Name
    if ($RunsToKeep -lt 0) {
        throw "KeepLastRuns must be 0 or greater"
    }

    $registry = Read-RalphAutoRegistry -Root $Root
    $projectRecord = Get-RalphAutoProject -Registry $registry -Name $Name
    $projectRoot = Resolve-RalphAutoProjectPath -Path $projectRecord.path
    $ralphDir = Join-Path $projectRoot "scripts\ralph"
    $prdPath = Join-Path $ralphDir "prd.json"
    $progressPath = Join-Path $ralphDir "progress.txt"
    $runsDir = Join-Path $ralphDir "runs"
    $archiveDir = Join-Path $ralphDir "archive"

    if (-not (Test-Path -LiteralPath $ralphDir -PathType Container)) {
        throw "Missing Ralph directory for CleanupContext: $ralphDir"
    }

    if (-not (Test-Path -LiteralPath $prdPath)) {
        throw "Missing current PRD; refusing cleanup: $prdPath"
    }

    $gitStatus = @(Get-RalphAutoGitStatus -Path $projectRoot)
    if ($gitStatus.Count -gt 0 -and -not $PreviewOnly) {
        Write-Host "Project worktree has uncommitted changes; refusing CleanupContext without -DryRun."
        $gitStatus | ForEach-Object { Write-Host "  $_" }
        throw "Project worktree must be clean before CleanupContext"
    }

    Write-Host "CleanupContext project: $Name"
    Write-Host "Project root: $projectRoot"
    Write-Host "Ralph dir: $ralphDir"
    Write-Host "DryRun: $PreviewOnly"
    Write-Host "KeepLastRuns: $RunsToKeep"
    Write-Host "ArchiveProgress: $ShouldArchiveProgress"
    Write-Host "Current PRD preserved: $prdPath"

    $runFiles = @()
    if (Test-Path -LiteralPath $runsDir) {
        $runFiles = @(Get-ChildItem -LiteralPath $runsDir -File | Sort-Object LastWriteTime -Descending)
    }

    $keptRuns = @($runFiles | Select-Object -First $RunsToKeep)
    $removedRuns = @($runFiles | Select-Object -Skip $RunsToKeep)
    Write-Host "Run logs found: $($runFiles.Count)"
    $keptRuns | ForEach-Object { Write-Host "  Keep run: $($_.FullName)" }
    $removedRuns | ForEach-Object { Write-Host "  Remove run: $($_.FullName)" }

    $taskCandidates = @(Get-RalphAutoCleanupTaskCandidates -Root $Root -Name $Name)
    $removableTasks = @($taskCandidates | Where-Object { $_.SafeToRemove -eq $true })
    $blockedTasks = @($taskCandidates | Where-Object { $_.SafeToRemove -ne $true })
    Write-Host "Worker task cleanup candidates: $($taskCandidates.Count)"
    $removableTasks | ForEach-Object { Write-Host "  Remove task $($_.Kind): $($_.Path)" }
    $blockedTasks | ForEach-Object { Write-Host "  Keep task $($_.Kind): $($_.Path) - $($_.Reason)" }

    if (Test-Path -LiteralPath $progressPath) {
        if ($ShouldArchiveProgress) {
            $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $archivePath = Join-Path $archiveDir "progress-$stamp.txt"
            Write-Host "Archive progress: $progressPath -> $archivePath"
        } else {
            Write-Host "Progress preserved: $progressPath"
        }
    } else {
        Write-Host "Progress missing: $progressPath"
    }

    if ($PreviewOnly) {
        Write-Host "DryRun: no files were changed."
        return
    }

    foreach ($run in $removedRuns) {
        Remove-Item -LiteralPath $run.FullName -Force
    }

    foreach ($task in $removableTasks) {
        if ($task.Kind -eq "clean-worker-worktree") {
            & $GitCommand -C $projectRoot worktree remove $task.Path --force | Out-Host
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to remove worker worktree: $($task.Path)"
            }
        } else {
            Remove-Item -LiteralPath $task.Path -Recurse -Force
        }
    }

    if ($ShouldArchiveProgress -and (Test-Path -LiteralPath $progressPath)) {
        New-Item -ItemType Directory -Force -Path $archiveDir | Out-Null
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $archivePath = Join-Path $archiveDir "progress-$stamp.txt"
        Copy-Item -LiteralPath $progressPath -Destination $archivePath -Force
        "# Ralph Progress Log" | Set-Content -LiteralPath $progressPath -Encoding UTF8
        "Started: $(Get-Date -Format o)" | Add-Content -LiteralPath $progressPath -Encoding UTF8
        "---" | Add-Content -LiteralPath $progressPath -Encoding UTF8
        "Archived previous progress to: $archivePath" | Add-Content -LiteralPath $progressPath -Encoding UTF8
    }

    Write-Host "CleanupContext completed."
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
    "RunParallel" {
        Invoke-RalphAutoParallelProject -Root $WorkspaceRoot -Name $Project -Iterations $MaxIterations -Workers $MaxWorkers -RequestedModel $Model -SkipMerge:$NoMerge.IsPresent -RemoveSuccessfulWorktrees:$CleanupOnSuccess.IsPresent -PreviewOnly:$DryRun.IsPresent
    }
    "CleanupContext" {
        Invoke-RalphAutoContextCleanup -Root $WorkspaceRoot -Name $Project -RunsToKeep $KeepLastRuns -ShouldArchiveProgress:$ArchiveProgress.IsPresent -PreviewOnly:$DryRun.IsPresent
    }
}
