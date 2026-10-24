[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path $PSScriptRoot 'dist\MicAirDoubao.exe'),
    [string]$Compiler,
    [string]$Runtime
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts\Resolve-AhkTools.ps1')
$compilerPath = Resolve-AhkExecutable -Kind Compiler -ExplicitPath $Compiler
$runtimePath = Resolve-AhkExecutable -Kind Runtime -ExplicitPath $Runtime
$OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
if ([IO.Path]::GetExtension($OutputPath) -ne '.exe') {
    throw 'OutputPath must end in .exe.'
}
$outputDirectory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$sourcePath = Join-Path $PSScriptRoot 'Main.ahk'
$iconPath = Join-Path $PSScriptRoot 'assets\app-icon.ico'
foreach ($required in @($sourcePath, $iconPath)) {
    if (!(Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required source asset is missing: $required" }
}

# Validate with the selected v2 x64 runtime without executing application startup.
$validation = Invoke-AhkProcess -Executable $runtimePath `
    -Arguments @('/ErrorStdOut=UTF-8', '/Validate', $sourcePath) `
    -WorkingDirectory $PSScriptRoot -LogPrefix (Join-Path $outputDirectory 'validate')
if ($validation.ExitCode -ne 0) {
    throw "AHK syntax/runtime validation failed ($($validation.ExitCode)). $($validation.Stderr)"
}

# Build a fresh file before replacing the requested destination. Failed builds
# cannot be mistaken for a successful build merely because an old EXE exists.
$temporaryOutput = Join-Path $outputDirectory ('.MicAirDoubao-' + [Guid]::NewGuid().ToString('N') + '.exe')
$build = Invoke-AhkProcess -Executable $compilerPath `
    -Arguments @('/in', $sourcePath, '/out', $temporaryOutput, '/base', $runtimePath,
        '/icon', $iconPath, '/cp', '65001', '/compress', '0', '/silent', 'verbose') `
    -WorkingDirectory $PSScriptRoot -LogPrefix (Join-Path $outputDirectory 'build')
if ($build.Stdout) { Write-Host $build.Stdout }
if ($build.Stderr) { Write-Host $build.Stderr }
if ($build.ExitCode -ne 0 -or !(Test-Path -LiteralPath $temporaryOutput -PathType Leaf)) {
    throw "Build failed ($($build.ExitCode)). Review $($build.StderrPath)."
}
if ((Get-Item -LiteralPath $temporaryOutput).Length -eq 0) { throw 'Compiler produced an empty executable.' }
Move-Item -LiteralPath $temporaryOutput -Destination $OutputPath -Force
$builtFile = Get-Item -LiteralPath $OutputPath
$builtHash = Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256
[pscustomobject]@{
    Path = $builtFile.FullName
    Bytes = $builtFile.Length
    SHA256 = $builtHash.Hash
}
Write-Host 'Build complete. The application was not launched; no driver was installed or removed.'
