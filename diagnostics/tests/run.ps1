[CmdletBinding()]
param(
    [string]$Runtime,
    [string]$ResultsDirectory
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $projectRoot 'scripts\Resolve-AhkTools.ps1')
$runtimePath = Resolve-AhkExecutable -Kind Runtime -ExplicitPath $Runtime
if (!$ResultsDirectory) {
    $runName = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $ResultsDirectory = Join-Path $PSScriptRoot ('.results\' + $runName)
}
$ResultsDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ResultsDirectory)
New-Item -ItemType Directory -Path $ResultsDirectory -Force | Out-Null

$testNames = @('DiagnosticInputTest', 'DiagnosticReportTest')
if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'DiagnosticControllerTest.ahk') -PathType Leaf) {
    $testNames += 'DiagnosticControllerTest'
} else {
    Write-Host 'SKIP DiagnosticControllerTest: this optional test is not present.'
}
$testNames += 'DiagnosticWireTest'
$validationTargets = @([pscustomobject]@{ Name = 'Main'; Path = (Join-Path $projectRoot 'Main.ahk') })
foreach ($testName in $testNames) {
    $testPath = Join-Path $PSScriptRoot ($testName + '.ahk')
    if (!(Test-Path -LiteralPath $testPath -PathType Leaf)) { throw "Required test is missing: $testName" }
    $validationTargets += [pscustomobject]@{ Name = $testName; Path = $testPath }
}

Write-Host 'Checking syntax first, then isolated tests. LiveRegistrationSmoke is not included.'
foreach ($target in $validationTargets) {
    $validation = Invoke-AhkProcess -Executable $runtimePath `
        -Arguments @('/ErrorStdOut=UTF-8', '/Validate', $target.Path) `
        -WorkingDirectory $projectRoot -LogPrefix (Join-Path $ResultsDirectory ('syntax-' + $target.Name))
    if ($validation.ExitCode -ne 0) {
        throw "$($target.Name) syntax validation failed ($($validation.ExitCode)). $($validation.Stderr)"
    }
    Write-Host "PASS $($target.Name): syntax only."
}

foreach ($testName in $testNames) {
    $testDirectory = Join-Path $ResultsDirectory $testName
    New-Item -ItemType Directory -Path $testDirectory -Force | Out-Null
    $test = Invoke-AhkProcess -Executable $runtimePath `
        -Arguments @('/ErrorStdOut=UTF-8', (Join-Path $PSScriptRoot ($testName + '.ahk')), $testDirectory) `
        -WorkingDirectory $projectRoot -LogPrefix (Join-Path $testDirectory 'process')
    $reportPath = Join-Path $testDirectory 'report.txt'
    if ($test.ExitCode -ne 0 -or !(Test-Path -LiteralPath $reportPath -PathType Leaf)) {
        $report = if (Test-Path -LiteralPath $reportPath) { Get-Content -LiteralPath $reportPath -Raw } else { 'No test report was produced.' }
        throw "$testName failed ($($test.ExitCode)).`n$report`n$($test.Stderr)`nLogs: $testDirectory"
    }
    Write-Host (Get-Content -LiteralPath $reportPath -Raw)
}
Write-Host "All isolated tests passed. Reports: $ResultsDirectory"
Write-Host 'No real input registration, shortcut transmission, driver operation or normal settings write was requested.'
