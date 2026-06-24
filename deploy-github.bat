@echo off
rem deploy-github.bat - 在 Windows 上用于触发仓库部署（调用 update-deploy.ps1），并生成日志

rem Prepare log directory and filename
set "SCRIPT_DIR=%~dp0"
set "LOG_DIR=%SCRIPT_DIR%logs"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"
for /f "usebackq delims=" %%T in (`powershell -NoProfile -Command "Get-Date -Format 'yyyyMMdd-HHmmss'"`) do set TIMESTAMP=%%T
set "LOGFILE=%LOG_DIR%\deploy-%TIMESTAMP%.log"

echo Logging to %LOGFILE%

rem Check git
where git >nul 2>&1
if errorlevel 1 (
  echo git not found in PATH. Please install Git for Windows.
  exit /b 1
)

echo Switching to main branch and pulling latest...
git checkout main 2>nul
git pull origin main >> "%LOGFILE%" 2>&1

rem Prefer pwsh (PowerShell Core), otherwise fall back to Windows PowerShell
where pwsh >nul 2>&1
if %errorlevel%==0 (
  echo Running update-deploy.ps1 with pwsh (publishing to gh-pages); transcript -> %LOGFILE%
  pwsh -NoProfile -ExecutionPolicy Bypass -Command "Start-Transcript -Path \"%LOGFILE%\" -Force; try { & \"%SCRIPT_DIR%update-deploy.ps1\" -PublishGhPages } finally { Stop-Transcript }"
  exit /b %ERRORLEVEL%
)

where powershell >nul 2>&1
if %errorlevel%==0 (
  echo Running update-deploy.ps1 with Windows PowerShell (publishing to gh-pages); transcript -> %LOGFILE%
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Transcript -Path '%LOGFILE%' -Force; try { & '%SCRIPT_DIR%update-deploy.ps1' -PublishGhPages } finally { Stop-Transcript }"
  exit /b %ERRORLEVEL%
)

echo No PowerShell detected. You can run update-deploy.ps1 manually once PowerShell is available. > "%LOGFILE%"
exit /b 0
