@echo off
chcp 65001 >nul 2>&1
setlocal

set "CUR_DIR=%~dp0"
if exist "%CUR_DIR%launcher\install-windows.ps1" (
    set "PS_SCRIPT=%CUR_DIR%launcher\install-windows.ps1"
) else if exist "%CUR_DIR%scripts\launcher\install-windows.ps1" (
    set "PS_SCRIPT=%CUR_DIR%scripts\launcher\install-windows.ps1"
) else (
    set "PS_SCRIPT=%CUR_DIR%install-windows.ps1"
)

if not exist "%PS_SCRIPT%" (
    echo [错误] 未找到安装脚本: %PS_SCRIPT%
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" %*
if %ERRORLEVEL% neq 0 (
    echo.
    echo [提示] 脚本执行遇到问题，已保留窗口以便查看输出。
    pause
)
