# Build a Windows x64 portable ZIP for DeepSeek Harness (dsh).
# Requires: Windows PowerShell 5.1+ or pwsh, network access.
[CmdletBinding()]
param(
  [string]$DshVersion = '',
  [string]$NodeVersion = '',
  [string]$PnpmVersion = ''
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

$ver = Read-VersionsEnv
if (-not $NodeVersion) { $NodeVersion = $ver['NODE_VERSION'] }
if (-not $PnpmVersion) { $PnpmVersion = $ver['PNPM_VERSION'] }
if (-not $DshVersion) {
  if ($env:DSH_VERSION) { $DshVersion = $env:DSH_VERSION }
  else { $DshVersion = $ver['DSH_VERSION_FALLBACK'] }
}

if (-not $NodeVersion) { throw 'NODE_VERSION is not set' }
if (-not $PnpmVersion) { throw 'PNPM_VERSION is not set' }
if (-not $DshVersion) { throw 'DSH_VERSION is not set' }

$Work = Join-Path $Root 'build\win-x64'
$Dist = Join-Path $Root 'dist'
$StageName = 'dsh-portable'
$Stage = Join-Path $Work $StageName
$ZipName = "dsh-portable-$DshVersion-win-x64.zip"

Write-Host "==> dsh-portable build"
Write-Host "    DSH_VERSION  = $DshVersion"
Write-Host "    NODE_VERSION = $NodeVersion"
Write-Host "    PNPM_VERSION = $PnpmVersion"

if (Test-Path $Work) { Remove-Item -Recurse -Force $Work }
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
Write-Host "    SHA256 OK"

Expand-Archive -Path $NodeZip -DestinationPath $Work -Force
$RuntimeNode = Join-Path $Stage 'runtime\node'
New-Item -ItemType Directory -Force -Path (Join-Path $Stage 'runtime') | Out-Null
Move-Item -Path (Join-Path $Work $NodeDist) -Destination $RuntimeNode

# Build-time caches stay under build\ (do not touch the user profile).
$BuildCache = Join-Path $Work 'cache'
New-Item -ItemType Directory -Force -Path `
  (Join-Path $BuildCache 'npm'), `
  (Join-Path $BuildCache 'npm-prefix') | Out-Null
$env:npm_config_cache = Join-Path $BuildCache 'npm'
$env:npm_config_prefix = Join-Path $BuildCache 'npm-prefix'
# @deepseek-ai/dsh pulls a large dependency tree; raise the heap for npm install.
if (-not $env:NODE_OPTIONS) { $env:NODE_OPTIONS = '--max-old-space-size=8192' }
$env:PATH = "$RuntimeNode;$env:PATH"

$NodeExe = Join-Path $RuntimeNode 'node.exe'
$NpmCmd = Join-Path $RuntimeNode 'npm.cmd'
if (-not (Test-Path $NodeExe)) { throw "node.exe missing after extract: $NodeExe" }

# --- @deepseek-ai/dsh ---
Write-Host "==> npm install @deepseek-ai/dsh@$DshVersion"
$AppDir = Join-Path $Stage 'app'
New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
& $NpmCmd install --prefix $AppDir --no-fund --no-audit --loglevel=error --foreground-scripts "@deepseek-ai/dsh@$DshVersion"
if ($LASTEXITCODE -ne 0) { throw "npm install failed with exit code $LASTEXITCODE" }

$DshBin = Join-Path $AppDir 'node_modules\@deepseek-ai\dsh\lib\bin.js'
if (-not (Test-Path $DshBin)) { throw "dsh entry missing: $DshBin" }

# --- pnpm standalone (GitHub releases ship pnpm-win32-x64.zip) ---
Write-Host "==> downloading pnpm $PnpmVersion win32-x64"
$PnpmDir = Join-Path $Stage 'runtime\pnpm'
New-Item -ItemType Directory -Force -Path $PnpmDir | Out-Null
$PnpmZip = Join-Path $Work 'pnpm.zip'
$PnpmUrl = "https://github.com/pnpm/pnpm/releases/download/v$PnpmVersion/pnpm-win32-x64.zip"
Invoke-WebRequest -Uri $PnpmUrl -OutFile $PnpmZip -UseBasicParsing
$PnpmExtract = Join-Path $Work 'pnpm-extract'
if (Test-Path $PnpmExtract) { Remove-Item -Recurse -Force $PnpmExtract }
Expand-Archive -Path $PnpmZip -DestinationPath $PnpmExtract -Force
# The zip contains pnpm.exe + dist\; both are required at runtime.
$PnpmExeSrc = Get-ChildItem -Path $PnpmExtract -Recurse -Filter 'pnpm.exe' | Select-Object -First 1
if (-not $PnpmExeSrc) { throw "pnpm.exe not found inside $PnpmUrl" }
$PnpmPayloadRoot = $PnpmExeSrc.Directory.FullName
if (Test-Path $PnpmDir) { Remove-Item -Recurse -Force $PnpmDir }
New-Item -ItemType Directory -Force -Path $PnpmDir | Out-Null
Copy-Item -Path (Join-Path $PnpmPayloadRoot '*') -Destination $PnpmDir -Recurse -Force
if (-not (Test-Path (Join-Path $PnpmDir 'pnpm.exe'))) { throw 'pnpm.exe missing after extract copy' }
if (-not (Test-Path (Join-Path $PnpmDir 'dist\pnpm.mjs'))) { throw 'dist\pnpm.mjs missing after extract copy' }

# --- Launchers & docs ---
Write-Host "==> copying launchers and docs"
# .cmd files must be ASCII + CRLF so cmd.exe parses them on non-English Windows.
function Copy-CmdAsciiCrlf([string]$From, [string]$To) {
  $text = [System.IO.File]::ReadAllText($From)
  $text = $text -replace "`r`n", "`n" -replace "`n", "`r`n"
  [System.IO.File]::WriteAllBytes($To, [System.Text.Encoding]::ASCII.GetBytes($text))
}
Copy-CmdAsciiCrlf (Join-Path $Root 'packaging\dsh.cmd') (Join-Path $Stage 'dsh.cmd')
Copy-CmdAsciiCrlf (Join-Path $Root 'packaging\start.cmd') (Join-Path $Stage 'start.cmd')
Copy-Item (Join-Path $Root 'packaging\README.txt') (Join-Path $Stage 'README.txt') -Force
Copy-Item (Join-Path $Root 'packaging\NOTICE.txt') (Join-Path $Stage 'NOTICE.txt') -Force
Copy-Item (Join-Path $Root 'LICENSE') (Join-Path $Stage 'LICENSE') -Force

# Empty portable data skeleton (no real credentials/sessions).
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

# Place a keep file so empty dirs survive zip tools that drop empties.
@(
  'data\dsh-home\.keep',
  'data\workspace\.keep',
  'data\cache\npm\.keep',
  'data\cache\pnpm-store\.keep'
) | ForEach-Object {
  Set-Content -Path (Join-Path $Stage $_) -Value '' -Encoding ascii
}

$VersionsJson = @{
  dsh     = $DshVersion
  node    = $NodeVersion
  pnpm    = $PnpmVersion
  builtAt = (Get-Date).ToUniversalTime().ToString('o')
  target  = 'win-x64'
} | ConvertTo-Json
Set-Content -Path (Join-Path $Stage 'versions.json') -Value $VersionsJson -Encoding utf8

# --- Smoke the staged CLI version before zipping ---
Write-Host "==> staged dsh --version"
$Got = & cmd /c "`"$(Join-Path $Stage 'dsh.cmd')`" --version"
$Got = ("$Got").Trim()
if ($Got -ne $DshVersion) {
  throw "staged dsh --version returned '$Got', expected '$DshVersion'"
}
Write-Host "    $Got"

# --- ZIP ---
$ZipPath = Join-Path $Dist $ZipName
if (Test-Path $ZipPath) { Remove-Item -Force $ZipPath }
Write-Host "==> writing $ZipName"
Push-Location $Work
try {
  # tar -a produces a standard zip and preserves empty dirs better than Compress-Archive.
  & tar -a -c -f $ZipPath $StageName
  if ($LASTEXITCODE -ne 0) { throw "tar zip failed with exit code $LASTEXITCODE" }
} finally {
  Pop-Location
}

$Hash = (Get-FileHash -Path $ZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
$SumsPath = Join-Path $Dist 'SHA256SUMS.txt'
"$Hash  $ZipName" | Set-Content -Path $SumsPath -Encoding ascii
Write-Host "==> done"
Write-Host "    $ZipPath"
Write-Host "    SHA256 $Hash"
Write-Host "    STAGE_DIR=$Stage"

# Export for callers / Actions.
Write-Output "STAGE_DIR=$Stage"
Write-Output "ZIP_PATH=$ZipPath"
Write-Output "DSH_VERSION=$DshVersion"
