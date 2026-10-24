param(
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\assets\app-icon.ico')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# Original geometric drawing, matching assets/app-icon.svg.
# No existing raster images or third-party graphic assets are read.
function New-RoundedRectanglePath {
    param([single]$X, [single]$Y, [single]$Width, [single]$Height, [single]$Radius)
    $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $diameter = [single](2 * $Radius)
    $path.AddArc($X, $Y, $diameter, $diameter, 180, 90)
    $path.AddArc(($X + $Width - $diameter), $Y, $diameter, $diameter, 270, 90)
    $path.AddArc(($X + $Width - $diameter), ($Y + $Height - $diameter), $diameter, $diameter, 0, 90)
    $path.AddArc($X, ($Y + $Height - $diameter), $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

$frames = [System.Collections.Generic.List[object]]::new()
foreach ($size in @(16, 32, 48, 256)) {
    $bitmap = [System.Drawing.Bitmap]::new($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $background = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 23, 46, 42))
    $foreground = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 248, 250, 249))
    $stroke = [System.Drawing.Pen]::new($foreground.Color, [single]14)
    $backgroundPath = New-RoundedRectanglePath 0 0 256 256 56
    $capsulePath = New-RoundedRectanglePath 94 44 68 116 34
    $framePath = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $png = [System.IO.MemoryStream]::new()
    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.ScaleTransform([single]($size / 256.0), [single]($size / 256.0))
        $stroke.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $stroke.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        $stroke.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
        $graphics.FillPath($background, $backgroundPath)
        $graphics.FillPath($foreground, $capsulePath)
        $framePath.AddLine([single]71, [single]126, [single]71, [single]137)
        $framePath.AddBezier([single]71, [single]137, [single]71, [single]168, [single]97, [single]193, [single]128, [single]193)
        $framePath.AddBezier([single]128, [single]193, [single]159, [single]193, [single]185, [single]168, [single]185, [single]137)
        $framePath.AddLine([single]185, [single]137, [single]185, [single]126)
        $graphics.DrawPath($stroke, $framePath)
        $graphics.DrawLine($stroke, [single]128, [single]193, [single]128, [single]216)
        $graphics.DrawLine($stroke, [single]101, [single]216, [single]155, [single]216)
        $bitmap.Save($png, [System.Drawing.Imaging.ImageFormat]::Png)
        $frames.Add([pscustomobject]@{ Size = $size; Bytes = $png.ToArray() })
    } finally {
        $png.Dispose()
        $framePath.Dispose()
        $capsulePath.Dispose()
        $backgroundPath.Dispose()
        $stroke.Dispose()
        $foreground.Dispose()
        $background.Dispose()
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

$resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
[System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($resolvedOutput)) | Out-Null
$stream = [System.IO.File]::Create($resolvedOutput)
$writer = [System.IO.BinaryWriter]::new($stream)
try {
    $writer.Write([uint16]0) # ICONDIR reserved
    $writer.Write([uint16]1) # ICO, not CUR
    $writer.Write([uint16]$frames.Count)
    $offset = [uint32](6 + 16 * $frames.Count)
    foreach ($frame in $frames) {
        $dimension = if ($frame.Size -eq 256) { [byte]0 } else { [byte]$frame.Size }
        $writer.Write($dimension)
        $writer.Write($dimension)
        $writer.Write([byte]0)
        $writer.Write([byte]0)
        $writer.Write([uint16]1)
        $writer.Write([uint16]32)
        $writer.Write([uint32]$frame.Bytes.Length)
        $writer.Write($offset)
        $offset += [uint32]$frame.Bytes.Length
    }
    foreach ($frame in $frames) { $writer.Write([byte[]]$frame.Bytes) }
} finally {
    $writer.Dispose()
}

Write-Output ("Created app-icon.ico: {0} bytes" -f (Get-Item -LiteralPath $resolvedOutput).Length)
Write-Output ("SHA256: {0}" -f (Get-FileHash -LiteralPath $resolvedOutput -Algorithm SHA256).Hash)
