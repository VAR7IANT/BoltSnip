param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\licensed-test\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$assembly = [Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($Executable))
$type = $assembly.GetType('BoltSnip.LicenseManager', $true)
$flags = [Reflection.BindingFlags]'Static,NonPublic'
$owner = $type.GetField('_owner', $flags)
$authorized = $type.GetField('_authorized', $flags)
$customerPath = $type.GetField('CustomerPath', $flags)
$info = $type.GetMethod('TryGetAuthorizationInfo', $flags)
$originalOwner = $owner.GetValue($null)
$originalAuthorized = $authorized.GetValue($null)
$originalPath = $customerPath.GetValue($null)
$testPath = Join-Path ([IO.Path]::GetTempPath()) ('boltsnip-license-info-' + [Guid]::NewGuid().ToString('N') + '.key')

try {
    $customerPath.SetValue($null, $testPath)
    [IO.File]::WriteAllText($testPath, 'BS-test-visible')

    $owner.SetValue($null, $true)
    $authorized.SetValue($null, 1)
    $values = @($null, $null)
    $result = $info.Invoke($null, $values)
    $ownerMethod = [string]$values[0]
    $ownerDetail = [string]$values[1]
    if (-not $result -or [string]::IsNullOrWhiteSpace($ownerMethod) -or
        -not $ownerDetail.EndsWith('owner.license')) {
        throw 'Owner authorization information was incorrect.'
    }

    $dialogType = $assembly.GetType('BoltSnip.ActivationDialog', $true)
    $dialog = [Windows.Forms.Form][Activator]::CreateInstance($dialogType, $true)
    try {
        $dialog.ShowInTaskbar = $false
        $dialog.StartPosition = [Windows.Forms.FormStartPosition]::Manual
        $dialog.Location = New-Object Drawing.Point(-2000, -2000)
        $dialog.Show()
        [Windows.Forms.Application]::DoEvents()
        $onlineTitle = $dialog.Controls | Where-Object { $_.GetType().Name -eq 'Label' -and $_.Location.Y -eq 140 } | Select-Object -First 1
        $change = $dialog.Controls | Where-Object { $_.GetType().Name -eq 'RoundedActionButton' -and $_.Location.Y -eq 355 } | Select-Object -First 1
        $revoke = $dialog.Controls | Where-Object { $_.GetType().Name -eq 'RoundedActionButton' -and $_.Location.X -eq 199 } | Select-Object -First 1
        if ($null -eq $onlineTitle -or $null -eq $change -or $null -eq $revoke -or
            $onlineTitle.Visible -or -not $change.Visible -or -not $revoke.Visible -or
            $dialog.ClientSize.Height -ne 420) {
            throw 'Authorized dialog did not show the summary view.'
        }
        $change.PerformClick()
        [Windows.Forms.Application]::DoEvents()
        if (-not $onlineTitle.Visible -or $change.Visible -or $revoke.Visible -or
            $dialog.ClientSize.Height -ne 510) {
            throw 'Change authorization did not show the activation methods.'
        }
    }
    finally { $dialog.Dispose() }

    $owner.SetValue($null, $false)
    $values = @($null, $null)
    if (-not $info.Invoke($null, $values) -or $values[0] -eq $ownerMethod -or
        $values[1] -ne 'BS-test-visible') {
        throw 'Customer authorization information was incorrect.'
    }

    $authorized.SetValue($null, 0)
    $values = @($null, $null)
    if ($info.Invoke($null, $values)) {
        throw 'Inactive authorization was displayed as valid.'
    }

    Write-Output 'Authorization information and dialog view switching: PASS'
}
finally {
    $owner.SetValue($null, $originalOwner)
    $authorized.SetValue($null, $originalAuthorized)
    $customerPath.SetValue($null, $originalPath)
    Remove-Item -LiteralPath $testPath -Force -ErrorAction SilentlyContinue
}
