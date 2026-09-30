# ============================================================================
# Antigravity-Proxy 智能安装与管理向导 (Smart Setup Wizard)
# ============================================================================
# 支持平台: Windows 10 / 11 (x64 / x86)
# 国际化语言: 中文 (Simplified Chinese) / English / Русский (Russian)
# 运行模式: 自动感知 IDE 桌面版 与 CLI 命令行版
# ============================================================================

[CmdletBinding()]
param(
    [ValidateSet("Interactive", "All", "Desktop", "StartMenu", "Taskbar", "SyncOnly", "Diagnostics", "Uninstall")]
    [string]$Mode = "Interactive",
    [string]$AppDir = "",
    [string]$Lang = "",
    [switch]$NoPause
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = $ScriptDir
if ((Split-Path -Leaf $ScriptDir) -match '^(launcher|scripts)$') {
    $Parent = Split-Path -Parent $ScriptDir
    if ((Test-Path (Join-Path $Parent "ide")) -or (Test-Path (Join-Path $Parent "cli")) -or `
        (Test-Path (Join-Path $Parent "Patch")) -or (Test-Path (Join-Path $Parent "build.ps1")) -or `
        (Test-Path (Join-Path $Parent "使用说明.md")) -or (Test-Path (Join-Path $Parent "setup.bat"))) {
        $RootDir = $Parent
    }
}

$LauncherDir = if (Test-Path (Join-Path $RootDir "launcher")) { Join-Path $RootDir "launcher" } else { $ScriptDir }
if (-not (Test-Path $LauncherDir)) {
    New-Item -ItemType Directory -Path $LauncherDir -Force | Out-Null
}

$LauncherExe = Join-Path $LauncherDir "AntigravityLauncher.exe"
$ConfigPathFile = Join-Path $RootDir "app_path.txt"
$AgyPathFile = Join-Path $RootDir "agy_path.txt"
$LangPrefFile = Join-Path $LauncherDir "lang.pref"

# ============================================================================
# 国际化多语言字符串字典 (i18n String Tables: zh, en, ru)
# ============================================================================
$M = @{
    "zh" = @{
        TitleIde          = "Antigravity-Proxy 桌面端启动守护与快捷方式向导"
        TitleCli          = "Antigravity-Proxy CLI 命令行补丁部署向导"
        TitleDiag         = "Antigravity-Proxy 环境与权限排错自检"
        ModeIde           = "[模式: 桌面 IDE 版]"
        ModeCli           = "[模式: 命令行 CLI 版]"
        BoundTarget       = "当前绑定程序目录: "
        PatchSource       = "当前补丁源目录:   "
        OptIdeAll         = "[1] 🚀 一键全套配置（推荐：桌面快捷方式 + 开始菜单 + 任务栏固定 + 自动防覆盖）"
        OptIdeDesktop     = "[2] 🖥️ 仅创建【桌面快捷方式】(Desktop)"
        OptIdeStartMenu   = "[3] 📂 仅添加到【开始菜单】(Start Menu)"
        OptIdeTaskbar     = "[4] 📌 固定到【任务栏】(Taskbar)"
        OptIdeSync        = "[5] 🔄 立即重新同步补丁文件到 Antigravity 目录"
        OptIdeDiag        = "[6] 🔍 运行环境与权限排错自检"
        OptIdeUninstall   = "[7] 🗑️ 卸载所有快捷方式并还原官方纯净状态"
        OptIdeUpdate      = "[8] 🌐 一键在线检查并更新补丁至最新官方 Release"
        OptCliDeploy      = "[1] 🚀 一键部署补丁到 agy.exe 目录（自动探测并注入 dbghelp.dll 代理）"
        OptCliSync        = "[2] 🔄 重新同步补丁文件到已绑定的 agy.exe 目录"
        OptCliDiag        = "[3] 🔍 CLI 运行环境与补丁排错自检"
        OptCliUninstall   = "[4] 🗑️ 卸载补丁并还原 agy.exe 官方纯净状态"
        OptCliUpdate      = "[5] 🌐 一键在线检查并更新补丁至最新官方 Release"
        OptPort           = "[P] ⚙️ 查看或修改本地代理端口号 (当前: {0}://{1}:{2})"
        OptLang           = "[L] 🌐 切换语言 / Switch Language / Сменить язык (当前: 中文)"
        OptExit           = "[0] 退出向导"
        PromptChoice      = "请输入数字或字母选项 [默认 1]: "
        InvalidChoice     = "无效选项，请重新输入。"
        PressEnterReturn  = "按回车键返回主菜单..."
        PressEnterClose   = "按回车键关闭窗口..."
        DoneIdeAll        = "🎉 全部配置完成！以后请直接通过桌面/开始菜单/任务栏的 Antigravity 图标启动。"
        DoneIdeHint       = "即使 Antigravity 自动升级覆盖了文件，每次双击图标也会在几毫秒内自动恢复代理补丁！"
        TaskbarNotice     = "💡 提示：因 Windows 11 安全策略限制，您可在桌面右键【Antigravity】图标 -> 选择【固定到任务栏】完美固定（已采用原生 EXE 架构，图标不分裂）。"
        DoneCliAll        = "🎉 CLI 代理补丁部署成功！现在可在终端中直接运行 agy 命令，流量将自动经由代理转发。"
        SelectAgyTitle    = "请选择 agy.exe 所在位置（仅首次需要）"
        SelectIdeTitle    = "请选择 Antigravity.exe 所在位置（仅首次需要）"
        NoIdeWarn         = "未在默认路径检测到 Antigravity.exe，请在弹出窗口中手动选择..."
        NoAgyWarn         = "未在 PATH 或常见目录检测到 agy.exe，请在弹出窗口中手动选择..."
        NoPatchWarn       = "未检测到有效的补丁目录，请确保已解压完整的 Release 压缩包。"
        LangMenuTitle     = "请选择界面语言 / Select Language / Выберите язык:"
        LangOptionZh      = "1. 简体中文 (Simplified Chinese)"
        LangOptionEn      = "2. English (英语)"
        LangOptionRu      = "3. Русский (Russian/俄语)"
        PortCurrentFile   = "当前配置文件: "
        PortCurrentVal    = "当前代理设置: "
        PortInputPrompt   = "请输入新的代理端口号 (直接按回车保持不变): "
        PortSuccess       = "已成功更新代理端口为: {0}！已同步保存至本地补丁库与程序目录。"
        PortErr           = "读取或修改 config.json 失败: "
        UninstallSuccess  = "已成功卸载并还原官方纯净状态！"
    }
    "en" = @{
        TitleIde          = "Antigravity-Proxy Desktop Launcher Guard & Shortcut Wizard"
        TitleCli          = "Antigravity-Proxy CLI Patch Deployment Wizard"
        TitleDiag         = "Antigravity-Proxy Environment & Permission Diagnostics"
        ModeIde           = "[Mode: Desktop IDE]"
        ModeCli           = "[Mode: Console CLI]"
        BoundTarget       = "Bound Target Directory: "
        PatchSource       = "Patch Source Directory: "
        OptIdeAll         = "[1] 🚀 One-Click Full Setup (Recommended: Desktop + Start Menu + Taskbar + Auto-Healing)"
        OptIdeDesktop     = "[2] 🖥️ Create [Desktop Shortcut] only"
        OptIdeStartMenu   = "[3] 📂 Add to [Start Menu] only"
        OptIdeTaskbar     = "[4] 📌 Pin to [Taskbar]"
        OptIdeSync        = "[5] 🔄 Sync Patch files to Antigravity directory immediately"
        OptIdeDiag        = "[6] 🔍 Environment & Permission Diagnostics"
        OptIdeUninstall   = "[7] 🗑️ Uninstall shortcuts and restore clean official state"
        OptIdeUpdate      = "[8] 🌐 Check & Update Patch to latest official Release online"
        OptCliDeploy      = "[1] 🚀 One-Click Deploy Patch to agy.exe directory (Auto-detect & inject dbghelp.dll)"
        OptCliSync        = "[2] 🔄 Re-sync Patch files to bound agy.exe directory"
        OptCliDiag        = "[3] 🔍 CLI Environment & Patch Diagnostics"
        OptCliUninstall   = "[4] 🗑️ Uninstall patch and restore clean official agy state"
        OptCliUpdate      = "[5] 🌐 Check & Update Patch to latest official Release online"
        OptPort           = "[P] ⚙️ View or Modify local proxy port (Current: {0}://{1}:{2})"
        OptLang           = "[L] 🌐 Switch Language / 切换语言 / Сменить язык (Current: English)"
        OptExit           = "[0] Exit"
        PromptChoice      = "Enter an option [Default 1]: "
        InvalidChoice     = "Invalid option, please try again."
        PressEnterReturn  = "Press Enter to return to main menu..."
        PressEnterClose   = "Press Enter to close window..."
        DoneIdeAll        = "🎉 Setup completed! Launch Antigravity directly via Desktop, Start Menu, or Taskbar."
        DoneIdeHint       = "Even if Antigravity auto-updates and wipes files, the launcher restores patches in milliseconds!"
        TaskbarNotice     = "💡 Note: Due to Windows 11 security policies, right-click the Desktop [Antigravity] shortcut -> [Pin to taskbar] for perfect pinning."
        DoneCliAll        = "🎉 CLI proxy patch deployed successfully! You can now run agy in terminal through proxy."
        SelectAgyTitle    = "Please select agy.exe location (First time only)"
        SelectIdeTitle    = "Please select Antigravity.exe location (First time only)"
        NoIdeWarn         = "Antigravity.exe not detected in default paths. Please select manually..."
        NoAgyWarn         = "agy.exe not detected in PATH or standard paths. Please select manually..."
        NoPatchWarn       = "No valid patch directory detected. Ensure full Release zip is extracted."
        LangMenuTitle     = "Select Language / 请选择界面语言 / Выберите язык:"
        LangOptionZh      = "1. 简体中文 (Simplified Chinese)"
        LangOptionEn      = "2. English (英语)"
        LangOptionRu      = "3. Русский (Russian/俄语)"
        PortCurrentFile   = "Current config file: "
        PortCurrentVal    = "Current proxy setting: "
        PortInputPrompt   = "Enter new proxy port (Press Enter to keep current): "
        PortSuccess       = "Successfully updated proxy port to: {0}! Synced to patch source and app directory."
        PortErr           = "Failed to read or modify config.json: "
        UninstallSuccess  = "Successfully uninstalled shortcuts and restored clean official state!"
    }
    "ru" = @{
        TitleIde          = "Мастер настройки и запуска Antigravity-Proxy (Desktop)"
        TitleCli          = "Мастер установки патча Antigravity-Proxy CLI"
        TitleDiag         = "Диагностика окружения и разрешений Antigravity-Proxy"
        ModeIde           = "[Режим: Desktop IDE]"
        ModeCli           = "[Режим: Консольный CLI]"
        BoundTarget       = "Целевая директория: "
        PatchSource       = "Источник патча:     "
        OptIdeAll         = "[1] 🚀 Полная установка (Рекомендуется: Рабочий стол + Пуск + Панель задач + Автозащита)"
        OptIdeDesktop     = "[2] 🖥️ Создать только [Ярлык на рабочем столе]"
        OptIdeStartMenu   = "[3] 📂 Добавить только в [Меню Пуск]"
        OptIdeTaskbar     = "[4] 📌 Закрепить на [Панели задач]"
        OptIdeSync        = "[5] 🔄 Немедленно синхронизировать патч в директорию Antigravity"
        OptIdeDiag        = "[6] 🔍 Диагностика окружения и разрешений"
        OptIdeUninstall   = "[7] 🗑️ Удалить все ярлыки и восстановить исходное состояние"
        OptIdeUpdate      = "[8] 🌐 Проверить и обновить патч до последнего релиза онлайн"
        OptCliDeploy      = "[1] 🚀 Установить патч в директорию agy.exe (Автопоиск и внедрение dbghelp.dll)"
        OptCliSync        = "[2] 🔄 Повторно синхронизировать патч с директорией agy.exe"
        OptCliDiag        = "[3] 🔍 Диагностика CLI окружения и патча"
        OptCliUninstall   = "[4] 🗑️ Удалить патч и восстановить чистый agy"
        OptCliUpdate      = "[5] 🌐 Проверить и обновить патч до последнего релиза онлайн"
        OptPort           = "[P] ⚙️ Просмотр и изменение порта прокси (Текущий: {0}://{1}:{2})"
        OptLang           = "[L] 🌐 Сменить язык / Switch Language / 切换语言 (Текущий: Русский)"
        OptExit           = "[0] Выход"
        PromptChoice      = "Введите опцию [По умолчанию 1]: "
        InvalidChoice     = "Неверный выбор, попробуйте снова."
        PressEnterReturn  = "Нажмите Enter для возврата в главное меню..."
        PressEnterClose   = "Нажмите Enter для закрытия окна..."
        DoneIdeAll        = "🎉 Настройка завершена! Запускайте Antigravity с Рабочего стола, Пуска или Панели задач."
        DoneIdeHint       = "Даже если Antigravity обновится и сотрет файлы, лаунчер восстановит их за миллисекунды!"
        TaskbarNotice     = "💡 Совет: В Windows 11 нажмите правой кнопкой на ярлык [Antigravity] -> [Закрепить на панели задач]."
        DoneCliAll        = "🎉 Патч для CLI успешно установлен! Теперь запускайте agy в терминале через прокси."
        SelectAgyTitle    = "Укажите расположение agy.exe (Только в первый раз)"
        SelectIdeTitle    = "Укажите расположение Antigravity.exe (Только в первый раз)"
        NoIdeWarn         = "Antigravity.exe не найден в стандартных папках. Выберите вручную..."
        NoAgyWarn         = "agy.exe не найден в PATH или стандартных папках. Выберите вручную..."
        NoPatchWarn       = "Действительная папка патча не найдена. Убедитесь, что распаковали полный архив."
        LangMenuTitle     = "Выберите язык / Select Language / 请选择界面语言:"
        LangOptionZh      = "1. 简体中文 (Simplified Chinese)"
        LangOptionEn      = "2. English (英语)"
        LangOptionRu      = "3. Русский (Russian/俄语)"
        PortCurrentFile   = "Текущий файл конфигурации: "
        PortCurrentVal    = "Текущие настройки прокси: "
        PortInputPrompt   = "Введите новый порт прокси (Enter чтобы оставить прежний): "
        PortSuccess       = "Порт прокси успешно обновлен на: {0}! Синхронизировано с папкой программы."
        PortErr           = "Ошибка чтения или изменения config.json: "
        UninstallSuccess  = "Ярлыки успешно удалены, исходное состояние восстановлено!"
    }
}

# ============================================================================
# 语言探测与切换逻辑
# ============================================================================
function Get-InitialLanguage {
    if (-not [string]::IsNullOrWhiteSpace($Lang) -and $M.ContainsKey($Lang.ToLower())) {
        return $Lang.ToLower()
    }
    if (Test-Path -LiteralPath $LangPrefFile) {
        $saved = (Get-Content -LiteralPath $LangPrefFile -Raw -Encoding UTF8).Trim().ToLower()
        if ($M.ContainsKey($saved)) { return $saved }
    }
    $uiCulture = [System.Globalization.CultureInfo]::InstalledUICulture.Name.ToLower()
    if ($uiCulture -like "zh*") { return "zh" }
    if ($uiCulture -like "ru*") { return "ru" }
    return "en"
}

$CurrentLang = Get-InitialLanguage

function T([string]$Key) {
    if ($M[$CurrentLang].ContainsKey($Key)) {
        return $M[$CurrentLang][$Key]
    }
    return $M["en"][$Key]
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

# ============================================================================
# 核心探测：产品形态 (IDE vs CLI)
# ============================================================================
function Detect-ProductMode {
    $hasIde = (Test-Path (Join-Path $RootDir "ide\version.dll")) -or `
              (Test-Path (Join-Path $RootDir "output\ide\version.dll")) -or `
              (Test-Path (Join-Path $RootDir "Patch\version.dll")) -or `
              (Test-Path (Join-Path $RootDir "version.dll"))

    $hasCli = (Test-Path (Join-Path $RootDir "cli\dbghelp.dll")) -or `
              (Test-Path (Join-Path $RootDir "output\cli\dbghelp.dll")) -or `
              (Test-Path (Join-Path $RootDir "dbghelp.dll"))

    if ($hasIde -and -not $hasCli) { return "IDE" }
    if ($hasCli -and -not $hasIde) { return "CLI" }
    # 若在源码仓库或全量目录中，优先看已绑定的路径记录，默认呈现 IDE
    if ((Test-Path -LiteralPath $AgyPathFile) -and -not (Test-Path -LiteralPath $ConfigPathFile)) { return "CLI" }
    return "IDE"
}

$ProductMode = Detect-ProductMode

# 定位 IDE 补丁源目录
function Find-IdePatchSourceDir {
    $candidates = @(
        (Join-Path $RootDir "ide"),
        (Join-Path $RootDir "output\ide"),
        (Join-Path $RootDir "Patch"),
        $RootDir
    )
    foreach ($dir in $candidates) {
        if ((Test-Path -LiteralPath $dir) -and (Test-Path (Join-Path $dir "version.dll"))) {
            return $dir
        }
    }
    return ""
}

# 定位 CLI 补丁源目录
function Find-CliPatchSourceDir {
    $candidates = @(
        (Join-Path $RootDir "cli"),
        (Join-Path $RootDir "output\cli"),
        $RootDir
    )
    foreach ($dir in $candidates) {
        if ((Test-Path -LiteralPath $dir) -and (Test-Path (Join-Path $dir "dbghelp.dll"))) {
            return $dir
        }
    }
    return ""
}

# 探测 Antigravity.exe 桌面版主程序目录
function Find-AntigravityDir([bool]$AllowDialog = $false) {
    if (Test-Path -LiteralPath $ConfigPathFile) {
        $savedPath = (Get-Content -LiteralPath $ConfigPathFile -Raw -Encoding UTF8).Trim()
        if (-not [string]::IsNullOrWhiteSpace($savedPath) -and (Test-Path (Join-Path $savedPath "Antigravity.exe"))) {
            return $savedPath
        }
    }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Antigravity"),
        (Join-Path $env:LOCALAPPDATA "Antigravity"),
        (Join-Path $env:ProgramFiles "Antigravity"),
        (Join-Path ${env:ProgramFiles(x86)} "Antigravity")
    )
    foreach ($dir in $candidates) {
        if ($dir -and (Test-Path (Join-Path $dir "Antigravity.exe"))) {
            return $dir
        }
    }

    foreach ($rootKey in @("HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*")) {
        $found = Get-ItemProperty -Path $rootKey -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like "*Antigravity*" -and $_.InstallLocation } |
            Select-Object -First 1
        if ($found) {
            $loc = $found.InstallLocation.Trim().TrimEnd('\', '/')
            if (Test-Path (Join-Path $loc "Antigravity.exe")) {
                return $loc
            }
        }
    }

    if ($AllowDialog) {
        Write-Warn (T "NoIdeWarn")
        Add-Type -AssemblyName System.Windows.Forms
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = "Antigravity.exe|Antigravity.exe"
        $dlg.Title = T "SelectIdeTitle"
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

# 探测 agy.exe CLI 命令行主程序目录
function Find-AgyDir([bool]$AllowDialog = $false) {
    if (Test-Path -LiteralPath $AgyPathFile) {
        $saved = (Get-Content -LiteralPath $AgyPathFile -Raw -Encoding UTF8).Trim()
        if (-not [string]::IsNullOrWhiteSpace($saved) -and (Test-Path (Join-Path $saved "agy.exe"))) {
            return $saved
        }
    }

    $cmd = Get-Command "agy.exe" -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) {
        $pDir = Split-Path -Parent $cmd.Source
        if (Test-Path (Join-Path $pDir "agy.exe")) {
            return $pDir
        }
    }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Antigravity CLI"),
        (Join-Path $env:LOCALAPPDATA "Programs\Antigravity\resources\app\extensions\antigravity\bin"),
        (Join-Path $env:ProgramFiles "Antigravity CLI")
    )
    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c "agy.exe")) {
            return $c
        }
    }

    if ($AllowDialog) {
        Write-Warn (T "NoAgyWarn")
        Add-Type -AssemblyName System.Windows.Forms
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = "agy.exe|agy.exe|All Exe (*.exe)|*.exe"
        $dlg.Title = T "SelectAgyTitle"
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $selectedDir = [System.IO.Path]::GetDirectoryName($dlg.FileName)
            if (Test-Path (Join-Path $selectedDir "agy.exe")) {
                $selectedDir | Out-File -FilePath $AgyPathFile -Encoding UTF8 -NoNewline
                return $selectedDir
            }
        }
    }
    return ""
}

# ============================================================================
# 原生无黑框 GUI 启动器保障 (IDE 专用)
# ============================================================================
function Ensure-NativeLauncherExe([string]$TargetAppDir) {
    if (Test-Path $LauncherExe) {
        Write-Ok "Launcher: $LauncherExe"
        return $LauncherExe
    }

    Write-Info "Compiling Native Win32 Launcher AntigravityLauncher.exe..."
    $iconFile = Join-Path $LauncherDir "antigravity.ico"
    $targetExePath = Join-Path $TargetAppDir "Antigravity.exe"

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
    } catch { }

    $csharpSource = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Windows.Forms;

public static class AntigravityLauncher {
    [STAThread]
    public static int Main(string[] args) {
        try {
            string exeDir = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\', '/');
            string rootDir = exeDir;
            DirectoryInfo pInfo = Directory.GetParent(exeDir);
            string parentDir = (pInfo != null) ? pInfo.FullName : exeDir;
            if (Directory.Exists(Path.Combine(parentDir, "ide")) || Directory.Exists(Path.Combine(parentDir, "Patch"))) {
                rootDir = parentDir;
            }

            string appDir = "";
            string savedCfg = Path.Combine(rootDir, "app_path.txt");
            if (File.Exists(savedCfg)) {
                string line = File.ReadAllText(savedCfg, Encoding.UTF8).Trim();
                if (!string.IsNullOrEmpty(line) && File.Exists(Path.Combine(line, "Antigravity.exe"))) {
                    appDir = line;
                }
            }

            if (string.IsNullOrEmpty(appDir)) {
                string[] candidates = new string[] {
                    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Programs\Antigravity"),
                    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Antigravity"),
                    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), @"Antigravity")
                };
                foreach (string c in candidates) {
                    if (File.Exists(Path.Combine(c, "Antigravity.exe"))) { appDir = c; break; }
                }
            }

            if (string.IsNullOrEmpty(appDir)) {
                OpenFileDialog dlg = new OpenFileDialog();
                dlg.Filter = "Antigravity.exe|Antigravity.exe";
                dlg.Title = "Select Antigravity.exe location";
                if (dlg.ShowDialog() == DialogResult.OK) {
                    appDir = Path.GetDirectoryName(dlg.FileName);
                    File.WriteAllText(savedCfg, appDir, Encoding.UTF8);
                } else {
                    return 1;
                }
            }

            string patchDir = "";
            string[] patchCandidates = new string[] {
                Path.Combine(rootDir, "ide"), Path.Combine(rootDir, "Patch"), rootDir
            };
            foreach (string p in patchCandidates) {
                if (Directory.Exists(p) && File.Exists(Path.Combine(p, "version.dll"))) {
                    patchDir = p; break;
                }
            }

            if (!string.IsNullOrEmpty(patchDir) && Directory.Exists(patchDir) && Directory.Exists(appDir)) {
                foreach (string srcFile in Directory.GetFiles(patchDir, "*.*", SearchOption.AllDirectories)) {
                    string rel = srcFile.Substring(patchDir.Length).TrimStart('\\', '/');
                    string dstFile = Path.Combine(appDir, rel);
                    string dstSubDir = Path.GetDirectoryName(dstFile);
                    if (!Directory.Exists(dstSubDir)) Directory.CreateDirectory(dstSubDir);

                    bool copy = true;
                    if (File.Exists(dstFile)) {
                        FileInfo fiSrc = new FileInfo(srcFile);
                        FileInfo fiDst = new FileInfo(dstFile);
                        if (fiSrc.Length == fiDst.Length && fiSrc.LastWriteTimeUtc <= fiDst.LastWriteTimeUtc) {
                            copy = false;
                        }
                    }
                    if (copy) {
                        try { File.Copy(srcFile, dstFile, true); } catch { }
                    }
                }
            }

            string targetExe = Path.Combine(appDir, "Antigravity.exe");
            ProcessStartInfo psi = new ProcessStartInfo(targetExe);
            psi.WorkingDirectory = appDir;
            if (args != null && args.Length > 0) {
                psi.Arguments = string.Join(" ", args);
            }
            Process.Start(psi);
            return 0;
        } catch (Exception ex) {
            MessageBox.Show("Launch failed: " + ex.Message, "Antigravity-Proxy", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
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
        throw "Compile Launcher Error:`n$errMsgs"
    }

    Write-Ok "Launcher compiled: $LauncherExe"
    return $LauncherExe
}

# ============================================================================
# 快捷方式与补丁同步模块
# ============================================================================
function Sync-IdePatchFiles([string]$TargetAppDir) {
    $patchDir = Find-IdePatchSourceDir
    if ([string]::IsNullOrWhiteSpace($patchDir)) {
        Write-Warn (T "NoPatchWarn")
        return $false
    }

    Write-Info "Syncing: [$patchDir] -> [$TargetAppDir]..."
    $copiedCount = 0
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
                }
            }
            if ($needCopy) {
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
                        Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
                        $copiedCount++
                    } catch { }
                }
            }
        }
    }
    Write-Ok "Synced ($copiedCount files updated)."
    return $true
}

