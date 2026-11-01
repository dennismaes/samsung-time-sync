@echo off
rem Double-click this file to set up the oven time sync.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0oven_sync.ps1" -Setup
echo.
pause
