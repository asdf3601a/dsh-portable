# Build a Windows x64 portable ZIP for DeepSeek Harness (dsh).
# Requires: Windows PowerShell 5.1+ or pwsh, git, network access.
[CmdletBinding()]
param(
  [string]$DshVersion = '',
  [string]$NodeVersion = '',
  [string]$PnpmVersion = '',
  # auto: use npm when @deepseek-ai/dsh@ver exists, otherwise clone Git tag + release:pack
  # git: always clone dsh-v<ver> and run official release:pack
  # npm: require registry package
  [ValidateSet('auto', 'git', 'npm')]
  [string]$Source = 'auto'
)

$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot

function Read-VersionsEnv {
  $map = @{}
  Get-Content (Join-Path $Root 'versions.env') | ForEach-Object {
    if ($_ -match '^\s*#' -or $_ -match '^\s*$') { return }
    if ($_ -match '^(\w+)=(.*)$') { $map[$Matches[1]] = $Matches[2].Trim() }
  }
  return $map
}

function Test-NpmDsh([string]$Version) {
  try {
    $pkg = Invoke-RestMethod -Uri "https://registry.npmjs.org/@deepseek-ai/dsh/$Version"
    return [bool]$pkg.version
  } catch {
    return $false
  }
}

function Invoke-Native([string]$FilePath, [string[]]$ArgumentList, [string]$WorkingDirectory = '') {
  Write-Host "    > $FilePath $($ArgumentList -join ' ')"
  if ($WorkingDirectory) {
    Push-Location -LiteralPath $WorkingDirectory
    try {
      & $FilePath @ArgumentList
      $code = $LASTEXITCODE
    } finally {
      Pop-Location
    }
  } else {
    & $FilePath @ArgumentList
    $code = $LASTEXITCODE
  }
  if ($null -eq $code) { $code = 0 }
  if ($code -ne 0) {
    throw "$FilePath exited with code $code"
  }
}

function Copy-CmdAsciiCrlf([string]$From, [string]$To) {
  $text = [System.IO.File]::ReadAllText($From)
  $text = $text -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllBytes($To, [System.Text.Encoding]::ASCII.GetBytes($text))
}

function Install-PnpmPayload([string]$Version, [string]$WorkDir, [string]$DestDir) {
  Write-Host "==> downloading pnpm $Version win32-x64"
  New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
  $PnpmZip = Join-Path $WorkDir 'pnpm.zip'
  $PnpmUrl = "https://github.com/pnpm/pnpm/releases/download/v$Version/pnpm-win32-x64.zip"
  Invoke-WebRequest -Uri $PnpmUrl -OutFile $PnpmZip -UseBasicParsing
  $PnpmExtract = Join-Path $WorkDir 'pnpm-extract'
  if (Test-Path $PnpmExtract) { Remove-Item -Recurse -Force $PnpmExtract }
  Expand-Archive -Path $PnpmZip -DestinationPath $PnpmExtract -Force
  $PnpmExeSrc = Get-ChildItem -Path $PnpmExtract -Recurse -Filter 'pnpm.exe' | Select-Object -First 1
  if (-not $PnpmExeSrc) { throw "pnpm.exe not found inside $PnpmUrl" }
  $PnpmPayloadRoot = $PnpmExeSrc.Directory.FullName
  if (Test-Path $DestDir) { Remove-Item -Recurse -Force $DestDir }
  New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
  Copy-Item -Path (Join-Path $PnpmPayloadRoot '*') -Destination $DestDir -Recurse -Force
  if (-not (Test-Path (Join-Path $DestDir 'pnpm.exe'))) { throw 'pnpm.exe missing after extract copy' }
  if (-not (Test-Path (Join-Path $DestDir 'dist\pnpm.mjs'))) { throw 'dist\pnpm.mjs missing after extract copy' }
}