function Sync-CliPatchFiles([string]$TargetAgyDir) {
    $patchDir = Find-CliPatchSourceDir
    if ([string]::IsNullOrWhiteSpace($patchDir)) {
        Write-Warn (T "NoPatchWarn")
        return $false
    }

    Write-Info "Syncing CLI: [$patchDir] -> [$TargetAgyDir]..."
    $copiedCount = 0
    Get-ChildItem -LiteralPath $patchDir -Recurse | ForEach-Object {
        if (-not $_.PSIsContainer) {
            $dest = Join-Path $TargetAgyDir $_.Name
            $needCopy = $true
            if (Test-Path -LiteralPath $dest -PathType Leaf) {
                $dstItem = Get-Item -LiteralPath $dest
                if ($_.Length -eq $dstItem.Length -and $_.LastWriteTimeUtc -le $dstItem.LastWriteTimeUtc) {
                    $needCopy = $false
                }
            }
            if ($needCopy) {
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
                        Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
                        $copiedCount++
                    } catch { }
                }
            }
        }
    }
    Write-Ok "CLI Synced ($copiedCount files updated)."
    return $true
}

function New-LauncherShortcut([string]$ShortcutPath, [string]$TargetExe, [string]$WorkingDir, [string]$IconSourceExe) {
    $parentDir = Split-Path -Parent $ShortcutPath
    if (-not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }
    $wsh = New-Object -ComObject WScript.Shell
    $shortcut = $wsh.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $TargetExe
    $shortcut.WorkingDirectory = $WorkingDir
    $shortcut.Description = "Antigravity (Anti-Update Protected)"
    if (Test-Path $IconSourceExe) {
        $shortcut.IconLocation = "$IconSourceExe,0"
    }
    $shortcut.Save()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut) | Out-Null
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wsh) | Out-Null
}

