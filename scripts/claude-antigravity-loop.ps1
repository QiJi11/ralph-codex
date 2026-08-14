param (
    [Parameter(Mandatory=$true)]
    [string]$Task
)

# 1. 确认环境变量（优先 ANTHROPIC_API_KEY，回退到 ANTHROPIC_AUTH_TOKEN）
$apiKey = $env:ANTHROPIC_API_KEY
if ([string]::IsNullOrEmpty($apiKey)) {
    $apiKey = $env:ANTHROPIC_AUTH_TOKEN
}
if ([string]::IsNullOrEmpty($apiKey)) {
    Write-Error "[ERROR] 未检测到 ANTHROPIC_API_KEY 或 ANTHROPIC_AUTH_TOKEN 环境变量。"
    exit 1
}

# 支持自定义 base URL（如 bearlab.ai 代理）
$baseUrl = $env:ANTHROPIC_BASE_URL
if ([string]::IsNullOrEmpty($baseUrl)) {
    $baseUrl = "https://api.anthropic.com"
}
$baseUrl = $baseUrl.TrimEnd('/')
$claudeEndpoint = "$baseUrl/v1/messages"

# 2. 检查目录准备
$progressDir = "C:\Users\tianh\ralph-codex\scripts\ralph"
if (!(Test-Path $progressDir)) {
    New-Item -ItemType Directory -Path $progressDir -Force | Out-Null
}
$progressFile = Join-Path $progressDir "progress.txt"

# 3. 检查端口是否正在监听
$port5000 = Get-NetTCPConnection -LocalPort 5000 -ErrorAction SilentlyContinue
$port9812 = Get-NetTCPConnection -LocalPort 9812 -ErrorAction SilentlyContinue

if (-not $port5000 -or -not $port9812) {
    $errText = @"
[ERROR] 未检测到端口 5000 (HTTP) 和 9812 (WebSocket) 的监听。
这通常是因为 VS Code / Antigravity IDE 需要重载窗口以激活新安装的 'antigravity_automation' 扩展。
请在 Antigravity IDE 中按下 'Ctrl+Shift+P'，输入并运行 'Developer: Reload Window' (重载窗口)。
窗口重载后，扩展会自动激活并在后台监听 5000 和 9812 端口。请在重载完成后重新运行本脚本。
"@
    Write-Host $errText -ForegroundColor Red
    Add-Content -Path $progressFile -Value "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $errText"
    exit 1
}

# 4. 获取最强 Gemini 模型
$cachePath = "C:\Users\tianh\.antigravity_cockpit\cache\available_models.json"
$bestModel = "gemini-3.1-pro-high"
$modelSource = "Default"
if (Test-Path $cachePath) {
    try {
        $modelsJson = Get-Content -Raw $cachePath | ConvertFrom-Json
        $maxVer = 3.1
        foreach ($m in $modelsJson.models) {
            if ($m.id -match "gemini-(\d+(\.\d+)?)-pro") {
                $ver = [double]$Matches[1]
                if ($ver -gt $maxVer) {
                    $maxVer = $ver
                    $bestModel = $m.id
                    $modelSource = "available_models.json"
                }
            }
        }
    } catch {
        # Fallback to default
    }
}

