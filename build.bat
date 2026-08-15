@echo off
REM Double-click this to build the minified dist\ copy of Qalcom OS.
REM It just runs build-qalcom.ps1 with the execution policy bypassed for this one call.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-qalcom.ps1" %*
echo.
pause
