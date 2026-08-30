@echo off
setlocal EnableExtensions

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

set "DSH_PORTABLE_ROOT=%ROOT%"
set "DSH_HOME=%ROOT%\data\dsh-home"
set "_P_SHELL="
set "_P_PROXY="
set "_P_PROXY_OK="
set "_P_HTTP_PROXY="
set "_P_HTTPS_PROXY="
set "_P_ALL_PROXY="
set "_P_NO_PROXY="
set "_P_NPM_REGISTRY="
set "_P_NPM_ALWAYS_AUTH="
set "_P_NPM_AUTH_TOKEN="
set "_P_NODE_EXTRA_CA_CERTS="
set "_HAS_PROXY="
if exist "%ROOT%\data\portable.env" (
  for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%ROOT%\data\portable.env") do (
    if /I "%%A"=="SHELL" if not "%%B"=="" set "_P_SHELL=%%B"
    if /I "%%A"=="PROXY" if not "%%B"=="" set "_P_PROXY=%%B"
    if /I "%%A"=="HTTP_PROXY" if not "%%B"=="" set "_P_HTTP_PROXY=%%B"
    if /I "%%A"=="HTTPS_PROXY" if not "%%B"=="" set "_P_HTTPS_PROXY=%%B"
    if /I "%%A"=="ALL_PROXY" if not "%%B"=="" set "_P_ALL_PROXY=%%B"
    if /I "%%A"=="NO_PROXY" if not "%%B"=="" set "_P_NO_PROXY=%%B"
    if /I "%%A"=="NPM_REGISTRY" if not "%%B"=="" set "_P_NPM_REGISTRY=%%B"
    if /I "%%A"=="NPM_ALWAYS_AUTH" if not "%%B"=="" set "_P_NPM_ALWAYS_AUTH=%%B"
    if /I "%%A"=="NPM_AUTH_TOKEN" if not "%%B"=="" set "_P_NPM_AUTH_TOKEN=%%B"
    if /I "%%A"=="NODE_EXTRA_CA_CERTS" if not "%%B"=="" set "_P_NODE_EXTRA_CA_CERTS=%%B"
  )
)
if not defined DSH_SHELL if defined _P_SHELL set "DSH_SHELL=%_P_SHELL%"
if /I not "%DSH_SHELL%"=="bash" set "DSH_SHELL=pwsh"

if not defined _P_PROXY goto :proxy_scheme_done
if /I "%_P_PROXY:~0,7%"=="http://" set "_P_PROXY_OK=1"
if /I "%_P_PROXY:~0,8%"=="https://" set "_P_PROXY_OK=1"
if not defined _P_PROXY_OK echo [dsh-portable] ignoring PROXY - need http:// or https://. Use ALL_PROXY for socks.
:proxy_scheme_done

if not defined HTTP_PROXY if defined _P_HTTP_PROXY set "HTTP_PROXY=%_P_HTTP_PROXY%"
if not defined HTTP_PROXY if defined _P_PROXY_OK set "HTTP_PROXY=%_P_PROXY%"
if not defined HTTPS_PROXY if defined _P_HTTPS_PROXY set "HTTPS_PROXY=%_P_HTTPS_PROXY%"
if not defined HTTPS_PROXY if defined _P_PROXY_OK set "HTTPS_PROXY=%_P_PROXY%"
if not defined ALL_PROXY if defined _P_ALL_PROXY set "ALL_PROXY=%_P_ALL_PROXY%"
if not defined ALL_PROXY goto :all_proxy_scheme_done
if /I "%ALL_PROXY:~0,7%"=="http://" if not defined HTTP_PROXY set "HTTP_PROXY=%ALL_PROXY%"
if /I "%ALL_PROXY:~0,8%"=="https://" if not defined HTTP_PROXY set "HTTP_PROXY=%ALL_PROXY%"
if /I "%ALL_PROXY:~0,7%"=="http://" if not defined HTTPS_PROXY set "HTTPS_PROXY=%ALL_PROXY%"
if /I "%ALL_PROXY:~0,8%"=="https://" if not defined HTTPS_PROXY set "HTTPS_PROXY=%ALL_PROXY%"
:all_proxy_scheme_done
if not defined HTTPS_PROXY if defined HTTP_PROXY set "HTTPS_PROXY=%HTTP_PROXY%"

if defined HTTP_PROXY set "_HAS_PROXY=1"
if defined HTTPS_PROXY set "_HAS_PROXY=1"
if defined _HAS_PROXY if not defined NO_PROXY if defined _P_NO_PROXY set "NO_PROXY=%_P_NO_PROXY%"
if defined _HAS_PROXY if not defined NO_PROXY set "NO_PROXY=localhost,127.0.0.1,::1"
if not defined _HAS_PROXY if not defined NO_PROXY if defined _P_NO_PROXY set "NO_PROXY=%_P_NO_PROXY%"
if defined HTTP_PROXY if not defined NODE_USE_ENV_PROXY set "NODE_USE_ENV_PROXY=1"
if defined HTTPS_PROXY if not defined NODE_USE_ENV_PROXY set "NODE_USE_ENV_PROXY=1"