function Install-DesktopShortcut([string]$LauncherPath, [string]$TargetAppDir) {
    $desktop = [Environment]::GetFolderPath("Desktop")
    $lnkPath = Join-Path $desktop "Antigravity.lnk"
    $origExe = Join-Path $TargetAppDir "Antigravity.exe"
    New-LauncherShortcut -ShortcutPath $lnkPath -TargetExe $LauncherPath -WorkingDir $RootDir -IconSourceExe $origExe
    Write-Ok "Desktop Shortcut: $lnkPath"
}

function Install-StartMenuShortcut([string]$LauncherPath, [string]$TargetAppDir) {
    $programs = [Environment]::GetFolderPath("Programs")
    $lnkPath = Join-Path $programs "Antigravity.lnk"
    $origExe = Join-Path $TargetAppDir "Antigravity.exe"
    New-LauncherShortcut -ShortcutPath $lnkPath -TargetExe $LauncherPath -WorkingDir $RootDir -IconSourceExe $origExe
    Write-Ok "Start Menu Shortcut: $lnkPath"
}

function Install-TaskbarPin([string]$LauncherPath, [string]$TargetAppDir) {
    $origExe = Join-Path $TargetAppDir "Antigravity.exe"
    $appData = $env:APPDATA
    $tbDir = Join-Path $appData "Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
    if (Test-Path $tbDir) {
        $tbLnk = Join-Path $tbDir "Antigravity.lnk"
        New-LauncherShortcut -ShortcutPath $tbLnk -TargetExe $LauncherPath -WorkingDir $RootDir -IconSourceExe $origExe
    }
    Write-Ok "Launcher executable ready for Taskbar pin."
    Write-Host "    $((T 'TaskbarNotice'))" -ForegroundColor Yellow
}

