# Exercise the production patcher without running downloads or the build.
$ErrorActionPreference = 'Stop'
$tokens = $null
$parseErrors = $null
foreach ($source in @(
  @{ File = 'build-windows.ps1'; Function = 'Set-BundledPresetShells' },
  @{ File = 'smoke-windows.ps1'; Function = 'Assert-ShellOverlay' }
)) {
  $ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot $source.File), [ref]$tokens, [ref]$parseErrors)
  if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
  $function = $ast.Find({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
      $node.Name -eq $source.Function
  }, $false)
  if (-not $function) { throw "$($source.Function) not found" }
  . ([scriptblock]::Create($function.Extent.Text))
}

# Small declarative compositions retain the upstream shell rows and nesting.
$regular = @'
- insert:
    - id: preset-PRESET
      name: '@deepseek-ai/dsh-agent-preset'
      config:
        id: PRESET
        order: 1
        plugins:
          - id: tool-bash
            name: '@deepseek-ai/dsh-tool-bash'
            disabled: !!js process.platform === 'win32'
          - id: tool-pwsh
            name: '@deepseek-ai/dsh-tool-pwsh'
            disabled: !!js process.platform !== 'win32'
          - id: other-plugin
            name: '@example/unchanged'
            disabled: true
'@
$minimal = @'
- insert:
    - id: preset-minimal
      name: '@deepseek-ai/dsh-agent-preset'
      config:
        id: minimal
        order: 3
        plugins:
          - id: persistent-shell
            name: cordis:group
            group: true
            isolate:
              terminals: true
            config:
              - id: terminal-bash
                name: '@deepseek-ai/dsh-terminal-bash'
                disabled: !!js process.platform === 'win32'
                config:
                  timeoutMs: 300000
              - id: persistent-bash
                name: '@deepseek-ai/dsh-tool-bash-persistent'
                disabled: !!js process.platform === 'win32'
              - id: terminal-pwsh
                name: '@deepseek-ai/dsh-terminal-bash'
                disabled: !!js process.platform !== 'win32'
                config:
                  shellDialect: pwsh
                  timeoutMs: 300000
              - id: persistent-pwsh
                name: '@deepseek-ai/dsh-tool-pwsh-persistent'
                disabled: !!js process.platform !== 'win32'
'@
$utf8 = New-Object System.Text.UTF8Encoding $false
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('dsh-preset-test-' + [guid]::NewGuid().ToString('N'))
$presets = Join-Path $testRoot 'node_modules\@deepseek-ai\dsh-web-app\presets'
New-Item -ItemType Directory -Path $presets -Force | Out-Null
try {
  foreach ($case in @('LF', 'CRLF', 'missing file', 'missing gate', 'duplicate gate', 'changed config')) {
    $newline = if ($case -eq 'CRLF') { "`r`n" } else { "`n" }
    $originals = @{}
    foreach ($id in @('standard', 'ptc', 'minimal', 'cordis')) {
      $text = if ($id -eq 'minimal') { $minimal } else { $regular.Replace('PRESET', $id) }
      $text = ($text -replace "`r`n", "`n").Replace("`n", $newline) + $newline
      $originals[$id] = $text
      [IO.File]::WriteAllText((Join-Path $presets "$id.patch.yml"), $text, $utf8)
    }
    $file = Join-Path $presets 'standard.patch.yml'
    $node = 'tool-bash'
    switch ($case) {
      'missing file' { Remove-Item -LiteralPath $file }
      'missing gate' {
        [IO.File]::WriteAllText($file, $originals.standard.Replace("process.platform === 'win32'", 'true'), $utf8)
      }
      'duplicate gate' { [IO.File]::WriteAllText($file, ($originals.standard + $originals.standard), $utf8) }
      'changed config' {
        $file = Join-Path $presets 'minimal.patch.yml'
        $node = 'terminal-bash'
        [IO.File]::WriteAllText($file, $originals.minimal.Replace('timeoutMs:', 'unknown:'), $utf8)
      }
    }
    $failure = $null
    try { Set-BundledPresetShells -AppDir $testRoot -Version '0.1.7-alpha.2' }
    catch { $failure = $_.Exception.Message }
    if ($case -notin @('LF', 'CRLF')) {
      if (-not $failure -or -not $failure.Contains('0.1.7-alpha.2') -or -not $failure.Contains($file) -or
          ($case -ne 'missing file' -and -not $failure.Contains($node))) {
        throw "${case}: expected a version/file/node diagnostic, got: $failure"
      }
    } else {
      if ($failure) { throw $failure }
      foreach ($id in $originals.Keys) {
        $actual = [IO.File]::ReadAllText((Join-Path $presets "$id.patch.yml"))
        $gates = if ($id -eq 'minimal') { 2 } else { 1 }
        foreach ($condition in @("process.env.DSH_SHELL !== 'bash'", "process.env.DSH_SHELL === 'bash'")) {
          if ([regex]::Matches($actual, [regex]::Escape($condition)).Count -ne $gates) {
            throw "${case}/${id}: incorrect shell gates"
          }
        }
        if ($id -eq 'minimal') {
          $shellPath = "                  shellPath: !!js process.env.DSH_PORTABLE_ROOT + '/runtime/git/usr/bin/bash.exe'$newline"
          if (-not $actual.Contains($shellPath + '                  timeoutMs: 300000')) {
            throw "${case}: Bash shellPath must preserve nesting and timeout"
          }
          $actual = $actual.Replace($shellPath, '')
        }
        # Reverse only the permitted changes; all other bytes must be identical.
        $actual = $actual.Replace("process.env.DSH_SHELL !== 'bash'", "process.platform === 'win32'").
          Replace("process.env.DSH_SHELL === 'bash'", "process.platform !== 'win32'")
        if ($actual -cne $originals[$id]) { throw "${case}/${id}: unrelated content changed" }
      }
    }
    Write-Host "    ${case}: OK"
  }
} finally {
  $resolved = (Resolve-Path -LiteralPath $testRoot).Path
  $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
  if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "test cleanup escaped TEMP: $resolved"
  }
  Remove-Item -LiteralPath $resolved -Recurse -Force
}
Write-Host '==> bundled preset tests passed'

$defaultDump = @'
- id: bash-sandbox
  name: '@deepseek-ai/dsh-bash-sandbox'
  disabled: !!js process.platform === 'win32'
- id: pwsh-sandbox
  name: '@deepseek-ai/dsh-pwsh-sandbox'
  disabled: !!js process.platform !== 'win32'
'@
# Preset-level DSH_SHELL must not count as an injected host overlay.
$defaultDump += "`n" + $regular.Replace("process.platform === 'win32'", "process.env.DSH_SHELL !== 'bash'")
$overlayDump = $defaultDump.Replace("process.platform === 'win32'", "process.env.DSH_SHELL !== 'bash'").
  Replace("process.platform !== 'win32'", "process.env.DSH_SHELL === 'bash'")
Assert-ShellOverlay $defaultDump $false
Assert-ShellOverlay $overlayDump $true
foreach ($case in @(
  @{ Text = $defaultDump; Expected = $true },
  @{ Text = $overlayDump; Expected = $false },
  @{ Text = $regular; Expected = $false },
  @{ Text = $overlayDump.Replace("process.env.DSH_SHELL === 'bash'", 'true'); Expected = $true }
)) {
  $rejected = $false
  try { Assert-ShellOverlay $case.Text $case.Expected } catch { $rejected = $true }
  if (-not $rejected) { throw 'incorrect or missing host shell gates must fail' }
}
Write-Host '==> host overlay tests passed (2 valid, 4 rejected)'
