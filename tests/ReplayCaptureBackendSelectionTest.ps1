param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$selectionType = $assembly.GetType('BoltSnip.ReplayCaptureBackendPolicy', $true)
$settingsType = $assembly.GetType('BoltSnip.ReplaySettings', $true)
$backendType = $assembly.GetType('BoltSnip.ReplayCaptureBackend', $true)
$flags = [Reflection.BindingFlags]'Static,NonPublic'
$fromEnvironment = @($selectionType.GetMethods($flags) | Where-Object {
    $_.Name -eq 'FromEnvironment' -and $_.GetParameters().Count -eq 1
})[0]
$fromEnvironmentWithProvider = @($selectionType.GetMethods($flags) | Where-Object {
    $_.Name -eq 'FromEnvironment' -and $_.GetParameters().Count -eq 2
})[0]
$candidateForScreenCount = $selectionType.GetMethod('CandidateForScreenCount', $flags)
$backendField = $settingsType.GetField('capture_backend', [Reflection.BindingFlags]'Instance,NonPublic')
if ($null -eq $fromEnvironment -or $null -eq $fromEnvironmentWithProvider -or
    $null -eq $candidateForScreenCount -or $null -eq $backendField) {
    throw 'Capture backend selection APIs were not found.'
}

$gdiBackend = [Enum]::Parse($backendType, 'GdiGrab')
$ddaBackend = [Enum]::Parse($backendType, 'DdaGrab')
$environmentVariable = 'BOLTSNIP_REPLAY_CAPTURE_BACKEND'
$oldValue = [Environment]::GetEnvironmentVariable($environmentVariable, 'Process')

function Invoke-Selection([string]$Value, [Func[int]]$ScreenCountProvider) {
    return $fromEnvironmentWithProvider.Invoke($null, [object[]]@($Value, $ScreenCountProvider))
}

try {
    $oneDisplay = [Func[int]] { return 1 }
    $twoDisplays = [Func[int]] { return 2 }
    $zeroDisplays = [Func[int]] { return 0 }
    $detectionThrows = [Func[int]] { throw [InvalidOperationException]::new('simulated display query failure') }

    $noOverrideOneDisplay = Invoke-Selection $null $oneDisplay
    $noOverrideTwoDisplays = Invoke-Selection $null $twoDisplays
    $noOverrideZeroDisplays = Invoke-Selection $null $zeroDisplays
    $detectionException = Invoke-Selection $null $detectionThrows
    $explicitGdiOneDisplay = Invoke-Selection 'gdigrab' $oneDisplay
    $explicitDdaTwoDisplays = Invoke-Selection 'ddagrab' $twoDisplays
    $unknownOverrideOneDisplay = Invoke-Selection 'unknown-value' $oneDisplay
    $unknownOverrideTwoDisplays = Invoke-Selection 'unknown-value' $twoDisplays
    $caseInsensitiveExplicitGdi = Invoke-Selection 'GdIgRaB' $twoDisplays
    $caseInsensitiveExplicitDda = Invoke-Selection 'DdAgRaB' $zeroDisplays

    $actualDisplayCount = 0
    try { $actualDisplayCount = [System.Windows.Forms.Screen]::AllScreens.Length } catch { $actualDisplayCount = 0 }
    $expectedActualBackend = $candidateForScreenCount.Invoke($null, [object[]]@($null, $actualDisplayCount))
    [Environment]::SetEnvironmentVariable($environmentVariable, $null, 'Process')
    $defaultSettings = [Activator]::CreateInstance($settingsType, $true)
    $defaultSettingsUseActualDisplayPolicy = $backendField.GetValue($defaultSettings) -eq $expectedActualBackend

    $passed =
        $noOverrideOneDisplay -eq $ddaBackend -and
        $noOverrideTwoDisplays -eq $gdiBackend -and
        $noOverrideZeroDisplays -eq $gdiBackend -and
        $detectionException -eq $gdiBackend -and
        $explicitGdiOneDisplay -eq $gdiBackend -and
        $explicitDdaTwoDisplays -eq $ddaBackend -and
        $unknownOverrideOneDisplay -eq $ddaBackend -and
        $unknownOverrideTwoDisplays -eq $gdiBackend -and
        $caseInsensitiveExplicitGdi -eq $gdiBackend -and
        $caseInsensitiveExplicitDda -eq $ddaBackend -and
        $defaultSettingsUseActualDisplayPolicy

    [pscustomobject]@{
        NoOverrideOneDisplayUsesDda = ($noOverrideOneDisplay -eq $ddaBackend)
        NoOverrideTwoDisplaysUsesGdi = ($noOverrideTwoDisplays -eq $gdiBackend)
        NoOverrideZeroDisplaysUsesGdi = ($noOverrideZeroDisplays -eq $gdiBackend)
        ScreenDetectionExceptionUsesGdi = ($detectionException -eq $gdiBackend)
        ExplicitGdiOneDisplayUsesGdi = ($explicitGdiOneDisplay -eq $gdiBackend)
        ExplicitDdaTwoDisplaysUsesDda = ($explicitDdaTwoDisplays -eq $ddaBackend)
        UnknownOverrideOneDisplayUsesAutoDda = ($unknownOverrideOneDisplay -eq $ddaBackend)
        UnknownOverrideTwoDisplaysUsesAutoGdi = ($unknownOverrideTwoDisplays -eq $gdiBackend)
        ExplicitValuesAreCaseInsensitive = ($caseInsensitiveExplicitGdi -eq $gdiBackend -and $caseInsensitiveExplicitDda -eq $ddaBackend)
        DefaultSettingsUseActualScreenCount = $defaultSettingsUseActualDisplayPolicy
        PhysicalScreenCountSeenByTest = $actualDisplayCount
        Passed = $passed
    } | Format-List

    if (-not $passed) { exit 1 }
}
finally {
    [Environment]::SetEnvironmentVariable($environmentVariable, $oldValue, 'Process')
}
