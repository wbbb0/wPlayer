Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

# MCP hosts intentionally inherit a reduced environment. Restore only the
# standard Windows module path required by CimCmdlets and NetTCPIP discovery.
if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT -and
  -not [Environment]::GetEnvironmentVariable('PSModulePath', 'Process')) {
  $windowsDirectory = [Environment]::GetEnvironmentVariable('SystemRoot', 'Process')
  if ($windowsDirectory) {
    $systemModulePath = Join-Path $windowsDirectory 'System32\WindowsPowerShell\v1.0\Modules'
    [Environment]::SetEnvironmentVariable('PSModulePath', $systemModulePath, 'Process')
  }
}

function ConvertTo-CommandDisplay {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,

    [string[]]$ArgumentList = @()
  )

  $parts = @($FilePath)
  foreach ($argument in $ArgumentList) {
    if ($argument -match '[\s"]') {
      $parts += '"' + $argument.Replace('"', '\"') + '"'
    } else {
      $parts += $argument
    }
  }
  return $parts -join ' '
}

function Invoke-NativeCommand {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,

    [string[]]$ArgumentList = @(),

    [string]$WorkingDirectory = '',

    [switch]$AllowFailure,

    [switch]$DryRun
  )

  $display = ConvertTo-CommandDisplay -FilePath $FilePath -ArgumentList $ArgumentList
  if ($DryRun) {
    return [pscustomobject]@{
      command = $display
      exitCode = 0
      durationMs = 0
      output = @()
      dryRun = $true
    }
  }

  $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
  $previousLocation = $null
  $previousErrorActionPreference = $ErrorActionPreference
  try {
    if ($WorkingDirectory.Length -gt 0) {
      $previousLocation = Get-Location
      Set-Location -LiteralPath $WorkingDirectory
    }

    # Native applications commonly use stderr for warnings and progress. Do not
    # let the module-level Stop preference turn those records into exceptions
    # before the process exit code can be inspected.
    $ErrorActionPreference = 'Continue'
    $output = @(& $FilePath @ArgumentList 2>&1 | ForEach-Object { $_.ToString() })
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
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
    dryRun = $false
  }

  if ($exitCode -ne 0 -and -not $AllowFailure) {
    $message = "Command failed with exit code ${exitCode}: ${display}"
    if ($output.Count -gt 0) {
      $message += [Environment]::NewLine + ($output -join [Environment]::NewLine)
    }
    throw $message
  }

  return $result
}

function ConvertTo-NativeProcessArgument {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Value
  )

  if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') {
    return $Value
  }

  $builder = New-Object System.Text.StringBuilder
  [void]$builder.Append('"')
  $backslashCount = 0
  foreach ($character in $Value.ToCharArray()) {
    if ($character -eq '\') {
      $backslashCount += 1
      continue
    }

    if ($character -eq '"') {
      [void]$builder.Append(('\' * ($backslashCount * 2 + 1)))
      [void]$builder.Append('"')
      $backslashCount = 0
      continue
    }

    if ($backslashCount -gt 0) {
      [void]$builder.Append(('\' * $backslashCount))
      $backslashCount = 0
    }
    [void]$builder.Append($character)
  }

  if ($backslashCount -gt 0) {
    [void]$builder.Append(('\' * ($backslashCount * 2)))
  }
  [void]$builder.Append('"')
  return $builder.ToString()
}

function Start-NativeCommand {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,

    [string[]]$ArgumentList = @(),

    [string]$WorkingDirectory = ''
  )

  $startInfo = New-Object System.Diagnostics.ProcessStartInfo
  $startInfo.FileName = $FilePath
  $startInfo.Arguments = (@($ArgumentList | ForEach-Object {
    ConvertTo-NativeProcessArgument -Value $_
  }) -join ' ')
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  if ($WorkingDirectory.Length -gt 0) {
    $startInfo.WorkingDirectory = $WorkingDirectory
  }

  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = $startInfo
  $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
  if (-not $process.Start()) {
    throw "Unable to start command: $(ConvertTo-CommandDisplay $FilePath $ArgumentList)"
  }

  return [pscustomobject]@{
    process = $process
    stopwatch = $stopwatch
    command = ConvertTo-CommandDisplay -FilePath $FilePath -ArgumentList $ArgumentList
  }
}

function Complete-NativeCommand {
  param(
    [Parameter(Mandatory = $true)]
    [object]$RunningCommand,

    [switch]$AllowFailure
  )

  $RunningCommand.process.WaitForExit()
  $RunningCommand.stopwatch.Stop()
  $standardOutput = $RunningCommand.process.StandardOutput.ReadToEnd()
  $standardError = $RunningCommand.process.StandardError.ReadToEnd()
  $exitCode = $RunningCommand.process.ExitCode
  $output = @()
  if ($standardOutput.Length -gt 0) {
    $output += @($standardOutput.TrimEnd() -split '\r?\n')
  }
  if ($standardError.Length -gt 0) {
    $output += @($standardError.TrimEnd() -split '\r?\n')
  }
  $RunningCommand.process.Dispose()

  $result = [pscustomobject]@{
    command = $RunningCommand.command
    exitCode = $exitCode
    durationMs = [int]$RunningCommand.stopwatch.ElapsedMilliseconds
    output = $output
    dryRun = $false
  }

  if ($exitCode -ne 0 -and -not $AllowFailure) {
    $message = "Command failed with exit code ${exitCode}: $($RunningCommand.command)"
    if ($output.Count -gt 0) {
      $message += [Environment]::NewLine + ($output -join [Environment]::NewLine)
    }
    throw $message
  }

  return $result
}

function Get-OptionalProperty {
  param(
    [Parameter(Mandatory = $true)]
    [object]$Object,

    [Parameter(Mandatory = $true)]
    [string]$Name,

    $DefaultValue = $null
  )

  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) {
    return $DefaultValue
  }
  return $property.Value
}

function Get-HarmonyDevice {
  [CmdletBinding()]
  param(
    [string]$HdcPath = 'hdc'
  )

  $command = Invoke-NativeCommand -FilePath $HdcPath -ArgumentList @('list', 'targets', '-v')
  $devices = @()
  foreach ($line in $command.output) {
    $trimmed = $line.Trim()
    if ($trimmed.Length -eq 0) {
      continue
    }
    $parts = @($trimmed -split '\s+')
    $devices += [pscustomobject]@{
      target = $parts[0]
      transport = if ($parts.Count -gt 1) { $parts[1] } else { '' }
      state = if ($parts.Count -gt 2) { $parts[2] } else { '' }
      description = if ($parts.Count -gt 3) { ($parts[3..($parts.Count - 1)] -join ' ') } else { '' }
      usable = $parts.Count -gt 2 -and $parts[2] -in @('Connected', 'Ready')
    }
  }
  return $devices
}

function Get-DevEcoEmulator {
  [CmdletBinding()]
  param(
    [string]$HdcPath = 'hdc'
  )

  if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'DevEco emulator name mapping is currently supported on Windows only.'
  }

  $devicesByTarget = @{}
  foreach ($device in @(Get-HarmonyDevice -HdcPath $HdcPath)) {
    $devicesByTarget[$device.target] = $device
  }

  $processes = @(Get-CimInstance Win32_Process -Filter "Name = 'Emulator.exe'")
  $listeners = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
    Where-Object { $_.LocalAddress -in @('127.0.0.1', '::1') })
  $emulators = @()
  foreach ($process in $processes) {
    $match = [regex]::Match(
      [string]$process.CommandLine,
      '-hvd\s+(?:"(?<quoted>[^"]+)"|(?<bare>\S+))'
    )
    $name = if ($match.Success) {
      if ($match.Groups['quoted'].Success) {
        $match.Groups['quoted'].Value
      } else {
        $match.Groups['bare'].Value
      }
    } else {
      ''
    }

    $processListeners = @($listeners |
      Where-Object { $_.OwningProcess -eq $process.ProcessId } |
      Sort-Object LocalPort)
    if ($processListeners.Count -eq 0) {
      $emulators += [pscustomobject]@{
        name = $name
        target = $null
        processId = [int]$process.ProcessId
        connected = $false
        hdcState = $null
      }
      continue
    }

    foreach ($listener in $processListeners) {
      $hostAddress = if ($listener.LocalAddress -eq '::1') { '[::1]' } else { '127.0.0.1' }
      $target = "${hostAddress}:$($listener.LocalPort)"
      $device = if ($devicesByTarget.ContainsKey($target)) {
        $devicesByTarget[$target]
      } else {
        $null
      }
      $emulators += [pscustomobject]@{
        name = $name
        target = $target
        processId = [int]$process.ProcessId
        connected = $null -ne $device -and [bool]$device.usable
        hdcState = if ($null -ne $device) { $device.state } else { $null }
      }
    }
  }

  return @($emulators | Sort-Object name, target)
}

function Resolve-DevEcoEmulatorTarget {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name,

    [string]$HdcPath = 'hdc'
  )

  $matches = @(Get-DevEcoEmulator -HdcPath $HdcPath |
    Where-Object { $_.name -eq $Name -and $_.connected })
  if ($matches.Count -eq 0) {
    $available = @(Get-DevEcoEmulator -HdcPath $HdcPath |
      Where-Object { $_.connected } |
      ForEach-Object { $_.name }) -join ', '
    throw "Connected DevEco emulator '${Name}' was not found. Available emulators: ${available}"
  }
  if ($matches.Count -gt 1) {
    $targets = @($matches | ForEach-Object { $_.target }) -join ', '
    throw "Multiple connected DevEco emulators are named '${Name}'. Specify -Target instead: ${targets}"
  }
  return $matches[0].target
}

