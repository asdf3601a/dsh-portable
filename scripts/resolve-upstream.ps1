# Resolve upstream deepseek-harness dsh-v* release tags that are on npm
# and not yet published as a portable ZIP in this repository.
[CmdletBinding()]
param(
  [string]$UpstreamRepo = 'deepseek-ai/deepseek-harness',
  [string]$ThisRepo = '',
  [int]$PerPage = 20,
  [switch]$Json
)

$ErrorActionPreference = 'Stop'

if (-not $ThisRepo) {
  if ($env:GITHUB_REPOSITORY) { $ThisRepo = $env:GITHUB_REPOSITORY }
  else { $ThisRepo = 'local/dsh-portable' }
}

function Invoke-GhApi([string]$Path) {
  if (Get-Command gh -ErrorAction SilentlyContinue) {
    $out = & gh api $Path
    if ($LASTEXITCODE -ne 0) { throw "gh api $Path failed" }
    return ($out | ConvertFrom-Json)
  }
  $url = "https://api.github.com/$Path"
  return Invoke-RestMethod -Uri $url -Headers @{
    'User-Agent' = 'dsh-portable-resolver'
    'Accept'     = 'application/vnd.github+json'
  }
}

function Test-NpmPackage([string]$Version) {
  try {
    $pkg = Invoke-RestMethod -Uri "https://registry.npmjs.org/@deepseek-ai/dsh/$Version"
    return [bool]$pkg.version
  } catch {
    return $false
  }
}

function Get-PublishedPortableVersions([string]$Repo) {
  $published = New-Object 'System.Collections.Generic.HashSet[string]'
  if ($Repo -eq 'local/dsh-portable') { return $published }
  try {
    $releases = Invoke-GhApi "repos/$Repo/releases?per_page=50"
  } catch {
    Write-Warning "could not list releases for $Repo : $_"
    return $published
  }
  foreach ($rel in $releases) {
    foreach ($asset in @($rel.assets)) {
      if ($asset.name -match '^dsh-portable-(.+)-win-x64\.zip$') {
        [void]$published.Add($Matches[1])
      }
    }
    if ($rel.tag_name -match '^dsh-v(.+)$') {
      [void]$published.Add($Matches[1])
    }
  }
  return $published
}

Write-Host "==> scanning upstream releases: $UpstreamRepo"
$upstream = Invoke-GhApi "repos/$UpstreamRepo/releases?per_page=$PerPage"
$published = Get-PublishedPortableVersions $ThisRepo

$pending = @()
# Process oldest-first among the fetched page so we publish in order.
$ordered = @($upstream | Sort-Object { $_.published_at }, { $_.created_at })

foreach ($rel in $ordered) {
  $tag = [string]$rel.tag_name
  if ($tag -notmatch '^dsh-v(.+)$') { continue }
  $ver = $Matches[1]
  if ($published.Contains($ver)) {
    Write-Host "    skip $tag (already published here)"
    continue
  }
  if (-not (Test-NpmPackage $ver)) {
    Write-Host "    skip $tag (not on npm yet)"
    continue
  }
  Write-Host "    pending $tag -> npm @$ver"
  $pending += [pscustomobject]@{
    tag         = $tag
    version     = $ver
    html_url    = $rel.html_url
    published_at = $rel.published_at
  }
}

if ($Json) {
  $pending | ConvertTo-Json -Compress -Depth 5
  return
}

if ($pending.Count -eq 0) {
  Write-Host '==> nothing to publish'
  if ($env:GITHUB_OUTPUT) {
    "has_pending=false" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
    "versions=" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
    'versions_json=[]' | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
  }
  return
}

$versionList = [string[]]@($pending | ForEach-Object { $_.version })
$versionsCsv = $versionList -join ','
# -InputObject keeps a single-element array as JSON array (no pipe unwrap).
$versionsJson = ConvertTo-Json -InputObject $versionList -Compress
Write-Host "==> pending versions: $versionsCsv"
if ($env:GITHUB_OUTPUT) {
  "has_pending=true" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
  "versions=$versionsCsv" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
  "versions_json=$versionsJson" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
}

# Also emit one version per line for shell loops.
$versionList
