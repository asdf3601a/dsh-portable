# Smoke-test a staged (or unzipped) dsh-portable folder on Windows.
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$StageDir,

  [string]$ExpectedDshVersion = '',

  [int]$WebTimeoutSec = 90,

  [int]$WebPort = 3080
)

$ErrorActionPreference = 'Stop'

$StageDir = (Resolve-Path -LiteralPath $StageDir).Path
$DshCmd = Join-Path $StageDir 'dsh.cmd'
$StartCmd = Join-Path $StageDir 'start.cmd'
$NodeExe = Join-Path $StageDir 'runtime\node\node.exe'
$PnpmExe = Join-Path $StageDir 'runtime\pnpm\pnpm.exe'

Write-Host "==> smoke: $StageDir"

if (-not (Test-Path $DshCmd)) { throw "missing dsh.cmd in $StageDir" }
if (-not (Test-Path $StartCmd)) { throw "missing start.cmd in $StageDir" }
if (-not (Test-Path $NodeExe)) { throw "missing bundled node.exe" }
if (-not (Test-Path $PnpmExe)) { throw "missing bundled pnpm.exe" }

# TMP/TEMP redirection must remain commented out by default.
$Launcher = Get-Content -LiteralPath $DshCmd -Raw
if ($Launcher -notmatch '(?im)^rem set "TEMP=%ROOT%\\data\\tmp"\s*$') {
  throw 'dsh.cmd must keep TEMP redirection commented out by default'
}
if ($Launcher -notmatch '(?im)^rem set "TMP=%ROOT%\\data\\tmp"\s*$') {
  throw 'dsh.cmd must keep TMP redirection commented out by default'
}
if ($Launcher -match '(?im)^set "TEMP=%ROOT%\\data\\tmp"\s*$' -or $Launcher -match '(?im)^set "TMP=%ROOT%\\data\\tmp"\s*$') {
  throw 'dsh.cmd must not enable TMP/TEMP redirection by default'
}
if ($Launcher -notmatch '(?im)registry\.env') {
  throw 'dsh.cmd must optionally load data\registry.env'
}
if ($Launcher -notmatch '(?im)npm_config_userconfig') {
  throw 'dsh.cmd must optionally set npm_config_userconfig from data\npmrc'
}
$NpmrcExample = Join-Path $StageDir 'data\npmrc.example'
$RegistryEnvExample = Join-Path $StageDir 'data\registry.env.example'
if (-not (Test-Path -LiteralPath $NpmrcExample)) { throw "missing $NpmrcExample" }
if (-not (Test-Path -LiteralPath $RegistryEnvExample)) { throw "missing $RegistryEnvExample" }