function Invoke-Uninstall-Ide([string]$TargetAppDir) {
    $desktop = [Environment]::GetFolderPath("Desktop")
    $dtLnk = Join-Path $desktop "Antigravity.lnk"
    if (Test-Path $dtLnk) { Remove-Item -LiteralPath $dtLnk -Force; Write-Ok "Removed Desktop Shortcut" }

    $programs = [Environment]::GetFolderPath("Programs")
    $smLnk = Join-Path $programs "Antigravity.lnk"
    if (Test-Path $smLnk) { Remove-Item -LiteralPath $smLnk -Force; Write-Ok "Removed Start Menu Shortcut" }

    if ($TargetAppDir -and (Test-Path $TargetAppDir)) {
        $vDll = Join-Path $TargetAppDir "version.dll"
        if (Test-Path $vDll) {
            try { Remove-Item -LiteralPath $vDll -Force; Write-Ok "Removed version.dll from Antigravity dir" }
            catch { Write-Warn "version.dll is locked by running process." }
        }
    }
    Write-Ok (T "UninstallSuccess")
}

function Invoke-Uninstall-Cli([string]$TargetAgyDir) {
    if ($TargetAgyDir -and (Test-Path $TargetAgyDir)) {
        foreach ($f in @("dbghelp.dll", "antigravity_proxy.dll")) {
            $p = Join-Path $TargetAgyDir $f
            if (Test-Path $p) {
                try { Remove-Item -LiteralPath $p -Force; Write-Ok "Removed $f" } catch { }
            }
        }
    }
    Write-Ok (T "UninstallSuccess")
}

