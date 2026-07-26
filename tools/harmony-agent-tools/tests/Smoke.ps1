[CmdletBinding()]
param()

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

$toolRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $toolRoot '..\..'))
$cli = Join-Path $toolRoot 'hdc-agent.cmd'

function Assert-True {
  param(
    [bool]$Condition,
    [string]$Message
  )

  if (-not $Condition) {
    throw $Message
  }
}

function Invoke-CliJson {
  param(
    [string[]]$Arguments
  )

  $output = @(& $cli @Arguments 2>&1)
  if ($LASTEXITCODE -ne 0) {
    throw "CLI failed: $($Arguments -join ' ')`n$($output -join [Environment]::NewLine)"
  }
  return ($output -join [Environment]::NewLine) | ConvertFrom-Json
}

$tap = Invoke-CliJson @('tap', '-X', '100', '-Y', '200', '-DryRun')
Assert-True ($tap.action -eq 'tap' -and $tap.command.dryRun) 'tap dry-run failed.'

$emulatorTap = Invoke-CliJson @(
  'tap', '-EmulatorName', 'Pura 90', '-X', '100', '-Y', '200', '-DryRun'
)
Assert-True ($emulatorTap.target -eq '<emulator:Pura 90>' -and $emulatorTap.command.dryRun) `
  'emulator-name dry-run selection failed.'

$swipe = Invoke-CliJson @(
  'swipe', '-StartX', '100', '-StartY', '400', '-EndX', '100', '-EndY', '200',
  '-DurationMs', '350', '-DryRun'
)
Assert-True ($swipe.action -eq 'swipe' -and $swipe.command.dryRun) 'swipe dry-run failed.'

$screenshot = Invoke-CliJson @(
  'screenshot', '-OutputPath', (Join-Path $toolRoot 'artifacts\smoke.jpeg'), '-DelayMs', '25',
  '-DryRun'
)
Assert-True ($screenshot.action -eq 'screenshot' -and $screenshot.dryRun) `
  'screenshot dry-run failed.'

$gesture = Invoke-CliJson @(
  'gesture-capture', '-StartX', '100', '-StartY', '500', '-EndX', '100', '-EndY', '200',
  '-DurationMs', '500', '-CaptureAtMs', '0,120,300',
  '-OutputDirectory', (Join-Path $toolRoot 'artifacts\smoke'), '-DryRun'
)
Assert-True ($gesture.action -eq 'gestureCapture' -and $gesture.captures.Count -eq 3) `
  'gesture-capture CSV time-point parsing failed.'

$build = Invoke-CliJson @(
  'build', '-ProjectRoot', $repositoryRoot, '-Product', 'default', '-BuildMode', 'debug',
  '-DryRun'
)
Assert-True ($build.action -eq 'build' -and $build.command.dryRun) 'build dry-run failed.'

$packages = Invoke-CliJson @('packages', '-ProjectRoot', $repositoryRoot)
Assert-True ($packages.Count -gt 0 -and $packages[0].path -match '\.hap$') `
  'package discovery failed.'

$package = Join-Path $repositoryRoot 'entry\build\default\outputs\default\entry-default-signed.hap'
$install = Invoke-CliJson @('install', '-PackagePath', $package, '-DryRun')
Assert-True ($install.action -eq 'install' -and $install.command.dryRun) 'install dry-run failed.'

$start = Invoke-CliJson @(
  'start', '-Bundle', 'com.example.app', '-Ability', 'EntryAbility', '-DebugLaunch', '-DryRun'
)
Assert-True ($start.action -eq 'start' -and $start.debugLaunch -and $start.command.dryRun) `
  'debug start dry-run failed.'

$stop = Invoke-CliJson @('stop', '-Bundle', 'com.example.app', '-DryRun')
Assert-True ($stop.action -eq 'stop' -and $stop.command.dryRun) 'stop dry-run failed.'

$logs = Invoke-CliJson @(
  'logs', '-Bundle', 'com.example.app', '-Level', 'E', '-Tail', '20', '-DryRun'
)
Assert-True ($logs.action -eq 'logs' -and $logs.tail -eq 20 -and $logs.command.dryRun) `
  'logs dry-run failed.'

$deploy = Invoke-CliJson @(
  'deploy', '-ProjectRoot', $repositoryRoot, '-PackagePath', $package,
  '-Bundle', 'com.example.app', '-Ability', 'EntryAbility', '-SkipBuild', '-DryRun'
)
Assert-True ($deploy.action -eq 'deploy' -and $deploy.dryRun) 'deploy dry-run failed.'

$example = Join-Path $toolRoot 'examples\tap-and-capture.json'
$validation = Invoke-CliJson @('scenario', '-ScenarioPath', $example, '-ValidateOnly')
Assert-True ($validation.valid -and $validation.stepCount -eq 4) 'scenario validation failed.'

$scenario = Invoke-CliJson @(
  'scenario', '-ScenarioPath', $example,
  '-OutputDirectory', (Join-Path $toolRoot 'artifacts\scenario-smoke'), '-DryRun'
)
Assert-True ($scenario.action -eq 'scenario' -and $scenario.events.Count -eq 4) `
  'scenario dry-run failed.'

$previousErrorActionPreference = $ErrorActionPreference
try {
  $ErrorActionPreference = 'Continue'
  $invalidOutput = @(
    & $cli screenshot -OutputPath (Join-Path $toolRoot 'artifacts\invalid.png') -DryRun 2>&1
  )
  $invalidExitCode = $LASTEXITCODE
} finally {
  $ErrorActionPreference = $previousErrorActionPreference
}
Assert-True ($invalidExitCode -ne 0) 'PNG output should have been rejected.'
Assert-True (($invalidOutput -join [Environment]::NewLine) -match '\.jpg or \.jpeg') `
  'PNG rejection did not explain the supported extensions.'

[pscustomobject]@{
  result = 'PASS'
  checks = 15
  deviceRequired = $false
} | ConvertTo-Json
