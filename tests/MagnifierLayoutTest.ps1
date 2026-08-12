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
    $overlay.ClientSize = [Drawing.Size]::new(800, 600)
    $flags = [Reflection.BindingFlags]'Instance,NonPublic'
    $staticFlags = [Reflection.BindingFlags]'Static,NonPublic'
    $getBounds = $overlayType.GetMethod('GetMagnifierBounds', $flags)
    $getSample = $overlayType.GetMethod('GetMagnifierSampleRectangle', $staticFlags)

    $middlePoint = [Drawing.Point]::new(100, 100)
    $edgePoint = [Drawing.Point]::new(795, 595)
    $middleBounds = $getBounds.Invoke($overlay, @($middlePoint))
    $edgeBounds = $getBounds.Invoke($overlay, @($edgePoint))
    $sample = $getSample.Invoke($null, @($middlePoint))

    $middleAvoidsCursor = $middleBounds.Left -gt $middlePoint.X -and $middleBounds.Top -gt $middlePoint.Y
    $edgeFlips = $edgeBounds.Right -le $overlay.ClientSize.Width -and
        $edgeBounds.Bottom -le $overlay.ClientSize.Height -and
        $edgeBounds.Left -lt $edgePoint.X -and $edgeBounds.Top -lt $edgePoint.Y
    $sampleCentered = $sample.Width -eq 13 -and $sample.Height -eq 7 -and
        ($sample.Left + 6) -eq $middlePoint.X -and ($sample.Top + 3) -eq $middlePoint.Y
    $passed = $middleAvoidsCursor -and $edgeFlips -and $sampleCentered

    [pscustomobject]@{
        CursorAvoidance = $middleAvoidsCursor
        EdgeFlip = $edgeFlips
        ThirteenBySevenSample = $sampleCentered
        Passed = $passed
    } | Format-List

    if (-not $passed) {
        exit 1
    }
}
finally {
    $overlay.Dispose()
}
