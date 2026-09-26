param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'bin\BoltSnip.exe')
)

$ErrorActionPreference = 'Stop'
$assembly = [Reflection.Assembly]::LoadFile((Resolve-Path $Executable))
$selectionType = $assembly.GetType('BoltSnip.ReplayCaptureBackendPolicy', $true)
$settingsType = $assembly.GetType('BoltSnip.ReplaySettings', $true)
$backendType = $assembly.GetType('BoltSnip.ReplayCaptureBackend', $true)
$fromEnvironment = $selectionType.GetMethod('FromEnvironment', [Reflection.BindingFlags]'Static,NonPublic')
$candidateForScreenCount = $selectionType.GetMethod('CandidateForScreenCount', [Reflection.BindingFlags]'Static,NonPublic')
$backendField = $settingsType.GetField('capture_backend', [Reflection.BindingFlags]'Instance,NonPublic')
if ($null -eq $fromEnvironment -or $null -eq $candidateForScreenCount -or $null -eq $backendField) {
    throw 'Capture backend selection APIs were not found.'
}
$gdiBackend = [Enum]::Parse($backendType, 'GdiGrab')
$ddaBackend = [Enum]::Parse($backendType, 'DdaGrab')

$environmentVariable = 'BOLTSNIP_REPLAY_CAPTURE_BACKEND'
$oldValue = [Environment]::GetEnvironmentVariable($environmentVariable, 'Process')
try {
    $unsetDefaultsToGdi = $fromEnvironment.Invoke($null, @($null)) -eq $gdiBackend
    $validDdaValueSelectsDda = $fromEnvironment.Invoke($null, @('ddagrab')) -eq $ddaBackend -and
        $fromEnvironment.Invoke($null, @('DDAGRAB')) -eq $ddaBackend
    $unknownValueDefaultsToGdi = $fromEnvironment.Invoke($null, @('unknown')) -eq $gdiBackend
    $singleScreenCandidateUsesDda = $candidateForScreenCount.Invoke($null, @('unknown', 1)) -eq $ddaBackend
    $multipleScreenCandidateUsesGdi = $candidateForScreenCount.Invoke($null, @('unknown', 2)) -eq $gdiBackend
    $noScreenCandidateUsesGdi = $candidateForScreenCount.Invoke($null, @('unknown', 0)) -eq $gdiBackend
    $explicitGdiOverridesCandidate = $candidateForScreenCount.Invoke($null, @('gdigrab', 1)) -eq $gdiBackend
    $explicitDdaOverridesCandidate = $candidateForScreenCount.Invoke($null, @('ddagrab', 2)) -eq $ddaBackend

    [Environment]::SetEnvironmentVariable($environmentVariable, $null, 'Process')
    $defaultSettings = [Activator]::CreateInstance($settingsType, $true)
    $defaultSettingsUseGdi = $backendField.GetValue($defaultSettings) -eq $gdiBackend

    [Environment]::SetEnvironmentVariable($environmentVariable, 'ddagrab', 'Process')
    $experimentalSettings = [Activator]::CreateInstance($settingsType, $true)
    $environmentOptInSelectsDda = $backendField.GetValue($experimentalSettings) -eq $ddaBackend

    [pscustomobject]@{
        UnsetDefaultsToGdi = $unsetDefaultsToGdi
        DdagrabOptInIsCaseInsensitive = $validDdaValueSelectsDda
        UnknownValueDefaultsToGdi = $unknownValueDefaultsToGdi
        SingleScreenCandidateUsesDda = $singleScreenCandidateUsesDda
        MultipleScreenCandidateUsesGdi = $multipleScreenCandidateUsesGdi
        NoScreenCandidateUsesGdi = $noScreenCandidateUsesGdi
        ExplicitGdiOverridesCandidate = $explicitGdiOverridesCandidate
        ExplicitDdaOverridesCandidate = $explicitDdaOverridesCandidate
        DefaultSettingsUseGdi = $defaultSettingsUseGdi
        EnvironmentOptInSelectsDda = $environmentOptInSelectsDda
        Passed = $unsetDefaultsToGdi -and $validDdaValueSelectsDda -and $unknownValueDefaultsToGdi -and
            $singleScreenCandidateUsesDda -and $multipleScreenCandidateUsesGdi -and $noScreenCandidateUsesGdi -and
            $explicitGdiOverridesCandidate -and $explicitDdaOverridesCandidate -and $defaultSettingsUseGdi -and
            $environmentOptInSelectsDda
    } | Format-List

    if (-not ($unsetDefaultsToGdi -and $validDdaValueSelectsDda -and $unknownValueDefaultsToGdi -and
        $singleScreenCandidateUsesDda -and $multipleScreenCandidateUsesGdi -and $noScreenCandidateUsesGdi -and
        $explicitGdiOverridesCandidate -and $explicitDdaOverridesCandidate -and $defaultSettingsUseGdi -and
        $environmentOptInSelectsDda)) { exit 1 }
}
finally {
    [Environment]::SetEnvironmentVariable($environmentVariable, $oldValue, 'Process')
}