function Resolve-HarmonyTarget {
  param(
    [string]$Target = '',

    [string]$HdcPath = 'hdc'
  )

  $devices = @(Get-HarmonyDevice -HdcPath $HdcPath)
  if ($Target.Length -gt 0) {
    $matching = @($devices | Where-Object { $_.target -eq $Target -and $_.usable })
    if ($matching.Count -ne 1) {
      throw "Target '${Target}' is not connected and usable."
    }
    return $Target
  }

  $usableDevices = @($devices | Where-Object { $_.usable })
  if ($usableDevices.Count -eq 0) {
    throw 'No connected HarmonyOS target is available.'
  }
  if ($usableDevices.Count -gt 1) {
    $names = @($usableDevices | ForEach-Object { $_.target }) -join ', '
    throw "Multiple targets are connected. Specify -Target explicitly. Available targets: ${names}"
  }
  return $usableDevices[0].target
}

function Get-HdcArguments {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Target,

    [Parameter(Mandatory = $true)]
    [string[]]$CommandArguments
  )

  return @('-t', $Target) + $CommandArguments
}

function Get-HarmonyCommandTarget {
  param(
    [string]$Target = '',

    [string]$HdcPath = 'hdc',

    [switch]$DryRun
  )

  if ($DryRun) {
    return $(if ($Target.Length -gt 0) { $Target } else { '<target>' })
  }
  return Resolve-HarmonyTarget -Target $Target -HdcPath $HdcPath
}

function Invoke-HarmonyHdc {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Target,

    [Parameter(Mandatory = $true)]
    [string[]]$CommandArguments,

    [string]$HdcPath = 'hdc',

    [switch]$AllowFailure,

    [switch]$DryRun
  )

  $arguments = Get-HdcArguments -Target $Target -CommandArguments $CommandArguments
  return Invoke-NativeCommand -FilePath $HdcPath -ArgumentList $arguments `
    -AllowFailure:$AllowFailure -DryRun:$DryRun
}

function Get-HarmonyDisplay {
  [CmdletBinding()]
  param(
    [string]$Target = '',

    [string]$HdcPath = 'hdc'
  )

  $resolvedTarget = Resolve-HarmonyTarget -Target $Target -HdcPath $HdcPath
  $command = Invoke-HarmonyHdc -Target $resolvedTarget -HdcPath $HdcPath `
    -CommandArguments @('shell', 'hidumper', '-s', 'WindowManagerService', '-a', '-a')
  $rectangles = @()
  foreach ($line in $command.output) {
    foreach ($match in [regex]::Matches(
      $line,
      '\[\s*(-?\d+)\s+(-?\d+)\s+(\d+)\s+(\d+)\s*\]'
    )) {
      $width = [int]$match.Groups[3].Value
      $height = [int]$match.Groups[4].Value
      if ($width -gt 0 -and $height -gt 0) {
        $rectangles += [pscustomobject]@{
          x = [int]$match.Groups[1].Value
          y = [int]$match.Groups[2].Value
          width = $width
          height = $height
          area = [long]$width * [long]$height
        }
      }
    }
  }

  if ($rectangles.Count -eq 0) {
    throw 'WindowManagerService did not report a usable display rectangle.'
  }
  $display = @($rectangles | Sort-Object `
    @{ Expression = { if ($_.x -eq 0 -and $_.y -eq 0) { 1 } else { 0 } }; Descending = $true }, `
    @{ Expression = 'area'; Descending = $true })[0]
  return [pscustomobject]@{
    action = 'display'
    target = $resolvedTarget
    width = $display.width
    height = $display.height
    orientation = if ($display.width -gt $display.height) { 'landscape' } else { 'portrait' }
    source = 'WindowManagerService'
    command = [pscustomobject]@{
      command = $command.command
      exitCode = $command.exitCode
      durationMs = $command.durationMs
      dryRun = $command.dryRun
    }
  }
}

