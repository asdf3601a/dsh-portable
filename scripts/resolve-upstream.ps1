# Resolve upstream deepseek-harness dsh-v* release tags that are not yet
# published as a portable ZIP in this repository.
# Packaging clones the Git tag and runs official release:pack (npm optional).
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

function Get-GitHubHeaders {
  $headers = @{
    'User-Agent' = 'dsh-portable-resolver'
    'Accept'     = 'application/vnd.github+json'
  }
  if ($env:GH_TOKEN) { $headers['Authorization'] = "Bearer $($env:GH_TOKEN)" }
  elseif ($env:GITHUB_TOKEN) { $headers['Authorization'] = "Bearer $($env:GITHUB_TOKEN)" }
  return $headers
}

function Get-PublishedPortableVersions([string]$Repo) {
  $published = New-Object 'System.Collections.Generic.HashSet[string]'
  if ($Repo -eq 'local/dsh-portable') {
    # Unary comma prevents PowerShell from enumerating an empty HashSet to $null.
    return , $published
  }
  try {
    $url = "https://api.github.com/repos/$Repo/releases?per_page=50"
    $releases = @(Invoke-RestMethod -Uri $url -Headers (Get-GitHubHeaders))
  } catch {
    Write-Warning "could not list releases for $Repo : $_"
    return , $published
  }
  foreach ($rel in $releases) {
    if ($null -eq $rel) { continue }
    foreach ($asset in @($rel.assets)) {
      if ($asset.name -match '^dsh-portable-(.+)-win-x64\.zip$') {
        [void]$published.Add($Matches[1])
      }
    }
  }
  return , $published
}

Write-Host "==> scanning upstream releases: $UpstreamRepo"
$upstreamUrl = "https://api.github.com/repos/$UpstreamRepo/releases?per_page=$PerPage"
$raw = Invoke-RestMethod -Uri $upstreamUrl -Headers (Get-GitHubHeaders)
# Copy into an explicit list so foreach never sees a nested Object[].
$upstream = New-Object System.Collections.Generic.List[object]
if ($raw -is [System.Array]) {
  foreach ($item in $raw) { [void]$upstream.Add($item) }
} elseif ($null -ne $raw) {
  [void]$upstream.Add($raw)
}
$published = Get-PublishedPortableVersions $ThisRepo

$pending = New-Object System.Collections.Generic.List[object]

# Oldest-first; ISO-8601 strings sort lexicographically.
$indices = 0..($upstream.Count - 1) | Sort-Object {
  $rel = $upstream[$_]
  $stamp = [string]$rel.published_at
  if (-not $stamp) { $stamp = [string]$rel.created_at }
  $stamp
}

foreach ($i in $indices) {
  $rel = $upstream[$i]
  if ($null -eq $rel) { continue }
  $tag = [string]$rel.tag_name
  if (-not $tag -or $tag -notmatch '^dsh-v(.+)$') { continue }
  $ver = [string]$Matches[1]
  if ($published.Contains($ver)) {
    Write-Host "    skip $tag (already published here)"
    continue
  }
  Write-Host "    pending $tag"
  [void]$pending.Add([pscustomobject]@{
    tag          = $tag
    version      = $ver
    html_url     = [string]$rel.html_url
    published_at = [string]$rel.published_at
  })
}

if ($Json) {
  ConvertTo-Json -InputObject $pending.ToArray() -Compress -Depth 5
  return
}

if ($pending.Count -eq 0) {
  Write-Host '==> nothing to publish'
  if ($env:GITHUB_OUTPUT) {
    "has_pending=false" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
    'versions_json=[]' | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
  }
  return
}

$versionList = [string[]]@($pending | ForEach-Object { $_.version })
$versionsCsv = $versionList -join ','
$versionsJson = ConvertTo-Json -InputObject $versionList -Compress
Write-Host "==> pending versions: $versionsCsv"
if ($env:GITHUB_OUTPUT) {
  "has_pending=true" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
  "versions_json=$versionsJson" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
}

$versionList
