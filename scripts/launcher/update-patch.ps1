# ============================================================================
# Antigravity-Proxy 一键在线更新补丁工具 (update-patch.ps1)
# ============================================================================
# 核心功能:
# 1. 自动对比本地 Patch/ (或 ide/) 与 GitHub 官方最新 Release 版本
# 2. 支持走本地代理端口 (读取 config.json) 及内置国内 GitHub 加速镜像，确保高成功率
# 3. 自动下载最新 Release 压缩包、解压并更新本地 Patch/ 目录
# 4. 智能配置保护：更新新版 DLL 的同时，自动保留用户原有的 proxy.host/port/type 配置
# 5. 更新完成后自动热同步到 Antigravity 安装目录
# ============================================================================

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$NoPause
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = $ScriptDir
if ((Split-Path -Leaf $ScriptDir) -match '^(launcher|scripts)$') {
    $Parent = Split-Path -Parent $ScriptDir
    if ((Test-Path (Join-Path $Parent "Patch")) -or (Test-Path (Join-Path $Parent "ide")) -or (Test-Path (Join-Path $Parent "build.ps1"))) {
        $RootDir = $Parent
    }
}

function Write-Title([string]$Text) {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
}

function Write-Info([string]$Text) { Write-Host "[*] $Text" -ForegroundColor Yellow }
function Write-Ok([string]$Text)   { Write-Host "[✓] $Text" -ForegroundColor Green }
function Write-Warn([string]$Text) { Write-Host "[!] $Text" -ForegroundColor Magenta }
function Write-Err([string]$Text)  { Write-Host "[✗] $Text" -ForegroundColor Red }

# 1. 定位本地补丁目录 (优先 Patch/，其次 ide/)
$PatchDir = Join-Path $RootDir "Patch"
if (-not (Test-Path $PatchDir) -and (Test-Path (Join-Path $RootDir "ide"))) {
    $PatchDir = Join-Path $RootDir "ide"
}
if (-not (Test-Path $PatchDir)) {
    New-Item -ItemType Directory -Path $PatchDir -Force | Out-Null
}

# 2. 读取本地已有版本与代理端口
$localVersion = "未知 (<=2.2)"
$proxyHost = "127.0.0.1"
$proxyPort = 7890
$proxyType = "socks5"
$localConfigFile = Join-Path $PatchDir "config.json"
$hasLocalConfig = Test-Path $localConfigFile

if ($hasLocalConfig) {
    try {
        $cfgJson = Get-Content -LiteralPath $localConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($cfgJson._version) { $localVersion = $cfgJson._version }
        if ($cfgJson.proxy) {
            if ($cfgJson.proxy.host) { $proxyHost = $cfgJson.proxy.host }
            if ($cfgJson.proxy.port) { $proxyPort = $cfgJson.proxy.port }
            if ($cfgJson.proxy.type) { $proxyType = $cfgJson.proxy.type }
        }
    } catch { }
}

Write-Title "Antigravity-Proxy 在线补丁自动更新工具"
Write-Host "  本地补丁目录: $PatchDir"
Write-Host "  当前本地版本: $localVersion"
Write-Host "  本地代理设置: ${proxyType}://${proxyHost}:${proxyPort}"

# 3. 准备网络请求工具（优先使用系统内置 curl.exe，原生支持 socks5/http 代理及 TLS 1.3）
$apiUrl = "https://api.github.com/repos/yuaotian/antigravity-proxy/releases/latest"
$releaseData = $null

Write-Info "正在获取 GitHub 官方仓库最新 Release 信息..."

$curlCmd = Get-Command "curl.exe" -ErrorAction SilentlyContinue
$proxyArg = "http://${proxyHost}:${proxyPort}"
if ($proxyType -eq "socks5") {
    $proxyArg = "socks5h://${proxyHost}:${proxyPort}"
}