function Install-DshFromNpm([string]$Version, [string]$NpmCmd, [string]$AppDir) {
  Write-Host "==> npm install @deepseek-ai/dsh@$Version (registry)"
  New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
  & $NpmCmd install --prefix $AppDir --no-fund --no-audit --loglevel=error --foreground-scripts "@deepseek-ai/dsh@$Version"
  if ($LASTEXITCODE -ne 0) { throw "npm install failed with exit code $LASTEXITCODE" }
}

function Get-ScopedNameFromTarball([string]$FileName) {
  # pnpm pack names @deepseek-ai/foo as deepseek-ai-foo-<version>.tgz
  $base = [IO.Path]::GetFileNameWithoutExtension($FileName)
  if ($base -notmatch '^(deepseek-ai-.+)-(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)$') {
    throw "cannot parse tarball filename: $FileName"
  }
  $unscoped = $Matches[1]
  if ($unscoped -notmatch '^deepseek-ai-(.+)$') {
    throw "unexpected unscoped package stem: $unscoped"
  }
  return ('@deepseek-ai/' + $Matches[1])
}

function Install-DshFromGitTag {
  param(
    [string]$Version,
    [string]$WorkDir,
    [string]$AppDir,
    [string]$NodeExe,
    [string]$NpmCmd,
    [string]$PnpmExe,
    [string]$RuntimeNode
  )

  $Tag = "dsh-v$Version"
  $UpstreamDir = Join-Path $WorkDir 'upstream'
  $PackDsh = Join-Path $UpstreamDir 'dist\npm-dsh'
  $PackVendor = Join-Path $UpstreamDir 'dist\npm-vendor'

  $dshMarker = Join-Path $PackDsh "deepseek-ai-dsh-$Version.tgz"
  $havePacks = (Test-Path $dshMarker) -and (Test-Path $PackVendor) -and (@(Get-ChildItem $PackVendor -Filter '*.tgz' -ErrorAction SilentlyContinue).Count -gt 0)

  if (-not $havePacks) {
    if (Test-Path $UpstreamDir) { Remove-Item -Recurse -Force $UpstreamDir }

    Write-Host "==> cloning deepseek-ai/deepseek-harness @$Tag"
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
      throw 'git is required to package from an upstream tag'
    }
    try { & git config --system core.longpaths true 2>$null } catch { }

    Invoke-Native -FilePath 'git' -ArgumentList @(
      'clone', '--depth', '1', '--branch', $Tag,
      'https://github.com/deepseek-ai/deepseek-harness.git',
      $UpstreamDir
    )

    $env:PATH = "$RuntimeNode;$(Split-Path $PnpmExe -Parent);$env:PATH"
    if (-not $env:NODE_OPTIONS) { $env:NODE_OPTIONS = '--max-old-space-size=8192' }

    Write-Host '==> pnpm install (upstream monorepo)'
    Invoke-Native -FilePath $PnpmExe -ArgumentList @('install', '--frozen-lockfile') -WorkingDirectory $UpstreamDir

    Write-Host '==> pnpm run build:official'
    Invoke-Native -FilePath $PnpmExe -ArgumentList @('run', 'build:official') -WorkingDirectory $UpstreamDir

    Write-Host '==> release:pack family dsh'
    Invoke-Native -FilePath $PnpmExe -ArgumentList @(
      'exec', 'tsx', 'scripts/release/pack.ts', '--family', 'dsh', '--out', 'dist/npm-dsh'
    ) -WorkingDirectory $UpstreamDir

    Write-Host '==> release:pack family vendor'
    Invoke-Native -FilePath $PnpmExe -ArgumentList @(
      'exec', 'tsx', 'scripts/release/pack.ts', '--family', 'vendor', '--out', 'dist/npm-vendor'
    ) -WorkingDirectory $UpstreamDir
  } else {
    Write-Host "==> reusing existing release:pack output under $UpstreamDir"
  }

  # Mirror official verify-packed-install: one consumer package.json with file: tarballs.
  # Parse names from filenames (avoid reading UTF-8 package.json via Windows tar/encoding).
  Write-Host '==> npm install packed tarballs into portable app/'
  New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
  $deps = @{}
  foreach ($dir in @($PackDsh, $PackVendor)) {
    Get-ChildItem -LiteralPath $dir -Filter '*.tgz' | ForEach-Object {
      $pkgName = Get-ScopedNameFromTarball $_.Name
      $fileUrl = 'file:///' + ($_.FullName -replace '\\', '/')
      $deps[$pkgName] = $fileUrl
    }
  }
  if (-not $deps.ContainsKey('@deepseek-ai/dsh')) {
    throw '@deepseek-ai/dsh tarball missing from release:pack output'
  }
  Write-Host ("    packed packages: " + $deps.Count)

  $consumerPkg = @{
    name         = 'dsh-portable-app'
    version      = '0.0.0'
    private      = $true
    dependencies = $deps
  } | ConvertTo-Json -Depth 8
  Set-Content -Path (Join-Path $AppDir 'package.json') -Value $consumerPkg -Encoding utf8

  # Prefer prebuilds for native addons (koffi/node-pty).
  # Do NOT use --omit=optional: that drops koffi's platform binary packages
  # (@koromix/koffi-win32-x64). Linux-only optionals (Landlock) are skipped by
  # npm's platform filter without failing the install.
  $env:npm_config_build_from_source = 'false'
  $npmArgs = @(
    'install', '--prefix', $AppDir,
    '--no-fund', '--no-audit', '--package-lock=false',
    '--loglevel=error'
  )
  $attempt = 0
  $ok = $false
  while ($attempt -lt 2 -and -not $ok) {
    $attempt += 1
    Write-Host "    npm install attempt $attempt"
    & $NpmCmd @npmArgs
    if ($LASTEXITCODE -eq 0) { $ok = $true }
    else {
      Write-Host "    npm install failed (exit $LASTEXITCODE); retrying once after brief wait"
      Start-Sleep -Seconds 5
    }
  }
  if (-not $ok) { throw "npm install from packed tarballs failed with exit code $LASTEXITCODE" }
}

