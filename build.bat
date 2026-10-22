@echo off
rem Assembla i giochi e pubblica i .bin (vedi build.ps1)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1" %*
pause
