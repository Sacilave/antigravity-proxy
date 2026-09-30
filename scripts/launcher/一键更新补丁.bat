@echo off
chcp 65001 >nul 2>&1
setlocal

set "CUR_DIR=%~dp0"
if exist "%CUR_DIR%launcher\update-patch.ps1" (
    set "PS_SCRIPT=%CUR_DIR%launcher\update-patch.ps1"
) else if exist "%CUR_DIR%scripts\launcher\update-patch.ps1" (
    set "PS_SCRIPT=%CUR_DIR%scripts\launcher\update-patch.ps1"
) else (
    set "PS_SCRIPT=%CUR_DIR%update-patch.ps1"
)

if not exist "%PS_SCRIPT%" (
    echo [错误] 未找到更新脚本: %PS_SCRIPT%
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" %*
