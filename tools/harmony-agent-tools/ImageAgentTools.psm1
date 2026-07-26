Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

if ($null -eq ('HarmonyAgentTools.ImageComparer' -as [type])) {
  Add-Type -ReferencedAssemblies @('System.Drawing', 'System') -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;

namespace HarmonyAgentTools
{
    public sealed class ImageComparisonResult
    {
        public int Width { get; set; }
        public int Height { get; set; }
        public long TotalPixels { get; set; }
        public long DifferentPixels { get; set; }
        public double DifferenceRatio { get; set; }
        public double MeanAbsoluteError { get; set; }
        public int MaxChannelDifference { get; set; }
    }

    public static class ImageComparer
    {
        private static Bitmap ToArgbBitmap(Image source)
        {
            Bitmap converted = new Bitmap(source.Width, source.Height, PixelFormat.Format32bppArgb);
            using (Graphics graphics = Graphics.FromImage(converted))
            {
                graphics.DrawImageUnscaled(source, 0, 0);
            }
            return converted;
        }

        private static byte[] ReadBytes(Bitmap bitmap, out BitmapData data)
        {
            Rectangle rectangle = new Rectangle(0, 0, bitmap.Width, bitmap.Height);
            data = bitmap.LockBits(rectangle, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            byte[] bytes = new byte[Math.Abs(data.Stride) * bitmap.Height];
            Marshal.Copy(data.Scan0, bytes, 0, bytes.Length);
            return bytes;
        }

        public static ImageComparisonResult Compare(
            string baselinePath,
            string actualPath,
            string differencePath,
            int pixelTolerance)
        {
            using (Image baselineSource = Image.FromFile(baselinePath))
            using (Image actualSource = Image.FromFile(actualPath))
            {
                if (baselineSource.Width != actualSource.Width ||
                    baselineSource.Height != actualSource.Height)
                {
                    throw new InvalidOperationException(String.Format(
                        "Image dimensions differ: baseline={0}x{1}, actual={2}x{3}.",
                        baselineSource.Width,
                        baselineSource.Height,
                        actualSource.Width,
                        actualSource.Height));
                }

                using (Bitmap baseline = ToArgbBitmap(baselineSource))
                using (Bitmap actual = ToArgbBitmap(actualSource))
                using (Bitmap difference = new Bitmap(
                    baseline.Width,
                    baseline.Height,
                    PixelFormat.Format32bppArgb))
                {
                    BitmapData baselineData;
                    BitmapData actualData;
                    byte[] baselineBytes = ReadBytes(baseline, out baselineData);
                    byte[] actualBytes = ReadBytes(actual, out actualData);
                    byte[] differenceBytes = new byte[baselineBytes.Length];
                    long differentPixels = 0;
                    long absoluteDifference = 0;
                    int maxChannelDifference = 0;

                    try
                    {
                        int stride = Math.Abs(baselineData.Stride);
                        for (int y = 0; y < baseline.Height; y++)
                        {
                            int row = y * stride;
                            for (int x = 0; x < baseline.Width; x++)
                            {
                                int offset = row + (x * 4);
                                int blue = Math.Abs(baselineBytes[offset] - actualBytes[offset]);
                                int green = Math.Abs(baselineBytes[offset + 1] - actualBytes[offset + 1]);
                                int red = Math.Abs(baselineBytes[offset + 2] - actualBytes[offset + 2]);
                                int pixelMaximum = Math.Max(blue, Math.Max(green, red));
                                absoluteDifference += blue + green + red;
                                maxChannelDifference = Math.Max(maxChannelDifference, pixelMaximum);

                                bool changed = pixelMaximum > pixelTolerance;
                                if (changed)
                                {
                                    differentPixels++;
                                    differenceBytes[offset] = 0;
                                    differenceBytes[offset + 1] = 0;
                                    differenceBytes[offset + 2] = (byte)Math.Max(64, pixelMaximum);
                                }
                                else
                                {
                                    byte context = (byte)(
                                        (actualBytes[offset] + actualBytes[offset + 1] +
                                         actualBytes[offset + 2]) / 15);
                                    differenceBytes[offset] = context;
                                    differenceBytes[offset + 1] = context;
                                    differenceBytes[offset + 2] = context;
                                }
                                differenceBytes[offset + 3] = 255;
                            }
                        }
                    }
                    finally
                    {
                        baseline.UnlockBits(baselineData);
                        actual.UnlockBits(actualData);
                    }

                    if (!String.IsNullOrEmpty(differencePath))
                    {
                        Rectangle rectangle = new Rectangle(0, 0, difference.Width, difference.Height);
                        BitmapData differenceData = difference.LockBits(
                            rectangle,
                            ImageLockMode.WriteOnly,
                            PixelFormat.Format32bppArgb);
                        try
                        {
                            Marshal.Copy(
                                differenceBytes,
                                0,
                                differenceData.Scan0,
                                differenceBytes.Length);
                        }
                        finally
                        {
                            difference.UnlockBits(differenceData);
                        }
                        string extension = Path.GetExtension(differencePath).ToLowerInvariant();
                        difference.Save(
                            differencePath,
                            extension == ".jpg" || extension == ".jpeg"
                                ? ImageFormat.Jpeg
                                : ImageFormat.Png);
                    }

                    long totalPixels = (long)baseline.Width * baseline.Height;
                    return new ImageComparisonResult
                    {
                        Width = baseline.Width,
                        Height = baseline.Height,
                        TotalPixels = totalPixels,
                        DifferentPixels = differentPixels,
                        DifferenceRatio = (double)differentPixels / totalPixels,
                        MeanAbsoluteError =
                            (double)absoluteDifference / (totalPixels * 3.0 * 255.0),
                        MaxChannelDifference = maxChannelDifference
                    };
                }
            }
        }
    }
}
'@
}

function Resolve-AgentImagePath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [switch]$MustExist
  )

  $absolutePath = [System.IO.Path]::GetFullPath($Path)
  $extension = [System.IO.Path]::GetExtension($absolutePath).ToLowerInvariant()
  if ($extension -notin @('.png', '.jpg', '.jpeg', '.bmp')) {
    throw "Unsupported image extension '${extension}'. Use PNG, JPEG or BMP."
  }
  if ($MustExist -and -not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) {
    throw "Image does not exist: ${absolutePath}"
  }
  return $absolutePath
}

