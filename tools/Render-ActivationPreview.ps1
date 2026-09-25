param(
    [Parameter(Mandatory = $true)]
    [string]$Executable,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,
    [switch]$AuthorizedOwnerPreview,
    [switch]$AuthorizedCustomerPreview,
    [switch]$ShowChangeAuthorizationPreview,
    [switch]$CancellationConfirmationPreview
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$assembly = [Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($Executable))
$nativeType = $assembly.GetType('BoltSnip.NativeMethods', $true)
$nativeType.GetMethod('EnableBestDpiAwareness', [Reflection.BindingFlags]'Static,NonPublic').Invoke($null, @())
[Windows.Forms.Application]::EnableVisualStyles()
if ($AuthorizedOwnerPreview -and $AuthorizedCustomerPreview) {
    throw 'Choose only one authorization preview mode.'
}
if ($AuthorizedOwnerPreview) {
    $licenseType = $assembly.GetType('BoltSnip.LicenseManager', $true)
    $ownerField = $licenseType.GetField('_owner', [Reflection.BindingFlags]'Static,NonPublic')
    $ownerField.SetValue($null, $true)
}
$customerField = $null
$previewCustomerPath = $null
if ($AuthorizedCustomerPreview) {
    $licenseType = $assembly.GetType('BoltSnip.LicenseManager', $true)
    $flags = [Reflection.BindingFlags]'Static,NonPublic'
    $customerField = $licenseType.GetField('CustomerPath', $flags)
    $originalCustomerPath = $customerField.GetValue($null)
    $previewCustomerPath = [IO.Path]::Combine([IO.Path]::GetTempPath(),
        'boltsnip-preview-' + [Guid]::NewGuid().ToString('N') + '.key')
    [IO.File]::WriteAllText($previewCustomerPath, 'BS-EXAMPLE-1234')
    $customerField.SetValue($null, $previewCustomerPath)
    $licenseType.GetField('_authorized', $flags).SetValue($null, 1)
}
$dialogType = $assembly.GetType(
    $(if ($CancellationConfirmationPreview) { 'BoltSnip.AuthorizationCancellationDialog' } else { 'BoltSnip.ActivationDialog' }),
    $true)
$dialog = [Windows.Forms.Form][Activator]::CreateInstance($dialogType, $true)
$dialog.ShowInTaskbar = $false
$dialog.StartPosition = [Windows.Forms.FormStartPosition]::Manual
$dialog.Location = New-Object Drawing.Point(-2000, -2000)
$bitmap = $null
try {
    $dialog.Show()
    [Windows.Forms.Application]::DoEvents()
    if ($ShowChangeAuthorizationPreview) {
        if (-not $AuthorizedOwnerPreview) { throw 'Change authorization preview requires -AuthorizedOwnerPreview.' }
        $change = $dialog.Controls | Where-Object {
            $_.GetType().Name -eq 'RoundedActionButton' -and $_.Location.Y -eq 355
        } | Select-Object -First 1
        if ($null -eq $change) { throw 'Change authorization button was not found.' }
        $change.PerformClick()
        [Windows.Forms.Application]::DoEvents()
        $dialog.Refresh()
        [Windows.Forms.Application]::DoEvents()
    }
    $bitmap = New-Object Drawing.Bitmap($dialog.Width, $dialog.Height)
    $bounds = New-Object Drawing.Rectangle(0, 0, $bitmap.Width, $bitmap.Height)
    $dialog.DrawToBitmap($bitmap, $bounds)
    $destination = [IO.Path]::GetFullPath($OutputPath)
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
    $bitmap.Save($destination, [Drawing.Imaging.ImageFormat]::Png)
    Write-Output $destination
}
finally {
    if ($null -ne $bitmap) { $bitmap.Dispose() }
    $dialog.Close()
    $dialog.Dispose()
    if ($null -ne $customerField) { $customerField.SetValue($null, $originalCustomerPath) }
    if ($null -ne $previewCustomerPath) { Remove-Item -LiteralPath $previewCustomerPath -Force }
}
