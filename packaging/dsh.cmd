@echo off
setlocal EnableExtensions

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

set "DSH_HOME=%ROOT%\data\dsh-home"
set "PATH=%ROOT%\runtime\node;%ROOT%\runtime\pnpm;%PATH%"
set "npm_config_cache=%ROOT%\data\cache\npm"
set "npm_config_prefix=%ROOT%\data\cache\npm-prefix"
set "PNPM_HOME=%ROOT%\data\cache\pnpm-home"
set "npm_config_store_dir=%ROOT%\data\cache\pnpm-store"

REM Optional Sonatype Nexus / npm registry (see data\npmrc.example and data\registry.env.example).
REM Pre-set environment variables win over data\registry.env; npm_config_* also override data\npmrc.
if exist "%ROOT%\data\registry.env" (
  for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%ROOT%\data\registry.env") do (
    if not "%%A"=="" if not defined %%A set "%%A=%%B"
  )
)
if exist "%ROOT%\data\npmrc" set "npm_config_userconfig=%ROOT%\data\npmrc"

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

if not exist "%NODE_EXE%" (
  echo [dsh-portable] Bundled Node.js not found: "%NODE_EXE%"
  exit /b 1
)
if not exist "%DSH_BIN%" (
  echo [dsh-portable] Bundled dsh not found: "%DSH_BIN%"
  exit /b 1
)

cd /d "%ROOT%\data\workspace"
"%NODE_EXE%" "%DSH_BIN%" %*
exit /b %ERRORLEVEL%