function Get-AgentImageInfo {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$ImagePath
  )

  $absolutePath = Resolve-AgentImagePath -Path $ImagePath -MustExist
  $image = [System.Drawing.Image]::FromFile($absolutePath)
  try {
    return [pscustomobject]@{
      action = 'imageInfo'
      path = $absolutePath
      width = $image.Width
      height = $image.Height
      pixelFormat = $image.PixelFormat.ToString()
      format = $image.RawFormat.ToString()
      sizeBytes = (Get-Item -LiteralPath $absolutePath).Length
    }
  } finally {
    $image.Dispose()
  }
}

function Crop-AgentImage {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$ImagePath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [Parameter(Mandatory = $true)]
    [ValidateRange(0, 100000)]
    [int]$X,

    [Parameter(Mandatory = $true)]
    [ValidateRange(0, 100000)]
    [int]$Y,

    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 100000)]
    [int]$Width,

    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 100000)]
    [int]$Height
  )

  $absoluteInput = Resolve-AgentImagePath -Path $ImagePath -MustExist
  $absoluteOutput = Resolve-AgentImagePath -Path $OutputPath
  $source = [System.Drawing.Image]::FromFile($absoluteInput)
  try {
    if ($X + $Width -gt $source.Width -or $Y + $Height -gt $source.Height) {
      throw "Crop rectangle ${X},${Y},${Width},${Height} exceeds image size $($source.Width)x$($source.Height)."
    }
    $directory = Split-Path -Parent $absoluteOutput
    [void](New-Item -ItemType Directory -Path $directory -Force)
    $bitmap = New-Object System.Drawing.Bitmap($Width, $Height)
    try {
      $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
      try {
        $sourceRectangle = New-Object System.Drawing.Rectangle($X, $Y, $Width, $Height)
        $destinationRectangle = New-Object System.Drawing.Rectangle(0, 0, $Width, $Height)
        $graphics.DrawImage(
          $source,
          $destinationRectangle,
          $sourceRectangle,
          [System.Drawing.GraphicsUnit]::Pixel
        )
      } finally {
        $graphics.Dispose()
      }
      $extension = [System.IO.Path]::GetExtension($absoluteOutput).ToLowerInvariant()
      $format = if ($extension -in @('.jpg', '.jpeg')) {
        [System.Drawing.Imaging.ImageFormat]::Jpeg
      } elseif ($extension -eq '.bmp') {
        [System.Drawing.Imaging.ImageFormat]::Bmp
      } else {
        [System.Drawing.Imaging.ImageFormat]::Png
      }
      $bitmap.Save($absoluteOutput, $format)
    } finally {
      $bitmap.Dispose()
    }
  } finally {
    $source.Dispose()
  }

  return [pscustomobject]@{
    action = 'cropImage'
    source = $absoluteInput
    path = $absoluteOutput
    rectangle = [pscustomobject]@{ x = $X; y = $Y; width = $Width; height = $Height }
  }
}

