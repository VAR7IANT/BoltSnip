param(
    [string]$ProjectRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$Executable = (Join-Path $ProjectRoot 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
$definition = Get-Content -Raw -Encoding UTF8 (Join-Path $ProjectRoot 'release.json') | ConvertFrom-Json
$assemblyInfo = Get-Content -Raw -Encoding UTF8 (Join-Path $ProjectRoot 'src\AssemblyInfo.cs')
$manifest = Get-Content -Raw -Encoding UTF8 (Join-Path $ProjectRoot 'app.manifest')
$installerScript = Get-Content -Raw -Encoding UTF8 (Join-Path $ProjectRoot 'installer\BoltSnip.iss')
$applicationBuild = Get-Content -Raw -Encoding UTF8 (Join-Path $ProjectRoot 'build.ps1')
$installerBuild = Get-Content -Raw -Encoding UTF8 (Join-Path $ProjectRoot 'build-installer.ps1')
$executable = $Executable
$assemblyVersion = ([Reflection.AssemblyName]::GetAssemblyName($executable)).Version.ToString()
$versionInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($executable)
$expectedAssemblyVersion = $definition.Version + '.0'

$singleVersionSource = $assemblyInfo -notmatch 'Assembly(File)?Version' -and
    $manifest -match '__ASSEMBLY_VERSION__' -and
    $installerScript -notmatch '#define AppVersion "' -and
    $installerBuild -notmatch '\[string\]\$Version'
$artifactMatches = $assemblyVersion -eq $expectedAssemblyVersion -and
    $versionInfo.FileVersion -eq $expectedAssemblyVersion -and
    $versionInfo.ProductName -eq $definition.ProductName -and
    $versionInfo.ProductVersion.StartsWith([string]$definition.Version, [StringComparison]::Ordinal)
$buildValidatesArtifact = $applicationBuild -match 'Built executable identity does not match release\.json'
$installerUsesIdentity = $installerBuild -match 'release\.json' -and
    $installerScript -match 'AppName=\{#ProductName\}' -and
    $installerScript -match 'OutputBaseFilename=\{#ProductName\}-Setup-\{#AppVersion\}-win-x64'
$perUserInstall = $installerScript -match 'DefaultDirName=\{localappdata\}\\Programs\\BoltSnip' -and
    $installerScript -match 'PrivilegesRequired=lowest'
$uninstallChecksRunningApp = $installerScript -match '(?m)^AppMutex=Local\\BoltSnip\.SingleInstance\r?$' -and
    (Get-Content -Raw -Encoding UTF8 (Join-Path $ProjectRoot 'src\Program.cs')).Contains('Local\\BoltSnip.SingleInstance')
$namedUninstallShortcuts = $installerScript.Contains('Name: "{app}\{cm:UninstallProgram,{#ProductName}}"; Filename: "{uninstallexe}"') -and
    $installerScript.Contains('Name: "{autoprograms}\{cm:UninstallProgram,{#ProductName}}"; Filename: "{uninstallexe}"')
$x64Only = $installerScript -match 'ArchitecturesAllowed=x64compatible'
$passed = $singleVersionSource -and $artifactMatches -and $buildValidatesArtifact -and
    $installerUsesIdentity -and $perUserInstall -and $uninstallChecksRunningApp -and
    $namedUninstallShortcuts -and $x64Only

[pscustomobject]@{
    SingleVersionSource = $singleVersionSource
    BuiltArtifactMatches = $artifactMatches
    BuildValidatesArtifact = $buildValidatesArtifact
    InstallerUsesReleaseIdentity = $installerUsesIdentity
    PerUserInstall = $perUserInstall
    UninstallChecksRunningApp = $uninstallChecksRunningApp
    NamedUninstallShortcuts = $namedUninstallShortcuts
    X64Installer = $x64Only
    Passed = $passed
} | Format-List

if (-not $passed) { exit 1 }