# ============================================================================
# 代理端口查看与修改交互
# ============================================================================
function Invoke-PortSetting([string]$CurrentTargetDir) {
    $patchDir = if ($ProductMode -eq "CLI") { Find-CliPatchSourceDir } else { Find-IdePatchSourceDir }
    $cfgFile = ""
    $candidates = @()
    if ($patchDir) { $candidates += (Join-Path $patchDir "config.json") }
    $candidates += @(
        (Join-Path $RootDir "ide\config.json"),
        (Join-Path $RootDir "cli\config.json"),
        (Join-Path $RootDir "Patch\config.json"),
        (Join-Path $RootDir "config.json")
    )
    if ($CurrentTargetDir) { $candidates += (Join-Path $CurrentTargetDir "config.json") }

    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { $cfgFile = $c; break }
    }

    if ($cfgFile -and (Test-Path -LiteralPath $cfgFile)) {
        try {
            $cObj = Get-Content -LiteralPath $cfgFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $curHost = if ($cObj.proxy -and $cObj.proxy.host) { $cObj.proxy.host } else { "127.0.0.1" }
            $curPort = if ($cObj.proxy -and $cObj.proxy.port) { $cObj.proxy.port } else { 7890 }
            $curType = if ($cObj.proxy -and $cObj.proxy.type) { $cObj.proxy.type } else { "socks5" }

            Write-Host ""
            Write-Host "  $((T 'PortCurrentFile'))$cfgFile" -ForegroundColor Gray
            Write-Host "  $((T 'PortCurrentVal'))$($curType)://$($curHost):$($curPort)" -ForegroundColor Cyan
            $newPort = Read-Host "  $((T 'PortInputPrompt'))"
            if (-not [string]::IsNullOrWhiteSpace($newPort) -and ($newPort -match '^\d+$')) {
                $cObj.proxy.port = [int]$newPort
                $cObj | ConvertTo-Json -Depth 10 | Out-File -FilePath $cfgFile -Encoding UTF8
                if ($CurrentTargetDir -and (Test-Path $CurrentTargetDir) -and (Test-Path (Join-Path $CurrentTargetDir "config.json"))) {
                    $cObj | ConvertTo-Json -Depth 10 | Out-File -FilePath (Join-Path $CurrentTargetDir "config.json") -Encoding UTF8
                }
                Write-Ok ([string]::Format((T "PortSuccess"), $newPort))
            }
        } catch {
            Write-Err "$((T 'PortErr'))$_"
        }
    } else {
        Write-Warn (T "NoPatchWarn")
    }
    Write-Host ""
    Read-Host (T "PressEnterReturn")
}

