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

$normalizedTap = Invoke-CliJson @(
  'tap', '-XRatio', '0.5', '-YRatio', '0.5',
  '-DisplayWidth', '1320', '-DisplayHeight', '2856', '-DryRun'
)
Assert-True ($normalizedTap.x -eq 660 -and $normalizedTap.y -eq 1428) `
  'normalized tap conversion failed.'

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

$normalizedSwipe = Invoke-CliJson @(
  'swipe', '-StartXRatio', '0.25', '-StartYRatio', '0.75',
  '-EndXRatio', '0.75', '-EndYRatio', '0.25',
  '-DisplayWidth', '1320', '-DisplayHeight', '2856', '-DryRun'
)
Assert-True ($normalizedSwipe.start.x -eq 330 -and $normalizedSwipe.end.x -eq 989) `
  'normalized swipe conversion failed.'

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

$localTest = Invoke-CliJson @('test-local', '-ProjectRoot', $repositoryRoot, '-DryRun')
Assert-True ($localTest.action -eq 'localTest' -and $localTest.command.dryRun) `
  'local test dry-run failed.'

$deviceTest = Invoke-CliJson @(
  'test-device', '-ProjectRoot', $repositoryRoot, '-Bundle', 'com.example.app',
  '-SkipBuild', '-DryRun'
)
Assert-True ($deviceTest.action -eq 'deviceTest' -and $deviceTest.test.dryRun) `
  'device test dry-run failed.'

$example = Join-Path $toolRoot 'examples\tap-and-capture.json'
$validation = Invoke-CliJson @('scenario', '-ScenarioPath', $example, '-ValidateOnly')
Assert-True ($validation.valid -and $validation.stepCount -eq 4) 'scenario validation failed.'

$scenario = Invoke-CliJson @(
  'scenario', '-ScenarioPath', $example,
  '-OutputDirectory', (Join-Path $toolRoot 'artifacts\scenario-smoke'), '-DryRun'
)
Assert-True ($scenario.action -eq 'scenario' -and $scenario.events.Count -eq 4) `
  'scenario dry-run failed.'

$normalizedExample = Join-Path $toolRoot 'examples\normalized-coordinates.json'
$normalizedScenario = Invoke-CliJson @(
  'scenario', '-ScenarioPath', $normalizedExample,
  '-OutputDirectory', (Join-Path $toolRoot 'artifacts\normalized-smoke'), '-DryRun'
)
Assert-True (
  $normalizedScenario.events[0].result.x -eq 660 -and
  $normalizedScenario.events[1].result.end.x -eq 989
) 'normalized scenario dry-run failed.'

Add-Type -AssemblyName System.Drawing
$imageDirectory = Join-Path $toolRoot 'artifacts\image-smoke'
[void](New-Item -ItemType Directory -Path $imageDirectory -Force)
$baselinePath = Join-Path $imageDirectory 'baseline.png'
$actualPath = Join-Path $imageDirectory 'actual.png'
$cropPath = Join-Path $imageDirectory 'crop.png'
$differencePath = Join-Path $imageDirectory 'difference.png'
$bitmap = New-Object System.Drawing.Bitmap(8, 8)
try {
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  try {
    $graphics.Clear([System.Drawing.Color]::Black)
  } finally {
    $graphics.Dispose()
  }
  $bitmap.Save($baselinePath, [System.Drawing.Imaging.ImageFormat]::Png)
  $bitmap.Save($actualPath, [System.Drawing.Imaging.ImageFormat]::Png)
} finally {
  $bitmap.Dispose()
}

$imageInfo = Invoke-CliJson @('image-info', '-ImagePath', $baselinePath)
Assert-True ($imageInfo.width -eq 8 -and $imageInfo.height -eq 8) 'image info failed.'

$crop = Invoke-CliJson @(
  'crop-image', '-ImagePath', $baselinePath, '-OutputPath', $cropPath,
  '-CropX', '2', '-CropY', '2', '-CropWidth', '4', '-CropHeight', '4'
)
Assert-True ($crop.rectangle.width -eq 4 -and (Test-Path -LiteralPath $crop.path)) `
  'image crop failed.'

$comparison = Invoke-CliJson @(
  'compare-images', '-BaselinePath', $baselinePath, '-ActualPath', $actualPath,
  '-DifferencePath', $differencePath
)
Assert-True ($comparison.passed -and $comparison.metrics.differentPixels -eq 0) `
  'identical image comparison failed.'

$assertion = Invoke-CliJson @(
  'assert-image', '-BaselinePath', $baselinePath, '-ActualPath', $actualPath
)
Assert-True ($assertion.passed -and $assertion.action -eq 'assertImage') `
  'image assertion failed.'

$changedBitmap = New-Object System.Drawing.Bitmap(8, 8)
try {
  $changedGraphics = [System.Drawing.Graphics]::FromImage($changedBitmap)
  try {
    $changedGraphics.Clear([System.Drawing.Color]::Black)
  } finally {
    $changedGraphics.Dispose()
  }
  $changedBitmap.SetPixel(3, 3, [System.Drawing.Color]::White)
  $changedBitmap.Save($actualPath, [System.Drawing.Imaging.ImageFormat]::Png)
} finally {
  $changedBitmap.Dispose()
}
$changedComparison = Invoke-CliJson @(
  'compare-images', '-BaselinePath', $baselinePath, '-ActualPath', $actualPath,
  '-DifferencePath', $differencePath
)
Assert-True (
  -not $changedComparison.passed -and
  $changedComparison.metrics.differentPixels -eq 1 -and
  (Test-Path -LiteralPath $changedComparison.difference)
) 'changed pixel comparison failed.'

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
  checks = 25
  deviceRequired = $false
} | ConvertTo-Json
