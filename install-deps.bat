@echo off
:: ============================================================
::  NEXUS OS — One-Click Dependency Installer (Windows + WSL)
::  Double-click করো অথবা cmd-এ চালাও
:: ============================================================

title Nexus OS — Dependency Installer

echo.
echo   NEXUS OS — Windows Setup (WSL)
echo   ================================
echo.

:: WSL আছে কিনা চেক করো
wsl --status >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] WSL installed নেই!
    echo.
    echo   WSL install করতে PowerShell (Admin) এ চালাও:
    echo   wsl --install
    echo.
    echo   Install হওয়ার পর PC restart করো, তারপর এই ফাইল আবার চালাও।
    pause
    exit /b 1
)

echo [OK] WSL পাওয়া গেছে।
echo.
echo [1/2] WSL এ dependencies install হচ্ছে...
wsl bash -c "sudo bash install-deps.sh"

if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Install failed! উপরের error দেখো।
    pause
    exit /b 1
)

echo.
echo [2/2] Setup সম্পন্ন!
echo.
echo   এখন ISO build করতে:
echo     wsl make build
echo.
echo   অথবা WSL terminal খুলে:
echo     sudo ./makebuild.sh
echo.
pause