# ============================================================================
# 语言手动切换交互
# ============================================================================
function Invoke-LanguageSwitch {
    Write-Host ""
    Write-Host (T "LangMenuTitle") -ForegroundColor Cyan
    Write-Host "  $((T 'LangOptionZh'))"
    Write-Host "  $((T 'LangOptionEn'))"
    Write-Host "  $((T 'LangOptionRu'))"
    Write-Host ""
    $lChoice = Read-Host "Select (1/2/3)"
    switch ($lChoice.Trim()) {
        "1" { $Global:CurrentLang = "zh" }
        "2" { $Global:CurrentLang = "en" }
        "3" { $Global:CurrentLang = "ru" }
    }
    $Global:CurrentLang | Out-File -FilePath $LangPrefFile -Encoding UTF8 -NoNewline
    Write-Ok "Language set to: $Global:CurrentLang"
}

# ============================================================================
# 主执行入口
# ============================================================================
$targetDir = ""
$patchSourceDir = ""

if ($ProductMode -eq "CLI") {
    $targetDir = Find-AgyDir -AllowDialog ($Mode -eq "Interactive")
    if ($targetDir) { $targetDir | Out-File -FilePath $AgyPathFile -Encoding UTF8 -NoNewline }
    $patchSourceDir = Find-CliPatchSourceDir
} else {
    $targetDir = Find-AntigravityDir -AllowDialog ($Mode -eq "Interactive")
    if ($targetDir) { $targetDir | Out-File -FilePath $ConfigPathFile -Encoding UTF8 -NoNewline }
    $patchSourceDir = Find-IdePatchSourceDir
}