function Compare-AgentImage {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$BaselinePath,

    [Parameter(Mandatory = $true)]
    [string]$ActualPath,

    [string]$DifferencePath = '',

    [ValidateRange(0, 255)]
    [int]$PixelTolerance = 0,

    [ValidateRange(0.0, 1.0)]
    [double]$MaxDifferenceRatio = 0.0,

    [ValidateRange(0.0, 1.0)]
    [double]$MaxMeanError = 0.0
  )

  $absoluteBaseline = Resolve-AgentImagePath -Path $BaselinePath -MustExist
  $absoluteActual = Resolve-AgentImagePath -Path $ActualPath -MustExist
  $absoluteDifference = ''
  if ($DifferencePath.Length -gt 0) {
    $absoluteDifference = Resolve-AgentImagePath -Path $DifferencePath
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $absoluteDifference) -Force)
  }
  $metrics = [HarmonyAgentTools.ImageComparer]::Compare(
    $absoluteBaseline,
    $absoluteActual,
    $absoluteDifference,
    $PixelTolerance
  )
  $passed = $metrics.DifferenceRatio -le $MaxDifferenceRatio -and
    $metrics.MeanAbsoluteError -le $MaxMeanError
  return [pscustomobject]@{
    action = 'compareImages'
    passed = $passed
    baseline = $absoluteBaseline
    actual = $absoluteActual
    difference = if ($absoluteDifference.Length -gt 0) { $absoluteDifference } else { $null }
    thresholds = [pscustomobject]@{
      pixelTolerance = $PixelTolerance
      maxDifferenceRatio = $MaxDifferenceRatio
      maxMeanError = $MaxMeanError
    }
    metrics = [pscustomobject]@{
      width = $metrics.Width
      height = $metrics.Height
      totalPixels = $metrics.TotalPixels
      differentPixels = $metrics.DifferentPixels
      differenceRatio = $metrics.DifferenceRatio
      meanAbsoluteError = $metrics.MeanAbsoluteError
      maxChannelDifference = $metrics.MaxChannelDifference
    }
  }
}

function Assert-AgentImage {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$BaselinePath,

    [Parameter(Mandatory = $true)]
    [string]$ActualPath,

    [string]$DifferencePath = '',

    [ValidateRange(0, 255)]
    [int]$PixelTolerance = 0,

    [ValidateRange(0.0, 1.0)]
    [double]$MaxDifferenceRatio = 0.0,

    [ValidateRange(0.0, 1.0)]
    [double]$MaxMeanError = 0.0
  )

  $comparison = Compare-AgentImage @PSBoundParameters
  if (-not $comparison.passed) {
    throw (
      'Image assertion failed: differenceRatio={0:P4} (max {1:P4}), ' +
      'meanAbsoluteError={2:P4} (max {3:P4}), diff={4}' -f
      $comparison.metrics.differenceRatio,
      $comparison.thresholds.maxDifferenceRatio,
      $comparison.metrics.meanAbsoluteError,
      $comparison.thresholds.maxMeanError,
      $comparison.difference
    )
  }
  $comparison.action = 'assertImage'
  return $comparison
}

Export-ModuleMember -Function @(
  'Get-AgentImageInfo',
  'Crop-AgentImage',
  'Compare-AgentImage',
  'Assert-AgentImage'
)