# --- optional registry loader (mirrors dsh.cmd; no dsh network required) ---
Write-Host '==> registry.env / npmrc loader'
$RegistryEnvPath = Join-Path $StageDir 'data\registry.env'
$NpmrcPath = Join-Path $StageDir 'data\npmrc'
$probeDir = Join-Path $StageDir 'data\cache'
$probeCmd = Join-Path $probeDir 'smoke-registry-probe.cmd'
New-Item -ItemType Directory -Force -Path $probeDir | Out-Null
$hadRegistryEnv = Test-Path -LiteralPath $RegistryEnvPath
$hadNpmrc = Test-Path -LiteralPath $NpmrcPath
$backupRegistryEnv = $null
$backupNpmrc = $null
if ($hadRegistryEnv) { $backupRegistryEnv = Get-Content -LiteralPath $RegistryEnvPath -Raw }
if ($hadNpmrc) { $backupNpmrc = Get-Content -LiteralPath $NpmrcPath -Raw }
try {
  Set-Content -LiteralPath $RegistryEnvPath -Value "npm_config_registry=https://nexus.example.com/repository/npm-group/`r`nnpm_config_always_auth=true`r`n" -Encoding ascii -NoNewline
  Set-Content -LiteralPath $NpmrcPath -Value "registry=https://nexus.example.com/repository/npm-group/`r`n" -Encoding ascii -NoNewline
  $probeBody = @"
@echo off
setlocal EnableExtensions
set "ROOT=$StageDir"
if exist "%ROOT%\data\registry.env" (
  for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%ROOT%\data\registry.env") do (
    if not "%%A"=="" if not defined %%A set "%%A=%%B"
  )
)
if exist "%ROOT%\data\npmrc" set "npm_config_userconfig=%ROOT%\data\npmrc"
echo REGISTRY=%npm_config_registry%
echo ALWAYS=%npm_config_always_auth%
echo USERCONFIG=%npm_config_userconfig%
"@
  [System.IO.File]::WriteAllText($probeCmd, ($probeBody -replace "`n", "`r`n"), [System.Text.Encoding]::ASCII)
  $probeOut = & cmd /c "`"$probeCmd`""
  $probeText = ($probeOut | Out-String)
  if ($probeText -notmatch 'REGISTRY=https://nexus\.example\.com/repository/npm-group/') {
    throw "registry.env did not set npm_config_registry; output: $probeText"
  }
  if ($probeText -notmatch 'ALWAYS=true') {
    throw "registry.env did not set npm_config_always_auth; output: $probeText"
  }
  $expectedUserconfig = Join-Path $StageDir 'data\npmrc'
  if ($probeText -notmatch [regex]::Escape("USERCONFIG=$expectedUserconfig")) {
    throw "npmrc did not set npm_config_userconfig to $expectedUserconfig; output: $probeText"
  }

  # Pre-set env must win over registry.env
  $probeOverride = Join-Path $probeDir 'smoke-registry-override.cmd'
  $overrideBody = @"
@echo off
setlocal EnableExtensions
set "ROOT=$StageDir"
set "npm_config_registry=https://env-wins.example/repository/npm/"
if exist "%ROOT%\data\registry.env" (
  for /f "usebackq eol=# tokens=1,* delims==" %%A in ("%ROOT%\data\registry.env") do (
    if not "%%A"=="" if not defined %%A set "%%A=%%B"
  )
)
echo REGISTRY=%npm_config_registry%
"@
  [System.IO.File]::WriteAllText($probeOverride, ($overrideBody -replace "`n", "`r`n"), [System.Text.Encoding]::ASCII)
  $overrideOut = & cmd /c "`"$probeOverride`""
  $overrideText = ($overrideOut | Out-String)
  if ($overrideText -notmatch 'REGISTRY=https://env-wins\.example/repository/npm/') {
    throw "pre-set npm_config_registry should win over registry.env; output: $overrideText"
  }
  Write-Host '    registry.env + npmrc load OK (env override OK)'
} finally {
  if ($hadRegistryEnv) {
    Set-Content -LiteralPath $RegistryEnvPath -Value $backupRegistryEnv -Encoding ascii -NoNewline
  } elseif (Test-Path -LiteralPath $RegistryEnvPath) {
    Remove-Item -LiteralPath $RegistryEnvPath -Force
  }
  if ($hadNpmrc) {
    Set-Content -LiteralPath $NpmrcPath -Value $backupNpmrc -Encoding ascii -NoNewline
  } elseif (Test-Path -LiteralPath $NpmrcPath) {
    Remove-Item -LiteralPath $NpmrcPath -Force
  }
  foreach ($f in @($probeCmd, (Join-Path $probeDir 'smoke-registry-override.cmd'))) {
    if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force }
  }
}

function Get-ProfileSnapshot {
  $paths = @(
    (Join-Path $env:USERPROFILE '.dsh'),
    (Join-Path $env:APPDATA 'npm'),
    (Join-Path $env:APPDATA 'npm-cache'),
    (Join-Path $env:LOCALAPPDATA 'npm-cache'),
    (Join-Path $env:LOCALAPPDATA 'pnpm'),
    (Join-Path $env:LOCALAPPDATA 'pnpm-store')
  )
  $snap = @{}
  foreach ($p in $paths) {
    if (Test-Path -LiteralPath $p) {
      $files = Get-ChildItem -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue |
        Sort-Object FullName |
        ForEach-Object { '{0}|{1}|{2}' -f $_.FullName, $_.Length, $_.LastWriteTimeUtc.Ticks }
      $snap[$p] = ($files -join "`n")
    } else {
      $snap[$p] = $null
    }
  }
  return $snap
}

function Assert-NoProfileDrift([hashtable]$Before, [hashtable]$After) {
  foreach ($key in $Before.Keys) {
    $b = $Before[$key]
    $a = $After[$key]
    if ($b -eq $null -and $a -ne $null) {
      throw "portable isolation failed: created user-profile path $key"
    }
    if ($b -ne $a) {
      throw "portable isolation failed: modified user-profile path $key"
    }
  }
}

$Before = Get-ProfileSnapshot

