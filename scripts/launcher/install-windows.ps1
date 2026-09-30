# ============================================================================
# Antigravity-Proxy 启动守护与快捷方式安装工具 (Windows)
# ============================================================================
# 功能亮点:
# 1. 彻底淘汰易被拦截和弃用的 .vbs 脚本，采用原生 WIN32 GUI 启动器 (AntigravityLauncher.exe)
# 2. 若本地无 C++ 编译产物，自动调用 Windows 内置 .NET 编译器并提取 Antigravity.exe 原生图标动态生成启动器
# 3. 支持一键安装到：[桌面快捷方式]、[开始菜单 (Start Menu)]、[任务栏固定 (Taskbar)]
# 4. 每次双击图标启动时毫秒级自动检测并恢复被客户端自动更新删除的 version.dll / config.json
# ============================================================================

[CmdletBinding()]
param(
    [ValidateSet("Interactive", "All", "Desktop", "StartMenu", "Taskbar", "SyncOnly", "Diagnostics", "Uninstall")]
    [string]$Mode = "Interactive",
    [string]$AppDir = "",
    [switch]$NoPause
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
# 判断当前脚本是在根目录还是在 launcher/ 子目录
$RootDir = $ScriptDir
if ((Split-Path -Leaf $ScriptDir) -match '^(launcher|scripts)$') {
    $Parent = Split-Path -Parent $ScriptDir
    if ((Test-Path (Join-Path $Parent "ide")) -or (Test-Path (Join-Path $Parent "Patch")) -or (Test-Path (Join-Path $Parent "build.ps1"))) {
        $RootDir = $Parent
    }
}

$LauncherDir = if (Test-Path (Join-Path $RootDir "launcher")) { Join-Path $RootDir "launcher" } else { $ScriptDir }
if (-not (Test-Path $LauncherDir)) {
    New-Item -ItemType Directory -Path $LauncherDir -Force | Out-Null
}

$LauncherExe = Join-Path $LauncherDir "AntigravityLauncher.exe"
$ConfigPathFile = Join-Path $RootDir "app_path.txt"

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

# 1. 多维度探测 Antigravity.exe 安装路径
function Find-AntigravityDir([bool]$AllowDialog = $true) {
    if (-not [string]::IsNullOrWhiteSpace($AppDir) -and (Test-Path (Join-Path $AppDir "Antigravity.exe"))) {
        return $AppDir
    }
    if (Test-Path $ConfigPathFile) {
        $saved = (Get-Content $ConfigPathFile -Raw -Encoding UTF8).Trim()
        if ($saved -and (Test-Path (Join-Path $saved "Antigravity.exe"))) {
            return $saved
        }
    }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Antigravity"),
        (Join-Path $env:LOCALAPPDATA "Antigravity"),
        (Join-Path $env:ProgramFiles "Antigravity")
    )
    if (${env:ProgramFiles(x86)}) {
        $candidates += (Join-Path ${env:ProgramFiles(x86)} "Antigravity")
    }

    foreach ($dir in $candidates) {
        if ($dir -and (Test-Path (Join-Path $dir "Antigravity.exe"))) {
            return $dir
        }
    }

    # 注册表 Uninstall 检索
    $regRoots = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($regPath in $regRoots) {
        $items = Get-ItemProperty $regPath -ErrorAction SilentlyContinue |
                 Where-Object { $_.DisplayName -like "*Antigravity*" -and $_.InstallLocation }
        foreach ($item in $items) {
            $loc = $item.InstallLocation.Trim('" ')
            if (Test-Path (Join-Path $loc "Antigravity.exe")) {
                return $loc
            }
        }
    }

    if ($AllowDialog) {
        Write-Warn "未在默认路径检测到 Antigravity.exe，请在弹出窗口中手动选择..."
        Add-Type -AssemblyName System.Windows.Forms
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = "Antigravity 主程序 (Antigravity.exe)|Antigravity.exe"
        $dlg.Title = "请选择 Antigravity.exe 所在位置"
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $selectedDir = [System.IO.Path]::GetDirectoryName($dlg.FileName)
            if (Test-Path (Join-Path $selectedDir "Antigravity.exe")) {
                $selectedDir | Out-File -FilePath $ConfigPathFile -Encoding UTF8 -NoNewline
                return $selectedDir
            }
        }
    }
    return ""
}

