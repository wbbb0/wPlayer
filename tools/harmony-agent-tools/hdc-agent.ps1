[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [ValidateSet(
    'targets',
    'emulators',
    'doctor',
    'tap',
    'swipe',
    'screenshot',
    'gesture-capture',
    'scenario',
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
  [int]$PressMs = 100,
  [int]$StartX,
  [int]$StartY,
  [int]$EndX,
  [int]$EndY,
  [int]$DurationMs = 300,
  [int]$KeepMs = 0,

  [string]$OutputPath = '',
  [string]$OutputDirectory = '',
  [string]$Prefix = 'gesture',
  [int]$DelayMs = 0,
  [string[]]$CaptureAtMs = @(),
  [string]$ScenarioPath = '',

  [string]$ProjectRoot = '',
  [string]$Product = 'default',
  [ValidateSet('debug', 'release')]
  [string]$BuildMode = 'debug',
  [string[]]$Modules = @(),
  [string]$PackagePath = '',
  [string]$Bundle = '',
  [string]$Ability = '',
  [string]$Module = '',
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

try {
  $deviceCommands = @(
    'tap', 'swipe', 'screenshot', 'gesture-capture', 'scenario',
    'install', 'start', 'stop', 'logs', 'deploy'
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
    'doctor' {
      $result = Get-HarmonyAgentHealth -ProjectRoot $ProjectRoot -HdcPath $HdcPath `
        -DevEcoCliPath $DevEcoCliPath
    }
    'tap' {
      $result = Send-HarmonyTap -X $X -Y $Y -PressMs $PressMs `
        -Target $Target -HdcPath $HdcPath -DryRun:$DryRun
    }
    'swipe' {
      $result = Send-HarmonySwipe -StartX $StartX -StartY $StartY `
        -EndX $EndX -EndY $EndY -DurationMs $DurationMs -KeepMs $KeepMs `
        -Target $Target -HdcPath $HdcPath -DryRun:$DryRun
    }
    'screenshot' {
      Require-Value -Name 'OutputPath' -Value $OutputPath
      $result = Save-HarmonyScreenshot -OutputPath $OutputPath -DelayMs $DelayMs `
        -Target $Target -HdcPath $HdcPath -KeepRemote:$KeepRemote -DryRun:$DryRun
    }
    'gesture-capture' {
      Require-Value -Name 'OutputDirectory' -Value $OutputDirectory
      $captureTimes = ConvertTo-TimePoints -Values $CaptureAtMs
      $result = Invoke-HarmonyGestureCapture -StartX $StartX -StartY $StartY `
        -EndX $EndX -EndY $EndY -DurationMs $DurationMs -KeepMs $KeepMs `
        -CaptureAtMs $captureTimes -OutputDirectory $OutputDirectory -Prefix $Prefix `
        -Target $Target -HdcPath $HdcPath -DryRun:$DryRun
    }
    'scenario' {
      Require-Value -Name 'ScenarioPath' -Value $ScenarioPath
      $result = Invoke-HarmonyScenario -Path $ScenarioPath -Target $Target `
        -OutputDirectory $OutputDirectory -HdcPath $HdcPath `
        -ValidateOnly:$ValidateOnly -DryRun:$DryRun
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
