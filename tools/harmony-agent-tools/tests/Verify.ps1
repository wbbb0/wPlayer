[CmdletBinding()]
param(
  [string]$NodePath = 'node',
  [string]$EmulatorName = ''
)

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

$toolRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$parseErrors = @()
Get-ChildItem -LiteralPath $toolRoot -Recurse -File |
  Where-Object {
    $_.Extension -in @('.ps1', '.psm1') -and
    $_.FullName -notmatch '[\\/](node_modules|artifacts)[\\/]'
  } |
  ForEach-Object {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
      $_.FullName,
      [ref]$tokens,
      [ref]$errors
    )
    $parseErrors += @($errors)
  }
if ($parseErrors.Count -gt 0) {
  $messages = @($parseErrors | ForEach-Object {
    "$($_.Extent.File):$($_.Extent.StartLineNumber): $($_.Message)"
  })
  throw "PowerShell parse validation failed:`n$($messages -join [Environment]::NewLine)"
}

& $NodePath (Join-Path $PSScriptRoot 'validate-json.mjs') $toolRoot
if ($LASTEXITCODE -ne 0) {
  throw 'JSON validation failed.'
}

& (Join-Path $PSScriptRoot 'Smoke.ps1')
& $NodePath --check (Join-Path $toolRoot 'mcp\server.mjs')
if ($LASTEXITCODE -ne 0) {
  throw 'MCP syntax check failed.'
}
& $NodePath (Join-Path $toolRoot 'mcp\smoke.mjs')
if ($LASTEXITCODE -ne 0) {
  throw 'MCP smoke test failed.'
}

$deviceChecked = $false
if ($EmulatorName.Length -gt 0) {
  & $NodePath (Join-Path $toolRoot 'mcp\device-integration.mjs') $EmulatorName
  if ($LASTEXITCODE -ne 0) {
    throw 'MCP device integration test failed.'
  }
  $deviceChecked = $true
}

[pscustomobject]@{
  result = 'PASS'
  powershellParsed = $true
  jsonParsed = $true
  smokePassed = $true
  mcpPassed = $true
  deviceChecked = $deviceChecked
  emulatorName = if ($deviceChecked) { $EmulatorName } else { $null }
} | ConvertTo-Json
