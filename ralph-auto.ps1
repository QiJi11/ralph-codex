[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("InitWorkspace", "ListProjects", "AddProject", "CreateAdhocProject", "InitProject", "InitializeProject", "ReviewProject", "RunProject", "RunParallel", "CleanupContext")]
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
    New-Item -ItemType Directory -Force -Path (Join-Path $Root "projects") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $Root "tasks") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $Root "archive") | Out-Null
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

# Returns the normalized ID for a Ralph subtask.
function New-RalphAutoSubtaskId {
    param(
        [string]$StoryId,
        [int]$Index
    )

    return "$StoryId-ST-{0:D3}" -f $Index
}

# Returns true when a story has explicit subtasks.
function Test-RalphAutoHasSubtasks {
    param([object]$Story)

    if (-not (Test-RalphAutoProperty -Object $Story -Name "subtasks")) {
        return $false
    }

    return @($Story.subtasks).Count -gt 0
}

# Returns the normalized file/touch/state arrays for a subtask.
function ConvertTo-RalphAutoStringArray {
    param([object]$Value)

    if ($null -eq $Value) {
        return @()
    }

    return @($Value | ForEach-Object {
        $item = [string]$_
        if (-not [string]::IsNullOrWhiteSpace($item)) {
            $item.Trim()
        }
    } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

# Returns a conservative subtask payload for a story that lacks explicit subtasks.
function New-RalphAutoDefaultSubtask {
    param([object]$Story)

    $defaultTouch = "story/$([string]$Story.id)"
    $stateWrites = @()
    $fileBudget = 3
    $parallelSafe = $false

    return [pscustomobject]@{
        id = (New-RalphAutoSubtaskId -StoryId ([string]$Story.id) -Index 1)
        title = [string]$Story.title
        description = [string]$Story.description
        acceptanceCriteria = @($Story.acceptanceCriteria)
        priority = [int]$Story.priority
        passes = ($Story.passes -eq $true)
        notes = ""
        dependsOn = @()
        parallelSafe = $parallelSafe
        estimatedFiles = @()
        touches = @($defaultTouch)
        stateWrites = $stateWrites
        fileBudget = $fileBudget
        splitRequired = $false
        sourceStoryId = [string]$Story.id
    }
}

# Splits a large story into smaller subtasks using acceptance criteria and heuristics.
function Split-RalphAutoStoryIntoSubtasks {
    param([object]$Story)

    $criteria = @($Story.acceptanceCriteria | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $nonQualityCriteria = @($criteria | Where-Object { $_ -notmatch 'Typecheck passes|Tests pass|Verify in browser' })
    $qualityCriteria = @($criteria | Where-Object { $_ -match 'Typecheck passes|Tests pass|Verify in browser' })

    $subtasks = @()
    $index = 1
    foreach ($criterion in $nonQualityCriteria) {
        $lower = $criterion.ToLowerInvariant()
        $touches = @("story/$([string]$Story.id)")
        $stateWrites = @()
        $parallelSafe = $true
        $fileBudget = 3

        if ($lower -match 'migration|column|table|database|schema') {
            $touches = @("db/schema")
            $stateWrites = @("migration")
            $parallelSafe = $false
            $fileBudget = 2
        } elseif ($lower -match 'api|server|action|service|endpoint') {
            $touches = @("backend/service")
        } elseif ($lower -match 'ui|page|modal|button|dropdown|badge|browser') {
            $touches = @("ui/component")
            $parallelSafe = $false
        } elseif ($lower -match 'config|route|build|manifest|package') {
            $touches = @("config/global")
            $stateWrites = @("shared-config")
            $parallelSafe = $false
            $fileBudget = 2
        }

        $subtasks += [pscustomobject]@{
            id = (New-RalphAutoSubtaskId -StoryId ([string]$Story.id) -Index $index)
            title = "$([string]$Story.title) - Step $index"
            description = $criterion
            acceptanceCriteria = @($criterion) + $qualityCriteria
            priority = [int]$Story.priority
            passes = $false
            notes = "Auto-split from oversized story $([string]$Story.id)."
            dependsOn = @()
            parallelSafe = $parallelSafe
            estimatedFiles = @()
            touches = $touches
            stateWrites = $stateWrites
            fileBudget = $fileBudget
            splitRequired = $false
            sourceStoryId = [string]$Story.id
        }
        $index++
    }

    if (@($subtasks).Count -gt 1) {
        for ($i = 1; $i -lt @($subtasks).Count; $i++) {
            $current = $subtasks[$i]
            $previous = $subtasks[$i - 1]
            if (@($current.stateWrites).Count -gt 0 -or @($previous.stateWrites).Count -gt 0 -or @(@($current.touches) | Where-Object { @($previous.touches) -contains $_ }).Count -gt 0) {
                $current.dependsOn = @([string]$previous.id)
                $current.parallelSafe = $false
            }
        }
    }

    if (@($subtasks).Count -eq 0) {
        return @((New-RalphAutoDefaultSubtask -Story $Story))
    }

    return $subtasks
}

# Ensures every story contains normalized subtasks.
function ConvertTo-RalphAutoNormalizedStories {
    param([object[]]$Stories)

    $normalized = @()
    foreach ($story in @($Stories | Sort-Object priority)) {
        $storyCopy = $story | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $subtasks = @()

        if (Test-RalphAutoHasSubtasks -Story $storyCopy) {
            $index = 1
            foreach ($subtask in @($storyCopy.subtasks | Sort-Object priority)) {
                if (-not (Test-RalphAutoProperty -Object $subtask -Name "id") -or [string]::IsNullOrWhiteSpace([string]$subtask.id)) {
                    $subtask | Add-Member -NotePropertyName "id" -NotePropertyValue (New-RalphAutoSubtaskId -StoryId ([string]$storyCopy.id) -Index $index)
                }
                if (-not (Test-RalphAutoProperty -Object $subtask -Name "priority")) {
                    $subtask | Add-Member -NotePropertyName "priority" -NotePropertyValue $storyCopy.priority
                }
                if (-not (Test-RalphAutoProperty -Object $subtask -Name "passes")) {
                    $subtask | Add-Member -NotePropertyName "passes" -NotePropertyValue $false
                }
                if (-not (Test-RalphAutoProperty -Object $subtask -Name "notes")) {
                    $subtask | Add-Member -NotePropertyName "notes" -NotePropertyValue ""
                }
                if (-not (Test-RalphAutoProperty -Object $subtask -Name "dependsOn")) {
                    $subtask | Add-Member -NotePropertyName "dependsOn" -NotePropertyValue @()
                }
                if (-not (Test-RalphAutoProperty -Object $subtask -Name "parallelSafe")) {
                    $subtask | Add-Member -NotePropertyName "parallelSafe" -NotePropertyValue $false
                }
                if (-not (Test-RalphAutoProperty -Object $subtask -Name "estimatedFiles")) {
                    $subtask | Add-Member -NotePropertyName "estimatedFiles" -NotePropertyValue @()
                }
                if (-not (Test-RalphAutoProperty -Object $subtask -Name "touches")) {
                    $subtask | Add-Member -NotePropertyName "touches" -NotePropertyValue @("story/$([string]$storyCopy.id)")
                }
                if (-not (Test-RalphAutoProperty -Object $subtask -Name "stateWrites")) {
                    $subtask | Add-Member -NotePropertyName "stateWrites" -NotePropertyValue @()
                }
                if (-not (Test-RalphAutoProperty -Object $subtask -Name "fileBudget")) {
                    $subtask | Add-Member -NotePropertyName "fileBudget" -NotePropertyValue 3
                }
                if (-not (Test-RalphAutoProperty -Object $subtask -Name "splitRequired")) {
                    $subtask | Add-Member -NotePropertyName "splitRequired" -NotePropertyValue $false
                }
                if (-not (Test-RalphAutoProperty -Object $subtask -Name "sourceStoryId")) {
                    $subtask | Add-Member -NotePropertyName "sourceStoryId" -NotePropertyValue ([string]$storyCopy.id)
                }

                $subtask.dependsOn = @(ConvertTo-RalphAutoStringArray -Value $subtask.dependsOn)
                $subtask.estimatedFiles = @(ConvertTo-RalphAutoStringArray -Value $subtask.estimatedFiles)
                $subtask.touches = @(ConvertTo-RalphAutoStringArray -Value $subtask.touches)
                $subtask.stateWrites = @(ConvertTo-RalphAutoStringArray -Value $subtask.stateWrites)
                $subtasks += $subtask
                $index++
            }
        } else {
            $subtasks = @(Split-RalphAutoStoryIntoSubtasks -Story $storyCopy)
        }

        if (Test-RalphAutoProperty -Object $storyCopy -Name "subtasks") {
            $storyCopy.subtasks = @($subtasks | Sort-Object priority, id)
        } else {
            $storyCopy | Add-Member -NotePropertyName "subtasks" -NotePropertyValue @($subtasks | Sort-Object priority, id)
        }

        $computedPasses = (@($storyCopy.subtasks | Where-Object { $_.passes -ne $true }).Count -eq 0)
        if (Test-RalphAutoProperty -Object $storyCopy -Name "passes") {
            $storyCopy.passes = $computedPasses
        } else {
            $storyCopy | Add-Member -NotePropertyName "passes" -NotePropertyValue $computedPasses
        }
        $normalized += $storyCopy
    }

    return $normalized
}

# Writes a normalized PRD back to disk.
function Update-RalphAutoPrdStories {
    param(
        [string]$PrdPath,
        [object]$Prd
    )

    $Prd.userStories = @(ConvertTo-RalphAutoNormalizedStories -Stories @($Prd.userStories))
    $Prd | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $PrdPath -Encoding UTF8
    return $Prd
}

# Returns all normalized subtasks with their parent story metadata.
function Get-RalphAutoPrdSubtasks {
    param([object]$Prd)

    $items = @()
    foreach ($story in @($Prd.userStories | Sort-Object priority)) {
        foreach ($subtask in @($story.subtasks | Sort-Object priority, id)) {
            $items += [pscustomobject]@{
                StoryId = [string]$story.id
                StoryTitle = [string]$story.title
                StoryPriority = [int]$story.priority
                Story = $story
                Subtask = $subtask
            }
        }
    }

    return $items
}

# Returns true when two subtasks have a file/touch/state conflict.
function Test-RalphAutoSubtaskConflict {
    param(
        [object]$Left,
        [object]$Right
    )

    $leftFiles = @(ConvertTo-RalphAutoStringArray -Value $Left.estimatedFiles)
    $rightFiles = @(ConvertTo-RalphAutoStringArray -Value $Right.estimatedFiles)
    if ((@($leftFiles | Where-Object { $rightFiles -contains $_ })).Count -gt 0) {
        return $true
    }

    $leftTouches = @(ConvertTo-RalphAutoStringArray -Value $Left.touches)
    $rightTouches = @(ConvertTo-RalphAutoStringArray -Value $Right.touches)
    if ((@($leftTouches | Where-Object { $rightTouches -contains $_ })).Count -gt 0) {
        return $true
    }

    $leftStates = @(ConvertTo-RalphAutoStringArray -Value $Left.stateWrites)
    $rightStates = @(ConvertTo-RalphAutoStringArray -Value $Right.stateWrites)
    if ((@($leftStates | Where-Object { $rightStates -contains $_ })).Count -gt 0) {
        return $true
    }

    return $false
}

# Plans executable subtask batches, grouping safe parallel work together.
function New-RalphAutoExecutionPlan {
    param([object]$Prd)

    $subtasks = @(Get-RalphAutoPrdSubtasks -Prd $Prd)
    $completedSubtaskIds = @($subtasks | Where-Object { $_.Subtask.passes -eq $true } | ForEach-Object { [string]$_.Subtask.id })
    $pending = @($subtasks | Where-Object { $_.Subtask.passes -ne $true } | Sort-Object StoryPriority, @{ Expression = { [int]$_.Subtask.priority } }, @{ Expression = { [string]$_.Subtask.id } })
    $batches = @()
    $analysisNotes = @()

    while ($pending.Count -gt 0) {
        $ready = @()
        foreach ($item in $pending) {
            $dependsOn = @(ConvertTo-RalphAutoStringArray -Value $item.Subtask.dependsOn)
            $blocked = @($dependsOn | Where-Object { $completedSubtaskIds -notcontains $_ })
            if ($blocked.Count -eq 0) {
                $ready += $item
            }
        }

        if ($ready.Count -eq 0) {
            throw "No executable subtasks remain. Check dependsOn cycles or unresolved priorities in prd.json."
        }

        $batch = @()
        foreach ($item in $ready) {
            $subtask = $item.Subtask
            $isOversized = [int]$subtask.fileBudget -gt 0 -and @(ConvertTo-RalphAutoStringArray -Value $subtask.estimatedFiles).Count -gt [int]$subtask.fileBudget
            if ($isOversized) {
                throw "Subtask $([string]$subtask.id) exceeds fileBudget. Split this subtask before execution or reduce estimatedFiles to fit the budget."
            }

            $conflicts = @($batch | Where-Object { Test-RalphAutoSubtaskConflict -Left $_.Subtask -Right $subtask })
            if ($batch.Count -eq 0) {
                $batch += $item
                continue
            }

            if ($subtask.parallelSafe -eq $true -and -not $isOversized -and $conflicts.Count -eq 0) {
                $batch += $item
            } elseif ($batch.Count -eq 0) {
                $batch += $item
            }
        }

        if ($batch.Count -eq 0) {
            $batch = @($ready[0])
        }

        $batches += ,@($batch)
        foreach ($item in $batch) {
            $completedSubtaskIds += [string]$item.Subtask.id
        }
        $selectedIds = @($batch | ForEach-Object { [string]$_.Subtask.id })
        $pending = @($pending | Where-Object { $selectedIds -notcontains [string]$_.Subtask.id })
    }

    return [pscustomobject]@{
        Batches = $batches
        AnalysisNotes = $analysisNotes
    }
}

# Writes execution analysis details into progress.txt.
function Write-RalphAutoExecutionAnalysis {
    param(
        [string]$ProgressPath,
        [string]$RunId,
        [object]$Plan
    )

    Initialize-RalphAutoProgressLog -ProgressPath $ProgressPath
    $existing = Get-Content -LiteralPath $ProgressPath -Raw -Encoding UTF8
    if ($existing -match [regex]::Escape("Execution analysis for Run ID: $RunId")) {
        return
    }

    $subtaskCount = 0
    foreach ($batch in @($Plan.Batches)) {
        $subtaskCount += @($batch).Count
    }

    "" | Add-Content -LiteralPath $ProgressPath -Encoding UTF8
    "## $(Get-Date -Format 'yyyy-MM-dd HH:mm zzz') - Execution analysis for Run ID: $RunId" | Add-Content -LiteralPath $ProgressPath -Encoding UTF8
    "- Subtasks analyzed: $subtaskCount" | Add-Content -LiteralPath $ProgressPath -Encoding UTF8
    "- Parallel batches: $(@($Plan.Batches | Where-Object { @($_).Count -gt 1 }).Count)" | Add-Content -LiteralPath $ProgressPath -Encoding UTF8
    $index = 1
    foreach ($batch in @($Plan.Batches)) {
        $mode = if (@($batch).Count -gt 1) { "parallel" } else { "serial" }
        $ids = (@($batch | ForEach-Object { "$([string]$_.StoryId)/$([string]$_.Subtask.id)" }) -join ", ")
        "- Batch $index ($mode): $ids" | Add-Content -LiteralPath $ProgressPath -Encoding UTF8
        $index++
    }
    foreach ($note in @($Plan.AnalysisNotes)) {
        "- Note: $note" | Add-Content -LiteralPath $ProgressPath -Encoding UTF8
    }
    "---" | Add-Content -LiteralPath $ProgressPath -Encoding UTF8
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

    $status = @(Get-RalphAutoGitStatus -Path $Path)
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

    $ignoredSuffixes = @(
        "scripts/ralph/.run-lock.json",
        "scripts\ralph\.run-lock.json"
    )

    return @($status | Where-Object {
        $line = [string]$_
        foreach ($suffix in $ignoredSuffixes) {
            if ($line.TrimEnd() -like "*$suffix") {
                return $false
            }
        }

        return $true
    })
}

# Creates a standard Ralph progress log when it is missing.
function Initialize-RalphAutoProgressLog {
    param([string]$ProgressPath)

    if (-not (Test-Path -LiteralPath $ProgressPath)) {
        "# Ralph Progress Log" | Set-Content -LiteralPath $ProgressPath -Encoding UTF8
        "Started: $(Get-Date -Format o)" | Add-Content -LiteralPath $ProgressPath -Encoding UTF8
        "---" | Add-Content -LiteralPath $ProgressPath -Encoding UTF8
    }
}

# Returns the current git branch name when available.
function Get-RalphAutoGitBranch {
    param([string]$Path)

    $branch = (& $GitCommand -C $Path branch --show-current 2>$null)
    if ($LASTEXITCODE -ne 0) {
        throw "Cannot determine git branch for $Path"
    }

    return [string]$branch
}

# Returns the project-level Ralph lock file path.
function Get-RalphAutoLockPath {
    param([string]$ProjectRoot)

    return Join-Path $ProjectRoot "scripts\ralph\.run-lock.json"
}

# Creates a filesystem-safe Ralph run identifier.
function New-RalphAutoRunId {
    param([string]$Mode)

    $safeMode = Get-RalphAutoSafeName -Value $Mode
    return "$(Get-Date -Format 'yyyyMMdd-HHmmss')-$safeMode-$PID"
}

# Reads the Ralph lock record when present.
function Read-RalphAutoLockRecord {
    param([string]$LockPath)

    if (-not (Test-Path -LiteralPath $LockPath)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $LockPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

# Returns true when the lock holder still appears to be running.
function Test-RalphAutoLockRecordActive {
    param([object]$Record)

    if ($null -eq $Record) {
        return $false
    }

    $pidValue = 0
    if (-not [int]::TryParse([string]$Record.pid, [ref]$pidValue)) {
        return $false
    }

    $hostName = [string]$Record.host
    if (-not [string]::IsNullOrWhiteSpace($hostName) -and $hostName -ne $env:COMPUTERNAME) {
        return $true
    }

    $process = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
    return $null -ne $process
}

# Returns the current Ralph lock state for a project.
function Get-RalphAutoLockState {
    param([string]$ProjectRoot)

    $lockPath = Get-RalphAutoLockPath -ProjectRoot $ProjectRoot
    $record = Read-RalphAutoLockRecord -LockPath $lockPath
    $exists = Test-Path -LiteralPath $lockPath
    $isActive = $exists -and (Test-RalphAutoLockRecordActive -Record $record)
    $isStale = $exists -and -not $isActive

    return [pscustomobject]@{
        Path = $lockPath
        Exists = $exists
        IsActive = $isActive
        IsStale = $isStale
        Record = $record
    }
}

# Formats a human-readable lock conflict message.
function Get-RalphAutoLockConflictMessage {
    param(
        [string]$ProjectName,
        [object]$LockState
    )

    $record = $LockState.Record
    $mode = if ($null -ne $record) { [string]$record.mode } else { "unknown" }
    $startedAt = if ($null -ne $record) { [string]$record.startedAt } else { "unknown" }
    $runId = if ($null -ne $record) { [string]$record.runId } else { "unknown" }
    $pidText = if ($null -ne $record) { [string]$record.pid } else { "unknown" }
    return "Project '$ProjectName' is already locked by active Ralph session $runId (mode=$mode pid=$pidText started=$startedAt). Wait for it to finish, inspect the lock with ReviewProject, or use RunParallel if isolated parallel work is intended."
}

# Writes a new project lock record, replacing stale locks when needed.
function Acquire-RalphAutoProjectLock {
    param(
        [string]$ProjectName,
        [string]$ProjectRoot,
        [string]$WorkspaceRoot,
        [string]$Mode,
        [string]$RunId
    )

    $lockPath = Get-RalphAutoLockPath -ProjectRoot $ProjectRoot
    $lockDir = Split-Path -Parent $lockPath
    New-Item -ItemType Directory -Force -Path $lockDir | Out-Null

    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        $state = Get-RalphAutoLockState -ProjectRoot $ProjectRoot
        if ($state.Exists) {
            if ($state.IsActive) {
                throw (Get-RalphAutoLockConflictMessage -ProjectName $ProjectName -LockState $state)
            }

            Remove-Item -LiteralPath $state.Path -Force -ErrorAction SilentlyContinue
        }

        $record = [ordered]@{
            project = $ProjectName
            mode = $Mode
            pid = $PID
            host = $env:COMPUTERNAME
            startedAt = (Get-Date -Format o)
            workspaceRoot = $WorkspaceRoot
            projectRoot = $ProjectRoot
            branch = (Get-RalphAutoGitBranch -Path $ProjectRoot)
            runId = $RunId
        }

        try {
            $stream = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            try {
                $writer = New-Object System.IO.StreamWriter($stream, [Text.Encoding]::UTF8)
                $writer.Write(($record | ConvertTo-Json -Depth 8))
                $writer.Flush()
            }
            finally {
                if ($null -ne $writer) {
                    $writer.Dispose()
                }
                $stream.Dispose()
            }

            return $record
        }
        catch [System.IO.IOException] {
            Start-Sleep -Milliseconds 200
        }
    }

    $finalState = Get-RalphAutoLockState -ProjectRoot $ProjectRoot
    throw (Get-RalphAutoLockConflictMessage -ProjectName $ProjectName -LockState $finalState)
}

# Releases the project lock owned by the current session.
function Release-RalphAutoProjectLock {
    param(
        [string]$ProjectRoot,
        [string]$RunId
    )

    $state = Get-RalphAutoLockState -ProjectRoot $ProjectRoot
    if (-not $state.Exists -or $null -eq $state.Record) {
        return
    }

    if ([string]$state.Record.runId -ne $RunId) {
        return
    }

    if ([string]$state.Record.pid -ne [string]$PID) {
        return
    }

    Remove-Item -LiteralPath $state.Path -Force -ErrorAction SilentlyContinue
}

# Appends a Ralph session header to progress.txt once per run.
function Write-RalphAutoSessionHeader {
    param(
        [string]$ProgressPath,
        [string]$ProjectName,
        [string]$Mode,
        [string]$RunId,
        [string]$Branch
    )

    Initialize-RalphAutoProgressLog -ProgressPath $ProgressPath
    $existing = Get-Content -LiteralPath $ProgressPath -Raw -Encoding UTF8
    if ($existing -match [regex]::Escape("Run ID: $RunId")) {
        return
    }

    "" | Add-Content -LiteralPath $ProgressPath -Encoding UTF8
    "## $(Get-Date -Format 'yyyy-MM-dd HH:mm zzz') - Ralph session" | Add-Content -LiteralPath $ProgressPath -Encoding UTF8
    "- Project: $ProjectName" | Add-Content -LiteralPath $ProgressPath -Encoding UTF8
    "- Mode: $Mode" | Add-Content -LiteralPath $ProgressPath -Encoding UTF8
    "- Run ID: $RunId" | Add-Content -LiteralPath $ProgressPath -Encoding UTF8
    "- Branch: $Branch" | Add-Content -LiteralPath $ProgressPath -Encoding UTF8
    "- Started: $(Get-Date -Format o)" | Add-Content -LiteralPath $ProgressPath -Encoding UTF8
    "---" | Add-Content -LiteralPath $ProgressPath -Encoding UTF8
}

# Appends a dirty-baseline note so continuation runs are visible in Ralph state.
function Add-RalphAutoDirtyBaselineNote {
    param(
        [string]$ProjectRoot,
        [string]$ProjectName,
        [string]$RunId = ""
    )

    $status = @(Get-RalphAutoGitStatus -Path $ProjectRoot)
    if ($status.Count -eq 0) {
        return
    }

    $ralphDir = Join-Path $ProjectRoot "scripts\ralph"
    $progressPath = Join-Path $ralphDir "progress.txt"
    $prdPath = Join-Path $ralphDir "prd.json"
    $branch = Get-RalphAutoGitBranch -Path $ProjectRoot
    Initialize-RalphAutoProgressLog -ProgressPath $progressPath

    "" | Add-Content -LiteralPath $progressPath -Encoding UTF8
    "## $(Get-Date -Format 'yyyy-MM-dd HH:mm zzz') - Dirty baseline continuation" | Add-Content -LiteralPath $progressPath -Encoding UTF8
    "- Project: $ProjectName" | Add-Content -LiteralPath $progressPath -Encoding UTF8
    if (-not [string]::IsNullOrWhiteSpace($RunId)) {
        "- Run ID: $RunId" | Add-Content -LiteralPath $progressPath -Encoding UTF8
    }
    "- Branch: $branch" | Add-Content -LiteralPath $progressPath -Encoding UTF8
    "- Mode: RunProject allowed dirty continuation; no auto-commit, no branch switch, no RunParallel." | Add-Content -LiteralPath $progressPath -Encoding UTF8
    "- Git status:" | Add-Content -LiteralPath $progressPath -Encoding UTF8
    foreach ($line in $status) {
        "  $line" | Add-Content -LiteralPath $progressPath -Encoding UTF8
    }
    "---" | Add-Content -LiteralPath $progressPath -Encoding UTF8

    if (Test-Path -LiteralPath $prdPath) {
        $prd = Get-Content -LiteralPath $prdPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $note = "Dirty baseline continuation on branch $branch at $(Get-Date -Format o)."
        if (Test-RalphAutoProperty -Object $prd -Name "dirtyBaseline") {
            $prd.dirtyBaseline = $note
        } else {
            $prd | Add-Member -NotePropertyName "dirtyBaseline" -NotePropertyValue $note
        }

        $prd | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $prdPath -Encoding UTF8
    }
}

# Creates a minimal runnable PRD for a newly created ad-hoc Ralph project.
function Initialize-RalphAutoAdhocState {
    param(
        [string]$ProjectRoot,
        [string]$ProjectName
    )

    $ralphDir = Join-Path $ProjectRoot "scripts\ralph"
    $prdPath = Join-Path $ralphDir "prd.json"
    $progressPath = Join-Path $ralphDir "progress.txt"
    $branchName = "ralph/adhoc/$((Get-RalphAutoSafeName -Value $ProjectName))"

    if (-not (Test-Path -LiteralPath $prdPath)) {
        $template = [ordered]@{
            project = $ProjectName
            branchName = $branchName
            description = "Ad-hoc Ralph project bootstrap"
            userStories = @(
                [ordered]@{
                    id = "US-001"
                    title = "Replace bootstrap PRD with the current execution plan"
                    description = "Update scripts\\ralph\\prd.json from the latest plan before running Ralph."
                    acceptanceCriteria = @(
                        "Replace the placeholder PRD with concrete stories derived from the intended task.",
                        "Keep passes set to false until work is complete."
                    )
                    priority = 1
                    passes = $false
                    notes = "Bootstrap story generated by CreateAdhocProject."
                }
            )
        }

        $template | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $prdPath -Encoding UTF8
    }

    Initialize-RalphAutoProgressLog -ProgressPath $progressPath
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

# Creates and registers an ad-hoc Ralph project inside the workspace.
function New-RalphAutoAdhocProject {
    param(
        [string]$Root,
        [string]$Name
    )

    $projectName = $Name
    if ([string]::IsNullOrWhiteSpace($projectName)) {
        $projectName = "ra-adhoc-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    }

    $safeName = Get-RalphAutoSafeName -Value $projectName
    $projectRoot = Join-Path $Root "projects\$safeName"
    if (Test-Path -LiteralPath $projectRoot) {
        throw "Ad-hoc project already exists: $projectRoot"
    }

    New-Item -ItemType Directory -Force -Path $projectRoot | Out-Null
    & $GitCommand -C $projectRoot init | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to initialize git repository: $projectRoot"
    }

    Add-RalphAutoProject -Root $Root -Name $safeName -Path $projectRoot
    Copy-RalphAutoTemplates -ProjectRoot $projectRoot
    Initialize-RalphAutoAdhocState -ProjectRoot $projectRoot -ProjectName $safeName

    Write-Host "Created ad-hoc project: $safeName"
    Write-Host "Project root: $projectRoot"
    Write-Host "PRD: $(Join-Path $projectRoot 'scripts\ralph\prd.json')"
    Write-Host "Progress: $(Join-Path $projectRoot 'scripts\ralph\progress.txt')"
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

    $lockState = Get-RalphAutoLockState -ProjectRoot $projectRoot
    if ($lockState.IsActive -and $null -ne $lockState.Record) {
        Write-Host "Active lock: yes"
        Write-Host "  Mode: $([string]$lockState.Record.mode)"
        Write-Host "  Run ID: $([string]$lockState.Record.runId)"
        Write-Host "  PID: $([string]$lockState.Record.pid)"
        Write-Host "  Started: $([string]$lockState.Record.startedAt)"
    } elseif ($lockState.IsStale) {
        Write-Host "Active lock: stale"
        Write-Host "  Lock path: $($lockState.Path)"
    } else {
        Write-Host "Active lock: none"
    }

    $branch = (& $GitCommand -C $projectRoot branch --show-current 2>$null)
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($branch)) {
        Write-Host "Git branch: $branch"
    }

    Write-Host "Git status:"
    $status = @(& $GitCommand -C $projectRoot status --short 2>$null)
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  unavailable"
    } elseif (@($status).Count -eq 0) {
        Write-Host "  clean"
    } else {
        $status | ForEach-Object { Write-Host "  $_" }
    }

    if (Test-Path -LiteralPath $prdPath) {
        $prd = Get-Content -LiteralPath $prdPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $prd = Update-RalphAutoPrdStories -PrdPath $prdPath -Prd $prd
        $stories = @($prd.userStories)
        $subtasks = @(Get-RalphAutoPrdSubtasks -Prd $prd)
        $unfinished = @($stories | Where-Object { $_.passes -ne $true })
        $pendingSubtasks = @($subtasks | Where-Object { $_.Subtask.passes -ne $true })
        Write-Host "PRD: $prdPath"
        Write-Host "Stories: $(@($stories).Count)"
        Write-Host "Unfinished: $(@($unfinished).Count)"
        Write-Host "Pending subtasks: $(@($pendingSubtasks).Count)"
        foreach ($story in ($unfinished | Sort-Object priority | Select-Object -First 5)) {
            Write-Host "  $($story.id): $($story.title)"
        }
        foreach ($item in ($pendingSubtasks | Select-Object -First 5)) {
            Write-Host "    $([string]$item.Subtask.id): $([string]$item.Subtask.title)"
        }
    } else {
        Write-Host "PRD: missing"
        Write-Host "Next step: create or hand off a plan, then write it to $prdPath before RunProject."
        Write-Host "  Suggested action: use Ralph Auto with a project goal, or run InitProject and convert the PRD into scripts\ralph\prd.json."
    }

    if (Test-Path -LiteralPath $progressPath) {
        Write-Host "Progress: $progressPath"
        Write-Host "Progress tail:"
        Get-Content -LiteralPath $progressPath -Tail 20 -Encoding UTF8 | ForEach-Object {
            Write-Host "  $_"
        }
    } else {
        Write-Host "Progress: missing"
        Write-Host "Next step: initialize Ralph state or rerun RunProject after prd.json exists so progress.txt can be created."
        Write-Host "  Suggested action: run InitProject for a new handoff, or RunProject to create progress.txt for an existing PRD."
    }

    if (Test-Path -LiteralPath $runsDir) {
        $runs = @(Get-ChildItem -LiteralPath $runsDir -File | Sort-Object LastWriteTime -Descending | Select-Object -First 5)
        Write-Host "Recent runs:"
        if (@($runs).Count -eq 0) {
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

    $runId = New-RalphAutoRunId -Mode "RunProject"
    $branch = Get-RalphAutoGitBranch -Path $projectRoot
    $progressPath = Join-Path $projectRoot "scripts\ralph\progress.txt"
    $projectLockReleased = $false
    $prdPath = Join-Path $projectRoot "scripts\ralph\prd.json"
    $gitStatus = @(Get-RalphAutoGitStatus -Path $projectRoot)

    if (Test-Path -LiteralPath $prdPath) {
        $prd = Get-Content -LiteralPath $prdPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $prd = Update-RalphAutoPrdStories -PrdPath $prdPath -Prd $prd
        $executionPlan = New-RalphAutoExecutionPlan -Prd $prd
    }
    $lockRecord = Acquire-RalphAutoProjectLock -ProjectName $Name -ProjectRoot $projectRoot -WorkspaceRoot $Root -Mode "RunProject" -RunId $runId
    Write-RalphAutoSessionHeader -ProgressPath $progressPath -ProjectName $Name -Mode "RunProject" -RunId $runId -Branch $branch
    if ($null -ne $executionPlan) {
        Write-RalphAutoExecutionAnalysis -ProgressPath $progressPath -RunId $runId -Plan $executionPlan
        $parallelBatch = @($executionPlan.Batches | Where-Object { @($_).Count -gt 1 } | Select-Object -First 1)
        if (@($parallelBatch).Count -gt 0 -and @($gitStatus).Count -eq 0) {
            Write-Host "Auto-detected safe parallel subtasks. Delegating this run to RunParallel."
            Release-RalphAutoProjectLock -ProjectRoot $projectRoot -RunId $runId
            $projectLockReleased = $true
            Invoke-RalphAutoParallelProject -Root $Root -Name $Name -Iterations $Iterations -Workers ([Math]::Min($MaxWorkers, @($parallelBatch[0]).Count)) -RequestedModel $RequestedModel -SkipMerge:$false -RemoveSuccessfulWorktrees:$false -PreviewOnly:$false
            return
        }
    }

    if (@($gitStatus).Count -gt 0) {
        Write-Host "Dirty continuation detected for RunProject. Continuing without auto-commit or branch changes."
        $gitStatus | ForEach-Object { Write-Host "  $_" }
        Add-RalphAutoDirtyBaselineNote -ProjectRoot $projectRoot -ProjectName $Name -RunId $runId
    }

    $args = @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $runnerPath,
        "-ProjectRoot",
        $projectRoot,
        "-RunId",
        $runId,
        "-MaxIterations",
        $Iterations
    )

    if (@($gitStatus).Count -gt 0) {
        $args += "-AllowDirtyContinuation"
    }

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
        if (-not $projectLockReleased) {
            Release-RalphAutoProjectLock -ProjectRoot $projectRoot -RunId $runId
        }
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
    $prd = Update-RalphAutoPrdStories -PrdPath $prdPath -Prd $prd
    $executionPlan = New-RalphAutoExecutionPlan -Prd $prd
    $parallelBatch = @($executionPlan.Batches | Where-Object { @($_).Count -gt 1 } | Select-Object -First 1)
    if ($parallelBatch.Count -eq 0) {
        throw "No parallel-safe ready subtasks found. Mark subtasks with parallelSafe: true, satisfied dependsOn, and non-conflicting file/state surfaces."
    }

    $selected = @($parallelBatch[0] | Select-Object -First $Workers)
    if ($selected.Count -eq 0) {
        throw "No executable subtasks selected for RunParallel."
    }

    $runId = New-RalphAutoRunId -Mode "RunParallel"
    $safeProject = Get-RalphAutoSafeName -Value $Name
    $taskRoot = Join-Path $Root "tasks\$safeProject\$runId"
    $baseBranch = (& $GitCommand -C $projectRoot branch --show-current)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($baseBranch)) {
        throw "Cannot determine current branch for $projectRoot"
    }

    $progressPath = Join-Path $ralphDir "progress.txt"

    Write-Host "RunParallel project: $Name"
    Write-Host "Project root: $projectRoot"
    Write-Host "Base branch: $baseBranch"
    Write-Host "Task root: $taskRoot"
    Write-Host "Selected subtasks:"
    $selected | ForEach-Object { Write-Host "  $([string]$_.Subtask.id): $([string]$_.Subtask.title)" }

    if ($PreviewOnly) {
        Write-Host "DryRun: no worktrees created and no workers started."
        foreach ($item in $selected) {
            $storyId = Get-RalphAutoSafeName -Value ([string]$item.Subtask.id)
            $branchName = "ralph/parallel/$safeProject/$storyId-$runId"
            $worktreePath = Join-Path $taskRoot $storyId
            Write-Host "Would create: $worktreePath"
            Write-Host "Would branch: $branchName"
        }
        return
    }

    $lockRecord = Acquire-RalphAutoProjectLock -ProjectName $Name -ProjectRoot $projectRoot -WorkspaceRoot $Root -Mode "RunParallel" -RunId $runId
    Write-RalphAutoSessionHeader -ProgressPath $progressPath -ProjectName $Name -Mode "RunParallel" -RunId $runId -Branch $baseBranch
    Write-RalphAutoExecutionAnalysis -ProgressPath $progressPath -RunId $runId -Plan $executionPlan

    try {
        New-Item -ItemType Directory -Force -Path $taskRoot | Out-Null
        $jobs = @()

        foreach ($item in $selected) {
            $subtask = $item.Subtask
            $storyId = Get-RalphAutoSafeName -Value ([string]$subtask.id)
            $branchName = "ralph/parallel/$safeProject/$storyId-$runId"
            $worktreePath = Join-Path $taskRoot $storyId

            & $GitCommand -C $projectRoot worktree add -b $branchName $worktreePath $baseBranch | Out-Host
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to create worktree for $($subtask.id)"
            }

            Copy-RalphAutoTemplates -ProjectRoot $worktreePath

            $workerRalphDir = Join-Path $worktreePath "scripts\ralph"
            $workerPrdPath = Join-Path $workerRalphDir "prd.json"
            $workerPrd = $prd | ConvertTo-Json -Depth 20 | ConvertFrom-Json
            $workerPrd.branchName = $branchName
            $workerStory = $item.Story | ConvertTo-Json -Depth 20 | ConvertFrom-Json
            $workerStory.subtasks = @($subtask)
            $workerStory.passes = ($subtask.passes -eq $true)
            $workerPrd.userStories = @($workerStory)
            if (Test-RalphAutoProperty -Object $workerPrd -Name "runId") {
                $workerPrd.runId = $runId
            } else {
                $workerPrd | Add-Member -NotePropertyName "runId" -NotePropertyValue $runId
            }
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
                "-RunId",
                $runId,
                "-MaxIterations",
                $Iterations
            )

            if (-not [string]::IsNullOrWhiteSpace($RequestedModel)) {
                $workerArgs += @("-Model", $RequestedModel)
            }

            Write-Host "Starting worker $($subtask.id): pwsh $($workerArgs -join ' ')"
            $job = Start-Job -Name $subtask.id -ScriptBlock {
                param([string[]]$ArgsForPwsh)
                & pwsh @ArgsForPwsh
                if ($LASTEXITCODE -ne 0) {
                    throw "Ralph worker exited with code $LASTEXITCODE"
                }
            } -ArgumentList (,$workerArgs)

            $jobs += [pscustomobject]@{
                StoryId = [string]$item.StoryId
                StoryTitle = [string]$item.StoryTitle
                SubtaskId = [string]$subtask.id
                SubtaskTitle = [string]$subtask.title
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
            $failed | ForEach-Object { Write-Host "  $($_.SubtaskId): $($_.Worktree)" }
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
            $mainPrd = Update-RalphAutoPrdStories -PrdPath $prdPath -Prd $mainPrd
            foreach ($item in $jobs) {
                $mainStory = @($mainPrd.userStories | Where-Object { $_.id -eq $item.StoryId }) | Select-Object -First 1
                if ($null -ne $mainStory) {
                    $mainSubtask = @($mainStory.subtasks | Where-Object { $_.id -eq $item.SubtaskId }) | Select-Object -First 1
                    if ($null -ne $mainSubtask) {
                        $mainSubtask.passes = $true
                        $subtaskNote = "Completed by parallel RA worker branch $($item.Branch)"
                        if (Test-RalphAutoProperty -Object $mainSubtask -Name "notes") {
                            $mainSubtask.notes = $subtaskNote
                        } else {
                            $mainSubtask | Add-Member -NotePropertyName "notes" -NotePropertyValue $subtaskNote
                        }
                    }
                    $mainStory.passes = (@($mainStory.subtasks | Where-Object { $_.passes -ne $true }).Count -eq 0)
                    $note = "Parallel subtask progress updated for $($item.SubtaskId)"
                    if (Test-RalphAutoProperty -Object $mainStory -Name "notes") {
                        $mainStory.notes = $note
                    } else {
                        $mainStory | Add-Member -NotePropertyName "notes" -NotePropertyValue $note
                    }
                }
            }

            $mainPrd | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $prdPath -Encoding UTF8
            if (-not (Test-Path -LiteralPath $progressPath)) {
                "# Ralph Progress Log" | Set-Content -LiteralPath $progressPath -Encoding UTF8
                "Started: $(Get-Date -Format o)" | Add-Content -LiteralPath $progressPath -Encoding UTF8
                "---" | Add-Content -LiteralPath $progressPath -Encoding UTF8
            }

            foreach ($item in $jobs) {
                "" | Add-Content -LiteralPath $progressPath -Encoding UTF8
                "## $(Get-Date -Format 'yyyy-MM-dd HH:mm zzz') - $($item.SubtaskId)" | Add-Content -LiteralPath $progressPath -Encoding UTF8
                "- Run ID: $runId" | Add-Content -LiteralPath $progressPath -Encoding UTF8
                "- Story: $($item.StoryId) - $($item.StoryTitle)" | Add-Content -LiteralPath $progressPath -Encoding UTF8
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
    finally {
        Release-RalphAutoProjectLock -ProjectRoot $projectRoot -RunId $runId
    }
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

    $runId = New-RalphAutoRunId -Mode "CleanupContext"
    $branch = Get-RalphAutoGitBranch -Path $projectRoot
    $lockRecord = Acquire-RalphAutoProjectLock -ProjectName $Name -ProjectRoot $projectRoot -WorkspaceRoot $Root -Mode "CleanupContext" -RunId $runId
    Write-RalphAutoSessionHeader -ProgressPath $progressPath -ProjectName $Name -Mode "CleanupContext" -RunId $runId -Branch $branch

    try {
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
    finally {
        Release-RalphAutoProjectLock -ProjectRoot $projectRoot -RunId $runId
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
    "CreateAdhocProject" {
        New-RalphAutoAdhocProject -Root $WorkspaceRoot -Name $Project
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
