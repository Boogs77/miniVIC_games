@echo off
rem Assembles the games and publishes the .bin files (see build.ps1)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1" %*
pause