# --- resolve versions ---
$ver = Read-VersionsEnv
if (-not $NodeVersion) { $NodeVersion = $ver['NODE_VERSION'] }
if (-not $PnpmVersion) { $PnpmVersion = $ver['PNPM_VERSION'] }
if (-not $DshVersion) {
  if ($env:DSH_VERSION) { $DshVersion = $env:DSH_VERSION }
  else { $DshVersion = $ver['DSH_VERSION_FALLBACK'] }
}
if ($env:DSH_SOURCE) { $Source = $env:DSH_SOURCE }

if (-not $NodeVersion) { throw 'NODE_VERSION is not set' }
if (-not $PnpmVersion) { throw 'PNPM_VERSION is not set' }
if (-not $DshVersion) { throw 'DSH_VERSION is not set' }

$onNpm = Test-NpmDsh $DshVersion
$useNpm = switch ($Source) {
  'npm' { $true }
  'git' { $false }
  default { $onNpm }
}
if ($Source -eq 'npm' -and -not $onNpm) {
  throw "@deepseek-ai/dsh@$DshVersion is not on npm; use -Source git"
}

$Work = Join-Path $Root 'build\win-x64'
$Dist = Join-Path $Root 'dist'
$StageName = 'dsh-portable'
$Stage = Join-Path $Work $StageName
$ZipName = "dsh-portable-$DshVersion-win-x64.zip"
$UpstreamTag = "dsh-v$DshVersion"

Write-Host '==> dsh-portable build'
Write-Host "    DSH_VERSION  = $DshVersion"
Write-Host "    UPSTREAM_TAG = $UpstreamTag"
Write-Host "    NODE_VERSION = $NodeVersion"
Write-Host "    PNPM_VERSION = $PnpmVersion"
Write-Host "    SOURCE       = $Source ($(if ($useNpm) { 'npm registry' } else { 'git tag + release:pack' }))"