function ConvertFrom-HarmonyNormalizedPoint {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(0.0, 1.0)]
    [double]$XRatio,

    [Parameter(Mandatory = $true)]
    [ValidateRange(0.0, 1.0)]
    [double]$YRatio,

    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 100000)]
    [int]$DisplayWidth,

    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 100000)]
    [int]$DisplayHeight
  )

  return [pscustomobject]@{
    x = [int][Math]::Round($XRatio * ($DisplayWidth - 1))
    y = [int][Math]::Round($YRatio * ($DisplayHeight - 1))
    xRatio = $XRatio
    yRatio = $YRatio
    displayWidth = $DisplayWidth
    displayHeight = $DisplayHeight
  }
}

function Send-HarmonyTap {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(0, 100000)]
    [int]$X,

    [Parameter(Mandatory = $true)]
    [ValidateRange(0, 100000)]
    [int]$Y,

    [ValidateRange(1, 450)]
    [int]$PressMs = 100,

    [string]$Target = '',

    [string]$HdcPath = 'hdc',

    [switch]$DryRun
  )

  $resolvedTarget = Get-HarmonyCommandTarget -Target $Target -HdcPath $HdcPath -DryRun:$DryRun
  $command = Invoke-HarmonyHdc -Target $resolvedTarget -HdcPath $HdcPath -DryRun:$DryRun `
    -CommandArguments @('shell', 'uinput', '-T', '-c', "$X", "$Y", "$PressMs")
  return [pscustomobject]@{
    action = 'tap'
    target = $resolvedTarget
    x = $X
    y = $Y
    pressMs = $PressMs
    command = $command
  }
}

function Send-HarmonySwipe {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [int]$StartX,

    [Parameter(Mandatory = $true)]
    [int]$StartY,

    [Parameter(Mandatory = $true)]
    [int]$EndX,

    [Parameter(Mandatory = $true)]
    [int]$EndY,

    [ValidateRange(1, 15000)]
    [int]$DurationMs = 300,

    [ValidateRange(0, 60000)]
    [int]$KeepMs = 0,

    [string]$Target = '',

    [string]$HdcPath = 'hdc',

    [switch]$DryRun
  )

  $resolvedTarget = Get-HarmonyCommandTarget -Target $Target -HdcPath $HdcPath -DryRun:$DryRun
  $touchArguments = @(
    'shell', 'uinput', '-T', '-m',
    "$StartX", "$StartY", "$EndX", "$EndY"
  )
  if ($KeepMs -gt 0) {
    $touchArguments += @('-k', "$KeepMs")
  }
  $touchArguments += "$DurationMs"
  $command = Invoke-HarmonyHdc -Target $resolvedTarget -HdcPath $HdcPath `
    -CommandArguments $touchArguments -DryRun:$DryRun
  return [pscustomobject]@{
    action = 'swipe'
    target = $resolvedTarget
    start = [pscustomobject]@{ x = $StartX; y = $StartY }
    end = [pscustomobject]@{ x = $EndX; y = $EndY }
    durationMs = $DurationMs
    keepMs = $KeepMs
    command = $command
  }
}

function Wait-HarmonyTimeline {
  param(
    [Parameter(Mandatory = $true)]
    [System.Diagnostics.Stopwatch]$Stopwatch,

    [Parameter(Mandatory = $true)]
    [ValidateRange(0, 3600000)]
    [int]$AtMs
  )

  while ($Stopwatch.ElapsedMilliseconds -lt $AtMs) {
    $remaining = $AtMs - $Stopwatch.ElapsedMilliseconds
    if ($remaining -gt 12) {
      Start-Sleep -Milliseconds ([Math]::Max(1, $remaining - 5))
    } else {
      Start-Sleep -Milliseconds 1
    }
  }
}

function New-ScreenshotPaths {
  param(
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$RunId = ''
  )

  $absolutePath = [System.IO.Path]::GetFullPath($OutputPath)
  $directory = Split-Path -Parent $absolutePath
  if ($directory.Length -eq 0) {
    $directory = (Get-Location).Path
  }
  $extension = [System.IO.Path]::GetExtension($absolutePath)
  if ($extension.Length -eq 0) {
    $absolutePath += '.jpeg'
    $extension = '.jpeg'
  }
  if ($RunId.Length -eq 0) {
    $RunId = [Guid]::NewGuid().ToString('N')
  }
  if ($extension.ToLowerInvariant() -notin @('.jpg', '.jpeg')) {
    throw "HarmonyOS snapshot_display output must use a .jpg or .jpeg path: $absolutePath"
  }
  return [pscustomobject]@{
    local = $absolutePath
    directory = $directory
    remote = "/data/local/tmp/hdc-agent-${RunId}.jpeg"
  }
}

