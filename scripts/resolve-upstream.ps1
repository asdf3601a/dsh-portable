# Resolve the newest upstream deepseek-harness dsh-v* GitHub Release that is
# not yet published as a portable ZIP in this repository.
# Never backfills older tags — one version or none.
# Packaging clones the Git tag and runs official release:pack (npm optional).
[CmdletBinding()]
param(
  [string]$UpstreamRepo = 'deepseek-ai/deepseek-harness',
  [string]$ThisRepo = '',
  [int]$PerPage = 10,
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

function Get-ErrorHttpStatus($ErrorRecord) {
  $ex = $ErrorRecord.Exception
  foreach ($candidate in @(
      $ex.StatusCode,
      $(if ($ex.Response) { $ex.Response.StatusCode }),
      $(if ($ex.InnerException -and $ex.InnerException.Response) { $ex.InnerException.Response.StatusCode })
    )) {
    if ($null -eq $candidate) { continue }
    try { return [int]$candidate } catch { }
  }
  if ($ErrorRecord.Exception.Message -match '\b404\b') { return 404 }
  return 0
}

function Test-PortableAssetPublished([string]$Repo, [string]$Version) {
  if ($Repo -eq 'local/dsh-portable') { return $false }
  $tag = "dsh-v$Version"
  $url = "https://api.github.com/repos/$Repo/releases/tags/$tag"
  try {
    $rel = Invoke-RestMethod -Uri $url -Headers (Get-GitHubHeaders)
  } catch {
    $code = Get-ErrorHttpStatus $_
    if ($code -eq 404) { return $false }
    Write-Warning "could not look up $Repo release $tag : $_"
    return $false
  }
  $requiredAssets = @("dsh-portable-$Version-win-x64.zip", 'SHA256SUMS.txt')
  $assetNames = @($rel.assets | ForEach-Object { $_.name })
  return @($requiredAssets | Where-Object { $_ -notin $assetNames }).Count -eq 0
}

function Write-ResolverResult([bool]$HasPending, [string]$Version, $PendingObj) {
  if ($Json) {
    if ($HasPending -and $null -ne $PendingObj) {
      ConvertTo-Json -InputObject $PendingObj -Compress -Depth 5
    } else {
      '[]'
    }
    return
  }
  if ($env:GITHUB_OUTPUT) {
    if ($HasPending) {
      "has_pending=true" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
      "dsh_version=$Version" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
    } else {
      "has_pending=false" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
      'dsh_version=' | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
    }
  }
  if ($HasPending) { $Version }
}

Write-Host "==> scanning latest upstream releases: $UpstreamRepo"
$upstreamUrl = "https://api.github.com/repos/$UpstreamRepo/releases?per_page=$PerPage"
$raw = Invoke-RestMethod -Uri $upstreamUrl -Headers (Get-GitHubHeaders)
# Copy into an explicit list so foreach never sees a nested Object[].
$upstream = New-Object System.Collections.Generic.List[object]
if ($raw -is [System.Array]) {
  foreach ($item in $raw) { [void]$upstream.Add($item) }
} elseif ($null -ne $raw) {
  [void]$upstream.Add($raw)
}

# GitHub returns newest first. Take the first dsh-v* only; do not paginate.
$latest = $null
$olderOnPage = 0
foreach ($rel in $upstream) {
  if ($null -eq $rel) { continue }
  $tag = [string]$rel.tag_name
  if (-not $tag -or $tag -notmatch '^dsh-v(.+)$') { continue }
  if ($null -eq $latest) {
    $latest = [pscustomobject]@{
      tag          = $tag
      version      = [string]$Matches[1]
      html_url     = [string]$rel.html_url
      published_at = [string]$rel.published_at
    }
    continue
  }
  $olderOnPage += 1
}

if ($null -eq $latest) {
  Write-Host '==> no dsh-v* GitHub Release on the newest page'
  Write-ResolverResult -HasPending $false -Version '' -PendingObj $null
  return
}

Write-Host "==> latest upstream $($latest.tag)"
if ($olderOnPage -gt 0) {
  Write-Host "    ignoring $olderOnPage older dsh-v* tag(s) on this page"
}

if (Test-PortableAssetPublished $ThisRepo $latest.version) {
  Write-Host "    skip $($latest.tag) (already published here)"
  Write-Host '==> nothing to publish'
  Write-ResolverResult -HasPending $false -Version '' -PendingObj $null
  return
}

Write-Host "    will publish $($latest.tag)"
Write-ResolverResult -HasPending $true -Version $latest.version -PendingObj $latest
