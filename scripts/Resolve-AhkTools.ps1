# Shared discovery for build.ps1 and tests/run.ps1. No downloads or installation.
Set-StrictMode -Version Latest

function Resolve-AhkExecutable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Runtime', 'Compiler')]
        [string]$Kind,
        [string]$ExplicitPath
    )

    if ($env:OS -ne 'Windows_NT') {
        throw 'This project requires Windows with AutoHotkey v2 x64.'
    }

    $variableName = if ($Kind -eq 'Runtime') { 'AHK_RUNTIME' } else { 'AHK_COMPILER' }
    $executableName = if ($Kind -eq 'Runtime') { 'AutoHotkey64.exe' } else { 'Ahk2Exe.exe' }
    $relativePath = if ($Kind -eq 'Runtime') { 'v2\AutoHotkey64.exe' } else { 'Compiler\Ahk2Exe.exe' }
    $configuredPath = [Environment]::GetEnvironmentVariable($variableName)
    if ($ExplicitPath) { $configuredPath = $ExplicitPath }
    if ($configuredPath) {
        if (!(Test-Path -LiteralPath $configuredPath -PathType Leaf)) {
            throw "$Kind executable was not found: $configuredPath. Correct -$Kind or $variableName."
        }
        return (Resolve-Path -LiteralPath $configuredPath).ProviderPath
    }

    $candidates = @()
    if ($env:AUTOHOTKEY_HOME) {
        $candidates += Join-Path $env:AUTOHOTKEY_HOME $relativePath
        $candidates += Join-Path $env:AUTOHOTKEY_HOME $executableName
    }
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($base) { $candidates += Join-Path $base ('AutoHotkey\' + $relativePath) }
    }
    if ($env:LOCALAPPDATA) {
        $candidates += Join-Path $env:LOCALAPPDATA ('Programs\AutoHotkey\' + $relativePath)
    }
    $command = Get-Command $executableName -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { $candidates += $command.Source }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).ProviderPath
        }
    }
    throw "$Kind not found. Install AutoHotkey v2 x64 and, for builds, the official Ahk2Exe compiler. Set -$Kind or $variableName to a custom executable path."
}

function Invoke-AhkProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string]$LogPrefix,
        [int]$TimeoutSeconds = 120
    )

    # These arguments are fixed switches and paths, not shell commands. A double
    # quote is not legal in Windows file names; reject it rather than interpreting it.
    $quotedArguments = foreach ($argument in $Arguments) {
        if ($argument.Contains('"') -or $argument.Contains("`r") -or $argument.Contains("`n")) {
            throw 'An executable argument contains an unsupported quote or line break.'
        }
        '"' + $argument + '"'
    }
    $stdoutPath = $LogPrefix + '.stdout.txt'
    $stderrPath = $LogPrefix + '.stderr.txt'
    $process = Start-Process -FilePath $Executable -ArgumentList $quotedArguments `
        -WorkingDirectory $WorkingDirectory -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    if (!$process.WaitForExit($TimeoutSeconds * 1000)) {
        # Stop only the exact helper started above; never unrelated AHK sessions.
        $process.Kill()
        $process.WaitForExit()
        throw "Process exceeded ${TimeoutSeconds}s. See $stderrPath"
    }
    # Flush redirected output before reading the process result.
    $process.WaitForExit()
    $process.Refresh()
    $stdout = if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath -Raw } else { '' }
    $stderr = if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath -Raw } else { '' }
    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Stdout = $stdout
        Stderr = $stderr
        StdoutPath = $stdoutPath
        StderrPath = $stderrPath
    }
}
