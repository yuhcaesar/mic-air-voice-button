[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$NativeCompiler,
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\assets\volume-guard.dll')
)

$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Build the guard with TinyCC for Windows x64.' }
$compilerPath = (Resolve-Path -LiteralPath $NativeCompiler).ProviderPath
$OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
$buildDirectory = Join-Path $PSScriptRoot ('..\.build\volume-guard-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $buildDirectory -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $OutputPath) -Force | Out-Null
$temporaryDll = Join-Path $buildDirectory 'volume-guard.dll'
$sourcePath = Join-Path $PSScriptRoot 'volume-guard.c'
# The DLL uses its own entry point and only Windows system APIs, with no CRT.
# TinyCC's generated .def stays in the ignored build directory.
& $compilerPath -shared -Wall -Werror -DAIRKEY_NOCRT '-Wl,-nostdlib' -o $temporaryDll $sourcePath -luser32 -lkernel32
if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $temporaryDll)) { throw 'Native volume guard build failed.' }
$bytes = [System.IO.File]::ReadAllBytes($temporaryDll)
if ($bytes.Length -lt 64) { throw 'The compiler did not produce a valid PE image.' }
$peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
if ($peOffset -lt 64 -or $peOffset + 26 -gt $bytes.Length -or
    [BitConverter]::ToUInt32($bytes, $peOffset) -ne 0x00004550 -or
    [BitConverter]::ToUInt16($bytes, $peOffset + 4) -ne 0x8664 -or
    [BitConverter]::ToUInt16($bytes, $peOffset + 24) -ne 0x20B) {
    throw 'Use the x64 Windows TinyCC compiler; the output must be a PE32+ x64 DLL.'
}
Move-Item -LiteralPath $temporaryDll -Destination $OutputPath -Force
Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256
Write-Output 'Built only. No hook, application, key input or audio operation was started.'
