Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'HdcAgentTools.psm1') -DisableNameChecking

function ConvertTo-AgentCommandDisplay {
  param(
    [string]$FilePath,
    [string[]]$ArgumentList
  )

  return (@($FilePath) + @($ArgumentList | ForEach-Object {
    if ($_ -match '[\s"]') { '"' + $_.Replace('"', '\"') + '"' } else { $_ }
  })) -join ' '
}

function Invoke-AgentNativeCommand {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,

    [string[]]$ArgumentList = @(),

    [string]$WorkingDirectory = '',

    [hashtable]$Environment = @{},

    [switch]$AllowFailure,

    [switch]$DryRun
  )

  $display = ConvertTo-AgentCommandDisplay -FilePath $FilePath -ArgumentList $ArgumentList
  if ($DryRun) {
    return [pscustomobject]@{
      command = $display
      exitCode = 0
      durationMs = 0
      output = @()
      environment = $Environment
      dryRun = $true
    }
  }

  $previousLocation = $null
  $previousErrorActionPreference = $ErrorActionPreference
  $previousEnvironment = @{}
  $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
  try {
    if ($WorkingDirectory.Length -gt 0) {
      $previousLocation = Get-Location
      Set-Location -LiteralPath $WorkingDirectory
    }
    foreach ($name in $Environment.Keys) {
      $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
      [Environment]::SetEnvironmentVariable($name, [string]$Environment[$name], 'Process')
    }
    $ErrorActionPreference = 'Continue'
    $output = @(& $FilePath @ArgumentList 2>&1 | ForEach-Object { $_.ToString() })
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
    foreach ($name in $Environment.Keys) {
      [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], 'Process')
    }
    if ($null -ne $previousLocation) {
      Set-Location -LiteralPath $previousLocation.Path
    }
    $stopwatch.Stop()
  }

  $result = [pscustomobject]@{
    command = $display
    exitCode = $exitCode
    durationMs = [int]$stopwatch.ElapsedMilliseconds
    output = $output
    environment = $Environment
    dryRun = $false
  }
  if ($exitCode -ne 0 -and -not $AllowFailure) {
    throw "Command failed with exit code ${exitCode}: ${display}`n$($output -join [Environment]::NewLine)"
  }
  return $result
}

function Resolve-HvigorWrapper {
  param(
    [string]$HvigorPath = ''
  )

  if ($HvigorPath.Length -gt 0) {
    $absolutePath = [System.IO.Path]::GetFullPath($HvigorPath)
    if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) {
      throw "Hvigor wrapper does not exist: ${absolutePath}"
    }
    return $absolutePath
  }
  $command = Get-Command 'hvigorw' -ErrorAction SilentlyContinue
  if ($null -ne $command) {
    return $command.Source
  }
  $defaultPath = 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat'
  if (Test-Path -LiteralPath $defaultPath -PathType Leaf) {
    return $defaultPath
  }
  throw 'Hvigor wrapper was not found. Pass -HvigorPath explicitly.'
}

function Resolve-DevEcoSdkHome {
  param(
    [string]$SdkHome = ''
  )

  $candidates = @()
  if ($SdkHome.Length -gt 0) {
    $candidates += $SdkHome
  }
  $configured = [Environment]::GetEnvironmentVariable('DEVECO_SDK_HOME')
  if ($configured) {
    $candidates += $configured
  }
  $candidates += 'C:\Program Files\Huawei\DevEco Studio\sdk'
  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate -PathType Container) {
      return [System.IO.Path]::GetFullPath($candidate)
    }
  }
  throw 'DEVECO_SDK_HOME could not be resolved. Pass -SdkHome with the DevEco SDK parent directory.'
}

function Invoke-HarmonyLocalTest {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,

    [string]$Module = 'entry',

    [string]$Product = 'default',

    [string]$HvigorPath = '',

    [string]$SdkHome = '',

    [switch]$DryRun
  )

  $absoluteRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
  if (-not $DryRun -and -not (Test-Path -LiteralPath $absoluteRoot -PathType Container)) {
    throw "Project root does not exist: ${absoluteRoot}"
  }
  $wrapper = if ($DryRun -and $HvigorPath.Length -eq 0) {
    'hvigorw'
  } else {
    Resolve-HvigorWrapper -HvigorPath $HvigorPath
  }
  $resolvedSdkHome = if ($DryRun -and $SdkHome.Length -eq 0) {
    '<DEVECO_SDK_HOME>'
  } else {
    Resolve-DevEcoSdkHome -SdkHome $SdkHome
  }
  $arguments = @(
    'test',
    '--mode', 'module',
    '-p', "product=${Product}",
    '-p', "module=${Module}@default",
    '--no-daemon'
  )
  $command = Invoke-AgentNativeCommand -FilePath $wrapper -ArgumentList $arguments `
    -WorkingDirectory $absoluteRoot -Environment @{ DEVECO_SDK_HOME = $resolvedSdkHome } `
    -DryRun:$DryRun
  return [pscustomobject]@{
    action = 'localTest'
    projectRoot = $absoluteRoot
    module = $Module
    product = $Product
    passed = $command.exitCode -eq 0
    command = $command
  }
}

