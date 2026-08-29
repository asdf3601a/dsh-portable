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
$GitExe = Join-Path $StageDir 'runtime\git\cmd\git.exe'
$BashExe = Join-Path $StageDir 'runtime\git\usr\bin\bash.exe'
$ShellOverlay = Join-Path $StageDir 'runtime\portable\shell.cordis.yml'
$PortablePreset = Join-Path $StageDir 'runtime\portable\presets\portable\agent.cordis.yml'

Write-Host "==> smoke: $StageDir"

if (-not (Test-Path $DshCmd)) { throw "missing dsh.cmd in $StageDir" }
if (-not (Test-Path $StartCmd)) { throw "missing start.cmd in $StageDir" }
if (-not (Test-Path $NodeExe)) { throw "missing bundled node.exe" }
if (-not (Test-Path $PnpmExe)) { throw "missing bundled pnpm.exe" }
if (-not (Test-Path $GitExe)) { throw "missing bundled git.exe" }
if (-not (Test-Path $BashExe)) { throw "missing bundled Git Bash (usr\bin\bash.exe)" }
if (-not (Test-Path $ShellOverlay)) { throw "missing shell overlay: $ShellOverlay" }
if (-not (Test-Path $PortablePreset)) { throw "missing portable preset: $PortablePreset" }

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
if ($Launcher -notmatch '(?im)^if exist "%ROOT%\\data\\npmrc" if not defined npm_config_userconfig set "npm_config_userconfig=%ROOT%\\data\\npmrc"\s*$') {
  throw 'dsh.cmd must optionally set npm_config_userconfig from data\npmrc'
}
if ($Launcher -notmatch '(?im)^set "NARB_NATIVE_CACHE_DIR=%ROOT%\\data\\cache\\native-addons"\s*$') {
  throw 'dsh.cmd must keep the native addon cache inside data\cache\native-addons'
}
if ($Launcher -notmatch '(?im)^set "DSH_PORTABLE_ROOT=%ROOT%"\s*$') {
  throw 'dsh.cmd must set DSH_PORTABLE_ROOT'
}
if ($Launcher -notmatch '(?im)^set "GIT_CONFIG_GLOBAL=%ROOT%\\data\\dsh-home\\gitconfig"\s*$') {
  throw 'dsh.cmd must keep gitconfig inside data\dsh-home'
}
if ($Launcher -notmatch '(?im)runtime\\git\\cmd') {
  throw 'dsh.cmd must prepend bundled runtime\git\cmd to PATH'
}
if ($Launcher -notmatch '(?im)web --patch "%PATCH%"') {
  throw 'dsh.cmd must pass the portable shell overlay as web --patch'
}
$NpmrcExample = Join-Path $StageDir 'data\npmrc.example'
if (-not (Test-Path -LiteralPath $NpmrcExample)) { throw "missing $NpmrcExample" }
$PortableEnvExample = Join-Path $StageDir 'data\portable.env.example'
if (-not (Test-Path -LiteralPath $PortableEnvExample)) { throw "missing $PortableEnvExample" }

function Get-ProfileSnapshot {
  $paths = @(
    (Join-Path $env:USERPROFILE '.dsh'),
    (Join-Path $env:APPDATA 'npm'),
    (Join-Path $env:APPDATA 'npm-cache'),
    (Join-Path $env:LOCALAPPDATA 'npm-cache'),
    (Join-Path $env:LOCALAPPDATA 'pnpm'),
    (Join-Path $env:LOCALAPPDATA 'pnpm-store'),
    (Join-Path $env:LOCALAPPDATA 'node-addon-native-custom-loader'),
    (Join-Path $env:USERPROFILE '.gitconfig'),
    (Join-Path $env:USERPROFILE '.git-credentials')
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

# --- bundled Git ---
Write-Host '==> git --version (bundled)'
$GitVer = & $GitExe --version
if ($LASTEXITCODE -ne 0) { throw "bundled git --version failed with exit code $LASTEXITCODE" }
$GitVer = ("$GitVer").Trim()
if ($GitVer -notmatch '^git version ') { throw "bundled git --version returned '$GitVer'" }
Write-Host "    $GitVer"

Write-Host '==> git bash -c'
$BashOut = & $BashExe -c 'echo DSH_OK'
if ($LASTEXITCODE -ne 0) { throw "bundled bash -c failed with exit code $LASTEXITCODE" }
$BashOut = ("$BashOut").Trim()
if ($BashOut -ne 'DSH_OK') { throw "bundled bash -c returned '$BashOut'" }
Write-Host '    DSH_OK'

$PresetText = Get-Content -LiteralPath $PortablePreset -Raw
if ($PresetText -notmatch "process\.env\.DSH_SHELL !== 'bash'") {
  throw 'portable preset must gate tool-bash on DSH_SHELL'
}
if ($PresetText -notmatch "process\.env\.DSH_SHELL === 'bash'") {
  throw 'portable preset must gate tool-pwsh on DSH_SHELL'
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
$DumpText = ($Dump | Out-String)
if ($DumpText -notmatch 'DSH_SHELL') {
  throw 'dsh web --dump-config must include the portable shell overlay'
}

$PortableEnv = Join-Path $StageDir 'data\portable.env'
$PortableEnvBackup = $null
if (Test-Path -LiteralPath $PortableEnv) {
  $PortableEnvBackup = Get-Content -LiteralPath $PortableEnv -Raw
}
try {
  Set-Content -Path $PortableEnv -Value "SHELL=bash`r`n" -Encoding ascii
  Write-Host '==> dsh web --dump-config (SHELL=bash)'
  $DumpBash = & cmd /c "`"$DshCmd`" web --dump-config 2>&1"
  if ($LASTEXITCODE -ne 0) {
    Write-Host ($DumpBash | Out-String)
    throw "dsh web --dump-config with SHELL=bash failed with exit code $LASTEXITCODE"
  }
  $DumpBashText = ($DumpBash | Out-String)
  if ($DumpBashText -notmatch 'DSH_SHELL') {
    throw 'SHELL=bash dump-config must still include the portable shell overlay'
  }
} finally {
  if ($null -ne $PortableEnvBackup) {
    Set-Content -Path $PortableEnv -Value $PortableEnvBackup -Encoding ascii -NoNewline
  } elseif (Test-Path -LiteralPath $PortableEnv) {
    Remove-Item -LiteralPath $PortableEnv -Force
  }
}

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

$NativeCache = Join-Path $StageDir 'data\cache\native-addons'
$NativeBinaries = @(Get-ChildItem -LiteralPath $NativeCache -Filter '*.node' -File -Recurse -ErrorAction SilentlyContinue)
if ($NativeBinaries.Count -eq 0) {
  throw 'portable native addon cache stayed empty after dsh startup'
}

$After = Get-ProfileSnapshot
Assert-NoProfileDrift -Before $Before -After $After
Write-Host '==> profile isolation OK (no %%USERPROFILE%% persistent drift)'
Write-Host '==> smoke passed'
