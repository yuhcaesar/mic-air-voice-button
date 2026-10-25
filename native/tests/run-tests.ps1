[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$NativeCompiler)

$ErrorActionPreference = 'Stop'
$compilerPath = (Resolve-Path -LiteralPath $NativeCompiler).ProviderPath
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$resultDirectory = Join-Path $projectRoot ('.build\volume-guard-tests-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $resultDirectory -Force | Out-Null
$testExecutable = Join-Path $resultDirectory 'volume-guard-test.exe'
& $compilerPath -Wall -Werror -o $testExecutable (Join-Path $PSScriptRoot 'volume-guard-test.c')
if ($LASTEXITCODE -ne 0) { throw 'Native guard mock test compilation failed.' }
# Every hook, message, window and property operation in the included C source
# is replaced by the test harness. This executable never installs a hook.
$reportPath = Join-Path $resultDirectory 'report.txt'
& $testExecutable | Tee-Object -FilePath $reportPath
if ($LASTEXITCODE -ne 0) { throw "Native guard mock tests failed. See $reportPath" }
Write-Output "Reports: $resultDirectory"
