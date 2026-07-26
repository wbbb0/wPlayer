[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [ValidateSet(
    'targets',
    'emulators',
    'display',
    'doctor',
    'tap',
    'swipe',
    'screenshot',
    'gesture-capture',
    'scenario',
    'image-info',
    'crop-image',
    'compare-images',
    'assert-image',
    'test-local',
    'test-device',
    'build',
    'packages',
    'install',
    'start',
    'stop',
    'logs',
    'deploy'
  )]
  [string]$Command,

  [string]$Target = '',
  [string]$EmulatorName = '',
  [string]$HdcPath = 'hdc',
  [string]$DevEcoCliPath = 'devecocli',

  [int]$X,
  [int]$Y,
  [Nullable[double]]$XRatio,
  [Nullable[double]]$YRatio,
  [int]$PressMs = 100,
  [int]$StartX,
  [int]$StartY,
  [int]$EndX,
  [int]$EndY,
  [Nullable[double]]$StartXRatio,
  [Nullable[double]]$StartYRatio,
  [Nullable[double]]$EndXRatio,
  [Nullable[double]]$EndYRatio,
  [Nullable[int]]$DisplayWidth,
  [Nullable[int]]$DisplayHeight,
  [int]$DurationMs = 300,
  [int]$KeepMs = 0,

  [string]$OutputPath = '',
  [string]$OutputDirectory = '',
  [string]$Prefix = 'gesture',
  [int]$DelayMs = 0,
  [string[]]$CaptureAtMs = @(),
  [string]$ScenarioPath = '',

  [string]$ImagePath = '',
  [string]$BaselinePath = '',
  [string]$ActualPath = '',
  [string]$DifferencePath = '',
  [int]$CropX,
  [int]$CropY,
  [int]$CropWidth,
  [int]$CropHeight,
  [ValidateRange(0, 255)]
  [int]$PixelTolerance = 0,
  [ValidateRange(0.0, 1.0)]
  [double]$MaxDifferenceRatio = 0.0,
  [ValidateRange(0.0, 1.0)]
  [double]$MaxMeanError = 0.0,

  [string]$ProjectRoot = '',
  [string]$Product = 'default',
  [string]$HvigorPath = '',
  [string]$SdkHome = '',
  [ValidateSet('debug', 'release')]
  [string]$BuildMode = 'debug',
  [string[]]$Modules = @(),
  [string]$PackagePath = '',
  [string]$MainPackagePath = '',
  [string]$TestPackagePath = '',
  [string]$Bundle = '',
  [string]$Ability = '',
  [string]$Module = '',
  [string]$TestModule = 'entry_test',
  [string]$Runner = 'OpenHarmonyTestRunner',
  [ValidateRange(1000, 3600000)]
  [int]$TestTimeoutMs = 60000,
  [ValidateRange(1, 3600)]
  [int]$WaitSeconds = 120,
  [ValidateRange(1, 5000)]
  [int]$Tail = 200,
  [string]$Level = '',
  [string]$Keyword = '',
  [string]$From = '',
  [string]$To = '',

  [Nullable[int]]$WindowLeft,
  [Nullable[int]]$WindowTop,
  [Nullable[int]]$WindowWidth,
  [Nullable[int]]$WindowHeight,

  [switch]$DebugLaunch,
  [switch]$SkipBuild,
  [switch]$IncludeTests,
  [switch]$ValidateOnly,
  [switch]$KeepRemote,
  [switch]$DryRun
)

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'HdcAgentTools.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'ImageAgentTools.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'TestAgentTools.psm1') -Force -DisableNameChecking

function Require-Value {
  param(
    [string]$Name,
    [string]$Value
  )

  if ($Value.Length -eq 0) {
    throw "-${Name} is required for command '${Command}'."
  }
}

function ConvertTo-TimePoints {
  param(
    [string[]]$Values
  )

  $timePoints = @()
  foreach ($value in $Values) {
    foreach ($part in ($value -split ',')) {
      $trimmed = $part.Trim()
      if ($trimmed.Length -eq 0) {
        continue
      }
      $parsed = 0
      if (-not [int]::TryParse($trimmed, [ref]$parsed)) {
        throw "-CaptureAtMs contains a non-integer value: '$trimmed'."
      }
      $timePoints += $parsed
    }
  }
  return [int[]]$timePoints
}

