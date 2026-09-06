# Exercise the real resolver with in-memory release responses; no GitHub requests.
$ErrorActionPreference = 'Stop'

function Invoke-RestMethod {
  param($Uri, $Headers)
  if ($Uri -match '/releases\?') {
    return @(
      [pscustomobject]@{ tag_name = 'dsh-v2.0.0' },
      [pscustomobject]@{ tag_name = 'dsh-v1.0.0' }
    )
  }
  return [pscustomobject]@{
    assets = @($case.Assets | ForEach-Object { [pscustomobject]@{ name = $_ } })
  }
}

foreach ($case in @(
  @{ Name = 'empty'; Assets = @(); Pending = $true },
  @{ Name = 'ZIP only'; Assets = @('dsh-portable-2.0.0-win-x64.zip'); Pending = $true },
  @{ Name = 'checksum only'; Assets = @('SHA256SUMS.txt'); Pending = $true },
  @{ Name = 'older ZIP'; Assets = @('dsh-portable-1.0.0-win-x64.zip', 'SHA256SUMS.txt'); Pending = $true },
  @{ Name = 'complete'; Assets = @('dsh-portable-2.0.0-win-x64.zip', 'SHA256SUMS.txt'); Pending = $false }
)) {
  $json = & (Join-Path $PSScriptRoot 'resolve-upstream.ps1') -ThisRepo 'test/portable' -Json
  $result = $json | ConvertFrom-Json
  if ($case.Pending) {
    if ($result.version -ne '2.0.0') { throw "$($case.Name): expected latest version to remain pending" }
  } elseif ($json -ne '[]') {
    throw "$($case.Name): expected no pending release"
  }
  Write-Host "    $($case.Name): OK"
}
Write-Host '==> resolver tests passed'
