param(
    [string]$ProjectRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$ExpectedVersion = '0.12.0'
)

$ErrorActionPreference = 'Stop'

$assemblyInfo = Get-Content -Raw -Encoding UTF8 (Join-Path $ProjectRoot 'src\AssemblyInfo.cs')
$manifest = Get-Content -Raw -Encoding UTF8 (Join-Path $ProjectRoot 'app.manifest')
$installerScript = Get-Content -Raw -Encoding UTF8 (Join-Path $ProjectRoot 'installer\BoltSnip.iss')
$buildScript = Get-Content -Raw -Encoding UTF8 (Join-Path $ProjectRoot 'build-installer.ps1')

$fourPartVersion = [Regex]::Escape($ExpectedVersion + '.0')
$assemblyMatches = $assemblyInfo -match ('AssemblyFileVersion\("' + $fourPartVersion + '"\)')
$manifestMatches = $manifest -match ('assemblyIdentity version="' + $fourPartVersion + '"')
$installerMatches = $installerScript -match ('#define AppVersion "' + [Regex]::Escape($ExpectedVersion) + '"')
$perUserInstall = $installerScript -match 'DefaultDirName=\{localappdata\}\\Programs\\BoltSnip' -and
    $installerScript -match 'PrivilegesRequired=lowest'
$x64Only = $installerScript -match 'ArchitecturesAllowed=x64compatible'
$outputNameMatches = $installerScript -match 'OutputBaseFilename=BoltSnip-Setup-\{#AppVersion\}-win-x64'
$buildUsesInno = $buildScript -match 'ISCC\.exe'
$passed = $assemblyMatches -and $manifestMatches -and $installerMatches -and
    $perUserInstall -and $x64Only -and $outputNameMatches -and $buildUsesInno

[pscustomobject]@{
    AssemblyVersionMatches = $assemblyMatches
    ManifestVersionMatches = $manifestMatches
    InstallerVersionMatches = $installerMatches
    PerUserInstall = $perUserInstall
    X64Installer = $x64Only
    ReleaseFileNameMatches = $outputNameMatches
    InnoBuildConfigured = $buildUsesInno
    Passed = $passed
} | Format-List

if (-not $passed) {
    exit 1
}