$displayForCoordinates = $null
function Resolve-InputPoint {
  param(
    [string]$XName,
    [string]$YName,
    [string]$XRatioName,
    [string]$YRatioName
  )

  $hasX = $PSBoundParametersFromCli.ContainsKey($XName)
  $hasY = $PSBoundParametersFromCli.ContainsKey($YName)
  $hasXRatio = $PSBoundParametersFromCli.ContainsKey($XRatioName)
  $hasYRatio = $PSBoundParametersFromCli.ContainsKey($YRatioName)
  if ($hasX -or $hasY) {
    if (-not ($hasX -and $hasY) -or $hasXRatio -or $hasYRatio) {
      throw "Specify either -${XName}/-${YName} or -${XRatioName}/-${YRatioName}."
    }
    return [pscustomobject]@{
      x = [int]$PSBoundParametersFromCli[$XName]
      y = [int]$PSBoundParametersFromCli[$YName]
      normalized = $false
    }
  }
  if (-not ($hasXRatio -and $hasYRatio)) {
    throw "Specify either -${XName}/-${YName} or -${XRatioName}/-${YRatioName}."
  }

  if ($null -eq $displayForCoordinates) {
    if ($null -ne $DisplayWidth -or $null -ne $DisplayHeight) {
      if ($null -eq $DisplayWidth -or $null -eq $DisplayHeight) {
        throw '-DisplayWidth and -DisplayHeight must be specified together.'
      }
      $displayForCoordinates = [pscustomobject]@{
        width = [int]$DisplayWidth
        height = [int]$DisplayHeight
        source = 'explicit'
      }
    } elseif ($DryRun) {
      throw 'Normalized coordinates in dry-run mode require -DisplayWidth and -DisplayHeight.'
    } else {
      $displayForCoordinates = Get-HarmonyDisplay -Target $Target -HdcPath $HdcPath
    }
  }

  $point = ConvertFrom-HarmonyNormalizedPoint `
    -XRatio ([double]$PSBoundParametersFromCli[$XRatioName]) `
    -YRatio ([double]$PSBoundParametersFromCli[$YRatioName]) `
    -DisplayWidth $displayForCoordinates.width -DisplayHeight $displayForCoordinates.height
  return [pscustomobject]@{
    x = $point.x
    y = $point.y
    xRatio = $point.xRatio
    yRatio = $point.yRatio
    normalized = $true
    display = $displayForCoordinates
  }
}

try {
  $PSBoundParametersFromCli = $PSBoundParameters
  $deviceCommands = @(
    'display', 'tap', 'swipe', 'screenshot', 'gesture-capture', 'scenario',
    'install', 'start', 'stop', 'logs', 'deploy', 'test-device'
  )
  if ($Command -in $deviceCommands -and $EmulatorName.Length -gt 0) {
    if ($Target.Length -gt 0) {
      throw 'Specify either -Target or -EmulatorName, not both.'
    }
    $Target = if ($DryRun) {
      "<emulator:$EmulatorName>"
    } else {
      Resolve-DevEcoEmulatorTarget -Name $EmulatorName -HdcPath $HdcPath
    }
  }

  switch ($Command) {
    'targets' {
      $result = @(Get-HarmonyDevice -HdcPath $HdcPath)
    }
    'emulators' {
      $result = @(Get-DevEcoEmulator -HdcPath $HdcPath)
    }
    'display' {
      if ($DryRun) {
        throw "The 'display' command does not support -DryRun."
      }
      $result = Get-HarmonyDisplay -Target $Target -HdcPath $HdcPath
    }
    'doctor' {
      $result = Get-HarmonyAgentHealth -ProjectRoot $ProjectRoot -HdcPath $HdcPath `
        -DevEcoCliPath $DevEcoCliPath
    }
    'tap' {
      $point = Resolve-InputPoint -XName 'X' -YName 'Y' `
        -XRatioName 'XRatio' -YRatioName 'YRatio'
      $result = Send-HarmonyTap -X $point.x -Y $point.y -PressMs $PressMs `
        -Target $Target -HdcPath $HdcPath -DryRun:$DryRun
      if ($point.normalized) {
        $result | Add-Member -NotePropertyName normalized -NotePropertyValue ([pscustomobject]@{
          xRatio = $point.xRatio
          yRatio = $point.yRatio
          displayWidth = $point.display.width
          displayHeight = $point.display.height
          displaySource = $point.display.source
        })
      }
    }
    'swipe' {
      $startPoint = Resolve-InputPoint -XName 'StartX' -YName 'StartY' `
        -XRatioName 'StartXRatio' -YRatioName 'StartYRatio'
      $endPoint = Resolve-InputPoint -XName 'EndX' -YName 'EndY' `
        -XRatioName 'EndXRatio' -YRatioName 'EndYRatio'
      if ($startPoint.normalized -ne $endPoint.normalized) {
        throw 'Swipe start and end must both use pixels or both use normalized coordinates.'
      }
      $result = Send-HarmonySwipe -StartX $startPoint.x -StartY $startPoint.y `
        -EndX $endPoint.x -EndY $endPoint.y -DurationMs $DurationMs -KeepMs $KeepMs `
        -Target $Target -HdcPath $HdcPath -DryRun:$DryRun
      if ($startPoint.normalized) {
        $result | Add-Member -NotePropertyName normalized -NotePropertyValue ([pscustomobject]@{
          startXRatio = $startPoint.xRatio
          startYRatio = $startPoint.yRatio
          endXRatio = $endPoint.xRatio
          endYRatio = $endPoint.yRatio
          displayWidth = $startPoint.display.width
          displayHeight = $startPoint.display.height
          displaySource = $startPoint.display.source
        })
      }
    }
    'screenshot' {
      Require-Value -Name 'OutputPath' -Value $OutputPath
      $result = Save-HarmonyScreenshot -OutputPath $OutputPath -DelayMs $DelayMs `
        -Target $Target -HdcPath $HdcPath -KeepRemote:$KeepRemote -DryRun:$DryRun
    }
    'gesture-capture' {
      Require-Value -Name 'OutputDirectory' -Value $OutputDirectory
      $captureTimes = ConvertTo-TimePoints -Values $CaptureAtMs
      $startPoint = Resolve-InputPoint -XName 'StartX' -YName 'StartY' `
        -XRatioName 'StartXRatio' -YRatioName 'StartYRatio'
      $endPoint = Resolve-InputPoint -XName 'EndX' -YName 'EndY' `
        -XRatioName 'EndXRatio' -YRatioName 'EndYRatio'
      if ($startPoint.normalized -ne $endPoint.normalized) {
        throw 'Gesture start and end must both use pixels or both use normalized coordinates.'
      }
      $result = Invoke-HarmonyGestureCapture -StartX $startPoint.x -StartY $startPoint.y `
        -EndX $endPoint.x -EndY $endPoint.y -DurationMs $DurationMs -KeepMs $KeepMs `
        -CaptureAtMs $captureTimes -OutputDirectory $OutputDirectory -Prefix $Prefix `
        -Target $Target -HdcPath $HdcPath -DryRun:$DryRun
    }
    'scenario' {
      Require-Value -Name 'ScenarioPath' -Value $ScenarioPath
      $result = Invoke-HarmonyScenario -Path $ScenarioPath -Target $Target `
        -OutputDirectory $OutputDirectory -HdcPath $HdcPath `
        -ValidateOnly:$ValidateOnly -DryRun:$DryRun
    }
    'image-info' {
      Require-Value -Name 'ImagePath' -Value $ImagePath
      $result = Get-AgentImageInfo -ImagePath $ImagePath
    }
    'crop-image' {
      Require-Value -Name 'ImagePath' -Value $ImagePath
      Require-Value -Name 'OutputPath' -Value $OutputPath
      foreach ($name in @('CropX', 'CropY', 'CropWidth', 'CropHeight')) {
        if (-not $PSBoundParametersFromCli.ContainsKey($name)) {
          throw "-${name} is required for command '${Command}'."
        }
      }
      $result = Crop-AgentImage -ImagePath $ImagePath -OutputPath $OutputPath `
        -X $CropX -Y $CropY -Width $CropWidth -Height $CropHeight
    }
    'compare-images' {
      Require-Value -Name 'BaselinePath' -Value $BaselinePath
      Require-Value -Name 'ActualPath' -Value $ActualPath
      $result = Compare-AgentImage -BaselinePath $BaselinePath -ActualPath $ActualPath `
        -DifferencePath $DifferencePath -PixelTolerance $PixelTolerance `
        -MaxDifferenceRatio $MaxDifferenceRatio -MaxMeanError $MaxMeanError
    }
    'assert-image' {
      Require-Value -Name 'BaselinePath' -Value $BaselinePath
      Require-Value -Name 'ActualPath' -Value $ActualPath
      $result = Assert-AgentImage -BaselinePath $BaselinePath -ActualPath $ActualPath `
        -DifferencePath $DifferencePath -PixelTolerance $PixelTolerance `
        -MaxDifferenceRatio $MaxDifferenceRatio -MaxMeanError $MaxMeanError
    }
    'test-local' {
      Require-Value -Name 'ProjectRoot' -Value $ProjectRoot
      $testModuleName = if ($Module.Length -gt 0) { $Module } else { 'entry' }
      $result = Invoke-HarmonyLocalTest -ProjectRoot $ProjectRoot -Module $testModuleName `
        -Product $Product -HvigorPath $HvigorPath -SdkHome $SdkHome -DryRun:$DryRun
    }
    'test-device' {
      Require-Value -Name 'ProjectRoot' -Value $ProjectRoot
      Require-Value -Name 'Bundle' -Value $Bundle
      $testModuleName = if ($Module.Length -gt 0) { $Module } else { 'entry' }
      $parameters = @{
        ProjectRoot = $ProjectRoot
        Bundle = $Bundle
        Module = $testModuleName
        TestModule = $TestModule
        Runner = $Runner
        Product = $Product
        MainPackagePath = $MainPackagePath
        TestPackagePath = $TestPackagePath
        Target = $Target
        HdcPath = $HdcPath
        HvigorPath = $HvigorPath
        SdkHome = $SdkHome
        TestTimeoutMs = $TestTimeoutMs
        WaitSeconds = $WaitSeconds
        SkipBuild = $SkipBuild
        DryRun = $DryRun
      }
      $result = Invoke-HarmonyDeviceTest @parameters
    }
    'build' {
      Require-Value -Name 'ProjectRoot' -Value $ProjectRoot
      $result = Build-HarmonyProject -ProjectRoot $ProjectRoot -Product $Product `
        -BuildMode $BuildMode -Modules $Modules -DevEcoCliPath $DevEcoCliPath `
        -DryRun:$DryRun
    }
    'packages' {
      Require-Value -Name 'ProjectRoot' -Value $ProjectRoot
      $result = @(Get-HarmonyPackage -ProjectRoot $ProjectRoot -IncludeTests:$IncludeTests)
    }
    'install' {
      Require-Value -Name 'PackagePath' -Value $PackagePath
      $result = Install-HarmonyPackage -PackagePath $PackagePath -Target $Target `
        -HdcPath $HdcPath -DryRun:$DryRun
    }
    'start' {
      Require-Value -Name 'Bundle' -Value $Bundle
      Require-Value -Name 'Ability' -Value $Ability
      $parameters = @{
        Bundle = $Bundle
        Ability = $Ability
        Module = $Module
        Target = $Target
        HdcPath = $HdcPath
        DebugLaunch = $DebugLaunch
        DryRun = $DryRun
      }
      if ($null -ne $WindowLeft) { $parameters.WindowLeft = $WindowLeft }
      if ($null -ne $WindowTop) { $parameters.WindowTop = $WindowTop }
      if ($null -ne $WindowWidth) { $parameters.WindowWidth = $WindowWidth }
      if ($null -ne $WindowHeight) { $parameters.WindowHeight = $WindowHeight }
      $result = Start-HarmonyAbility @parameters
    }
    'stop' {
      Require-Value -Name 'Bundle' -Value $Bundle
      $result = Stop-HarmonyApp -Bundle $Bundle -Target $Target -HdcPath $HdcPath `
        -DryRun:$DryRun
    }
    'logs' {
      $result = Read-HarmonyLog -Target $Target -Bundle $Bundle -Tail $Tail -Level $Level `
        -Keyword $Keyword -From $From -To $To -HdcPath $HdcPath `
        -DevEcoCliPath $DevEcoCliPath -DryRun:$DryRun
    }
    'deploy' {
      Require-Value -Name 'ProjectRoot' -Value $ProjectRoot
      Require-Value -Name 'PackagePath' -Value $PackagePath
      Require-Value -Name 'Bundle' -Value $Bundle
      Require-Value -Name 'Ability' -Value $Ability
      $result = Deploy-HarmonyApp -ProjectRoot $ProjectRoot -PackagePath $PackagePath `
        -Bundle $Bundle -Ability $Ability -Module $Module -Product $Product `
        -BuildMode $BuildMode -Target $Target -HdcPath $HdcPath `
        -DevEcoCliPath $DevEcoCliPath -DebugLaunch:$DebugLaunch -SkipBuild:$SkipBuild `
        -DryRun:$DryRun
    }
  }

  $result | ConvertTo-Json -Depth 20
} catch {
  [Console]::Error.WriteLine($_.Exception.Message)
  exit 1
}
