@echo off
setlocal DisableDelayedExpansion
if not "%~2"=="" goto usage
if "%~1"=="" goto preview
if /i "%~1"=="--dry-run" goto preview
if /i "%~1"=="--clean" goto clean
if /i "%~1"=="--help" goto usage
goto invalid
:preview
set "SC_CLEANER_MODE=Preview"
goto run
:clean
set "SC_CLEANER_MODE=Clean"
goto run
:run
if not exist "%~dp0SC Cleaner.ps1" (
  echo ERROR: SC Cleaner.ps1 is missing. Extract both files from the ZIP first.
  pause
  exit /b 1
)
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0SC Cleaner.ps1" -Mode %SC_CLEANER_MODE%
set "SC_CLEANER_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %SC_CLEANER_EXIT%
:invalid
echo ERROR: Unknown argument.
:usage
echo Usage: "SC Cleaner.bat" [--dry-run ^| --clean ^| --help]
echo Default: simulation only. --clean shows the plan and asks you to type CLEAN.
if /i "%~1"=="--help" exit /b 0
exit /b 2
