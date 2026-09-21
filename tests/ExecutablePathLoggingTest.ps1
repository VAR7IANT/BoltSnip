param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$identityType = $assembly.GetType('BoltSnip.ReleaseIdentity', $true)
$flags = [Reflection.BindingFlags]'Static,NonPublic'
$method = $identityType.GetMethod('CreateStartupDetails', $flags)
$expectedPath = [IO.Path]::GetFullPath($Executable)
$startedAt = [DateTime]::SpecifyKind([DateTime]'2026-09-03T01:02:03', [DateTimeKind]::Utc)
$details = $method.Invoke($null, @($expectedPath, 4242, $startedAt))

$pathRecorded = $details.Contains('Path=' + $expectedPath)
$pidRecorded = $details.Contains('PID=4242')
$timeRecorded = $details.Contains('StartedAtUtc=2026-09-03T01:02:03.0000000Z')
$passed = $pathRecorded -and $pidRecorded -and $timeRecorded

[pscustomobject]@{
    FullExecutablePathRecorded = $pathRecorded
    ProcessIdRecorded = $pidRecorded
    StartupTimeRecorded = $timeRecorded
    Passed = $passed
} | Format-List

if (-not $passed) { exit 1 }