function Save-HarmonyScreenshot {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [ValidateRange(0, 3600000)]
    [int]$DelayMs = 0,

    [string]$Target = '',

    [string]$HdcPath = 'hdc',

    [switch]$KeepRemote,

    [switch]$DryRun
  )

  $resolvedTarget = Get-HarmonyCommandTarget -Target $Target -HdcPath $HdcPath -DryRun:$DryRun
  $paths = New-ScreenshotPaths -OutputPath $OutputPath
  if (-not $DryRun) {
    [void](New-Item -ItemType Directory -Path $paths.directory -Force)
    if ($DelayMs -gt 0) {
      Start-Sleep -Milliseconds $DelayMs
    }
  }

  $captureStartedAt = [DateTimeOffset]::Now
  $capture = Invoke-HarmonyHdc -Target $resolvedTarget -HdcPath $HdcPath -DryRun:$DryRun `
    -CommandArguments @('shell', 'snapshot_display', '-f', $paths.remote)
  $receive = Invoke-HarmonyHdc -Target $resolvedTarget -HdcPath $HdcPath -DryRun:$DryRun `
    -CommandArguments @('file', 'recv', $paths.remote, $paths.local)
  $cleanup = $null
  if (-not $KeepRemote) {
    $cleanup = Invoke-HarmonyHdc -Target $resolvedTarget -HdcPath $HdcPath -DryRun:$DryRun `
      -AllowFailure -CommandArguments @('shell', 'rm', '-f', $paths.remote)
  }

  if (-not $DryRun) {
    if (-not (Test-Path -LiteralPath $paths.local)) {
      $captureOutput = @($capture.output) -join [Environment]::NewLine
      $receiveOutput = @($receive.output) -join [Environment]::NewLine
      throw ("Screenshot was not received: {0}{1}capture: {2}{1}receive: {3}" -f
        $paths.local, [Environment]::NewLine, $captureOutput, $receiveOutput)
    }
    if ((Get-Item -LiteralPath $paths.local).Length -le 0) {
      throw "Screenshot is empty: $($paths.local)"
    }
  }

  return [pscustomobject]@{
    action = 'screenshot'
    target = $resolvedTarget
    requestedDelayMs = $DelayMs
    capturedAt = $captureStartedAt.ToString('o')
    path = $paths.local
    remotePath = if ($KeepRemote) { $paths.remote } else { $null }
    capture = $capture
    receive = $receive
    cleanup = $cleanup
    dryRun = [bool]$DryRun
  }
}

function Invoke-HarmonyGestureCapture {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [int]$StartX,

    [Parameter(Mandatory = $true)]
    [int]$StartY,

    [Parameter(Mandatory = $true)]
    [int]$EndX,

    [Parameter(Mandatory = $true)]
    [int]$EndY,

    [ValidateRange(1, 15000)]
    [int]$DurationMs = 300,

    [ValidateRange(0, 60000)]
    [int]$KeepMs = 0,

    [Parameter(Mandatory = $true)]
    [int[]]$CaptureAtMs,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [string]$Prefix = 'gesture',

    [string]$Target = '',

    [string]$HdcPath = 'hdc',

    [switch]$DryRun
  )

  if ($CaptureAtMs.Count -eq 0) {
    throw 'CaptureAtMs must contain at least one time point.'
  }
  foreach ($timePoint in $CaptureAtMs) {
    if ($timePoint -lt 0 -or $timePoint -gt 3600000) {
      throw "Invalid capture time point: ${timePoint}ms"
    }
  }

  $resolvedTarget = Get-HarmonyCommandTarget -Target $Target -HdcPath $HdcPath -DryRun:$DryRun
  $absoluteOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
  if (-not $DryRun) {
    [void](New-Item -ItemType Directory -Path $absoluteOutputDirectory -Force)
  }

  $touchArguments = @(
    'shell', 'uinput', '-T', '-m',
    "$StartX", "$StartY", "$EndX", "$EndY"
  )
  if ($KeepMs -gt 0) {
    $touchArguments += @('-k', "$KeepMs")
  }
  $touchArguments += "$DurationMs"
  $hdcTouchArguments = Get-HdcArguments -Target $resolvedTarget -CommandArguments $touchArguments

  $orderedTimes = @($CaptureAtMs | Sort-Object)
  $runId = [Guid]::NewGuid().ToString('N')
  $scheduledCaptures = @()

  if ($DryRun) {
    for ($index = 0; $index -lt $orderedTimes.Count; $index += 1) {
      $timePoint = $orderedTimes[$index]
      $name = '{0}-{1:D4}ms-{2:D2}.jpeg' -f $Prefix, $timePoint, $index
      $paths = New-ScreenshotPaths -OutputPath (Join-Path $absoluteOutputDirectory $name) `
        -RunId "${runId}-${index}"
      $scheduledCaptures += [pscustomobject]@{
        requestedAtMs = $timePoint
        actualStartMs = $timePoint
        path = $paths.local
        remotePath = $paths.remote
        command = ConvertTo-CommandDisplay -FilePath $HdcPath -ArgumentList (
          Get-HdcArguments -Target $resolvedTarget `
            -CommandArguments @('shell', 'snapshot_display', '-f', $paths.remote)
        )
      }
    }

    return [pscustomobject]@{
      action = 'gestureCapture'
      target = $resolvedTarget
      gestureCommand = ConvertTo-CommandDisplay -FilePath $HdcPath -ArgumentList $hdcTouchArguments
      durationMs = $DurationMs
      keepMs = $KeepMs
      captures = $scheduledCaptures
      artifacts = @($scheduledCaptures | ForEach-Object {
        [pscustomobject]@{ type = 'image'; path = $_.path; requestedAtMs = $_.requestedAtMs }
      })
      dryRun = $true
    }
  }

  $timeline = [System.Diagnostics.Stopwatch]::StartNew()
  $gesture = Start-NativeCommand -FilePath $HdcPath -ArgumentList $hdcTouchArguments
  try {
    for ($index = 0; $index -lt $orderedTimes.Count; $index += 1) {
      $timePoint = $orderedTimes[$index]
      Wait-HarmonyTimeline -Stopwatch $timeline -AtMs $timePoint
      $name = '{0}-{1:D4}ms-{2:D2}.jpeg' -f $Prefix, $timePoint, $index
      $paths = New-ScreenshotPaths -OutputPath (Join-Path $absoluteOutputDirectory $name) `
        -RunId "${runId}-${index}"
      $captureArguments = Get-HdcArguments -Target $resolvedTarget `
        -CommandArguments @('shell', 'snapshot_display', '-f', $paths.remote)
      $actualStartMs = [int]$timeline.ElapsedMilliseconds
      $runningCapture = Start-NativeCommand -FilePath $HdcPath -ArgumentList $captureArguments
      $scheduledCaptures += [pscustomobject]@{
        requestedAtMs = $timePoint
        actualStartMs = $actualStartMs
        path = $paths.local
        remotePath = $paths.remote
        running = $runningCapture
      }
    }

    $gestureResult = Complete-NativeCommand -RunningCommand $gesture
    $completedCaptures = @()
    foreach ($scheduled in $scheduledCaptures) {
      $captureResult = Complete-NativeCommand -RunningCommand $scheduled.running
      $receiveResult = Invoke-HarmonyHdc -Target $resolvedTarget -HdcPath $HdcPath `
        -CommandArguments @('file', 'recv', $scheduled.remotePath, $scheduled.path)
      [void](Invoke-HarmonyHdc -Target $resolvedTarget -HdcPath $HdcPath -AllowFailure `
        -CommandArguments @('shell', 'rm', '-f', $scheduled.remotePath))
      if (-not (Test-Path -LiteralPath $scheduled.path) -or
        (Get-Item -LiteralPath $scheduled.path).Length -le 0) {
        throw "Gesture screenshot was not received: $($scheduled.path)"
      }
      $completedCaptures += [pscustomobject]@{
        requestedAtMs = $scheduled.requestedAtMs
        actualStartMs = $scheduled.actualStartMs
        latenessMs = $scheduled.actualStartMs - $scheduled.requestedAtMs
        path = $scheduled.path
        capture = $captureResult
        receive = $receiveResult
      }
    }
  } catch {
    if (-not $gesture.process.HasExited) {
      $gesture.process.Kill()
    }
    foreach ($scheduled in $scheduledCaptures) {
      if ($null -ne $scheduled.running -and -not $scheduled.running.process.HasExited) {
        $scheduled.running.process.Kill()
      }
      [void](Invoke-HarmonyHdc -Target $resolvedTarget -HdcPath $HdcPath -AllowFailure `
        -CommandArguments @('shell', 'rm', '-f', $scheduled.remotePath))
    }
    throw
  } finally {
    $timeline.Stop()
  }

  return [pscustomobject]@{
    action = 'gestureCapture'
    target = $resolvedTarget
    gesture = $gestureResult
    durationMs = $DurationMs
    keepMs = $KeepMs
    elapsedMs = [int]$timeline.ElapsedMilliseconds
    captures = $completedCaptures
    artifacts = @($completedCaptures | ForEach-Object {
      [pscustomobject]@{
        type = 'image'
        path = $_.path
        requestedAtMs = $_.requestedAtMs
        actualStartMs = $_.actualStartMs
        latenessMs = $_.latenessMs
      }
    })
    dryRun = $false
  }
}

