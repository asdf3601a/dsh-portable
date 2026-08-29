@echo off
setlocal EnableExtensions

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

set "DSH_PORTABLE_ROOT=%ROOT%"
set "DSH_HOME=%ROOT%\data\dsh-home"
set "DSH_SHELL=pwsh"
if exist "%ROOT%\data\portable.env" (
  findstr /b /i /c:"SHELL=bash" "%ROOT%\data\portable.env" >nul 2>&1
  if not errorlevel 1 set "DSH_SHELL=bash"
)
if /I not "%DSH_SHELL%"=="bash" set "DSH_SHELL=pwsh"

if /I "%DSH_SHELL%"=="bash" (
  set "PATH=%ROOT%\runtime\node;%ROOT%\runtime\pnpm;%ROOT%\runtime\git\usr\bin;%ROOT%\runtime\git\mingw64\bin;%ROOT%\runtime\git\cmd;%PATH%"
) else (
  set "PATH=%ROOT%\runtime\node;%ROOT%\runtime\pnpm;%ROOT%\runtime\git\cmd;%PATH%"
)
set "GIT_INSTALL_ROOT=%ROOT%\runtime\git"
set "GIT_CONFIG_GLOBAL=%ROOT%\data\dsh-home\gitconfig"
set "npm_config_cache=%ROOT%\data\cache\npm"
set "npm_config_prefix=%ROOT%\data\cache\npm-prefix"
set "PNPM_HOME=%ROOT%\data\cache\pnpm-home"
set "npm_config_store_dir=%ROOT%\data\cache\pnpm-store"
set "NARB_NATIVE_CACHE_DIR=%ROOT%\data\cache\native-addons"

REM Optional Sonatype Nexus / npm registry (see data\npmrc.example).
REM Pre-set npm_config_* environment variables override data\npmrc settings.
if exist "%ROOT%\data\npmrc" if not defined npm_config_userconfig set "npm_config_userconfig=%ROOT%\data\npmrc"

REM Optional: keep temp files inside the portable folder.
REM Default is OFF - rely on the system TEMP cleanup.
REM set "TEMP=%ROOT%\data\tmp"
REM set "TMP=%ROOT%\data\tmp"

if not exist "%ROOT%\data\dsh-home" mkdir "%ROOT%\data\dsh-home"
if not exist "%ROOT%\data\workspace" mkdir "%ROOT%\data\workspace"
if not exist "%ROOT%\data\cache\npm" mkdir "%ROOT%\data\cache\npm"
if not exist "%ROOT%\data\cache\npm-prefix" mkdir "%ROOT%\data\cache\npm-prefix"
if not exist "%ROOT%\data\cache\pnpm-home" mkdir "%ROOT%\data\cache\pnpm-home"
if not exist "%ROOT%\data\cache\pnpm-store" mkdir "%ROOT%\data\cache\pnpm-store"

set "NODE_EXE=%ROOT%\runtime\node\node.exe"
set "DSH_BIN=%ROOT%\app\node_modules\@deepseek-ai\dsh\lib\bin.js"
set "GIT_EXE=%ROOT%\runtime\git\cmd\git.exe"
set "PATCH=%ROOT%\runtime\portable\shell.cordis.yml"

if not exist "%NODE_EXE%" (
  echo [dsh-portable] Bundled Node.js not found: "%NODE_EXE%"
  exit /b 1
)
if not exist "%DSH_BIN%" (
  echo [dsh-portable] Bundled dsh not found: "%DSH_BIN%"
  exit /b 1
)
if not exist "%GIT_EXE%" (
  echo [dsh-portable] Bundled Git not found: "%GIT_EXE%"
  exit /b 1
)

cd /d "%ROOT%\data\workspace"
if /I "%~1"=="web" (
  if exist "%PATCH%" (
    "%NODE_EXE%" "%DSH_BIN%" web --patch "%PATCH%" %2 %3 %4 %5 %6 %7 %8 %9
  ) else (
    "%NODE_EXE%" "%DSH_BIN%" web %2 %3 %4 %5 %6 %7 %8 %9
  )
  exit /b %ERRORLEVEL%
)
"%NODE_EXE%" "%DSH_BIN%" %*
exit /b %ERRORLEVEL%
