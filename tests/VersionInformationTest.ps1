param(
    [string]$ProjectRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$Executable = (Join-Path $ProjectRoot 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
$definition = Get-Content -Raw -Encoding UTF8 (Join-Path $ProjectRoot 'release.json') | ConvertFrom-Json
$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$identityType = $assembly.GetType('BoltSnip.ReleaseIdentity', $true)
$flags = [Reflection.BindingFlags]'Static,NonPublic'
$runtimeProduct = $identityType.GetProperty('ProductName', $flags).GetValue($null, $null)
$runtimeVersion = $identityType.GetProperty('Version', $flags).GetValue($null, $null)
$buildTime = $identityType.GetProperty('BuildTimeUtc', $flags).GetValue($null, $null)
$buildId = $identityType.GetProperty('BuildId', $flags).GetValue($null, $null)
$parsedBuildTime = [DateTime]::MinValue

$productMatches = $runtimeProduct -eq $definition.ProductName
$versionMatches = $runtimeVersion -eq $definition.Version
$buildTimeValid = [DateTime]::TryParse(
    $buildTime,
    [Globalization.CultureInfo]::InvariantCulture,
    [Globalization.DateTimeStyles]::RoundtripKind,
    [ref]$parsedBuildTime)
$buildIdPresent = -not [string]::IsNullOrWhiteSpace($buildId)
$passed = $productMatches -and $versionMatches -and $buildTimeValid -and $buildIdPresent

[pscustomobject]@{
    ProductNameMatches = $productMatches
    VersionMatches = $versionMatches
    BuildTimeValid = $buildTimeValid
    BuildIdPresent = $buildIdPresent
    BuildId = $buildId
    Passed = $passed
} | Format-List

if (-not $passed) { exit 1 }