function Get-HarmonyScenarioPoint {
  param(
    [Parameter(Mandatory = $true)]
    [object]$Step,

    [Parameter(Mandatory = $true)]
    [string]$XName,

    [Parameter(Mandatory = $true)]
    [string]$YName,

    [Parameter(Mandatory = $true)]
    [string]$XRatioName,

    [Parameter(Mandatory = $true)]
    [string]$YRatioName,

    [Parameter(Mandatory = $true)]
    [ref]$Display,

    [string]$Target,

    [string]$HdcPath,

    [switch]$DryRun
  )

  $xProperty = $Step.PSObject.Properties[$XName]
  $yProperty = $Step.PSObject.Properties[$YName]
  $xRatioProperty = $Step.PSObject.Properties[$XRatioName]
  $yRatioProperty = $Step.PSObject.Properties[$YRatioName]
  $hasPixels = $null -ne $xProperty -or $null -ne $yProperty
  $hasRatios = $null -ne $xRatioProperty -or $null -ne $yRatioProperty
  if ($hasPixels) {
    if ($null -eq $xProperty -or $null -eq $yProperty -or $hasRatios) {
      throw "Scenario step must specify either ${XName}/${YName} or ${XRatioName}/${YRatioName}."
    }
    return [pscustomobject]@{
      x = [int]$xProperty.Value
      y = [int]$yProperty.Value
      normalized = $false
    }
  }
  if ($null -eq $xRatioProperty -or $null -eq $yRatioProperty) {
    throw "Scenario step must specify either ${XName}/${YName} or ${XRatioName}/${YRatioName}."
  }
  if ($null -eq $Display.Value) {
    if ($DryRun) {
      throw 'Normalized scenario coordinates in dry-run mode require displayWidth and displayHeight.'
    }
    $Display.Value = Get-HarmonyDisplay -Target $Target -HdcPath $HdcPath
  }
  $point = ConvertFrom-HarmonyNormalizedPoint -XRatio ([double]$xRatioProperty.Value) `
    -YRatio ([double]$yRatioProperty.Value) -DisplayWidth $Display.Value.width `
    -DisplayHeight $Display.Value.height
  return [pscustomobject]@{
    x = $point.x
    y = $point.y
    normalized = $true
  }
}

