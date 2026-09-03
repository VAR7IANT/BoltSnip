param(
    [string]$ProjectRoot = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = 'Stop'
$executable = Join-Path $ProjectRoot 'bin\BoltSnip.exe'
$definition = Get-Content -Raw -Encoding UTF8 (Join-Path $ProjectRoot 'release.json') | ConvertFrom-Json
$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $executable))
$identityType = $assembly.GetType('BoltSnip.ReleaseIdentity', $true)
$flags = [Reflection.BindingFlags]'Static,NonPublic'
$method = $identityType.GetMethod('IsSupportedVersion', $flags)
$minimum = [Version]$definition.MinimumSupportedVersion
$older = [Version]::new($minimum.Major, [Math]::Max(0, $minimum.Minor - 1), 0, 0)
if ($older -ge $minimum) {
    $older = [Version]::new([Math]::Max(0, $minimum.Major - 1), 0, 0, 0)
}

$oldRejected = -not [bool]$method.Invoke($null, @($older))
$minimumAccepted = [bool]$method.Invoke($null, @($minimum))
$programSource = Get-Content -Raw -Encoding UTF8 (Join-Path $ProjectRoot 'src\Program.cs')
$gateBeforeTray = $programSource.IndexOf('ReleaseIdentity.IsCurrentVersionSupported') -ge 0 -and
    $programSource.IndexOf('ReleaseIdentity.IsCurrentVersionSupported') -lt $programSource.IndexOf('Application.Run(new TrayApplicationContext())')
$messagePresent = $programSource -match 'MessageBox\.Show\(' -and
    $programSource -match 'ReleaseIdentity\.ProductName'
$passed = $oldRejected -and $minimumAccepted -and $gateBeforeTray -and $messagePresent

[pscustomobject]@{
    OldVersionRejected = $oldRejected
    MinimumVersionAccepted = $minimumAccepted
    GateRunsBeforeTray = $gateBeforeTray
    UserMessagePresent = $messagePresent
    Passed = $passed
} | Format-List

if (-not $passed) { exit 1 }
