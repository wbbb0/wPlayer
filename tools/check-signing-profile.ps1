param(
  [switch]$Staged
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$profilePath = Join-Path $repositoryRoot 'build-profile.json5'

if ($Staged) {
  $stagedPaths = @(& git -C $repositoryRoot diff --cached --name-only --diff-filter=ACMR)
  if ($stagedPaths -contains 'signing.local.json') {
    Write-Error 'Legacy signing.local.json must not be committed.'
    exit 1
  }
  $profileLines = & git -C $repositoryRoot show ':build-profile.json5' 2>$null
  if ($LASTEXITCODE -ne 0) {
    throw 'Unable to read staged build-profile.json5. Stage the portable profile before committing.'
  }
  $profileText = $profileLines -join [Environment]::NewLine
} else {
  $trackedLegacySigning = & git -C $repositoryRoot ls-files -- 'signing.local.json'
  if ($trackedLegacySigning) {
    Write-Error 'Legacy signing.local.json must not be tracked.'
    exit 1
  }
  $profileText = Get-Content -LiteralPath $profilePath -Raw
}

$errors = [System.Collections.Generic.List[string]]::new()
$signingConfigBlocks = [regex]::Matches($profileText, '"signingConfigs"\s*:')
if ($signingConfigBlocks.Count -ne 1) {
  $errors.Add('app.signingConfigs must appear exactly once.')
}
if ($profileText -notmatch '"signingConfigs"\s*:\s*\[\s*\]') {
  $errors.Add('app.signingConfigs must be an empty array in Git.')
}
if ($profileText -match '"signingConfig"\s*:') {
  $errors.Add('Product-level signingConfig references must be removed before committing.')
}

$forbiddenKeys = @('storeFile', 'storePassword', 'keyAlias', 'keyPassword', 'profile', 'certpath')
foreach ($key in $forbiddenKeys) {
  if ($profileText -match ('"' + [regex]::Escape($key) + '"\s*:')) {
    $errors.Add("Signing material key '$key' must not be committed.")
  }
}

if ($errors.Count -gt 0) {
  Write-Error ("Signing profile check failed:`n- " + ($errors -join "`n- "))
  exit 1
}

$source = if ($Staged) { 'staged build-profile.json5' } else { 'build-profile.json5' }
Write-Host "Signing profile check passed for $source."