# Keep upstream release:pack output when retrying the same DSH version.
$UpstreamKeep = Join-Path $Work 'upstream'
$packMarker = Join-Path $UpstreamKeep "dist\npm-dsh\deepseek-ai-dsh-$DshVersion.tgz"
$preserveUpstream = Test-Path -LiteralPath $packMarker
if (Test-Path $Work) {
  if ($preserveUpstream) {
    Write-Host "==> preserving upstream pack cache for $DshVersion"
    Get-ChildItem -LiteralPath $Work -Force | Where-Object { $_.Name -ne 'upstream' } |
      Remove-Item -Recurse -Force
  } else {
    Remove-Item -Recurse -Force $Work
  }
}
New-Item -ItemType Directory -Force -Path $Work, $Dist, $Stage | Out-Null

# --- Node.js (official zip, SHA-256 verified) ---
$NodeDist = "node-v$NodeVersion-win-x64"
$NodeZip = Join-Path $Work 'node.zip'
$NodeUrl = "https://nodejs.org/dist/v$NodeVersion/$NodeDist.zip"
Write-Host "==> downloading Node $NodeVersion win-x64"
Invoke-WebRequest -Uri $NodeUrl -OutFile $NodeZip -UseBasicParsing

$SumsUrl = "https://nodejs.org/dist/v$NodeVersion/SHASUMS256.txt"
$Sums = (Invoke-WebRequest -Uri $SumsUrl -UseBasicParsing).Content
$Line = ($Sums -split "`n" | Where-Object { $_ -match [regex]::Escape("$NodeDist.zip") } | Select-Object -First 1)
if (-not $Line) { throw "SHA256 line for $NodeDist.zip not found" }
$Expected = (($Line -split '\s+')[0]).ToLowerInvariant()
$Actual = (Get-FileHash -Path $NodeZip -Algorithm SHA256).Hash.ToLowerInvariant()
if ($Actual -ne $Expected) { throw "Node SHA256 mismatch: $Actual != $Expected" }
Write-Host '    SHA256 OK'

Expand-Archive -Path $NodeZip -DestinationPath $Work -Force
$RuntimeNode = Join-Path $Stage 'runtime\node'
New-Item -ItemType Directory -Force -Path (Join-Path $Stage 'runtime') | Out-Null
Move-Item -Path (Join-Path $Work $NodeDist) -Destination $RuntimeNode

$BuildCache = Join-Path $Work 'cache'
New-Item -ItemType Directory -Force -Path `
  (Join-Path $BuildCache 'npm'), `
  (Join-Path $BuildCache 'npm-prefix') | Out-Null
$env:npm_config_cache = Join-Path $BuildCache 'npm'
$env:npm_config_prefix = Join-Path $BuildCache 'npm-prefix'
if (-not $env:NODE_OPTIONS) { $env:NODE_OPTIONS = '--max-old-space-size=8192' }
$env:PATH = "$RuntimeNode;$env:PATH"

$NodeExe = Join-Path $RuntimeNode 'node.exe'
$NpmCmd = Join-Path $RuntimeNode 'npm.cmd'
if (-not (Test-Path $NodeExe)) { throw "node.exe missing after extract: $NodeExe" }

# --- pnpm (needed for git pack and shipped in the portable runtime) ---
$PnpmDir = Join-Path $Stage 'runtime\pnpm'
Install-PnpmPayload -Version $PnpmVersion -WorkDir $Work -DestDir $PnpmDir
$PnpmExe = Join-Path $PnpmDir 'pnpm.exe'
$env:PATH = "$RuntimeNode;$PnpmDir;$env:PATH"

