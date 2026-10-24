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

Write-Host 'Checking syntax and running isolated tests. No driver changes, hotkeys, or real key sends.'
$validation = Invoke-AhkProcess -Executable $runtimePath `
    -Arguments @('/ErrorStdOut=UTF-8', '/Validate', (Join-Path $projectRoot 'Main.ahk')) `
    -WorkingDirectory $projectRoot -LogPrefix (Join-Path $ResultsDirectory 'syntax')
if ($validation.ExitCode -ne 0) {
    throw "Main.ahk syntax validation failed ($($validation.ExitCode)). $($validation.Stderr)"
}
Write-Host 'PASS Main.ahk and included modules: syntax only; application startup was not executed.'

foreach ($testName in @('LocalizationTest', 'ShortcutConfigTest', 'LifecycleTest', 'ModernControlsTest', 'AppArtworkTest', 'NativeOutputTest', 'TrayWindowTest', 'ButtonInputTest', 'SetupWizardTest', 'MachineProfileTest', 'MicSetupControllerTest')) {
    $testDirectory = Join-Path $ResultsDirectory $testName
    New-Item -ItemType Directory -Path $testDirectory -Force | Out-Null
    $test = Invoke-AhkProcess -Executable $runtimePath `
        -Arguments @('/ErrorStdOut=UTF-8', (Join-Path $PSScriptRoot ($testName + '.ahk')), $testDirectory) `
        -WorkingDirectory $projectRoot -LogPrefix (Join-Path $testDirectory 'process')
    $reportPath = Join-Path $testDirectory 'report.txt'
    if ($test.ExitCode -ne 0 -or !(Test-Path -LiteralPath $reportPath)) {
        $report = if (Test-Path -LiteralPath $reportPath) { Get-Content -LiteralPath $reportPath -Raw } else { 'No test report was produced.' }
        throw "$testName failed ($($test.ExitCode)).`n$report`n$($test.Stderr)`nLogs: $testDirectory"
    }
    Write-Host (Get-Content -LiteralPath $reportPath -Raw)
}

Write-Host "All test processes passed. Reports: $ResultsDirectory"
Write-Host 'Lifecycle cases may be marked SKIP if a physical modifier/key was held; inspect the report counts.'