function Invoke-HarmonyDeviceTest {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,

    [Parameter(Mandatory = $true)]
    [string]$Bundle,

    [string]$Module = 'entry',

    [string]$TestModule = 'entry_test',

    [string]$Runner = 'OpenHarmonyTestRunner',

    [string]$Product = 'default',

    [string]$MainPackagePath = '',

    [string]$TestPackagePath = '',

    [string]$Target = '',

    [string]$HdcPath = 'hdc',

    [string]$HvigorPath = '',

    [string]$SdkHome = '',

    [ValidateRange(1000, 3600000)]
    [int]$TestTimeoutMs = 60000,

    [ValidateRange(1, 3600)]
    [int]$WaitSeconds = 120,

    [switch]$SkipBuild,

    [switch]$DryRun
  )

  $absoluteRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
  $resolvedTarget = if ($DryRun) {
    if ($Target.Length -gt 0) { $Target } else { '<target>' }
  } else {
    Resolve-HarmonyTarget -Target $Target -HdcPath $HdcPath
  }

  $build = $null
  if (-not $SkipBuild) {
    $wrapper = if ($DryRun -and $HvigorPath.Length -eq 0) {
      'hvigorw'
    } else {
      Resolve-HvigorWrapper -HvigorPath $HvigorPath
    }
    $resolvedSdkHome = if ($DryRun -and $SdkHome.Length -eq 0) {
      '<DEVECO_SDK_HOME>'
    } else {
      Resolve-DevEcoSdkHome -SdkHome $SdkHome
    }
    $buildCommand = Invoke-AgentNativeCommand -FilePath $wrapper -ArgumentList @(
      'onDeviceTest',
      '--mode', 'module',
      '-p', "product=${Product}",
      '-p', "module=${Module}@ohosTest",
      '--no-daemon'
    ) -WorkingDirectory $absoluteRoot `
      -Environment @{ DEVECO_SDK_HOME = $resolvedSdkHome } -DryRun:$DryRun
    $build = [pscustomobject]@{
      action = 'buildDeviceTest'
      command = $buildCommand
    }
  }

  if ($MainPackagePath.Length -eq 0) {
    $MainPackagePath = Join-Path $absoluteRoot `
      "${Module}\build\${Product}\outputs\${Product}\${Module}-${Product}-signed.hap"
  }
  if ($TestPackagePath.Length -eq 0) {
    $TestPackagePath = Join-Path $absoluteRoot `
      "${Module}\build\${Product}\outputs\ohosTest\${Module}-ohosTest-signed.hap"
  }
  $mainInstall = Install-HarmonyPackage -PackagePath $MainPackagePath `
    -Target $resolvedTarget -HdcPath $HdcPath -DryRun:$DryRun
  $testInstall = Install-HarmonyPackage -PackagePath $TestPackagePath `
    -Target $resolvedTarget -HdcPath $HdcPath -DryRun:$DryRun
  $testArguments = @(
    '-t', $resolvedTarget,
    'shell', 'aa', 'test',
    '-b', $Bundle,
    '-m', $TestModule,
    '-s', 'unittest', $Runner,
    '-s', 'timeout', "$TestTimeoutMs",
    '-w', "$WaitSeconds"
  )
  $test = Invoke-AgentNativeCommand -FilePath $HdcPath -ArgumentList $testArguments `
    -AllowFailure -DryRun:$DryRun
  $testsRun = $null
  $failureCount = $null
  $errorCount = $null
  $passCount = $null
  $reportCode = $null
  $finishedCode = $null
  foreach ($line in $test.output) {
    $resultMatch = [regex]::Match(
      $line,
      'Tests run:\s*(\d+),\s*Failure:\s*(\d+),\s*Error:\s*(\d+),\s*Pass:\s*(\d+)'
    )
    if ($resultMatch.Success) {
      $testsRun = [int]$resultMatch.Groups[1].Value
      $failureCount = [int]$resultMatch.Groups[2].Value
      $errorCount = [int]$resultMatch.Groups[3].Value
      $passCount = [int]$resultMatch.Groups[4].Value
    }
    if ($line -match 'OHOS_REPORT_CODE:\s*(-?\d+)') {
      $reportCode = [int]$Matches[1]
    }
    if ($line -match 'TestFinished-ResultCode:\s*(-?\d+)') {
      $finishedCode = [int]$Matches[1]
    }
  }
  $hasStructuredResult = $null -ne $testsRun -and $null -ne $reportCode
  $passed = $test.exitCode -eq 0 -and (
    $DryRun -or (
      $hasStructuredResult -and
      $testsRun -gt 0 -and
      $passCount -eq $testsRun -and
      $failureCount -eq 0 -and
      $errorCount -eq 0 -and
      $reportCode -eq 0 -and
      ($null -eq $finishedCode -or $finishedCode -eq 0)
    )
  )

  return [pscustomobject]@{
    action = 'deviceTest'
    projectRoot = $absoluteRoot
    target = $resolvedTarget
    bundle = $Bundle
    testModule = $TestModule
    runner = $Runner
    passed = $passed
    build = $build
    installs = @($mainInstall, $testInstall)
    test = $test
    summary = [pscustomobject]@{
      testsRun = $testsRun
      passed = $passCount
      failures = $failureCount
      errors = $errorCount
      reportCode = $reportCode
      finishedCode = $finishedCode
      structuredResultFound = $hasStructuredResult
    }
    dryRun = [bool]$DryRun
  }
}

Export-ModuleMember -Function @(
  'Invoke-HarmonyLocalTest',
  'Invoke-HarmonyDeviceTest'
)