if defined NODE_EXTRA_CA_CERTS goto :ca_done
if not defined _P_NODE_EXTRA_CA_CERTS goto :ca_done
if "%_P_NODE_EXTRA_CA_CERTS:~1,1%"==":" set "NODE_EXTRA_CA_CERTS=%_P_NODE_EXTRA_CA_CERTS%"
if defined NODE_EXTRA_CA_CERTS goto :ca_done
if "%_P_NODE_EXTRA_CA_CERTS:~0,2%"=="\\" set "NODE_EXTRA_CA_CERTS=%_P_NODE_EXTRA_CA_CERTS%"
if defined NODE_EXTRA_CA_CERTS goto :ca_done
set "NODE_EXTRA_CA_CERTS=%ROOT%\%_P_NODE_EXTRA_CA_CERTS%"
:ca_done

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

REM Optional npm registry: data\npmrc (legacy) wins over portable.env NPM_*.
REM Pre-set npm_config_* environment variables override both.
if exist "%ROOT%\data\npmrc" (
  if not defined npm_config_userconfig set "npm_config_userconfig=%ROOT%\data\npmrc"
) else (
  if not defined npm_config_registry if defined _P_NPM_REGISTRY set "npm_config_registry=%_P_NPM_REGISTRY%"
  if not defined npm_config_always_auth if defined _P_NPM_ALWAYS_AUTH set "npm_config_always_auth=%_P_NPM_ALWAYS_AUTH%"
)

REM Optional: keep temp files inside the portable folder.
REM Default is OFF - rely on the system TEMP cleanup.
REM set "TEMP=%ROOT%\data\tmp"
REM set "TMP=%ROOT%\data\tmp"

if not exist "%ROOT%\data\dsh-home" mkdir "%ROOT%\data\dsh-home"
if not exist "%ROOT%\data\workspace" mkdir "%ROOT%\data\workspace"
if not exist "%ROOT%\data\cache" mkdir "%ROOT%\data\cache"
if not exist "%ROOT%\data\cache\npm" mkdir "%ROOT%\data\cache\npm"
if not exist "%ROOT%\data\cache\npm-prefix" mkdir "%ROOT%\data\cache\npm-prefix"
if not exist "%ROOT%\data\cache\pnpm-home" mkdir "%ROOT%\data\cache\pnpm-home"
if not exist "%ROOT%\data\cache\pnpm-store" mkdir "%ROOT%\data\cache\pnpm-store"

set "NODE_EXE=%ROOT%\runtime\node\node.exe"
set "DSH_BIN=%ROOT%\app\node_modules\@deepseek-ai\dsh\lib\bin.js"
set "GIT_EXE=%ROOT%\runtime\git\cmd\git.exe"
set "DSH_PORTABLE_PATCH=%ROOT%\runtime\portable\shell.cordis.yml"
set "DSH_PORTABLE_ARGV=%ROOT%\runtime\portable\argv.cjs"

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
if not exist "%DSH_PORTABLE_PATCH%" (
  echo [dsh-portable] Portable shell overlay not found: "%DSH_PORTABLE_PATCH%"
  exit /b 1
)
if not exist "%DSH_PORTABLE_ARGV%" (
  echo [dsh-portable] Portable argument preload not found: "%DSH_PORTABLE_ARGV%"
  exit /b 1
)

if exist "%ROOT%\data\npmrc" goto :npm_gen_done
if defined npm_config_userconfig goto :npm_gen_done
if not defined _P_NPM_AUTH_TOKEN goto :npm_gen_done
if not defined _P_NPM_REGISTRY goto :npm_gen_done
set "DSH_GEN_NPM_REGISTRY=%_P_NPM_REGISTRY%"
set "DSH_GEN_NPM_TOKEN=%_P_NPM_AUTH_TOKEN%"
set "DSH_GEN_NPM_ALWAYS_AUTH=%_P_NPM_ALWAYS_AUTH%"
set "DSH_GEN_NPMRC=%ROOT%\data\cache\generated.npmrc"
"%NODE_EXE%" -e "const fs=require('fs'); const r=process.env.DSH_GEN_NPM_REGISTRY; const t=process.env.DSH_GEN_NPM_TOKEN; const a=process.env.DSH_GEN_NPM_ALWAYS_AUTH||''; const u=new URL(r); const p=u.pathname.endsWith('/')?u.pathname:u.pathname+'/'; let s='registry='+r+'\n'; if(a) s+='always-auth='+a+'\n'; s+='//'+u.host+p+':_authToken='+t+'\n'; fs.writeFileSync(process.env.DSH_GEN_NPMRC,s);"
if errorlevel 1 (
  echo [dsh-portable] Failed to write data\cache\generated.npmrc from NPM_REGISTRY / NPM_AUTH_TOKEN
  exit /b 1
)
set "npm_config_userconfig=%ROOT%\data\cache\generated.npmrc"
set "DSH_GEN_NPM_REGISTRY="
set "DSH_GEN_NPM_TOKEN="
set "DSH_GEN_NPM_ALWAYS_AUTH="
set "DSH_GEN_NPMRC="
:npm_gen_done

set "_P_SHELL="
set "_P_PROXY="
set "_P_PROXY_OK="
set "_P_HTTP_PROXY="
set "_P_HTTPS_PROXY="
set "_P_ALL_PROXY="
set "_P_NO_PROXY="
set "_P_NPM_REGISTRY="
set "_P_NPM_ALWAYS_AUTH="
set "_P_NPM_AUTH_TOKEN="
set "_P_NODE_EXTRA_CA_CERTS="
set "_HAS_PROXY="

cd /d "%ROOT%\data\workspace"
"%NODE_EXE%" --require "%DSH_PORTABLE_ARGV%" "%DSH_BIN%" %*
exit /b %ERRORLEVEL%