function Invoke-HarmonyScenario {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [string]$Target = '',

    [string]$OutputDirectory = '',

    [string]$HdcPath = 'hdc',

    [switch]$ValidateOnly,

    [switch]$DryRun
  )

  $scenarioPath = [System.IO.Path]::GetFullPath($Path)
  if (-not (Test-Path -LiteralPath $scenarioPath)) {
    throw "Scenario file does not exist: ${scenarioPath}"
  }
  $scenario = Get-Content -LiteralPath $scenarioPath -Raw | ConvertFrom-Json
  $steps = @(Get-OptionalProperty -Object $scenario -Name 'steps' -DefaultValue @())
  if ($steps.Count -eq 0) {
    throw 'Scenario must contain at least one step.'
  }

  $scenarioTarget = [string](Get-OptionalProperty -Object $scenario -Name 'target' -DefaultValue '')
  if ($Target.Length -eq 0) {
    $Target = $scenarioTarget
  }
  $resolvedTarget = Get-HarmonyCommandTarget -Target $Target -HdcPath $HdcPath `
    -DryRun:($DryRun -or $ValidateOnly)

  if ($OutputDirectory.Length -eq 0) {
    $configuredOutput = [string](Get-OptionalProperty -Object $scenario -Name 'outputDirectory' `
      -DefaultValue 'artifacts')
    if ([System.IO.Path]::IsPathRooted($configuredOutput)) {
      $OutputDirectory = $configuredOutput
    } else {
      $OutputDirectory = Join-Path (Split-Path -Parent $scenarioPath) $configuredOutput
    }
  }
  $absoluteOutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
  $scenarioDisplay = $null
  $configuredDisplayWidth = Get-OptionalProperty -Object $scenario -Name 'displayWidth'
  $configuredDisplayHeight = Get-OptionalProperty -Object $scenario -Name 'displayHeight'
  if ($null -ne $configuredDisplayWidth -or $null -ne $configuredDisplayHeight) {
    if ($null -eq $configuredDisplayWidth -or $null -eq $configuredDisplayHeight) {
      throw 'Scenario displayWidth and displayHeight must be specified together.'
    }
    $scenarioDisplay = [pscustomobject]@{
      width = [int]$configuredDisplayWidth
      height = [int]$configuredDisplayHeight
      source = 'scenario'
    }
  }

  $supportedActions = @('tap', 'swipe', 'wait', 'screenshot', 'gestureCapture')
  foreach ($step in $steps) {
    $action = [string](Get-OptionalProperty -Object $step -Name 'action' -DefaultValue '')
    if ($action -notin $supportedActions) {
      throw "Unsupported scenario action: '${action}'. Supported actions: $($supportedActions -join ', ')"
    }
  }

  if ($ValidateOnly) {
    return [pscustomobject]@{
      action = 'scenarioValidation'
      scenario = $scenarioPath
      target = $resolvedTarget
      stepCount = $steps.Count
      valid = $true
    }
  }

  $timeline = [System.Diagnostics.Stopwatch]::StartNew()
  $events = @()
  $artifacts = @()
  for ($index = 0; $index -lt $steps.Count; $index += 1) {
    $step = $steps[$index]
    $action = [string](Get-OptionalProperty -Object $step -Name 'action' -DefaultValue '')
    $atMs = [int](Get-OptionalProperty -Object $step -Name 'atMs' -DefaultValue -1)
    if (-not $DryRun -and $atMs -ge 0) {
      Wait-HarmonyTimeline -Stopwatch $timeline -AtMs $atMs
    }

    switch ($action) {
      'tap' {
        $point = Get-HarmonyScenarioPoint -Step $step -XName 'x' -YName 'y' `
          -XRatioName 'xRatio' -YRatioName 'yRatio' -Display ([ref]$scenarioDisplay) `
          -Target $resolvedTarget -HdcPath $HdcPath -DryRun:$DryRun
        $event = Send-HarmonyTap `
          -X $point.x -Y $point.y `
          -PressMs ([int](Get-OptionalProperty $step 'pressMs' 100)) `
          -Target $resolvedTarget -HdcPath $HdcPath -DryRun:$DryRun
      }
      'swipe' {
        $startPoint = Get-HarmonyScenarioPoint -Step $step -XName 'startX' -YName 'startY' `
          -XRatioName 'startXRatio' -YRatioName 'startYRatio' -Display ([ref]$scenarioDisplay) `
          -Target $resolvedTarget -HdcPath $HdcPath -DryRun:$DryRun
        $endPoint = Get-HarmonyScenarioPoint -Step $step -XName 'endX' -YName 'endY' `
          -XRatioName 'endXRatio' -YRatioName 'endYRatio' -Display ([ref]$scenarioDisplay) `
          -Target $resolvedTarget -HdcPath $HdcPath -DryRun:$DryRun
        $event = Send-HarmonySwipe `
          -StartX $startPoint.x -StartY $startPoint.y `
          -EndX $endPoint.x -EndY $endPoint.y `
          -DurationMs ([int](Get-OptionalProperty $step 'durationMs' 300)) `
          -KeepMs ([int](Get-OptionalProperty $step 'keepMs' 0)) `
          -Target $resolvedTarget -HdcPath $HdcPath -DryRun:$DryRun
      }
      'wait' {
        $milliseconds = [int](Get-OptionalProperty $step 'milliseconds' 0)
        if ($milliseconds -lt 0) {
          throw 'Wait milliseconds cannot be negative.'
        }
        if (-not $DryRun -and $milliseconds -gt 0) {
          Start-Sleep -Milliseconds $milliseconds
        }
        $event = [pscustomobject]@{
          action = 'wait'
          milliseconds = $milliseconds
          dryRun = [bool]$DryRun
        }
      }
      'screenshot' {
        $name = [string](Get-OptionalProperty $step 'name' ('shot-{0:D2}.jpeg' -f $index))
        $event = Save-HarmonyScreenshot -OutputPath (Join-Path $absoluteOutputDirectory $name) `
          -Target $resolvedTarget -HdcPath $HdcPath -DryRun:$DryRun
        $artifacts += [pscustomobject]@{
          type = 'image'
          path = $event.path
          scenarioStep = $index
        }
      }
      'gestureCapture' {
        $startPoint = Get-HarmonyScenarioPoint -Step $step -XName 'startX' -YName 'startY' `
          -XRatioName 'startXRatio' -YRatioName 'startYRatio' -Display ([ref]$scenarioDisplay) `
          -Target $resolvedTarget -HdcPath $HdcPath -DryRun:$DryRun
        $endPoint = Get-HarmonyScenarioPoint -Step $step -XName 'endX' -YName 'endY' `
          -XRatioName 'endXRatio' -YRatioName 'endYRatio' -Display ([ref]$scenarioDisplay) `
          -Target $resolvedTarget -HdcPath $HdcPath -DryRun:$DryRun
        $captureAtMs = @((Get-OptionalProperty $step 'captureAtMs' @()) | ForEach-Object { [int]$_ })
        $prefix = [string](Get-OptionalProperty $step 'prefix' ('gesture-{0:D2}' -f $index))
        $event = Invoke-HarmonyGestureCapture `
          -StartX $startPoint.x -StartY $startPoint.y `
          -EndX $endPoint.x -EndY $endPoint.y `
          -DurationMs ([int](Get-OptionalProperty $step 'durationMs' 300)) `
          -KeepMs ([int](Get-OptionalProperty $step 'keepMs' 0)) `
          -CaptureAtMs $captureAtMs -OutputDirectory $absoluteOutputDirectory `
          -Prefix $prefix -Target $resolvedTarget -HdcPath $HdcPath -DryRun:$DryRun
        $artifacts += @($event.artifacts | ForEach-Object {
          [pscustomobject]@{
            type = $_.type
            path = $_.path
            requestedAtMs = $_.requestedAtMs
            scenarioStep = $index
          }
        })
      }
    }

    $events += [pscustomobject]@{
      index = $index
      scheduledAtMs = if ($atMs -ge 0) { $atMs } else { $null }
      startedAtMs = [int]$timeline.ElapsedMilliseconds
      result = $event
    }
  }
  $timeline.Stop()

  return [pscustomobject]@{
    action = 'scenario'
    scenario = $scenarioPath
    target = $resolvedTarget
    outputDirectory = $absoluteOutputDirectory
    elapsedMs = [int]$timeline.ElapsedMilliseconds
    events = $events
    artifacts = $artifacts
    dryRun = [bool]$DryRun
  }
}

function Get-HarmonyPackage {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,

    [switch]$IncludeTests
  )

  $absoluteRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
  if (-not (Test-Path -LiteralPath $absoluteRoot -PathType Container)) {
    throw "Project root does not exist: ${absoluteRoot}"
  }

  $packages = @(Get-ChildItem -LiteralPath $absoluteRoot -Recurse -File -Filter '*.hap' |
    Where-Object {
      $_.FullName -match '[\\/]build[\\/]' -and
      ($IncludeTests -or $_.FullName -notmatch '[\\/]outputs[\\/]ohosTest[\\/]')
    } |
    Sort-Object LastWriteTime -Descending)
  return @($packages | ForEach-Object {
    $relativePath = $_.FullName.Substring($absoluteRoot.Length).TrimStart('\', '/')
    [pscustomobject]@{
      path = $_.FullName
      relativePath = $relativePath
      fileName = $_.Name
      signed = $_.Name -match '-signed\.hap$'
      testPackage = $_.FullName -match '[\\/]outputs[\\/]ohosTest[\\/]'
      recommended = $_.Name -match '-signed\.hap$' -and
        $_.FullName -notmatch '[\\/]outputs[\\/]ohosTest[\\/]'
      sizeBytes = [long]$_.Length
      modifiedAt = ([DateTimeOffset]$_.LastWriteTime).ToString('o')
    }
  })
}

function Get-HarmonyAgentHealth {
  [CmdletBinding()]
  param(
    [string]$ProjectRoot = '',

    [string]$HdcPath = 'hdc',

    [string]$DevEcoCliPath = 'devecocli'
  )

  $checks = @()
  $hdcAvailable = $false
  try {
    $hdcCommand = Get-Command $HdcPath -ErrorAction Stop
    $hdcAvailable = $true
    $checks += [pscustomobject]@{
      name = 'hdc'
      status = 'pass'
      detail = $hdcCommand.Source
    }
  } catch {
    $checks += [pscustomobject]@{
      name = 'hdc'
      status = 'fail'
      detail = $_.Exception.Message
    }
  }

  try {
    $devecoCommand = Get-Command $DevEcoCliPath -ErrorAction Stop
    $checks += [pscustomobject]@{
      name = 'devecocli'
      status = 'pass'
      detail = $devecoCommand.Source
    }
  } catch {
    $checks += [pscustomobject]@{
      name = 'devecocli'
      status = 'fail'
      detail = $_.Exception.Message
    }
  }

  $sdkHome = [Environment]::GetEnvironmentVariable('DEVECO_SDK_HOME')
  if ($sdkHome -and (Test-Path -LiteralPath $sdkHome -PathType Container)) {
    $checks += [pscustomobject]@{
      name = 'devecoSdkHome'
      status = 'pass'
      detail = [System.IO.Path]::GetFullPath($sdkHome)
    }
  } else {
    $checks += [pscustomobject]@{
      name = 'devecoSdkHome'
      status = 'fail'
      detail = if ($sdkHome) { "Directory not found: $sdkHome" } else { 'DEVECO_SDK_HOME is not set.' }
    }
  }

  if ($hdcAvailable) {
    try {
      $devices = @(Get-HarmonyDevice -HdcPath $HdcPath)
      $usableTargets = @($devices | Where-Object { $_.usable })
      $checks += [pscustomobject]@{
        name = 'targets'
        status = if ($usableTargets.Count -gt 0) { 'pass' } else { 'warning' }
        detail = if ($usableTargets.Count -gt 0) {
          @($usableTargets.target) -join ', '
        } else {
          'No connected usable target.'
        }
      }
    } catch {
      $checks += [pscustomobject]@{
        name = 'targets'
        status = 'fail'
        detail = $_.Exception.Message
      }
    }
  }

  if ($ProjectRoot.Length -gt 0) {
    $absoluteRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
    $profilePath = Join-Path $absoluteRoot 'build-profile.json5'
    $projectExists = Test-Path -LiteralPath $absoluteRoot -PathType Container
    $checks += [pscustomobject]@{
      name = 'project'
      status = if ($projectExists -and (Test-Path -LiteralPath $profilePath -PathType Leaf)) {
        'pass'
      } else {
        'fail'
      }
      detail = $absoluteRoot
    }
    if ($projectExists) {
      $packages = @(Get-HarmonyPackage -ProjectRoot $absoluteRoot)
      $checks += [pscustomobject]@{
        name = 'packages'
        status = if ($packages.Count -gt 0) { 'pass' } else { 'warning' }
        detail = if ($packages.Count -gt 0) {
          "$($packages.Count) HAP package(s); latest: $($packages[0].relativePath)"
        } else {
          'No non-test HAP package found.'
        }
      }
    }
  }

  return [pscustomobject]@{
    action = 'doctor'
    healthy = @($checks | Where-Object { $_.status -eq 'fail' }).Count -eq 0
    checks = $checks
  }
}

function Build-HarmonyProject {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,

    [string]$Product = 'default',

    [ValidateSet('debug', 'release')]
    [string]$BuildMode = 'debug',

    [string[]]$Modules = @(),

    [string]$DevEcoCliPath = 'devecocli',

    [switch]$DryRun
  )

  $absoluteRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
  if (-not $DryRun -and -not (Test-Path -LiteralPath $absoluteRoot -PathType Container)) {
    throw "Project root does not exist: ${absoluteRoot}"
  }
  $arguments = @('build', '--product', $Product, '--build-mode', $BuildMode)
  if ($Modules.Count -gt 0) {
    $arguments += '--modules'
    $arguments += $Modules
  }
  $command = Invoke-NativeCommand -FilePath $DevEcoCliPath -ArgumentList $arguments `
    -WorkingDirectory $absoluteRoot -DryRun:$DryRun
  return [pscustomobject]@{
    action = 'build'
    projectRoot = $absoluteRoot
    product = $Product
    buildMode = $BuildMode
    modules = $Modules
    command = $command
  }
}

function Install-HarmonyPackage {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$PackagePath,

    [string]$Target = '',

    [string]$HdcPath = 'hdc',

    [switch]$DryRun
  )

  $absolutePackage = [System.IO.Path]::GetFullPath($PackagePath)
  if (-not $DryRun -and -not (Test-Path -LiteralPath $absolutePackage -PathType Leaf)) {
    throw "Package does not exist: ${absolutePackage}"
  }
  $resolvedTarget = Get-HarmonyCommandTarget -Target $Target -HdcPath $HdcPath -DryRun:$DryRun
  $command = Invoke-HarmonyHdc -Target $resolvedTarget -HdcPath $HdcPath -DryRun:$DryRun `
    -CommandArguments @('install', '-r', $absolutePackage)
  return [pscustomobject]@{
    action = 'install'
    target = $resolvedTarget
    package = $absolutePackage
    command = $command
  }
}

function Start-HarmonyAbility {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$Bundle,

    [Parameter(Mandatory = $true)]
    [string]$Ability,

    [string]$Module = '',

    [string]$Target = '',

    [Nullable[int]]$WindowLeft,

    [Nullable[int]]$WindowTop,

    [Nullable[int]]$WindowWidth,

    [Nullable[int]]$WindowHeight,

    [string]$HdcPath = 'hdc',

    [switch]$DebugLaunch,

    [switch]$DryRun
  )

  $resolvedTarget = Get-HarmonyCommandTarget -Target $Target -HdcPath $HdcPath -DryRun:$DryRun
  $arguments = @('shell', 'aa', 'start', '-a', $Ability, '-b', $Bundle)
  if ($Module.Length -gt 0) {
    $arguments += @('-m', $Module)
  }
  if ($DebugLaunch) {
    $arguments += '-D'
  }
  if ($null -ne $WindowLeft) {
    $arguments += @('--wl', "$WindowLeft")
  }
  if ($null -ne $WindowTop) {
    $arguments += @('--wt', "$WindowTop")
  }
  if ($null -ne $WindowWidth) {
    $arguments += @('--ww', "$WindowWidth")
  }
  if ($null -ne $WindowHeight) {
    $arguments += @('--wh', "$WindowHeight")
  }
  $command = Invoke-HarmonyHdc -Target $resolvedTarget -HdcPath $HdcPath `
    -CommandArguments $arguments -DryRun:$DryRun
  return [pscustomobject]@{
    action = 'start'
    target = $resolvedTarget
    bundle = $Bundle
    ability = $Ability
    module = $Module
    debugLaunch = [bool]$DebugLaunch
    command = $command
  }
}

function Stop-HarmonyApp {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$Bundle,

    [string]$Target = '',

    [string]$HdcPath = 'hdc',

    [switch]$DryRun
  )

  $resolvedTarget = Get-HarmonyCommandTarget -Target $Target -HdcPath $HdcPath -DryRun:$DryRun
  $command = Invoke-HarmonyHdc -Target $resolvedTarget -HdcPath $HdcPath -DryRun:$DryRun `
    -CommandArguments @('shell', 'aa', 'force-stop', $Bundle)
  return [pscustomobject]@{
    action = 'stop'
    target = $resolvedTarget
    bundle = $Bundle
    command = $command
  }
}

function Read-HarmonyLog {
  [CmdletBinding()]
  param(
    [string]$Target = '',

    [string]$Bundle = '',

    [ValidateRange(1, 5000)]
    [int]$Tail = 200,

    [string]$Level = '',

    [string]$Keyword = '',

    [string]$From = '',

    [string]$To = '',

    [string]$HdcPath = 'hdc',

    [string]$DevEcoCliPath = 'devecocli',

    [switch]$DryRun
  )

  if ($Level.Length -gt 0 -and $Level -notin @('D', 'I', 'W', 'E', 'F')) {
    throw "-Level must be one of D, I, W, E or F."
  }

  $resolvedTarget = Get-HarmonyCommandTarget -Target $Target -HdcPath $HdcPath -DryRun:$DryRun
  $arguments = @('log', '--device', $resolvedTarget, '--tail', "$Tail")
  if ($Bundle.Length -gt 0) {
    $arguments += @('--bundle-name', $Bundle)
  }
  if ($Level.Length -gt 0) {
    $arguments += @('--level', $Level)
  }
  if ($Keyword.Length -gt 0) {
    $arguments += @('--keyword', $Keyword)
  }
  if ($From.Length -gt 0) {
    $arguments += @('--from', $From)
  }
  if ($To.Length -gt 0) {
    $arguments += @('--to', $To)
  }
  $command = Invoke-NativeCommand -FilePath $DevEcoCliPath -ArgumentList $arguments -DryRun:$DryRun
  $logLines = @($command.output | Where-Object {
    $_.Trim().Length -gt 0 -and $_ -notmatch 'Preparing log request'
  })
  return [pscustomobject]@{
    action = 'logs'
    target = $resolvedTarget
    bundle = $Bundle
    tail = $Tail
    level = $Level
    keyword = $Keyword
    from = $From
    to = $To
    lines = $logLines
    command = $command
  }
}

function Deploy-HarmonyApp {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,

    [Parameter(Mandatory = $true)]
    [string]$PackagePath,

    [Parameter(Mandatory = $true)]
    [string]$Bundle,

    [Parameter(Mandatory = $true)]
    [string]$Ability,

    [string]$Product = 'default',

    [ValidateSet('debug', 'release')]
    [string]$BuildMode = 'debug',

    [string]$Module = '',

    [string]$Target = '',

    [string]$HdcPath = 'hdc',

    [string]$DevEcoCliPath = 'devecocli',

    [switch]$DebugLaunch,

    [switch]$SkipBuild,

    [switch]$DryRun
  )

  $build = $null
  if (-not $SkipBuild) {
    $build = Build-HarmonyProject -ProjectRoot $ProjectRoot -Product $Product `
      -BuildMode $BuildMode -DevEcoCliPath $DevEcoCliPath -DryRun:$DryRun
  }
  $install = Install-HarmonyPackage -PackagePath $PackagePath -Target $Target `
    -HdcPath $HdcPath -DryRun:$DryRun
  $start = Start-HarmonyAbility -Bundle $Bundle -Ability $Ability -Module $Module `
    -Target $install.target -HdcPath $HdcPath -DebugLaunch:$DebugLaunch -DryRun:$DryRun
  return [pscustomobject]@{
    action = 'deploy'
    build = $build
    install = $install
    start = $start
    dryRun = [bool]$DryRun
  }
}

Export-ModuleMember -Function @(
  'Get-HarmonyDevice',
  'Get-DevEcoEmulator',
  'Resolve-DevEcoEmulatorTarget',
  'Get-HarmonyDisplay',
  'ConvertFrom-HarmonyNormalizedPoint',
  'Get-HarmonyAgentHealth',
  'Get-HarmonyPackage',
  'Resolve-HarmonyTarget',
  'Send-HarmonyTap',
  'Send-HarmonySwipe',
  'Save-HarmonyScreenshot',
  'Invoke-HarmonyGestureCapture',
  'Invoke-HarmonyScenario',
  'Build-HarmonyProject',
  'Install-HarmonyPackage',
  'Start-HarmonyAbility',
  'Stop-HarmonyApp',
  'Read-HarmonyLog',
  'Deploy-HarmonyApp'
)
