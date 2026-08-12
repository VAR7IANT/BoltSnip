param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$overlayType = $assembly.GetType('BoltSnip.CaptureOverlay', $true)
$overlay = [Activator]::CreateInstance($overlayType, $true)

try {
    $flags = [Reflection.BindingFlags]'Instance,NonPublic'
    $windowsField = $overlayType.GetField('_windowRectangles', $flags)
    $virtualScreenField = $overlayType.GetField('_virtualScreen', $flags)
    $findWindow = $overlayType.GetMethod('FindWindowAt', $flags)

    $listType = [Collections.Generic.List[Drawing.Rectangle]]
    $windows = [Activator]::CreateInstance($listType)
    $target = [Drawing.Rectangle]::new(100, 100, 200, 150)
    $windows.Add($target)
    $windowsField.SetValue($overlay, $windows)
    $virtualScreenField.SetValue($overlay, [Windows.Forms.SystemInformation]::VirtualScreen)

    $exact = $findWindow.Invoke($overlay, @([Drawing.Point]::new(150, 150)))
    $nearEdge = $findWindow.Invoke($overlay, @([Drawing.Point]::new(305, 150)))
    $outsideMagnet = $findWindow.Invoke($overlay, @([Drawing.Point]::new(312, 150)))

    $passed = $exact -eq $target -and $nearEdge -eq $target -and $outsideMagnet -ne $target
    [pscustomobject]@{
        ExactHit = $exact -eq $target
        FivePixelEdgeMagnet = $nearEdge -eq $target
        TwelvePixelsDoesNotMagnetize = $outsideMagnet -ne $target
        Passed = $passed
    }

    if (-not $passed) {
        exit 1
    }
}
finally {
    $overlay.Dispose()
}