$initMsg = @"
--------------------------------------------------
[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Starting Claude-Antigravity loop.
Task: $Task
Strongest Gemini Model: $bestModel (Source: $modelSource)
--------------------------------------------------
"@
Write-Host $initMsg -ForegroundColor Green
Add-Content -Path $progressFile -Value $initMsg

# 5. 闭环循环主体
$history = ""
$maxIterations = 10
$completed = $false

for ($i = 1; $i -le $maxIterations; $i++) {
    $logMsg = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Iteration ${i}: Preparing prompt for Claude..."
    Write-Host $logMsg -ForegroundColor Cyan
    Add-Content -Path $progressFile -Value $logMsg
    
    $claudePrompt = @"
任务目标：$Task
执行模型：$bestModel（Antigravity Agent，支持终端执行、文件读写、浏览器）
当前轮次：${i} / $maxIterations

已完成的执行记录：
$history

请判断任务进展并在回复最后一行给出指令：
- 如果任务已完成，最后一行写：STATUS: COMPLETE
- 如果还需要继续，最后一行写：INSTRUCTION: <下一步具体操作，可直接在终端或文件系统执行>
"@

    # 调用 Claude API
    $messages = @(
        @{
            role = "user"
            content = $claudePrompt
        }
    )
    $payload = @{
        model = "claude-opus-4-8"
        max_tokens = 4096
        messages = $messages
    }
    
    $jsonBody = ConvertTo-Json $payload -Depth 10 -Compress
    $headers = @{
        "x-api-key"         = $apiKey
        "anthropic-version" = "2023-06-01"
        "anthropic-beta"    = "context-1m-2025-08-07"
        "content-type"      = "application/json"
    }

    Write-Host "Calling Claude API ($claudeEndpoint)..." -ForegroundColor Cyan
    try {
        $response = Invoke-RestMethod -Uri $claudeEndpoint -Method Post -Headers $headers -Body $jsonBody
        # API may return a thinking block first; find the actual text block
        $reply = ($response.content | Where-Object { $_.type -eq "text" } | Select-Object -First 1).text
    } catch {
        $errorMsg = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Error calling Claude API: $_"
        Write-Error $errorMsg
        Add-Content -Path $progressFile -Value $errorMsg
        break
    }
    
    Write-Host "Claude Reply:`n$reply`n" -ForegroundColor Yellow
    
    if ($reply -match "STATUS:\s*COMPLETE") {
        $logMsg = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Iteration ${i}: Claude marked task as COMPLETE.`nSummary: $reply"
        Write-Host $logMsg -ForegroundColor Green
        Add-Content -Path $progressFile -Value $logMsg
        $completed = $true
        break
    }
    
    # 提取指令
    $instruction = $null
    if ($reply -match "(?s)INSTRUCTION:\s*(.*)") {
        $instruction = $Matches[1].Trim()
    } else {
        $instruction = $reply.Trim()
    }
    
    $logMsg = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Iteration ${i}: Sending instruction to Antigravity..."
    Write-Host $logMsg -ForegroundColor Magenta
    Add-Content -Path $progressFile -Value $logMsg
    
    # 通过 CDP 直接发送到 Antigravity 桌面应用的 Agent 面板
    # 回传协议：要求 Agent 执行完毕后把结果写入约定文件，脚本轮询该文件
    $resultFile = "C:\Users\tianh\tmp\agy_result.txt"
    Remove-Item $resultFile -ErrorAction SilentlyContinue

    $fullInstruction = "$instruction`n`n执行完成后，请把执行结果摘要（做了什么、是否成功、关键输出）写入文件 $resultFile"

    try {
        $sendOut = node "C:\Users\tianh\ralph-codex\scripts\cdp-send.js" $fullInstruction 2>&1
        Write-Host "CDP send: $sendOut" -ForegroundColor Cyan

        # 轮询结果文件，最长 10 分钟
        $wsOutput = $null
        for ($w = 1; $w -le 120; $w++) {
            if (Test-Path $resultFile) {
                Start-Sleep -Seconds 2  # 等 Agent 写完
                $wsOutput = Get-Content $resultFile -Raw
                break
            }
            Start-Sleep -Seconds 5
        }
        if ($null -eq $wsOutput) { $wsOutput = "[TIMEOUT] Agent 未在 10 分钟内写入结果文件。" }

        # 记录交互历史
        $history += "--- Iteration $i ---`n"
        $history += "Claude Instruction: $instruction`n"
        $history += "Antigravity Result: $wsOutput`n`n"
        
        $logMsg = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Iteration ${i}: Execution finished. Result length: $($wsOutput.Length) chars."
        Write-Host $logMsg -ForegroundColor Green
        Add-Content -Path $progressFile -Value $logMsg
    } catch {
        $logMsg = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Iteration ${i}: Communication with Antigravity failed: $_"
        Write-Error $logMsg
        Add-Content -Path $progressFile -Value $logMsg
        break
    }
}

if ($completed) {
    Write-Host "Task completed successfully!" -ForegroundColor Green
} else {
    Write-Host "Task did not complete within limit or encountered an error." -ForegroundColor Red
}