# 2. 探测补丁源目录 (兼容官方 Release 的 ide/、cli/、Patch/ 以及根目录)
function Find-PatchSourceDir {
    $candidates = @(
        (Join-Path $RootDir "ide"),
        (Join-Path $RootDir "output\ide"),
        (Join-Path $RootDir "cli"),
        (Join-Path $RootDir "output\cli"),
        (Join-Path $RootDir "Patch"),
        $RootDir
    )
    foreach ($dir in $candidates) {
        if ((Test-Path -LiteralPath $dir) -and ((Test-Path (Join-Path $dir "version.dll")) -or (Test-Path (Join-Path $dir "dbghelp.dll")) -or (Test-Path (Join-Path $dir "config.json")))) {
            return $dir
        }
    }
    return ""
}

# 3. 确保原生无黑框启动器 AntigravityLauncher.exe 存在（若无 C++ 编译产物，则提取原版图标并动态编译）
function Ensure-NativeLauncherExe([string]$TargetAppDir) {
    if (Test-Path $LauncherExe) {
        Write-Ok "已就绪原生启动器: $LauncherExe"
        return $LauncherExe
    }

    Write-Info "正在生成原生无黑框 GUI 启动器 AntigravityLauncher.exe..."
    $iconFile = Join-Path $LauncherDir "antigravity.ico"
    $targetExePath = Join-Path $TargetAppDir "Antigravity.exe"

    # 从 Antigravity.exe 提取原生高清图标用于内嵌到启动器 EXE
    try {
        Add-Type -AssemblyName System.Drawing
        if (Test-Path $targetExePath) {
            $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($targetExePath)
            if ($ico) {
                $fs = New-Object System.IO.FileStream($iconFile, [System.IO.FileMode]::Create)
                $ico.Save($fs)
                $fs.Close()
                $ico.Dispose()
            }
        }
    } catch {
        # 忽略图标提取异常
    }

    $csharpSource = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

public static class AntigravityLauncher {
    [STAThread]
    public static int Main(string[] args) {
        try {
            string exeDir = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\', '/');
            string parentDir = Directory.GetParent(exeDir) != null ? Directory.GetParent(exeDir).FullName : exeDir;
            string rootDir = exeDir;
            if (!File.Exists(Path.Combine(exeDir, "app_path.txt")) &&
                (Directory.Exists(Path.Combine(parentDir, "ide")) || Directory.Exists(Path.Combine(parentDir, "Patch")))) {
                rootDir = parentDir;
            }

            string appDir = DetectAppDir(rootDir);
            if (string.IsNullOrEmpty(appDir) || !File.Exists(Path.Combine(appDir, "Antigravity.exe"))) {
                MessageBox.Show("未能定位到 Antigravity.exe 安装目录，请重新运行【快速安装快捷方式.bat】。",
                    "Antigravity-Proxy 启动守护", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }

            string patchDir = FindPatchDir(exeDir, parentDir);
            if (!string.IsNullOrEmpty(patchDir)) {
                SyncDirectory(patchDir, appDir);
            }

            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = Path.Combine(appDir, "Antigravity.exe");
            psi.WorkingDirectory = appDir;
            if (args != null && args.Length > 0) {
                psi.Arguments = string.Join(" ", args);
            }
            psi.UseShellExecute = true;
            Process.Start(psi);
            return 0;
        } catch (Exception ex) {
            MessageBox.Show("启动异常: " + ex.Message, "Antigravity-Proxy 启动守护", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    private static string DetectAppDir(string rootDir) {
        string cfg = Path.Combine(rootDir, "app_path.txt");
        if (File.Exists(cfg)) {
            string saved = File.ReadAllText(cfg).Trim();
            if (!string.IsNullOrEmpty(saved) && File.Exists(Path.Combine(saved, "Antigravity.exe"))) return saved;
        }
        string[] candidates = new string[] {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Programs\Antigravity"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Antigravity"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), @"Antigravity"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), @"Antigravity")
        };
        foreach (string c in candidates) {
            if (!string.IsNullOrEmpty(c) && File.Exists(Path.Combine(c, "Antigravity.exe"))) return c;
        }
        using (OpenFileDialog ofd = new OpenFileDialog()) {
            ofd.Filter = "Antigravity 主程序 (Antigravity.exe)|Antigravity.exe";
            ofd.Title = "请选择 Antigravity.exe 所在位置（仅首次需要）";
            if (ofd.ShowDialog() == DialogResult.OK) {
                string dir = Path.GetDirectoryName(ofd.FileName);
                File.WriteAllText(cfg, dir);
                return dir;
            }
        }
        return "";
    }

    private static string FindPatchDir(string exeDir, string parentDir) {
        string[] dirs = new string[] {
            Path.Combine(exeDir, "ide"),
            Path.Combine(parentDir, "ide"),
            Path.Combine(exeDir, "output\\ide"),
            Path.Combine(parentDir, "output\\ide"),
            Path.Combine(exeDir, "Patch"),
            Path.Combine(parentDir, "Patch"),
            exeDir
        };
        foreach (string d in dirs) {
            if (File.Exists(Path.Combine(d, "version.dll"))) return d;
        }
        return "";
    }

    private static void SyncDirectory(string srcDir, string dstDir) {
        if (!Directory.Exists(srcDir) || !Directory.Exists(dstDir)) return;
        foreach (string file in Directory.GetFiles(srcDir)) {
            string name = Path.GetFileName(file);
            string dstFile = Path.Combine(dstDir, name);
            bool needCopy = !File.Exists(dstFile);
            if (!needCopy) {
                FileInfo sInfo = new FileInfo(file);
                FileInfo dInfo = new FileInfo(dstFile);
                if (sInfo.Length != dInfo.Length || sInfo.LastWriteTimeUtc > dInfo.LastWriteTimeUtc) {
                    needCopy = true;
                }
            }
            if (needCopy) {
                try { File.Copy(file, dstFile, true); } catch { }
            }
        }
        foreach (string subDir in Directory.GetDirectories(srcDir)) {
            string subName = Path.GetFileName(subDir);
            string dstSub = Path.Combine(dstDir, subName);
            if (!Directory.Exists(dstSub)) {
                try { Directory.CreateDirectory(dstSub); } catch { }
            }
            SyncDirectory(subDir, dstSub);
        }
    }
}
'@

    $compilerOpts = "/target:winexe /optimize+"
    if (Test-Path $iconFile) {
        $compilerOpts += " /win32icon:`"$iconFile`""
    }

    $provider = New-Object Microsoft.CSharp.CSharpCodeProvider
    $cp = New-Object System.CodeDom.Compiler.CompilerParameters
    $cp.GenerateExecutable = $true
    $cp.OutputAssembly = $LauncherExe
    $cp.CompilerOptions = $compilerOpts
    [void]$cp.ReferencedAssemblies.Add("System.dll")
    [void]$cp.ReferencedAssemblies.Add("System.Windows.Forms.dll")
    [void]$cp.ReferencedAssemblies.Add("System.Drawing.dll")

    $results = $provider.CompileAssemblyFromSource($cp, $csharpSource)
    if ($results.Errors.HasErrors) {
        $errMsgs = ($results.Errors | ForEach-Object { $_.ToString() }) -join "`n"
        throw "编译启动器失败:`n$errMsgs"
    }

    Write-Ok "已编译生成原生无黑框启动器: $LauncherExe"
    return $LauncherExe
}

# 4. 同步补丁文件到 Antigravity 安装目录（支持增量比对与运行中进程文件锁保护）
function Sync-PatchFiles([string]$TargetAppDir) {
    $patchDir = Find-PatchSourceDir
    if ([string]::IsNullOrWhiteSpace($patchDir)) {
        Write-Warn "未检测到包含 version.dll 的补丁目录 (ide/ 或 Patch/)，请确保已编译或解压完整 Release 包。"
        return $false
    }

    Write-Info "正在校验并同步补丁 [$patchDir] -> [$TargetAppDir]..."
    $copiedCount = 0
    $skippedCount = 0
    $lockedCount = 0

    Get-ChildItem -LiteralPath $patchDir -Recurse | ForEach-Object {
        $rel = $_.FullName.Substring($patchDir.Length).TrimStart('\', '/')
        $dest = Join-Path $TargetAppDir $rel
        if ($_.PSIsContainer) {
            if (-not (Test-Path $dest)) {
                New-Item -ItemType Directory -Path $dest -Force | Out-Null
            }
        } else {
            $needCopy = $true
            if (Test-Path -LiteralPath $dest -PathType Leaf) {
                $dstItem = Get-Item -LiteralPath $dest
                if ($_.Length -eq $dstItem.Length -and $_.LastWriteTimeUtc -le $dstItem.LastWriteTimeUtc) {
                    $needCopy = $false
                    $skippedCount++
                }
            }
            if ($needCopy) {
                # 端口保护逻辑：如果同步的是 config.json 且目标目录已存在用户配好的非默认端口，优先继承用户的自定义端口设置
                if ($_.Name -eq "config.json" -and (Test-Path -LiteralPath $dest)) {
                    try {
                        $existingJson = Get-Content -LiteralPath $dest -Raw -Encoding UTF8 | ConvertFrom-Json
                        $sourceJson = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                        if ($existingJson.proxy -and $sourceJson.proxy) {
                            $sourceJson.proxy.host = $existingJson.proxy.host
                            $sourceJson.proxy.port = $existingJson.proxy.port
                            $sourceJson.proxy.type = $existingJson.proxy.type
                            $sourceJson | ConvertTo-Json -Depth 10 | Out-File -FilePath $dest -Encoding UTF8
                            $copiedCount++
                            $needCopy = $false
                        }
                    } catch { }
                }
                if ($needCopy) {
                    try {
                        Copy-Item -LiteralPath $_.FullName -Destination $dest -Force -ErrorAction Stop
                        $copiedCount++
                    } catch {
                        $lockedCount++
                    }
                }
            }
        }
    }

    if ($lockedCount -gt 0) {
        Write-Ok "补丁校验完成（新增/更新: $copiedCount 项，已最新跳过: $skippedCount 项；另有 $lockedCount 个 DLL 当前正在被运行中的 Antigravity 加载使用，将在下次双击快捷方式启动时自动热替换）"
    } else {
        Write-Ok "补丁文件同步完成（新增/更新: $copiedCount 项，已最新无需覆盖: $skippedCount 项）"
    }
    return $true
}

# 5. 创建通用快捷方式 (.lnk)
function New-LauncherShortcut([string]$ShortcutPath, [string]$TargetExe, [string]$WorkingDir, [string]$IconSourceExe) {
    $ws = New-Object -ComObject WScript.Shell
    $lnk = $ws.CreateShortcut($ShortcutPath)
    $lnk.TargetPath = $TargetExe
    $lnk.WorkingDirectory = $WorkingDir
    $lnk.Description = "Antigravity (免 TUN 自动防覆盖代理启动器)"
    if (Test-Path $IconSourceExe) {
        $lnk.IconLocation = "$IconSourceExe,0"
    }
    $lnk.Save()
}

# 6. 安装桌面快捷方式
function Install-DesktopShortcut([string]$LauncherPath, [string]$TargetAppDir) {
    $desktopDir = [Environment]::GetFolderPath("Desktop")
    $lnkPath = Join-Path $desktopDir "Antigravity.lnk"
    $origExe = Join-Path $TargetAppDir "Antigravity.exe"
    New-LauncherShortcut -ShortcutPath $lnkPath -TargetExe $LauncherPath -WorkingDir $RootDir -IconSourceExe $origExe
    Write-Ok "已创建【桌面快捷方式】: $lnkPath"
}

# 7. 安装开始菜单快捷方式 (Start Menu)
function Install-StartMenuShortcut([string]$LauncherPath, [string]$TargetAppDir) {
    $startMenuDir = [Environment]::GetFolderPath("Programs")
    $lnkPath = Join-Path $startMenuDir "Antigravity.lnk"
    $origExe = Join-Path $TargetAppDir "Antigravity.exe"
    New-LauncherShortcut -ShortcutPath $lnkPath -TargetExe $LauncherPath -WorkingDir $RootDir -IconSourceExe $origExe
    Write-Ok "已添加到【开始菜单 (Start Menu)】: $lnkPath (支持按 Win 键直接搜索启动)"
}

# 8. 固定到任务栏 (Taskbar Pin)
function Install-TaskbarPin([string]$LauncherPath, [string]$TargetAppDir) {
    $origExe = Join-Path $TargetAppDir "Antigravity.exe"
    $pinnedSuccess = $false

    # 方法 A: 尝试通过 Shell.Application Verb 固定
    try {
        $shell = New-Object -ComObject Shell.Application
        $folder = $shell.Namespace((Split-Path -Parent $LauncherPath))
        $item = $folder.ParseName((Split-Path -Leaf $LauncherPath))
        if ($item) {
            foreach ($verb in $item.Verbs()) {
                $vName = $verb.Name.Replace("&", "")
                if ($vName -match "固定到任务栏|Pin to taskbar") {
                    $verb.DoIt()
                    $pinnedSuccess = $true
                    break
                }
            }
        }
    } catch { }

    # 方法 B: 放置快捷方式到 User Pinned\TaskBar 目录，供用户一键确认或系统识别
    $taskbarPinDir = Join-Path $env:APPDATA "Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
    if (Test-Path $taskbarPinDir) {
        $tbLnk = Join-Path $taskbarPinDir "Antigravity.lnk"
        try {
            New-LauncherShortcut -ShortcutPath $tbLnk -TargetExe $LauncherPath -WorkingDir $RootDir -IconSourceExe $origExe
        } catch { }
    }

    if ($pinnedSuccess) {
        Write-Ok "已成功将【Antigravity 启动器】固定到任务栏！"
    } else {
        Write-Ok "已生成原生 .exe 启动器及任务栏快捷项！"
        Write-Host "    💡 提示：因 Windows 11 安全策略限制脚本静默篡改任务栏，您只需在桌面或开始菜单右键【Antigravity】图标 -> 选择【固定到任务栏】即可完美固定（已采用原生 EXE 架构，100% 支持任务栏固定且图标不分裂）。" -ForegroundColor Gray
    }
}

# 9. 一键卸载与还原
function Invoke-Uninstall([string]$TargetAppDir) {
    Write-Title "卸载快捷方式并还原 Antigravity 官方纯净状态"
    $desktopLnk = Join-Path ([Environment]::GetFolderPath("Desktop")) "Antigravity.lnk"
    $startMenuLnk = Join-Path ([Environment]::GetFolderPath("Programs")) "Antigravity.lnk"
    $taskbarLnk = Join-Path $env:APPDATA "Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\Antigravity.lnk"

    foreach ($f in @($desktopLnk, $startMenuLnk, $taskbarLnk)) {
        if (Test-Path $f) {
            Remove-Item $f -Force -ErrorAction SilentlyContinue
            Write-Ok "已移除快捷方式: $f"
        }
    }

    if ($TargetAppDir -and (Test-Path $TargetAppDir)) {
        foreach ($dll in @("version.dll", "dbghelp.dll", "antigravity_proxy.dll", "config.json", "config-web.html")) {
            $p = Join-Path $TargetAppDir $dll
            if (Test-Path $p) {
                Remove-Item $p -Force -ErrorAction SilentlyContinue
                Write-Ok "已从安装目录移除补丁文件: $p"
            }
        }
    }
    Write-Ok "卸载与清理完成！"
}

# 10. 诊断自检
function Invoke-Diagnostics {
    Write-Title "Antigravity-Proxy 启动守护 - 环境自检"
    Write-Host "[1] 工具根目录: $RootDir"
    $patchDir = Find-PatchSourceDir
    if ($patchDir) {
        Write-Ok "[2] 补丁源目录: $patchDir (包含 version.dll)"
    } else {
        Write-Err "[2] 补丁源目录: 未找到 version.dll"
    }

    $detectedDir = Find-AntigravityDir -AllowDialog:$false
    if ($detectedDir) {
        Write-Ok "[3] Antigravity 安装目录: $detectedDir"
        $hasDll = Test-Path (Join-Path $detectedDir "version.dll")
        $hasCfg = Test-Path (Join-Path $detectedDir "config.json")
        Write-Host "    - 目标目录 version.dll 存在: $hasDll"
        Write-Host "    - 目标目录 config.json 存在: $hasCfg"
    } else {
        Write-Warn "[3] Antigravity 安装目录: 未在默认位置找到（首次运行将弹窗引导选择）"
    }

    Write-Host "[4] 原生启动器状态: $(if (Test-Path $LauncherExe) { '已生成 (' + $LauncherExe + ')' } else { '待生成' })"
}

# ============================================================================
# 主执行流
# ============================================================================
if ($Mode -eq "Diagnostics") {
    Invoke-Diagnostics
    exit 0
}

$targetDir = Find-AntigravityDir -AllowDialog:($Mode -ne "Uninstall")
if ($Mode -eq "Uninstall") {
    Invoke-Uninstall -TargetAppDir $targetDir
    exit 0
}

if ([string]::IsNullOrWhiteSpace($targetDir)) {
    Write-Err "未找到 Antigravity.exe，操作已中止。"
    exit 1
}

# 保存探测到的路径，供启动器毫秒级读取
$targetDir | Out-File -FilePath $ConfigPathFile -Encoding UTF8 -NoNewline

if ($Mode -eq "SyncOnly") {
    Sync-PatchFiles -TargetAppDir $targetDir | Out-Null
    exit 0
}

$exePath = Ensure-NativeLauncherExe -TargetAppDir $targetDir
Sync-PatchFiles -TargetAppDir $targetDir | Out-Null

if ($Mode -eq "All") {
    Install-DesktopShortcut -LauncherPath $exePath -TargetAppDir $targetDir
    Install-StartMenuShortcut -LauncherPath $exePath -TargetAppDir $targetDir
    Install-TaskbarPin -LauncherPath $exePath -TargetAppDir $targetDir
    exit 0
} elseif ($Mode -eq "Desktop") {
    Install-DesktopShortcut -LauncherPath $exePath -TargetAppDir $targetDir
    exit 0
} elseif ($Mode -eq "StartMenu") {
    Install-StartMenuShortcut -LauncherPath $exePath -TargetAppDir $targetDir
    exit 0
} elseif ($Mode -eq "Taskbar") {
    Install-TaskbarPin -LauncherPath $exePath -TargetAppDir $targetDir
    exit 0
}

# Interactive 交互模式
while ($true) {
    Write-Title "Antigravity-Proxy 防更新覆盖 & 快捷方式安装向导"
    Write-Host "  当前绑定程序目录: " -NoNewline
    Write-Host "$targetDir" -ForegroundColor Green
    Write-Host "  当前补丁源目录:   " -NoNewline
    Write-Host "$(Find-PatchSourceDir)" -ForegroundColor Green
    Write-Host ""
    Write-Host "  请选择要执行的操作：" -ForegroundColor White
    Write-Host "  [1] 🚀 一键全套安装（推荐：桌面快捷方式 + 开始菜单 + 任务栏固定 + 自动防覆盖）" -ForegroundColor Yellow
    Write-Host "  [2] 🖥️ 仅创建【桌面快捷方式】(Desktop)"
    Write-Host "  [3] 📂 仅添加到【开始菜单】(Start Menu)"
    Write-Host "  [4] 📌 固定到【任务栏】(Taskbar)"
    Write-Host "  [5] 🔄 立即重新同步补丁文件到 Antigravity 目录"
    Write-Host "  [6] 🔍 运行环境与权限排错自检"
    Write-Host "  [7] 🗑️ 卸载所有快捷方式并还原官方纯净状态"
    Write-Host "  [8] 🌐 一键在线检查并更新补丁至最新官方 Release (自动保留代理配置)" -ForegroundColor Cyan
    Write-Host "  [P] ⚙️ 查看或修改本地代理端口号 (当前配置)" -ForegroundColor Yellow
    Write-Host "  [0] 退出向导"
    Write-Host ""

    $choice = Read-Host "请输入数字或字母选项 [默认 1]"
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "1" }

    switch ($choice.ToUpper()) {
        "1" {
            Install-DesktopShortcut -LauncherPath $exePath -TargetAppDir $targetDir
            Install-StartMenuShortcut -LauncherPath $exePath -TargetAppDir $targetDir
            Install-TaskbarPin -LauncherPath $exePath -TargetAppDir $targetDir
            Write-Host ""
            Write-Ok "🎉 全部配置完成！以后请直接通过桌面/开始菜单/任务栏的 Antigravity 图标启动。"
            Write-Host "   即使 Antigravity 自动升级覆盖了文件，每次双击图标也会在几毫秒内自动恢复代理补丁！" -ForegroundColor Cyan
            break
        }
        "2" { Install-DesktopShortcut -LauncherPath $exePath -TargetAppDir $targetDir }
        "3" { Install-StartMenuShortcut -LauncherPath $exePath -TargetAppDir $targetDir }
        "4" { Install-TaskbarPin -LauncherPath $exePath -TargetAppDir $targetDir }
        "5" { Sync-PatchFiles -TargetAppDir $targetDir | Out-Null }
        "6" { Invoke-Diagnostics }
        "7" { Invoke-Uninstall -TargetAppDir $targetDir; break }
        "8" {
            $updateScript = Join-Path $LauncherDir "update-patch.ps1"
            if (Test-Path $updateScript) {
                & $updateScript -NoPause
            } else {
                Write-Warn "未找到 update-patch.ps1"
            }
        }
        "P" {
            $patchDir = Find-PatchSourceDir
            $cfgFile = ""
            $candidatesToSearch = @()
            if ($patchDir) { $candidatesToSearch += (Join-Path $patchDir "config.json") }
            $candidatesToSearch += @(
                (Join-Path $RootDir "ide\config.json"),
                (Join-Path $RootDir "cli\config.json"),
                (Join-Path $RootDir "Patch\config.json"),
                (Join-Path $RootDir "config.json")
            )
            if ($targetDir) { $candidatesToSearch += (Join-Path $targetDir "config.json") }

            foreach ($c in $candidatesToSearch) {
                if (Test-Path -LiteralPath $c) {
                    $cfgFile = $c
                    break
                }
            }

            if ($cfgFile -and (Test-Path -LiteralPath $cfgFile)) {
                try {
                    $cObj = Get-Content -LiteralPath $cfgFile -Raw -Encoding UTF8 | ConvertFrom-Json
                    $curHost = if ($cObj.proxy -and $cObj.proxy.host) { $cObj.proxy.host } else { "127.0.0.1" }
                    $curPort = if ($cObj.proxy -and $cObj.proxy.port) { $cObj.proxy.port } else { 7890 }
                    $curType = if ($cObj.proxy -and $cObj.proxy.type) { $cObj.proxy.type } else { "socks5" }
                    Write-Host ""
                    Write-Host "  当前配置文件: $cfgFile" -ForegroundColor Gray
                    Write-Host "  当前代理配置: $($curType)://$($curHost):$($curPort)" -ForegroundColor Cyan
                    $newPort = Read-Host "  请输入新的代理端口号 (按回车保持不变)"
                    if (-not [string]::IsNullOrWhiteSpace($newPort) -and ($newPort -match '^\d+$')) {
                        $cObj.proxy.port = [int]$newPort
                        $cObj | ConvertTo-Json -Depth 10 | Out-File -FilePath $cfgFile -Encoding UTF8
                        if ($targetDir -and (Test-Path $targetDir) -and (Test-Path (Join-Path $targetDir "config.json"))) {
                            $cObj | ConvertTo-Json -Depth 10 | Out-File -FilePath (Join-Path $targetDir "config.json") -Encoding UTF8
                        }
                        Write-Ok "已成功更新代理端口为: $newPort！已同步保存至本地补丁库与主程序目录。"
                    }
                } catch {
                    Write-Err "读取或修改 config.json 失败: $_"
                }
            } else {
                Write-Warn "未找到可修改的 config.json 文件 (请确保已解压 ide/、cli/ 或已绑定主程序目录)。"
            }
            Write-Host ""
            Read-Host "按回车键返回主菜单..."
        }
        "0" { break }
        default { Write-Warn "无效选项，请重新输入。" }
    }

    if ($choice -in @("1", "7", "0")) {
        break
    }
}

if (-not $NoPause) {
    Write-Host ""
    Read-Host "按回车键关闭窗口..."
}