# 快捷非交互模式处理
if ($Mode -ne "Interactive") {
    if ($ProductMode -eq "CLI") {
        Sync-CliPatchFiles -TargetAgyDir $targetDir | Out-Null
    } else {
        $exePath = Ensure-NativeLauncherExe -TargetAppDir $targetDir
        Sync-IdePatchFiles -TargetAppDir $targetDir | Out-Null
        switch ($Mode) {
            "All" {
                Install-DesktopShortcut -LauncherPath $exePath -TargetAppDir $targetDir
                Install-StartMenuShortcut -LauncherPath $exePath -TargetAppDir $targetDir
                Install-TaskbarPin -LauncherPath $exePath -TargetAppDir $targetDir
            }
            "Desktop"   { Install-DesktopShortcut -LauncherPath $exePath -TargetAppDir $targetDir }
            "StartMenu" { Install-StartMenuShortcut -LauncherPath $exePath -TargetAppDir $targetDir }
            "Taskbar"   { Install-TaskbarPin -LauncherPath $exePath -TargetAppDir $targetDir }
            "Uninstall" { Invoke-Uninstall-Ide -TargetAppDir $targetDir }
        }
    }
    exit 0
}

# ============================================================================
# 交互式菜单循环
# ============================================================================
while ($true) {
    $isCli = ($ProductMode -eq "CLI")
    $title = if ($isCli) { T "TitleCli" } else { T "TitleIde" }
    Write-Title $title

    Write-Host "  $(if ($isCli) { T 'ModeCli' } else { T 'ModeIde' })" -ForegroundColor Yellow
    Write-Host "  $((T 'BoundTarget'))$targetDir"
    Write-Host "  $((T 'PatchSource'))$patchSourceDir"
    Write-Host ""

    # 读取当前端口以显示在菜单上
    $curPortStr = "7890"
    $curTypeStr = "socks5"
    $cfgCandidate = if ($patchSourceDir) { Join-Path $patchSourceDir "config.json" } else { "" }
    if ($cfgCandidate -and (Test-Path $cfgCandidate)) {
        try {
            $c = Get-Content -LiteralPath $cfgCandidate -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($c.proxy.port) { $curPortStr = $c.proxy.port }
            if ($c.proxy.type) { $curTypeStr = $c.proxy.type }
        } catch { }
    }

    if ($isCli) {
        Write-Host "  $((T 'OptCliDeploy'))"
        Write-Host "  $((T 'OptCliSync'))"
        Write-Host "  $((T 'OptCliDiag'))"
        Write-Host "  $((T 'OptCliUninstall'))"
        Write-Host "  $((T 'OptCliUpdate'))"
    } else {
        Write-Host "  $((T 'OptIdeAll'))"
        Write-Host "  $((T 'OptIdeDesktop'))"
        Write-Host "  $((T 'OptIdeStartMenu'))"
        Write-Host "  $((T 'OptIdeTaskbar'))"
        Write-Host "  $((T 'OptIdeSync'))"
        Write-Host "  $((T 'OptIdeDiag'))"
        Write-Host "  $((T 'OptIdeUninstall'))"
        Write-Host "  $((T 'OptIdeUpdate'))"
    }

    $portMenuText = [string]::Format((T "OptPort"), $curTypeStr, "127.0.0.1", $curPortStr)
    Write-Host "  $portMenuText"
    Write-Host "  $((T 'OptLang'))"
    Write-Host "  $((T 'OptExit'))"
    Write-Host ""

    $choice = Read-Host (T "PromptChoice")
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "1" }

    switch ($choice.ToUpper()) {
        "1" {
            if ($isCli) {
                Sync-CliPatchFiles -TargetAgyDir $targetDir | Out-Null
                Write-Host ""
                Write-Ok (T "DoneCliAll")
            } else {
                $exePath = Ensure-NativeLauncherExe -TargetAppDir $targetDir
                Sync-IdePatchFiles -TargetAppDir $targetDir | Out-Null
                Install-DesktopShortcut -LauncherPath $exePath -TargetAppDir $targetDir
                Install-StartMenuShortcut -LauncherPath $exePath -TargetAppDir $targetDir
                Install-TaskbarPin -LauncherPath $exePath -TargetAppDir $targetDir
                Write-Host ""
                Write-Ok (T "DoneIdeAll")
                Write-Host "   $((T 'DoneIdeHint'))" -ForegroundColor Cyan
            }
            break
        }
        "2" {
            if ($isCli) {
                Sync-CliPatchFiles -TargetAgyDir $targetDir | Out-Null
            } else {
                $exePath = Ensure-NativeLauncherExe -TargetAppDir $targetDir
                Sync-IdePatchFiles -TargetAppDir $targetDir | Out-Null
                Install-DesktopShortcut -LauncherPath $exePath -TargetAppDir $targetDir
            }
        }
        "3" {
            if ($isCli) {
                # CLI 诊断
                Write-Title (T "TitleDiag")
                Write-Host "agy.exe: $targetDir\agy.exe"
                Write-Host "dbghelp.dll: $(Test-Path (Join-Path $targetDir 'dbghelp.dll'))"
                Write-Host "antigravity_proxy.dll: $(Test-Path (Join-Path $targetDir 'antigravity_proxy.dll'))"
                Read-Host (T "PressEnterReturn")
            } else {
                $exePath = Ensure-NativeLauncherExe -TargetAppDir $targetDir
                Sync-IdePatchFiles -TargetAppDir $targetDir | Out-Null
                Install-StartMenuShortcut -LauncherPath $exePath -TargetAppDir $targetDir
            }
        }
        "4" {
            if ($isCli) {
                Invoke-Uninstall-Cli -TargetAgyDir $targetDir
                break
            } else {
                $exePath = Ensure-NativeLauncherExe -TargetAppDir $targetDir
                Install-TaskbarPin -LauncherPath $exePath -TargetAppDir $targetDir
            }
        }
        "5" {
            if ($isCli) {
                $upScript = Join-Path $LauncherDir "update-patch.ps1"
                if (Test-Path $upScript) { & $upScript -Lang $CurrentLang -NoPause }
            } else {
                Sync-IdePatchFiles -TargetAppDir $targetDir | Out-Null
            }
        }
        "6" {
            if (-not $isCli) {
                Write-Title (T "TitleDiag")
                Write-Host "Antigravity.exe: $targetDir\Antigravity.exe"
                Write-Host "version.dll: $(Test-Path (Join-Path $targetDir 'version.dll'))"
                Write-Host "config.json: $(Test-Path (Join-Path $targetDir 'config.json'))"
                Read-Host (T "PressEnterReturn")
            }
        }
        "7" {
            if (-not $isCli) {
                Invoke-Uninstall-Ide -TargetAppDir $targetDir
                break
            }
        }
        "8" {
            if (-not $isCli) {
                $upScript = Join-Path $LauncherDir "update-patch.ps1"
                if (Test-Path $upScript) { & $upScript -Lang $CurrentLang -NoPause }
            }
        }
        "P" {
            Invoke-PortSetting -CurrentTargetDir $targetDir
        }
        "L" {
            Invoke-LanguageSwitch
        }
        "0" { break }
        default { Write-Warn (T "InvalidChoice") }
    }

    if ($choice -in @("1", "4", "7", "0") -and ($choice -ne "4" -or $isCli)) {
        break
    }
}

if (-not $NoPause) {
    Write-Host ""
    Read-Host (T "PressEnterClose")
}
