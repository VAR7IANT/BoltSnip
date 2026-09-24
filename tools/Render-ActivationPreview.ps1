param(
    [Parameter(Mandatory = $true)]
    [string]$Executable,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

$assembly = [Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($Executable))
$dialogType = $assembly.GetType('BoltSnip.ActivationDialog', $true)
$dialog = [Windows.Forms.Form][Activator]::CreateInstance($dialogType, $true)
$dialog.ShowInTaskbar = $false
$dialog.StartPosition = [Windows.Forms.FormStartPosition]::Manual
$dialog.Location = New-Object Drawing.Point(-2000, -2000)
$bitmap = $null
try {
    $dialog.Show()
    [Windows.Forms.Application]::DoEvents()
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
}