if ($curlCmd) {
    foreach ($proxyCandidate in @($proxyArg, "http://${proxyHost}:${proxyPort}", "")) {
        try {
            $argsList = @("-fsSL", "--connect-timeout", "8", "-H", "User-Agent: Antigravity-Updater")
            if ($proxyCandidate) {
                $argsList += @("-x", $proxyCandidate)
            }
            $argsList += $apiUrl
            $respText = (& curl.exe @argsList 2>$null) -join "`n"
            if ($respText -and $respText.Contains("tag_name")) {
                $releaseData = $respText | ConvertFrom-Json
                break
            }
        } catch { }
    }
}

# 兜底：若 curl 未成功，尝试通过加速镜像请求
if (-not $releaseData -or -not $releaseData.tag_name) {
    $webClient = New-Object System.Net.WebClient
    $webClient.Headers.Add("User-Agent", "Antigravity-Update-Script/1.0")
    foreach ($endpoint in @("https://ghproxy.net/$apiUrl", $apiUrl)) {
        try {
            $resp = $webClient.DownloadString($endpoint)
            if ($resp) {
                $releaseData = $resp | ConvertFrom-Json
                if ($releaseData.tag_name) { break }
            }
        } catch { }
    }
}

if (-not $releaseData -or -not $releaseData.tag_name) {
    Write-Err "无法连接到 GitHub Releases 服务，请检查代理端口 ($proxyPort) 是否开启或网络连接状态。"
    if (-not $NoPause) { Read-Host "按回车键退出..." }
    exit 1
}

$remoteTag = $releaseData.tag_name
$remoteVersion = $remoteTag.TrimStart('vV')
Write-Host ""
Write-Ok "获取到最新官方 Release: $remoteTag (发布日期: $($releaseData.published_at))"

# 4. 判断是否需要更新
$needUpdate = $false
if ($localVersion -ne $remoteVersion -or $Force) {
    $needUpdate = $true
}

if (-not $needUpdate) {
    Write-Ok "当前本地补丁版本 ($localVersion) 已是最新版本，无需更新！"
    Write-Host "（如需强制重新下载覆盖，可加参数 -Force 运行）" -ForegroundColor Gray
    if (-not $NoPause) { Read-Host "按回车键退出..." }
    exit 0
}

Write-Info "发现新版本！本地: [$localVersion] -> 最新: [$remoteVersion]"

# 5. 寻找 Windows x64 IDE 资产包下载地址（优先匹配 ide-win-x64.zip）
$asset = $releaseData.assets | Where-Object { $_.name -like "*ide-win-x64.zip" } | Select-Object -First 1
if (-not $asset) {
    $asset = $releaseData.assets | Where-Object { $_.name -like "*-win-x64.zip" -and $_.name -notlike "*cli*" } | Select-Object -First 1
}
if (-not $asset) {
    $asset = $releaseData.assets | Where-Object { $_.name -like "*.zip" } | Select-Object -First 1
}

if (-not $asset) {
    Write-Err "未在最新 Release 中找到适合的 Windows zip 资产包。"
    exit 1
}

$downloadUrl = $asset.browser_download_url
$zipFileName = $asset.name
Write-Info "目标下载包: $zipFileName"

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "ag-proxy-update-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
$tempZip = Join-Path $tempDir $zipFileName

$downloadSuccess = $false
if ($curlCmd) {
    $oldEa = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    foreach ($proxyCandidate in @($proxyArg, "http://${proxyHost}:${proxyPort}", "")) {
        Write-Info "正在通过代理 ($proxyCandidate) 高速下载 $zipFileName ..."
        $dlArgs = @("-fsSL", "--connect-timeout", "10", "-o", $tempZip)
        if ($proxyCandidate) {
            $dlArgs += @("-x", $proxyCandidate)
        }
        $dlArgs += $downloadUrl
        & curl.exe @dlArgs 2>$null
        if ((Test-Path $tempZip) -and (Get-Item $tempZip).Length -gt 10000) {
            $downloadSuccess = $true
            Write-Ok "下载完成！包大小: $([math]::Round((Get-Item $tempZip).Length / 1KB, 1)) KB"
            break
        }
    }
    $ErrorActionPreference = $oldEa
}

