param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$analyzerType = $assembly.GetType('BoltSnip.GuideColorAnalyzer', $true)
$instanceFlags = [Reflection.BindingFlags]'Instance,NonPublic'
$staticFlags = [Reflection.BindingFlags]'Static,NonPublic'
$tryUpdateAt = $analyzerType.GetMethod('TryUpdateAt', $instanceFlags)
$reset = $analyzerType.GetMethod('Reset', $instanceFlags)
$getSampleBounds = $analyzerType.GetMethod('GetSampleBounds', $staticFlags)
$cachedColorProperty = $analyzerType.GetProperty('CachedColor', $instanceFlags)
$sampleCountProperty = $analyzerType.GetProperty('SampleCount', $instanceFlags)

if ($null -eq $tryUpdateAt -or $null -eq $reset -or $null -eq $getSampleBounds -or
    $null -eq $cachedColorProperty -or $null -eq $sampleCountProperty) {
    throw 'GuideColorAnalyzer test seams were not found.'
}

$analyzer = [Activator]::CreateInstance($analyzerType, $true)
$white = [Drawing.Bitmap]::new(256, 256)
$black = [Drawing.Bitmap]::new(256, 256)
$image = [Drawing.Bitmap]::new(2000, 1200)
$whiteGraphics = [Drawing.Graphics]::FromImage($white)
$blackGraphics = [Drawing.Graphics]::FromImage($black)
$imageGraphics = [Drawing.Graphics]::FromImage($image)
try {
    $whiteGraphics.Clear([Drawing.Color]::White)
    $blackGraphics.Clear([Drawing.Color]::Black)
    $imageGraphics.Clear([Drawing.Color]::Black)
    $imageGraphics.FillRectangle([Drawing.Brushes]::White, 992, 592, 17, 17)

    $center = [Drawing.Point]::new(128, 128)
    [void]$tryUpdateAt.Invoke($analyzer, @($white, $center.PSObject.BaseObject, 0))
    $whiteBackgroundColor = $cachedColorProperty.GetValue($analyzer, $null)

    # A call inside the 150ms window must use the cached result without sampling black.
    [void]$tryUpdateAt.Invoke($analyzer, @($black, $center.PSObject.BaseObject, 100))
    $cachedInsideThrottleWindow = $cachedColorProperty.GetValue($analyzer, $null)
    $samplesInsideThrottleWindow = $sampleCountProperty.GetValue($analyzer, $null)

    [void]$tryUpdateAt.Invoke($analyzer, @($black, $center.PSObject.BaseObject, 150))
    $blackBackgroundColor = $cachedColorProperty.GetValue($analyzer, $null)

    [void]$reset.Invoke($analyzer, $null)
    $imagePoint = [Drawing.Point]::new(1000, 600)
    [void]$tryUpdateAt.Invoke($analyzer, @($image, $imagePoint.PSObject.BaseObject, 0))
    $localImageColor = $cachedColorProperty.GetValue($analyzer, $null)
    $sampleBounds = $getSampleBounds.Invoke($null, @($image.Size.PSObject.BaseObject, $imagePoint.PSObject.BaseObject))

    [void]$reset.Invoke($analyzer, $null)
    $watch = [Diagnostics.Stopwatch]::StartNew()
    for ($tick = 0; $tick -lt 1000; $tick++) {
        $point = [Drawing.Point]::new(100 + ($tick % 500), 100 + ($tick % 300))
        [void]$tryUpdateAt.Invoke($analyzer, @($image, $point.PSObject.BaseObject, $tick))
    }
    $watch.Stop()
    $samplesForThousandMoves = $sampleCountProperty.GetValue($analyzer, $null)

    $whiteUsesDarkGuide = $whiteBackgroundColor.GetBrightness() -lt $blackBackgroundColor.GetBrightness()
    $blackUsesLightGuide = $blackBackgroundColor.GetBrightness() -gt $whiteBackgroundColor.GetBrightness()
    $imageUsesLocalPatch = $localImageColor.ToArgb() -eq $whiteBackgroundColor.ToArgb()
    $throttleUsesCache = $cachedInsideThrottleWindow.ToArgb() -eq $whiteBackgroundColor.ToArgb() -and
        $samplesInsideThrottleWindow -eq 1
    $smallSampleOnly = $sampleBounds.Width -eq 17 -and $sampleBounds.Height -eq 17
    $samplingIsThrottled = $samplesForThousandMoves -eq 7
    $passed = $whiteUsesDarkGuide -and $blackUsesLightGuide -and $imageUsesLocalPatch -and
        $throttleUsesCache -and $smallSampleOnly -and $samplingIsThrottled

    [pscustomobject]@{
        WhiteWebsiteUsesDarkGuide = $whiteUsesDarkGuide
        BlackEditorUsesLightGuide = $blackUsesLightGuide
        ImageUsesMouseLocalPatch = $imageUsesLocalPatch
        SampleBounds = $sampleBounds.ToString()
        CachedInside150msWindow = $throttleUsesCache
        SamplesFor1000MouseMoves = $samplesForThousandMoves
        ThousandMoveAnalyzerTimeMs = $watch.ElapsedMilliseconds
        Passed = $passed
    } | Format-List

    if (-not $passed) {
        exit 1
    }
}
finally {
    $whiteGraphics.Dispose()
    $blackGraphics.Dispose()
    $imageGraphics.Dispose()
    $white.Dispose()
    $black.Dispose()
    $image.Dispose()
}
