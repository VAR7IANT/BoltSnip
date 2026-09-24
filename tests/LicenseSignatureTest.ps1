param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\licensed-test\BoltSnip.exe'),
    [Parameter(Mandatory = $true)]
    [string]$OwnerLicense
)

$ErrorActionPreference = 'Stop'
$assembly = [Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($Executable))
$type = $assembly.GetType('BoltSnip.LicenseManager', $true)
$flags = [Reflection.BindingFlags]'Static,NonPublic'
$method = $type.GetMethod('IsValidOwnerFile', $flags)
$valid = [IO.File]::ReadAllText($OwnerLicense)
$parts = $valid.Split('.')
$payload = [Text.Encoding]::UTF8.GetBytes('BoltSnip|customer|1')
$forged = $parts[0] + '.' + [Convert]::ToBase64String($payload) + '.' + $parts[2]

$accepted = [bool]$method.Invoke($null, @($valid))
$forgeryRejected = -not [bool]$method.Invoke($null, @($forged))
$garbageRejected = -not [bool]$method.Invoke($null, @('invalid'))
$deviceMethod = $type.GetMethod('GetDeviceId', $flags)
$deviceId = [string]$deviceMethod.Invoke($null, @())
$deviceIdValid = $deviceId -match '^[0-9a-f]{64}$'
if (-not ($accepted -and $forgeryRejected -and $garbageRejected -and $deviceIdValid)) {
    throw "License verification failed: accepted=$accepted forgedRejected=$forgeryRejected garbageRejected=$garbageRejected deviceIdValid=$deviceIdValid"
}
Write-Output 'Owner license verification, forgery rejection, and device ID: PASS'