# --- install @deepseek-ai/dsh ---
$AppDir = Join-Path $Stage 'app'
if ($useNpm) {
  Install-DshFromNpm -Version $DshVersion -NpmCmd $NpmCmd -AppDir $AppDir
} else {
  Install-DshFromGitTag -Version $DshVersion -WorkDir $Work -AppDir $AppDir `
    -NodeExe $NodeExe -NpmCmd $NpmCmd -PnpmExe $PnpmExe -RuntimeNode $RuntimeNode
}

$DshBin = Join-Path $AppDir 'node_modules\@deepseek-ai\dsh\lib\bin.js'
if (-not (Test-Path $DshBin)) { throw "dsh entry missing: $DshBin" }

# --- Launchers & docs ---
Write-Host '==> copying launchers and docs'
Copy-CmdAsciiCrlf (Join-Path $Root 'packaging\dsh.cmd') (Join-Path $Stage 'dsh.cmd')
Copy-CmdAsciiCrlf (Join-Path $Root 'packaging\start.cmd') (Join-Path $Stage 'start.cmd')
Copy-Item (Join-Path $Root 'packaging\README.txt') (Join-Path $Stage 'README.txt') -Force
Copy-Item (Join-Path $Root 'packaging\NOTICE.txt') (Join-Path $Stage 'NOTICE.txt') -Force
Copy-Item (Join-Path $Root 'LICENSE') (Join-Path $Stage 'LICENSE') -Force

foreach ($rel in @(
  'data\dsh-home',
  'data\workspace',
  'data\cache\npm',
  'data\cache\npm-prefix',
  'data\cache\pnpm-home',
  'data\cache\pnpm-store'
)) {
  New-Item -ItemType Directory -Force -Path (Join-Path $Stage $rel) | Out-Null
}
Copy-Item (Join-Path $Root 'packaging\npmrc.example') (Join-Path $Stage 'data\npmrc.example') -Force
Copy-Item (Join-Path $Root 'packaging\registry.env.example') (Join-Path $Stage 'data\registry.env.example') -Force
@(
  'data\dsh-home\.keep',
  'data\workspace\.keep',
  'data\cache\npm\.keep',
  'data\cache\pnpm-store\.keep'
) | ForEach-Object {
  Set-Content -Path (Join-Path $Stage $_) -Value '' -Encoding ascii
}

$VersionsJson = @{
  dsh         = $DshVersion
  upstreamTag = $UpstreamTag
  node        = $NodeVersion
  pnpm        = $PnpmVersion
  source      = $(if ($useNpm) { 'npm' } else { 'git-tag' })
  builtAt     = (Get-Date).ToUniversalTime().ToString('o')
  target      = 'win-x64'
} | ConvertTo-Json
Set-Content -Path (Join-Path $Stage 'versions.json') -Value $VersionsJson -Encoding utf8

Write-Host '==> staged dsh --version'
$Got = & cmd /c "`"$(Join-Path $Stage 'dsh.cmd')`" --version"
$Got = ("$Got").Trim()
if ($Got -ne $DshVersion) {
  throw "staged dsh --version returned '$Got', expected '$DshVersion'"
}
Write-Host "    $Got"

$ZipPath = Join-Path $Dist $ZipName
if (Test-Path $ZipPath) { Remove-Item -Force $ZipPath }
Write-Host "==> writing $ZipName"
Push-Location $Work
try {
  & tar -a -c -f $ZipPath $StageName
  if ($LASTEXITCODE -ne 0) { throw "tar zip failed with exit code $LASTEXITCODE" }
} finally {
  Pop-Location
}

$Hash = (Get-FileHash -Path $ZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
$SumsPath = Join-Path $Dist 'SHA256SUMS.txt'
"$Hash  $ZipName" | Set-Content -Path $SumsPath -Encoding ascii
Write-Host '==> done'
Write-Host "    $ZipPath"
Write-Host "    SHA256 $Hash"
Write-Host "    STAGE_DIR=$Stage"

Write-Output "STAGE_DIR=$Stage"
Write-Output "ZIP_PATH=$ZipPath"
Write-Output "DSH_VERSION=$DshVersion"
Write-Output "SOURCE=$(if ($useNpm) { 'npm' } else { 'git-tag' })"
