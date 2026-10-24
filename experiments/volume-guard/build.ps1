[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$NativeCompiler,
    [string]$Runtime,
    [string]$Compiler,
    [string]$OutputPath = (Join-Path $PSScriptRoot 'dist\AirKey-Volume-Check.exe')
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts\Resolve-AhkTools.ps1')
$runtimePath = Resolve-AhkExecutable -Kind Runtime -ExplicitPath $Runtime
$compilerPath = Resolve-AhkExecutable -Kind Compiler -ExplicitPath $Compiler
$nativePath = (Resolve-Path -LiteralPath $NativeCompiler).Path
$sourcePath = Join-Path $PSScriptRoot 'native\volume-guard.c'
$dllPath = Join-Path $PSScriptRoot 'native\volume-guard.dll'
& $nativePath -shared -Wall -Werror -DAIRKEY_NOCRT '-Wl,-nostdlib' -o $dllPath $sourcePath -luser32 -lkernel32
if ($LASTEXITCODE -ne 0) { throw 'Native DLL build failed.' }
$OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
$outputDirectory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$source = Join-Path $PSScriptRoot 'VolumeProbe.ahk'
$validation = Invoke-AhkProcess -Executable $runtimePath -Arguments @('/ErrorStdOut=UTF-8','/Validate',$source) -WorkingDirectory $PSScriptRoot -LogPrefix (Join-Path $outputDirectory 'validate')
if ($validation.ExitCode -ne 0) { throw $validation.Stderr }
$temporary = Join-Path $outputDirectory ('.probe-'+[Guid]::NewGuid().ToString('N')+'.exe')
$build = Invoke-AhkProcess -Executable $compilerPath -Arguments @('/in',$source,'/out',$temporary,'/base',$runtimePath,'/icon',(Join-Path $PSScriptRoot 'app-icon.ico'),'/cp','65001','/compress','0','/silent','verbose') -WorkingDirectory $PSScriptRoot -LogPrefix (Join-Path $outputDirectory 'build')
if ($build.ExitCode -ne 0 -or !(Test-Path -LiteralPath $temporary)) { throw ($build.Stdout+$build.Stderr) }
Move-Item -LiteralPath $temporary -Destination $OutputPath -Force
Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256
'Built only. No application or hook was started.'