if (-not $downloadSuccess) {
    $webClient = New-Object System.Net.WebClient
    $webClient.Headers.Add("User-Agent", "Antigravity-Update-Script/1.0")
    foreach ($url in @("https://ghproxy.net/$downloadUrl", $downloadUrl)) {
        Write-Info "正在通过镜像下载: $url ..."
        try {
            $webClient.DownloadFile($url, $tempZip)
            if ((Test-Path $tempZip) -and (Get-Item $tempZip).Length -gt 10000) {
                $downloadSuccess = $true
                Write-Ok "下载完成！包大小: $([math]::Round((Get-Item $tempZip).Length / 1KB, 1)) KB"
                break
            }
        } catch { }
    }
}

if (-not $downloadSuccess) {
    Write-Err "所有镜像源下载均失败，请检查网络或代理连接。"
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

# 6. 解压并智能更新到 Patch/ 目录
Write-Info "正在解压并更新本地补丁文件..."
$extractDir = Join-Path $tempDir "extracted"
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($tempZip, $extractDir)

# 寻找解压出的补丁文件目录 (可能是 ide/ 或根目录)
$sourceDir = $extractDir
if (Test-Path (Join-Path $extractDir "ide")) {
    $sourceDir = Join-Path $extractDir "ide"
}

# 提取关键文件
$filesToCopy = Get-ChildItem -Path $sourceDir -Recurse -File

foreach ($f in $filesToCopy) {
    $dest = Join-Path $PatchDir $f.Name
    if ($f.Name -eq "config.json" -and $hasLocalConfig) {
        # 智能保护：保留用户原本配置的 proxy.host / port / type 等
        try {
            $newCfg = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($newCfg.proxy) {
                $newCfg.proxy.host = $proxyHost
                $newCfg.proxy.port = $proxyPort
                $newCfg.proxy.type = $proxyType
            }
            # 备份旧配置
            Copy-Item -LiteralPath $localConfigFile -Destination "$localConfigFile.bak" -Force
            # 写入合并后的新配置
            $newCfg | ConvertTo-Json -Depth 10 | Out-File -FilePath $dest -Encoding UTF8
            Write-Ok "已更新 config.json 并智能保留了您的代理设置 (${proxyType}://${proxyHost}:${proxyPort})"
            continue
        } catch { }
    }
    Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
    Write-Ok "已更新补丁文件: $($f.Name)"
}

# 同时更新根目录的可视化配置工具与说明文档 (如果解压包包含)
foreach ($docName in @("config-web.html", "使用说明.md")) {
    $docFile = Join-Path $extractDir $docName
    if (Test-Path $docFile) {
        Copy-Item -LiteralPath $docFile -Destination (Join-Path $RootDir $docName) -Force
    }
}

# 清理临时文件
Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Ok "🎉 补丁更新成功！当前版本已升级至: $remoteTag"

# 7. 立即自动热同步到 Antigravity 安装目录
$appPathFile = Join-Path $RootDir "app_path.txt"
if (Test-Path $appPathFile) {
    $appDir = (Get-Content $appPathFile -Raw -Encoding UTF8).Trim()
    if ($appDir -and (Test-Path $appDir)) {
        Write-Info "正在热同步新补丁到 Antigravity 程序目录 [$appDir]..."
        $installScript = Join-Path $RootDir "launcher\install-windows.ps1"
        if (Test-Path $installScript) {
            & $installScript -Mode SyncOnly -NoPause
        } else {
            foreach ($item in (Get-ChildItem -Path $PatchDir -File)) {
                try {
                    Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $appDir $item.Name) -Force
                } catch { }
            }
        }
        Write-Ok "已将最新补丁热部署至 Antigravity！"
    }
}

Write-Host ""
Write-Ok "全部流程完成！下次启动直接双击快捷方式即可使用最新版 $remoteTag。"

if (-not $NoPause) {
    Write-Host ""
    Read-Host "按回车键关闭窗口..."
}
