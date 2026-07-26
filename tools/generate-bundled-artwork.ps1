[CmdletBinding()]
param(
  [string]$MagickCommand = 'magick'
)

$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sourceDirectory = Join-Path $repositoryRoot 'assets\artwork'
$outputDirectory = Join-Path $repositoryRoot 'entry\src\main\resources\base\media'
$artworks = @('default', 'demo_city', 'demo_coast', 'demo_night')
$variants = @(
  @{ Name = 'small'; Edge = 256 },
  @{ Name = 'large'; Edge = 768 },
  @{ Name = 'full'; Edge = 2048 }
)

foreach ($artwork in $artworks) {
  $sourcePath = Join-Path $sourceDirectory "$artwork.svg"
  if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    throw "Missing bundled artwork source: $sourcePath"
  }
  foreach ($variant in $variants) {
    $outputPath = Join-Path $outputDirectory "bundled_artwork_${artwork}_$($variant.Name).png"
    & $MagickCommand $sourcePath `
      -resize "$($variant.Edge)x$($variant.Edge)" `
      -background '#000000' `
      -alpha remove `
      -alpha off `
      -strip `
      -define png:color-type=2 `
      $outputPath
    if ($LASTEXITCODE -ne 0) {
      throw "Unable to generate bundled artwork: $outputPath"
    }
  }
}

Write-Output "Generated $($artworks.Count * $variants.Count) bundled artwork variants."
