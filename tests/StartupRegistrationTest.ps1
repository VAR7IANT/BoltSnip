param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'

$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$startupType = $assembly.GetType('BoltSnip.StartupRegistration', $true)
$flags = [Reflection.BindingFlags]'Static,NonPublic'
$buildCommand = $startupType.GetMethod('BuildCommand', $flags)

$pathWithSpaces = 'D:\Apps With Spaces\BoltSnip.exe'
$command = $buildCommand.Invoke($null, @($pathWithSpaces))
$quoted = $command -eq '"D:\Apps With Spaces\BoltSnip.exe" --startup'

$relativeRejected = $false
try {
    [void]$buildCommand.Invoke($null, @('BoltSnip.exe'))
}
catch {
    $relativeRejected = $_.Exception -is [ArgumentException] -or
        $_.Exception.InnerException -is [ArgumentException]
}

$passed = $quoted -and $relativeRejected
[pscustomobject]@{
    QuotedAbsolutePath = $quoted
    StartupArgumentIncluded = $command.EndsWith(' --startup')
    RelativePathRejected = $relativeRejected
    Passed = $passed
} | Format-List

if (-not $passed) {
    exit 1
}
