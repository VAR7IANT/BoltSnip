param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\licensed-cancel\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
$assembly = [Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($Executable))
$type = $assembly.GetType('BoltSnip.LicenseManager', $true)
$flags = [Reflection.BindingFlags]'Static,NonPublic'
$fields = @{}
foreach ($name in 'DirectoryPath', 'OwnerPath', 'CustomerPath', '_owner', '_authorized', '_canceled') {
    $field = $type.GetField($name, $flags)
    $fields[$name] = @{ Field = $field; Original = $field.GetValue($null) }
}
$root = Split-Path $PSScriptRoot -Parent
$testDirectory = Join-Path $root ('bin\license-cancel-test-' + [Guid]::NewGuid().ToString('N'))
$ownerPath = Join-Path $testDirectory 'owner.license'
$customerPath = Join-Path $testDirectory 'customer.key'

try {
    [IO.Directory]::CreateDirectory($testDirectory) | Out-Null
    [IO.File]::WriteAllText($ownerPath, 'owner-test')
    [IO.File]::WriteAllText($customerPath, 'customer-test')
    $fields['DirectoryPath'].Field.SetValue($null, $testDirectory)
    $fields['OwnerPath'].Field.SetValue($null, $ownerPath)
    $fields['CustomerPath'].Field.SetValue($null, $customerPath)
    $fields['_owner'].Field.SetValue($null, $true)
    $fields['_authorized'].Field.SetValue($null, 1)
    $fields['_canceled'].Field.SetValue($null, $false)

    $type.GetMethod('CancelAuthorization', $flags).Invoke($null, @())
    $isAuthorized = $type.GetProperty('IsAuthorized', $flags).GetValue($null, $null)
    $backups = @(Get-ChildItem -LiteralPath (Join-Path $testDirectory 'revoked') -Directory)
    if ($isAuthorized -or (Test-Path -LiteralPath $ownerPath) -or
        (Test-Path -LiteralPath $customerPath) -or $backups.Count -ne 1 -or
        [IO.File]::ReadAllText((Join-Path $backups[0].FullName 'owner.license')) -ne 'owner-test' -or
        [IO.File]::ReadAllText((Join-Path $backups[0].FullName 'customer.key')) -ne 'customer-test') {
        throw 'Local authorization cancellation did not revoke and back up both credentials.'
    }
    Write-Output 'Local authorization cancellation and backup: PASS'
}
finally {
    foreach ($name in $fields.Keys) {
        $fields[$name].Field.SetValue($null, $fields[$name].Original)
    }
    $resolvedRoot = [IO.Path]::GetFullPath((Join-Path $root 'bin'))
    $resolvedTest = [IO.Path]::GetFullPath($testDirectory)
    if (-not $resolvedTest.StartsWith($resolvedRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Test cleanup path left the project bin directory.'
    }
    if (Test-Path -LiteralPath $resolvedTest) {
        Remove-Item -LiteralPath $resolvedTest -Recurse -Force
    }
}
