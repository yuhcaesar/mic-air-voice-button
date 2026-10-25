[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path $PSScriptRoot 'dist\AirKey-Diagnostics.exe'),
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
$sourcePath = Join-Path $PSScriptRoot 'Main.ahk'
$iconPath = Join-Path $PSScriptRoot 'assets\app-icon.ico'
foreach ($relativePath in @('Main.ahk', 'assets\app-icon.ico', 'assets\interception.dll',
    'LICENSE', 'THIRD_PARTY_NOTICES.md', 'assets\AutoHotkey-license.txt', 'assets\LGPL-3.0.txt', 'assets\GPL-3.0.txt')) {
    if (!(Test-Path -LiteralPath (Join-Path $PSScriptRoot $relativePath) -PathType Leaf)) {
        throw "Required source or license file is missing: $relativePath"
    }
}
$runName = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
$logDirectory = Join-Path $PSScriptRoot ('.build\' + $runName)
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null

# /Validate does not run the GUI, register input listeners or send keys.
$validation = Invoke-AhkProcess -Executable $runtimePath `
    -Arguments @('/ErrorStdOut=UTF-8', '/Validate', $sourcePath) `
    -WorkingDirectory $PSScriptRoot -LogPrefix (Join-Path $logDirectory 'validate')
if ($validation.ExitCode -ne 0) {
    throw "Main.ahk validation failed ($($validation.ExitCode)). $($validation.Stderr) See $logDirectory"
}

$outputDirectory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
# A stale executable cannot masquerade as a successful build.
$temporaryOutput = Join-Path $outputDirectory ('.AirKey-Diagnostics-' + [Guid]::NewGuid().ToString('N') + '.exe')
$build = Invoke-AhkProcess -Executable $compilerPath `
    -Arguments @('/in', $sourcePath, '/out', $temporaryOutput, '/base', $runtimePath,
        '/icon', $iconPath, '/cp', '65001', '/compress', '0', '/silent', 'verbose') `
    -WorkingDirectory $PSScriptRoot -LogPrefix (Join-Path $logDirectory 'build')
if ($build.Stdout) { Write-Host $build.Stdout }
if ($build.Stderr) { Write-Host $build.Stderr }
if ($build.ExitCode -ne 0 -or !(Test-Path -LiteralPath $temporaryOutput -PathType Leaf)) {
    throw "Build failed ($($build.ExitCode)). Review $logDirectory"
}
if ((Get-Item -LiteralPath $temporaryOutput).Length -eq 0) {
    throw "Compiler produced an empty executable. Review $logDirectory"
}
Move-Item -LiteralPath $temporaryOutput -Destination $OutputPath -Force
$builtFile = Get-Item -LiteralPath $OutputPath
[pscustomobject]@{
    Path = $builtFile.FullName
    Bytes = $builtFile.Length
    SHA256 = (Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash
    BuildLogs = $logDirectory
}
Write-Host 'Build complete. The diagnostic executable was not launched. No input was registered, keys sent, or drivers changed.'