# --- version ---
Write-Host '==> dsh --version'
$VerOut = & cmd /c "`"$DshCmd`" --version"
$VerOut = ("$VerOut").Trim()
Write-Host "    $VerOut"
if ($ExpectedDshVersion -and $VerOut -ne $ExpectedDshVersion) {
  throw "dsh --version '$VerOut' != expected '$ExpectedDshVersion'"
}

# --- node engine floor ---
$NodeVer = & $NodeExe --version
$NodeVer = ("$NodeVer").Trim().TrimStart('v')
Write-Host "==> bundled node $NodeVer"
$parts = $NodeVer.Split('.')
$major = [int]$parts[0]
$minor = [int]$parts[1]
$okEngine = ($major -eq 22 -and $minor -ge 19) -or ($major -ge 24)
if (-not $okEngine) { throw "bundled Node $NodeVer outside supported engines (^22.19 || >=24)" }

# --- pnpm binary ---
Write-Host '==> pnpm --version'
$PnpmVer = & $PnpmExe --version
if ($LASTEXITCODE -ne 0) { throw "pnpm --version failed with exit code $LASTEXITCODE" }
$PnpmVer = ("$PnpmVer").Trim()
if (-not $PnpmVer) { throw 'pnpm --version returned empty output' }
Write-Host "    $PnpmVer"
if (-not (Test-Path (Join-Path $StageDir 'runtime\pnpm\dist\pnpm.mjs'))) {
  throw 'runtime\pnpm\dist\pnpm.mjs missing — pnpm zip must be fully extracted'
}

# --- dump-config ---
Write-Host '==> dsh web --dump-config'
$Dump = & cmd /c "`"$DshCmd`" web --dump-config 2>&1"
if ($LASTEXITCODE -ne 0) {
  Write-Host ($Dump | Out-String)
  throw "dsh web --dump-config failed with exit code $LASTEXITCODE"
}
$ExpectedHome = Join-Path $StageDir 'data\dsh-home'
$DumpNormalized = (($Dump | Out-String) -replace '\\', '/')
$HomeNeedle = $ExpectedHome.Replace('\', '/')
if ($DumpNormalized -like "*$HomeNeedle*") {
  Write-Host "    dump-config references $ExpectedHome"
} else {
  Write-Host '    dump-config did not echo absolute DSH_HOME (OK if layout differs); launcher still sets it'
}
Write-Host "    expected DSH_HOME=$ExpectedHome"

# --- web HTTP probe ---
Write-Host "==> dsh web --no-open (port $WebPort)"
$WebOut = Join-Path $StageDir 'data\smoke-web.out.log'
$WebErr = Join-Path $StageDir 'data\smoke-web.err.log'
foreach ($f in @($WebOut, $WebErr)) { if (Test-Path $f) { Remove-Item -Force $f } }

# Invoke through cmd.exe so we exercise the real launcher, but capture stdio via
# Start-Process redirects (cmd '>' redirection is unreliable under Start-Process).
$WebProc = Start-Process -FilePath 'cmd.exe' `
  -ArgumentList @('/c', "`"$DshCmd`" web --no-open --port $WebPort") `
  -WorkingDirectory (Join-Path $StageDir 'data\workspace') `
  -RedirectStandardOutput $WebOut `
  -RedirectStandardError $WebErr `
  -PassThru -WindowStyle Hidden

function Show-WebLogs {
  foreach ($f in @($WebOut, $WebErr)) {
    if (Test-Path $f) {
      Write-Host "---- $(Split-Path $f -Leaf) ----"
      Get-Content -LiteralPath $f | Write-Host
    }
  }
}

try {
  $deadline = (Get-Date).AddSeconds($WebTimeoutSec)
  $ok = $false
  $probeUrl = "http://127.0.0.1:$WebPort/"
  while ((Get-Date) -lt $deadline) {
    # Newer dsh builds print a one-time token URL (required for browser trust).
    if (Test-Path $WebOut) {
      $outText = Get-Content -LiteralPath $WebOut -Raw -ErrorAction SilentlyContinue
      $urlPattern = "https?://127\.0\.0\.1:$WebPort/\S*"
      if ($outText -match $urlPattern) {
        $probeUrl = $Matches[0].Trim()
      } elseif ($outText -match 'token=([A-Za-z0-9._\-]+)') {
        $probeUrl = "http://127.0.0.1:$WebPort/?token=$($Matches[1])"
      }
    }
    try {
      $resp = Invoke-WebRequest -Uri $probeUrl -UseBasicParsing -TimeoutSec 3
      if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 500) {
        $ok = $true
        Write-Host "    HTTP $($resp.StatusCode) ($probeUrl)"
        break
      }
    } catch {
      Start-Sleep -Seconds 2
    }
    if ($WebProc.HasExited) {
      Show-WebLogs
      throw "dsh web exited early with code $($WebProc.ExitCode)"
    }
  }
  if (-not $ok) {
    Show-WebLogs
    throw "dsh web did not respond on 127.0.0.1:$WebPort within ${WebTimeoutSec}s"
  }
} finally {
  if (-not $WebProc.HasExited) {
    Stop-Process -Id $WebProc.Id -Force -ErrorAction SilentlyContinue
  }
  Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -like "*$StageDir*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

# --- profile created under data\ ---
$WebProfile = Join-Path $StageDir 'data\dsh-home\profiles\web'
if (-not (Test-Path $WebProfile)) {
  Write-Host "    warning: profiles\\web not found yet (dump/init layout may differ); checking dsh-home nonempty"
  $HomeItems = Get-ChildItem -LiteralPath (Join-Path $StageDir 'data\dsh-home') -Force -ErrorAction SilentlyContinue
  if (-not $HomeItems -or $HomeItems.Count -eq 0) {
    throw 'data\dsh-home stayed empty after web start'
  }
} else {
  Write-Host "    profiles\\web present"
}

$After = Get-ProfileSnapshot
Assert-NoProfileDrift -Before $Before -After $After
Write-Host '==> profile isolation OK (no %%USERPROFILE%% persistent drift)'
Write-Host '==> smoke passed'
