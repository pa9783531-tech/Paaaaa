@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
title PakesY - Windows One-Click Start
echo.
echo ============================================
echo  PakesY - One-Click Windows Start (v3)
echo ============================================
echo.
echo [PakesY] Checking and installing missing tools automatically...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_windows.ps1"
set "RESULT=%ERRORLEVEL%"
if not "%RESULT%"=="0" (
  echo.
  echo [PakesY] Setup or startup failed. See setup_log.txt for details.
  echo [PakesY] Send the error text or setup_log.txt if you need help.
  pause
)
exit /b %RESULT%
